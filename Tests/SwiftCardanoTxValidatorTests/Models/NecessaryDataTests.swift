import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

@Suite("NecessaryData")
struct NecessaryDataTests {

    // MARK: - Model instantiation

    @Test("TransactionInputRef can be created and compared")
    func transactionInputRef() {
        let ref1 = TransactionInputRef(transactionId: "deadbeef", index: 0)
        let ref2 = TransactionInputRef(transactionId: "deadbeef", index: 0)
        let ref3 = TransactionInputRef(transactionId: "cafebabe", index: 1)

        #expect(ref1 == ref2)
        #expect(ref1 != ref3)
    }

    @Test("GovActionIdRef can be created and compared")
    func govActionIdRef() {
        let ref1 = GovActionIdRef(transactionId: "deadbeef", govActionIndex: 0)
        let ref2 = GovActionIdRef(transactionId: "deadbeef", govActionIndex: 0)
        let ref3 = GovActionIdRef(transactionId: "cafebabe", govActionIndex: 1)

        #expect(ref1 == ref2)
        #expect(ref1 != ref3)
    }

    @Test("NecessaryData is Codable")
    func necessaryDataCodable() throws {
        let data = NecessaryData(
            inputs: [TransactionInputRef(transactionId: "abc", index: 0)],
            rewardAccounts: ["stake1abc"],
            stakePools: ["pool1xyz"],
            dReps: ["drep1abc"],
            govActionIds: [GovActionIdRef(transactionId: "def", govActionIndex: 0)],
            lastEnactedGovActionTypes: [.hardForkInitiation],
            committeeMembersCold: ["cold1abc"],
            committeeMembersHot: ["hot1xyz"]
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(NecessaryData.self, from: encoded)

        #expect(decoded.inputs.count == 1)
        #expect(decoded.inputs[0].transactionId == "abc")
        #expect(decoded.rewardAccounts == ["stake1abc"])
        #expect(decoded.stakePools == ["pool1xyz"])
        #expect(decoded.dReps == ["drep1abc"])
        #expect(decoded.govActionIds.count == 1)
        #expect(decoded.lastEnactedGovActionTypes == [.hardForkInitiation])
    }

    // MARK: - NecessaryData.from(Transaction) integration

    @Test("NecessaryData.from extracts spending inputs")
    func necessaryDataFromTransaction() throws {
        // Build a minimal transaction with one spending input and one output.
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 200_000)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let result = NecessaryData.from(tx)

        #expect(result.inputs.count == 1)
        #expect(result.inputs[0].index == 0)
        #expect(result.rewardAccounts.isEmpty)
        #expect(result.stakePools.isEmpty)
        #expect(result.dReps.isEmpty)
        #expect(result.govActionIds.isEmpty)
        #expect(result.lastEnactedGovActionTypes.isEmpty)
    }

    @Test("NecessaryData.from extracts lastEnactedGovActionTypes from proposals")
    func necessaryDataFromProposals() throws {
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))

        let rewardAccount: RewardAccount = Data([0xE0] + [UInt8](repeating: 0x01, count: 28))
        let anchor = Anchor(
            anchorUrl: try Url("https://test.example.com"),
            anchorDataHash: AnchorDataHash(payload: Data(repeating: 0, count: 32))
        )
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .infoAction(InfoAction()),
            anchor: anchor
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [output],
            fee: 200_000,
            proposalProcedures: NonEmptyOrderedSet([proposal])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let result = NecessaryData.from(tx)

        #expect(result.lastEnactedGovActionTypes == [.info])
    }

    // MARK: - RedeemerEvalResult model

    @Test("ExUnitsView equality and coding")
    func exUnitsViewCodable() throws {
        let eu1 = ExUnitsView(memory: 14_000_000, steps: 10_000_000_000)
        let eu2 = ExUnitsView(memory: 14_000_000, steps: 10_000_000_000)
        #expect(eu1 == eu2)

        let encoded = try JSONEncoder().encode(eu1)
        let decoded = try JSONDecoder().decode(ExUnitsView.self, from: encoded)
        #expect(decoded.memory == 14_000_000)
        #expect(decoded.steps  == 10_000_000_000)
    }

    @Test("RedeemerEvalResult is Codable")
    func redeemerEvalResultCodable() throws {
        let result = RedeemerEvalResult(
            index: 0,
            passed: true,
            remainingBudget: ExUnitsView(memory: 12_000_000, steps: 9_000_000_000),
            logs: ["trace: OK"],
            error: nil
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RedeemerEvalResult.self, from: encoded)

        #expect(decoded.index == 0)
        #expect(decoded.passed)
        #expect(decoded.remainingBudget.memory == 12_000_000)
        #expect(decoded.logs == ["trace: OK"])
        #expect(decoded.error == nil)
    }

    @Test("TxValidatorReport has redeemerEvalResults field")
    func reportHasRedeemerEvalResults() async throws {
        let pp  = try loadProtocolParams()
        let ctx = ValidationContext()

        // Build a minimal transaction programmatically (no scripts → Phase-2 not run).
        let txId = TransactionId(payload: Data(repeating: 0xBB, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x02, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(address: addr, amount: Value(coin: 2_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 200_000)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let phase1 = Phase1Validator()
        let phase1Result = try await phase1.validate(
            transaction: tx,
            context: ctx,
            protocolParams: pp
        )
        // Phase-2 not run → redeemerEvalResults is nil on a report built without it
        let view = try TransactionParser().buildView(transaction: tx)
        let report = TxValidatorReport(
            transactionView: view,
            phase1Result: phase1Result,
            phase2Result: nil,
            redeemerEvalResults: nil
        )

        #expect(report.redeemerEvalResults == nil)
    }
}
