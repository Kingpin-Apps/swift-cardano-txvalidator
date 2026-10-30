import BigInt
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
    public let validityStart: SlotNumber?

    /// Upper validity slot (TTL end / time-to-live).
    public let ttl: SlotNumber?

    // MARK: - Signers / Network

    /// Required signer key hashes (hex).
    public let requiredSigners: [String]

    /// Number of vkey witnesses.
    public let witnessCount: Int

    /// Network ID byte (0 = testnet, 1 = mainnet), if declared.
    public let networkId: Int?

    // MARK: - Mint

    /// Human-readable mint/burn policy map, if present.
    /// Keys are policy IDs (hex); values are `{ assetName: amount }`, a
    /// burn negative, each a ledger `Int64`.
    public let mint: [String: [String: Int64]]?

    // MARK: - Auxiliary

    /// Hex-encoded auxiliary data hash, if present.
    public let auxiliaryDataHash: String?

    // MARK: - Details

    /// The eras the transaction could have been written for, e.g. `babbage…conway`.
    public var possibleEras: String = ""
    /// Reward withdrawals.
    public var withdrawals: [WithdrawalView] = []
    /// Certificates, in body order.
    public var certificates: [CertificateView] = []
    /// Governance votes, in the ledger's voter order.
    public var votes: [VoteView] = []
    /// Governance proposals, in body order.
    public var proposals: [ProposalView] = []
    /// The treasury value the transaction asserts, lovelace (Conway).
    public var currentTreasuryAmount: UInt64? = nil
    /// The treasury donation, lovelace (Conway).
    public var treasuryDonation: UInt64? = nil
    /// Datums in the witness set.
    public var datums: [DatumView] = []
    /// Scripts in the witness set.
    public var scripts: [ScriptView] = []
    /// Redeemers, each with its tag and what it is for.
    public var redeemers: [RedeemerView] = []
}

// MARK: - Nested OutputView

public struct OutputView: Sendable, Codable, Equatable {
    /// Bech32 or hex address string.
    public let address: String
    /// ADA value in lovelace, a ledger `Word64`.
    public let lovelace: UInt64
    /// Multi-asset policy map `{ policyId: { assetName: amount } }`, if
    /// present. Each quantity is a ledger `Word64`.
    public let multiAsset: [String: [String: UInt64]]?
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

        let mint: [String: [String: Int64]]? = try body.mint.map { try quantities($0, "Mint") }

        let auxHashHex = body.auxiliaryDataHash.map { "\($0)" }

        // A transaction that spends via a reference script carries no script
        // in its witness set at all, so looking only there reported "no Plutus
        // scripts" for transactions that are nothing but a Plutus script call.
        // Redeemers are the reliable signal: they exist only to run one.
        let hasPlutusScripts =
            witnesses.plutusV1Script != nil ||
            witnesses.plutusV2Script != nil ||
            witnesses.plutusV3Script != nil ||
            redeemerCount > 0

        return TransactionView(
            txId: "\(try body.id)",
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
            auxiliaryDataHash: auxHashHex,
            possibleEras: tx.possibleEras.description,
            withdrawals: DetailViews.withdrawals(body),
            certificates: DetailViews.certificates(body),
            votes: DetailViews.votes(body),
            proposals: DetailViews.proposals(body),
            currentTreasuryAmount: body.currentTreasuryAmount,
            treasuryDonation: body.treasuryDonation.map { UInt64($0.value) },
            datums: DetailViews.datums(witnesses),
            scripts: DetailViews.scripts(witnesses),
            redeemers: DetailViews.redeemers(tx)
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

        let multiAsset: [String: [String: UInt64]]? = output.amount.multiAsset.data.isEmpty
            ? nil : try quantities(output.amount.multiAsset, "Output quantity")

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
            lovelace: try exactly(output.amount.coin, "Output lovelace"),
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

/// `value` as a `T`, or an error naming `what` when the ledger could not hold it.
private func exactly<T: FixedWidthInteger>(_ value: BigInt, _ what: String) throws -> T {
    guard let result = T(exactly: value) else {
        throw TxValidatorError.malformedCBOR("\(what) \(value) does not fit a ledger \(T.self)")
    }
    return result
}

/// A multi-asset's quantities as `{ policyId: { assetName: amount } }`.
private func quantities<T: FixedWidthInteger>(_ multiAsset: MultiAsset, _ what: String) throws -> [String: [String: T]] {
    try Dictionary(uniqueKeysWithValues: multiAsset.data.map { policyId, asset in
        ("\(policyId)", try Dictionary(uniqueKeysWithValues: asset.data.map { name, qty in
            (name.payload.hexEncodedString(), try exactly(qty, what) as T)
        }))
    })
}
