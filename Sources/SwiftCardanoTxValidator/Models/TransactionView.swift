import Foundation
import SwiftCardanoCore

/// A human-readable, JSON-serialisable mirror of a decoded Cardano `Transaction`.
/// All nested Cardano types are flattened to strings for display/export.
public struct TransactionView: Sendable, Codable, Equatable {

    // MARK: - Top-level

    /// Blake2b-256 hash of the serialised transaction body (hex).
    public let txId: String

    /// Whether the node should apply this transaction (Conway `valid` field).
    public let isValid: Bool

    // MARK: - Inputs / Outputs

    /// Spending inputs as `"txhash#index"` strings.
    public let inputs: [String]

    /// Reference inputs as `"txhash#index"` strings.
    public let referenceInputs: [String]

    /// Collateral inputs as `"txhash#index"` strings.
    public let collateralInputs: [String]

    /// Each output flattened to an `OutputView`.
    public let outputs: [OutputView]

    /// Collateral return output, if present.
    public let collateralReturn: OutputView?

    // MARK: - Fees / Value

    /// Transaction fee in lovelace.
    public let fee: UInt64

    /// Total collateral lovelace declared in body, if present.
    public let totalCollateral: UInt64?

    // MARK: - Script / Datum related

    /// Hex-encoded `scriptDataHash`, if present.
    public let scriptDataHash: String?

    /// Number of redeemers in the witness set.
    public let redeemerCount: Int

    /// Whether the transaction contains any Plutus scripts.
    public let hasPlutusScripts: Bool

    // MARK: - Validity

    /// Lower validity slot (TTL start).
    public let validityStart: Int?

    /// Upper validity slot (TTL end / time-to-live).
    public let ttl: Int?

    // MARK: - Signers / Network

    /// Required signer key hashes (hex).
    public let requiredSigners: [String]

    /// Number of vkey witnesses.
    public let witnessCount: Int

    /// Network ID byte (0 = testnet, 1 = mainnet), if declared.
    public let networkId: Int?

    // MARK: - Mint

    /// Human-readable mint/burn policy map, if present.
    /// Keys are policy IDs (hex); values are `{ assetName: amount }`.
    public let mint: [String: [String: Int]]?

    // MARK: - Auxiliary

    /// Hex-encoded auxiliary data hash, if present.
    public let auxiliaryDataHash: String?
}

// MARK: - Nested OutputView

public struct OutputView: Sendable, Codable, Equatable {
    /// Bech32 or hex address string.
    public let address: String
    /// ADA value in lovelace.
    public let lovelace: Int
    /// Multi-asset policy map `{ policyId: { assetName: amount } }`, if present.
    public let multiAsset: [String: [String: Int]]?
    /// Whether the output carries an inline datum.
    public let hasInlineDatum: Bool
    /// Whether the output carries a datum hash.
    public let hasDatumHash: Bool
    /// Whether the output carries an inline script reference.
    public let hasScriptRef: Bool
}

// MARK: - Build from Transaction

extension TransactionView {
    /// Build a `TransactionView` from a fully-decoded `Transaction`.
    static func from(_ tx: Transaction) throws -> TransactionView {
        let body = tx.transactionBody
        let witnesses = tx.transactionWitnessSet

        // ListOrOrderedSet uses .asArray; ListOrNonEmptyOrderedSet uses .asList
        let inputs = body.inputs.asArray.map { "\($0.transactionId)#\($0.index)" }

        let referenceInputs = body.referenceInputs?.asList.map {
            "\($0.transactionId)#\($0.index)"
        } ?? []

        let collateralInputs = body.collateral?.asList.map {
            "\($0.transactionId)#\($0.index)"
        } ?? []

        let outputs = try body.outputs.map { try OutputView.from($0) }

        let collateralReturn = try body.collateralReturn.map { try OutputView.from($0) }

        let scriptDataHashHex = body.scriptDataHash.map { "\($0)" }

        let requiredSigners = body.requiredSigners?.asList.map { "\($0)" } ?? []

        let witnessCount = witnesses.vkeyWitnesses?.count ?? 0

        let hasPlutusScripts =
            witnesses.plutusV1Script != nil ||
            witnesses.plutusV2Script != nil ||
            witnesses.plutusV3Script != nil

        // Redeemers is an enum: .list([any RedeemerProtocol]) or .map(RedeemerMap)
        let redeemerCount: Int
        if let redeemers = witnesses.redeemers {
            switch redeemers {
            case .list(let arr):      redeemerCount = arr.count
            case .map(let map):       redeemerCount = map.count
            }
        } else {
            redeemerCount = 0
        }

        let mint: [String: [String: Int]]? = body.mint.map { multiAsset in
            Dictionary(uniqueKeysWithValues: multiAsset.data.map { (policyId, asset) in
                let assetMap = Dictionary(
                    uniqueKeysWithValues: asset.data.map { (name, qty) in
                        (name.payload.hexEncodedString(), qty)
                    }
                )
                return ("\(policyId)", assetMap)
            })
        }

        let auxHashHex = body.auxiliaryDataHash.map { "\($0)" }

        return TransactionView(
            txId: "\(body.id)",
            isValid: tx.valid,
            inputs: inputs,
            referenceInputs: referenceInputs,
            collateralInputs: collateralInputs,
            outputs: outputs,
            collateralReturn: collateralReturn,
            fee: body.fee,
            totalCollateral: body.totalCollateral,
            scriptDataHash: scriptDataHashHex,
            redeemerCount: redeemerCount,
            hasPlutusScripts: hasPlutusScripts,
            validityStart: body.validityStart,
            ttl: body.ttl,
            requiredSigners: requiredSigners,
            witnessCount: witnessCount,
            networkId: body.networkId,
            mint: mint,
            auxiliaryDataHash: auxHashHex
        )
    }
}

extension OutputView {
    static func from(_ output: TransactionOutput) throws -> OutputView {
        let addressStr: String
        if let bech32 = try? output.address.toBech32() {
            addressStr = bech32
        } else {
            addressStr = output.address.toBytes().hexEncodedString()
        }

        let multiAsset: [String: [String: Int]]?
        if output.amount.multiAsset.data.isEmpty {
            multiAsset = nil
        } else {
            multiAsset = Dictionary(uniqueKeysWithValues: output.amount.multiAsset.data.map { policyId, asset in
                let assetMap = Dictionary(
                    uniqueKeysWithValues: asset.data.map { name, qty in
                        (name.payload.hexEncodedString(), qty)
                    }
                )
                return ("\(policyId)", assetMap)
            })
        }

        let hasInlineDatum: Bool
        let hasDatumHash: Bool
        if let opt = output.datumOption {
            switch opt.datum {
            case .data:   hasInlineDatum = true;  hasDatumHash = false
            case .datumHash: hasInlineDatum = false; hasDatumHash = true
            }
        } else if output.datumHash != nil {
            hasInlineDatum = false; hasDatumHash = true
        } else {
            hasInlineDatum = false; hasDatumHash = false
        }

        return OutputView(
            address: addressStr,
            lovelace: output.amount.coin,
            multiAsset: multiAsset,
            hasInlineDatum: hasInlineDatum,
            hasDatumHash: hasDatumHash,
            hasScriptRef: output.script != nil
        )
    }
}

// MARK: - Data hex helper

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
