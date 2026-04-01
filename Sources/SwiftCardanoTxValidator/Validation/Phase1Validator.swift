import Foundation
import SwiftCardanoCore
import Logging

/// Runs all Phase-1 (ledger rule) checks against a transaction.
///
/// Rules are evaluated **concurrently** via `withThrowingTaskGroup`, so they
/// must each be `Sendable` (enforced by `ValidationRule: Sendable`).
public struct Phase1Validator: Sendable {

    private let rules: [any ValidationRule]
    private let logger: Logger

    // MARK: - Init

    /// Create a validator with the default rule set plus any extra rules.
    public init(
        additionalRules: [any ValidationRule] = [],
        logger: Logger = Logger(label: "SwiftCardanoTxValidator.Phase1")
    ) {
        self.rules = Self.defaultRules() + additionalRules
        self.logger = logger
    }

    // MARK: - Validate

    /// Run all rules and collect every error/warning.
    ///
    /// Rules that require resolved inputs or current slot context will skip
    /// their checks if that data is absent from `context`.
    ///
    /// Note: Rules run sequentially on the calling task. SwiftCardanoCore's
    /// `Transaction` and `ProtocolParameters` types are not unconditionally
    /// `Sendable` (due to existential boxing in `Redeemers`), which prevents
    /// safe concurrent dispatch via `withThrowingTaskGroup`. Parallelism can
    /// be re-enabled once SwiftCardanoCore adds explicit `Sendable` conformances.
    public func validate(
        transaction: Transaction,
        context: ValidationContext = ValidationContext(),
        protocolParams: ProtocolParameters
    ) async throws -> ValidationResult {

        var allIssues: [ValidationError] = []

        for rule in rules {
            do {
                let issues = try rule.validate(
                    transaction: transaction,
                    context: context,
                    protocolParams: protocolParams
                )
                allIssues.append(contentsOf: issues)
            } catch {
                allIssues.append(ValidationError(
                    kind: .unknown,
                    fieldPath: "rule.\(rule.name)",
                    message: "Rule '\(rule.name)' threw an unexpected error: \(error.localizedDescription)"
                ))
            }
        }

        if allIssues.isEmpty {
            logger.debug("Phase-1 passed: no issues found")
            return .valid
        }

        let errorCount   = allIssues.filter { !$0.isWarning }.count
        let warningCount = allIssues.filter {  $0.isWarning }.count
        logger.debug("Phase-1 complete: \(errorCount) error(s), \(warningCount) warning(s)")
        return .invalid(allIssues)
    }

    // MARK: - Default rule set

    private static func defaultRules() -> [any ValidationRule] {
        [
            AuxiliaryDataRule(),
            TransactionLimitsRule(),
            FeeRule(),
            BalanceRule(),
            CollateralRule(),
            ScriptIntegrityRule(),
            ValidityIntervalRule(),
            RequiredSignersRule(),
            WitnessRule(),
            SignatureRule(),
            OutputValueRule(),
            NetworkIdRule(),
            RegistrationRule(),
            GovernanceProposalRule(),
            VotingRule(),
        ]
    }
}
