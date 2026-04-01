import Foundation
import SwiftCardanoCore
import SwiftNcal

/// Verifies that every key hash listed in `required_signers` has a corresponding
/// vkey witness whose Blake2b-224 hash matches that value.
///
/// Reference: cquisitor-lib `witness.rs` — `MissingVKeyWitnesses`
public struct RequiredSignersRule: ValidationRule {
    public let name = "requiredSigners"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body     = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet

        guard let requiredSigners = body.requiredSigners, requiredSigners.count > 0 else {
            return []
        }

        // Pre-compute the Blake2b-224 hashes of all vkey witnesses.
        // VerificationKeyWitness.vkey.payload is the raw 32-byte Ed25519 verification key;
        // its Blake2b-224 digest (28 bytes) must match the required signer hash.
        var witnessedHashes: Set<String> = []
        for vkw in witnesses.vkeyWitnesses?.asList ?? [] {
            let keyBytes = vkw.vkey.payload
            if let hashBytes = try? Hash().blake2b(
                data: keyBytes,
                digestSize: 28,
                encoder: RawEncoder.self
            ) {
                witnessedHashes.insert(hashBytes.toHex)
            }
        }

        // Required signer hashes are VerificationKeyHash (28-byte Blake2b-224).
        let requiredHashes = requiredSigners.asList

        var issues: [ValidationError] = []

        for (i, signerHash) in requiredHashes.enumerated() {
            let signerHex = signerHash.payload.toHex
            if !witnessedHashes.contains(signerHex) {
                issues.append(ValidationError(
                    kind: .missingRequiredSigner,
                    fieldPath: "transaction_body.required_signers[\(i)]",
                    message: "Required signer \(signerHex) has no corresponding "
                        + "vkey witness in the transaction witness set.",
                    hint: "Sign the transaction with the private key whose public key hashes to \(signerHex)."
                ))
            }
        }

        return issues
    }
}
