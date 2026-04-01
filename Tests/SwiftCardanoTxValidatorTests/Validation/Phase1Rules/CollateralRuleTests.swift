import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("CollateralRule")
struct CollateralRuleTests {

    private func makeAddr(_ byte: UInt8, network: NetworkId = .testnet) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: byte, count: 28))
            ),
            network: network
        )
    }

    private func makeInput(_ byte: UInt8, index: UInt16 = 0) -> TransactionInput {
        TransactionInput(transactionId: TransactionId(payload: Data(repeating: byte, count: 32)), index: index)
    }

    private func makeRedeemers() -> Redeemers {
        .map(RedeemerMap([
            RedeemerKey(tag: .spend, index: 0): RedeemerValue(
                data: PlutusData.bigInt(.int(1)),
                exUnits: ExecutionUnits(mem: 1000, steps: 2000)
            )
        ]))
    }

    // MARK: - No collateral when needed

    @Test("noCollateralInputs when redeemers present but no collateral")
    func noCollateral() throws {
        let pp = try loadProtocolParams()
        let body = TransactionBody(
            inputs: .list([makeInput(0xA1)]),
            outputs: [TransactionOutput(address: try makeAddr(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000
        )
        let ws = TransactionWitnessSet(redeemers: makeRedeemers())
        let tx = Transaction(transactionBody: body, transactionWitnessSet: ws)
        let issues = try CollateralRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.contains { $0.kind == .noCollateralInputs })
    }

    // MARK: - Collateral unnecessary

    @Test("collateralUnnecessary warning when collateral present but no redeemers")
    func unnecessary() throws {
        let pp = try loadProtocolParams()
        let collInput = makeInput(0xB1)
        let body = TransactionBody(
            inputs: .list([makeInput(0xA2)]),
            outputs: [TransactionOutput(address: try makeAddr(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            collateral: .list([collInput])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try CollateralRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let warn = issues.first { $0.kind == .collateralUnnecessary }
        #expect(warn != nil)
        #expect(warn?.isWarning == true)
    }

    // MARK: - Too many collateral inputs

    @Test("tooManyCollateralInputs when count exceeds maxCollateralInputs")
    func tooMany() throws {
        let pp = try loadProtocolParams()  // maxCollateralInputs = 3
        let collaterals = (0..<4).map { makeInput(UInt8(0xC0 + $0)) }
        let body = TransactionBody(
            inputs: .list([makeInput(0xA3)]),
            outputs: [TransactionOutput(address: try makeAddr(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            collateral: .list(collaterals)
        )
        let ws = TransactionWitnessSet(redeemers: makeRedeemers())
        let tx = Transaction(transactionBody: body, transactionWitnessSet: ws)
        let issues = try CollateralRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.contains { $0.kind == .tooManyCollateralInputs })
    }

    // MARK: - totalCollateral not declared warning

    @Test("totalCollateralNotDeclared warning when collateralReturn present but totalCollateral absent")
    func totalNotDeclared() throws {
        let pp = try loadProtocolParams()
        let collInput = makeInput(0xD1)
        let returnAddr = try makeAddr(0x02)
        let body = TransactionBody(
            inputs: .list([makeInput(0xA4)]),
            outputs: [TransactionOutput(address: try makeAddr(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            collateral: .list([collInput]),
            collateralReturn: TransactionOutput(address: returnAddr, amount: Value(coin: 5_000_000))
        )
        let ws = TransactionWitnessSet(redeemers: makeRedeemers())
        let tx = Transaction(transactionBody: body, transactionWitnessSet: ws)
        let issues = try CollateralRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let warn = issues.first { $0.kind == .totalCollateralNotDeclared }
        #expect(warn != nil)
        #expect(warn?.isWarning == true)
    }

    // MARK: - Rule name

    @Test("CollateralRule name is 'collateral'")
    func name() {
        #expect(CollateralRule().name == "collateral")
    }
}
