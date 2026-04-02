import Foundation
import SwiftCardanoCore

/// Extra context that validation rules may need beyond the transaction itself.
///
/// Pass this when calling `Phase1Validator.validate` or individual rules.
/// All fields are optional — rules gracefully skip checks they can't perform
/// without the relevant context.
public struct ValidationContext: Sendable {
    /// Resolved UTxOs for the transaction's spending inputs.
    /// Required by `BalanceRule`. Without these, balance is not checked.
    public let resolvedInputs: [UTxO]

    /// Current ledger slot, used by `ValidityIntervalRule`.
    /// If `nil`, the validity interval is not checked.
    public let currentSlot: UInt64?

    /// The network the transaction is intended for.
    /// Used by `NetworkIdRule`. If `nil`, network-ID checks are skipped.
    public let network: NetworkId?

    // MARK: - Chain-state context (Batch 6)

    /// Stake / reward account state from the ledger.
    public let accountContexts: [AccountInputContext]

    /// Stake pool registration state from the ledger.
    public let poolContexts: [PoolInputContext]

    /// DRep registration state from the ledger.
    public let drepContexts: [DRepInputContext]

    /// Governance action state from the ledger.
    public let govActionContexts: [GovActionInputContext]

    /// Last enacted governance action per type.
    public let lastEnactedGovAction: [GovActionInputContext]

    /// Current constitutional committee members.
    public let currentCommitteeMembers: [CommitteeInputContext]

    /// Potential (proposed) constitutional committee members.
    public let potentialCommitteeMembers: [CommitteeInputContext]

    /// Treasury balance in lovelace, used for treasury value mismatch check.
    public let treasuryValue: UInt64?

    /// Current epoch, used by `RegistrationRule` for pool retirement bounds.
    public let currentEpoch: UInt64?

    /// The transaction era. When set, rules skip era-inappropriate checks.
    /// If `nil`, Conway is assumed (backward-compatible default).
    public let era: Era?

    public init(
        resolvedInputs: [UTxO] = [],
        currentSlot: UInt64? = nil,
        network: NetworkId? = nil,
        accountContexts: [AccountInputContext] = [],
        poolContexts: [PoolInputContext] = [],
        drepContexts: [DRepInputContext] = [],
        govActionContexts: [GovActionInputContext] = [],
        lastEnactedGovAction: [GovActionInputContext] = [],
        currentCommitteeMembers: [CommitteeInputContext] = [],
        potentialCommitteeMembers: [CommitteeInputContext] = [],
        treasuryValue: UInt64? = nil,
        currentEpoch: UInt64? = nil,
        era: Era? = nil
    ) {
        self.resolvedInputs = resolvedInputs
        self.currentSlot = currentSlot
        self.network = network
        self.accountContexts = accountContexts
        self.poolContexts = poolContexts
        self.drepContexts = drepContexts
        self.govActionContexts = govActionContexts
        self.lastEnactedGovAction = lastEnactedGovAction
        self.currentCommitteeMembers = currentCommitteeMembers
        self.potentialCommitteeMembers = potentialCommitteeMembers
        self.treasuryValue = treasuryValue
        self.currentEpoch = currentEpoch
        self.era = era
    }

    // MARK: - Finder methods

    /// Look up account context by reward address string.
    public func findAccountContext(rewardAddress: String) -> AccountInputContext? {
        accountContexts.first { $0.rewardAddress == rewardAddress }
    }

    /// Look up pool context by pool key hash (hex).
    public func findPoolContext(poolId: String) -> PoolInputContext? {
        poolContexts.first { $0.poolId == poolId }
    }

    /// Look up DRep context by DRep ID string.
    public func findDRepContext(drepId: String) -> DRepInputContext? {
        drepContexts.first { $0.drepId == drepId }
    }

    /// Look up governance action context by tx hash + index.
    public func findGovActionContext(
        transactionId: String,
        govActionIndex: UInt16
    ) -> GovActionInputContext? {
        govActionContexts.first {
            $0.transactionId == transactionId && $0.govActionIndex == govActionIndex
        }
    }

    /// Look up last enacted governance action by action type.
    public func findLastEnactedGovAction(
        actionType: GovActionType
    ) -> GovActionInputContext? {
        lastEnactedGovAction.first { $0.actionType == actionType }
    }

    /// Look up current committee member by cold credential string.
    public func findCurrentCommitteeMember(
        coldCredential: String
    ) -> CommitteeInputContext? {
        currentCommitteeMembers.first { $0.committeeColdCredential == coldCredential }
    }

    /// Look up potential committee member by cold credential string.
    public func findPotentialCommitteeMember(
        coldCredential: String
    ) -> CommitteeInputContext? {
        potentialCommitteeMembers.first { $0.committeeColdCredential == coldCredential }
    }

    /// Look up current committee member by hot credential string.
    public func findCurrentCommitteeMemberByHot(
        hotCredential: String
    ) -> CommitteeInputContext? {
        currentCommitteeMembers.first { $0.committeeHotCredential == hotCredential }
    }

    /// Look up potential committee member by hot credential string.
    public func findPotentialCommitteeMemberByHot(
        hotCredential: String
    ) -> CommitteeInputContext? {
        potentialCommitteeMembers.first { $0.committeeHotCredential == hotCredential }
    }
}
