import Foundation
import SwiftCardanoCore
import SwiftCardanoChain
import Logging

// MARK: - TxValidator

/// Main entry point for the SwiftCardanoTxValidator library.
///
/// ```swift
/// let validator = TxValidator()
/// let report = try await validator.validate(
///     cborHex: rawTxHex,
///     protocolParams: pp,
///     context: ValidationContext(resolvedInputs: utxos, currentSlot: 42_000_000, network: .mainnet)
/// )
/// print(report.phase1Result.isValid)
/// print(try report.toJSON())
/// ```
public struct TxValidator: Sendable {

    private let parser: TransactionParser
    private let phase1: Phase1Validator
    private let phase2: Phase2Validator
    private let logger: Logger

    // MARK: - Init

    public init(
        additionalRules: [any ValidationRule] = [],
        logger: Logger = Logger(label: "SwiftCardanoTxValidator")
    ) {
        self.parser  = TransactionParser()
        self.phase1  = Phase1Validator(additionalRules: additionalRules, logger: logger)
        self.phase2  = Phase2Validator()
        self.logger  = logger
    }

    // MARK: - Inspect

    /// Parse CBOR hex and return a human-readable `TransactionView`.
    public func inspect(cborHex: String) throws -> TransactionView {
        try parser.view(cborHex: cborHex)
    }

    // MARK: - Data discovery

    /// Inspect a transaction and return the complete list of chain state that must be
    /// fetched before running full validation.
    ///
    /// - Parameter cborHex: Hex-encoded CBOR transaction.
    /// - Returns: Structured list of everything the caller must fetch.
    public func necessaryData(cborHex: String) throws -> NecessaryData {
        let transaction = try parser.parse(cborHex: cborHex)
        return NecessaryData.from(transaction)
    }

    /// Extract all fields of a transaction as a flat list.
    public func fields(cborHex: String) throws -> [FieldView] {
        try parser.fields(cborHex: cborHex)
    }

    // MARK: - Validate (Phase-1 only)

    /// Parse and run Phase-1 ledger rule checks.
    ///
    /// - Parameters:
    ///   - cborHex: Hex-encoded CBOR transaction.
    ///   - protocolParams: Current protocol parameters.
    ///   - context: Optional resolved inputs, current slot, and network.
    public func validatePhase1(
        cborHex: String,
        protocolParams: ProtocolParameters,
        context: ValidationContext = ValidationContext()
    ) async throws -> TxValidatorReport {

        let transaction = try parser.parse(cborHex: cborHex)
        let txView = try parser.buildView(transaction: transaction)

        let phase1Result = try await phase1.validate(
            transaction: transaction,
            context: context,
            protocolParams: protocolParams
        )

        return TxValidatorReport(
            transactionView: txView,
            phase1Result: phase1Result,
            phase2Result: nil,
            redeemerEvalResults: nil
        )
    }

    // MARK: - Validate (Phase-1 + Phase-2)

    /// Full validation pipeline: parse → Phase-1 → Phase-2 (if requested).
    ///
    /// Phase-1 and Phase-2 are run **concurrently** via `async let` when both are requested.
    ///
    /// - Parameters:
    ///   - cborHex: Hex-encoded CBOR transaction.
    ///   - protocolParams: Current protocol parameters.
    ///   - context: Resolved inputs, current slot, and network.
    ///   - chainContext: Required for Phase-2 script execution. Pass `nil` to skip Phase-2.
    public func validate(
        cborHex: String,
        protocolParams: ProtocolParameters,
        context: ValidationContext = ValidationContext(),
        chainContext: (any ChainContext)? = nil
    ) async throws -> TxValidatorReport {

        let transaction = try parser.parse(cborHex: cborHex)
        let txView = try parser.buildView(transaction: transaction)

        logger.debug("Validating transaction \(txView.txId)")

        // Run Phase-1 first, then Phase-2.
        // Note: async let parallelism is not used here because `ProtocolParameters`
        // and `any ChainContext` are not unconditionally `Sendable` in SwiftCardanoCore,
        // so Swift 6 prohibits sending them into concurrent child tasks.
        // Phase-1 rules still run (sequentially) and Phase-2 delegates to PhaseTwo
        // which uses structured concurrency internally.
        let phase1Result = try await phase1.validate(
            transaction: transaction,
            context: context,
            protocolParams: protocolParams
        )

        let phase2Outcome: Phase2Outcome?
        if let chainContext {
            phase2Outcome = try await phase2.evaluate(
                transaction: transaction,
                resolvedInputs: context.resolvedInputs,
                chainContext: chainContext
            )
        } else {
            phase2Outcome = nil
        }

        return TxValidatorReport(
            transactionView: txView,
            phase1Result: phase1Result,
            phase2Result: phase2Outcome?.result,
            redeemerEvalResults: phase2Outcome?.redeemerEvalResults
        )
    }

    // MARK: - Transaction overloads

    /// Parse and return a human-readable ``TransactionView`` from an already-decoded transaction.
    public func inspect(transaction: Transaction) throws -> TransactionView {
        try parser.buildView(transaction: transaction)
    }

    /// Return the chain-state fetch requirements for an already-decoded transaction.
    public func necessaryData(transaction: Transaction) -> NecessaryData {
        NecessaryData.from(transaction)
    }

    /// Run Phase-1 ledger rule checks on an already-decoded transaction.
    ///
    /// - Parameters:
    ///   - transaction: The decoded transaction.
    ///   - protocolParams: Current protocol parameters.
    ///   - context: Optional resolved inputs, current slot, and network.
    public func validatePhase1(
        transaction: Transaction,
        protocolParams: ProtocolParameters,
        context: ValidationContext = ValidationContext()
    ) async throws -> TxValidatorReport {

        let txView = try parser.buildView(transaction: transaction)

        let phase1Result = try await phase1.validate(
            transaction: transaction,
            context: context,
            protocolParams: protocolParams
        )

        return TxValidatorReport(
            transactionView: txView,
            phase1Result: phase1Result,
            phase2Result: nil,
            redeemerEvalResults: nil
        )
    }

    /// Full validation pipeline on an already-decoded transaction: Phase-1 → Phase-2 (if requested).
    ///
    /// - Parameters:
    ///   - transaction: The decoded transaction.
    ///   - protocolParams: Current protocol parameters.
    ///   - context: Resolved inputs, current slot, and network.
    ///   - chainContext: Required for Phase-2 script execution. Pass `nil` to skip Phase-2.
    public func validate(
        transaction: Transaction,
        protocolParams: ProtocolParameters,
        context: ValidationContext = ValidationContext(),
        chainContext: (any ChainContext)? = nil
    ) async throws -> TxValidatorReport {

        let txView = try parser.buildView(transaction: transaction)

        logger.debug("Validating transaction \(txView.txId)")

        let phase1Result = try await phase1.validate(
            transaction: transaction,
            context: context,
            protocolParams: protocolParams
        )

        let phase2Outcome: Phase2Outcome?
        if let chainContext {
            phase2Outcome = try await phase2.evaluate(
                transaction: transaction,
                resolvedInputs: context.resolvedInputs,
                chainContext: chainContext
            )
        } else {
            phase2Outcome = nil
        }

        return TxValidatorReport(
            transactionView: txView,
            phase1Result: phase1Result,
            phase2Result: phase2Outcome?.result,
            redeemerEvalResults: phase2Outcome?.redeemerEvalResults
        )
    }
}

// MARK: - TxValidatorReport

/// The combined output of parsing and validation.
public struct TxValidatorReport: Sendable, Codable {

    /// Human-readable representation of the transaction.
    public let transactionView: TransactionView

    /// Results of Phase-1 ledger rule checks.
    public let phase1Result: ValidationResult

    /// Results of Phase-2 Plutus script execution, or `nil` if Phase-2 was not run.
    public let phase2Result: ValidationResult?

    /// Per-redeemer evaluation details from Phase-2, or `nil` if Phase-2 was not run.
    public let redeemerEvalResults: [RedeemerEvalResult]?

    // MARK: - Convenience

    /// All hard errors from both phases (warnings excluded).
    public var allErrors: [ValidationError] {
        phase1Result.errors + (phase2Result?.errors ?? [])
    }

    /// All warnings from both phases.
    public var allWarnings: [ValidationError] {
        phase1Result.warnings + (phase2Result?.warnings ?? [])
    }

    /// `true` if there are no hard errors in either phase.
    public var isValid: Bool {
        phase1Result.isValid && (phase2Result?.isValid ?? true)
    }

    // MARK: - JSON export

    /// Pretty-printed JSON string representation of the full report.
    public func toJSON() throws -> String {
        try JSONExport.encode(self)
    }
}
