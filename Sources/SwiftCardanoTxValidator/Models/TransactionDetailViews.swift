import Foundation
import SwiftCardanoCore
import SwiftCardanoUPLC

// Detail views of a transaction's certificates, withdrawals, governance,
// datums, scripts and redeemers, flattened to strings for display and export
// like the rest of ``TransactionView``.

/// A reward withdrawal.
public struct WithdrawalView: Sendable, Codable, Equatable {
    /// The reward address (bech32 when it can be encoded, hex otherwise).
    public let rewardAddress: String
    /// `key` or `script`: what the reward credential is.
    public let credentialKind: String
    public let lovelace: UInt64
}

/// A certificate.
public struct CertificateView: Sendable, Codable, Equatable {
    /// Its position in the body's certificate list — a `cert` redeemer's index.
    public let index: Int
    /// The certificate kind, e.g. `stakeRegistration`, `registerDRep`.
    public let kind: String
    /// Plain-language summary.
    public let summary: String
    /// The stake, DRep or committee credential it acts on, as `key:<hex>` or
    /// `script:<hex>`.
    public let credential: String?
    /// The pool it names, hex.
    public let pool: String?
    /// The DRep it delegates to.
    public let drep: String?
    /// The deposit it takes (positive) or refunds (negative), when it states one.
    public let deposit: Int64?
    public let anchorURL: String?
    public let anchorHash: String?
}

/// A governance vote.
public struct VoteView: Sendable, Codable, Equatable {
    /// `committee`, `drep` or `spo`.
    public let voterRole: String
    /// The voter's credential, as `key:<hex>` or `script:<hex>`.
    public let voter: String
    /// The action voted on, `<tx id>#<index>`.
    public let govActionId: String
    /// `yes`, `no` or `abstain`.
    public let vote: String
    public let anchorURL: String?
    public let anchorHash: String?
}

/// A governance proposal.
public struct ProposalView: Sendable, Codable, Equatable {
    /// Its position in the body — a `proposing` redeemer's index, and the
    /// action's index in its id `<this tx id>#<index>`.
    public let index: Int
    /// The action type, e.g. `parameterChange`, `treasuryWithdrawals`, `info`.
    public let actionType: String
    public let deposit: UInt64
    /// The deposit return address, hex.
    public let returnAddress: String
    public let anchorURL: String
    public let anchorHash: String
}

/// A datum in the witness set.
public struct DatumView: Sendable, Codable, Equatable {
    /// Blake2b-256 of its CBOR, hex.
    public let hash: String
    public let cborHex: String
}

/// A script in the witness set.
public struct ScriptView: Sendable, Codable, Equatable {
    /// Blake2b-224 script hash, hex.
    public let hash: String
    /// `native`, `plutusV1`, `plutusV2` or `plutusV3`.
    public let language: String
    /// Serialized size in bytes.
    public let size: Int
}

/// A redeemer, with what it is for.
public struct RedeemerView: Sendable, Codable, Equatable {
    /// Its position in the witness set, as Phase-2 results number it.
    public let position: Int
    /// `spend`, `mint`, `cert`, `reward`, `voting` or `proposing`.
    public let tag: String
    /// The index the redeemer declares, into the ledger's ordering for its tag.
    public let index: Int
    /// What the index points at: the spent input `<tx id>#<i>`, the minting
    /// policy, the withdrawal's reward account, `certificate[<i>]`, the voter,
    /// or `proposal[<i>]` — or `nil` when the index is out of range.
    public let purpose: String?
    public let dataCBORHex: String
    public let exUnits: ExUnitsView?
}

// MARK: - Building

enum DetailViews {
    static func credential(_ credential: CredentialType) -> String {
        switch credential {
        case .verificationKeyHash(let hash): return "key:\(hash.payload.toHex)"
        case .scriptHash(let hash): return "script:\(hash.payload.toHex)"
        }
    }

    static func withdrawals(_ body: TransactionBody) -> [WithdrawalView] {
        body.withdrawals?.data.map { account, coin in
            let address = (try? Address(from: .bytes(account)).toBech32()) ?? account.toHex
            let isScript = (account.first ?? 0) & 0x10 != 0
            return WithdrawalView(rewardAddress: address, credentialKind: isScript ? "script" : "key", lovelace: coin)
        } ?? []
    }

    static func certificates(_ body: TransactionBody) -> [CertificateView] {
        (body.certificates?.asList ?? []).enumerated().map { index, certificate in
            certificateView(index: index, certificate)
        }
    }

    static func certificateView(index: Int, _ certificate: Certificate) -> CertificateView {
        func view(
            _ kind: String, _ summary: String, credential: CredentialType? = nil, pool: PoolKeyHash? = nil,
            drep: DRep? = nil, deposit: Int64? = nil, anchor: Anchor? = nil
        ) -> CertificateView {
            CertificateView(
                index: index, kind: kind, summary: summary,
                credential: credential.map(Self.credential), pool: pool?.payload.toHex,
                drep: drep.map { "\($0)" }, deposit: deposit,
                anchorURL: anchor.map { "\($0.anchorUrl)" }, anchorHash: anchor?.anchorDataHash.payload.toHex
            )
        }
        switch certificate {
        case .stakeRegistration(let c):
            return view("stakeRegistration", "Register a stake credential", credential: c.stakeCredential.credential)
        case .stakeDeregistration(let c):
            return view("stakeDeregistration", "Deregister a stake credential", credential: c.stakeCredential.credential)
        case .stakeDelegation(let c):
            return view("stakeDelegation", "Delegate stake to a pool", credential: c.stakeCredential.credential, pool: c.poolKeyHash)
        case .poolRegistration(let c):
            let p = c.poolParams
            return view("poolRegistration", "Register or update a pool (pledge \(p.pledge), cost \(p.cost))", pool: p.poolOperator)
        case .poolRetirement(let c):
            return view("poolRetirement", "Retire a pool at epoch \(c.epoch)", pool: c.poolKeyHash)
        case .genesisKeyDelegation:
            return view("genesisKeyDelegation", "Delegate a genesis key")
        case .moveInstantaneousRewards:
            return view("moveInstantaneousRewards", "Move instantaneous rewards")
        case .register(let c):
            return view("register", "Register a stake credential", credential: c.stakeCredential.credential, deposit: Int64(c.coin))
        case .unregister(let c):
            return view("unregister", "Deregister a stake credential", credential: c.stakeCredential.credential, deposit: -Int64(c.coin))
        case .voteDelegate(let c):
            return view("voteDelegate", "Delegate votes to a DRep", credential: c.stakeCredential.credential, drep: c.drep)
        case .stakeVoteDelegate(let c):
            return view("stakeVoteDelegate", "Delegate stake to a pool and votes to a DRep",
                        credential: c.stakeCredential.credential, pool: c.poolKeyHash, drep: c.drep)
        case .stakeRegisterDelegate(let c):
            return view("stakeRegisterDelegate", "Register and delegate stake to a pool",
                        credential: c.stakeCredential.credential, pool: c.poolKeyHash, deposit: Int64(c.coin))
        case .voteRegisterDelegate(let c):
            return view("voteRegisterDelegate", "Register and delegate votes to a DRep",
                        credential: c.stakeCredential.credential, drep: c.drep, deposit: Int64(c.coin))
        case .stakeVoteRegisterDelegate(let c):
            return view("stakeVoteRegisterDelegate", "Register, delegate stake to a pool and votes to a DRep",
                        credential: c.stakeCredential.credential, pool: c.poolKeyHash, drep: c.drep, deposit: Int64(c.coin))
        case .authCommitteeHot(let c):
            return view("authCommitteeHot", "Authorize a committee hot key (hot \(Self.credential(c.committeeHotCredential.credential)))",
                        credential: c.committeeColdCredential.credential)
        case .resignCommitteeCold(let c):
            return view("resignCommitteeCold", "Resign from the constitutional committee",
                        credential: c.committeeColdCredential.credential, anchor: c.anchor)
        case .registerDRep(let c):
            return view("registerDRep", "Register as a DRep", credential: c.drepCredential.credential,
                        deposit: Int64(c.coin), anchor: c.anchor)
        case .unRegisterDRep(let c):
            return view("unRegisterDRep", "Retire as a DRep", credential: c.drepCredential.credential, deposit: -Int64(c.coin))
        case .updateDRep(let c):
            return view("updateDRep", "Update a DRep's metadata", credential: c.drepCredential.credential, anchor: c.anchor)
        }
    }

    static func voterRole(_ voter: Voter) -> (role: String, credential: String) {
        switch voter.credential {
        case .constitutionalCommitteeHotKeyhash(let h): return ("committee", "key:\(h.payload.toHex)")
        case .constitutionalCommitteeHotScriptHash(let h): return ("committee", "script:\(h.payload.toHex)")
        case .drepKeyhash(let h): return ("drep", "key:\(h.payload.toHex)")
        case .drepScriptHash(let h): return ("drep", "script:\(h.payload.toHex)")
        case .stakePoolKeyhash(let h): return ("spo", "key:\(h.payload.toHex)")
        }
    }

    static func govActionId(_ id: GovActionID) -> String {
        "\(id.transactionID.payload.toHex)#\(id.govActionIndex)"
    }

    static func votes(_ body: TransactionBody) -> [VoteView] {
        guard let procedures = body.votingProcedures else { return [] }
        return orderedVoters(procedures).flatMap { voter -> [VoteView] in
            let (role, credential) = voterRole(voter)
            let byAction = procedures[voter] ?? [:]
            return byAction.keys.sorted {
                ($0.transactionID.payload, $0.govActionIndex) < ($1.transactionID.payload, $1.govActionIndex)
            }.map { id in
                let procedure = byAction[id]!
                let vote: String
                switch procedure.vote {
                case .yes: vote = "yes"
                case .no: vote = "no"
                case .abstain: vote = "abstain"
                }
                return VoteView(
                    voterRole: role, voter: credential, govActionId: govActionId(id), vote: vote,
                    anchorURL: procedure.anchor.map { "\($0.anchorUrl)" },
                    anchorHash: procedure.anchor?.anchorDataHash.payload.toHex
                )
            }
        }
    }

    static func proposals(_ body: TransactionBody) -> [ProposalView] {
        (body.proposalProcedures?.elementsOrdered ?? []).enumerated().map { index, proposal in
            let type: String
            switch proposal.govAction {
            case .parameterChangeAction: type = "parameterChange"
            case .hardForkInitiationAction: type = "hardForkInitiation"
            case .treasuryWithdrawalsAction: type = "treasuryWithdrawals"
            case .noConfidence: type = "noConfidence"
            case .updateCommittee: type = "updateCommittee"
            case .newConstitution: type = "newConstitution"
            case .infoAction: type = "info"
            }
            return ProposalView(
                index: index, actionType: type, deposit: proposal.deposit,
                returnAddress: proposal.rewardAccount.toHex,
                anchorURL: "\(proposal.anchor.anchorUrl)",
                anchorHash: proposal.anchor.anchorDataHash.payload.toHex
            )
        }
    }

    static func datums(_ witnesses: TransactionWitnessSet) -> [DatumView] {
        (witnesses.plutusData?.asList ?? []).compactMap { datum -> DatumView? in
            guard let cbor = try? datum.toCBORData() else { return nil }
            let hash = (try? Utils.blake2b256(cbor))?.toHex ?? ""
            return DatumView(hash: hash, cborHex: cbor.toHex)
        }
    }

    static func scripts(_ witnesses: TransactionWitnessSet) -> [ScriptView] {
        var scripts: [(ScriptType, String, Int)] = []
        for s in witnesses.nativeScripts?.asList ?? [] {
            scripts.append((.nativeScript(s), "native", (try? s.toCBORData().count) ?? 0))
        }
        for s in witnesses.plutusV1Script?.asList ?? [] { scripts.append((.plutusV1Script(s), "plutusV1", s.data.count)) }
        for s in witnesses.plutusV2Script?.asList ?? [] { scripts.append((.plutusV2Script(s), "plutusV2", s.data.count)) }
        for s in witnesses.plutusV3Script?.asList ?? [] { scripts.append((.plutusV3Script(s), "plutusV3", s.data.count)) }
        return scripts.map { script, language, size in
            ScriptView(hash: (try? scriptHash(script: script))?.payload.toHex ?? "", language: language, size: size)
        }
    }

    static func redeemers(_ transaction: Transaction) -> [RedeemerView] {
        let body = transaction.transactionBody
        let sortedInputs = body.inputs.asArray.sorted {
            ($0.transactionId.payload, $0.index) < ($1.transactionId.payload, $1.index)
        }
        let sortedPolicies = (body.mint.map { Array($0.data.keys) } ?? []).sorted {
            $0.payload.lexicographicallyPrecedes($1.payload)
        }
        let withdrawals = orderedWithdrawals(body.withdrawals)
        let certificates = body.certificates?.asList ?? []
        let voters = body.votingProcedures.map(orderedVoters) ?? []
        let proposalCount = body.proposalProcedures?.elementsOrdered.count ?? 0

        return PhaseTwo.redeemers(of: transaction).enumerated().map { position, redeemer in
            let i = redeemer.index
            let purpose: String?
            let tag: String
            switch redeemer.tag {
            case .spend?:
                tag = "spend"
                purpose = sortedInputs.indices.contains(i)
                    ? "\(sortedInputs[i].transactionId.payload.toHex)#\(sortedInputs[i].index)" : nil
            case .mint?:
                tag = "mint"
                purpose = sortedPolicies.indices.contains(i) ? sortedPolicies[i].payload.toHex : nil
            case .cert?:
                tag = "cert"
                purpose = certificates.indices.contains(i) ? "certificate[\(i)]" : nil
            case .reward?:
                tag = "reward"
                purpose = withdrawals.indices.contains(i) ? withdrawals[i] : nil
            case .voting?:
                tag = "voting"
                purpose = voters.indices.contains(i) ? voterRole(voters[i]).credential : nil
            case .proposing?:
                tag = "proposing"
                purpose = i < proposalCount ? "proposal[\(i)]" : nil
            case nil:
                tag = "unknown"
                purpose = nil
            }
            return RedeemerView(
                position: position, tag: tag, index: i, purpose: purpose,
                dataCBORHex: (try? redeemer.data.toCBORData())?.toHex ?? "",
                exUnits: redeemer.exUnits.map { ExUnitsView(memory: Int64($0.mem), steps: Int64($0.steps)) }
            )
        }
    }

    /// Reward accounts in the ledger's order — script credentials before key
    /// credentials, then by hash — which a `reward` redeemer's index counts
    /// through.
    static func orderedWithdrawals(_ withdrawals: Withdrawals?) -> [String] {
        (withdrawals?.data.keys.map { $0 } ?? []).sorted { lhs, rhs in
            let lhsScript = (lhs.first ?? 0) & 0x10 != 0
            let rhsScript = (rhs.first ?? 0) & 0x10 != 0
            if lhsScript != rhsScript { return lhsScript }
            return lhs.dropFirst().lexicographicallyPrecedes(rhs.dropFirst())
        }.map { account in (try? Address(from: .bytes(account)).toBech32()) ?? account.toHex }
    }

    /// Voters in the ledger's order — committee, then DReps, then pools;
    /// scripts before keys within a role; then by hash — which a `voting`
    /// redeemer's index counts through.
    static func orderedVoters(_ procedures: VotingProcedures) -> [Voter] {
        func key(_ voter: Voter) -> (role: Int, isKey: Bool, hash: Data) {
            switch voter.credential {
            case .constitutionalCommitteeHotScriptHash(let h): return (0, false, h.payload)
            case .constitutionalCommitteeHotKeyhash(let h): return (0, true, h.payload)
            case .drepScriptHash(let h): return (1, false, h.payload)
            case .drepKeyhash(let h): return (1, true, h.payload)
            case .stakePoolKeyhash(let h): return (2, true, h.payload)
            }
        }
        return procedures.voters.sorted { lhs, rhs in
            let (l, r) = (key(lhs), key(rhs))
            if l.role != r.role { return l.role < r.role }
            if l.isKey != r.isKey { return !l.isKey }
            return l.hash.lexicographicallyPrecedes(r.hash)
        }
    }
}

private func < (lhs: (Data, UInt16), rhs: (Data, UInt16)) -> Bool {
    lhs.0 != rhs.0 ? lhs.0.lexicographicallyPrecedes(rhs.0) : lhs.1 < rhs.1
}
