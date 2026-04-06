import Foundation
import SwiftCardanoCore

/// Validates the auxiliary data hash field in the transaction body.
///
/// Three checks:
/// 1. If `auxiliaryData` is present, `body.auxiliaryDataHash` must also be present.
/// 2. If `body.auxiliaryDataHash` is present but no `auxiliaryData` exists, that is an error.
/// 3. When both are present, the declared hash must match Blake2b-256 of the CBOR-encoded auxiliary data.
public struct AuxiliaryDataRule: ValidationRule {
    public let name = "auxiliaryData"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let hasAuxData = transaction.auxiliaryData != nil
        let declaredHash = body.auxiliaryDataHash

        // Case 1: auxiliary data present but hash field is absent
        if hasAuxData && declaredHash == nil {
            return [ValidationError(
                kind: .auxiliaryDataHashMissing,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Transaction contains auxiliary data but the auxiliary_data_hash field is absent.",
                hint: "Set auxiliary_data_hash to the Blake2b-256 hash of the CBOR-encoded auxiliary data."
            )]
        }

        // Case 2: hash field present but no auxiliary data
        if !hasAuxData && declaredHash != nil {
            return [ValidationError(
                kind: .auxiliaryDataHashUnexpected,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Transaction declares an auxiliary_data_hash but contains no auxiliary data.",
                hint: "Remove the auxiliary_data_hash field or attach the corresponding auxiliary data."
            )]
        }

        // Case 3: both present — verify hash matches
        guard let auxData = transaction.auxiliaryData, let declared = declaredHash else {
            return []  // neither present — nothing to check
        }

        do {
            let computed = try auxData.hash()
            let computedHex = "\(computed)"
            let declaredHex = "\(declared)"

            if computedHex != declaredHex {
                return [ValidationError(
                    kind: .auxiliaryDataHashMismatch,
                    fieldPath: "transaction_body.auxiliary_data_hash",
                    message: "auxiliary_data_hash mismatch: declared=\(declaredHex), computed=\(computedHex).",
                    hint: "Recompute the auxiliary_data_hash as the Blake2b-256 hash of the CBOR-encoded auxiliary data."
                )]
            }
        } catch {
            return [ValidationError(
                kind: .auxiliaryDataHashMismatch,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Could not compute auxiliary data hash: \(error.localizedDescription).",
                hint: "Verify the auxiliary data is well-formed.",
                isWarning: true
            )]
        }

        return []
    }
}
