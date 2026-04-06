import Foundation
import SwiftCardanoCore

/// Checks that the transaction fee is at least the ledger-computed minimum fee.
///
/// Minimum fee formula (Babbage / Conway):
/// ```
/// min_fee = txFeePerByte * tx_size_bytes + txFeeFixed
///         + executionUnitPrices.priceMemory * Σ(redeemer.mem)
///         + executionUnitPrices.priceSteps  * Σ(redeemer.steps)
///         + minFeeRefScriptCostPerByte * Σ(inline_reference_script_bytes)  [Conway only]
/// ```
public struct FeeRule: ValidationRule {
    public let name = "fee"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        let declaredFee = body.fee   // Coin = UInt64

        // Serialise the transaction to get its byte size.
        // If serialisation fails, we skip the size-based check gracefully.
        guard let txBytes = try? transaction.toCBORData() else {
            return [ValidationError(
                kind: .unknown,
                fieldPath: "transaction_body.fee",
                message: "Could not serialise transaction to compute minimum fee — fee check skipped."
            )]
        }

        // 1. Size-based fee component
        let txSizeFee = UInt64(protocolParams.txFeePerByte) * UInt64(txBytes.count)
        var minFee = txSizeFee + UInt64(protocolParams.txFeeFixed)

        // 2. Execution-unit fee component (Alonzo+)
        //    fee += priceMemory × Σ(mem) + priceSteps × Σ(steps)
        if let redeemers = witnesses.redeemers {
            var totalMem: Double = 0
            var totalSteps: Double = 0

            switch redeemers {
            case .list(let list):
                for r in list {
                    if let eu = r.exUnits {
                        totalMem  += Double(eu.mem)
                        totalSteps += Double(eu.steps)
                    }
                }
            case .map(let map):
                for rv in map.dictionary.values {
                    totalMem  += Double(rv.exUnits.mem)
                    totalSteps += Double(rv.exUnits.steps)
                }
            }

            let exUnitFee = protocolParams.executionUnitPrices.priceMemory * totalMem
                          + protocolParams.executionUnitPrices.priceSteps  * totalSteps
            minFee += UInt64(exUnitFee)
        }

        // 3. Reference-script fee component (Conway+)
        //    Sum over all resolved UTxOs that carry an inline script.
        //    Note: for full accuracy, reference-input UTxOs should also be included;
        //    callers may pass them via context.resolvedInputs alongside spending inputs.
        var totalRefScriptBytes = 0
        for utxo in context.resolvedInputs {
            if let inlineScript = utxo.output.script,
               let scriptBytes = try? inlineScript.scriptData() {
                totalRefScriptBytes += scriptBytes.count
            }
        }
        if totalRefScriptBytes > 0 {
            // Prefer tiered model (base × multiplier^tier for each chunk of `range` bytes)
            if let tiered = protocolParams.minFeeReferenceScripts,
               let base = tiered.base, base > 0,
               let multiplier = tiered.multiplier, multiplier > 0,
               let range = tiered.range, range > 0 {
                minFee += tieredRefScriptFee(
                    totalBytes: totalRefScriptBytes,
                    base: base,
                    multiplier: multiplier,
                    range: range
                )
            } else if let refCostPerByte = protocolParams.minFeeRefScriptCostPerByte, refCostPerByte > 0 {
                // Flat model fallback
                minFee += UInt64(refCostPerByte * totalRefScriptBytes)
            }
        }

        var issues: [ValidationError] = []

        if declaredFee < minFee {
            issues.append(ValidationError(
                kind: .feeTooSmall,
                fieldPath: "transaction_body.fee",
                message: "Fee \(declaredFee) lovelace is less than the minimum \(minFee) lovelace "
                    + "(txFeePerByte=\(protocolParams.txFeePerByte), "
                    + "txFeeFixed=\(protocolParams.txFeeFixed), "
                    + "txSize=\(txBytes.count) bytes).",
                hint: "Increase the fee to at least \(minFee) lovelace."
            ))
        } else if declaredFee > minFee * 110 / 100 {
            // Warn if fee is more than 10% over minimum (likely a mistake but not invalid).
            issues.append(ValidationError(
                kind: .feeTooBig,
                fieldPath: "transaction_body.fee",
                message: "Fee \(declaredFee) lovelace is more than 10% above the minimum "
                    + "\(minFee) lovelace. This may indicate an overestimation.",
                hint: "Consider recalculating the fee to avoid overpaying.",
                isWarning: true
            ))
        }

        return issues
    }
}

// MARK: - Tiered reference-script fee

/// Compute the tiered reference-script fee per the Conway ledger spec.
///
/// The total script bytes are split into chunks of `range` bytes.
/// Each successive chunk is charged at `base × multiplier^i` per byte,
/// making larger scripts progressively more expensive.
private func tieredRefScriptFee(
    totalBytes: Int,
    base: Double,
    multiplier: Double,
    range: Double
) -> UInt64 {
    let chunkSize = Int(range)
    guard chunkSize > 0 else { return 0 }

    var remaining = totalBytes
    var tier = 0
    var fee: Double = 0

    while remaining > 0 {
        let chunk = min(remaining, chunkSize)
        fee += base * Double(chunk) * pow(multiplier, Double(tier))
        remaining -= chunk
        tier += 1
    }

    return UInt64(ceil(fee))
}

// MARK: - ScriptType helpers

private extension ScriptType {
    /// Return the raw serialised bytes for this script (used to compute reference-script fee).
    func scriptData() throws -> Data {
        switch self {
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
}
