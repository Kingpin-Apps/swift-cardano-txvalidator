import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

/// Tests for the top-level `TxValidator` entry point and `TxValidatorReport`.
@Suite("TxValidator")
struct TxValidatorTests {

    // MARK: - Fixtures

    private func makeAddress(_ byte: UInt8 = 0x01) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet
        )
    }

    /// A minimal, well-formed transaction. `fee: 0` makes Phase-1 report `feeTooSmall`,
    /// which lets us exercise the error-reporting paths.
    private func makeTransaction(fee: Coin = 0) throws -> Transaction {
        let input = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)),
            index: 0
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: fee
        )
        return Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
    }

    // MARK: - Transaction overloads

    @Test("inspect(transaction:) returns a view with the matching tx id")
    func inspectTransaction() throws {
        let tx = try makeTransaction()
        let view = try TxValidator().inspect(transaction: tx)
        #expect(view.txId == "\(tx.transactionBody.id)")
    }

    @Test("necessaryData(transaction:) reports the spending input")
    func necessaryDataTransaction() throws {
        let tx = try makeTransaction()
        let needed = TxValidator().necessaryData(transaction: tx)
        #expect(needed.inputs.count == 1)
    }

    @Test("validatePhase1(transaction:) runs Phase-1 and leaves Phase-2 nil")
    func validatePhase1Transaction() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 0)
        let report = try await TxValidator().validatePhase1(transaction: tx, protocolParams: pp)
        #expect(report.phase2Result == nil)
        #expect(report.redeemerEvalResults == nil)
        // fee 0 → feeTooSmall hard error → invalid.
        #expect(report.phase1Result.errors.contains { $0.kind == .feeTooSmall })
        #expect(!report.isValid)
    }

    @Test("validate(transaction:) without chainContext skips Phase-2")
    func validateTransactionNoChainContext() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 200_000)
        let report = try await TxValidator().validate(transaction: tx, protocolParams: pp)
        #expect(report.phase2Result == nil)
    }

    @Test("validate(transaction:) with chainContext but no redeemers skips Phase-2")
    func validateTransactionChainContextNoRedeemers() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 200_000)
        let chain = MockChainContext(protocolParams: pp)
        let report = try await TxValidator().validate(
            transaction: tx, protocolParams: pp, chainContext: chain
        )
        // No redeemers in the witness set → Phase-2 is not attempted.
        #expect(report.phase2Result == nil)
    }

    // MARK: - cborHex overloads

    @Test("cborHex overloads round-trip through serialised CBOR")
    func cborHexOverloads() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 200_000)
        let hex = try tx.toCBORHex()
        let validator = TxValidator()

        let view = try validator.inspect(cborHex: hex)
        #expect(view.txId == "\(tx.transactionBody.id)")

        let needed = try validator.necessaryData(cborHex: hex)
        #expect(needed.inputs.count == 1)

        let fields = try validator.fields(cborHex: hex)
        #expect(fields.contains { $0.path == "transaction_body.fee" })

        let p1 = try await validator.validatePhase1(cborHex: hex, protocolParams: pp)
        #expect(p1.phase2Result == nil)

        let full = try await validator.validate(cborHex: hex, protocolParams: pp)
        #expect(full.phase2Result == nil)
    }

    @Test("validatePhase1(cborHex:) throws on malformed CBOR")
    func validatePhase1MalformedThrows() async throws {
        let pp = try loadProtocolParams()
        await #expect(throws: TxValidatorError.self) {
            _ = try await TxValidator().validatePhase1(cborHex: "deadbeef", protocolParams: pp)
        }
    }

    // MARK: - TxValidatorReport

    @Test("TxValidatorReport aggregates errors, warnings, validity, and JSON")
    func reportAggregation() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 0)
        let report = try await TxValidator().validatePhase1(transaction: tx, protocolParams: pp)

        // allErrors includes Phase-1 hard errors; Phase-2 contributes nothing (nil).
        #expect(!report.allErrors.isEmpty)
        #expect(report.allErrors.count == report.phase1Result.errors.count)
        #expect(report.allWarnings.count == report.phase1Result.warnings.count)
        #expect(report.isValid == report.phase1Result.isValid)

        let json = try report.toJSON()
        #expect(json.contains("phase1Result"))
        #expect(json.contains("transactionView"))

        // Round-trips back through Codable.
        let decoded = try JSONExport.decode(TxValidatorReport.self, from: json)
        #expect(decoded.isValid == report.isValid)
    }

    @Test("custom additional rules are honoured by the validator")
    func additionalRulesRun() async throws {
        let pp = try loadProtocolParams()
        let tx = try makeTransaction(fee: 200_000)
        let validator = TxValidator(additionalRules: [AlwaysFailsRule()])
        let report = try await validator.validatePhase1(transaction: tx, protocolParams: pp)
        #expect(report.phase1Result.errors.contains { $0.kind == .unknown })
    }
}

/// A trivial rule that always emits one error — used to confirm `additionalRules` are executed.
private struct AlwaysFailsRule: ValidationRule {
    let name = "alwaysFails"
    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        [ValidationError(kind: .unknown, fieldPath: "test", message: "always fails")]
    }
}
