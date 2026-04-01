import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("TransactionLimitsRule")
struct TransactionLimitsRuleTests {

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
