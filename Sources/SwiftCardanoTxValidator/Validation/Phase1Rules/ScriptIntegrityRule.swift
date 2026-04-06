import Foundation
import SwiftCardanoCore

/// Verifies that `transaction_body.script_data_hash` matches the expected hash
/// computed from the transaction's redeemers, datums, and cost-model language views.
///
/// The hash covers (concatenated in CBOR):
///   - Serialised redeemers map/list
///   - Serialised plutus datums set (CBOR tag 258)
///   - Serialised cost model language views (only versions used by required scripts)
///
/// If neither redeemers nor datums are present, the `script_data_hash` field must
/// also be absent.
public struct ScriptIntegrityRule: ValidationRule {
    public let name = "scriptIntegrity"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet

        let hasRedeemers = witnesses.redeemers != nil
        let hasDatums    = witnesses.plutusData != nil

        let declaredHash = body.scriptDataHash

        // If there is no script-related witness data, the hash must be absent
        if !hasRedeemers && !hasDatums {
            if declaredHash != nil {
                return [ValidationError(
                    kind: .scriptDataHashMismatch,
                    fieldPath: "transaction_body.script_data_hash",
                    message: "script_data_hash is set but the transaction has no redeemers or datums.",
                    hint: "Remove the script_data_hash field from the transaction body."
                )]
            }
            return []
        }

        // The hash must be present when there is script witness data
        guard declaredHash != nil else {
            return [ValidationError(
                kind: .scriptDataHashMismatch,
                fieldPath: "transaction_body.script_data_hash",
                message: "Transaction has redeemers or datums but script_data_hash is absent.",
                hint: "Compute and set the script_data_hash covering redeemers, datums, and cost model language views."
            )]
        }

        // Recompute the hash.
        // CBORUtils.scriptDataHash performs the Blake2b-256 hash over the canonical
        // CBOR encoding of (redeemers || datums || languageViews).
        // If it throws (e.g. Blake2b not yet available), we fall back to a warning.
        do {
            let computedHashData = try CBORUtils.scriptDataHash(
                witnessSet: witnesses,
                protocolParams: protocolParams
            )
            let computedHashHex = computedHashData.map { String(format: "%02x", $0) }.joined()
            let declaredHashHex = "\(declaredHash!)"

            if computedHashHex != declaredHashHex {
                return [ValidationError(
                    kind: .scriptDataHashMismatch,
                    fieldPath: "transaction_body.script_data_hash",
                    message: "script_data_hash mismatch: declared=\(declaredHashHex), "
                        + "computed=\(computedHashHex).",
                    hint: "Recompute the script_data_hash using the canonical redeemers, datums, "
                        + "and cost model language views. Check that cost models match the protocol parameters."
                )]
            }
        } catch TxValidatorError.notImplemented {
            // Hashing not yet available — skip comparison but note the limitation
            return [ValidationError(
                kind: .unknown,
                fieldPath: "transaction_body.script_data_hash",
                message: "script_data_hash could not be recomputed: Blake2b-256 hashing is not yet available.",
                hint: "Verify the hashing implementation in CBORUtils.blake2b256.",
                isWarning: true
            )]
        }

        return []
    }
}
