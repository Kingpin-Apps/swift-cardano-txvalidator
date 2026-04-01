import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - GovernanceProposalRule Tests

@Suite("GovernanceProposalRule")
struct GovernanceProposalRuleTests {

    // MARK: - Helpers

    private func makeAnchor() -> Anchor {
        Anchor(
            anchorUrl: try! Url("https://test.example.com"),
            anchorDataHash: AnchorDataHash(payload: Data(repeating: 0xAA, count: 32))
        )
    }

    /// 29-byte reward address: header byte followed by 28 bytes key hash.
    /// bit 0 of header = 0 → testnet, = 1 → mainnet.
    private func makeRewardAccount(network: NetworkId, keyByte: UInt8 = 0x01) -> RewardAccount {
        let header: UInt8 = network == .mainnet ? 0xE1 : 0xE0
        return Data([header] + [UInt8](repeating: keyByte, count: 28))
    }

    private func makeGovActionId(byte: UInt8 = 0xAB, index: UInt16 = 0) -> GovActionID {
        GovActionID(
            transactionID: TransactionId(payload: Data(repeating: byte, count: 32)),
            govActionIndex: index
        )
    }

    private func makeMinimalBody(
        proposalProcedures: ProposalProcedures? = nil
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
            proposalProcedures: proposalProcedures
        )
    }

    private func runRule(
        proposalProcedures: ProposalProcedures?,
        context: ValidationContext = ValidationContext()
    ) throws -> [ValidationError] {
        let body = makeMinimalBody(proposalProcedures: proposalProcedures)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let pp = try loadProtocolParams()
        return try GovernanceProposalRule().validate(transaction: tx, context: context, protocolParams: pp)
    }

    private func makeInfoProposal(rewardAccount: RewardAccount) -> ProposalProcedure {
        ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .infoAction(InfoAction()),
            anchor: makeAnchor()
        )
    }

    // MARK: - No proposals → pass

    @Test("No proposals produces no issues")
    func noProposals() throws {
        let issues = try runRule(proposalProcedures: nil)
        #expect(issues.isEmpty)
    }

    // MARK: - Network ID checks

    @Test("proposalProcedureNetworkIdMismatch when reward account has wrong network")
    func rewardAccountNetworkMismatch() throws {
        // mainnet reward account, but context expects testnet
        let rewardAccount = makeRewardAccount(network: .mainnet)
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        let ctx = ValidationContext(network: .testnet)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .proposalProcedureNetworkIdMismatch })
    }

    @Test("No network mismatch when reward account matches expected network")
    func rewardAccountNetworkMatch() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        let ctx = ValidationContext(network: .testnet)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(!issues.contains { $0.kind == .proposalProcedureNetworkIdMismatch })
    }

    // MARK: - Return account existence checks

    @Test("proposalReturnAccountDoesNotExist when return account not in context")
    func returnAccountNotFound() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        // Provide some account context but not for this reward account
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: "some_other_address", isRegistered: true)
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .proposalReturnAccountDoesNotExist })
    }

    @Test("proposalReturnAccountDoesNotExist when return account is not registered")
    func returnAccountNotRegistered() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let rewardAddress = rewardAccount.toHexString()
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: rewardAddress, isRegistered: false)
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .proposalReturnAccountDoesNotExist })
    }

    @Test("No return-account error when account is registered")
    func returnAccountRegistered() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let rewardAddress = rewardAccount.toHexString()
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: rewardAddress, isRegistered: true)
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(!issues.contains { $0.kind == .proposalReturnAccountDoesNotExist })
    }

    // MARK: - Previous gov action ID checks

    @Test("invalidPrevGovActionId when referenced previous action not in context")
    func prevGovActionNotFound() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let prevId = makeGovActionId(byte: 0xAB)
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .hardForkInitiationAction(
                HardForkInitiationAction(
                    id: prevId,
                    protocolVersion: ProtocolVersion(major: 10, minor: 0)
                )
            ),
            anchor: makeAnchor()
        )
        // Non-empty context but missing the referenced action
        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: "deadbeef\(String(repeating: "00", count: 28))",
                    govActionIndex: 0,
                    actionType: .hardForkInitiation,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .invalidPrevGovActionId })
    }

    @Test("invalidPrevGovActionId when previous action has wrong type")
    func prevGovActionWrongType() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let prevId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(prevId.transactionID)"

        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .parameterChangeAction(
                ParameterChangeAction(
                    id: prevId,
                    protocolParamUpdate: ProtocolParamUpdate(),
                    policyHash: nil
                )
            ),
            anchor: makeAnchor()
        )
        // Action exists but is hardForkInitiation, not parameterChange
        let ctx = ValidationContext(
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: prevId.govActionIndex,
                    actionType: .hardForkInitiation,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .invalidPrevGovActionId })
    }

    @Test("No prevGovActionId error when govActionContexts is empty (context-free skip)")
    func prevGovActionCheckSkippedWithEmptyContext() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let prevId = makeGovActionId(byte: 0xCD)
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .hardForkInitiationAction(
                HardForkInitiationAction(
                    id: prevId,
                    protocolVersion: ProtocolVersion(major: 10, minor: 0)
                )
            ),
            anchor: makeAnchor()
        )
        // Empty govActionContexts → skip the check
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ValidationContext()
        )
        #expect(!issues.contains { $0.kind == .invalidPrevGovActionId })
    }

    @Test("No error when previous action exists with matching type")
    func prevGovActionValid() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let rewardAddress = rewardAccount.toHexString()
        let prevId = makeGovActionId(byte: 0xAB)
        let txIdStr = "\(prevId.transactionID)"

        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .hardForkInitiationAction(
                HardForkInitiationAction(
                    id: prevId,
                    protocolVersion: ProtocolVersion(major: 10, minor: 0)
                )
            ),
            anchor: makeAnchor()
        )
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: rewardAddress, isRegistered: true)
            ],
            govActionContexts: [
                GovActionInputContext(
                    transactionId: txIdStr,
                    govActionIndex: prevId.govActionIndex,
                    actionType: .hardForkInitiation,
                    isActive: true
                )
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(!issues.contains { $0.kind == .invalidPrevGovActionId })
    }

    // MARK: - TreasuryWithdrawals checks

    @Test("zeroTreasuryWithdrawals when all withdrawal amounts are zero")
    func zeroTreasuryWithdrawals() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let withdrawalAccount = makeRewardAccount(network: .testnet, keyByte: 0x02)
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .treasuryWithdrawalsAction(
                TreasuryWithdrawalsAction(
                    withdrawals: [withdrawalAccount: 0],
                    policyHash: nil
                )
            ),
            anchor: makeAnchor()
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ValidationContext()
        )
        #expect(issues.contains { $0.kind == .zeroTreasuryWithdrawals })
    }

    @Test("treasuryWithdrawalsNetworkIdMismatch when withdrawal account has wrong network")
    func treasuryWithdrawalsNetworkMismatch() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        // mainnet withdrawal account with testnet context
        let withdrawalAccount = makeRewardAccount(network: .mainnet, keyByte: 0x02)
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .treasuryWithdrawalsAction(
                TreasuryWithdrawalsAction(
                    withdrawals: [withdrawalAccount: 1_000_000],
                    policyHash: nil
                )
            ),
            anchor: makeAnchor()
        )
        let ctx = ValidationContext(network: .testnet)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .treasuryWithdrawalsNetworkIdMismatch })
    }

    @Test("treasuryWithdrawalReturnAccountDoesNotExist when withdrawal account not in context")
    func treasuryWithdrawalAccountMissing() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let withdrawalAccount = makeRewardAccount(network: .testnet, keyByte: 0x02)
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .treasuryWithdrawalsAction(
                TreasuryWithdrawalsAction(
                    withdrawals: [withdrawalAccount: 1_000_000],
                    policyHash: nil
                )
            ),
            anchor: makeAnchor()
        )
        // Provide an account context but not for the withdrawal account
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: "unrelated_address", isRegistered: true)
            ]
        )
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .treasuryWithdrawalReturnAccountDoesNotExist })
    }

    // MARK: - UpdateCommittee checks

    @Test("conflictingCommitteeUpdate when credential in both add and remove")
    func conflictingCommitteeUpdate() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let credential = CommitteeColdCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0xCC, count: 28))
            )
        )
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .updateCommittee(
                UpdateCommittee(
                    id: nil,
                    coldCredentials: [credential],  // remove
                    credentialEpochs: [credential: 500],  // also add
                    interval: UnitInterval(numerator: 2, denominator: 3)
                )
            ),
            anchor: makeAnchor()
        )
        let ctx = ValidationContext(currentEpoch: 400)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .conflictingCommitteeUpdate })
    }

    @Test("expirationEpochTooSmall when epoch is not greater than current epoch")
    func expirationEpochTooSmall() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let credential = CommitteeColdCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0xDD, count: 28))
            )
        )
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .updateCommittee(
                UpdateCommittee(
                    id: nil,
                    coldCredentials: [],
                    credentialEpochs: [credential: 400],  // same as current epoch
                    interval: UnitInterval(numerator: 2, denominator: 3)
                )
            ),
            anchor: makeAnchor()
        )
        let ctx = ValidationContext(currentEpoch: 400)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(issues.contains { $0.kind == .expirationEpochTooSmall })
    }

    @Test("No expirationEpochTooSmall when epoch is strictly greater than current epoch")
    func expirationEpochValid() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let credential = CommitteeColdCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0xDD, count: 28))
            )
        )
        let proposal = ProposalProcedure(
            deposit: 500_000_000,
            rewardAccount: rewardAccount,
            govAction: .updateCommittee(
                UpdateCommittee(
                    id: nil,
                    coldCredentials: [],
                    credentialEpochs: [credential: 401],  // strictly greater than 400
                    interval: UnitInterval(numerator: 2, denominator: 3)
                )
            ),
            anchor: makeAnchor()
        )
        let ctx = ValidationContext(currentEpoch: 400)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ctx
        )
        #expect(!issues.contains { $0.kind == .expirationEpochTooSmall })
    }

    // MARK: - InfoAction

    @Test("InfoAction produces no content-rule errors")
    func infoActionNoErrors() throws {
        let rewardAccount = makeRewardAccount(network: .testnet)
        let proposal = makeInfoProposal(rewardAccount: rewardAccount)
        let issues = try runRule(
            proposalProcedures: NonEmptyOrderedSet([proposal]),
            context: ValidationContext()
        )
        let contentErrors = issues.filter {
            $0.kind == .conflictingCommitteeUpdate
            || $0.kind == .expirationEpochTooSmall
            || $0.kind == .zeroTreasuryWithdrawals
            || $0.kind == .invalidPrevGovActionId
        }
        #expect(contentErrors.isEmpty)
    }
}
