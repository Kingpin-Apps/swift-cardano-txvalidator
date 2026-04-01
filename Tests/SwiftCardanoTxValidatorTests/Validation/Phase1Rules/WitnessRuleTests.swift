import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - WitnessRule Tests

@Suite("WitnessRule")
struct WitnessRuleTests {

    // MARK: - Smoke tests

    @Test("WitnessRule name is correct")
    func ruleName() {
        #expect(WitnessRule().name == "witness")
    }

    @Test("ValidationError.Kind has witness-related cases")
    func witnessKinds() {
        let extraneousScript = ValidationError(kind: .extraneousScript, fieldPath: "x", message: "x", isWarning: true)
        let extraneousDatum  = ValidationError(kind: .extraneousDatum,  fieldPath: "x", message: "x", isWarning: true)
        let nativeScriptFailed = ValidationError(kind: .nativeScriptFailed, fieldPath: "x", message: "x")

        #expect(extraneousScript.kind == .extraneousScript)
        #expect(extraneousScript.isWarning)
        #expect(extraneousDatum.kind == .extraneousDatum)
        #expect(extraneousDatum.isWarning)
        #expect(nativeScriptFailed.kind == .nativeScriptFailed)
        #expect(!nativeScriptFailed.isWarning)
    }

    // MARK: - No witnesses, no scripts — passes cleanly

    @Test("WitnessRule passes for key-locked transaction with no scripts")
    func passesKeyLockedTransaction() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()
        let ctx = ValidationContext()

        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 200_000)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.isEmpty)
    }

    // MARK: - Missing redeemer pre-check

    @Test("WitnessRule emits missingRedeemer when Plutus script required but no redeemers")
    func missingRedeemerPreCheck() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        // Build a PlutusV2 script and script-locked address
        let scriptData = Data(repeating: 0x01, count: 64)
        let script = PlutusV2Script(data: scriptData)
        let scriptHashValue = try scriptHash(script: .plutusV2Script(script))
        let scriptAddr = try Address(
            paymentPart: .scriptHash(scriptHashValue),
            network: .testnet
        )

        let txId = TransactionId(payload: Data(repeating: 0xBB, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000),
            datumOption: DatumOption(datum: PlutusData.bigInt(.int(42))),
            postAlonzo: true
        )
        let resolvedUTxO = UTxO(input: input, output: utxoOutput)

        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x02, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: changeAddr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )
        // No redeemers in witness set, but script witness present
        let witnessSet = TransactionWitnessSet(plutusV2Script: .list([script]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext(resolvedInputs: [resolvedUTxO])
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let redeemerIssues = issues.filter { $0.kind == .missingRedeemer }
        #expect(!redeemerIssues.isEmpty, "Expected missingRedeemer issue")
    }

    // MARK: - Extraneous redeemer pre-check

    @Test("WitnessRule emits extraneousRedeemer warning when redeemers present but no Plutus scripts")
    func extraneousRedeemerWarning() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        let txId = TransactionId(payload: Data(repeating: 0xCC, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 200_000)

        // Redeemer present but no script-locked input
        let redeemer = Redeemer(
            tag: .spend, index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000, steps: 1_000_000)
        )
        let witnessSet = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext()   // no resolved inputs
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let warning = issues.filter { $0.kind == .extraneousRedeemer && $0.isWarning }
        #expect(!warning.isEmpty, "Expected extraneousRedeemer warning")
    }

    // MARK: - Missing datum pre-check

    @Test("WitnessRule emits missingDatum when PlutusV2 input has no datum")
    func missingDatumPreCheck() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        let script = PlutusV2Script(data: Data(repeating: 0x02, count: 64))
        let sh = try scriptHash(script: .plutusV2Script(script))
        let scriptAddr = try Address(paymentPart: .scriptHash(sh), network: .testnet)

        let txId = TransactionId(payload: Data(repeating: 0xDD, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        // UTxO has NO datum option
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000),
            postAlonzo: true
        )
        let resolvedUTxO = UTxO(input: input, output: utxoOutput)

        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x03, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: changeAddr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )
        let redeemer = Redeemer(
            tag: .spend, index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000_000)
        )
        let witnessSet = TransactionWitnessSet(
            plutusV2Script: .list([script]),
            redeemers: .list([redeemer])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext(resolvedInputs: [resolvedUTxO])
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let datumIssues = issues.filter { $0.kind == .missingDatum }
        #expect(!datumIssues.isEmpty, "Expected missingDatum issue for PlutusV2 input with no datum")
    }

    @Test("WitnessRule passes when PlutusV2 input has inline datum")
    func passesWithInlineDatum() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        let script = PlutusV2Script(data: Data(repeating: 0x03, count: 64))
        let sh = try scriptHash(script: .plutusV2Script(script))
        let scriptAddr = try Address(paymentPart: .scriptHash(sh), network: .testnet)

        let txId = TransactionId(payload: Data(repeating: 0xEE, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        // UTxO HAS inline datum
        let datum = PlutusData.bigInt(.int(99))
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000),
            datumOption: DatumOption(datum: datum),
            postAlonzo: true
        )
        let resolvedUTxO = UTxO(input: input, output: utxoOutput)

        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x04, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: changeAddr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )
        let redeemer = Redeemer(
            tag: .spend, index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000_000)
        )
        let witnessSet = TransactionWitnessSet(
            plutusV2Script: .list([script]),
            redeemers: .list([redeemer])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext(resolvedInputs: [resolvedUTxO])
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let datumIssues = issues.filter { $0.kind == .missingDatum }
        #expect(datumIssues.isEmpty, "Expected no missingDatum issue for input with inline datum")
    }

    // MARK: - Native script tests

    @Test("WitnessRule passes for native script with required key present in witnesses")
    func nativeScriptPubkeyPasses() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        // Create a native script that requires a specific key hash
        let keyHash = VerificationKeyHash(payload: Data(repeating: 0x05, count: 28))
        let ns = NativeScript.scriptPubkey(ScriptPubkey(keyHash: keyHash))
        let sh = try ns.scriptHash()
        let scriptAddr = try Address(paymentPart: .scriptHash(sh), network: .testnet)

        let txId = TransactionId(payload: Data(repeating: 0xFF, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000)
        )
        let resolvedUTxO = UTxO(input: input, output: utxoOutput)

        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x06, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: changeAddr, amount: Value(coin: 1_500_000))],
            fee: 200_000
        )
        // Include the native script in witnesses but do NOT include the key hash in vkeyWitnesses
        // → native script evaluation should FAIL
        let witnessSet = TransactionWitnessSet(nativeScripts: .list([ns]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext(resolvedInputs: [resolvedUTxO])
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let nativeScriptIssues = issues.filter { $0.kind == .nativeScriptFailed }
        #expect(!nativeScriptIssues.isEmpty,
            "Expected nativeScriptFailed when required key hash not in witnesses")
    }

    @Test("WitnessRule correctly identifies extraneous script witness (warning)")
    func extraneousScriptWarning() throws {
        let pp = try loadProtocolParams()
        let rule = WitnessRule()

        // Transaction with a key-locked input but a Plutus script in the witness set
        let script = PlutusV2Script(data: Data(repeating: 0xAB, count: 64))

        let txId = TransactionId(payload: Data(repeating: 0x11, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x07, count: 28))
            ),
            network: .testnet
        )
        let utxoOutput = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))
        let resolvedUTxO = UTxO(input: input, output: utxoOutput)

        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [utxoOutput],
            fee: 200_000
        )
        // Script in witness set but not required
        let witnessSet = TransactionWitnessSet(plutusV2Script: .list([script]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let ctx = ValidationContext(resolvedInputs: [resolvedUTxO])
        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)

        let extraneousScriptWarnings = issues.filter { $0.kind == .extraneousScript && $0.isWarning }
        #expect(!extraneousScriptWarnings.isEmpty,
            "Expected extraneousScript warning for script not required by any input")
    }
}
