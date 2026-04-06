import Foundation
import SwiftCardanoCore
import SwiftNcal

/// CBOR and hashing utilities used by validation rules.
public enum CBORUtils {

    // MARK: - Hex conversion

    /// Convert a hex string to `Data`.
    public static func data(fromHex hex: String) -> Data? {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    /// Encode `Data` as a lowercase hex string.
    public static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Blake2b-256

    /// Compute a Blake2b-256 hash of `data`.
    public static func blake2b256(_ data: Data) throws -> Data {
        return try Hash().blake2b(data: data, digestSize: 32, encoder: RawEncoder.self)
    }

    // MARK: - Script data hash

    /// Compute the `script_data_hash` as defined by the Cardano ledger spec:
    ///
    /// ```
    /// scriptDataHash = Blake2b256(redeemers_cbor || datums_cbor || language_views_cbor)
    /// ```
    ///
    /// - `redeemers_cbor`: canonical CBOR of the redeemers (map or list encoding)
    /// - `datums_cbor`: CBOR set (tag 258) of PlutusDatas from the witness set;
    ///   `0xA0` (empty map) if no datums
    /// - `language_views_cbor`: cost models for only the Plutus versions actually used,
    ///   `0xA0` (empty map) if no redeemers
    static func scriptDataHash(
        witnessSet: TransactionWitnessSet,
        protocolParams: ProtocolParameters
    ) throws -> Data {

        // Redeemers CBOR
        let redeemersBytes: Data
        if let redeemers = witnessSet.redeemers {
            redeemersBytes = try redeemers.toCBORData()
        } else {
            redeemersBytes = Data([0xA0])  // empty map
        }

        // Datums CBOR — encoded as a set (tag 258) when present
        let datumsBytes: Data
        if let datums = witnessSet.plutusData, datums.count > 0 {
            // Re-serialise as CBOR set with tag 258
            // ListOrNonEmptyOrderedSet encodes as a CBOR set when appropriate
            datumsBytes = try datums.toCBORData()
        } else {
            datumsBytes = Data([0xA0])  // empty map
        }

        // Language views CBOR — cost models for versions used by this transaction
        let languageViewsBytes: Data
        if witnessSet.redeemers != nil {
            languageViewsBytes = try languageViewsCBOR(
                witnessSet: witnessSet,
                protocolParams: protocolParams
            )
        } else {
            languageViewsBytes = Data([0xA0])  // empty map
        }

        let preimage = redeemersBytes + datumsBytes + languageViewsBytes
        return try blake2b256(preimage)
    }

    /// Build the cost-model language views CBOR.
    ///
    /// Only the Plutus versions actually required by the scripts in this transaction
    /// are included. Keys are sorted by encoded length first, then lexicographically
    /// (canonical ordering). For 1-byte keys 0/1/2, the order is V1 → V2 → V3.
    ///
    /// **PlutusV1** (due to cardano-ledger bug cardano-ledger#2512):
    ///   - Language key: CBOR bytestring `0x4100` (1-byte bstr containing `0x00`)
    ///   - Cost model value: CBOR bytestring wrapping an indefinite-length array
    ///     Format: `0x59XXXX 9F <cost1> <cost2> ... FF`
    ///
    /// **PlutusV2/V3** (standard encoding):
    ///   - Language key: CBOR unsigned integer (1 for V2, 2 for V3)
    ///   - Cost model value: definite-length CBOR array of integers
    ///
    /// Reference: Cardano Ledger Spec § "language views encoding",
    private static func languageViewsCBOR(
        witnessSet: TransactionWitnessSet,
        protocolParams: ProtocolParameters
    ) throws -> Data {
        let usesV1 = witnessSet.plutusV1Script != nil
        let usesV2 = witnessSet.plutusV2Script != nil
        let usesV3 = witnessSet.plutusV3Script != nil

        var entryCount: UInt = 0
        var entriesData = Data()

        if usesV1, let costs = protocolParams.costModels.getVersion(1) {
            // Key: CBOR bytestring containing a single byte 0x00 → 0x41 0x00
            entriesData += cborByteString(Data([0x00]))

            // Value: CBOR bytestring wrapping the indefinite-length array of costs.
            // First build the inner indefinite-length array: 9F <int> <int> ... FF
            var innerArray = Data()
            innerArray.append(0x9F)  // indefinite-length array start
            for cost in costs {
                innerArray += cborInt(cost)
            }
            innerArray.append(0xFF)  // CBOR break
            // Wrap the inner array in a CBOR bytestring
            entriesData += cborByteString(innerArray)

            entryCount += 1
        }

        if usesV2, let costs = protocolParams.costModels.getVersion(2) {
            // Key 1 (PlutusV2): CBOR uint 1
            entriesData += cborUInt(1, majorType: 0)
            // Value: definite-length CBOR array
            entriesData += cborUInt(UInt(costs.count), majorType: 4)
            for cost in costs {
                entriesData += cborInt(cost)
            }
            entryCount += 1
        }

        if usesV3, let costs = protocolParams.costModels.getVersion(3) {
            // Key 2 (PlutusV3): CBOR uint 2
            entriesData += cborUInt(2, majorType: 0)
            // Value: definite-length CBOR array
            entriesData += cborUInt(UInt(costs.count), majorType: 4)
            for cost in costs {
                entriesData += cborInt(cost)
            }
            entryCount += 1
        }

        if entryCount == 0 {
            return Data([0xA0])  // empty map
        }

        // CBOR definite-length map header (major type 5)
        let mapHeader = cborUInt(entryCount, majorType: 5)
        return mapHeader + entriesData
    }

    // MARK: - CBOR primitive encoding helpers

    /// Encode a byte string with CBOR major type 2.
    private static func cborByteString(_ data: Data) -> Data {
        return cborUInt(UInt(data.count), majorType: 2) + data
    }

    /// Encode a non-negative integer with the given CBOR major type.
    private static func cborUInt(_ value: UInt, majorType: UInt8) -> Data {
        let major: UInt8 = majorType << 5
        if value <= 23 {
            return Data([major | UInt8(value)])
        } else if value <= 0xFF {
            return Data([major | 24, UInt8(value)])
        } else if value <= 0xFFFF {
            return Data([major | 25, UInt8(value >> 8), UInt8(value & 0xFF)])
        } else if value <= 0xFFFF_FFFF {
            return Data([
                major | 26,
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),  UInt8(value & 0xFF),
            ])
        } else {
            return Data([
                major | 27,
                UInt8((value >> 56) & 0xFF), UInt8((value >> 48) & 0xFF),
                UInt8((value >> 40) & 0xFF), UInt8((value >> 32) & 0xFF),
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),  UInt8(value & 0xFF),
            ])
        }
    }

    /// Encode a signed integer using CBOR major type 0 (non-negative) or 1 (negative).
    private static func cborInt(_ value: Int) -> Data {
        if value >= 0 {
            return cborUInt(UInt(value), majorType: 0)
        } else {
            // CBOR negative: encode -(n+1) with major type 1
            return cborUInt(UInt(-(value + 1)), majorType: 1)
        }
    }

    // MARK: - Testing support

    /// Test-accessible entry point for `languageViewsCBOR` that accepts raw cost arrays
    /// directly, bypassing the need for a full `TransactionWitnessSet` and `ProtocolParameters`.
    ///
    /// - Important: This method is intended for unit tests only.
    static func languageViewsCBORForTesting(
        usesV1: Bool, usesV2: Bool, usesV3: Bool,
        v1Costs: [Int]?, v2Costs: [Int]?, v3Costs: [Int]?
    ) throws -> Data {
        var entryCount: UInt = 0
        var entriesData = Data()

        if usesV1, let costs = v1Costs {
            entriesData += cborByteString(Data([0x00]))
            var innerArray = Data()
            innerArray.append(0x9F)
            for cost in costs { innerArray += cborInt(cost) }
            innerArray.append(0xFF)
            entriesData += cborByteString(innerArray)
            entryCount += 1
        }

        if usesV2, let costs = v2Costs {
            entriesData += cborUInt(1, majorType: 0)
            entriesData += cborUInt(UInt(costs.count), majorType: 4)
            for cost in costs { entriesData += cborInt(cost) }
            entryCount += 1
        }

        if usesV3, let costs = v3Costs {
            entriesData += cborUInt(2, majorType: 0)
            entriesData += cborUInt(UInt(costs.count), majorType: 4)
            for cost in costs { entriesData += cborInt(cost) }
            entryCount += 1
        }

        if entryCount == 0 { return Data([0xA0]) }
        return cborUInt(entryCount, majorType: 5) + entriesData
    }
}
