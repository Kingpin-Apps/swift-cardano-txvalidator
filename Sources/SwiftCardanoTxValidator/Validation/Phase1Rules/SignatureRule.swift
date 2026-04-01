import Foundation
import SwiftCardanoCore
import SwiftNcal

/// Phase-1 signature and vkey witness checks.
///
/// Checks:
/// - Ed25519 signature verification — Blake2b-256 of the tx body CBOR, then verify
///   each `(vkey, signature)` pair. Emits `invalidSignature` on failure.
/// - Key-locked input / withdrawal vkey witness completeness — every key-payment-locked
///   spending input and every key-based withdrawal must have a vkey witness whose
///   Blake2b-224 hash matches the required key hash. Emits `missingRequiredSigner`.
/// - Extraneous vkey witnesses (warning) — vkey witnesses not required by any input,
///   cert, withdrawal, minting policy, or `requiredSigners`.
///
/// Reference: cquisitor-lib `witness.rs` — `InvalidSignature`, `MissingVKeyWitnesses`,
/// `ExtraneousVKeyWitnesses`
public struct SignatureRule: ValidationRule {
    public let name = "signature"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        let vkeyWitnesses = witnesses.vkeyWitnesses?.asList ?? []

        guard !vkeyWitnesses.isEmpty else {
            // No vkey witnesses at all — other rules (RequiredSignersRule, etc.) will
            // catch missing witnesses.  Nothing for us to verify here.
            return []
        }

        var issues: [ValidationError] = []

        // -----------------------------------------------------------------------
        // MARK: 1. Pre-compute witness key hashes
        // -----------------------------------------------------------------------
        // Map: blake2b-224(vkey) hex → index in vkeyWitnesses
        var witnessedKeyHashes: Set<String> = []
        var witnessKeyHashToIndex: [String: Int] = [:]
        for (i, vkw) in vkeyWitnesses.enumerated() {
            if let hashBytes = try? Hash().blake2b(
                data: vkw.vkey.payload,
                digestSize: 28,
                encoder: RawEncoder.self
            ) {
                let hex = hashBytes.toHex
                witnessedKeyHashes.insert(hex)
                witnessKeyHashToIndex[hex] = i
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 2. Ed25519 signature verification
        // -----------------------------------------------------------------------
        // tx body hash = Blake2b-256 of the CBOR-serialised transaction body
        let txBodyCBOR = body.payload
        let txBodyHash = try CBORUtils.blake2b256(txBodyCBOR)

        for (i, vkw) in vkeyWitnesses.enumerated() {
            let vkeyBytes = vkw.vkey.payload
            let sigBytes  = vkw.signature
            do {
                let verifyKey = try VerifyKey(key: vkeyBytes)
                // VerifyKey.verify expects the combined format: signature ‖ message.
                // We concatenate the 64-byte Ed25519 signature with the 32-byte tx body hash.
                let combined = sigBytes + txBodyHash
                _ = try verifyKey.verify(smessage: combined)
            } catch {
                issues.append(ValidationError(
                    kind: .invalidSignature,
                    fieldPath: "transaction_witness_set.vkeyWitnesses[\(i)]",
                    message: "Ed25519 signature verification failed for vkey "
                        + "\(vkeyBytes.toHex.prefix(16))…: \(error.localizedDescription)",
                    hint: "Ensure the transaction was signed with the correct private key "
                        + "and the transaction body has not been modified after signing."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 3. Collect all required key hashes
        // -----------------------------------------------------------------------
        // Build the full set of key hashes that MUST have a vkey witness.
        var requiredKeyHashes: Set<String> = []

        // 3a. Required signers from tx body
        if let requiredSigners = body.requiredSigners {
            for signer in requiredSigners.asList {
                requiredKeyHashes.insert(signer.payload.toHex)
            }
        }

        // 3b. Key-payment-locked spending inputs
        if !context.resolvedInputs.isEmpty {
            let resolvedMap: [String: TransactionOutput] = Dictionary(
                uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                    ("\(utxo.input.transactionId)#\(utxo.input.index)", utxo.output)
                }
            )
            for input in body.inputs.asArray {
                let key = "\(input.transactionId)#\(input.index)"
                guard let output = resolvedMap[key] else { continue }
                guard let paymentPart = output.address.paymentPart else { continue }
                if case .verificationKeyHash(let vkh) = paymentPart {
                    requiredKeyHashes.insert(vkh.payload.toHex)
                }
            }
        }

        // 3c. Withdrawal key hashes (reward accounts with key-based credentials)
        if let withdrawals = body.withdrawals {
            for (rewardAccount, _) in withdrawals.data {
                // RewardAccount = Data — first byte is header, remaining 28 bytes
                // are the credential hash. Header bits 4..7 = 0b1110 (noneKey) for
                // key-based, 0b1111 (noneScript) for script-based.
                guard rewardAccount.count == 29 else { continue }
                let header = rewardAccount[0]
                let credentialType = (header & 0x10) >> 4  // bit 4: 0 = key, 1 = script
                if credentialType == 0 {
                    let credentialHash = rewardAccount.dropFirst()
                    requiredKeyHashes.insert(credentialHash.toHex)
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 4. Missing vkey witnesses for key-locked inputs / withdrawals
        // -----------------------------------------------------------------------
        for requiredHash in requiredKeyHashes {
            if !witnessedKeyHashes.contains(requiredHash) {
                // Don't duplicate RequiredSignersRule reports for body.requiredSigners;
                // only report for input / withdrawal keys.
                let isExplicitRequiredSigner = body.requiredSigners?.asList.contains(where: {
                    $0.payload.toHex == requiredHash
                }) ?? false
                if !isExplicitRequiredSigner {
                    issues.append(ValidationError(
                        kind: .missingRequiredSigner,
                        fieldPath: "transaction_witness_set.vkeyWitnesses",
                        message: "Key hash \(requiredHash) is required by a spending input or "
                            + "withdrawal but has no corresponding vkey witness.",
                        hint: "Sign the transaction with the private key whose public key "
                            + "hashes to \(requiredHash)."
                    ))
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 5. Extraneous vkey witnesses (warning)
        // -----------------------------------------------------------------------
        // Collect script-pubkey hashes required by native scripts in the witness set.
        var nativeScriptKeyHashes: Set<String> = []
        for ns in witnesses.nativeScripts?.asList ?? [] {
            collectScriptPubkeyHashes(ns, into: &nativeScriptKeyHashes)
        }

        let allRequiredHashes = requiredKeyHashes.union(nativeScriptKeyHashes)

        for (witnessHash, idx) in witnessKeyHashToIndex {
            if !allRequiredHashes.contains(witnessHash) {
                issues.append(ValidationError(
                    kind: .extraneousSignature,
                    fieldPath: "transaction_witness_set.vkeyWitnesses[\(idx)]",
                    message: "Vkey witness with key hash \(witnessHash) is not required by any "
                        + "spending input, withdrawal, certificate, minting policy, or requiredSigners.",
                    hint: "Remove unreferenced vkey witnesses to reduce transaction size.",
                    isWarning: true
                ))
            }
        }

        return issues
    }
}

// MARK: - Helpers

/// Recursively collect all `scriptPubkey` key hashes from a native script tree.
private func collectScriptPubkeyHashes(_ script: NativeScript, into set: inout Set<String>) {
    switch script {
    case .scriptPubkey(let sp):
        set.insert(sp.keyHash.payload.toHex)
    case .scriptAll(let sa):
        for sub in sa.scripts { collectScriptPubkeyHashes(sub, into: &set) }
    case .scriptAny(let sa):
        for sub in sa.scripts { collectScriptPubkeyHashes(sub, into: &set) }
    case .scriptNofK(let snk):
        for sub in snk.scripts { collectScriptPubkeyHashes(sub, into: &set) }
    case .invalidBefore, .invalidHereAfter:
        break
    }
}
