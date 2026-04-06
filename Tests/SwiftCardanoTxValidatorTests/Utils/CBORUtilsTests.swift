import Testing
import Foundation
import SwiftCardanoCore
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

    // MARK: - PlutusV1 language views encoding

    @Test("PlutusV1 language views key uses CBOR bytestring 0x4100, not uint 0x00")
    func plutusV1LanguageViewsKeyEncoding() throws {
        // Reference for PlutusV1 cost_models_cbor starts with:
        //   a1    -- 1-entry map
        //   4100  -- key: bytestring(1) = [0x00]   (NOT 0x00 = uint 0)
        //   5901a6 -- value: bytestring(422 bytes)
        //   9f ... ff  -- indefinite-length array of cost model integers inside
        //
        // This encoding is mandated by cardano-ledger#2512.
        let expectedPrefix = Data([0xA1, 0x41, 0x00, 0x59])

        let result = try CBORUtils.languageViewsCBORForTesting(
            usesV1: true, usesV2: false, usesV3: false,
            v1Costs: PLUTUS_V1_COST_MODEL.values.map { $0 },
            v2Costs: nil, v3Costs: nil
        )

        let prefix = result.prefix(expectedPrefix.count)
        #expect(
            prefix == expectedPrefix,
            "PlutusV1 language views should start with A1 4100 59..., got: \(CBORUtils.hexString(from: Data(prefix)))"
        )
    }

    @Test("PlutusV1 cost model CBOR uses known reference hex")
    func plutusV1CostModelMatchesReference() throws {
        // The decomposition for a PlutusV1-only transaction shows
        // cost_models_cbor starting with: a141005901a69f...
        let result = try CBORUtils.languageViewsCBORForTesting(
            usesV1: true, usesV2: false, usesV3: false,
            v1Costs: PLUTUS_V1_COST_MODEL.values.map { $0 },
            v2Costs: nil, v3Costs: nil
        )
        let hex = CBORUtils.hexString(from: result)

        // Map header + V1 key
        #expect(hex.hasPrefix("a14100"), "Expected map with bytestring key 0x00")

        // The value must be a 2-byte-length CBOR bytestring (major type 2, additional info 25)
        // containing the indefinite array. Byte at offset 3 should be 0x59 (bstr, 2-byte length).
        #expect(result[3] == 0x59, "Expected 2-byte length bytestring (0x59) for cost model value")
    }
}
