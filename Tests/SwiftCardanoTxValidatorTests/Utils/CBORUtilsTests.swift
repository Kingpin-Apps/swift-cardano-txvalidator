import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("CBORUtils")
struct CBORUtilsTests {

    // MARK: - blake2b256

    @Test("blake2b256 of empty data matches known vector")
    func blake2b256EmptyVector() throws {
        let result = try CBORUtils.blake2b256(Data())
        let hex = CBORUtils.hexString(from: result)
        // Blake2b-256 of empty input (RFC 7693 / BLAKE2 reference)
        #expect(hex == "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8")
    }

    @Test("blake2b256 of 'abc' matches known vector")
    func blake2b256KnownVector() throws {
        let input = Data("abc".utf8)
        let result = try CBORUtils.blake2b256(input)
        let hex = CBORUtils.hexString(from: result)
        // Blake2b-256 of "abc" (well-known reference value)
        #expect(hex == "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319")
    }

    @Test("blake2b256 produces 32-byte output")
    func blake2b256OutputLength() throws {
        let result = try CBORUtils.blake2b256(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(result.count == 32)
    }

    @Test("blake2b256 is deterministic")
    func blake2b256Deterministic() throws {
        let input = Data("Cardano".utf8)
        let result1 = try CBORUtils.blake2b256(input)
        let result2 = try CBORUtils.blake2b256(input)
        #expect(result1 == result2)
    }

    // MARK: - hex utilities

    @Test("data(fromHex:) round-trips with hexString(from:)")
    func hexRoundTrip() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        let hex = CBORUtils.hexString(from: original)
        let recovered = CBORUtils.data(fromHex: hex)
        #expect(recovered == original)
    }

    @Test("data(fromHex:) handles 0x prefix")
    func hexPrefixStripping() {
        let result = CBORUtils.data(fromHex: "0xDEAD")
        #expect(result == Data([0xDE, 0xAD]))
    }

    @Test("data(fromHex:) returns nil for odd-length input")
    func hexOddLength() {
        #expect(CBORUtils.data(fromHex: "ABC") == nil)
    }
}
