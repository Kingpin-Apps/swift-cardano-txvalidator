import Foundation
import SwiftCardanoCore

/// Validates collateral inputs whenever Plutus redeemers are present.
///
/// Checks:
/// - Collateral is present when scripts are being executed
/// - Collateral does not exceed `maxCollateralInputs`
/// - Total collateral ADA ≥ `fee × collateralPercentage / 100`
/// - Collateral inputs are not locked by scripts (must be key-payment credentials)
/// - Warns if collateral is declared but no redeemers are present
public struct CollateralRule: ValidationRule {
    public let name = "collateral"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        let hasRedeemers = witnesses.redeemers != nil

        let collateralInputs = body.collateral
        let collateralCount = collateralInputs?.count ?? 0

        var issues: [ValidationError] = []

        if !hasRedeemers {
            if collateralCount > 0 {
                issues.append(ValidationError(
                    kind: .collateralUnnecessary,
                    fieldPath: "transaction_body.collateral",
                    message: "Collateral inputs are declared but no Plutus redeemers are present.",
                    hint: "Remove the collateral field if this transaction does not execute scripts.",
                    isWarning: true
                ))
            }
            return issues
        }

        // Scripts are being executed — collateral is required.
        guard collateralCount > 0 else {
            return [ValidationError(
                kind: .noCollateralInputs,
                fieldPath: "transaction_body.collateral",
                message: "Transaction executes Plutus scripts but provides no collateral inputs.",
                hint: "Add collateral inputs to cover the maximum fee in case script execution fails."
            )]
        }

        // Too many collateral inputs
        if collateralCount > protocolParams.maxCollateralInputs {
            issues.append(ValidationError(
                kind: .tooManyCollateralInputs,
                fieldPath: "transaction_body.collateral",
                message: "Transaction provides \(collateralCount) collateral inputs but the "
                    + "maximum allowed is \(protocolParams.maxCollateralInputs).",
                hint: "Reduce the number of collateral inputs to at most \(protocolParams.maxCollateralInputs)."
            ))
        }

        // Check that collateral inputs are not locked by a script
        if let inputs = collateralInputs {
            let resolvedMap: [String: TransactionOutput] = Dictionary(
                uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                    ("\(utxo.input.transactionId)#\(utxo.input.index)", utxo.output)
                }
            )
            // ListOrNonEmptyOrderedSet requires .asList to iterate
            for (i, input) in inputs.asList.enumerated() {
                let key = "\(input.transactionId)#\(input.index)"
                if let resolved = resolvedMap[key] {
                    let isScriptAddress: Bool
                    switch resolved.address.addressType {
                    case .scriptNone, .scriptKey, .scriptScript, .scriptPointer:
                        isScriptAddress = true
                    default:
                        isScriptAddress = false
                    }
                    if isScriptAddress {
                        issues.append(ValidationError(
                            kind: .collateralLockedByScript,
                            fieldPath: "transaction_body.collateral[\(i)]",
                            message: "Collateral input \(key) is locked by a script. "
                                + "Collateral must come from a key-payment-credential address.",
                            hint: "Replace this collateral input with one from a regular key-based address."
                        ))
                    }

                    // Warn if collateral input uses a staking-only address (no payment part).
                    // Collateral should come from a payment address (keyNone / scriptNone /
                    // keyKey / scriptKey / etc.), not a pure staking address (noneKey / noneScript).
                    let isRewardAddress: Bool
                    switch resolved.address.addressType {
                    case .noneKey, .noneScript:
                        isRewardAddress = true
                    default:
                        isRewardAddress = false
                    }
                    if isRewardAddress {
                        issues.append(ValidationError(
                            kind: .collateralUsesRewardAddress,
                            fieldPath: "transaction_body.collateral[\(i)]",
                            message: "Collateral input \(key) uses a reward (staking) address. "
                                + "Collateral should come from a payment address.",
                            hint: "Use a UTxO at a payment address (key-hash or script-hash) as collateral.",
                            isWarning: true
                        ))
                    }

                }
            }
        }

        // Minimum collateral amount = fee × collateralPercentage / 100
        let minCollateral = body.fee * UInt64(protocolParams.collateralPercentage) / 100

        // Compute total supplied collateral lovelace (from resolved inputs minus return)
        if !context.resolvedInputs.isEmpty, let inputs = collateralInputs {
            let resolvedMap: [String: TransactionOutput] = Dictionary(
                uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                    ("\(utxo.input.transactionId)#\(utxo.input.index)", utxo.output)
                }
            )

            var totalCollateralAda: Int = 0
            for input in inputs.asList {
                let key = "\(input.transactionId)#\(input.index)"
                if let resolved = resolvedMap[key] {
                    totalCollateralAda += resolved.amount.coin
                }
            }
            // Subtract collateral return
            if let ret = body.collateralReturn {
                totalCollateralAda -= ret.amount.coin
            }

            // Check declared totalCollateral field matches actual
            if let declared = body.totalCollateral {
                if declared != UInt64(totalCollateralAda) {
                    issues.append(ValidationError(
                        kind: .incorrectTotalCollateral,
                        fieldPath: "transaction_body.total_collateral",
                        message: "Declared total_collateral \(declared) lovelace does not match "
                            + "computed net collateral \(totalCollateralAda) lovelace.",
                        hint: "Set total_collateral to the exact difference between collateral "
                            + "inputs and the collateral return output."
                    ))
                }
            }

            if UInt64(totalCollateralAda) < minCollateral {
                issues.append(ValidationError(
                    kind: .insufficientCollateral,
                    fieldPath: "transaction_body.collateral",
                    message: "Net collateral \(totalCollateralAda) lovelace is less than the "
                        + "minimum required \(minCollateral) lovelace "
                        + "(fee=\(body.fee), collateralPercentage=\(protocolParams.collateralPercentage)%).",
                    hint: "Increase the collateral inputs so their net value is at least \(minCollateral) lovelace."
                ))
            }

            // Net collateral must be ADA-only.
            // Sum the MultiAsset across all collateral inputs, then subtract the return.
            var netMultiAsset = MultiAsset([:])
            for input in inputs.asList {
                let key = "\(input.transactionId)#\(input.index)"
                if let resolved = resolvedMap[key] {
                    netMultiAsset = netMultiAsset + resolved.amount.multiAsset
                }
            }
            if let ret = body.collateralReturn {
                netMultiAsset = netMultiAsset - ret.amount.multiAsset
            }
            // After normalize(), any remaining entries mean non-ADA in the net.
            let normalised = netMultiAsset.normalize()
            if !normalised.data.isEmpty {
                issues.append(ValidationError(
                    kind: .collateralContainsNonAdaAssets,
                    fieldPath: "transaction_body.collateral",
                    message: "Net collateral (inputs minus return) contains non-ADA assets. "
                        + "The net collateral value must be ADA-only.",
                    hint: "Add or adjust the collateral return to sweep all native tokens, "
                        + "leaving only ADA as net collateral."
                ))
            }
        }

        // Collateral return address must be a key-payment address (not script-locked)
        if let ret = body.collateralReturn {
            switch ret.address.addressType {
            case .scriptNone, .scriptKey, .scriptScript, .scriptPointer:
                issues.append(ValidationError(
                    kind: .collateralLockedByScript,
                    fieldPath: "transaction_body.collateral_return",
                    message: "Collateral return address is locked by a script. "
                        + "Collateral return must go to a key-payment-credential address.",
                    hint: "Use a regular key-based address for the collateral return output."
                ))
            default:
                break
            }
        }

        // Collateral return min-ADA check
        if let ret = body.collateralReturn {
            if let retBytes = try? ret.toCBORData() {
                let minAda = protocolParams.utxoCostPerByte * (160 + retBytes.count)
                if ret.amount.coin < minAda {
                    issues.append(ValidationError(
                        kind: .collateralReturnTooSmall,
                        fieldPath: "transaction_body.collateral_return.amount",
                        message: "Collateral return contains \(ret.amount.coin) lovelace, which is below "
                            + "the minimum \(minAda) lovelace required for its size "
                            + "(\(retBytes.count) bytes, utxoCostPerByte=\(protocolParams.utxoCostPerByte)).",
                        hint: "Increase the ADA in the collateral return to at least \(minAda) lovelace."
                    ))
                }
            }
        }

        // Warn when a collateral return is present but total_collateral is not declared
        if body.collateralReturn != nil && body.totalCollateral == nil {
            issues.append(ValidationError(
                kind: .totalCollateralNotDeclared,
                fieldPath: "transaction_body.total_collateral",
                message: "A collateral return output is present but total_collateral is not declared.",
                hint: "Set total_collateral to the net lovelace difference between the collateral "
                    + "inputs and the collateral return output.",
                isWarning: true
            ))
        }

        return issues
    }
}
