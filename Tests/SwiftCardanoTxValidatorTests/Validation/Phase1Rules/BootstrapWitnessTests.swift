import Testing
import Foundation
import SwiftCardanoCore
import SwiftNcal
@testable import SwiftCardanoTxValidator

// MARK: - Bootstrap Witness Tests (Batch 8)

@Suite("BootstrapWitness")
struct BootstrapWitnessTests {

    // MARK: - Helpers

    private func makeBody() throws -> TransactionBody {
        let txId = TransactionId(payload: Data(repeating: 0xBC, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        return TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000
        )
    }

    private func makeBootstrapWitness(signing body: TransactionBody) throws -> BootstrapWitness {
        let signingKey = try SigningKey.generate()
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        return try BootstrapWitness(
            publicKey: signingKey.verifyKey.bytes,
            signature: signed.getSignature,
            chainCode: Data(repeating: 0xCC, count: 32),
            attributes: Data()
        )
    }

    // MARK: - Bootstrap witness signature verification

    @Test("Bootstrap witness with valid signature passes")
    func validBootstrapSignaturePasses() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()
        let body = try makeBody()
        let bw = try makeBootstrapWitness(signing: body)

        let witnessSet = TransactionWitnessSet(bootstrapWitness: .list([bw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let sigIssues = issues.filter { $0.kind == .invalidSignature }
        #expect(sigIssues.isEmpty, "Expected no invalidSignature for a valid bootstrap witness")
    }

    @Test("Bootstrap witness with tampered signature emits invalidSignature")
    func tamperedBootstrapSignature() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()
        let body = try makeBody()

        let signingKey = try SigningKey.generate()
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        var sigData = signed.getSignature
        if sigData.count > 0 { sigData[0] ^= 0xFF }  // flip a byte to corrupt

        let bw = try BootstrapWitness(
            publicKey: signingKey.verifyKey.bytes,
            signature: sigData,
            chainCode: Data(repeating: 0xCC, count: 32),
            attributes: Data()
        )

        let witnessSet = TransactionWitnessSet(bootstrapWitness: .list([bw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let sigIssues = issues.filter { $0.kind == .invalidSignature }
        #expect(!sigIssues.isEmpty, "Expected invalidSignature for tampered bootstrap signature")
        #expect(sigIssues.first?.fieldPath.contains("bootstrapWitness") == true)
    }

    // MARK: - Extraneous bootstrap witness warning

    @Test("Bootstrap witness present but no Byron inputs emits extraneousSignature warning")
    func extraneousBootstrapWitness() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        let signingKey = try SigningKey.generate()
        let txId = TransactionId(payload: Data(repeating: 0xBD, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)

        // Shelley address — not a Byron address
        let shelleyAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x02, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: shelleyAddr, amount: Value(coin: 2_000_000))],
            fee: 200_000
        )

        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        let bw = try BootstrapWitness(
            publicKey: signingKey.verifyKey.bytes,
            signature: signed.getSignature,
            chainCode: Data(repeating: 0xCC, count: 32),
            attributes: Data()
        )

        // Provide the resolved Shelley input (non-Byron)
        let resolvedOutput = TransactionOutput(address: shelleyAddr, amount: Value(coin: 5_000_000))
        let utxo = UTxO(input: input, output: resolvedOutput)
        let ctx = ValidationContext(resolvedInputs: [utxo])

        let witnessSet = TransactionWitnessSet(bootstrapWitness: .list([bw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let extraIssues = issues.filter {
            $0.kind == .extraneousSignature && $0.isWarning
                && ($0.fieldPath.contains("bootstrapWitness"))
        }
        #expect(!extraIssues.isEmpty,
            "Expected extraneousSignature warning when bootstrap witness present but no Byron inputs")
    }

    // MARK: - Missing bootstrap witness for Byron input

    @Test("Byron-addressed input without bootstrap witness emits missingBootstrapWitness")
    func missingBootstrapWitnessForByronInput() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        let txId = TransactionId(payload: Data(repeating: 0xBE, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let shelleyAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x03, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: shelleyAddr, amount: Value(coin: 2_000_000))],
            fee: 200_000
        )

        // Build a valid Byron address using ByronAddress.create(), then wrap it in Address.
        let byronAddr = try ByronAddress.create(root: Data(repeating: 0xAB, count: 28))
        let byronAddress = try Address(from: .bytes(byronAddr.toBytes()))
        guard byronAddress.addressType == .byron else { return }

        // Provide a resolved output at a Byron address — no bootstrap witness in witness set.
        let byronOutput = TransactionOutput(address: byronAddress, amount: Value(coin: 5_000_000))
        let utxo = UTxO(input: input, output: byronOutput)
        let ctx = ValidationContext(resolvedInputs: [utxo])

        // Provide only a vkey witness, no bootstrap witness.
        let signingKey = try SigningKey.generate()
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        let vkey = try VerificationKeyType(from: .bytes(signingKey.verifyKey.bytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: signed.getSignature)
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let missing = issues.filter { $0.kind == .missingBootstrapWitness }
        #expect(!missing.isEmpty,
            "Expected missingBootstrapWitness for Byron-addressed input with no bootstrap witness")
    }

    // MARK: - No witnesses — no issues

    @Test("No vkey or bootstrap witnesses returns no issues")
    func noWitnessesNoIssues() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()
        let body = try makeBody()
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.isEmpty)
    }
}
