import Foundation
import SwiftCardanoCore

// MARK: - NecessaryData

/// The complete set of chain state that a caller must fetch before running full validation.
///
/// Call `TxValidator.necessaryData(cborHex:)` to obtain this from a raw transaction.
/// Use the returned values to populate `ValidationContext` fields before calling `validate()`.
public struct NecessaryData: Sendable, Codable {

    /// All UTxOs the transaction references (spending inputs + collateral + reference inputs).
    /// Fetch these from the ledger before validation.
    public let inputs: [TransactionInputRef]

    /// Reward account addresses involved via withdrawals or certificate stake credentials.
    /// Fetch stake balances and DRep delegation state for each.
    public let rewardAccounts: [String]

    /// Pool key hashes referenced by delegation or registration certificates.
    /// Fetch pool registration state for each.
    public let stakePools: [String]

    /// DRep identifiers referenced by vote-delegation certificates.
    /// Fetch DRep registration state for each.
    public let dReps: [String]

    /// Governance action IDs that this transaction votes on or references as previous actions.
    /// Fetch governance action state for each.
    public let govActionIds: [GovActionIdRef]

    /// Governance action types for which the last enacted action must be fetched.
    /// Populate `ValidationContext.lastEnactedGovAction` with one entry per type.
    public let lastEnactedGovActionTypes: [GovActionType]

    public init(
        inputs: [TransactionInputRef],
        rewardAccounts: [String],
        stakePools: [String],
        dReps: [String],
        govActionIds: [GovActionIdRef],
        lastEnactedGovActionTypes: [GovActionType] = [],
        committeeMembersCold: [String],
        committeeMembersHot: [String]
    ) {
        self.inputs = inputs
        self.rewardAccounts = rewardAccounts
        self.stakePools = stakePools
        self.dReps = dReps
        self.govActionIds = govActionIds
        self.lastEnactedGovActionTypes = lastEnactedGovActionTypes
        self.committeeMembersCold = committeeMembersCold
        self.committeeMembersHot = committeeMembersHot
    }

    /// Committee cold credentials referenced by `authCommitteeHot` / `resignCommitteeCold` certs.
    /// Fetch committee member state for each.
    public let committeeMembersCold: [String]

    /// Committee hot credentials referenced by `authCommitteeHot` certs.
    /// Fetch committee member state for each.
    public let committeeMembersHot: [String]
}

// MARK: - TransactionInputRef

/// A lightweight, serialisable reference to a UTxO.
public struct TransactionInputRef: Sendable, Codable, Equatable, Hashable {
    /// Transaction hash (hex).
    public let transactionId: String
    /// Output index within the transaction.
    public let index: UInt16

    public init(transactionId: String, index: UInt16) {
        self.transactionId = transactionId
        self.index = index
    }
}

// MARK: - GovActionIdRef

/// A lightweight, serialisable governance action identifier.
public struct GovActionIdRef: Sendable, Codable, Equatable, Hashable {
    /// Transaction hash of the proposal (hex).
    public let transactionId: String
    /// Index within that transaction.
    public let govActionIndex: UInt16

    public init(transactionId: String, govActionIndex: UInt16) {
        self.transactionId = transactionId
        self.govActionIndex = govActionIndex
    }
}

// MARK: - NecessaryData builder

extension NecessaryData {
    /// Build `NecessaryData` by inspecting the transaction body.
    ///
    /// No chain state is required; the data is derived purely from the tx structure.
    static func from(_ transaction: Transaction) -> NecessaryData {
        let body = transaction.transactionBody

        // ── UTxO inputs ──────────────────────────────────────────────────────────
        var inputSet: [TransactionInputRef] = []
        var seen = Set<String>()

        func addInput(_ txInput: TransactionInput) {
            let key = "\(txInput.transactionId)#\(txInput.index)"
            guard seen.insert(key).inserted else { return }
            inputSet.append(TransactionInputRef(
                transactionId: "\(txInput.transactionId)",
                index: txInput.index
            ))
        }

        for inp in body.inputs.asArray         { addInput(inp) }
        if let coll = body.collateral          { for inp in coll.asList { addInput(inp) } }
        if let refs = body.referenceInputs     { for inp in refs.asList { addInput(inp) } }

        // ── Reward accounts ──────────────────────────────────────────────────────
        var rewardAccounts: [String] = []
        var rewardAccountSeen = Set<String>()

        func addRewardAccount(_ s: String) {
            guard rewardAccountSeen.insert(s).inserted else { return }
            rewardAccounts.append(s)
        }

        // From withdrawals
        if let withdrawals = body.withdrawals {
            for rewardAccount in withdrawals.data.keys {
                addRewardAccount("\(rewardAccount)")
            }
        }

        // From certificates (stake credentials)
        if let certs = body.certificates {
            for cert in certs.asList {
                if let cred = stakeCredential(from: cert) {
                    addRewardAccount("\(cred)")
                }
            }
        }

        // ── Stake pools ──────────────────────────────────────────────────────────
        var stakePools: [String] = []
        var stakePoolSeen = Set<String>()

        func addPool(_ s: String) {
            guard stakePoolSeen.insert(s).inserted else { return }
            stakePools.append(s)
        }

        if let certs = body.certificates {
            for cert in certs.asList {
                if let pool = poolKeyHash(from: cert) {
                    addPool("\(pool)")
                }
            }
        }

        // ── DReps ────────────────────────────────────────────────────────────────
        var dReps: [String] = []
        var dRepSeen = Set<String>()

        func addDRep(_ s: String) {
            guard dRepSeen.insert(s).inserted else { return }
            dReps.append(s)
        }

        if let certs = body.certificates {
            for cert in certs.asList {
                if let drep = dRepId(from: cert) {
                    addDRep(drep)
                }
            }
        }

        // ── Governance action IDs ────────────────────────────────────────────────
        var govActionIds: [GovActionIdRef] = []
        var govActionSeen = Set<String>()

        func addGovActionId(_ govActionId: GovActionID) {
            let key = "\(govActionId.transactionID)#\(govActionId.govActionIndex)"
            guard govActionSeen.insert(key).inserted else { return }
            govActionIds.append(GovActionIdRef(
                transactionId: "\(govActionId.transactionID)",
                govActionIndex: govActionId.govActionIndex
            ))
        }

        if let votingProcedures = body.votingProcedures {
            for (_, govActionId, _) in votingProcedures.allVotes {
                addGovActionId(govActionId)
            }
        }

        // Extract previous action IDs referenced by proposals
        if let proposals = body.proposalProcedures {
            for proposal in proposals.elementsOrdered {
                switch proposal.govAction {
                case .parameterChangeAction(let a):
                    if let id = a.id { addGovActionId(id) }
                case .hardForkInitiationAction(let a):
                    if let id = a.id { addGovActionId(id) }
                case .noConfidence(let a):
                    addGovActionId(a.id)
                case .updateCommittee(let a):
                    if let id = a.id { addGovActionId(id) }
                case .newConstitution(let a):
                    addGovActionId(a.id)
                case .treasuryWithdrawalsAction, .infoAction:
                    break
                }
            }
        }

        // ── Last enacted gov action types ────────────────────────────────────────
        var lastEnactedGovActionTypes: [GovActionType] = []
        var lastEnactedSeen = Set<GovActionType>()

        if let proposals = body.proposalProcedures {
            for proposal in proposals.elementsOrdered {
                let actionType: GovActionType
                switch proposal.govAction {
                case .parameterChangeAction:   actionType = .parameterChange
                case .hardForkInitiationAction: actionType = .hardForkInitiation
                case .treasuryWithdrawalsAction: actionType = .treasuryWithdrawals
                case .noConfidence:            actionType = .noConfidence
                case .updateCommittee:         actionType = .updateCommittee
                case .newConstitution:         actionType = .newConstitution
                case .infoAction:              actionType = .info
                }
                if lastEnactedSeen.insert(actionType).inserted {
                    lastEnactedGovActionTypes.append(actionType)
                }
            }
        }

        // ── Committee members ──────────────────────────────────────────────────
        var committeeMembersCold: [String] = []
        var committeeMembersHot: [String] = []
        var committeeColdSeen = Set<String>()
        var committeeHotSeen = Set<String>()

        if let certs = body.certificates {
            for cert in certs.asList {
                switch cert {
                case .authCommitteeHot(let c):
                    let coldStr = "\(c.committeeColdCredential)"
                    let hotStr = "\(c.committeeHotCredential)"
                    if committeeColdSeen.insert(coldStr).inserted {
                        committeeMembersCold.append(coldStr)
                    }
                    if committeeHotSeen.insert(hotStr).inserted {
                        committeeMembersHot.append(hotStr)
                    }
                case .resignCommitteeCold(let c):
                    let coldStr = "\(c.committeeColdCredential)"
                    if committeeColdSeen.insert(coldStr).inserted {
                        committeeMembersCold.append(coldStr)
                    }
                default:
                    break
                }
            }
        }

        return NecessaryData(
            inputs: inputSet,
            rewardAccounts: rewardAccounts,
            stakePools: stakePools,
            dReps: dReps,
            govActionIds: govActionIds,
            lastEnactedGovActionTypes: lastEnactedGovActionTypes,
            committeeMembersCold: committeeMembersCold,
            committeeMembersHot: committeeMembersHot
        )
    }

    // MARK: - Certificate field extractors

    private static func stakeCredential(from cert: Certificate) -> StakeCredential? {
        switch cert {
        case .stakeRegistration(let c):              return c.stakeCredential
        case .stakeDeregistration(let c):            return c.stakeCredential
        case .stakeDelegation(let c):                return c.stakeCredential
        case .register(let c):                       return c.stakeCredential
        case .unregister(let c):                     return c.stakeCredential
        case .voteDelegate(let c):                   return c.stakeCredential
        case .stakeVoteDelegate(let c):              return c.stakeCredential
        case .stakeRegisterDelegate(let c):          return c.stakeCredential
        case .voteRegisterDelegate(let c):           return c.stakeCredential
        case .stakeVoteRegisterDelegate(let c):      return c.stakeCredential
        default:                                     return nil
        }
    }

    private static func poolKeyHash(from cert: Certificate) -> PoolKeyHash? {
        switch cert {
        case .stakeDelegation(let c):                return c.poolKeyHash
        case .stakeVoteDelegate(let c):              return c.poolKeyHash
        case .stakeRegisterDelegate(let c):          return c.poolKeyHash
        case .stakeVoteRegisterDelegate(let c):      return c.poolKeyHash
        case .poolRegistration(let c):               return c.poolParams.poolOperator
        case .poolRetirement(let c):                 return c.poolKeyHash
        default:                                     return nil
        }
    }

    private static func dRepId(from cert: Certificate) -> String? {
        switch cert {
        case .voteDelegate(let c):                   return "\(c.drep)"
        case .stakeVoteDelegate(let c):              return "\(c.drep)"
        case .voteRegisterDelegate(let c):           return "\(c.drep)"
        case .stakeVoteRegisterDelegate(let c):      return "\(c.drep)"
        case .registerDRep(let c):                   return "\(c.drepCredential)"
        case .unRegisterDRep(let c):                 return "\(c.drepCredential)"
        case .updateDRep(let c):                     return "\(c.drepCredential)"
        default:                                     return nil
        }
    }
}
