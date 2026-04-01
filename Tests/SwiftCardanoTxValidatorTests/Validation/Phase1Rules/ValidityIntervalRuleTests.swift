import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("ValidityIntervalRule")
struct ValidityIntervalRuleTests {

    private func makeTx(validityStart: Int? = nil, ttl: Int? = nil) throws -> Transaction {
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
            fee: 200_000,
            ttl: ttl,
            validityStart: validityStart
        )
        return Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
    }

    // MARK: - Before validity start

    @Test("outsideValidityInterval when current slot < validity start")
    func beforeStart() throws {
        let pp = try loadProtocolParams()
        let tx = try makeTx(validityStart: 1000)
        let ctx = ValidationContext(currentSlot: 500)
        let issues = try ValidityIntervalRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .outsideValidityInterval })
    }

    // MARK: - After TTL (expired)

    @Test("outsideValidityInterval when current slot >= TTL")
    func afterTTL() throws {
        let pp = try loadProtocolParams()
        let tx = try makeTx(ttl: 1000)
        let ctx = ValidationContext(currentSlot: 1000)
        let issues = try ValidityIntervalRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .outsideValidityInterval })
    }

    // MARK: - Within interval

    @Test("No issues when current slot is within validity interval")
    func withinInterval() throws {
        let pp = try loadProtocolParams()
        let tx = try makeTx(validityStart: 100, ttl: 2000)
        let ctx = ValidationContext(currentSlot: 500)
        let issues = try ValidityIntervalRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.isEmpty)
    }

    // MARK: - No bounds set

    @Test("No issues when neither start nor TTL is set")
    func noBounds() throws {
        let pp = try loadProtocolParams()
        let tx = try makeTx()
        let ctx = ValidationContext(currentSlot: 500)
        let issues = try ValidityIntervalRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.isEmpty)
    }

    // MARK: - Skips without slot

    @Test("Skips check when currentSlot is nil")
    func skipsWithoutSlot() throws {
        let pp = try loadProtocolParams()
        let tx = try makeTx(validityStart: 1000, ttl: 2000)
        let ctx = ValidationContext()
        let issues = try ValidityIntervalRule().validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.isEmpty)
    }

    @Test("ValidityIntervalRule name is 'validityInterval'")
    func name() {
        #expect(ValidityIntervalRule().name == "validityInterval")
    }
}
