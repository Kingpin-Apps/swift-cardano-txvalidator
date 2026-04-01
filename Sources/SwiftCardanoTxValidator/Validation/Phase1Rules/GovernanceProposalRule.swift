import Foundation
import SwiftCardanoCore

/// Validates Conway-era governance proposal procedures.
///
/// For each `ProposalProcedure` in the transaction body, checks:
/// - Reward account network ID matches the expected network
/// - Return account is registered on-chain
/// - Previous governance action ID is valid (exists and is the correct type)
/// - Action-specific rules:
///   - `TreasuryWithdrawalsAction`: withdrawals must sum to non-zero; each withdrawal
///     account network ID must match; accounts must exist
///   - `UpdateCommittee`: no credential in both add and remove sets; expiration
///     epochs must be greater than the current epoch
///   - All others with a previous action ID: that ID must exist in chain state
///
/// Reference: cquisitor-lib governance proposal validation
public struct GovernanceProposalRule: ValidationRule {
    public let name = "governanceProposal"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        guard let proposals = transaction.transactionBody.proposalProcedures else {
            return []
        }

        var issues: [ValidationError] = []

        for (i, proposal) in proposals.elementsOrdered.enumerated() {
            let fieldPath = "transaction_body.proposal_procedures[\(i)]"
            validateProposal(
                proposal,
                fieldPath: fieldPath,
                context: context,
                issues: &issues
            )
        }

        return issues
    }
}

// MARK: - Per-proposal validation

private extension GovernanceProposalRule {

    func validateProposal(
        _ proposal: ProposalProcedure,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        // 1. Reward account network ID
        checkRewardAccountNetwork(
            rewardAccount: proposal.rewardAccount,
            fieldPath: "\(fieldPath).reward_account",
            context: context,
            errorKind: .proposalProcedureNetworkIdMismatch,
            issues: &issues
        )

        // 2. Return account must exist and be registered
        if !context.accountContexts.isEmpty {
            let rewardAddress = proposal.rewardAccount.toHexString()
            if let accountCtx = context.findAccountContext(rewardAddress: rewardAddress) {
                if !accountCtx.isRegistered {
                    issues.append(ValidationError(
                        kind: .proposalReturnAccountDoesNotExist,
                        fieldPath: "\(fieldPath).reward_account",
                        message: "Proposal return account \(rewardAddress) is not registered."
                    ))
                }
            } else {
                issues.append(ValidationError(
                    kind: .proposalReturnAccountDoesNotExist,
                    fieldPath: "\(fieldPath).reward_account",
                    message: "Proposal return account \(rewardAddress) does not exist in the ledger."
                ))
            }
        }

        // 3. Action-specific rules
        validateGovAction(
            proposal.govAction,
            fieldPath: "\(fieldPath).gov_action",
            context: context,
            issues: &issues
        )
    }

    // MARK: - Action dispatch

    func validateGovAction(
        _ action: GovAction,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        switch action {
        case .parameterChangeAction(let a):
            if let prevId = a.id {
                checkPrevGovActionId(
                    prevId, expectedType: .parameterChange,
                    fieldPath: fieldPath, context: context, issues: &issues
                )
            }

        case .hardForkInitiationAction(let a):
            if let prevId = a.id {
                checkPrevGovActionId(
                    prevId, expectedType: .hardForkInitiation,
                    fieldPath: fieldPath, context: context, issues: &issues
                )
            }

        case .treasuryWithdrawalsAction(let a):
            checkTreasuryWithdrawals(a, fieldPath: fieldPath, context: context, issues: &issues)

        case .noConfidence(let a):
            checkPrevGovActionId(
                a.id, expectedType: .noConfidence,
                fieldPath: fieldPath, context: context, issues: &issues
            )

        case .updateCommittee(let a):
            if let prevId = a.id {
                checkPrevGovActionId(
                    prevId, expectedType: .updateCommittee,
                    fieldPath: fieldPath, context: context, issues: &issues
                )
            }
            checkUpdateCommittee(a, fieldPath: fieldPath, context: context, issues: &issues)

        case .newConstitution(let a):
            checkPrevGovActionId(
                a.id, expectedType: .newConstitution,
                fieldPath: fieldPath, context: context, issues: &issues
            )

        case .infoAction:
            break
        }
    }

    // MARK: - Previous gov action ID check

    func checkPrevGovActionId(
        _ govActionId: GovActionID,
        expectedType: GovActionType,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        guard !context.govActionContexts.isEmpty else { return }

        let txId = "\(govActionId.transactionID)"
        let idx = govActionId.govActionIndex

        if let existing = context.findGovActionContext(transactionId: txId, govActionIndex: idx) {
            if existing.actionType != expectedType {
                issues.append(ValidationError(
                    kind: .invalidPrevGovActionId,
                    fieldPath: fieldPath,
                    message: "Previous governance action \(txId)#\(idx) has type "
                        + "\(existing.actionType) but expected \(expectedType)."
                ))
            }
        } else {
            issues.append(ValidationError(
                kind: .invalidPrevGovActionId,
                fieldPath: fieldPath,
                message: "Previous governance action \(txId)#\(idx) not found in ledger state."
            ))
        }
    }

    // MARK: - TreasuryWithdrawals checks

    func checkTreasuryWithdrawals(
        _ action: TreasuryWithdrawalsAction,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        // Withdrawals must not sum to zero
        let total = action.withdrawals.values.reduce(0 as Coin) { $0 + $1 }
        if total == 0 {
            issues.append(ValidationError(
                kind: .zeroTreasuryWithdrawals,
                fieldPath: "\(fieldPath).withdrawals",
                message: "Treasury withdrawals sum to zero lovelace."
            ))
        }

        // Each withdrawal account: network ID and existence checks
        for (rewardAccount, _) in action.withdrawals {
            checkRewardAccountNetwork(
                rewardAccount: rewardAccount,
                fieldPath: "\(fieldPath).withdrawals",
                context: context,
                errorKind: .treasuryWithdrawalsNetworkIdMismatch,
                issues: &issues
            )

            if !context.accountContexts.isEmpty {
                let rewardAddress = rewardAccount.toHexString()
                if context.findAccountContext(rewardAddress: rewardAddress) == nil {
                    issues.append(ValidationError(
                        kind: .treasuryWithdrawalReturnAccountDoesNotExist,
                        fieldPath: "\(fieldPath).withdrawals",
                        message: "Treasury withdrawal account \(rewardAddress) does not exist "
                            + "in the ledger."
                    ))
                }
            }
        }
    }

    // MARK: - UpdateCommittee checks

    func checkUpdateCommittee(
        _ action: UpdateCommittee,
        fieldPath: String,
        context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        // No credential should appear in both the add set and the remove set
        let toAdd = Set(action.credentialEpochs.keys)
        let toRemove = action.coldCredentials
        let conflicts = toAdd.intersection(toRemove)

        if !conflicts.isEmpty {
            issues.append(ValidationError(
                kind: .conflictingCommitteeUpdate,
                fieldPath: fieldPath,
                message: "Committee update has \(conflicts.count) credential(s) in both the "
                    + "add and remove sets: "
                    + conflicts.map { "\($0)" }.sorted().joined(separator: ", ")
            ))
        }

        // Expiration epochs must be strictly greater than the current epoch
        if let currentEpoch = context.currentEpoch {
            for (credential, expirationEpoch) in action.credentialEpochs {
                if expirationEpoch <= currentEpoch {
                    issues.append(ValidationError(
                        kind: .expirationEpochTooSmall,
                        fieldPath: fieldPath,
                        message: "Committee member \(credential) expiration epoch "
                            + "\(expirationEpoch) must be greater than current epoch "
                            + "\(currentEpoch)."
                    ))
                }
            }
        }
    }

    // MARK: - Network ID helper

    /// Check that the first byte of `rewardAccount` encodes the expected network.
    ///
    /// Cardano reward address header byte: bit 0 = network (0 → testnet, 1 → mainnet).
    func checkRewardAccountNetwork(
        rewardAccount: RewardAccount,
        fieldPath: String,
        context: ValidationContext,
        errorKind: ValidationError.Kind,
        issues: inout [ValidationError]
    ) {
        guard let expectedNetwork = context.network else { return }

        let hexStr = rewardAccount.toHexString()
        guard hexStr.count >= 2,
              let headerByte = UInt8(hexStr.prefix(2), radix: 16) else { return }

        let networkBit = headerByte & 0x01
        let accountNetwork: NetworkId = networkBit == 1 ? .mainnet : .testnet

        if accountNetwork != expectedNetwork {
            issues.append(ValidationError(
                kind: errorKind,
                fieldPath: fieldPath,
                message: "Reward account \(hexStr) has network \(accountNetwork) "
                    + "but the transaction targets \(expectedNetwork).",
                hint: "Use a \(expectedNetwork) reward account."
            ))
        }
    }
}
