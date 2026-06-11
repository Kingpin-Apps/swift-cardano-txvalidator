import Testing
import Foundation
import SwiftCardanoCore
import SwiftNaCl
@testable import SwiftCardanoTxValidator

@Suite("RequiredSignersRule")
struct RequiredSignersRuleTests {

    private func makeAddress(_ byte: UInt8 = 0x01) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet
        )
    }

    private func makeBody(
        requiredSigners: ListOrNonEmptyOrderedSet<VerificationKeyHash>? = nil
    ) throws -> TransactionBody {
        TransactionBody(
            inputs: .list([
                TransactionInput(transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)), index: 0)
            ]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            requiredSigners: requiredSigners
        )
    }

    private func run(
        requiredSigners: ListOrNonEmptyOrderedSet<VerificationKeyHash>?,
        witnessSet: TransactionWitnessSet = TransactionWitnessSet()
    ) throws -> [ValidationError] {
        let body = try makeBody(requiredSigners: requiredSigners)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)
        let pp = try loadProtocolParams()
        return try RequiredSignersRule().validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
    }

    // MARK: - Name

    @Test("rule name is requiredSigners")
    func ruleName() {
        #expect(RequiredSignersRule().name == "requiredSigners")
    }

    // MARK: - No required signers

    @Test("returns empty when there are no required signers")
    func noRequiredSigners() throws {
        #expect(try run(requiredSigners: nil).isEmpty)
    }

    @Test("returns empty when the required-signers set is empty")
    func emptyRequiredSigners() throws {
        #expect(try run(requiredSigners: .list([])).isEmpty)
    }

    // MARK: - Missing signer

    @Test("missingRequiredSigner when no matching vkey witness is present")
    func missingSigner() throws {
        let signer = VerificationKeyHash(payload: Data(repeating: 0x42, count: 28))
        let issues = try run(requiredSigners: .list([signer]))
        #expect(issues.contains { $0.kind == .missingRequiredSigner })
        #expect(issues.first?.fieldPath == "transaction_body.required_signers[0]")
    }

    // MARK: - Satisfied signer

    @Test("no error when a vkey witness hashes to the required signer")
    func signerSatisfied() throws {
        // Generate a real key and derive its Blake2b-224 hash — the required-signer value.
        let signingKey = try SigningKey.generate()
        let vkeyBytes = signingKey.verifyKey.bytes
        let hashBytes = try Hash().blake2b(data: vkeyBytes, digestSize: 28, encoder: RawEncoder.self)
        let signer = VerificationKeyHash(payload: hashBytes)

        let vkey = try VerificationKeyType(from: .bytes(vkeyBytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: Data(repeating: 0, count: 64))
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))

        let issues = try run(requiredSigners: .list([signer]), witnessSet: witnessSet)
        #expect(!issues.contains { $0.kind == .missingRequiredSigner })
    }

    @Test("reports only the unsatisfied signer when one of two matches")
    func mixedSigners() throws {
        let signingKey = try SigningKey.generate()
        let vkeyBytes = signingKey.verifyKey.bytes
        let hashBytes = try Hash().blake2b(data: vkeyBytes, digestSize: 28, encoder: RawEncoder.self)
        let present = VerificationKeyHash(payload: hashBytes)
        let absent = VerificationKeyHash(payload: Data(repeating: 0x99, count: 28))

        let vkey = try VerificationKeyType(from: .bytes(vkeyBytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: Data(repeating: 0, count: 64))
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))

        let issues = try run(requiredSigners: .list([present, absent]), witnessSet: witnessSet)
        let missing = issues.filter { $0.kind == .missingRequiredSigner }
        #expect(missing.count == 1)
        #expect(missing.first?.fieldPath == "transaction_body.required_signers[1]")
    }
}
