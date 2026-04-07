import Foundation
import SwiftCardanoCore
import SwiftCardanoTxBuilder

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
            
            var version = -1
            let usesV1 = witnesses.plutusV1Script != nil
            let usesV2 = witnesses.plutusV2Script != nil
            let usesV3 = witnesses.plutusV3Script != nil
            
            var costModels: [Int: [Int]] = [:]
            if usesV1 {
                version = 1
                costModels[version - 1] = protocolParams.costModels.getVersion(version)
            }
            if usesV2 {
                version = 2
                costModels[version - 1] = protocolParams.costModels.getVersion(version)
            }
            if usesV3 {
                version = 3
                costModels[version - 1] = protocolParams.costModels.getVersion(version)
            }
            
            let datums: ListOrNonEmptyOrderedSet<Datum>?
            switch witnesses.plutusData {
                case .list(let list):
                    datums = .list(list.map( { .plutusData($0) }))
                case .indefiniteList(let list):
                    datums = .indefiniteList(
                        IndefiniteList(
                            list.map( { .plutusData($0) } )
                        )
                    )
                case .nonEmptyOrderedSet(let set):
                    datums =
                        .nonEmptyOrderedSet(
                            NonEmptyOrderedSet(
                                set.elementsOrdered.map( { .plutusData($0) })
                            )
                        )
                case nil:
                    datums = nil
            }
            
            let computedHashData = try SwiftCardanoTxBuilder.Utils.scriptDataHash(
                redeemers: witnesses.redeemers,
                datums: datums,
                costModels: CostModels(costModels)
            )
            
            let computedHashHex = computedHashData.payload.toHex
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
        }

        return []
    }
}
