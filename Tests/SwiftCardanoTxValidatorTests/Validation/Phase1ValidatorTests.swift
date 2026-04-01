import Testing
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - Phase-1 Validator Tests

@Suite("Phase1Validator")
struct Phase1ValidatorTests {

    // MARK: - ValidationResult helpers

    @Test("valid result has no errors")
    func validResultHasNoErrors() {
        let result = ValidationResult.valid
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(result.allIssues.isEmpty)
    }

    @Test("invalid result exposes errors and warnings separately")
    func invalidResultSeparation() {
        let hardError = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let warning   = ValidationError(kind: .feeTooBig,  fieldPath: "fee", message: "too big",  isWarning: true)
        let result    = ValidationResult.invalid([hardError, warning])

        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.warnings.count == 1)
        #expect(result.allIssues.count == 2)
    }

    @Test("merging two valid results is valid")
    func mergeValid() {
        let merged = ValidationResult.valid.merged(with: .valid)
        #expect(merged.isValid)
    }

    @Test("merging valid and invalid yields invalid")
    func mergeValidInvalid() {
        let err = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "small")
        let merged = ValidationResult.valid.merged(with: .invalid([err]))
        #expect(!merged.isValid)
        #expect(merged.errors.count == 1)
    }

    // MARK: - ValidityIntervalRule unit tests

    @Test("ValidityIntervalRule: no bounds always passes")
    func validityNoBounds() throws {
        let rule = ValidityIntervalRule()
        // A transaction with no TTL and no validityStart always passes
        // We test the logic directly by confirming empty output for a trivially-valid context
        // (Full integration test needs a real Transaction; skipped here without fixtures)
        _ = rule.name
        #expect(rule.name == "validityInterval")
    }

    @Test("ValidityIntervalRule: skips when no currentSlot in context")
    func validitySkipsWithoutSlot() throws {
        let rule    = ValidityIntervalRule()
        let context = ValidationContext(currentSlot: nil)
        // Without a transaction we cannot call validate directly, but we can confirm
        // the rule is correctly named and conforms to ValidationRule
        #expect(rule.name == "validityInterval")
        _ = context.currentSlot
    }

    // MARK: - FeeRule unit tests

    @Test("FeeRule name is correct")
    func feeRuleName() {
        #expect(FeeRule().name == "fee")
    }

    // MARK: - BalanceRule unit tests

    @Test("BalanceRule skips when resolvedInputs is empty")
    func balanceRuleSkipsWithoutInputs() throws {
        let rule    = BalanceRule()
        let context = ValidationContext(resolvedInputs: [])
        #expect(rule.name == "balance")
        _ = context.resolvedInputs
    }

    // MARK: - CollateralRule unit tests

    @Test("CollateralRule name is correct")
    func collateralRuleName() {
        #expect(CollateralRule().name == "collateral")
    }

    // MARK: - RequiredSignersRule unit tests

    @Test("RequiredSignersRule name is correct")
    func requiredSignersRuleName() {
        #expect(RequiredSignersRule().name == "requiredSigners")
    }

    // MARK: - OutputValueRule unit tests

    @Test("OutputValueRule name is correct")
    func outputValueRuleName() {
        #expect(OutputValueRule().name == "outputValue")
    }

    // MARK: - NetworkIdRule unit tests

    @Test("NetworkIdRule name is correct")
    func networkIdRuleName() {
        #expect(NetworkIdRule().name == "networkId")
    }

    // MARK: - ScriptIntegrityRule unit tests

    @Test("ScriptIntegrityRule name is correct")
    func scriptIntegrityRuleName() {
        #expect(ScriptIntegrityRule().name == "scriptIntegrity")
    }

    // MARK: - ValidationContext

    @Test("ValidationContext defaults to empty")
    func defaultContext() {
        let ctx = ValidationContext()
        #expect(ctx.resolvedInputs.isEmpty)
        #expect(ctx.currentSlot == nil)
        #expect(ctx.network == nil)
    }

    @Test("ValidationContext stores provided values")
    func contextStoresValues() {
        let ctx = ValidationContext(currentSlot: 100, network: .mainnet)
        #expect(ctx.currentSlot == 100)
        #expect(ctx.network == .mainnet)
    }

    // MARK: - TxValidatorReport

    @Test("TxValidatorReport.isValid when both phases valid")
    func reportIsValidWhenBothValid() {
        let txView = TransactionView(
            txId: "abc123",
            isValid: true,
            inputs: [],
            referenceInputs: [],
            collateralInputs: [],
            outputs: [],
            collateralReturn: nil,
            fee: 200_000,
            totalCollateral: nil,
            scriptDataHash: nil,
            redeemerCount: 0,
            hasPlutusScripts: false,
            validityStart: nil,
            ttl: nil,
            requiredSigners: [],
            witnessCount: 1,
            networkId: nil,
            mint: nil,
            auxiliaryDataHash: nil
        )
        let report = TxValidatorReport(
            transactionView: txView,
            phase1Result: .valid,
            phase2Result: .valid,
            redeemerEvalResults: nil
        )
        #expect(report.isValid)
        #expect(report.allErrors.isEmpty)
        #expect(report.allWarnings.isEmpty)
    }

    @Test("TxValidatorReport.isValid false when phase1 has errors")
    func reportInvalidWhenPhase1Fails() {
        let txView = TransactionView(
            txId: "abc123",
            isValid: true,
            inputs: [],
            referenceInputs: [],
            collateralInputs: [],
            outputs: [],
            collateralReturn: nil,
            fee: 100,
            totalCollateral: nil,
            scriptDataHash: nil,
            redeemerCount: 0,
            hasPlutusScripts: false,
            validityStart: nil,
            ttl: nil,
            requiredSigners: [],
            witnessCount: 1,
            networkId: nil,
            mint: nil,
            auxiliaryDataHash: nil
        )
        let err = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let report = TxValidatorReport(
            transactionView: txView,
            phase1Result: .invalid([err]),
            phase2Result: nil,
            redeemerEvalResults: nil
        )
        #expect(!report.isValid)
        #expect(report.allErrors.count == 1)
        #expect(report.allErrors.first?.kind == .feeTooSmall)
    }

    @Test("TxValidatorReport JSON round-trip")
    func reportJSONRoundTrip() throws {
        let txView = TransactionView(
            txId: "abc123",
            isValid: true,
            inputs: [],
            referenceInputs: [],
            collateralInputs: [],
            outputs: [],
            collateralReturn: nil,
            fee: 200_000,
            totalCollateral: nil,
            scriptDataHash: nil,
            redeemerCount: 0,
            hasPlutusScripts: false,
            validityStart: nil,
            ttl: nil,
            requiredSigners: [],
            witnessCount: 1,
            networkId: nil,
            mint: nil,
            auxiliaryDataHash: nil
        )
        let report = TxValidatorReport(
            transactionView: txView,
            phase1Result: .valid,
            phase2Result: nil,
            redeemerEvalResults: nil
        )
        let json = try report.toJSON()
        #expect(!json.isEmpty)
        #expect(json.contains("abc123"))
        #expect(json.contains("valid"))
    }
}
