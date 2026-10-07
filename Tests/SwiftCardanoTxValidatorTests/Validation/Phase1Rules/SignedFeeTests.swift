import Foundation
import SwiftCardanoCore
import SwiftNaCl
import Testing

@testable import SwiftCardanoTxValidator

/// The fee is checked against the transaction as the node will see it:
/// signed. A stake registration whose fee covered it unsigned, but not once
/// its two keys had signed, was refused by the node with FeeTooSmallUTxO
/// (supplied 171529, expected 171617); it fails here before anyone signs.
@Suite("Fee once signed")
struct SignedFeeTests {
    /// Unsigned: inputs and certificates as tagged sets, fee 171529.
    static let unsignedHex =
        "84a400d901028182582077d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e0001818258390157330328870a37311d9ca0f064ac870d9a75ae436111952f999248e75a15bb387f2c67792f3143439854a4bb8cefb1259e230550b02f1b2e1a005358fd021a00029e0904d901028183078200581cc6faa2b3aefd8d833901921bb17eaa4655ad05ae7fa18506b9c4215f1a001e8480a0f5f6"
    static let address = "0157330328870a37311d9ca0f064ac870d9a75ae436111952f999248e75a15bb387f2c67792f3143439854a4bb8cefb1259e230550b02f1b2e"

    static func transaction(fee: UInt64 = 171_529) throws -> Transaction {
        let hex = unsignedHex.replacingOccurrences(of: "021a00029e09", with: "021a" + String(format: "%08x", fee))
        return try Transaction.fromCBOR(data: Data(hexString: hex)!)
    }

    /// The UTxO the transaction spends, at the base address whose payment
    /// key must sign.
    static func context() throws -> ValidationContext {
        let input = TransactionInput(
            transactionId: TransactionId(payload: Data(hexString: "77d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e")!),
            index: 0
        )
        let output = TransactionOutput(
            address: try Address(from: .bytes(Data(hexString: address)!)),
            amount: Value(coin: 5_462_269 + 171_529 + 2_000_000)
        )
        return ValidationContext(resolvedInputs: [UTxO(input: input, output: output)])
    }

    /// `transaction` with real-sized witnesses for `count` keys.
    static func signed(_ transaction: Transaction, count: Int, tagged: Bool = true) throws -> Transaction {
        var signed = transaction
        let witnesses = try (0..<count).map { try SignedSize.placeholder(100 + $0) }
        signed.transactionWitnessSet.vkeyWitnesses = tagged ? .nonEmptyOrderedSet(NonEmptyOrderedSet(witnesses)) : .list(witnesses)
        return signed
    }

    func feeIssues(_ transaction: Transaction, _ context: ValidationContext) throws -> [ValidationError] {
        try FeeRule().validate(transaction: transaction, context: context, protocolParams: try loadProtocolParams())
            .filter { $0.kind == .feeTooSmall }
    }

    @Test("Unsigned, it is sized with the two signatures it needs, and its fee is too small")
    func unsignedTooSmall() throws {
        let size = try SignedSize.of(try Self.transaction(), context: try Self.context())
        #expect(size.missingWitnesses == 2)
        #expect(size.bytes == 369)

        let issue = try #require(try feeIssues(try Self.transaction(), try Self.context()).first)
        #expect(issue.message.contains("Fee 171529 lovelace is less than the minimum 171617 lovelace"))
        #expect(issue.message.contains("txSize=369 bytes, counting the 2 vkey witnesses still to be added"))
        #expect(issue.message.contains("FeeTooSmallUTxO"))
        #expect(issue.hint?.contains("Signing cannot fix it") == true)
    }

    @Test("Signed by both keys, as the node saw it, it is 369 bytes and the fee is 88 lovelace short")
    func signedAsTheNodeSawIt() throws {
        // Two real-sized witnesses, written as a tagged set: the node's size.
        let signed = try Self.signed(try Self.transaction(), count: 2)
        let size = try Utils.feeRelevantSize(of: signed)
        #expect(size == 369)
        let parameters = try loadProtocolParams()
        #expect(UInt64(parameters.txFeeFixed) + UInt64(parameters.txFeePerByte) * UInt64(size) == 171_617)
    }

    @Test("A transaction signed by every key it needs is sized as written, as the node sizes it")
    func fullySigned() throws {
        let vkey = Data(repeating: 0x42, count: 32)
        let hash = try #require(try? Hash().blake2b(data: vkey, digestSize: 28, encoder: RawEncoder.self))
        let body = TransactionBody(
            inputs: .list([TransactionInput(transactionId: TransactionId(payload: Data(repeating: 0xB3, count: 32)), index: 0)]),
            outputs: [TransactionOutput(address: try Address(from: .bytes(Data(hexString: Self.address)!)), amount: Value(coin: 1_500_000))],
            fee: 200_000,
            requiredSigners: .list([VerificationKeyHash(payload: hash)])
        )
        let witness = VerificationKeyWitness(vkey: try VerificationKeyType(from: .bytes(vkey)), signature: Data(repeating: 0, count: 64))
        let transaction = Transaction(
            transactionBody: body, transactionWitnessSet: TransactionWitnessSet(vkeyWitnesses: .nonEmptyOrderedSet(NonEmptyOrderedSet([witness])))
        )
        let size = try SignedSize.of(transaction, context: ValidationContext())
        #expect(size.missingWitnesses == 0)
        #expect(size.bytes == (try Utils.feeRelevantSize(of: transaction)))
    }

    @Test("With the fee the node asks for, it passes; a lovelace less, it does not")
    func exactFeePasses() throws {
        #expect(try feeIssues(try Self.transaction(fee: 171_617), try Self.context()).isEmpty)
        #expect(!(try feeIssues(try Self.transaction(fee: 171_616), try Self.context()).isEmpty))
    }

    @Test("Through the whole validator, as `scm tx validate` runs it, the transaction is invalid with the fee error")
    func wholeValidator() async throws {
        let report = try await TxValidator().validatePhase1(
            cborHex: Self.unsignedHex, protocolParams: try loadProtocolParams(), context: try Self.context()
        )
        #expect(!report.isValid)
        #expect(report.phase1Result.errors.contains { $0.kind == .feeTooSmall && $0.message.contains("171617") })
    }

    @Test("A witness set already written as a list stays a list; one already signed key is not counted twice")
    func keepsListForm() throws {
        var partly = try Self.transaction()
        partly.transactionWitnessSet.vkeyWitnesses = .list([try SignedSize.placeholder(7)])
        // The placeholder signs for no required key: both are still missing.
        let size = try SignedSize.of(partly, context: try Self.context())
        #expect(size.missingWitnesses == 2)
        // One list witness plus two more, untagged: 3 bytes under the tagged form.
        #expect(size.bytes == 369 + 101 - 3)
    }

    @Test("Without the input's UTxO, only the keys the body names are counted")
    func unresolvedInput() throws {
        let size = try SignedSize.of(try Self.transaction(), context: ValidationContext())
        #expect(size.missingWitnesses == 1, "The certificate's stake key.")
    }

    @Test("A native script needs only the fewest keys that satisfy it")
    func nativeScripts() {
        func key(_ byte: UInt8) -> NativeScript {
            .scriptPubkey(ScriptPubkey(keyHash: VerificationKeyHash(payload: Data(repeating: byte, count: 28))))
        }
        #expect(RequiredWitnesses.fewestKeys(.scriptAll(ScriptAll(scripts: [key(1), key(2)]))).count == 2)
        #expect(RequiredWitnesses.fewestKeys(.scriptAny(ScriptAny(scripts: [key(1), key(2)]))).count == 1)
        #expect(RequiredWitnesses.fewestKeys(.scriptNofK(ScriptNofK(required: 2, scripts: [key(1), key(2), key(3)]))).count == 2)
        #expect(RequiredWitnesses.fewestKeys(.scriptAny(ScriptAny(scripts: [key(1), .invalidBefore(BeforeScript(slot: 10))]))).isEmpty)
    }
}
