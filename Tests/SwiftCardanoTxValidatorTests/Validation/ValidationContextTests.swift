import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("ValidationContext")
struct ValidationContextTests {

    // MARK: - Default initialization

    @Test("Default context has empty collections and nil optionals")
    func defaultInit() {
        let ctx = ValidationContext()
        #expect(ctx.resolvedInputs.isEmpty)
        #expect(ctx.currentSlot == nil)
        #expect(ctx.network == nil)
        #expect(ctx.accountContexts.isEmpty)
        #expect(ctx.poolContexts.isEmpty)
        #expect(ctx.drepContexts.isEmpty)
        #expect(ctx.govActionContexts.isEmpty)
        #expect(ctx.lastEnactedGovAction.isEmpty)
        #expect(ctx.currentCommitteeMembers.isEmpty)
        #expect(ctx.potentialCommitteeMembers.isEmpty)
        #expect(ctx.treasuryValue == nil)
        #expect(ctx.currentEpoch == nil)
    }

    // MARK: - Account finder

    @Test("findAccountContext returns matching account")
    func findAccount() {
        let ctx = ValidationContext(accountContexts: [
            AccountInputContext(rewardAddress: "stake1abc", isRegistered: true),
            AccountInputContext(rewardAddress: "stake1xyz", isRegistered: false),
        ])
        let found = ctx.findAccountContext(rewardAddress: "stake1xyz")
        #expect(found != nil)
        #expect(found?.isRegistered == false)
    }

    @Test("findAccountContext returns nil when not found")
    func findAccountMissing() {
        let ctx = ValidationContext(accountContexts: [
            AccountInputContext(rewardAddress: "stake1abc", isRegistered: true),
        ])
        #expect(ctx.findAccountContext(rewardAddress: "other") == nil)
    }

    // MARK: - Pool finder

    @Test("findPoolContext returns matching pool")
    func findPool() {
        let ctx = ValidationContext(poolContexts: [
            PoolInputContext(poolId: "pool1abc", isRegistered: true),
        ])
        #expect(ctx.findPoolContext(poolId: "pool1abc") != nil)
        #expect(ctx.findPoolContext(poolId: "pool1other") == nil)
    }

    // MARK: - DRep finder

    @Test("findDRepContext returns matching DRep")
    func findDRep() {
        let ctx = ValidationContext(drepContexts: [
            DRepInputContext(drepId: "drep1abc", isRegistered: true),
        ])
        #expect(ctx.findDRepContext(drepId: "drep1abc") != nil)
        #expect(ctx.findDRepContext(drepId: "drep1other") == nil)
    }

    // MARK: - GovAction finder

    @Test("findGovActionContext matches by txId and index")
    func findGovAction() {
        let ctx = ValidationContext(govActionContexts: [
            GovActionInputContext(transactionId: "abc", govActionIndex: 0, actionType: .info, isActive: true),
            GovActionInputContext(transactionId: "abc", govActionIndex: 1, actionType: .noConfidence, isActive: false),
        ])
        let found = ctx.findGovActionContext(transactionId: "abc", govActionIndex: 1)
        #expect(found != nil)
        #expect(found?.actionType == .noConfidence)
        #expect(ctx.findGovActionContext(transactionId: "abc", govActionIndex: 2) == nil)
    }

    // MARK: - Last enacted gov action finder

    @Test("findLastEnactedGovAction matches by type")
    func findLastEnacted() {
        let ctx = ValidationContext(lastEnactedGovAction: [
            GovActionInputContext(transactionId: "a", govActionIndex: 0, actionType: .parameterChange, isActive: false),
        ])
        #expect(ctx.findLastEnactedGovAction(actionType: .parameterChange) != nil)
        #expect(ctx.findLastEnactedGovAction(actionType: .info) == nil)
    }

    // MARK: - Committee finders

    @Test("findCurrentCommitteeMember by cold credential")
    func findCurrentCommittee() {
        let ctx = ValidationContext(currentCommitteeMembers: [
            CommitteeInputContext(committeeColdCredential: "cold1", committeeHotCredential: "hot1"),
        ])
        #expect(ctx.findCurrentCommitteeMember(coldCredential: "cold1") != nil)
        #expect(ctx.findCurrentCommitteeMember(coldCredential: "cold2") == nil)
    }

    @Test("findPotentialCommitteeMember by cold credential")
    func findPotentialCommittee() {
        let ctx = ValidationContext(potentialCommitteeMembers: [
            CommitteeInputContext(committeeColdCredential: "cold1"),
        ])
        #expect(ctx.findPotentialCommitteeMember(coldCredential: "cold1") != nil)
    }

    @Test("findCurrentCommitteeMemberByHot by hot credential")
    func findByHot() {
        let ctx = ValidationContext(currentCommitteeMembers: [
            CommitteeInputContext(committeeColdCredential: "cold1", committeeHotCredential: "hot1"),
            CommitteeInputContext(committeeColdCredential: "cold2"),
        ])
        #expect(ctx.findCurrentCommitteeMemberByHot(hotCredential: "hot1") != nil)
        #expect(ctx.findCurrentCommitteeMemberByHot(hotCredential: "hot2") == nil)
    }

    @Test("findPotentialCommitteeMemberByHot by hot credential")
    func findPotentialByHot() {
        let ctx = ValidationContext(potentialCommitteeMembers: [
            CommitteeInputContext(committeeColdCredential: "cold1", committeeHotCredential: "hot1"),
        ])
        #expect(ctx.findPotentialCommitteeMemberByHot(hotCredential: "hot1") != nil)
        #expect(ctx.findPotentialCommitteeMemberByHot(hotCredential: "missing") == nil)
    }
}
