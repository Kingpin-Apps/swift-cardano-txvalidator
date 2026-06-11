import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

/// Additional `TransactionParser` coverage: byte parsing, view building, and field extraction.
@Suite("TransactionParserExtra")
struct TransactionParserExtraTests {

    let parser = TransactionParser()

    private func makeAddress(_ byte: UInt8 = 0x01) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet
        )
    }

    private func makeInput(_ txByte: UInt8, _ index: UInt16 = 0) -> TransactionInput {
        TransactionInput(transactionId: TransactionId(payload: Data(repeating: txByte, count: 32)), index: index)
    }

    /// A transaction body that populates every optional field `extractFields` inspects.
    private func makeRichTransaction() throws -> Transaction {
        let body = TransactionBody(
            inputs: .list([makeInput(0xAA), makeInput(0xBB)]),
            outputs: [
                TransactionOutput(address: try makeAddress(0x01), amount: Value(coin: 2_000_000)),
                TransactionOutput(address: try makeAddress(0x02), amount: Value(coin: 3_000_000)),
            ],
            fee: 200_000,
            ttl: 5_000,
            auxiliaryDataHash: nil,
            validityStart: 1_000,
            scriptDataHash: ScriptDataHash(payload: Data(repeating: 0x07, count: 32)),
            requiredSigners: nil,
            networkId: 0,
            totalCollateral: 1_500_000
        )
        return Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
    }

    // MARK: - parse(cborBytes:)

    @Test("parse(cborBytes:) decodes valid CBOR bytes")
    func parseValidBytes() throws {
        let tx = try makeRichTransaction()
        let bytes = try tx.toCBORData()
        let decoded = try parser.parse(cborBytes: bytes)
        #expect("\(decoded.transactionBody.id)" == "\(tx.transactionBody.id)")
    }

    @Test("parse(cborBytes:) throws malformedCBOR on garbage bytes")
    func parseInvalidBytes() {
        #expect(throws: TxValidatorError.self) {
            _ = try parser.parse(cborBytes: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        }
    }

    // MARK: - view / buildView

    @Test("view(cborHex:) builds a TransactionView")
    func viewFromHex() throws {
        let tx = try makeRichTransaction()
        let view = try parser.view(cborHex: try tx.toCBORHex())
        #expect(view.txId == "\(tx.transactionBody.id)")
        #expect(view.fee == 200_000)
    }

    @Test("buildView(transaction:) builds a TransactionView from a decoded tx")
    func buildViewFromTransaction() throws {
        let tx = try makeRichTransaction()
        let view = try parser.buildView(transaction: tx)
        #expect(view.txId == "\(tx.transactionBody.id)")
        #expect(view.totalCollateral == 1_500_000)
        #expect(view.scriptDataHash != nil)
    }

    // MARK: - fields(cborHex:)

    @Test("fields(cborHex:) extracts core, optional, input, and output fields")
    func fieldsExtraction() throws {
        let tx = try makeRichTransaction()
        let fields = try parser.fields(cborHex: try tx.toCBORHex())
        let paths = Set(fields.map { $0.path })

        // Core fields
        #expect(paths.contains("transaction_body.tx_id"))
        #expect(paths.contains("transaction_body.fee"))
        #expect(paths.contains("transaction.valid"))

        // Optional fields (all set in the rich tx)
        #expect(paths.contains("transaction_body.ttl"))
        #expect(paths.contains("transaction_body.validity_start_interval"))
        #expect(paths.contains("transaction_body.script_data_hash"))
        #expect(paths.contains("transaction_body.network_id"))
        #expect(paths.contains("transaction_body.total_collateral"))

        // Per-input and per-output fields
        #expect(paths.contains("transaction_body.inputs[0]"))
        #expect(paths.contains("transaction_body.inputs[1]"))
        #expect(paths.contains("transaction_body.outputs[0].address"))
        #expect(paths.contains("transaction_body.outputs[0].amount"))
        #expect(paths.contains("transaction_body.outputs[1].address"))
        #expect(paths.contains("transaction_body.outputs[1].amount"))
    }

    @Test("fields(cborHex:) omits optional fields that are absent")
    func fieldsOmitsAbsentOptionals() throws {
        let body = TransactionBody(
            inputs: .list([makeInput(0xAA)]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let fields = try parser.fields(cborHex: try tx.toCBORHex())
        let paths = Set(fields.map { $0.path })

        #expect(!paths.contains("transaction_body.ttl"))
        #expect(!paths.contains("transaction_body.script_data_hash"))
        #expect(!paths.contains("transaction_body.total_collateral"))
        // Core fields are still present.
        #expect(paths.contains("transaction_body.fee"))
    }

    // MARK: - TxValidatorError

    @Test("TxValidatorError.localizedDescription covers every case")
    func errorDescriptions() {
        #expect(TxValidatorError.malformedCBOR("x").localizedDescription == "Malformed CBOR: x")
        #expect(TxValidatorError.internalError("y").localizedDescription == "Internal error: y")
        #expect(TxValidatorError.phase2UnavailableNoChainContext.localizedDescription
            == "Phase-2 validation requires a ChainContext")
        #expect(TxValidatorError.notImplemented("z").localizedDescription == "Not implemented: z")
    }
}
