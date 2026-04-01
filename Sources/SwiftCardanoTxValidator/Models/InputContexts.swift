import Foundation
import SwiftCardanoCore

// MARK: - Governance Action Type

/// Type of governance action, mirroring cquisitor-lib's `GovernanceActionType`.
public enum GovActionType: String, Sendable, Codable, Equatable, Hashable {
    case parameterChange
    case hardForkInitiation
    case treasuryWithdrawals
    case noConfidence
    case updateCommittee
    case newConstitution
    case info
}

// MARK: - Account Input Context

/// Chain-state context for a stake / reward account.
///
/// Mirrors cquisitor-lib's `AccountInputContext`.
public struct AccountInputContext: Sendable, Codable, Equatable {
    /// Bech32 reward address (e.g. `stake_test1...`).
    public let rewardAddress: String
    /// Whether the stake credential is currently registered on-chain.
    public let isRegistered: Bool
    /// The deposit originally paid at registration, if known.
    public let payedDeposit: Coin?
    /// Bech32 DRep ID the account is delegated to, or `nil`.
    public let delegatedToDRep: String?
    /// Pool ID (hex) the account is delegated to, or `nil`.
    public let delegatedToPool: String?
    /// Current reward balance in lovelace, if known.
    public let balance: Coin?

    public init(
        rewardAddress: String,
        isRegistered: Bool,
        payedDeposit: Coin? = nil,
        delegatedToDRep: String? = nil,
        delegatedToPool: String? = nil,
        balance: Coin? = nil
    ) {
        self.rewardAddress = rewardAddress
        self.isRegistered = isRegistered
        self.payedDeposit = payedDeposit
        self.delegatedToDRep = delegatedToDRep
        self.delegatedToPool = delegatedToPool
        self.balance = balance
    }
}

// MARK: - Pool Input Context

/// Chain-state context for a stake pool.
///
/// Mirrors cquisitor-lib's `PoolInputContext`.
public struct PoolInputContext: Sendable, Codable, Equatable {
    /// Pool key hash (hex).
    public let poolId: String
    /// Whether the pool is currently registered on-chain.
    public let isRegistered: Bool
    /// If the pool has a pending retirement, the retirement epoch.
    public let retirementEpoch: UInt64?

    public init(
        poolId: String,
        isRegistered: Bool,
        retirementEpoch: UInt64? = nil
    ) {
        self.poolId = poolId
        self.isRegistered = isRegistered
        self.retirementEpoch = retirementEpoch
    }
}

// MARK: - DRep Input Context

/// Chain-state context for a DRep.
///
/// Mirrors cquisitor-lib's `DrepInputContext`.
public struct DRepInputContext: Sendable, Codable, Equatable {
    /// Bech32 DRep ID (e.g. `drep1...`).
    public let drepId: String
    /// Whether the DRep is currently registered on-chain.
    public let isRegistered: Bool
    /// The deposit originally paid at registration, if known.
    public let payedDeposit: Coin?

    public init(
        drepId: String,
        isRegistered: Bool,
        payedDeposit: Coin? = nil
    ) {
        self.drepId = drepId
        self.isRegistered = isRegistered
        self.payedDeposit = payedDeposit
    }
}

// MARK: - Governance Action Input Context

/// Chain-state context for a governance action.
///
/// Mirrors cquisitor-lib's `GovActionInputContext`.
public struct GovActionInputContext: Sendable, Codable, Equatable {
    /// Transaction hash (hex) of the proposal.
    public let transactionId: String
    /// Index within that transaction.
    public let govActionIndex: UInt16
    /// The type of governance action.
    public let actionType: GovActionType
    /// Whether the action is still active (not expired or enacted).
    public let isActive: Bool

    public init(
        transactionId: String,
        govActionIndex: UInt16,
        actionType: GovActionType,
        isActive: Bool
    ) {
        self.transactionId = transactionId
        self.govActionIndex = govActionIndex
        self.actionType = actionType
        self.isActive = isActive
    }
}

// MARK: - Committee Input Context

/// Chain-state context for a constitutional committee member.
///
/// Mirrors cquisitor-lib's `CommitteeInputContext`.
public struct CommitteeInputContext: Sendable, Codable, Equatable {
    /// String representation of the committee member's cold credential.
    public let committeeColdCredential: String
    /// String representation of the authorized hot credential, or `nil`.
    public let committeeHotCredential: String?
    /// Whether the member has resigned.
    public let isResigned: Bool

    public init(
        committeeColdCredential: String,
        committeeHotCredential: String? = nil,
        isResigned: Bool = false
    ) {
        self.committeeColdCredential = committeeColdCredential
        self.committeeHotCredential = committeeHotCredential
        self.isResigned = isResigned
    }
}
