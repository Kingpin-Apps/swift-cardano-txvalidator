import Foundation
import SwiftCardanoCore

/// Validates structural transaction-level size and composition limits.
///
/// Checks (all structural — no chain state required):
/// - Input set must be non-empty
/// - Serialised CBOR size must not exceed `maxTxSize`
/// - Total declared execution units must not exceed `maxTxExecutionUnits`
/// - A reference input must not also appear in the spending input set
/// - Spending inputs must be in canonical lexicographic order (warning)
///
/// Reference: cquisitor-lib — `InputSetEmptyUTxO`, `MaxTxSizeUTxO`,
/// `ExUnitsTooBigUTxO`, `ReferenceInputsNotSubsetOfInputs`, `BadInputsUTxO`
public struct TransactionLimitsRule: ValidationRule {
    public let name = "transactionLimits"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        var issues: [ValidationError] = []

        // 1. Input set must not be empty
        if body.inputs.count == 0 {
            issues.append(ValidationError(
                kind: .inputSetEmpty,
                fieldPath: "transaction_body.inputs",
                message: "Transaction has no spending inputs. At least one input is required.",
                hint: "Add at least one UTxO as a spending input."
            ))
        }

        // 2. Maximum transaction size
        if let txBytes = try? transaction.toCBORData() {
            if txBytes.count > protocolParams.maxTxSize {
                issues.append(ValidationError(
                    kind: .maximumTransactionSizeExceeded,
                    fieldPath: "transaction_body",
                    message: "Transaction serialises to \(txBytes.count) bytes, exceeding the "
                        + "maximum allowed \(protocolParams.maxTxSize) bytes.",
                    hint: "Reduce the transaction size by removing unnecessary witnesses, "
                        + "datums, or splitting into multiple transactions."
                ))
            }
        }

        // 3. Total declared execution units must not exceed maxTxExecutionUnits
        if let redeemers = witnesses.redeemers {
            var totalMem: Int = 0
            var totalSteps: Int64 = 0

            switch redeemers {
            case .list(let list):
                for r in list {
                    if let eu = r.exUnits {
                        totalMem  += eu.mem
                        totalSteps += Int64(eu.steps)
                    }
                }
            case .map(let map):
                for rv in map.dictionary.values {
                    totalMem  += rv.exUnits.mem
                    totalSteps += Int64(rv.exUnits.steps)
                }
            }

            let maxMem   = protocolParams.maxTxExecutionUnits.memory
            let maxSteps = protocolParams.maxTxExecutionUnits.steps

            if totalMem > maxMem || totalSteps > maxSteps {
                issues.append(ValidationError(
                    kind: .executionUnitsTooLarge,
                    fieldPath: "transaction_witness_set.redeemers",
                    message: "Total declared execution units "
                        + "(mem=\(totalMem), steps=\(totalSteps)) exceed the maximum "
                        + "(mem=\(maxMem), steps=\(maxSteps)).",
                    hint: "Reduce the execution units declared in one or more redeemers, "
                        + "or split the transaction."
                ))
            }
        }

        // 4. Reference inputs must not overlap with spending inputs
        if let refInputs = body.referenceInputs {
            let spendingKeys = Set(body.inputs.asArray.map { "\($0.transactionId)#\($0.index)" })
            for (i, refInput) in refInputs.asList.enumerated() {
                let key = "\(refInput.transactionId)#\(refInput.index)"
                if spendingKeys.contains(key) {
                    issues.append(ValidationError(
                        kind: .referenceInputOverlapsWithInput,
                        fieldPath: "transaction_body.reference_inputs[\(i)]",
                        message: "Reference input \(key) is also listed as a spending input.",
                        hint: "An input can appear in either the spending set or the reference set, not both."
                    ))
                }
            }
        }

        // 5. Bad inputs — spending inputs that are not in the resolved UTxO set
        if !context.resolvedInputs.isEmpty {
            let resolvedKeys = Set(context.resolvedInputs.map {
                "\($0.input.transactionId)#\($0.input.index)"
            })
            for (i, input) in body.inputs.asArray.enumerated() {
                let key = "\(input.transactionId)#\(input.index)"
                if !resolvedKeys.contains(key) {
                    issues.append(ValidationError(
                        kind: .badInput,
                        fieldPath: "transaction_body.inputs[\(i)]",
                        message: "Spending input \(key) does not exist in the UTxO set "
                            + "or has already been spent.",
                        hint: "Remove this input or provide the correct UTxO."
                    ))
                }
            }
        }

        // 6. Spending inputs must be in canonical lexicographic order (warning)
        let inputKeys = body.inputs.asArray.map { "\($0.transactionId)#\($0.index)" }
        if inputKeys != inputKeys.sorted() {
            issues.append(ValidationError(
                kind: .inputsNotSorted,
                fieldPath: "transaction_body.inputs",
                message: "Spending inputs are not in canonical lexicographic order (txId then index).",
                hint: "Sort the spending inputs lexicographically by transaction ID, then by output index.",
                isWarning: true
            ))
        }

        // 7. Reference scripts total size must not exceed maxReferenceScriptsSize (Conway+)
        //    Sum over all resolved UTxOs that carry an inline script.
        if let maxRefSize = protocolParams.maxReferenceScriptsSize {
            var totalRefScriptBytes = 0
            for utxo in context.resolvedInputs {
                if let inlineScript = utxo.output.script,
                   let scriptBytes = try? scriptData(of: inlineScript) {
                    totalRefScriptBytes += scriptBytes.count
                }
            }
            if totalRefScriptBytes > maxRefSize {
                issues.append(ValidationError(
                    kind: .maximumTransactionSizeExceeded,
                    fieldPath: "transaction_body.reference_inputs",
                    message: "Total inline reference script size \(totalRefScriptBytes) bytes "
                        + "exceeds the maximum allowed \(maxRefSize) bytes.",
                    hint: "Reduce the number or size of inline reference scripts referenced by this transaction."
                ))
            }
        }

        return issues
    }
}

// MARK: - Helpers

/// Return the raw bytes of a script type for size calculations.
private func scriptData(of script: ScriptType) throws -> Data {
    switch script {
    case .nativeScript(let ns):
        return try ns.toCBORData()
    case .plutusV1Script(let s):
        return s.data
    case .plutusV2Script(let s):
        return s.data
    case .plutusV3Script(let s):
        return s.data
    }
}
