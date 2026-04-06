import Foundation
import SwiftCardanoCore
import SwiftCardanoChain

extension ValidationContext {

    /// Build a ``ValidationContext`` by fetching all chain-state derivable from a ``ChainContext``.
    ///
    /// Populates the following fields automatically:
    /// - ``resolvedInputs`` — UTxOs for all spending, collateral, and reference inputs
    /// - ``currentSlot`` — last block slot number
    /// - ``network`` — network identifier
    /// - ``currentEpoch`` — current epoch number
    /// - ``era`` — current era
    /// - ``accountContexts`` — stake address state for each reward account referenced in
    ///   withdrawals and certificates
    /// - ``poolContexts`` — stake pool registration state for each pool referenced in certificates
    /// - ``drepContexts`` — DRep registration state for each DRep referenced in certificates
    /// - ``govActionContexts`` — governance action state for each action referenced in voting
    ///   procedures and proposal procedures
    /// - ``lastEnactedGovAction`` — last enacted governance action per action type
    /// - ``currentCommitteeMembers`` — current constitutional committee members
    /// - ``potentialCommitteeMembers`` — potential (proposed) constitutional committee members
    ///
    /// ``treasuryValue`` is only fetched when ``currentTreasuryAmount`` is present in the
    /// transaction body.
    ///
    /// - Parameters:
    ///   - transaction: The parsed transaction.
    ///   - chainContext: Chain context used to resolve UTxOs and query chain state.
    /// - Returns: A populated ``ValidationContext``.
    public static func from(
        transaction: Transaction,
        chainContext: any ChainContext
    ) async throws -> ValidationContext {
        let body = transaction.transactionBody
        let network = chainContext.networkId

        // MARK: - Resolved Inputs

        // Collect de-duplicated input references from NecessaryData, then resolve each UTxO.
        let needed = NecessaryData.from(transaction)
        var resolvedInputs: [UTxO] = []
        for ref in needed.inputs {
            guard let input = try? TransactionInput(from: ref.transactionId, index: ref.index) else {
                continue
            }
            if let (utxo, _) = try await chainContext.utxo(input: input) {
                resolvedInputs.append(utxo)
            }
        }

        // MARK: - Chain Metadata

        let slot = try await chainContext.lastBlockSlot()
        let epoch = try await chainContext.epoch()
        let era = try await chainContext.era()

        // MARK: - Account Contexts

        var accountContexts: [AccountInputContext] = []
        var seenAccounts = Set<String>()

        // Helper: query stakeAddressInfo and append an AccountInputContext if not yet seen.
        // Note: must only be called serially (never inside withThrowingTaskGroup) because it
        // mutates captured vars. See feedback_concurrency.md for context on concurrency constraints.
        func fetchAccountContext(address: Address) async {
            guard let bech32 = try? address.toBech32(),
                  seenAccounts.insert(bech32).inserted else { return }
            guard let infos = try? await chainContext.stakeAddressInfo(address: address),
                  let info = infos.first else { return }
            accountContexts.append(AccountInputContext(
                rewardAddress: info.address,
                isRegistered: info.active ?? false,
                payedDeposit: info.stakeRegistrationDeposit.flatMap { $0 >= 0 ? Coin($0) : nil },
                delegatedToDRep: info.voteDelegation.map { "\($0)" },
                delegatedToPool: info.stakeDelegation.flatMap { try? $0.id(.hex) },
                balance: info.rewardAccountBalance >= 0 ? Coin(info.rewardAccountBalance) : nil
            ))
        }

        // Reward accounts from withdrawals (RewardAccount = Data = raw address bytes).
        if let withdrawals = body.withdrawals {
            for rewardAccount in withdrawals.data.keys {
                if let addr = try? Address(from: .bytes(rewardAccount)) {
                    await fetchAccountContext(address: addr)
                }
            }
        }

        // Stake addresses derived from certificate stake credentials.
        if let certs = body.certificates {
            for cert in certs.asList {
                guard let stakeCredential = stakeCredential(from: cert) else { continue }
                let stakingPart: StakingPart
                switch stakeCredential.credential {
                case .verificationKeyHash(let vkh):
                    stakingPart = .verificationKeyHash(vkh)
                case .scriptHash(let sh):
                    stakingPart = .scriptHash(sh)
                }
                if let addr = try? Address(paymentPart: nil, stakingPart: stakingPart, network: network) {
                    await fetchAccountContext(address: addr)
                }
            }
        }

        // MARK: - Pool Contexts

        var poolContexts: [PoolInputContext] = []
        var seenPools = Set<String>()

        if let certs = body.certificates {
            for cert in certs.asList {
                guard let poolKeyHash = poolKeyHash(from: cert) else { continue }
                let poolHex = poolKeyHash.payload.toHex
                guard seenPools.insert(poolHex).inserted else { continue }
                let poolOp = PoolOperator(poolKeyHash: poolKeyHash)
                guard let bech32 = try? poolOp.toBech32() else { continue }
                guard let info = try? await chainContext.stakePoolInfo(poolId: bech32) else { continue }
                let (isRegistered, retirementEpoch): (Bool, UInt64?) = {
                    switch info.status {
                        case .registered:        return (true, nil)
                        case .retired:           return (false, nil)
                        case .retiring(let e):   return (true, UInt64(e))
                        case nil:                return (false, nil)
                    }
                }()
                poolContexts.append(PoolInputContext(
                    poolId: poolHex,
                    isRegistered: isRegistered,
                    retirementEpoch: retirementEpoch
                ))
            }
        }

        // MARK: - DRep Contexts

        var drepContexts: [DRepInputContext] = []
        var seenDReps = Set<String>()

        if let certs = body.certificates {
            for cert in certs.asList {
                guard let _drepCredential = try drepCredential(from: cert) else {
                    continue
                }
                
                let drepHex = _drepCredential.credential.payload.toHex
                guard seenDReps.insert(drepHex).inserted else { continue }
                
                let drep = DRep(
                    credential:  try DRepType(from: _drepCredential)
                )
                
                guard let info = try? await chainContext.drepInfo(drep: drep) else {
                    continue
                }
                
                drepContexts.append(DRepInputContext(
                    drepId: try info.drep.id(),
                    isRegistered: info.status == .registered,
                    payedDeposit: info.deposit
                ))
            }
        }
        
        // MARK: - Committee Members
        
        var potentialCommitteeMembers: [CommitteeInputContext] = []
        var currentCommitteeMembers: [CommitteeInputContext] = []
        var seenCommittee = Set<String>()
        
        if let certs = body.certificates {
            for cert in certs.asList {
                guard let _committeeCredential = try committeeCredential(from: cert) else {
                    continue
                }
                
                let committeeHex = _committeeCredential.credential.payload.toHex
                guard seenCommittee.insert(committeeHex).inserted else { continue }
                
                guard let memberInfo = try? await chainContext.committeeMemberInfo(committeeMember: _committeeCredential) else {
                    continue
                }
                
                currentCommitteeMembers.append(CommitteeInputContext(
                    committeeColdCredential: memberInfo.coldCredential.description,
                    committeeHotCredential: memberInfo.hotCredential?.description,
                    isResigned: memberInfo.status == .expired || memberInfo.status == .unrecognized
                ))
            }
        }

        // MARK: - Governance Action Contexts

        var govActionContexts: [GovActionInputContext] = []
        var seenGovActions = Set<String>()

        // Collect all GovActionIDs referenced in voting procedures.
        if let votingProcedures = body.votingProcedures {
            for (_, govActionID, _) in votingProcedures.allVotes {
                guard let key = try? govActionID.id(),
                      seenGovActions.insert(key).inserted else { continue }
                
                guard let info = try? await chainContext.govActionInfo(govActionID: govActionID) else { continue }
                
                govActionContexts.append(
                    GovActionInputContext(
                        transactionId: govActionID.transactionID.payload.toHex,
                        govActionIndex: UInt16(govActionID.govActionIndex),
                        actionType: govActionType(from: info.govAction),
                        isActive: info.status == nil
                    )
                )
            }
        }

        // MARK: - Last Enacted Governance Action and Potential Committee Members from Proposal Procedures
        
        var lastEnactedGovAction: [GovActionInputContext] = []
        
        // Collect GovActionIDs referenced by proposal procedures (the "previous action" pointer).
        if let proposals = body.proposalProcedures {
            for proposal in proposals.elements {
                
                var prevAction: GovActionID? = nil
                
                switch proposal.govAction {
                    case .parameterChangeAction(let parameterChangeAction):
                        prevAction = parameterChangeAction.id
                    case .hardForkInitiationAction(let hardForkInitiationAction):
                        prevAction = hardForkInitiationAction.id
                    case .noConfidence(let noConfidence):
                        prevAction = noConfidence.id
                    case .updateCommittee(let updateCommittee):
                        prevAction = updateCommittee.id
                        
                        for coldCredential in updateCommittee.credentialEpochs.keys {
                            
                            let committeeHex = coldCredential.credential.payload.toHex
                            guard seenCommittee.insert(committeeHex).inserted else { continue }
                            
                            guard let memberInfo = try? await chainContext.committeeMemberInfo(committeeMember: coldCredential) else {
                                continue
                            }
                            
                            potentialCommitteeMembers.append(CommitteeInputContext(
                                committeeColdCredential: memberInfo.coldCredential.description,
                                committeeHotCredential: memberInfo.hotCredential?.description,
                                isResigned: memberInfo.status == .expired || memberInfo.status == .unrecognized
                            ))
                            
                        }
                    case .newConstitution(let newConstitution):
                        prevAction = newConstitution.id
                    case .treasuryWithdrawalsAction(let treasuryWithdrawals):
                        
                        for rewardAccount in treasuryWithdrawals.withdrawals.keys {
                            if let addr = try? Address(from: .bytes(rewardAccount)) {
                                await fetchAccountContext(address: addr)
                            }
                        }
                    default:
                        continue
                }
                
                guard prevAction != nil,
                      let _prevAction = prevAction else { continue }
                
                guard let key = try? _prevAction.id(),
                      seenGovActions.insert(key).inserted else { continue }
                
                guard let info = try? await chainContext.govActionInfo(govActionID: _prevAction) else { continue }
                
                lastEnactedGovAction.append(GovActionInputContext(
                    transactionId: _prevAction.transactionID.payload.toHex,
                    govActionIndex: UInt16(_prevAction.govActionIndex),
                    actionType: govActionType(from: info.govAction),
                    isActive: info.status == .enacted || info.status == .ratified
                ))
            }
        }
        
        // MARK: - Treasury Value
        
        var treasuryValue: UInt64? = nil
        if body.currentTreasuryAmount != nil {
            treasuryValue = try? await chainContext.treasury()
        }

        return ValidationContext(
            resolvedInputs: resolvedInputs,
            currentSlot: UInt64(max(0, slot)),
            network: network,
            accountContexts: accountContexts,
            poolContexts: poolContexts,
            drepContexts: drepContexts,
            govActionContexts: govActionContexts,
            lastEnactedGovAction: lastEnactedGovAction,
            currentCommitteeMembers: currentCommitteeMembers,
            potentialCommitteeMembers: potentialCommitteeMembers,
            treasuryValue: treasuryValue,
            currentEpoch: UInt64(max(0, epoch)),
            era: era
        )
    }

    // MARK: - Certificate Field Extractors

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
    
    private static func drepCredential(from cert: Certificate) throws -> DRepCredential? {
        switch cert {
            case .registerDRep(let c):               return c.drepCredential
            case .unRegisterDRep(let c):             return c.drepCredential
            case .updateDRep(let c):                 return c.drepCredential
            case .voteDelegate(let c):               return try c.drep.credential.toDRepCredential()
            case .stakeVoteDelegate(let c):          return try c.drep.credential.toDRepCredential()
            case .voteRegisterDelegate(let c):       return try c.drep.credential.toDRepCredential()
            case .stakeVoteRegisterDelegate(let c):  return try c.drep.credential.toDRepCredential()
            default:                                 return nil
        }
    }
    
    private static func committeeCredential(from cert: Certificate) throws -> CommitteeColdCredential? {
        switch cert {
            case .authCommitteeHot(let c):           return c.committeeColdCredential
            case .resignCommitteeCold(let c):        return c.committeeColdCredential
            default:                                 return nil
        }
    }

    // MARK: - GovAction → GovActionType mapping

    private static func govActionType(from action: GovAction) -> GovActionType {
        switch action {
            case .parameterChangeAction:     return .parameterChange
            case .hardForkInitiationAction:  return .hardForkInitiation
            case .treasuryWithdrawalsAction: return .treasuryWithdrawals
            case .noConfidence:              return .noConfidence
            case .updateCommittee:           return .updateCommittee
            case .newConstitution:           return .newConstitution
            case .infoAction:                return .info
        }
    }
}
