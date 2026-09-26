import Foundation
import CBORCodable
import SwiftCardanoCore
import SwiftNaCl

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
    /// - `redeemers_cbor`: canonical CBOR of the redeemers (map or list encoding);
    ///   `0xA0` (the empty map) when the witness set has no redeemers field —
    ///   this part is always present
    /// - `datums_cbor`: CBOR set (tag 258) of PlutusDatas from the witness set;
    ///   contributes *nothing* when there are no datums
    /// - `language_views_cbor`: cost models for only the Plutus versions actually used,
    ///   `0xA0` (empty map) if no redeemers — a Plutus script the transaction
    ///   actually needs always comes with a redeemer, so no redeemers means no
    ///   language to view
    /// - Parameters:
    ///   - witnessSet: The transaction's witness set.
    ///   - protocolParams: Protocol parameters supplying the cost models.
    ///   - transaction: The whole transaction. Required to work out which
    ///     reference scripts the transaction actually needs; without it only
    ///     witness-set scripts contribute to the language views.
    ///   - resolvedInputs: Resolved UTxOs for the transaction's spending,
    ///     collateral, and reference inputs — the only place a reference
    ///     script can be found.
    ///   - assumingUnresolvedInputsUseReferenceScripts: When a spending input
    ///     could not be resolved, its script hash is unknown, so a reference
    ///     script cannot be matched against it. Passing `true` counts every
    ///     Plutus reference script the transaction carries, which is the right
    ///     guess for a transaction whose inputs are already spent.
    public static func scriptDataHash(
        witnessSet: TransactionWitnessSet,
        protocolParams: ProtocolParameters,
        transaction: Transaction? = nil,
        resolvedInputs: [UTxO] = [],
        assumingUnresolvedInputsUseReferenceScripts: Bool = false
    ) throws -> ScriptDataHash {

        let costModels = try languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: protocolParams,
            transaction: transaction,
            resolvedInputs: resolvedInputs,
            assumingUnresolvedInputsUseReferenceScripts:
                assumingUnresolvedInputsUseReferenceScripts
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
        case .indefiniteNonEmptyOrderedSet(let list):
            // `#6.258` around an indefinite-length array: keep the form so the
            // datums re-encode to the bytes `script_data_hash` was built over.
            datums = .indefiniteNonEmptyOrderedSet(
                IndefiniteList(
                    list.map({ .plutusData($0) })
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
        // The ledger always hashes a redeemers value. A witness set that omits
        // the field decodes to the empty redeemer map, which still contributes
        // its `0xA0` — contributing nothing instead shifts the whole preimage
        // and makes every datum-carrying, redeemer-free transaction (one that
        // only *sends* to a script address) look like a hash mismatch.
        let redeemerBytes = try (redeemers ?? .map(RedeemerMap())).toCBORData()
        
        return ScriptDataHash(
            payload: try SwiftNaCl.Hash().blake2b(
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
        protocolParams: ProtocolParameters,
        transaction: Transaction? = nil,
        resolvedInputs: [UTxO] = [],
        assumingUnresolvedInputsUseReferenceScripts: Bool = false
    ) throws -> [Int: [Int64]] {

        // Plutus versions carried directly in the witness set.
        var versions = Set<Int>()
        if witnessSet.plutusV1Script != nil { versions.insert(1) }
        if witnessSet.plutusV2Script != nil { versions.insert(2) }
        if witnessSet.plutusV3Script != nil { versions.insert(3) }

        // Plutus versions supplied by reference scripts. A transaction that
        // spends from a script address using a reference script carries no
        // script in its witness set at all, so skipping these leaves the
        // language views empty and the recomputed hash wrong.
        //
        // Only scripts the transaction actually needs count — a reference
        // input included solely to read its datum must not drag its script's
        // language into the hash.
        if !resolvedInputs.isEmpty, let transaction {
            let required = requiredScriptHashes(
                transaction: transaction,
                resolvedInputs: resolvedInputs
            )
            // An input we could not resolve has an unknown address, so its
            // script hash never reaches `required` and a reference script that
            // satisfies it would be filtered out here — leaving the language
            // views empty and the recomputed hash wrong. That is why the caller
            // can ask for those reference scripts to be counted anyway.
            let inputsAreComplete = unresolvedSpendingInputs(
                transaction: transaction, resolvedInputs: resolvedInputs
            ).isEmpty
            let countEveryReferenceScript =
                assumingUnresolvedInputsUseReferenceScripts && !inputsAreComplete

            for utxo in resolvedInputs {
                guard let script = utxo.output.script,
                      let version = plutusVersion(of: script),
                      let hash = try? scriptHash(script: script),
                      countEveryReferenceScript || required.contains(hash.payload.toHex)
                else { continue }
                versions.insert(version)
            }
        }

        var costModels: [Int: [Int64]] = [:]
        for version in versions.sorted() {
            // A nil cost model removes the key, matching the ledger's
            // behaviour of only viewing languages it knows about.
            costModels[version - 1] = protocolParams.costModels.getVersion(version)
        }

        return costModels
    }

    /// Spending inputs with no resolved UTxO behind them.
    ///
    /// These are the inputs whose addresses — and so whose script hashes — are
    /// unknown, which is what makes the language views uncertain. Collateral and
    /// reference inputs are not included: neither contributes a script hash that
    /// the transaction is required to satisfy.
    /// The size of a transaction as the ledger measures it for its fee and
    /// against the maximum transaction size.
    ///
    /// From Alonzo on, a transaction is written `[body, witnesses, isValid,
    /// auxiliary data]`, but the ledger sizes it without the one-byte
    /// `isValid` flag, as the three-element shape earlier eras used — so the
    /// fee does not change with the flag. Shelley to Mary transactions are
    /// sized as written.
    public static func feeRelevantSize(of transaction: Transaction) throws -> Int {
        let bytes = try transaction.toCBORData()
        return bytes.first == 0x84 ? bytes.count - 1 : bytes.count
    }

    public static func unresolvedSpendingInputs(
        transaction: Transaction?,
        resolvedInputs: [UTxO]
    ) -> [TransactionInput] {
        guard let transaction else { return [] }
        let resolved = Set(
            resolvedInputs.map { "\($0.input.transactionId)#\($0.input.index)" }
        )
        return transaction.transactionBody.inputs.asArray.filter {
            !resolved.contains("\($0.transactionId)#\($0.index)")
        }
    }

    /// The Plutus language version of a script, or `nil` for native scripts.
    public static func plutusVersion(of script: ScriptType) -> Int? {
        switch script {
        case .plutusV1Script: return 1
        case .plutusV2Script: return 2
        case .plutusV3Script: return 3
        case .nativeScript:   return nil
        }
    }

    /// Hex-encoded hashes of every script the transaction needs in order to
    /// validate: script-locked spending inputs, minting policies, script
    /// stake credentials in withdrawals and certificates, and script voters.
    ///
    /// The script itself may live in the witness set or in a reference input.
    public static func requiredScriptHashes(
        transaction: Transaction,
        resolvedInputs: [UTxO] = []
    ) -> Set<String> {
        let body = transaction.transactionBody
        var hashes = Set<String>()

        // Script-locked spending inputs.
        let resolvedMap: [String: TransactionOutput] = Dictionary(
            resolvedInputs.map { ("\($0.input.transactionId)#\($0.input.index)", $0.output) },
            uniquingKeysWith: { first, _ in first }
        )
        for input in body.inputs.asArray {
            let key = "\(input.transactionId)#\(input.index)"
            guard let output = resolvedMap[key],
                  case .scriptHash(let sh)? = output.address.paymentPart
            else { continue }
            hashes.insert(sh.payload.toHex)
        }

        // Minting policies are script hashes by definition.
        if let mint = body.mint {
            for policyId in mint.data.keys {
                hashes.insert(policyId.payload.toHex)
            }
        }

        // Withdrawals from script-controlled reward accounts. A reward address
        // is a 1-byte header followed by the credential; the header's low bit
        // of the type nibble is set when that credential is a script.
        if let withdrawals = body.withdrawals {
            for rewardAccount in withdrawals.data.keys {
                guard let header = rewardAccount.first, (header & 0x10) != 0 else { continue }
                hashes.insert(rewardAccount.dropFirst().toHex)
            }
        }

        // Script stake credentials in certificates.
        if let certificates = body.certificates {
            for cert in certificates.asList {
                guard let credential = certificateStakeCredential(cert) else { continue }
                if case .scriptHash(let sh) = credential.credential {
                    hashes.insert(sh.payload.toHex)
                }
            }
        }

        // Script voters (constitutional committee hot script / DRep script).
        if let votingProcedures = body.votingProcedures {
            for voter in votingProcedures.voters {
                switch voter.credential {
                case .constitutionalCommitteeHotScriptHash(let sh), .drepScriptHash(let sh):
                    hashes.insert(sh.payload.toHex)
                default:
                    break
                }
            }
        }

        return hashes
    }

    private static func certificateStakeCredential(_ cert: Certificate) -> StakeCredential? {
        switch cert {
        case .stakeRegistration(let c):           return c.stakeCredential
        case .stakeDeregistration(let c):         return c.stakeCredential
        case .stakeDelegation(let c):             return c.stakeCredential
        case .register(let c):                    return c.stakeCredential
        case .unregister(let c):                  return c.stakeCredential
        case .voteDelegate(let c):                return c.stakeCredential
        case .stakeVoteDelegate(let c):           return c.stakeCredential
        case .stakeRegisterDelegate(let c):       return c.stakeCredential
        case .voteRegisterDelegate(let c):        return c.stakeCredential
        case .stakeVoteRegisterDelegate(let c):   return c.stakeCredential
        default:                                  return nil
        }
    }
}
