import Foundation
import SwiftCardanoCore
import SwiftCardanoChain
import SwiftCardanoUPLC

// MARK: - Phase2Outcome

/// Combined output of Phase-2 Plutus script evaluation.
struct Phase2Outcome: Sendable {
    /// Hard errors and warnings (compatible with `TxValidatorReport`).
    let result: ValidationResult
    /// Per-redeemer evaluation details (index, pass/fail, budget, logs).
    let redeemerEvalResults: [RedeemerEvalResult]
}

// MARK: - Phase2Validator

/// Executes all Plutus scripts in a transaction using the SwiftCardanoUPLC CEK machine.
///
/// This delegates to `PhaseTwo.evaluate`, which mirrors the Aiken/Rust UPLC crate's
/// `eval_phase_two` entry point. It resolves scripts, builds `ScriptContext` for each
/// redeemer, and runs them through the CEK machine under the protocol cost model.
///
/// Usage requires a `ChainContext` (from SwiftCardanoChain) to load the cost models.
public struct Phase2Validator: Sendable {

    public init() {}

    // MARK: - Validate

    /// Evaluate all Plutus redeemers in the transaction.
    ///
    /// - Parameters:
    ///   - transaction: The fully decoded transaction.
    ///   - resolvedInputs: UTxOs referenced by the transaction's spending inputs.
    ///   - chainContext: Provides cost models and budget limits for the CEK machine.
    /// - Returns: A `Phase2Outcome` with validation result and per-redeemer details.
    func evaluate(
        transaction: Transaction,
        resolvedInputs: [UTxO],
        chainContext: any ChainContext
    ) async throws -> Phase2Outcome {

        // Early out: no redeemers means no scripts to evaluate
        guard transaction.transactionWitnessSet.redeemers != nil else {
            return Phase2Outcome(result: .valid, redeemerEvalResults: [])
        }

        let phaseTwo = PhaseTwo(chainContext: chainContext)
        let phaseTwoResult = try await phaseTwo.evaluate(
            transaction: transaction,
            resolvedInputs: resolvedInputs
        )

        var errors: [ValidationError] = []
        var evalResults: [RedeemerEvalResult] = []

        // The restricted budget per-redeemer (cpu: 10B steps, mem: 14M).
        // Used to compute consumed units for passing scripts.
        let restrictedCpu  = ExBudget.restricted.cpu
        let restrictedMem  = ExBudget.restricted.mem

        for redeemerResult in phaseTwoResult.redeemers {
            let remaining = ExUnitsView(
                memory: redeemerResult.remainingBudget.mem,
                steps:  redeemerResult.remainingBudget.cpu
            )

            let errorStr: String?
            if let machineError = redeemerResult.error {
                errorStr = "\(machineError)"
            } else if !redeemerResult.passed {
                errorStr = "Script execution failed (no error detail available)."
            } else {
                errorStr = nil
            }

            evalResults.append(RedeemerEvalResult(
                index: redeemerResult.index,
                passed: redeemerResult.passed,
                remainingBudget: remaining,
                logs: redeemerResult.logs,
                error: errorStr
            ))

            if !redeemerResult.passed {
                let logContext = redeemerResult.logs.isEmpty
                    ? ""
                    : " Script logs: \(redeemerResult.logs.joined(separator: "; "))"

                // Distinguish between input resolution errors and actual script failures
                let isInputResolutionError = errorStr?.contains("Unresolved spent input") ?? false
                let hint: String
                if isInputResolutionError {
                    hint = "The spent input could not be resolved. This occurs when validating past transactions with a chain backend that only supports the current UTxO set (e.g., cardano-cli, Ogmios). Switch to a backend that supports historical UTxO lookup (Blockfrost, Koios) to validate spent transactions."
                } else {
                    hint = "Check the script logic, the redeemer value, and the datum passed to it. Inspect the script logs above for more detail."
                }

                errors.append(ValidationError(
                    kind: .plutusScriptFailed,
                    fieldPath: "transaction_witness_set.redeemers[\(redeemerResult.index)]",
                    message: "Plutus script execution failed for redeemer[\(redeemerResult.index)]: "
                        + (errorStr ?? "") + logContext,
                    hint: hint
                ))
            } else {
                // Phase-2 warning: declared execution units significantly exceed calculated units.
                // Calculated units = restricted budget − remaining budget (per script).
                let calculatedCpu = restrictedCpu - redeemerResult.remainingBudget.cpu
                let calculatedMem = restrictedMem - redeemerResult.remainingBudget.mem

                // Fetch declared ex-units for this redeemer index from the witness set.
                if let (declMem, declSteps) = declaredExUnits(
                    for: redeemerResult.index,
                    in: transaction.transactionWitnessSet
                ) {
                    // Warn if declared is more than 2× the calculated for both mem and steps.
                    let overMem   = calculatedMem  > 0 && Int64(declMem)   > calculatedMem  * 2
                    let overSteps = calculatedCpu  > 0 && Int64(declSteps) > calculatedCpu  * 2
                    if overMem || overSteps {
                        errors.append(ValidationError(
                            kind: .excessiveExecutionUnits,
                            fieldPath: "transaction_witness_set.redeemers[\(redeemerResult.index)]",
                            message: "Declared execution units for redeemer[\(redeemerResult.index)] "
                                + "(mem=\(declMem), steps=\(declSteps)) are more than 2× the "
                                + "calculated units (mem=\(calculatedMem), steps=\(calculatedCpu)).",
                            hint: "Recalculate execution units using a local evaluator or "
                                + "reduce declared units to avoid overpaying fees.",
                            isWarning: true
                        ))
                    }
                }
            }
        }

        let result: ValidationResult = errors.filter { !$0.isWarning }.isEmpty
            ? (errors.isEmpty ? .valid : .invalid(errors))
            : .invalid(errors)

        return Phase2Outcome(result: result, redeemerEvalResults: evalResults)
    }

    // MARK: - Helpers

    /// Look up the declared `(mem, steps)` for the redeemer at `index` in the witness set.
    private func declaredExUnits(
        for index: Int,
        in witnesses: TransactionWitnessSet
    ) -> (mem: Int, steps: Int)? {
        guard let redeemers = witnesses.redeemers else { return nil }
        switch redeemers {
        case .list(let list):
            for r in list where r.index == index {
                if let eu = r.exUnits { return (eu.mem, eu.steps) }
            }
        case .map(let map):
            for (key, value) in map.dictionary where key.index == index {
                _ = key  // suppress unused warning
                return (value.exUnits.mem, value.exUnits.steps)
            }
        }
        return nil
    }
}
