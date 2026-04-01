import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("ValidationError")
struct ValidationErrorTests {

    @Test("ValidationError Codable round-trip")
    func codableRoundTrip() throws {
        let error = ValidationError(
            kind: .feeTooSmall,
            fieldPath: "transaction_body.fee",
            message: "Fee too small",
            hint: "Increase the fee",
            isWarning: false
        )
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(ValidationError.self, from: data)
        #expect(decoded == error)
    }

    @Test("ValidationError warning defaults to false")
    func warningDefault() {
        let error = ValidationError(kind: .unknown, fieldPath: "test", message: "test")
        #expect(error.isWarning == false)
        #expect(error.hint == nil)
    }

    @Test("ValidationError equality by kind, fieldPath, message")
    func equality() {
        let a = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let b = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let c = ValidationError(kind: .feeTooBig, fieldPath: "fee", message: "too small")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("ValidationError.Kind raw values are stable strings")
    func kindRawValues() {
        #expect(ValidationError.Kind.feeTooSmall.rawValue == "feeTooSmall")
        #expect(ValidationError.Kind.badInput.rawValue == "badInput")
        #expect(ValidationError.Kind.stakeAlreadyRegistered.rawValue == "stakeAlreadyRegistered")
        #expect(ValidationError.Kind.committeeAlreadyAuthorized.rawValue == "committeeAlreadyAuthorized")
    }
}
