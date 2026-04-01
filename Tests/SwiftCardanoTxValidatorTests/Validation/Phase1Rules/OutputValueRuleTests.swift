import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("OutputValueRule")
struct OutputValueRuleTests {

    private func makeAddr() throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
    }

    // MARK: - Output too small

    @Test("outputTooSmall when ADA is below minimum")
    func outputTooSmall() throws {
        let pp = try loadProtocolParams()
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        // 1 lovelace is way below minimum
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: try makeAddr(), amount: Value(coin: 1))],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try OutputValueRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.contains { $0.kind == .outputTooSmall })
    }

    // MARK: - Output adequate

    @Test("No outputTooSmall when ADA is sufficient")
    func outputAdequate() throws {
        let pp = try loadProtocolParams()
        let txId = TransactionId(payload: Data(repeating: 0xBB, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        // 5 ADA should be well above minimum for a simple output
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: try makeAddr(), amount: Value(coin: 5_000_000))],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try OutputValueRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let tooSmall = issues.filter { $0.kind == .outputTooSmall }
        #expect(tooSmall.isEmpty)
    }

    @Test("OutputValueRule name is 'outputValue'")
    func name() {
        #expect(OutputValueRule().name == "outputValue")
    }
}
