import Foundation
import SwiftCardanoCore

/// Checks that every transaction output meets the minimum ADA requirement and
/// does not exceed the maximum serialised value size.
///
/// Conway / Babbage min-ADA formula:
/// ```
/// min_ada = utxoCostPerByte × (160 + serialised_output_size_bytes)
/// ```
///
/// Reference: cquisitor-lib `output.rs` — `OutputTooSmallUTxO`, `OutputsValueTooBig`
public struct OutputValueRule: ValidationRule {
    public let name = "outputValue"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        var issues: [ValidationError] = []

        for (i, output) in transaction.transactionBody.outputs.enumerated() {
            let path = "transaction_body.outputs[\(i)]"

            // Serialise the output to measure its size.
            guard let outputBytes = try? output.toCBORData() else {
                issues.append(ValidationError(
                    kind: .unknown,
                    fieldPath: path,
                    message: "Could not serialise output[\(i)] to compute minimum ADA requirement.",
                    isWarning: true
                ))
                continue
            }

            // Minimum ADA check
            let minAda = protocolParams.utxoCostPerByte * (160 + outputBytes.count)
            let lovelace = output.amount.coin  // Int

            if lovelace < minAda {
                issues.append(ValidationError(
                    kind: .outputTooSmall,
                    fieldPath: "\(path).amount",
                    message: "Output[\(i)] contains \(lovelace) lovelace which is below the "
                        + "minimum \(minAda) lovelace required for its size "
                        + "(\(outputBytes.count) bytes, utxoCostPerByte=\(protocolParams.utxoCostPerByte)).",
                    hint: "Increase the ADA amount in output[\(i)] to at least \(minAda) lovelace, "
                        + "or reduce the output size (fewer assets / smaller datum)."
                ))
            }

            // Maximum serialised value size check
            // The value field (amount) is checked separately per cquisitor-lib
            if let valueBytes = try? output.amount.toCBORData() {
                if valueBytes.count > protocolParams.maxValueSize {
                    issues.append(ValidationError(
                        kind: .outputValueTooBig,
                        fieldPath: "\(path).amount",
                        message: "Output[\(i)] value serialises to \(valueBytes.count) bytes, "
                            + "exceeding the maximum allowed \(protocolParams.maxValueSize) bytes.",
                        hint: "Split the output or reduce the number of distinct native assets."
                    ))
                }
            }
        }

        return issues
    }
}
