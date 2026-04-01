import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("InputContexts")
struct InputContextsTests {

    // MARK: - AccountInputContext

    @Test("AccountInputContext Codable round-trip")
    func accountCodable() throws {
        let ctx = AccountInputContext(
            rewardAddress: "stake_test1abc",
            isRegistered: true,
            payedDeposit: 2_000_000,
            delegatedToDRep: "drep1xyz",
            delegatedToPool: "pool1abc",
            balance: 500_000
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(AccountInputContext.self, from: data)
        #expect(decoded == ctx)
    }

    @Test("AccountInputContext defaults are nil")
    func accountDefaults() {
        let ctx = AccountInputContext(rewardAddress: "stake1abc", isRegistered: false)
        #expect(ctx.payedDeposit == nil)
        #expect(ctx.delegatedToDRep == nil)
        #expect(ctx.delegatedToPool == nil)
        #expect(ctx.balance == nil)
    }

    // MARK: - PoolInputContext

    @Test("PoolInputContext Codable round-trip")
    func poolCodable() throws {
        let ctx = PoolInputContext(poolId: "pool1xyz", isRegistered: true, retirementEpoch: 300)
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(PoolInputContext.self, from: data)
        #expect(decoded == ctx)
    }

    // MARK: - DRepInputContext

    @Test("DRepInputContext Codable round-trip")
    func drepCodable() throws {
        let ctx = DRepInputContext(drepId: "drep1abc", isRegistered: true, payedDeposit: 500_000_000)
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(DRepInputContext.self, from: data)
        #expect(decoded == ctx)
    }

    // MARK: - GovActionInputContext

    @Test("GovActionInputContext Codable round-trip")
    func govActionCodable() throws {
        let ctx = GovActionInputContext(
            transactionId: "deadbeef",
            govActionIndex: 0,
            actionType: .treasuryWithdrawals,
            isActive: true
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(GovActionInputContext.self, from: data)
        #expect(decoded == ctx)
    }

    // MARK: - CommitteeInputContext

    @Test("CommitteeInputContext Codable round-trip")
    func committeeCodable() throws {
        let ctx = CommitteeInputContext(
            committeeColdCredential: "cold1abc",
            committeeHotCredential: "hot1xyz",
            isResigned: false
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(CommitteeInputContext.self, from: data)
        #expect(decoded == ctx)
    }

    @Test("CommitteeInputContext defaults")
    func committeeDefaults() {
        let ctx = CommitteeInputContext(committeeColdCredential: "cold1abc")
        #expect(ctx.committeeHotCredential == nil)
        #expect(ctx.isResigned == false)
    }

    // MARK: - GovActionType

    @Test("GovActionType all cases encode correctly")
    func govActionTypeCases() throws {
        let cases: [GovActionType] = [
            .parameterChange, .hardForkInitiation, .treasuryWithdrawals,
            .noConfidence, .updateCommittee, .newConstitution, .info
        ]
        for actionType in cases {
            let data = try JSONEncoder().encode(actionType)
            let decoded = try JSONDecoder().decode(GovActionType.self, from: data)
            #expect(decoded == actionType)
        }
    }
}
