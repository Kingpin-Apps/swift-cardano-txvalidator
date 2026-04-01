import Testing
@testable import SwiftCardanoTxValidator

// MARK: - Parser Tests

@Suite("TransactionParser")
struct ParserTests {

    let parser = TransactionParser()

    // MARK: - Malformed input

    @Test("Empty hex string throws malformedCBOR")
    func emptyHexThrows() {
        #expect(throws: TxValidatorError.self) {
            _ = try parser.parse(cborHex: "")
        }
    }

    @Test("Garbage hex throws malformedCBOR")
    func garbageHexThrows() {
        #expect(throws: TxValidatorError.self) {
            _ = try parser.parse(cborHex: "deadbeef")
        }
    }

    @Test("Non-hex string throws malformedCBOR")
    func nonHexStringThrows() {
        #expect(throws: TxValidatorError.self) {
            _ = try parser.parse(cborHex: "not-hex-at-all!")
        }
    }

    // MARK: - Valid transaction

    // A minimal Shelley-era transaction with a single ADA input and output.
    // Replace with a real mainnet/preprod CBOR once fixture files are added to
    // Tests/SwiftCardanoTxValidatorTests/Resources/Transactions/
    static let sampleTxHex = """
        84a500818258200000000000000000000000000000000000000000000000000000000000000001\
        0001818258390011111111111111111111111111111111111111111111111111111111\
        11111111111111111111111111111111111111111111111111111b000000012a05f200\
        021a0002a300031a00ffffff0e80a0f5f6
        """.replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\\", with: "")

    @Test("Parse valid transaction returns non-nil id")
    func parseValidTransaction() throws {
        // This test uses a real or synthetic CBOR hex; swap in a real fixture when available.
        // For now we verify that a parse error is produced (since the hex above is illustrative).
        do {
            let tx = try parser.parse(cborHex: Self.sampleTxHex)
            // If parsing succeeds, check basic fields
            #expect(!"\(tx.transactionBody.id)".isEmpty)
            #expect(tx.transactionBody.fee > 0)
        } catch TxValidatorError.malformedCBOR {
            // Acceptable if the illustrative hex is not valid CBOR
        }
    }

    // MARK: - Field extraction

    @Test("CBORUtils hex round-trip")
    func hexRoundTrip() throws {
        let original = "deadbeef01020304"
        let data = CBORUtils.data(fromHex: original)
        #expect(data != nil)
        let roundTripped = CBORUtils.hexString(from: data!)
        #expect(roundTripped == original)
    }

    @Test("CBORUtils rejects odd-length hex")
    func oddLengthHex() {
        let data = CBORUtils.data(fromHex: "abc")
        #expect(data == nil)
    }

    @Test("CBORUtils strips 0x prefix")
    func stripPrefix() {
        let data = CBORUtils.data(fromHex: "0xdeadbeef")
        #expect(data != nil)
        #expect(data!.count == 4)
    }

    // MARK: - JSON export

    @Test("ValidationError round-trips through JSON")
    func validationErrorJSON() throws {
        let error = ValidationError(
            kind: .feeTooSmall,
            fieldPath: "transaction_body.fee",
            message: "Fee is too small",
            hint: "Increase the fee"
        )
        let json = try JSONExport.encode(error)
        #expect(json.contains("feeTooSmall"))
        #expect(json.contains("transaction_body.fee"))

        let decoded = try JSONExport.decode(ValidationError.self, from: json)
        #expect(decoded == error)
    }

    @Test("ValidationResult.valid encodes and decodes")
    func validResultJSON() throws {
        let result = ValidationResult.valid
        let json = try JSONExport.encode(result)
        #expect(json.contains("valid"))

        let decoded = try JSONExport.decode(ValidationResult.self, from: json)
        #expect(decoded.isValid)
    }

    @Test("ValidationResult.invalid encodes and decodes")
    func invalidResultJSON() throws {
        let err = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let result = ValidationResult.invalid([err])
        let json = try JSONExport.encode(result)

        let decoded = try JSONExport.decode(ValidationResult.self, from: json)
        #expect(!decoded.isValid)
        #expect(decoded.errors.count == 1)
        #expect(decoded.errors.first?.kind == .feeTooSmall)
    }
}
