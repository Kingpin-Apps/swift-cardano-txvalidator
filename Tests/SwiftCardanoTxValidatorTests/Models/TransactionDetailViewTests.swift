import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxValidator

@Suite("Transaction detail views")
struct TransactionDetailViewTests {
    func inspect(_ feature: String, era: Era? = nil) throws -> TransactionView? {
        guard let entry = EraCorpus.entries.first(where: { $0.features.contains(feature) && (era == nil || $0.era == era) })
        else { return nil }
        return try TxValidator().inspect(cborHex: try entry.hex())
    }

    @Test("Every redeemer of an accepted transaction points at something", arguments: EraCorpus.entries.filter { $0.features.contains("redeemers") })
    func everyRedeemerHasAPurpose(_ entry: EraCorpus.Entry) throws {
        let view = try TxValidator().inspect(cborHex: try entry.hex())
        #expect(!view.redeemers.isEmpty)
        #expect(view.redeemers.count == view.redeemerCount)
        for redeemer in view.redeemers {
            #expect(redeemer.purpose != nil, "\(redeemer.tag)[\(redeemer.index)]")
            #expect(redeemer.exUnits != nil)
            #expect(!redeemer.dataCBORHex.isEmpty)
        }
    }

    @Test func certificates() throws {
        let view = try #require(try inspect("drep-reg"))
        let registration = view.certificates.first { $0.kind == "registerDRep" }
        #expect((registration?.deposit ?? 0) > 0)
        #expect(registration?.credential != nil)
        #expect(view.certificates.map(\.index) == Array(view.certificates.indices))
        let delegation = try #require(try inspect("stake-deleg", era: .shelley))
        #expect(delegation.certificates.contains { $0.kind == "stakeDelegation" && $0.pool != nil })
    }

    @Test func votes() throws {
        let view = try #require(try inspect("cc-vote"))
        #expect(!view.votes.isEmpty)
        #expect(view.votes.allSatisfy { ["yes", "no", "abstain"].contains($0.vote) && $0.govActionId.contains("#") })
        #expect(view.votes.contains { $0.voterRole == "committee" })
    }

    @Test func proposals() throws {
        let view = try #require(try inspect("parameter-change"))
        #expect(view.proposals.first?.actionType == "parameterChange")
        #expect((view.proposals.first?.deposit ?? 0) > 0)
        let treasury = try #require(try inspect("treasury-withdrawal"))
        #expect(treasury.proposals.contains { $0.actionType == "treasuryWithdrawals" })
        #expect(treasury.redeemers.contains { $0.tag == "proposing" && $0.purpose == "proposal[0]" })
    }

    @Test func withdrawals() throws {
        let view = try #require(try inspect("withdrawal"))
        #expect(!view.withdrawals.isEmpty)
        let addresses = view.withdrawals.map(\.rewardAddress)
        #expect(addresses.allSatisfy { $0.hasPrefix("stake") })
    }

    @Test func datumsAndScripts() throws {
        let view = try #require(try inspect("datums"))
        #expect(!view.datums.isEmpty)
        #expect(view.datums.allSatisfy { $0.hash.count == 64 && !$0.cborHex.isEmpty })
        let v3 = try #require(try inspect("plutus-v3"))
        #expect(v3.scripts.contains { $0.language == "plutusV3" && $0.hash.count == 56 && $0.size > 0 })
    }

    @Test func erasAreDescribed() throws {
        let votes = try #require(try inspect("votes"))
        #expect(votes.possibleEras == "conway")
        let update = try #require(try inspect("update", era: .alonzo))
        #expect(update.possibleEras == "alonzo…babbage")
    }

    @Test("The view still encodes and decodes")
    func codableRoundTrip() throws {
        let view = try #require(try inspect("cc-vote"))
        let decoded = try JSONDecoder().decode(TransactionView.self, from: try JSONEncoder().encode(view))
        #expect(decoded == view)
    }
}
