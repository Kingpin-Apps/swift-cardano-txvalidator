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
/// The language views depend on `context.resolvedInputs`: a transaction that
/// uses a reference script carries no script in its witness set, so the Plutus
/// version it needs can only be read off the resolved UTxOs.
///
/// When a spending input cannot be resolved — which is the normal state of a
/// transaction whose inputs have already been spent — its script hash is
/// unknown, and a reference script that satisfies it cannot be matched to it.
/// The recomputed hash is then meaningless, so this rule does not report a
/// mismatch from it. It retries counting every Plutus reference script the
/// transaction carries, and if that agrees with the declared hash the
/// transaction passes; if it still disagrees the result is reported as a
/// warning, because the evidence does not support calling the hash wrong.
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
        // Utils.scriptDataHash performs the Blake2b-256 hash over the canonical
        // CBOR encoding of (redeemers || datums || languageViews).
        // If it throws (e.g. Blake2b not yet available), we fall back to a warning.
        do {
            
            let computedHashData = try Utils.scriptDataHash(
                witnessSet: witnesses,
                protocolParams: protocolParams,
                transaction: transaction,
                resolvedInputs: context.resolvedInputs
            )
            
            let computedHashHex = computedHashData.payload.toHex
            let declaredHashHex = "\(declaredHash!)"

            if computedHashHex == declaredHashHex { return [] }

            let unresolved = Utils.unresolvedSpendingInputs(
                transaction: transaction,
                resolvedInputs: context.resolvedInputs
            )

            // Everything the hash depends on was known, so a mismatch is real.
            guard !unresolved.isEmpty else {
                return [ValidationError(
                    kind: .scriptDataHashMismatch,
                    fieldPath: "transaction_body.script_data_hash",
                    message: "script_data_hash mismatch: declared=\(declaredHashHex), "
                        + "computed=\(computedHashHex).",
                    hint: "Recompute the script_data_hash using the canonical redeemers, datums, "
                        + "and cost model language views. Check that cost models match the protocol parameters."
                )]
            }

            // An unresolved spending input hides its script hash, so a reference
            // script satisfying it was skipped. Try again counting them all.
            let assumed = try? Utils.scriptDataHash(
                witnessSet: witnesses,
                protocolParams: protocolParams,
                transaction: transaction,
                resolvedInputs: context.resolvedInputs,
                assumingUnresolvedInputsUseReferenceScripts: true
            )
            if assumed?.payload.toHex == declaredHashHex { return [] }

            let names = unresolved
                .map { "\($0.transactionId)#\($0.index)" }
                .joined(separator: ", ")
            return [ValidationError(
                kind: .cannotCheckScriptDataHash,
                fieldPath: "transaction_body.script_data_hash",
                message: "script_data_hash could not be verified: \(unresolved.count) spending "
                    + "input(s) could not be resolved (\(names)), so the Plutus versions this "
                    + "transaction uses are unknown and the language views may be incomplete. "
                    + "declared=\(declaredHashHex), computed=\(computedHashHex).",
                hint: "Resolve the inputs against a chain context that still has them — a UTxO "
                    + "that has already been spent is not returned by every backend. The declared "
                    + "hash has not been shown to be wrong.",
                isWarning: true
            )]
        }

        return []
    }
}
