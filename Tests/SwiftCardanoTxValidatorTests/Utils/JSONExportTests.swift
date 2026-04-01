import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("JSONExport")
struct JSONExportTests {

    @Test("encode produces pretty-printed JSON")
    func encodePretty() throws {
        let error = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "test")
        let json = try JSONExport.encode(error)
        #expect(json.contains("\n"))  // pretty-printed has newlines
        #expect(json.contains("feeTooSmall"))
    }

    @Test("encodeCompact produces single-line JSON")
    func encodeCompact() throws {
        let error = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "test")
        let json = try JSONExport.encodeCompact(error)
        #expect(!json.contains("\n"))
        #expect(json.contains("feeTooSmall"))
    }

    @Test("decode round-trips with encode")
    func decodeRoundTrip() throws {
        let original = ValidationError(kind: .inputSetEmpty, fieldPath: "inputs", message: "empty", hint: "add input")
        let json = try JSONExport.encode(original)
        let decoded = try JSONExport.decode(ValidationError.self, from: json)
        #expect(decoded == original)
    }

    @Test("decode throws on invalid JSON")
    func decodeInvalid() {
        #expect(throws: (any Error).self) {
            _ = try JSONExport.decode(ValidationError.self, from: "not json")
        }
    }

    @Test("ValidationResult round-trip via JSONExport")
    func validationResultRoundTrip() throws {
        let error = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "msg")
        let result = ValidationResult.invalid([error])
        let json = try JSONExport.encode(result)
        let decoded = try JSONExport.decode(ValidationResult.self, from: json)
        #expect(!decoded.isValid)
        #expect(decoded.errors.count == 1)
    }
}
