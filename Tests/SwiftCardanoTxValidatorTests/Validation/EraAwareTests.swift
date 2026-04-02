import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - Era-Aware Validation Tests (Batch 8)

@Suite("EraAwareValidation")
struct EraAwareTests {

    // MARK: - Helpers

    private func makeAddr() throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
    }

    private func makeBody(
        certificates: ListOrNonEmptyOrderedSet<Certificate>? = nil,
        proposalProcedures: ProposalProcedures? = nil,
        votingProcedures: VotingProcedures? = nil
    ) throws -> TransactionBody {
        let txId = TransactionId(payload: Data(repeating: 0xEA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try makeAddr()
        return TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: certificates,
            votingProcedures: votingProcedures,
            proposalProcedures: proposalProcedures
        )
    }

    private func makeTx(_ body: TransactionBody) -> Transaction {
        Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
    }

    // MARK: - ValidationContext era field

    @Test("ValidationContext stores era correctly")
    func contextStoresEra() {
        let ctx = ValidationContext(era: .shelley)
        #expect(ctx.era == .shelley)
    }

    @Test("ValidationContext era defaults to nil")
    func contextEraDefaultsToNil() {
        let ctx = ValidationContext()
        #expect(ctx.era == nil)
    }

    // MARK: - Era comparison

    @Test("Era comparison is chronological")
    func eraComparison() {
        #expect(Era.byron < Era.shelley)
        #expect(Era.shelley < Era.alonzo)
        #expect(Era.babbage < Era.conway)
        #expect(!(Era.conway < Era.babbage))
    }

    // MARK: - GovernanceProposalRule: skipped pre-Conway

    @Test("GovernanceProposalRule skips validation when era is Shelley")
    func govProposalRuleSkippedInShelley() throws {
        let pp = try loadProtocolParams()
        let anchor = Anchor(
            anchorUrl: try Url("https://test.example.com"),
            anchorDataHash: AnchorDataHash(payload: Data(repeating: 0xAA, count: 32))
        )
        // Mainnet reward account — in Conway+testnet context this would emit a network mismatch.
        let mainnetReward: RewardAccount = Data([0xE1] + [UInt8](repeating: 0x01, count: 28))
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: mainnetReward,
            govAction: .infoAction(InfoAction()),
            anchor: anchor
        )
        let body = try makeBody(proposalProcedures: NonEmptyOrderedSet([proposal]))
        let tx = makeTx(body)

        // Shelley era — GovernanceProposalRule must skip entirely.
        let shelleyCtx = ValidationContext(network: .testnet, era: .shelley)
        let issues = try GovernanceProposalRule().validate(
            transaction: tx, context: shelleyCtx, protocolParams: pp
        )
        #expect(issues.isEmpty,
            "GovernanceProposalRule should produce no issues when era < conway")
    }

    @Test("GovernanceProposalRule runs when era is nil (Conway default)")
    func govProposalRuleRunsWhenEraIsNil() throws {
        let pp = try loadProtocolParams()
        let anchor = Anchor(
            anchorUrl: try Url("https://test.example.com"),
            anchorDataHash: AnchorDataHash(payload: Data(repeating: 0xAA, count: 32))
        )
        let mainnetReward: RewardAccount = Data([0xE1] + [UInt8](repeating: 0x01, count: 28))
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: mainnetReward,
            govAction: .infoAction(InfoAction()),
            anchor: anchor
        )
        let body = try makeBody(proposalProcedures: NonEmptyOrderedSet([proposal]))
        let tx = makeTx(body)

        // era: nil → Conway; testnet context should flag network mismatch.
        let conwayCtx = ValidationContext(network: .testnet)
        let issues = try GovernanceProposalRule().validate(
            transaction: tx, context: conwayCtx, protocolParams: pp
        )
        #expect(issues.contains { $0.kind == .proposalProcedureNetworkIdMismatch },
            "GovernanceProposalRule should run and flag issues when era is nil (Conway default)")
    }

    // MARK: - VotingRule: skipped pre-Conway

    @Test("VotingRule skips validation when era is Babbage")
    func votingRuleSkippedInBabbage() throws {
        let pp = try loadProtocolParams()
        let govActionId = GovActionID(
            transactionID: TransactionId(payload: Data(repeating: 0xAB, count: 32)),
            govActionIndex: 0
        )
        let voter = Voter(credential: .drepKeyhash(
            VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
        ))
        var vp = VotingProcedures()
        vp[voter, govActionId] = VotingProcedure(vote: .yes)

        let body = try makeBody(votingProcedures: vp)
        let tx = makeTx(body)

        // In Conway era with non-empty govActionContexts this would emit govActionsDoNotExist.
        // In Babbage era the rule should be skipped.
        let babbageCtx = ValidationContext(
            govActionContexts: [GovActionInputContext(
                transactionId: "dummy", govActionIndex: 99,
                actionType: .info, isActive: true
            )],
            era: .babbage
        )
        let issues = try VotingRule().validate(
            transaction: tx, context: babbageCtx, protocolParams: pp
        )
        #expect(issues.isEmpty,
            "VotingRule should produce no issues when era < conway")
    }

    // MARK: - RegistrationRule: Conway-only cert types skipped pre-Conway

    @Test("RegistrationRule skips registerDRep cert when era is Babbage")
    func regRuleSkipsDRepCertInBabbage() throws {
        let pp = try loadProtocolParams()
        let drepCred = DRepCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x10, count: 28))
            )
        )
        let registerDRepCert = Certificate.registerDRep(
            RegisterDRep(drepCredential: drepCred, coin: 500_000_000, anchor: nil)
        )
        let body = try makeBody(certificates: .list([registerDRepCert]))
        let tx = makeTx(body)

        let babbageCtx = ValidationContext(
            drepContexts: [DRepInputContext(drepId: "other", isRegistered: false)],
            era: .babbage
        )
        let issues = try RegistrationRule().validate(
            transaction: tx, context: babbageCtx, protocolParams: pp
        )
        // registerDRep is Conway-only — no issues expected in Babbage.
        #expect(issues.isEmpty,
            "RegistrationRule should skip registerDRep cert when era < conway")
    }

    @Test("RegistrationRule validates stakeRegistration in Shelley era")
    func regRuleValidatesStakeRegInShelley() throws {
        let pp = try loadProtocolParams()
        let stakeCred = StakeCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x11, count: 28))
            )
        )
        let stakeRegCert = Certificate.stakeRegistration(
            StakeRegistration(stakeCredential: stakeCred)
        )
        let body = try makeBody(certificates: .list([stakeRegCert]))
        let tx = makeTx(body)

        let stakeId = "\(stakeCred)"
        // Account already registered → should emit stakeAlreadyRegistered even in Shelley.
        let shelleyCtx = ValidationContext(
            accountContexts: [AccountInputContext(rewardAddress: stakeId, isRegistered: true)],
            era: .shelley
        )
        let issues = try RegistrationRule().validate(
            transaction: tx, context: shelleyCtx, protocolParams: pp
        )
        #expect(issues.contains { $0.kind == .stakeAlreadyRegistered },
            "RegistrationRule should still validate stakeRegistration in Shelley era")
    }

    // MARK: - RegistrationRule: pool cost check is Alonzo+

    @Test("RegistrationRule skips pool cost check when era is Shelley")
    func regRuleSkipsPoolCostInShelley() throws {
        let pp = try loadProtocolParams()  // minPoolCost > 0 in real params
        let poolKey = PoolKeyHash(payload: Data(repeating: 0x20, count: 28))
        let vrfKey = VrfKeyHash(payload: Data(repeating: 0x21, count: 32))
        let rewardAccount = RewardAccountHash(payload: Data(repeating: 0x22, count: 29))
        let owner = VerificationKeyHash(payload: Data(repeating: 0x2F, count: 28))
        let poolParams = PoolParams(
            poolOperator: poolKey,
            vrfKeyHash: vrfKey,
            pledge: 1_000_000,
            cost: 0,        // Below minPoolCost
            margin: UnitInterval(numerator: 1, denominator: 10),
            rewardAccount: rewardAccount,
            poolOwners: .list([owner]),
            relays: nil,
            poolMetadata: nil
        )
        let poolRegCert = Certificate.poolRegistration(PoolRegistration(poolParams: poolParams))
        let body = try makeBody(certificates: .list([poolRegCert]))
        let tx = makeTx(body)

        let shelleyCtx = ValidationContext(
            poolContexts: [PoolInputContext(poolId: "\(poolKey)", isRegistered: false)],
            era: .shelley
        )
        let issues = try RegistrationRule().validate(
            transaction: tx, context: shelleyCtx, protocolParams: pp
        )
        let costIssues = issues.filter { $0.kind == .stakePoolCostTooLow }
        #expect(costIssues.isEmpty,
            "RegistrationRule should not check pool cost when era < alonzo")
    }

    @Test("RegistrationRule checks pool cost when era is Alonzo")
    func regRuleChecksPoolCostInAlonzo() throws {
        let pp = try loadProtocolParams()
        let poolKey = PoolKeyHash(payload: Data(repeating: 0x23, count: 28))
        let vrfKey = VrfKeyHash(payload: Data(repeating: 0x24, count: 32))
        let rewardAccount = RewardAccountHash(payload: Data(repeating: 0x25, count: 29))
        let owner = VerificationKeyHash(payload: Data(repeating: 0x2E, count: 28))
        let poolParams = PoolParams(
            poolOperator: poolKey,
            vrfKeyHash: vrfKey,
            pledge: 1_000_000,
            cost: 0,        // Below minPoolCost
            margin: UnitInterval(numerator: 1, denominator: 10),
            rewardAccount: rewardAccount,
            poolOwners: .list([owner]),
            relays: nil,
            poolMetadata: nil
        )
        let poolRegCert = Certificate.poolRegistration(PoolRegistration(poolParams: poolParams))
        let body = try makeBody(certificates: .list([poolRegCert]))
        let tx = makeTx(body)

        let alonzoCtx = ValidationContext(
            poolContexts: [PoolInputContext(poolId: "\(poolKey)", isRegistered: false)],
            era: .alonzo
        )
        let issues = try RegistrationRule().validate(
            transaction: tx, context: alonzoCtx, protocolParams: pp
        )
        let costIssues = issues.filter { $0.kind == .stakePoolCostTooLow }
        #expect(!costIssues.isEmpty,
            "RegistrationRule should check pool cost when era >= alonzo")
    }
}
