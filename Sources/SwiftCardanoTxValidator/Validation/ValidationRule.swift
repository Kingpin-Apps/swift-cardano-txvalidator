import SwiftCardanoCore

/// A single Phase-1 ledger rule that can be checked against a transaction.
///
/// Conforming types must be `Sendable` because `Phase1Validator` evaluates all
/// rules concurrently via `withThrowingTaskGroup`.
public protocol ValidationRule: Sendable {
    /// Identifies the rule in error reports and logs.
    var name: String { get }

    /// Evaluate the rule.
    ///
    /// - Returns: An array of `ValidationError`; empty means the rule passed.
    /// - Throws: Only for unexpected internal errors — not for validation failures.
    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError]
}
