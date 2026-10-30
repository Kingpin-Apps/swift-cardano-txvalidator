import Foundation
import SwiftCardanoCore

/// Validates the auxiliary data hash field in the transaction body.
///
/// Three checks:
/// 1. If `auxiliaryData` is present, `body.auxiliaryDataHash` must also be present.
/// 2. If `body.auxiliaryDataHash` is present but no `auxiliaryData` exists, that is an error.
/// 3. When both are present, the declared hash must match Blake2b-256 of the CBOR-encoded auxiliary data.
///
/// It also checks the metadata as the ledger's `validMetadatum` does from Allegra
/// on: no byte string or text longer than 64 bytes, at any depth (`InvalidMetadata`).
public struct AuxiliaryDataRule: ValidationRule {
    public let name = "auxiliaryData"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let issues = metadataIssues(transaction, era: context.era ?? .conway)
        let hasAuxData = transaction.auxiliaryData != nil
        let declaredHash = body.auxiliaryDataHash

        // Case 1: auxiliary data present but hash field is absent
        if hasAuxData && declaredHash == nil {
            return issues + [ValidationError(
                kind: .auxiliaryDataHashMissing,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Transaction contains auxiliary data but the auxiliary_data_hash field is absent.",
                hint: "Set auxiliary_data_hash to the Blake2b-256 hash of the CBOR-encoded auxiliary data."
            )]
        }

        // Case 2: hash field present but no auxiliary data
        if !hasAuxData && declaredHash != nil {
            return issues + [ValidationError(
                kind: .auxiliaryDataHashUnexpected,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Transaction declares an auxiliary_data_hash but contains no auxiliary data.",
                hint: "Remove the auxiliary_data_hash field or attach the corresponding auxiliary data."
            )]
        }

        // Case 3: both present — verify hash matches
        guard let auxData = transaction.auxiliaryData, let declared = declaredHash else {
            return issues  // neither present — nothing to check
        }

        do {
            let computed = try transaction.auxiliaryDataHash() ?? auxData.hash()
            let computedHex = "\(computed)"
            let declaredHex = "\(declared)"

            if computedHex != declaredHex {
                return issues + [ValidationError(
                    kind: .auxiliaryDataHashMismatch,
                    fieldPath: "transaction_body.auxiliary_data_hash",
                    message: "auxiliary_data_hash mismatch: declared=\(declaredHex), computed=\(computedHex).",
                    hint: "Recompute the auxiliary_data_hash as the Blake2b-256 hash of the CBOR-encoded auxiliary data."
                )]
            }
        } catch {
            return issues + [ValidationError(
                kind: .auxiliaryDataHashMismatch,
                fieldPath: "transaction_body.auxiliary_data_hash",
                message: "Could not compute auxiliary data hash: \(error.localizedDescription).",
                hint: "Verify the auxiliary data is well-formed.",
                isWarning: true
            )]
        }

        return issues
    }

    /// The most bytes a metadata byte string or text may hold.
    static let maxMetadatumBytes = 64

    /// One issue for each metadata byte string or text longer than the ledger allows.
    /// Shelley's first protocol version did not check, so its transactions are not.
    private func metadataIssues(_ transaction: Transaction, era: Era) -> [ValidationError] {
        guard era >= .allegra, let auxiliaryData = transaction.auxiliaryData else { return [] }
        let metadata: Metadata?
        switch auxiliaryData.data {
        case .metadata(let value): metadata = value
        case .shelleyMaryMetadata(let value): metadata = value.metadata
        case .alonzoMetadata(let value): metadata = value.metadata
        }
        guard let metadata else { return [] }

        var issues: [ValidationError] = []
        for (label, root) in metadata.data {
            var pending = [root]
            while let value = pending.popLast() {
                let size: Int?
                switch value {
                case .bytes(let data): size = data.count
                case .text(let text): size = text.utf8.count
                case .list(let elements): pending.append(contentsOf: elements.array); size = nil
                case .map(let pairs): pending.append(contentsOf: pairs.elements.flatMap { [$0.key, $0.value] }); size = nil
                case .int, .bigInt: size = nil
                }
                if let size, size > Self.maxMetadatumBytes {
                    issues.append(ValidationError(
                        kind: .invalidMetadata,
                        fieldPath: "auxiliary_data.metadata[\(label)]",
                        message: "Metadata under label \(label) holds a \(size)-byte string; the ledger allows "
                            + "at most \(Self.maxMetadatumBytes) (InvalidMetadata).",
                        hint: "Split long strings into a list of chunks of at most \(Self.maxMetadatumBytes) bytes."
                    ))
                }
            }
        }
        return issues
    }
}
