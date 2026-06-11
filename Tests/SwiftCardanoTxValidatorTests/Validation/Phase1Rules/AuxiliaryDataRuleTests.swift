import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("AuxiliaryDataRule")
struct AuxiliaryDataRuleTests {

    @Test("rule name is correct")
    func ruleName() {
        #expect(AuxiliaryDataRule().name == "auxiliaryData")
    }

    // MARK: - validate() paths

    private func makeAddress() throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))),
            network: .testnet
        )
    }

    private func makeTx(
        auxiliaryDataHash: AuxiliaryDataHash? = nil,
        auxiliaryData: AuxiliaryData? = nil
    ) throws -> Transaction {
        let body = TransactionBody(
            inputs: .list([
                TransactionInput(transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)), index: 0)
            ]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            auxiliaryDataHash: auxiliaryDataHash
        )
        return Transaction(
            transactionBody: body,
            transactionWitnessSet: TransactionWitnessSet(),
            auxiliaryData: auxiliaryData
        )
    }

    private func run(
        auxiliaryDataHash: AuxiliaryDataHash? = nil,
        auxiliaryData: AuxiliaryData? = nil
    ) throws -> [ValidationError] {
        let tx = try makeTx(auxiliaryDataHash: auxiliaryDataHash, auxiliaryData: auxiliaryData)
        let pp = try loadProtocolParams()
        return try AuxiliaryDataRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
    }

    private func sampleAuxData() throws -> AuxiliaryData {
        try AuxiliaryData(data: .metadata(Metadata([1: .int(42)])))
    }

    @Test("returns empty when neither aux data nor hash is present")
    func neitherPresent() throws {
        #expect(try run().isEmpty)
    }

    @Test("auxiliaryDataHashMissing when aux data present but hash absent")
    func hashMissing() throws {
        let issues = try run(auxiliaryData: try sampleAuxData())
        #expect(issues.contains { $0.kind == .auxiliaryDataHashMissing })
    }

    @Test("auxiliaryDataHashUnexpected when hash present but no aux data")
    func hashUnexpected() throws {
        let hash = AuxiliaryDataHash(payload: Data(repeating: 0x55, count: 32))
        let issues = try run(auxiliaryDataHash: hash)
        #expect(issues.contains { $0.kind == .auxiliaryDataHashUnexpected })
    }

    @Test("no issues when aux data and a matching hash are both present")
    func hashMatches() throws {
        let aux = try sampleAuxData()
        let correctHash = try aux.hash()
        let issues = try run(auxiliaryDataHash: correctHash, auxiliaryData: aux)
        #expect(issues.isEmpty)
    }

    @Test("auxiliaryDataHashMismatch when the declared hash is wrong")
    func hashMismatch() throws {
        let aux = try sampleAuxData()
        let wrongHash = AuxiliaryDataHash(payload: Data(repeating: 0x00, count: 32))
        let issues = try run(auxiliaryDataHash: wrongHash, auxiliaryData: aux)
        #expect(issues.contains { $0.kind == .auxiliaryDataHashMismatch })
    }

    // MARK: - New error kind availability

    @Test("ValidationError.Kind has auxiliaryData cases")
    func auxiliaryDataKinds() {
        let missing    = ValidationError(kind: .auxiliaryDataHashMissing,    fieldPath: "x", message: "x")
        let unexpected = ValidationError(kind: .auxiliaryDataHashUnexpected, fieldPath: "x", message: "x")
        let mismatch   = ValidationError(kind: .auxiliaryDataHashMismatch,   fieldPath: "x", message: "x")

        #expect(missing.kind    == .auxiliaryDataHashMissing)
        #expect(unexpected.kind == .auxiliaryDataHashUnexpected)
        #expect(mismatch.kind   == .auxiliaryDataHashMismatch)
    }
}
