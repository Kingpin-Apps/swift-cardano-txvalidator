import Testing
import Foundation
import SwiftCardanoCore
import SwiftNcal
@testable import SwiftCardanoTxValidator

// MARK: - SignatureRule Tests

@Suite("SignatureRule")
struct SignatureRuleTests {

    // MARK: - Smoke tests

    @Test("SignatureRule name is correct")
    func ruleName() {
        #expect(SignatureRule().name == "signature")
    }

    @Test("SignatureRule returns empty when no vkey witnesses")
    func noVkeyWitnesses() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        let txId = TransactionId(payload: Data(repeating: 0xB0, count: 32))
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
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        #expect(issues.isEmpty)
    }

    // MARK: - Valid signature passes

    @Test("SignatureRule passes for correctly signed transaction")
    func validSignaturePasses() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        // Generate a real key pair
        let signingKey = try SigningKey.generate()
        let vkeyBytes = signingKey.verifyKey.bytes

        // Build a transaction body
        let txId = TransactionId(payload: Data(repeating: 0xB1, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let vkh = VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
        let addr = try Address(paymentPart: .verificationKeyHash(vkh), network: .testnet)
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000
        )

        // Sign the body CBOR
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        let sigData = signed.getSignature

        let vkey = try VerificationKeyType(from: .bytes(vkeyBytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: sigData)
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        // Provide a resolved input so the key hash is in the required set
        let resolvedOutput = TransactionOutput(address: addr, amount: Value(coin: 5_000_000))
        let utxo = UTxO(input: input, output: resolvedOutput)
        let ctx = ValidationContext(resolvedInputs: [utxo])

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let sigIssues = issues.filter { $0.kind == .invalidSignature }
        #expect(sigIssues.isEmpty, "Expected no invalidSignature for correctly signed tx")
    }

    // MARK: - Tampered signature emits invalidSignature

    @Test("SignatureRule emits invalidSignature for tampered signature")
    func tamperedSignature() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        let signingKey = try SigningKey.generate()
        let vkeyBytes = signingKey.verifyKey.bytes

        let txId = TransactionId(payload: Data(repeating: 0xB2, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x02, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000
        )

        // Sign, then tamper with the signature
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)
        var sigData = signed.getSignature
        // Flip a byte to invalidate
        if sigData.count > 0 {
            sigData[0] ^= 0xFF
        }

        let vkey = try VerificationKeyType(from: .bytes(vkeyBytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: sigData)
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let sigIssues = issues.filter { $0.kind == .invalidSignature }
        #expect(!sigIssues.isEmpty, "Expected invalidSignature for tampered signature")
    }

    // MARK: - Missing vkey witness for key-locked input

    @Test("SignatureRule emits missingVKeyWitness for key-locked input without witness")
    func missingVkeyForKeyLockedInput() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        // Generate a key pair for the witness (wrong key)
        let signingKey = try SigningKey.generate()
        let vkeyBytes = signingKey.verifyKey.bytes

        // The input is locked by a different key hash
        let inputKeyHash = VerificationKeyHash(payload: Data(repeating: 0x03, count: 28))
        let addr = try Address(paymentPart: .verificationKeyHash(inputKeyHash), network: .testnet)

        let txId = TransactionId(payload: Data(repeating: 0xB3, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)

        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )

        // Sign with the wrong key — signature is valid for this key but the input
        // requires a different key hash
        let txBodyHash = try CBORUtils.blake2b256(body.payload)
        let signed = try signingKey.sign(message: txBodyHash)

        let vkey = try VerificationKeyType(from: .bytes(vkeyBytes))
        let vkw = VerificationKeyWitness(vkey: vkey, signature: signed.getSignature)
        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([vkw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let resolvedOutput = TransactionOutput(address: addr, amount: Value(coin: 5_000_000))
        let utxo = UTxO(input: input, output: resolvedOutput)
        let ctx = ValidationContext(resolvedInputs: [utxo])

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let missingIssues = issues.filter { $0.kind == .missingVKeyWitness }
        #expect(!missingIssues.isEmpty,
            "Expected missingVKeyWitness for key-locked input with wrong witness key")
    }

    // MARK: - Extraneous vkey witness

    @Test("SignatureRule emits extraneousSignature warning for unrequired witness")
    func extraneousVkeyWitness() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        // Generate two key pairs — one required, one extraneous
        let requiredKey = try SigningKey.generate()
        let extraKey = try SigningKey.generate()

        // Hash the required key to use as the input payment address
        let reqVkeyBytes = requiredKey.verifyKey.bytes
        let reqHashBytes = try Hash().blake2b(data: reqVkeyBytes, digestSize: 28, encoder: RawEncoder.self)
        let inputKeyHash = VerificationKeyHash(payload: reqHashBytes)
        let addr = try Address(paymentPart: .verificationKeyHash(inputKeyHash), network: .testnet)

        let txId = TransactionId(payload: Data(repeating: 0xB4, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)

        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )

        let txBodyHash = try CBORUtils.blake2b256(body.payload)

        // Both keys sign — one is required, one is not
        let reqSigned = try requiredKey.sign(message: txBodyHash)
        let extraSigned = try extraKey.sign(message: txBodyHash)

        let reqVkey = try VerificationKeyType(from: .bytes(requiredKey.verifyKey.bytes))
        let extraVkey = try VerificationKeyType(from: .bytes(extraKey.verifyKey.bytes))
        let reqVkw = VerificationKeyWitness(vkey: reqVkey, signature: reqSigned.getSignature)
        let extraVkw = VerificationKeyWitness(vkey: extraVkey, signature: extraSigned.getSignature)

        let witnessSet = TransactionWitnessSet(vkeyWitnesses: .list([reqVkw, extraVkw]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let resolvedOutput = TransactionOutput(address: addr, amount: Value(coin: 5_000_000))
        let utxo = UTxO(input: input, output: resolvedOutput)
        let ctx = ValidationContext(resolvedInputs: [utxo])

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let extraIssues = issues.filter { $0.kind == .extraneousSignature && $0.isWarning }
        #expect(!extraIssues.isEmpty,
            "Expected extraneousSignature warning for unrequired witness")
    }
    // MARK: - Specific missing witness messages

    @Test("SignatureRule reports specific message for missing withdrawal witness")
    func missingWithdrawalWitness() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        // Withdrawal for a reward account
        // Data containing a reward account (29 bytes)
        // First byte: 0b1110_0000 = 0xE0 (shelley, key-based, testnet)
        let rewardAccount = Data([0xE0]) + Data(repeating: 0x07, count: 28)
        let body = TransactionBody(
            inputs: .list([]),
            outputs: [],
            fee: 100_000,
            withdrawals: Withdrawals([rewardAccount: 1_000_000])
        )

        let dummyVkey = try VerificationKeyType(from: .bytes(Data(repeating: 0x99, count: 32)))
        let dummyVkw = VerificationKeyWitness(vkey: dummyVkey, signature: Data(repeating: 0, count: 64))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet(vkeyWitnesses: .list([dummyVkw])))
        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)

        let missing = issues.filter { $0.kind == ValidationError.Kind.missingVKeyWitness }
        #expect(missing.count == 1)
        #expect(missing.first?.message.contains("required by withdrawal") == true)
    }

    @Test("SignatureRule reports specific message for missing certificate witness")
    func missingCertificateWitness() throws {
        let pp = try loadProtocolParams()
        let rule = SignatureRule()

        // A certificate requiring a vkey witness (e.g., stake registration)
        let vkeyHash = VerificationKeyHash(payload: Data(repeating: 0x08, count: 28))
        let stakeCred = StakeCredential(
            credential: .verificationKeyHash(vkeyHash)
        )
        let cert = Certificate.stakeRegistration(StakeRegistration(stakeCredential: stakeCred))
        let body = TransactionBody(
            inputs: .list([]),
            outputs: [],
            fee: 100_000,
            certificates: .list([cert])
        )

        let dummyVkey = try VerificationKeyType(from: .bytes(Data(repeating: 0x99, count: 32)))
        let dummyVkw = VerificationKeyWitness(vkey: dummyVkey, signature: Data(repeating: 0, count: 64))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet(vkeyWitnesses: .list([dummyVkw])))
        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)

        let missing = issues.filter { $0.kind == ValidationError.Kind.missingVKeyWitness }
        #expect(missing.count == 1)
        #expect(missing.first?.message.contains("required by certificate at index 0") == true)
    }
}
