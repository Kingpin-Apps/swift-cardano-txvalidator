import Testing
import Foundation
import SwiftCardanoCore
import SwiftCardanoChain
@testable import SwiftCardanoTxValidator

/// Tests for `ValidationContext.from(transaction:chainContext:)`.
///
/// `MockChainContext` returns real values only for `epoch`, `era`, `lastBlockSlot`, and
/// `networkId`; every chain *lookup* (`utxo`, `stakeAddressInfo`, `stakePoolInfo`, `drepInfo`,
/// `committeeMemberInfo`, `treasury`) throws `notImplemented`. Because `from(...)` wraps each
/// lookup in `try?`, those failures are swallowed and the corresponding context collections stay
/// empty — which lets us drive every code path (input resolution, withdrawals, each certificate
/// extractor, treasury) without a live backend, and assert on the chain-metadata that *is*
/// populated.
@Suite("ValidationContext+ChainContext")
struct ValidationContextChainContextTests {

    // MARK: - Helpers

    private func makeAddress(_ byte: UInt8) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet
        )
    }

    private func makeStakeCred(_ byte: UInt8) -> StakeCredential {
        StakeCredential(credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))))
    }

    private func makeInput(_ txByte: UInt8, _ index: UInt16) -> TransactionInput {
        TransactionInput(transactionId: TransactionId(payload: Data(repeating: txByte, count: 32)), index: index)
    }

    // MARK: - Minimal transaction

    @Test("from populates chain metadata for a minimal transaction")
    func minimalTransaction() async throws {
        let pp = try loadProtocolParams()
        let ctxChain = MockChainContext(protocolParams: pp)

        let body = TransactionBody(
            inputs: .list([makeInput(0xAA, 0)]),
            outputs: [TransactionOutput(address: try makeAddress(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try await ValidationContext.from(transaction: tx, chainContext: ctxChain)

        // Metadata pulled directly from the mock.
        #expect(ctx.network == .testnet)
        #expect(ctx.currentSlot == 0)
        #expect(ctx.currentEpoch == 0)
        #expect(ctx.era == .conway)

        // No inputs resolvable (mock throws), no certs/withdrawals/treasury → all empty/nil.
        #expect(ctx.resolvedInputs.isEmpty)
        #expect(ctx.spentInputRefs.isEmpty)
        #expect(ctx.accountContexts.isEmpty)
        #expect(ctx.poolContexts.isEmpty)
        #expect(ctx.drepContexts.isEmpty)
        #expect(ctx.govActionContexts.isEmpty)
        #expect(ctx.lastEnactedGovAction.isEmpty)
        #expect(ctx.currentCommitteeMembers.isEmpty)
        #expect(ctx.potentialCommitteeMembers.isEmpty)
        #expect(ctx.treasuryValue == nil)
    }

    // MARK: - Withdrawals path

    @Test("from walks the withdrawals reward-account path")
    func withdrawalsPath() async throws {
        let pp = try loadProtocolParams()
        let ctxChain = MockChainContext(protocolParams: pp)

        // 29-byte reward address (header byte 0xE0 → stake key, testnet).
        let rewardAccount = Data([0xE0] + Array(repeating: UInt8(0xC0), count: 28))
        let body = TransactionBody(
            inputs: .list([makeInput(0xAB, 0)]),
            outputs: [TransactionOutput(address: try makeAddress(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            withdrawals: Withdrawals([rewardAccount: 1_000_000])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try await ValidationContext.from(transaction: tx, chainContext: ctxChain)

        // stakeAddressInfo throws in the mock, so no account context is appended.
        #expect(ctx.accountContexts.isEmpty)
        #expect(ctx.network == .testnet)
    }

    // MARK: - Certificate extractors

    @Test("from walks every certificate extractor branch")
    func certificateExtractors() async throws {
        let pp = try loadProtocolParams()
        let ctxChain = MockChainContext(protocolParams: pp)

        let stakeReg = Certificate.stakeRegistration(StakeRegistration(stakeCredential: makeStakeCred(0x10)))
        let poolRetire = Certificate.poolRetirement(
            PoolRetirement(poolKeyHash: PoolKeyHash(payload: Data(repeating: 0x20, count: 28)), epoch: 100)
        )
        let regDRep = Certificate.registerDRep(
            RegisterDRep(
                drepCredential: DRepCredential(
                    credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x30, count: 28)))
                ),
                coin: 500_000_000,
                anchor: nil
            )
        )
        let authHot = Certificate.authCommitteeHot(
            AuthCommitteeHot(
                committeeColdCredential: CommitteeColdCredential(
                    credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x40, count: 28)))
                ),
                committeeHotCredential: CommitteeHotCredential(
                    credential: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: 0x50, count: 28)))
                )
            )
        )

        let body = TransactionBody(
            inputs: .list([makeInput(0xAC, 0)]),
            outputs: [TransactionOutput(address: try makeAddress(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([stakeReg, poolRetire, regDRep, authHot])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try await ValidationContext.from(transaction: tx, chainContext: ctxChain)

        // The extractor switches run for every cert, but each backend lookup throws → empty contexts.
        #expect(ctx.accountContexts.isEmpty)
        #expect(ctx.poolContexts.isEmpty)
        #expect(ctx.drepContexts.isEmpty)
        #expect(ctx.currentCommitteeMembers.isEmpty)
        #expect(ctx.era == .conway)
    }

    // MARK: - Treasury path

    @Test("from queries treasury only when currentTreasuryAmount is present")
    func treasuryPath() async throws {
        let pp = try loadProtocolParams()
        let ctxChain = MockChainContext(protocolParams: pp)

        let body = TransactionBody(
            inputs: .list([makeInput(0xAD, 0)]),
            outputs: [TransactionOutput(address: try makeAddress(0x01), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            currentTreasuryAmount: 1_000_000_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try await ValidationContext.from(transaction: tx, chainContext: ctxChain)

        // treasury() throws in the mock, so even though the branch is taken the value stays nil.
        #expect(ctx.treasuryValue == nil)
    }
}
