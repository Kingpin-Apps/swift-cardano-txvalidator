import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("FieldView")
struct FieldViewTests {

    @Test("init stores all properties")
    func initStoresProperties() {
        let field = FieldView(path: "transaction_body.fee", value: "200000", raw: "1a0002a300")
        #expect(field.path == "transaction_body.fee")
        #expect(field.value == "200000")
        #expect(field.raw == "1a0002a300")
    }

    @Test("raw defaults to nil")
    func rawDefaultsToNil() {
        let field = FieldView(path: "transaction_body.network_id", value: "testnet")
        #expect(field.raw == nil)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let field = FieldView(path: "transaction_body.inputs[0]", value: "utxo#0", raw: "deadbeef")
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(FieldView.self, from: data)
        #expect(decoded == field)
    }

    @Test("Codable round-trip with nil raw")
    func codableRoundTripNilRaw() throws {
        let field = FieldView(path: "transaction_body.ttl", value: "1000")
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(FieldView.self, from: data)
        #expect(decoded == field)
        #expect(decoded.raw == nil)
    }

    @Test("equality distinguishes differing fields")
    func equality() {
        let a = FieldView(path: "a", value: "1", raw: nil)
        let b = FieldView(path: "a", value: "1", raw: nil)
        let c = FieldView(path: "a", value: "2", raw: nil)
        let d = FieldView(path: "a", value: "1", raw: "00")
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}
