import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("ValidationResult")
struct ValidationResultTests {

    @Test("valid result has no errors or warnings")
    func validResult() {
        let result = ValidationResult.valid
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(result.allIssues.isEmpty)
    }

    @Test("invalid result separates errors from warnings")
    func errorsAndWarnings() {
        let error = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let warning = ValidationError(kind: .feeTooBig, fieldPath: "fee", message: "too big", isWarning: true)
        let result = ValidationResult.invalid([error, warning])

        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].kind == .feeTooSmall)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].kind == .feeTooBig)
        #expect(result.allIssues.count == 2)
    }

    @Test("merging two valid results gives valid")
    func mergeValidValid() {
        let merged = ValidationResult.valid.merged(with: .valid)
        #expect(merged.isValid)
    }

    @Test("merging valid with invalid gives invalid")
    func mergeValidInvalid() {
        let error = ValidationError(kind: .inputSetEmpty, fieldPath: "inputs", message: "empty")
        let merged = ValidationResult.valid.merged(with: .invalid([error]))
        #expect(!merged.isValid)
        #expect(merged.allIssues.count == 1)
    }

    @Test("merging two invalid results combines issues")
    func mergeInvalidInvalid() {
        let e1 = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "a")
        let e2 = ValidationError(kind: .inputSetEmpty, fieldPath: "inputs", message: "b")
        let merged = ValidationResult.invalid([e1]).merged(with: .invalid([e2]))
        #expect(merged.allIssues.count == 2)
    }

    @Test("Codable round-trip for valid")
    func codableValid() throws {
        let result = ValidationResult.valid
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ValidationResult.self, from: data)
        #expect(decoded.isValid)
    }

    @Test("Codable round-trip for invalid")
    func codableInvalid() throws {
        let error = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "msg")
        let result = ValidationResult.invalid([error])
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ValidationResult.self, from: data)
        #expect(!decoded.isValid)
        #expect(decoded.allIssues.count == 1)
        #expect(decoded.allIssues[0].kind == .feeTooSmall)
    }
}
