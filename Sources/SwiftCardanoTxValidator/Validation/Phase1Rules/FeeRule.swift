import BigInt
import Foundation
import SwiftCardanoCore

/// Checks that the transaction fee is at least the ledger-computed minimum fee
/// (the ledger's `FeeTooSmallUTxO`).
///
/// The size is the transaction's once signed (``SignedSize``): a transaction
/// still missing signatures is sized with a witness for each key that must
/// sign, since the node charges for them.
///
/// Minimum fee formula (Babbage / Conway):
/// ```
/// min_fee = txFeePerByte * tx_size_bytes + txFeeFixed
///         + ⌈priceMemory × Σ(redeemer.mem) + priceSteps × Σ(redeemer.steps)⌉
///         + ⌊tiered reference-script fee over Σ(reference_script_bytes)⌋  [Conway only]
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

        // The size the ledger charges for once the transaction is signed —
        // see `SignedSize`. A signed transaction is sized as written.
        // If serialisation fails, we skip the size-based check gracefully.
        guard let signedSize = try? SignedSize.of(transaction, context: context) else {
            return [ValidationError(
                kind: .unknown,
                fieldPath: "transaction_body.fee",
                message: "Could not serialise transaction to compute minimum fee — fee check skipped."
            )]
        }

        let txSize = signedSize.bytes

        // 1. Size-based fee component
        let txSizeFee = BigInt(protocolParams.txFeePerByte) * BigInt(txSize)
        var minFee = txSizeFee + BigInt(protocolParams.txFeeFixed)

        // 2. Execution-unit fee component (Alonzo+): the ledger's txscriptfee,
        //    the exact cost of every redeemer's memory and steps rounded up once.
        if let redeemers = witnesses.redeemers {
            var totalMem = BigInt(0)
            var totalSteps = BigInt(0)

            switch redeemers {
            case .list(let list):
                for r in list {
                    if let eu = r.exUnits {
                        totalMem += BigInt(eu.mem)
                        totalSteps += BigInt(eu.steps)
                    }
                }
            case .map(let map):
                for rv in map.dictionary.values {
                    totalMem += BigInt(rv.exUnits.mem)
                    totalSteps += BigInt(rv.exUnits.steps)
                }
            }

            minFee += LedgerFees.scriptFee(
                prices: protocolParams.executionUnitPrices, memory: totalMem, steps: totalSteps)
        }

        // 3. Reference-script fee component (Conway+)
        //    The scripts carried by the UTxOs this transaction spends or
        //    references, as the ledger counts them. Other resolved UTxOs a
        //    caller passes (collateral, or chain data kept for other
        //    transactions) do not count.
        var totalRefScriptBytes = 0
        let era = context.era ?? .conway
        let counted = Set(
            transaction.transactionBody.inputs.asArray
                + (transaction.transactionBody.referenceInputs?.asList ?? [])
        )
        for utxo in context.resolvedInputs where era >= .conway && counted.contains(utxo.input) {
            if let inlineScript = utxo.output.script,
               let scriptBytes = try? inlineScript.scriptData() {
                totalRefScriptBytes += scriptBytes.count
            }
        }
        if totalRefScriptBytes > 0,
           let referenceScriptFee = LedgerFees.referenceScriptFee(bytes: totalRefScriptBytes, parameters: protocolParams) {
            minFee += referenceScriptFee
        }

        var issues: [ValidationError] = []

        if BigInt(declaredFee) < minFee {
            let unsigned = signedSize.missingWitnesses
            let counting = unsigned == 0 ? "" : ", counting the \(unsigned) vkey witness\(unsigned == 1 ? "" : "es") still to be added"
            issues.append(ValidationError(
                kind: .feeTooSmall,
                fieldPath: "transaction_body.fee",
                message: "Fee \(declaredFee) lovelace is less than the minimum \(minFee) lovelace "
                    + "(txFeePerByte=\(protocolParams.txFeePerByte), "
                    + "txFeeFixed=\(protocolParams.txFeeFixed), "
                    + "txSize=\(txSize) bytes\(counting)). The node rejects it with FeeTooSmallUTxO.",
                hint: unsigned == 0
                    ? "Increase the fee to at least \(minFee) lovelace."
                    : "Rebuild the transaction with a fee of at least \(minFee) lovelace. Signing cannot fix "
                        + "it: the signatures are part of what the fee pays for, and the fee is part of what is signed."
            ))
        } else if BigInt(declaredFee) > minFee * 110 / 100 {
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
