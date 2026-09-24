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
        // Resolve the spending input to a key address: these cases are about the
        // hash itself, so the rule must have the whole picture — otherwise it
        // rightly refuses to call a hash wrong.
        let context = ValidationContext(resolvedInputs: [
            UTxO(
                input: TransactionInput(
                    transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)),
                    index: 0
                ),
                output: TransactionOutput(
                    address: try makeAddress(), amount: Value(coin: 5_000_000)
                )
            )
        ])
        return try ScriptIntegrityRule().validate(transaction: tx, context: context, protocolParams: pp)
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

    // MARK: - Reference scripts

    /// A transaction that spends from a script address using a reference
    /// script carries no script in its witness set, so the Plutus version for
    /// the language views can only come from the resolved reference input.
    private func makeReferenceScriptFixture() throws -> (
        transaction: Transaction,
        context: ValidationContext,
        witnessSet: TransactionWitnessSet
    ) {
        let script = PlutusV3Script(data: Data([0x03, 0x04, 0x05]))
        let hash = try scriptHash(script: .plutusV3Script(script))
        let scriptAddress = try Address(paymentPart: .scriptHash(hash), network: .testnet)

        let spendInput = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0xAA, count: 32)), index: 0
        )
        let referenceInput = TransactionInput(
            transactionId: TransactionId(payload: Data(repeating: 0xBB, count: 32)), index: 0
        )

        var redeemerMap = RedeemerMap()
        redeemerMap[RedeemerKey(tag: .spend, index: 0)] = RedeemerValue(
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
        let witnessSet = TransactionWitnessSet(redeemers: .map(redeemerMap))

        let body = TransactionBody(
            inputs: .list([spendInput]),
            outputs: [TransactionOutput(address: try makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            referenceInputs: .list([referenceInput])
        )
        let transaction = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let context = ValidationContext(resolvedInputs: [
            UTxO(
                input: spendInput,
                output: TransactionOutput(address: scriptAddress, amount: Value(coin: 5_000_000))
            ),
            UTxO(
                input: referenceInput,
                output: TransactionOutput(
                    address: try makeAddress(),
                    amount: Value(coin: 5_000_000),
                    script: .plutusV3Script(script)
                )
            ),
        ])

        return (transaction, context, witnessSet)
    }

    @Test("language views pick up the Plutus version of a required reference script")
    func referenceScriptContributesLanguageView() throws {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        let views = try Utils.languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: pp,
            transaction: transaction,
            resolvedInputs: context.resolvedInputs
        )

        // PlutusV3 is language id 2.
        #expect(views[2] != nil)
        #expect(views[0] == nil)
        #expect(views[1] == nil)
    }

    @Test("a reference script the transaction does not need is left out")
    func unusedReferenceScriptIsIgnored() throws {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        // Swap the spending input's address for a key address, so nothing in
        // the transaction requires the referenced script any more.
        let keyAddress = try makeAddress()
        let rewritten = context.resolvedInputs.map { utxo -> UTxO in
            guard utxo.output.script == nil else { return utxo }
            return UTxO(
                input: utxo.input,
                output: TransactionOutput(address: keyAddress, amount: utxo.output.amount)
            )
        }

        let views = try Utils.languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: pp,
            transaction: transaction,
            resolvedInputs: rewritten
        )

        #expect(views.isEmpty)
    }

    @Test("no mismatch for a reference-script transaction whose hash is correct")
    func referenceScriptHashMatches() throws {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        let computed = try Utils.scriptDataHash(
            witnessSet: witnessSet,
            protocolParams: pp,
            transaction: transaction,
            resolvedInputs: context.resolvedInputs
        )

        var body = transaction.transactionBody
        body.scriptDataHash = ScriptDataHash(payload: computed.payload)
        let signed = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try ScriptIntegrityRule().validate(
            transaction: signed, context: context, protocolParams: pp
        )
        #expect(!issues.contains { $0.kind == .scriptDataHashMismatch })
    }

    @Test("ignoring reference scripts produces a different, wrong hash")
    func referenceScriptIsRequiredForTheHash() throws {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        let withReferenceScripts = try Utils.scriptDataHash(
            witnessSet: witnessSet,
            protocolParams: pp,
            transaction: transaction,
            resolvedInputs: context.resolvedInputs
        )
        // This is what the rule used to compute: witness-set scripts only,
        // which for this transaction means empty language views.
        let withoutReferenceScripts = try Utils.scriptDataHash(
            witnessSet: witnessSet,
            protocolParams: pp
        )

        #expect(withReferenceScripts.payload != withoutReferenceScripts.payload)
    }

    // MARK: - Unresolvable spending inputs

    /// The fixture with the spending input dropped from the resolved set, which
    /// is what a chain context returns once that UTxO has been spent: backends
    /// like cardano-cli and Ogmios only hand back unspent UTxOs.
    private func makeSpentInputFixture() throws -> (
        transaction: Transaction,
        correctHash: ScriptDataHash,
        contextMissingSpend: ValidationContext,
        witnessSet: TransactionWitnessSet
    ) {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        let computed = try Utils.scriptDataHash(
            witnessSet: witnessSet, protocolParams: pp,
            transaction: transaction, resolvedInputs: context.resolvedInputs
        )
        let correctHash = ScriptDataHash(payload: computed.payload)

        var body = transaction.transactionBody
        body.scriptDataHash = correctHash
        let declared = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        // Only the reference input survives; the spent one is gone.
        let missing = ValidationContext(
            resolvedInputs: context.resolvedInputs.filter { $0.output.script != nil }
        )
        return (declared, correctHash, missing, witnessSet)
    }

    @Test("an unresolved spending input is reported as such")
    func unresolvedSpendingInputsAreIdentified() throws {
        let (transaction, _, context, _) = try makeSpentInputFixture()
        let unresolved = Utils.unresolvedSpendingInputs(
            transaction: transaction, resolvedInputs: context.resolvedInputs
        )
        #expect(unresolved.count == 1)
        #expect(unresolved.first?.index == 0)
    }

    /// Without the spending input the reference script cannot be matched to
    /// anything the transaction requires, so it is filtered out and the language
    /// views come out empty — which is why the plain computation disagrees.
    @Test("a spent spending input hides the reference script from the language views")
    func spentInputEmptiesTheLanguageViews() throws {
        let pp = try loadProtocolParams()
        let (transaction, _, context, witnessSet) = try makeSpentInputFixture()

        let views = try Utils.languageViewsCostModels(
            witnessSet: witnessSet, protocolParams: pp,
            transaction: transaction, resolvedInputs: context.resolvedInputs
        )
        #expect(views.isEmpty)

        let assumed = try Utils.languageViewsCostModels(
            witnessSet: witnessSet, protocolParams: pp,
            transaction: transaction, resolvedInputs: context.resolvedInputs,
            assumingUnresolvedInputsUseReferenceScripts: true
        )
        #expect(assumed[2] != nil)
    }

    /// The bug this guards: a correct transaction whose inputs happen to be
    /// spent was reported as having a wrong script_data_hash, which invites
    /// someone to "fix" a hash that was right all along.
    @Test("a correct hash still passes when the spending input cannot be resolved")
    func correctHashPassesDespiteSpentInput() throws {
        let pp = try loadProtocolParams()
        let (transaction, _, context, _) = try makeSpentInputFixture()

        let issues = try ScriptIntegrityRule().validate(
            transaction: transaction, context: context, protocolParams: pp
        )
        #expect(issues.isEmpty)
    }

    /// And when it genuinely does not match, the rule still must not claim the
    /// hash is wrong — it could not compute the right one.
    @Test("an unverifiable hash is a warning, not an error")
    func unverifiableHashIsAWarning() throws {
        let pp = try loadProtocolParams()
        let (transaction, _, context, witnessSet) = try makeSpentInputFixture()

        var body = transaction.transactionBody
        body.scriptDataHash = ScriptDataHash(payload: Data(repeating: 0x5A, count: 32))
        let wrong = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try ScriptIntegrityRule().validate(
            transaction: wrong, context: context, protocolParams: pp
        )
        #expect(!issues.contains { $0.kind == .scriptDataHashMismatch })
        let issue = try #require(issues.first { $0.kind == .cannotCheckScriptDataHash })
        #expect(issue.isWarning)
        #expect(issue.message.contains("could not be verified"))
    }

    /// With every input resolved there is no excuse, and a wrong hash is an error.
    @Test("a wrong hash is still an error when every input resolves")
    func wrongHashIsAnErrorWhenFullyResolved() throws {
        let pp = try loadProtocolParams()
        let (transaction, context, witnessSet) = try makeReferenceScriptFixture()

        var body = transaction.transactionBody
        body.scriptDataHash = ScriptDataHash(payload: Data(repeating: 0x5A, count: 32))
        let wrong = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let issues = try ScriptIntegrityRule().validate(
            transaction: wrong, context: context, protocolParams: pp
        )
        let issue = try #require(issues.first { $0.kind == .scriptDataHashMismatch })
        #expect(!issue.isWarning)
    }
}
