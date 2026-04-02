import Foundation
import SwiftCardanoCore

/// Validates Conway-era voting procedures.
///
/// For each vote cast in `transaction_body.voting_procedures`, checks:
/// - The voter (CC hot key, DRep, or SPO) exists in chain state
/// - The governance action being voted on exists and is still active
/// - The voter type is permitted to vote on the given action type (CIP-1694 matrix)
///
/// All checks are skipped gracefully when the relevant context arrays are empty.
///
/// Reference: cquisitor-lib voting validation / CIP-1694 voting permission matrix
public struct VotingRule: ValidationRule {
    public let name = "voting"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let era = context.era ?? .conway
        guard era >= .conway else { return [] }

        guard let votingProcedures = transaction.transactionBody.votingProcedures else {
            return []
        }

        var issues: [ValidationError] = []

        for (voter, govActionId, _) in votingProcedures.allVotes {
            let txIdStr = "\(govActionId.transactionID)"
            let actionIdx = govActionId.govActionIndex
            let fieldPath = "transaction_body.voting_procedures[\(txIdStr)#\(actionIdx)]"

            // 1. Voter must exist in chain state
            checkVoterExists(voter, fieldPath: fieldPath, context: context, issues: &issues)

            // 2. Governance action must exist and be active
            var actionType: GovActionType? = nil
            if !context.govActionContexts.isEmpty {
                if let govAction = context.findGovActionContext(
                    transactionId: txIdStr,
                    govActionIndex: actionIdx
                ) {
                    if !govAction.isActive {
                        issues.append(ValidationError(
                            kind: .votingOnExpiredGovAction,
                            fieldPath: fieldPath,
                            message: "Governance action \(txIdStr)#\(actionIdx) is no longer "
                                + "active (expired or already enacted)."
                        ))
                    }
                    actionType = govAction.actionType
                } else {
                    issues.append(ValidationError(
                        kind: .govActionsDoNotExist,
                        fieldPath: fieldPath,
                        message: "Governance action \(txIdStr)#\(actionIdx) does not exist "
                            + "in the ledger state."
                    ))
                }
            }

            // 3. Voter type must be permitted to vote on this action type
            if let actionType {
                checkVoterAllowed(
                    voter, actionType: actionType, fieldPath: fieldPath, issues: &issues
                )
            }
        }

        return issues
    }
}

// MARK: - Voter existence checks

private extension VotingRule {

    func checkVoterExists(
        _ voter: Voter,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        switch voter.credential {
        case .constitutionalCommitteeHotKeyhash(let hash):
            checkCCHotExists(credStr: "\(hash)", fieldPath: fieldPath, context: context, issues: &issues)

        case .constitutionalCommitteeHotScriptHash(let hash):
            checkCCHotExists(credStr: "\(hash)", fieldPath: fieldPath, context: context, issues: &issues)

        case .drepKeyhash(let hash):
            checkDRepExists(drepIdStr: "\(hash)", fieldPath: fieldPath, context: context, issues: &issues)

        case .drepScriptHash(let hash):
            checkDRepExists(drepIdStr: "\(hash)", fieldPath: fieldPath, context: context, issues: &issues)

        case .stakePoolKeyhash(let hash):
            guard !context.poolContexts.isEmpty else { return }
            let poolIdStr = "\(hash)"
            if let poolCtx = context.findPoolContext(poolId: poolIdStr) {
                if !poolCtx.isRegistered {
                    issues.append(ValidationError(
                        kind: .voterDoesNotExist,
                        fieldPath: fieldPath,
                        message: "Stake pool \(poolIdStr) is not registered."
                    ))
                }
            } else {
                issues.append(ValidationError(
                    kind: .voterDoesNotExist,
                    fieldPath: fieldPath,
                    message: "Stake pool \(poolIdStr) does not exist in the ledger state."
                ))
            }
        }
    }

    func checkCCHotExists(
        credStr: String,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        guard !context.currentCommitteeMembers.isEmpty else { return }
        if context.findCurrentCommitteeMemberByHot(hotCredential: credStr) == nil {
            issues.append(ValidationError(
                kind: .voterDoesNotExist,
                fieldPath: fieldPath,
                message: "Constitutional committee hot credential \(credStr) is not "
                    + "a known active committee member."
            ))
        }
    }

    func checkDRepExists(
        drepIdStr: String,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        guard !context.drepContexts.isEmpty else { return }
        if let drepCtx = context.findDRepContext(drepId: drepIdStr) {
            if !drepCtx.isRegistered {
                issues.append(ValidationError(
                    kind: .voterDoesNotExist,
                    fieldPath: fieldPath,
                    message: "DRep \(drepIdStr) is not registered."
                ))
            }
        } else {
            issues.append(ValidationError(
                kind: .voterDoesNotExist,
                fieldPath: fieldPath,
                message: "DRep \(drepIdStr) does not exist in the ledger state."
            ))
        }
    }

    // MARK: - CIP-1694 voting permission matrix

    /// Returns whether a given voter type may vote on a given governance action type.
    ///
    /// CIP-1694 permission matrix:
    ///
    /// | Action Type           | CC  | DRep | SPO |
    /// |-----------------------|-----|------|-----|
    /// | NoConfidence          |  ✗  |  ✓   |  ✓  |
    /// | UpdateCommittee       |  ✗  |  ✓   |  ✓  |
    /// | NewConstitution       |  ✓  |  ✓   |  ✗  |
    /// | HardForkInitiation    |  ✓  |  ✓   |  ✓  |
    /// | ParameterChange       |  ✓  |  ✓   |  ✗  |
    /// | TreasuryWithdrawals   |  ✓  |  ✓   |  ✗  |
    /// | InfoAction            |  ✓  |  ✓   |  ✓  |
    ///
    /// Note: SPOs can technically vote on security-parameter changes, but distinguishing
    /// security-group parameters requires inspecting individual fields — this is treated
    /// the same as regular ParameterChange here (SPO not allowed).
    func checkVoterAllowed(
        _ voter: Voter,
        actionType: GovActionType,
        fieldPath: String,
        issues: inout [ValidationError]
    ) {
        let allowed: Bool

        switch voter.credential {
        case .constitutionalCommitteeHotKeyhash, .constitutionalCommitteeHotScriptHash:
            // CC cannot vote on NoConfidence or UpdateCommittee
            switch actionType {
            case .noConfidence, .updateCommittee:
                allowed = false
            default:
                allowed = true
            }

        case .drepKeyhash, .drepScriptHash:
            // DReps can vote on all action types
            allowed = true

        case .stakePoolKeyhash:
            // SPOs can only vote on NoConfidence, UpdateCommittee, HardForkInitiation, InfoAction
            switch actionType {
            case .noConfidence, .updateCommittee, .hardForkInitiation, .info:
                allowed = true
            case .parameterChange, .treasuryWithdrawals, .newConstitution:
                allowed = false
            }
        }

        if !allowed {
            issues.append(ValidationError(
                kind: .disallowedVoter,
                fieldPath: fieldPath,
                message: "Voter type '\(voterTypeName(voter.credential))' is not permitted "
                    + "to vote on \(actionType) actions (CIP-1694)."
            ))
        }
    }

    func voterTypeName(_ credential: VoterType) -> String {
        switch credential {
        case .constitutionalCommitteeHotKeyhash:   return "constitutional_committee_hot_keyhash"
        case .constitutionalCommitteeHotScriptHash: return "constitutional_committee_hot_scripthash"
        case .drepKeyhash:                          return "drep_keyhash"
        case .drepScriptHash:                       return "drep_scripthash"
        case .stakePoolKeyhash:                     return "stake_pool_keyhash"
        }
    }
}
