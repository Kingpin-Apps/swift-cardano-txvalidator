import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("AuxiliaryDataRule")
struct AuxiliaryDataRuleTests {

    @Test("rule name is correct")
    func ruleName() {
        #expect(AuxiliaryDataRule().name == "auxiliaryData")
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
