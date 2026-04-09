import Foundation
import SwiftCardanoCore
import SwiftNcal

/// Phase-1 signature and vkey witness checks.
///
/// Checks:
/// - Ed25519 signature verification — Blake2b-256 of the tx body CBOR, then verify
///   each `(vkey, signature)` pair. Emits `invalidSignature` on failure.
/// - Key-locked input vkey witness completeness — every key-payment-locked spending
///   input must have a vkey witness. Emits `missingVKeyWitness`.
/// - Key-locked collateral input vkey witness completeness — every key-payment-locked
///   collateral input must also have a vkey witness (Rust: `collect_collateral_witnesses`).
/// - Certificate vkey witness completeness — stake/pool/DRep/committee key-credential
///   certificates require a corresponding vkey witness (Rust: `collect_certificate_witnesses`).
/// - Voting procedure vkey witness completeness — CC-hot key, DRep key, and SPO voters
///   all require a vkey witness (Rust: `collect_vote_witnesses`).
/// - Withdrawal vkey witness completeness — every key-based withdrawal reward account
///   must have a vkey witness.
/// - Extraneous vkey witnesses (warning) — vkey witnesses not required by any input,
///   collateral, cert, withdrawal, vote, minting policy, or `requiredSigners`.
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
        let bootstrapWitnesses = witnesses.bootstrapWitness?.asList ?? []

        var issues: [ValidationError] = []

        // -----------------------------------------------------------------------
        // MARK: 1. Pre-compute vkey witness key hashes
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
        // MARK: 1b. Pre-compute bootstrap witness key hashes
        // -----------------------------------------------------------------------
        // Map: blake2b-224(publicKey) hex → index in bootstrapWitnesses
        var bootstrapKeyHashes: Set<String> = []
        var bootstrapKeyHashToIndex: [String: Int] = [:]
        for (i, bw) in bootstrapWitnesses.enumerated() {
            if let hashBytes = try? Hash().blake2b(
                data: bw.publicKey,
                digestSize: 28,
                encoder: RawEncoder.self
            ) {
                let hex = hashBytes.toHex
                bootstrapKeyHashes.insert(hex)
                bootstrapKeyHashToIndex[hex] = i
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 2. Ed25519 signature verification — vkey witnesses
        // -----------------------------------------------------------------------
        // tx body hash = Blake2b-256 of the CBOR-serialised transaction body
        let txBodyCBOR = body.payload
        let txBodyHash = try Utils.blake2b256(txBodyCBOR)

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
        // MARK: 2b. Ed25519 signature verification — bootstrap witnesses
        // -----------------------------------------------------------------------
        for (i, bw) in bootstrapWitnesses.enumerated() {
            do {
                let verifyKey = try VerifyKey(key: bw.publicKey)
                let combined = bw.signature + txBodyHash
                _ = try verifyKey.verify(smessage: combined)
            } catch {
                issues.append(ValidationError(
                    kind: .invalidSignature,
                    fieldPath: "transaction_witness_set.bootstrapWitness[\(i)]",
                    message: "Ed25519 signature verification failed for bootstrap witness "
                        + "\(bw.publicKey.toHex.prefix(16))…: \(error.localizedDescription)",
                    hint: "Ensure the transaction was signed with the correct Byron private key "
                        + "and the transaction body has not been modified after signing."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 3. Collect required key hashes and report missing witnesses
        // -----------------------------------------------------------------------
        // Build the full set of key hashes for extraneous check (MARK 5),
        // while reporting specific missing ones for each section.
        var allRequiredKeyHashes: Set<String> = []
        var byronInputIndices: [Int] = []

        // 3a. Required signers from tx body
        let explicitRequiredSigners: Set<String> = Set(body.requiredSigners?.asList.map { $0.payload.toHex } ?? [])
        allRequiredKeyHashes.formUnion(explicitRequiredSigners)

        // Build resolved UTxO map for input/collateral lookups.
        let resolvedMap: [String: TransactionOutput] = Dictionary(
            uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                ("\(utxo.input.transactionId)#\(utxo.input.index)", utxo.output)
            }
        )

        // 3b. Spending inputs — key-payment-locked (Shelley) and Byron-addressed
        for (i, input) in body.inputs.asArray.enumerated() {
            let key = "\(input.transactionId)#\(input.index)"
            guard let output = resolvedMap[key] else { continue }

            if output.address.addressType == .byron {
                // Byron-addressed inputs require a BootstrapWitness.
                byronInputIndices.append(i)
            } else if let paymentPart = output.address.paymentPart,
                      case .verificationKeyHash(let vkh) = paymentPart {
                let hashHex = vkh.payload.toHex
                allRequiredKeyHashes.insert(hashHex)
                if !witnessedKeyHashes.contains(hashHex) {
                    issues.append(ValidationError(
                        kind: .missingVKeyWitness,
                        fieldPath: "transaction_body.inputs[\(i)]",
                        message: "Key hash \(hashHex) is required by spending input at index \(i) "
                            + "but has no corresponding vkey witness.",
                        hint: "Sign the transaction with the private key whose public key "
                            + "hashes to \(hashHex)."
                    ))
                }
            }
        }

        // 3c. Collateral inputs — every key-locked collateral must also be witnessed.
        if let collateralInputs = body.collateral {
            for (i, input) in collateralInputs.asList.enumerated() {
                let key = "\(input.transactionId)#\(input.index)"
                guard let output = resolvedMap[key] else { continue }
                if let paymentPart = output.address.paymentPart,
                   case .verificationKeyHash(let vkh) = paymentPart {
                    let hashHex = vkh.payload.toHex
                    allRequiredKeyHashes.insert(hashHex)
                    if !witnessedKeyHashes.contains(hashHex) {
                        issues.append(ValidationError(
                            kind: .missingVKeyWitness,
                            fieldPath: "transaction_body.collateral[\(i)]",
                            message: "Key hash \(hashHex) is required by collateral input at index \(i) "
                                + "but has no corresponding vkey witness.",
                            hint: "Sign the transaction with the private key whose public key "
                                + "hashes to \(hashHex)."
                        ))
                    }
                }
            }
        }

        // 3d. Certificate key-credential witnesses.
        if let certs = body.certificates {
            for (i, cert) in certs.asList.enumerated() {
                var certKeyHashes = Set<String>()
                collectCertificateKeyHashes(cert, into: &certKeyHashes)
                for hashHex in certKeyHashes {
                    allRequiredKeyHashes.insert(hashHex)
                    if !witnessedKeyHashes.contains(hashHex) {
                        issues.append(ValidationError(
                            kind: .missingVKeyWitness,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "Key hash \(hashHex) is required by certificate at index \(i) "
                                + "(\(String(describing: cert))) but has no corresponding vkey witness.",
                            hint: "Sign the transaction with the private key whose public key "
                                + "hashes to \(hashHex)."
                        ))
                    }
                }
            }
        }

        // 3e. Voting procedure vkey witnesses — CC-hot key, DRep key, SPO.
        if let votingProcedures = body.votingProcedures {
            for (voter, _, _) in votingProcedures.allVotes {
                var voterKeyHash: String?
                switch voter.credential {
                case .constitutionalCommitteeHotKeyhash(let hash):
                    voterKeyHash = hash.payload.toHex
                case .drepKeyhash(let hash):
                    voterKeyHash = hash.payload.toHex
                case .stakePoolKeyhash(let hash):
                    voterKeyHash = hash.payload.toHex
                case .constitutionalCommitteeHotScriptHash, .drepScriptHash:
                    break
                }

                if let hashHex = voterKeyHash {
                    allRequiredKeyHashes.insert(hashHex)
                    if !witnessedKeyHashes.contains(hashHex) {
                        issues.append(ValidationError(
                            kind: .missingVKeyWitness,
                            fieldPath: "transaction_body.voting_procedures",
                            message: "Key hash \(hashHex) is required by voting procedure (voter: \(voter)) "
                                + "but has no corresponding vkey witness.",
                            hint: "Sign the transaction with the private key whose public key "
                                + "hashes to \(hashHex)."
                        ))
                    }
                }
            }
        }

        // 3f. Withdrawal key hashes (reward accounts with key-based credentials)
        if let withdrawals = body.withdrawals {
            for (rewardAccount, _) in withdrawals.data {
                guard rewardAccount.count == 29 else { continue }
                let header = rewardAccount[0]
                let credentialType = (header & 0x10) >> 4  // bit 4: 0 = key, 1 = script
                if credentialType == 0 {
                    let hashHex = rewardAccount.dropFirst().toHex
                    allRequiredKeyHashes.insert(hashHex)
                    if !witnessedKeyHashes.contains(hashHex) {
                        issues.append(ValidationError(
                            kind: .missingVKeyWitness,
                            fieldPath: "transaction_body.withdrawals",
                            message: "Key hash \(hashHex) is required by withdrawal for reward account \(rewardAccount.toHex) "
                                + "but has no corresponding vkey witness.",
                            hint: "Sign the transaction with the private key whose public key "
                                + "hashes to \(hashHex)."
                        ))
                    }
                }
            }
        }


        // -----------------------------------------------------------------------
        // MARK: 4b. Missing bootstrap witness for Byron inputs
        // -----------------------------------------------------------------------
        if !byronInputIndices.isEmpty && bootstrapWitnesses.isEmpty {
            issues.append(ValidationError(
                kind: .missingBootstrapWitness,
                fieldPath: "transaction_witness_set.bootstrapWitness",
                message: "Transaction spends \(byronInputIndices.count) Byron-addressed "
                    + "input(s) (at indices \(byronInputIndices)) but no bootstrap witnesses "
                    + "are present in the witness set.",
                hint: "Sign the transaction with the Byron key(s) corresponding to the "
                    + "spending inputs and include the bootstrap witnesses."
            ))
        }

        // -----------------------------------------------------------------------
        // MARK: 5. Extraneous vkey witnesses (warning)
        // -----------------------------------------------------------------------
        // Collect script-pubkey hashes required by native scripts in the witness set.
        var nativeScriptKeyHashes: Set<String> = []
        for ns in witnesses.nativeScripts?.asList ?? [] {
            collectScriptPubkeyHashes(ns, into: &nativeScriptKeyHashes)
        }

        let allRequiredHashes = allRequiredKeyHashes.union(nativeScriptKeyHashes)

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

        // -----------------------------------------------------------------------
        // MARK: 5b. Extraneous bootstrap witnesses (warning)
        // -----------------------------------------------------------------------
        if !bootstrapWitnesses.isEmpty && byronInputIndices.isEmpty {
            issues.append(ValidationError(
                kind: .extraneousSignature,
                fieldPath: "transaction_witness_set.bootstrapWitness",
                message: "Bootstrap witnesses are present but no spending inputs use Byron addresses.",
                hint: "Remove unreferenced bootstrap witnesses to reduce transaction size.",
                isWarning: true
            ))
        }

        return issues
    }
}

// MARK: - Helpers

/// Collects key-credential vkey witness requirements from a certificate.
///
/// Mirrors Rust `collect_certificate_witness` / `add_certificate_credential_witness`.
/// Only key-credential cases are collected here; script-credential cases are handled
/// by `WitnessRule` (script witness checks).
private func collectCertificateKeyHashes(_ cert: Certificate, into set: inout Set<String>) {
    /// Helper to extract a key hash hex from a `StakeCredential` if it is key-based.
    func keyHashHex(from cred: StakeCredential) -> String? {
        switch cred.credential {
        case .verificationKeyHash(let vkh): return vkh.payload.toHex
        case .scriptHash:                   return nil
        }
    }

    /// Helper to extract a key hash hex from a `DRepCredential` if it is key-based.
    func keyHashHex(from cred: DRepCredential) -> String? {
        switch cred.credential {
        case .verificationKeyHash(let vkh): return vkh.payload.toHex
        case .scriptHash:                   return nil
        }
    }

    /// Helper to extract a key hash hex from a `CommitteeColdCredential` if it is key-based.
    func keyHashHex(from cred: CommitteeColdCredential) -> String? {
        switch cred.credential {
        case .verificationKeyHash(let vkh): return vkh.payload.toHex
        case .scriptHash:                   return nil
        }
    }

    switch cert {
    // Stake credential certs — key-credential requires vkey witness
    case .stakeRegistration(let c):         if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .stakeDeregistration(let c):       if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .stakeDelegation(let c):           if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .register(let c):                  if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .unregister(let c):                if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .voteDelegate(let c):              if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .stakeVoteDelegate(let c):         if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .stakeRegisterDelegate(let c):     if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .voteRegisterDelegate(let c):      if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    case .stakeVoteRegisterDelegate(let c): if let h = keyHashHex(from: c.stakeCredential) { set.insert(h) }
    // Pool registration — operator + all owners
    case .poolRegistration(let c):
        set.insert(c.poolParams.poolOperator.payload.toHex)
            for owner in c.poolParams.poolOwners.asArray {
            set.insert(owner.payload.toHex)
        }
    // Pool retirement — pool keyhash
    case .poolRetirement(let c):
        set.insert(c.poolKeyHash.payload.toHex)
    // DRep certs — key-credential only
    case .registerDRep(let c):
        if let h = keyHashHex(from: c.drepCredential) { set.insert(h) }
    case .unRegisterDRep(let c):
        if let h = keyHashHex(from: c.drepCredential) { set.insert(h) }
    case .updateDRep(let c):
        if let h = keyHashHex(from: c.drepCredential) { set.insert(h) }
    // Committee certs — cold credential
    case .authCommitteeHot(let c):
        if let h = keyHashHex(from: c.committeeColdCredential) { set.insert(h) }
    case .resignCommitteeCold(let c):
        if let h = keyHashHex(from: c.committeeColdCredential) { set.insert(h) }
    default:
        break
    }
}

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
