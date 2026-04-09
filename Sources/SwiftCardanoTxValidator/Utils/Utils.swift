import Foundation
import SwiftCardanoCore
import SwiftNcal
import PotentCBOR

/// Utilities used by validation rules.
public enum Utils {

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
    public static func scriptDataHash(
        witnessSet: TransactionWitnessSet,
        protocolParams: ProtocolParameters
    ) throws -> ScriptDataHash {

        let costModels = try languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: protocolParams
        )

        let datums: ListOrNonEmptyOrderedSet<Datum>?
        switch witnessSet.plutusData {
        case .list(let list):
            datums = .list(list.map({ .plutusData($0) }))
        case .indefiniteList(let list):
            datums = .indefiniteList(
                IndefiniteList(
                    list.map({ .plutusData($0) })
                )
            )
        case .nonEmptyOrderedSet(let set):
            datums =
                .nonEmptyOrderedSet(
                    NonEmptyOrderedSet(
                        set.elementsOrdered.map({ .plutusData($0) })
                    )
                )
        case nil:
            datums = nil
        }

        return try scriptDataHash(
            redeemers: witnessSet.redeemers,
            datums: datums,
            costModels: CostModels(costModels)
        )
    }
    
    /// Calculate plutus script data hash
    ///
    /// - Parameters:
    ///   - redeemers: Redeemers to include.
    ///   - datums: Datums to include.
    ///   - costModels: Cost models.
    /// - Returns: Plutus script data hash
    public static func scriptDataHash(
        redeemers: Redeemers? = .map(RedeemerMap()),
        datums: ListOrNonEmptyOrderedSet<Datum>? = nil,
        costModels: CostModels? = nil
    ) throws -> ScriptDataHash {
        
        let redeemersIsEmpty: Bool
        switch redeemers {
            case .list(let list):
                redeemersIsEmpty = list.isEmpty
            case .map(let map):
                redeemersIsEmpty = map.count == 0
            case .none:
                redeemersIsEmpty = true
        }
        
        let costModelsBytes: Data
        if redeemersIsEmpty {
            costModelsBytes = try CBOREncoder().encode(CBOR.map([:]))
        } else if let costModels = costModels {
            costModelsBytes = try costModels.toCBORData()
        } else {
            let costModels = try CostModels.forScriptDataHash()
            costModelsBytes = try costModels.toCBORData()
        }
        
        let datumBytes = try datums?.toCBORData() ?? Data()
        let redeemerBytes = try redeemers?.toCBORData() ?? Data()
        
        return ScriptDataHash(
            payload: try SwiftNcal.Hash().blake2b(
                data: redeemerBytes + datumBytes + costModelsBytes,
                digestSize: SCRIPT_DATA_HASH_SIZE,
                encoder: RawEncoder.self
            )
        )
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
    public static func languageViewsCostModels(
        witnessSet: TransactionWitnessSet,
        protocolParams: ProtocolParameters
    ) throws -> [Int: [Int]] {
        var version = -1
        let usesV1 = witnessSet.plutusV1Script != nil
        let usesV2 = witnessSet.plutusV2Script != nil
        let usesV3 = witnessSet.plutusV3Script != nil

        var costModels: [Int: [Int]] = [:]
        if usesV1 {
            version = 1
            costModels[version - 1] = protocolParams.costModels.getVersion(version)
        }
        if usesV2 {
            version = 2
            costModels[version - 1] = protocolParams.costModels.getVersion(version)
        }
        if usesV3 {
            version = 3
            costModels[version - 1] = protocolParams.costModels.getVersion(version)
        }

        return costModels
    }
}
