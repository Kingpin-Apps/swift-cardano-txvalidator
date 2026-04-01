import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - VotingRule Tests

@Suite("VotingRule")
struct VotingRuleTests {

    // MARK: - Helpers

    private func makeHash(_ byte: UInt8) -> VerificationKeyHash {
        VerificationKeyHash(payload: Data(repeating: byte, count: 28))
    }

    private func makeGovActionId(byte: UInt8 = 0xAB, index: UInt16 = 0) -> GovActionID {
        GovActionID(
            transactionID: TransactionId(payload: Data(repeating: byte, count: 32)),
            govActionIndex: index
        )
    }

    private func makeActiveGovAction(
        txIdByte: UInt8,
        index: UInt16 = 0,
        actionType: GovActionType,
        isActive: Bool = true
    ) -> GovActionInputContext {
        GovActionInputContext(
            transactionId: "\(TransactionId(payload: Data(repeating: txIdByte, count: 32)))",
            govActionIndex: index,
            actionType: actionType,
            isActive: isActive
        )
    }

    private func makeMinimalBody(
        votingProcedures: VotingProcedures? = nil
    ) -> TransactionBody {
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try! Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        return TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            votingProcedures: votingProcedures
        )
    }

    private func runRule(
        votingProcedures: VotingProcedures?,
        context: ValidationContext = ValidationContext()
    ) throws -> [ValidationError] {
        let body = makeMinimalBody(votingProcedures: votingProcedures)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let pp = try loadProtocolParams()
        return try VotingRule().validate(transaction: tx, context: context, protocolParams: pp)
    }

    // MARK: - No votes → pass

    @Test("No voting procedures produces no issues")
    func noVotingProcedures() throws {
        let issues = try runRule(votingProcedures: nil)
        #expect(issues.isEmpty)
    }

    // MARK: - Gov action existence

    @Test("govActionsDoNotExist when gov action not in context")
    func govActionNotFound() throws {
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .drepKeyhash(makeHash(0x01)))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        // Non-empty context but doesn't contain the referenced action
        let ctx = ValidationContext(
            govActionContexts: [
                makeActiveGovAction(txIdByte: 0xFF, actionType: .parameterChange)
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .govActionsDoNotExist })
    }

    @Test("votingOnExpiredGovAction when action is inactive")
    func votingOnExpiredAction() throws {
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .drepKeyhash(makeHash(0x01)))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .parameterChange,
                    isActive: false  // expired
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .votingOnExpiredGovAction })
    }

    @Test("Skip gov action check when govActionContexts is empty")
    func skipGovActionCheckWithEmptyContext() throws {
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .drepKeyhash(makeHash(0x01)))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let issues = try runRule(votingProcedures: vp, context: ValidationContext())
        #expect(!issues.contains { $0.kind == .govActionsDoNotExist })
        #expect(!issues.contains { $0.kind == .votingOnExpiredGovAction })
    }

    // MARK: - Voter existence checks

    @Test("voterDoesNotExist for unknown CC hot credential")
    func ccVoterNotFound() throws {
        let hash = makeHash(0x01)
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .constitutionalCommitteeHotKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        // Provide committee context but not for this hot credential
        let ctx = ValidationContext(
            currentCommitteeMembers: [
                CommitteeInputContext(
                    committeeColdCredential: "cold_other",
                    committeeHotCredential: "hot_other"
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .voterDoesNotExist })
    }

    @Test("voterDoesNotExist for unregistered DRep")
    func drepVoterNotRegistered() throws {
        let hash = makeHash(0x02)
        let drepIdStr = "\(hash)"
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .drepKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let ctx = ValidationContext(
            drepContexts: [
                DRepInputContext(drepId: drepIdStr, isRegistered: false)
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .voterDoesNotExist })
    }

    @Test("voterDoesNotExist for unknown SPO")
    func spoVoterNotFound() throws {
        let hash = makeHash(0x03)
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .stakePoolKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        // Pool context but not for this pool
        let ctx = ValidationContext(
            poolContexts: [
                PoolInputContext(poolId: "other_pool", isRegistered: true)
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .voterDoesNotExist })
    }

    @Test("Skip voter check when context is empty")
    func skipVoterCheckWithEmptyContext() throws {
        let govActionId = makeGovActionId(byte: 0xAB)
        let voter = Voter(credential: .drepKeyhash(makeHash(0x99)))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .no)

        let issues = try runRule(votingProcedures: vp, context: ValidationContext())
        #expect(!issues.contains { $0.kind == .voterDoesNotExist })
    }

    // MARK: - CIP-1694 voting permission checks

    @Test("disallowedVoter when CC votes on NoConfidence")
    func ccVoteOnNoConfidenceDisallowed() throws {
        let hash = makeHash(0x01)
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .constitutionalCommitteeHotKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .noConfidence,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .disallowedVoter })
    }

    @Test("disallowedVoter when CC votes on UpdateCommittee")
    func ccVoteOnUpdateCommitteeDisallowed() throws {
        let hash = makeHash(0x01)
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .constitutionalCommitteeHotKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .updateCommittee,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .disallowedVoter })
    }

    @Test("disallowedVoter when SPO votes on ParameterChange")
    func spoVoteOnParameterChangeDisallowed() throws {
        let hash = makeHash(0x04)
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .stakePoolKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .parameterChange,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .disallowedVoter })
    }

    @Test("disallowedVoter when SPO votes on TreasuryWithdrawals")
    func spoVoteOnTreasuryWithdrawalsDisallowed() throws {
        let hash = makeHash(0x04)
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .stakePoolKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .no)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .treasuryWithdrawals,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .disallowedVoter })
    }

    @Test("disallowedVoter when SPO votes on NewConstitution")
    func spoVoteOnNewConstitutionDisallowed() throws {
        let hash = makeHash(0x04)
        let govActionId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(govActionId.transactionID)"
        let voter = Voter(credential: .stakePoolKeyhash(hash))

        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .no)

        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: govActionId.govActionIndex,
                    actionType: .newConstitution,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(votingProcedures: vp, context: ctx)
        #expect(issues.contains { $0.kind == .disallowedVoter })
    }

    // MARK: - Allowed votes

    @Test("DRep can vote on any action type")
    func drepVoteAllowed() throws {
        let hash = makeHash(0x02)
        let voter = Voter(credential: .drepKeyhash(hash))
        let actionTypes: [GovActionType] = [
            .parameterChange, .hardForkInitiation, .treasuryWithdrawals,
            .noConfidence, .updateCommittee, .newConstitution, .info
        ]

        for actionType in actionTypes {
            let govActionId = makeGovActionId(byte: 0xAB)
            let txIdStr = "\(govActionId.transactionID)"

            var vp = VotingProcedures()
            vp[voter, govActionId] = VotingProcedure(vote: .yes)

            let ctx = ValidationContext(
                govActionContexts: [
                    GovActionInputContext(
                        transactionId: txIdStr,
                        govActionIndex: govActionId.govActionIndex,
                        actionType: actionType,
                        isActive: true
                    )
                ]
            )
            let issues = try runRule(votingProcedures: vp, context: ctx)
            #expect(
                !issues.contains { $0.kind == .disallowedVoter },
                "DRep should be allowed to vote on \(actionType)"
            )
        }
    }

    @Test("CC can vote on HardForkInitiation, ParameterChange, TreasuryWithdrawals, NewConstitution, InfoAction")
    func ccVoteAllowedTypes() throws {
        let hash = makeHash(0x01)
        let voter = Voter(credential: .constitutionalCommitteeHotKeyhash(hash))
        let allowedTypes: [GovActionType] = [
            .hardForkInitiation, .parameterChange, .treasuryWithdrawals,
            .newConstitution, .info
        ]

        for actionType in allowedTypes {
            let govActionId = makeGovActionId(byte: 0xAB)
            let txIdStr = "\(govActionId.transactionID)"

            var vp = VotingProcedures()
            vp[voter, govActionId] = VotingProcedure(vote: .yes)

            let ctx = ValidationContext(
                govActionContexts: [
                    GovActionInputContext(
                        transactionId: txIdStr,
                        govActionIndex: govActionId.govActionIndex,
                        actionType: actionType,
                        isActive: true
                    )
                ]
            )
            let issues = try runRule(votingProcedures: vp, context: ctx)
            #expect(
                !issues.contains { $0.kind == .disallowedVoter },
                "CC should be allowed to vote on \(actionType)"
            )
        }
    }

    @Test("SPO can vote on NoConfidence, UpdateCommittee, HardForkInitiation, InfoAction")
    func spoVoteAllowedTypes() throws {
        let hash = makeHash(0x04)
        let voter = Voter(credential: .stakePoolKeyhash(hash))
        let allowedTypes: [GovActionType] = [
            .noConfidence, .updateCommittee, .hardForkInitiation, .info
        ]

        for actionType in allowedTypes {
            let govActionId = makeGovActionId(byte: 0xAB)
            let txIdStr = "\(govActionId.transactionID)"

            var vp = VotingProcedures()
            vp[voter, govActionId] = VotingProcedure(vote: .yes)

            let ctx = ValidationContext(
                govActionContexts: [
                    GovActionInputContext(
                        transactionId: txIdStr,
                        govActionIndex: govActionId.govActionIndex,
                        actionType: actionType,
                        isActive: true
                    )
                ]
            )
            let issues = try runRule(votingProcedures: vp, context: ctx)
            #expect(
                !issues.contains { $0.kind == .disallowedVoter },
                "SPO should be allowed to vote on \(actionType)"
            )
        }
    }
}
