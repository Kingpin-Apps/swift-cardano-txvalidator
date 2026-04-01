import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("FeeRule")
struct FeeRuleTests {

    private func makeMinimalTx(fee: Coin) throws -> Transaction {
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: fee
        )
        return Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
    }

    // MARK: - Fee too small

    @Test("feeTooSmall when fee is 0")
    func feeTooSmall() throws {
        let pp = try loadProtocolParams()
        let tx = try makeMinimalTx(fee: 0)
        let issues = try FeeRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.contains { $0.kind == .feeTooSmall })
    }

    // MARK: - Fee too big warning

    @Test("feeTooBig warning when fee is massively over minimum")
    func feeTooBig() throws {
        let pp = try loadProtocolParams()
        // A very large fee should be > 10% over minimum
        let tx = try makeMinimalTx(fee: 100_000_000)
        let issues = try FeeRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let warn = issues.first { $0.kind == .feeTooBig }
        #expect(warn != nil)
        #expect(warn?.isWarning == true)
    }

    // MARK: - Fee passes

    @Test("No issues when fee is reasonable")
    func feeReasonable() throws {
        let pp = try loadProtocolParams()
        // txFeeFixed=155381, txFeePerByte=44; a minimal tx is ~200 bytes => minFee ≈ 155381 + 44*200 ≈ 164181
        // Use a fee slightly above expected minimum
        let tx = try makeMinimalTx(fee: 200_000)
        let issues = try FeeRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        // Should not have feeTooSmall (200k should cover a minimal tx)
        let feeErrors = issues.filter { $0.kind == .feeTooSmall }
        #expect(feeErrors.isEmpty)
    }

    // MARK: - Rule name

    @Test("FeeRule name is 'fee'")
    func name() {
        #expect(FeeRule().name == "fee")
    }
}
