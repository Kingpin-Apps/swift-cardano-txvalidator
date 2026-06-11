import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("TransactionLimitsRule")
struct TransactionLimitsRuleTests {

    // MARK: - Helpers

    private func makeAddress(_ byte: UInt8 = 0x01) -> Address {
        try! Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet
        )
    }

    private func makeInput(_ txByte: UInt8, _ index: UInt16 = 0) -> TransactionInput {
        TransactionInput(transactionId: TransactionId(payload: Data(repeating: txByte, count: 32)), index: index)
    }

    private func makeBody(
        inputs: [TransactionInput],
        referenceInputs: [TransactionInput]? = nil
    ) -> TransactionBody {
        TransactionBody(
            inputs: .list(inputs),
            outputs: [TransactionOutput(address: makeAddress(), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            referenceInputs: referenceInputs.map { .list($0) }
        )
    }

    private func run(
        inputs: [TransactionInput],
        referenceInputs: [TransactionInput]? = nil,
        context: ValidationContext = ValidationContext()
    ) throws -> [ValidationError] {
        let body = makeBody(inputs: inputs, referenceInputs: referenceInputs)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let pp = try loadProtocolParams()
        return try TransactionLimitsRule().validate(transaction: tx, context: context, protocolParams: pp)
    }

    // MARK: - Empty input set

    @Test("inputSetEmpty when transaction has no spending inputs")
    func emptyInputSet() throws {
        let issues = try run(inputs: [])
        #expect(issues.contains { $0.kind == .inputSetEmpty })
    }

    // MARK: - Input ordering

    @Test("inputsNotSorted warning when inputs are out of canonical order")
    func inputsNotSorted() throws {
        // 0xBB sorts after 0xAA, so listing 0xBB first is non-canonical.
        let issues = try run(inputs: [makeInput(0xBB), makeInput(0xAA)])
        let unsorted = issues.filter { $0.kind == .inputsNotSorted }
        #expect(unsorted.count == 1)
        #expect(unsorted.first?.isWarning == true)
    }

    @Test("no inputsNotSorted warning when inputs are in canonical order")
    func inputsSorted() throws {
        let issues = try run(inputs: [makeInput(0xAA), makeInput(0xBB)])
        #expect(!issues.contains { $0.kind == .inputsNotSorted })
    }

    // MARK: - Reference / spending overlap

    @Test("referenceInputOverlapsWithInput when a reference input is also a spending input")
    func referenceOverlap() throws {
        let shared = makeInput(0xAA)
        let issues = try run(inputs: [shared], referenceInputs: [shared])
        #expect(issues.contains { $0.kind == .referenceInputOverlapsWithInput })
    }

    @Test("no overlap error when reference and spending inputs are disjoint")
    func referenceNoOverlap() throws {
        let issues = try run(inputs: [makeInput(0xAA)], referenceInputs: [makeInput(0xBB)])
        #expect(!issues.contains { $0.kind == .referenceInputOverlapsWithInput })
    }

    // MARK: - Bad inputs

    @Test("badInput when a spending input is not in the resolved UTxO set")
    func badInput() throws {
        let resolved = makeInput(0xAA)
        let utxo = UTxO(
            input: resolved,
            output: TransactionOutput(address: makeAddress(), amount: Value(coin: 5_000_000))
        )
        // Spend a different input than the one resolved → badInput.
        let issues = try run(
            inputs: [makeInput(0xCC)],
            context: ValidationContext(resolvedInputs: [utxo])
        )
        #expect(issues.contains { $0.kind == .badInput })
    }

    @Test("no badInput when every spending input is resolved")
    func goodInput() throws {
        let input = makeInput(0xAA)
        let utxo = UTxO(
            input: input,
            output: TransactionOutput(address: makeAddress(), amount: Value(coin: 5_000_000))
        )
        let issues = try run(inputs: [input], context: ValidationContext(resolvedInputs: [utxo]))
        #expect(!issues.contains { $0.kind == .badInput })
    }

    @Test("rule name is correct")
    func ruleName() {
        #expect(TransactionLimitsRule().name == "transactionLimits")
    }

    // MARK: - New error kind availability

    @Test("ValidationError.Kind has transaction-limits cases")
    func transactionLimitsKinds() {
        let empty     = ValidationError(kind: .inputSetEmpty,                  fieldPath: "x", message: "x")
        let tooBig    = ValidationError(kind: .maximumTransactionSizeExceeded, fieldPath: "x", message: "x")
        let exUnits   = ValidationError(kind: .executionUnitsTooLarge,         fieldPath: "x", message: "x")
        let refOverlap = ValidationError(kind: .referenceInputOverlapsWithInput, fieldPath: "x", message: "x")
        let unsorted  = ValidationError(kind: .inputsNotSorted,                fieldPath: "x", message: "x", isWarning: true)

        #expect(empty.kind      == .inputSetEmpty)
        #expect(tooBig.kind     == .maximumTransactionSizeExceeded)
        #expect(exUnits.kind    == .executionUnitsTooLarge)
        #expect(refOverlap.kind == .referenceInputOverlapsWithInput)
        #expect(unsorted.kind   == .inputsNotSorted)
        #expect(unsorted.isWarning)
    }

    // MARK: - CollateralRule new cases

    @Test("ValidationError.Kind has new collateral cases")
    func newCollateralKinds() {
        let notDeclared  = ValidationError(kind: .totalCollateralNotDeclared, fieldPath: "x", message: "x", isWarning: true)
        let rewardAddr   = ValidationError(kind: .collateralUsesRewardAddress, fieldPath: "x", message: "x", isWarning: true)

        #expect(notDeclared.kind == .totalCollateralNotDeclared)
        #expect(notDeclared.isWarning)
        #expect(rewardAddr.kind  == .collateralUsesRewardAddress)
        #expect(rewardAddr.isWarning)
    }
}
