import Foundation
import SwiftCardanoCore

/// Validates certificate registration / deregistration consistency against chain state.
///
/// Requires `accountContexts`, `poolContexts`, `drepContexts`, and committee member
/// arrays on `ValidationContext` to perform most checks. Gracefully skips chain-state
/// checks when these are empty.
///
/// Reference: cquisitor-lib `registration.rs`
public struct RegistrationRule: ValidationRule {
    public let name = "registration"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        guard let certs = transaction.transactionBody.certificates else {
            return []
        }

        let hasChainState = !context.accountContexts.isEmpty
            || !context.poolContexts.isEmpty
            || !context.drepContexts.isEmpty
            || !context.currentCommitteeMembers.isEmpty
            || !context.potentialCommitteeMembers.isEmpty

        guard hasChainState else {
            // Without any chain state we cannot validate registrations.
            return []
        }

        let era = context.era ?? .conway

        // Build initial registration state from context
        var state = RegistrationState()
        state.loadInitialState(from: context)

        var issues: [ValidationError] = []

        for (i, cert) in certs.asList.enumerated() {
            let certIndex = UInt32(i)
            let fieldPath = "transaction_body.certificates[\(i)]"

            validateCertificate(
                cert,
                certIndex: certIndex,
                fieldPath: fieldPath,
                state: &state,
                context: context,
                era: era,
                protocolParams: protocolParams,
                issues: &issues
            )

            // Update state after validation (order matters for duplicate detection)
            state.updateState(cert: cert, certIndex: certIndex)
        }

        return issues
    }
}

// MARK: - Registration State

/// Tracks in-transaction registration changes for duplicate/conflict detection.
private struct RegistrationState {
    /// Entities registered at the start of tx processing (from chain state).
    var initialAccounts: Set<String> = []
    var initialPools: Set<String> = []
    var initialDReps: Set<String> = []

    /// Maps entity ID → first cert index that registered it in this tx.
    var accountRegistrationsInTx: [String: UInt32] = [:]
    var poolRegistrationsInTx: [String: UInt32] = [:]
    var drepRegistrationsInTx: [String: UInt32] = [:]

    /// Entities deregistered in this tx.
    var accountDeregistrationsInTx: Set<String> = []
    var drepDeregistrationsInTx: Set<String> = []

    /// Pool retirements in this tx: poolId → retirement epoch.
    var poolRetirementsInTx: [String: UInt64] = [:]

    /// Committee cold credentials that have resigned in this tx.
    var committeeResignationsInTx: Set<String> = []

    /// Committee hot credentials registered in this tx: cold credential → first cert index.
    var committeeHotRegistrationsInTx: [String: UInt32] = [:]

    mutating func loadInitialState(from context: ValidationContext) {
        for account in context.accountContexts where account.isRegistered {
            initialAccounts.insert(account.rewardAddress)
        }
        for pool in context.poolContexts where pool.isRegistered {
            initialPools.insert(pool.poolId)
        }
        for drep in context.drepContexts where drep.isRegistered {
            initialDReps.insert(drep.drepId)
        }
    }

    func isAccountRegistered(_ id: String) -> Bool {
        let wasInitial = initialAccounts.contains(id)
        let registeredInTx = accountRegistrationsInTx[id] != nil
        let deregisteredInTx = accountDeregistrationsInTx.contains(id)
        return (wasInitial || registeredInTx) && !deregisteredInTx
    }

    func isPoolRegistered(_ id: String) -> Bool {
        let wasInitial = initialPools.contains(id)
        let registeredInTx = poolRegistrationsInTx[id] != nil
        let retiringInTx = poolRetirementsInTx[id] != nil
        return (wasInitial || registeredInTx) && !retiringInTx
    }

    func isDRepRegistered(_ id: String) -> Bool {
        let wasInitial = initialDReps.contains(id)
        let registeredInTx = drepRegistrationsInTx[id] != nil
        let deregisteredInTx = drepDeregistrationsInTx.contains(id)
        return (wasInitial || registeredInTx) && !deregisteredInTx
    }

    mutating func updateState(cert: Certificate, certIndex: UInt32) {
        switch cert {
        case .stakeRegistration(let c):
            let id = "\(c.stakeCredential)"
            accountRegistrationsInTx[id] = accountRegistrationsInTx[id] ?? certIndex
            accountDeregistrationsInTx.remove(id)

        case .register(let c):
            let id = "\(c.stakeCredential)"
            accountRegistrationsInTx[id] = accountRegistrationsInTx[id] ?? certIndex
            accountDeregistrationsInTx.remove(id)

        case .stakeRegisterDelegate(let c):
            let id = "\(c.stakeCredential)"
            accountRegistrationsInTx[id] = accountRegistrationsInTx[id] ?? certIndex
            accountDeregistrationsInTx.remove(id)

        case .voteRegisterDelegate(let c):
            let id = "\(c.stakeCredential)"
            accountRegistrationsInTx[id] = accountRegistrationsInTx[id] ?? certIndex
            accountDeregistrationsInTx.remove(id)

        case .stakeVoteRegisterDelegate(let c):
            let id = "\(c.stakeCredential)"
            accountRegistrationsInTx[id] = accountRegistrationsInTx[id] ?? certIndex
            accountDeregistrationsInTx.remove(id)

        case .stakeDeregistration(let c):
            let id = "\(c.stakeCredential)"
            accountDeregistrationsInTx.insert(id)
            accountRegistrationsInTx.removeValue(forKey: id)

        case .unregister(let c):
            let id = "\(c.stakeCredential)"
            accountDeregistrationsInTx.insert(id)
            accountRegistrationsInTx.removeValue(forKey: id)

        case .poolRegistration(let c):
            let id = "\(c.poolParams.poolOperator)"
            poolRegistrationsInTx[id] = poolRegistrationsInTx[id] ?? certIndex
            poolRetirementsInTx.removeValue(forKey: id)

        case .poolRetirement(let c):
            let id = "\(c.poolKeyHash)"
            poolRetirementsInTx[id] = UInt64(c.epoch)

        case .registerDRep(let c):
            let id = "\(c.drepCredential)"
            drepRegistrationsInTx[id] = drepRegistrationsInTx[id] ?? certIndex
            drepDeregistrationsInTx.remove(id)

        case .unRegisterDRep(let c):
            let id = "\(c.drepCredential)"
            drepDeregistrationsInTx.insert(id)
            drepRegistrationsInTx.removeValue(forKey: id)

        case .resignCommitteeCold(let c):
            let id = "\(c.committeeColdCredential)"
            committeeResignationsInTx.insert(id)

        case .authCommitteeHot(let c):
            let coldId = "\(c.committeeColdCredential)"
            committeeHotRegistrationsInTx[coldId] = committeeHotRegistrationsInTx[coldId] ?? certIndex

        default:
            break
        }
    }
}

// MARK: - Per-certificate validation

private extension RegistrationRule {

    func validateCertificate(
        _ cert: Certificate,
        certIndex: UInt32,
        fieldPath: String,
        state: inout RegistrationState,
        context: ValidationContext,
        era: Era,
        protocolParams: ProtocolParameters,
        issues: inout [ValidationError]
    ) {
        switch cert {
        // ── Stake registration certs ─────────────────────────────────
        case .stakeRegistration(let c):
            validateStakeRegistration(
                id: "\(c.stakeCredential)", certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .register(let c):
            // Conway+ only
            guard era >= .conway else { break }
            validateStakeRegistration(
                id: "\(c.stakeCredential)", certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .stakeRegisterDelegate(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let accountId = "\(c.stakeCredential)"
            let poolId = "\(c.poolKeyHash)"
            validateStakeRegistration(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validatePoolExists(
                poolId: poolId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .voteRegisterDelegate(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let accountId = "\(c.stakeCredential)"
            let drepId = "\(c.drep)"
            validateStakeRegistration(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validateDRepExists(
                drepId: drepId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .stakeVoteRegisterDelegate(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let accountId = "\(c.stakeCredential)"
            let poolId = "\(c.poolKeyHash)"
            let drepId = "\(c.drep)"
            validateStakeRegistration(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validatePoolExists(
                poolId: poolId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validateDRepExists(
                drepId: drepId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        // ── Stake deregistration ─────────────────────────────────────
        case .stakeDeregistration(let c):
            validateStakeDeregistration(
                id: "\(c.stakeCredential)", certIndex: certIndex, fieldPath: fieldPath,
                state: state, context: context, issues: &issues
            )

        case .unregister(let c):
            // Conway+ only
            guard era >= .conway else { break }
            validateStakeDeregistration(
                id: "\(c.stakeCredential)", certIndex: certIndex, fieldPath: fieldPath,
                state: state, context: context, issues: &issues
            )

        // ── Stake delegation (no registration) ──────────────────────
        case .stakeDelegation(let c):
            let accountId = "\(c.stakeCredential)"
            let poolId = "\(c.poolKeyHash)"
            validateStakeExists(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validatePoolExists(
                poolId: poolId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .voteDelegate(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let accountId = "\(c.stakeCredential)"
            let drepId = "\(c.drep)"
            validateStakeExists(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validateDRepExists(
                drepId: drepId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        case .stakeVoteDelegate(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let accountId = "\(c.stakeCredential)"
            let poolId = "\(c.poolKeyHash)"
            let drepId = "\(c.drep)"
            validateStakeExists(
                id: accountId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validatePoolExists(
                poolId: poolId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )
            validateDRepExists(
                drepId: drepId, certIndex: certIndex, fieldPath: fieldPath,
                state: state, issues: &issues
            )

        // ── Pool registration ────────────────────────────────────────
        case .poolRegistration(let c):
            let poolId = "\(c.poolParams.poolOperator)"
            let entity = poolId

            // Duplicate registration in tx
            if let firstIndex = state.poolRegistrationsInTx[entity],
               firstIndex < certIndex {
                issues.append(ValidationError(
                    kind: .duplicateRegistrationInTx,
                    fieldPath: fieldPath,
                    message: "Pool \(poolId) registered more than once in this transaction.",
                    isWarning: true
                ))
            }

            // Pool cost too low (minPoolCost introduced in Alonzo)
            if era >= .alonzo && c.poolParams.cost < protocolParams.minPoolCost {
                issues.append(ValidationError(
                    kind: .stakePoolCostTooLow,
                    fieldPath: fieldPath,
                    message: "Pool cost \(c.poolParams.cost) is below minimum \(protocolParams.minPoolCost).",
                    hint: "Set pool cost to at least \(protocolParams.minPoolCost) lovelace."
                ))
            }

            // Already registered (warning — re-registration = update)
            if state.initialPools.contains(entity)
                && state.poolRetirementsInTx[entity] == nil {
                issues.append(ValidationError(
                    kind: .poolAlreadyRegistered,
                    fieldPath: fieldPath,
                    message: "Pool \(poolId) is already registered (this is a re-registration/update).",
                    isWarning: true
                ))
            }

        // ── Pool retirement ──────────────────────────────────────────
        case .poolRetirement(let c):
            let poolId = "\(c.poolKeyHash)"

            // Pool must be registered
            if !state.isPoolRegistered(poolId) {
                issues.append(ValidationError(
                    kind: .stakePoolNotRegistered,
                    fieldPath: fieldPath,
                    message: "Cannot retire pool \(poolId): pool is not registered."
                ))
            }

            // Retirement epoch bounds
            if let currentEpoch = context.currentEpoch {
                let minEpoch = currentEpoch + 1
                let maxEpoch = currentEpoch + UInt64(protocolParams.poolRetireMaxEpoch)
                let retirementEpoch = UInt64(c.epoch)
                if retirementEpoch < minEpoch || retirementEpoch > maxEpoch {
                    issues.append(ValidationError(
                        kind: .wrongRetirementEpoch,
                        fieldPath: fieldPath,
                        message: "Pool retirement epoch \(retirementEpoch) is outside "
                            + "valid range [\(minEpoch)..\(maxEpoch)] "
                            + "(current epoch: \(currentEpoch)).",
                        hint: "Set the retirement epoch between \(minEpoch) and \(maxEpoch)."
                    ))
                }
            }

        // ── DRep registration ────────────────────────────────────────
        case .registerDRep(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let drepId = "\(c.drepCredential)"

            // Duplicate in tx
            if let firstIndex = state.drepRegistrationsInTx[drepId],
               firstIndex < certIndex {
                issues.append(ValidationError(
                    kind: .duplicateRegistrationInTx,
                    fieldPath: fieldPath,
                    message: "DRep \(drepId) registered more than once in this transaction.",
                    isWarning: true
                ))
            }

            // Already registered (warning)
            if state.initialDReps.contains(drepId)
                && !state.drepDeregistrationsInTx.contains(drepId) {
                issues.append(ValidationError(
                    kind: .drepAlreadyRegistered,
                    fieldPath: fieldPath,
                    message: "DRep \(drepId) is already registered.",
                    isWarning: true
                ))
            }

        // ── DRep deregistration ──────────────────────────────────────
        case .unRegisterDRep(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let drepId = "\(c.drepCredential)"
            if !state.isDRepRegistered(drepId) {
                issues.append(ValidationError(
                    kind: .drepNotRegistered,
                    fieldPath: fieldPath,
                    message: "DRep \(drepId) is not registered.",
                    isWarning: true
                ))
            }

        // ── DRep update ──────────────────────────────────────────────
        case .updateDRep(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let drepId = "\(c.drepCredential)"
            if !state.isDRepRegistered(drepId) {
                issues.append(ValidationError(
                    kind: .drepNotRegistered,
                    fieldPath: fieldPath,
                    message: "DRep \(drepId) is not registered (cannot update).",
                    isWarning: true
                ))
            }

        // ── Committee hot auth ───────────────────────────────────────
        case .authCommitteeHot(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let coldId = "\(c.committeeColdCredential)"
            let hotId = "\(c.committeeHotCredential)"

            // Already authorized in this tx
            if let firstIndex = state.committeeHotRegistrationsInTx[coldId],
               firstIndex < certIndex {
                issues.append(ValidationError(
                    kind: .duplicateCommitteeHotRegistrationInTx,
                    fieldPath: fieldPath,
                    message: "Committee hot credential \(hotId) authorized more than once in this transaction.",
                    isWarning: true
                ))
            }

            // Already authorized on-chain (existing hot key)
            if let current = context.findCurrentCommitteeMember(coldCredential: coldId),
               current.committeeHotCredential != nil,
               !current.isResigned {
                issues.append(ValidationError(
                    kind: .committeeAlreadyAuthorized,
                    fieldPath: fieldPath,
                    message: "Committee member \(coldId) already has an authorized hot credential on-chain.",
                    isWarning: true
                ))
            } else if let potential = context.findPotentialCommitteeMember(coldCredential: coldId),
                      potential.committeeHotCredential != nil,
                      !potential.isResigned {
                issues.append(ValidationError(
                    kind: .committeeAlreadyAuthorized,
                    fieldPath: fieldPath,
                    message: "Committee member \(coldId) already has an authorized hot credential.",
                    isWarning: true
                ))
            }

            // Resigned in this tx
            if state.committeeResignationsInTx.contains(coldId) {
                issues.append(ValidationError(
                    kind: .committeeHasPreviouslyResigned,
                    fieldPath: fieldPath,
                    message: "Committee member \(coldId) has resigned in this transaction."
                ))
            }

            // Previously resigned on-chain
            checkCommitteeResigned(
                coldId: coldId, fieldPath: fieldPath, context: context, issues: &issues
            )

            // Unknown committee member
            checkCommitteeKnown(
                coldId: coldId, fieldPath: fieldPath, context: context, issues: &issues
            )

        // ── Committee cold resign ────────────────────────────────────
        case .resignCommitteeCold(let c):
            // Conway+ only
            guard era >= .conway else { break }
            let coldId = "\(c.committeeColdCredential)"

            // Previously resigned on-chain
            checkCommitteeResigned(
                coldId: coldId, fieldPath: fieldPath, context: context, issues: &issues
            )

            // Duplicate resignation in this tx
            if state.committeeResignationsInTx.contains(coldId) {
                issues.append(ValidationError(
                    kind: .duplicateCommitteeColdResignationInTx,
                    fieldPath: fieldPath,
                    message: "Committee cold credential \(coldId) resigned more than once in this transaction.",
                    isWarning: true
                ))
            }

            // Unknown committee member
            checkCommitteeKnown(
                coldId: coldId, fieldPath: fieldPath, context: context, issues: &issues
            )

        default:
            break
        }
    }

    // MARK: - Helpers

    func validateStakeRegistration(
        id: String, certIndex: UInt32, fieldPath: String,
        state: RegistrationState, issues: inout [ValidationError]
    ) {
        // Duplicate in tx
        if let firstIndex = state.accountRegistrationsInTx[id],
           firstIndex < certIndex {
            issues.append(ValidationError(
                kind: .duplicateRegistrationInTx,
                fieldPath: fieldPath,
                message: "Stake key \(id) registered more than once in this transaction.",
                isWarning: true
            ))
        }

        // Already registered on-chain (and not deregistered in this tx)
        if state.initialAccounts.contains(id)
            && !state.accountDeregistrationsInTx.contains(id) {
            issues.append(ValidationError(
                kind: .stakeAlreadyRegistered,
                fieldPath: fieldPath,
                message: "Stake key \(id) is already registered."
            ))
        }
    }

    func validateStakeDeregistration(
        id: String, certIndex: UInt32, fieldPath: String,
        state: RegistrationState, context: ValidationContext,
        issues: inout [ValidationError]
    ) {
        if !state.isAccountRegistered(id) {
            issues.append(ValidationError(
                kind: .stakeNotRegistered,
                fieldPath: fieldPath,
                message: "Stake key \(id) is not registered."
            ))
        } else {
            // Check non-zero balance
            if let accountCtx = context.findAccountContext(rewardAddress: id),
               let balance = accountCtx.balance, balance > 0 {
                issues.append(ValidationError(
                    kind: .stakeNonZeroAccountBalance,
                    fieldPath: fieldPath,
                    message: "Cannot deregister stake key \(id): "
                        + "reward account has \(balance) lovelace remaining.",
                    hint: "Withdraw all rewards before deregistering."
                ))
            }
        }
    }

    func validateStakeExists(
        id: String, certIndex: UInt32, fieldPath: String,
        state: RegistrationState, issues: inout [ValidationError]
    ) {
        if !state.isAccountRegistered(id) {
            issues.append(ValidationError(
                kind: .stakeNotRegistered,
                fieldPath: fieldPath,
                message: "Stake key \(id) is not registered (delegation requires registration)."
            ))
        }
    }

    func validatePoolExists(
        poolId: String, certIndex: UInt32, fieldPath: String,
        state: RegistrationState, issues: inout [ValidationError]
    ) {
        if !state.isPoolRegistered(poolId) {
            issues.append(ValidationError(
                kind: .stakePoolNotRegistered,
                fieldPath: fieldPath,
                message: "Pool \(poolId) is not registered."
            ))
        }
    }

    func validateDRepExists(
        drepId: String, certIndex: UInt32, fieldPath: String,
        state: RegistrationState, issues: inout [ValidationError]
    ) {
        if !drepId.isEmpty && !state.isDRepRegistered(drepId) {
            issues.append(ValidationError(
                kind: .drepNotRegistered,
                fieldPath: fieldPath,
                message: "DRep \(drepId) is not registered.",
                isWarning: true
            ))
        }
    }

    func checkCommitteeResigned(
        coldId: String, fieldPath: String,
        context: ValidationContext, issues: inout [ValidationError]
    ) {
        if let current = context.findCurrentCommitteeMember(coldCredential: coldId),
           current.isResigned {
            issues.append(ValidationError(
                kind: .committeeHasPreviouslyResigned,
                fieldPath: fieldPath,
                message: "Committee member \(coldId) has previously resigned."
            ))
        } else if let potential = context.findPotentialCommitteeMember(coldCredential: coldId),
                  potential.isResigned {
            issues.append(ValidationError(
                kind: .committeeHasPreviouslyResigned,
                fieldPath: fieldPath,
                message: "Committee member \(coldId) has previously resigned."
            ))
        }
    }

    func checkCommitteeKnown(
        coldId: String, fieldPath: String,
        context: ValidationContext, issues: inout [ValidationError]
    ) {
        let isCurrent = context.findCurrentCommitteeMember(coldCredential: coldId) != nil
        let isPotential = context.findPotentialCommitteeMember(coldCredential: coldId) != nil
        if !isCurrent && !isPotential {
            issues.append(ValidationError(
                kind: .committeeIsUnknown,
                fieldPath: fieldPath,
                message: "Unknown committee cold credential: \(coldId)."
            ))
        }
    }
}
