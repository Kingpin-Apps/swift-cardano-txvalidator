import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("ScriptIntegrityRule")
struct ScriptIntegrityRuleTests {

    private func makeAddress() throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))),
            network: .testnet
        )
    }

    private func makeTx(
        scriptDataHash: ScriptDataHash? = nil,
        witnessSet: TransactionWitnessSet = TransactionWitnessSet()
    ) throws -> Transaction {
        let body = TransactionBody(
            inputs: .list([
                TransactionInput(transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)), index: 0)
            ]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            scriptDataHash: scriptDataHash
        )
        return Transaction(transactionBody: body, transactionWitnessSet: witnessSet)
    }

    private func run(
        scriptDataHash: ScriptDataHash? = nil,
        witnessSet: TransactionWitnessSet = TransactionWitnessSet()
    ) throws -> [ValidationError] {
        let tx = try makeTx(scriptDataHash: scriptDataHash, witnessSet: witnessSet)
        let pp = try loadProtocolParams()
        return try ScriptIntegrityRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
    }

    private func sampleRedeemer() -> Redeemer {
        Redeemer(
            tag: .spend,
            index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
    }

    // MARK: - Name

    @Test("rule name is scriptIntegrity")
    func ruleName() {
        #expect(ScriptIntegrityRule().name == "scriptIntegrity")
    }

    // MARK: - No script data

    @Test("returns empty when there is no script data and no hash")
    func noScriptDataNoHash() throws {
        #expect(try run().isEmpty)
    }

    @Test("scriptDataHashMismatch when hash is set but there are no redeemers or datums")
    func hashSetWithoutScriptData() throws {
        let hash = ScriptDataHash(payload: Data(repeating: 0x07, count: 32))
        let issues = try run(scriptDataHash: hash)
        #expect(issues.contains { $0.kind == .scriptDataHashMismatch })
    }

    // MARK: - Missing hash

    @Test("scriptDataHashMismatch when redeemers are present but hash is absent")
    func redeemersWithoutHash() throws {
        let witnessSet = TransactionWitnessSet(redeemers: .list([sampleRedeemer()]))
        let issues = try run(witnessSet: witnessSet)
        #expect(issues.contains { $0.kind == .scriptDataHashMismatch })
    }

    @Test("scriptDataHashMismatch when datums are present but hash is absent")
    func datumsWithoutHash() throws {
        let witnessSet = TransactionWitnessSet(plutusData: .list([PlutusData.bigInt(.int(42))]))
        let issues = try run(witnessSet: witnessSet)
        #expect(issues.contains { $0.kind == .scriptDataHashMismatch })
    }

    // MARK: - Mismatched hash

    @Test("scriptDataHashMismatch when redeemers present and declared hash is wrong")
    func wrongHash() throws {
        let witnessSet = TransactionWitnessSet(redeemers: .list([sampleRedeemer()]))
        let wrongHash = ScriptDataHash(payload: Data(repeating: 0x00, count: 32))
        let issues = try run(scriptDataHash: wrongHash, witnessSet: witnessSet)
        #expect(issues.contains { $0.kind == .scriptDataHashMismatch })
    }

    // MARK: - Matching hash

    @Test("no issues when the declared hash matches the computed script data hash")
    func matchingHash() throws {
        let pp = try loadProtocolParams()
        let witnessSet = TransactionWitnessSet(
            plutusV2Script: .list([PlutusV2Script(data: Data([0x02]))]),
            plutusData: .list([PlutusData.bigInt(.int(42))]),
            redeemers: .list([sampleRedeemer()])
        )
        let computed = try Utils.scriptDataHash(witnessSet: witnessSet, protocolParams: pp)
        let correctHash = ScriptDataHash(payload: computed.payload)

        let issues = try run(scriptDataHash: correctHash, witnessSet: witnessSet)
        #expect(!issues.contains { $0.kind == .scriptDataHashMismatch })
    }
}
