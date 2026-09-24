import Foundation

/// Execution-unit view used in per-redeemer evaluation results.
public struct ExUnitsView: Sendable, Codable, Equatable {
    /// Memory execution units.
    public let memory: Int64
    /// CPU step execution units.
    public let steps: Int64

    public init(memory: Int64, steps: Int64) {
        self.memory = memory
        self.steps = steps
    }
}

/// Per-redeemer outcome from Phase-2 Plutus script evaluation.
/// 
/// SwiftCardanoUPLC's `PhaseTwoResult` exposes.
public struct RedeemerEvalResult: Sendable, Codable, Equatable {

    /// Index of the redeemer within the transaction witness set.
    public let index: Int

    /// `true` if the script passed; `false` if it failed.
    public let passed: Bool

    /// Execution-unit budget remaining after this script ran.
    /// For failing scripts this is the full (unconsumed) restricted budget.
    public let remainingBudget: ExUnitsView

    /// Script trace / debug logs emitted during evaluation.
    public let logs: [String]

    /// Human-readable error from the CEK machine, if the script failed.
    public let error: String?

    /// Whether ``remainingBudget`` came from a real cost model.
    ///
    /// The evaluator currently runs on a placeholder cost model, so this is
    /// `false` and the budget figures carry no meaning. They are reported as
    /// unmeasured rather than shown as execution units.
    public let budgetMeasured: Bool

    public init(
        index: Int,
        passed: Bool,
        remainingBudget: ExUnitsView,
        logs: [String],
        error: String?,
        budgetMeasured: Bool = false
    ) {
        self.index = index
        self.passed = passed
        self.remainingBudget = remainingBudget
        self.logs = logs
        self.error = error
        self.budgetMeasured = budgetMeasured
    }
}
