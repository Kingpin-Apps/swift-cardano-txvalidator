import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("NetworkIdRule")
struct NetworkIdRuleTests {

    private func makeAddr(network: NetworkId) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: network
        )
    }

    // MARK: - Mismatch detected

    @Test("networkIdMismatch when output address has wrong network")
    func outputMismatch() throws {
        let pp = try loadProtocolParams()
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)

        // Body says mainnet, output is testnet
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: try makeAddr(network: .testnet), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            networkId: 1  // mainnet
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(network: .mainnet)
        let issues = try NetworkIdRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .networkIdMismatch })
    }

    // MARK: - No mismatch

    @Test("No issues when all addresses match network")
    func noMismatch() throws {
        let pp = try loadProtocolParams()
        let txId = TransactionId(payload: Data(repeating: 0xBB, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: try makeAddr(network: .testnet), amount: Value(coin: 2_000_000))],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(network: .testnet)
        let issues = try NetworkIdRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        let networkIssues = issues.filter { $0.kind == .networkIdMismatch }
        #expect(networkIssues.isEmpty)
    }

    // MARK: - Skips without context

    @Test("Skips check when no network context and no body networkId")
    func skipsWithoutContext() throws {
        let pp = try loadProtocolParams()
        let txId = TransactionId(payload: Data(repeating: 0xCC, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try NetworkIdRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.isEmpty)
    }

    @Test("NetworkIdRule name is 'networkId'")
    func name() {
        #expect(NetworkIdRule().name == "networkId")
    }
}
