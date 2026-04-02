import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - RegistrationRule Tests

@Suite("RegistrationRule")
struct RegistrationRuleTests {

    // MARK: - Helpers

    private func makeStakeCred(_ byte: UInt8) -> StakeCredential {
        StakeCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: byte, count: 28))
            )
        )
    }

    private func makeDRepCred(_ byte: UInt8) -> DRepCredential {
        DRepCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: byte, count: 28))
            )
        )
    }

    private func makePoolKeyHash(_ byte: UInt8) -> PoolKeyHash {
        PoolKeyHash(payload: Data(repeating: byte, count: 28))
    }

    private func makeMinimalBody(certs: [Certificate]) -> TransactionBody {
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
            certificates: .list(certs)
        )
    }

    private func runRule(
        certs: [Certificate],
        context: ValidationContext
    ) throws -> [ValidationError] {
        let body = makeMinimalBody(certs: certs)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let pp = try loadProtocolParams()
        return try RegistrationRule().validate(transaction: tx, context: context, protocolParams: pp)
    }

    // MARK: - Stake already registered

    @Test("stakeAlreadyRegistered when registering an already-registered key")
    func stakeAlreadyRegistered() throws {
        let cred = makeStakeCred(0x10)
        let credStr = "\(cred)"
        let cert = Certificate.register(Register(stakeCredential: cred, coin: 2_000_000))
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: credStr, isRegistered: true)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .stakeAlreadyRegistered })
    }

    // MARK: - Stake not registered (deregistration)

    @Test("stakeNotRegistered when deregistering an unregistered key")
    func stakeNotRegistered() throws {
        let cred = makeStakeCred(0x11)
        let credStr = "\(cred)"
        let cert = Certificate.unregister(Unregister(stakeCredential: cred, coin: 2_000_000))
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: credStr, isRegistered: false)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .stakeNotRegistered })
    }

    // MARK: - Stake non-zero balance on deregistration

    @Test("stakeNonZeroAccountBalance when deregistering with remaining balance")
    func stakeNonZeroBalance() throws {
        let cred = makeStakeCred(0x12)
        let credStr = "\(cred)"
        let cert = Certificate.unregister(Unregister(stakeCredential: cred, coin: 2_000_000))
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(
                    rewardAddress: credStr,
                    isRegistered: true,
                    balance: 500_000
                )
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .stakeNonZeroAccountBalance })
    }

    // MARK: - Pool cost too low

    @Test("stakePoolCostTooLow when pool cost is below minPoolCost")
    func poolCostTooLow() throws {
        let pp = try loadProtocolParams()
        let poolKH = makePoolKeyHash(0x20)
        let vrfKH = VrfKeyHash(payload: Data(repeating: 0x30, count: 32))
        let rewardAccount = RewardAccountHash(payload: Data(repeating: 0x40, count: 29))
        let owner = VerificationKeyHash(payload: Data(repeating: 0x50, count: 28))

        let poolParams = PoolParams(
            poolOperator: poolKH,
            vrfKeyHash: vrfKH,
            pledge: 100_000_000,
            cost: pp.minPoolCost - 1, // Below minimum
            margin: UnitInterval(numerator: 1, denominator: 100),
            rewardAccount: rewardAccount,
            poolOwners: .list([owner]),
            relays: nil,
            poolMetadata: nil
        )
        let cert = Certificate.poolRegistration(PoolRegistration(poolParams: poolParams))
        let poolId = "\(poolKH)"

        let ctx = ValidationContext(
            poolContexts: [
                PoolInputContext(poolId: poolId, isRegistered: false)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .stakePoolCostTooLow })
    }

    // MARK: - Pool already registered (warning)

    @Test("poolAlreadyRegistered warning when re-registering")
    func poolAlreadyRegistered() throws {
        let pp = try loadProtocolParams()
        let poolKH = makePoolKeyHash(0x21)
        let vrfKH = VrfKeyHash(payload: Data(repeating: 0x31, count: 32))
        let rewardAccount = RewardAccountHash(payload: Data(repeating: 0x41, count: 29))
        let owner = VerificationKeyHash(payload: Data(repeating: 0x51, count: 28))

        let poolParams = PoolParams(
            poolOperator: poolKH,
            vrfKeyHash: vrfKH,
            pledge: 100_000_000,
            cost: pp.minPoolCost,
            margin: UnitInterval(numerator: 1, denominator: 100),
            rewardAccount: rewardAccount,
            poolOwners: .list([owner]),
            relays: nil,
            poolMetadata: nil
        )
        let cert = Certificate.poolRegistration(PoolRegistration(poolParams: poolParams))
        let poolId = "\(poolKH)"

        let ctx = ValidationContext(
            poolContexts: [
                PoolInputContext(poolId: poolId, isRegistered: true)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        let warning = issues.first { $0.kind == .poolAlreadyRegistered }
        #expect(warning != nil)
        #expect(warning?.isWarning == true)
    }

    // MARK: - Pool retirement wrong epoch

    @Test("wrongRetirementEpoch when retirement epoch is out of bounds")
    func wrongRetirementEpoch() throws {
        let _ = try loadProtocolParams()
        let poolKH = makePoolKeyHash(0x22)
        let poolId = "\(poolKH)"

        // Retire at epoch 0 (too early — current epoch is 100)
        let cert = Certificate.poolRetirement(
            PoolRetirement(poolKeyHash: poolKH, epoch: 0)
        )
        let ctx = ValidationContext(
            poolContexts: [
                PoolInputContext(poolId: poolId, isRegistered: true)
            ],
            currentEpoch: 100
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .wrongRetirementEpoch })
    }

    // MARK: - Pool not registered (retirement)

    @Test("stakePoolNotRegistered when retiring an unregistered pool")
    func poolNotRegisteredRetirement() throws {
        let poolKH = makePoolKeyHash(0x23)
        let poolId = "\(poolKH)"

        let cert = Certificate.poolRetirement(
            PoolRetirement(poolKeyHash: poolKH, epoch: 200)
        )
        let ctx = ValidationContext(
            poolContexts: [
                PoolInputContext(poolId: poolId, isRegistered: false)
            ],
            currentEpoch: 100
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .stakePoolNotRegistered })
    }

    // MARK: - DRep already registered (warning)

    @Test("drepAlreadyRegistered warning when re-registering")
    func drepAlreadyRegistered() throws {
        let cred = makeDRepCred(0x30)
        let drepId = "\(cred)"
        let cert = Certificate.registerDRep(RegisterDRep(drepCredential: cred, coin: 500_000_000))
        let ctx = ValidationContext(
            drepContexts: [
                DRepInputContext(drepId: drepId, isRegistered: true)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        let warning = issues.first { $0.kind == .drepAlreadyRegistered }
        #expect(warning != nil)
        #expect(warning?.isWarning == true)
    }

    // MARK: - DRep not registered (deregistration warning)

    @Test("drepNotRegistered warning when deregistering an unregistered DRep")
    func drepNotRegistered() throws {
        let cred = makeDRepCred(0x31)
        let drepId = "\(cred)"
        let cert = Certificate.unRegisterDRep(UnregisterDRep(drepCredential: cred, coin: 500_000_000))
        let ctx = ValidationContext(
            drepContexts: [
                DRepInputContext(drepId: drepId, isRegistered: false)
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        let warning = issues.first { $0.kind == .drepNotRegistered }
        #expect(warning != nil)
        #expect(warning?.isWarning == true)
    }

    // MARK: - Duplicate registration in tx (warning)

    @Test("duplicateRegistrationInTx when same stake key registered twice")
    func duplicateStakeRegistration() throws {
        let cred = makeStakeCred(0x40)
        let credStr = "\(cred)"
        let cert1 = Certificate.register(Register(stakeCredential: cred, coin: 2_000_000))
        let cert2 = Certificate.register(Register(stakeCredential: cred, coin: 2_000_000))
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: credStr, isRegistered: false)
            ]
        )
        let issues = try runRule(certs: [cert1, cert2], context: ctx)
        let warning = issues.first { $0.kind == .duplicateRegistrationInTx }
        #expect(warning != nil)
        #expect(warning?.isWarning == true)
    }

    // MARK: - Committee unknown

    @Test("committeeIsUnknown when authorizing unknown cold credential")
    func committeeUnknown() throws {
        let coldCred = CommitteeColdCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x50, count: 28))
            )
        )
        let hotCred = CommitteeHotCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x51, count: 28))
            )
        )
        let cert = Certificate.authCommitteeHot(
            AuthCommitteeHot(
                committeeColdCredential: coldCred,
                committeeHotCredential: hotCred
            )
        )
        // Empty committee lists = unknown
        _ = ValidationContext(
            currentCommitteeMembers: [],
            potentialCommitteeMembers: []
        )
        // Need at least one chain-state array non-empty for the rule to run
        let ctxWithState = ValidationContext(
            accountContexts: [AccountInputContext(rewardAddress: "dummy", isRegistered: false)],
            currentCommitteeMembers: [],
            potentialCommitteeMembers: []
        )
        let issues = try runRule(certs: [cert], context: ctxWithState)
        #expect(issues.contains { $0.kind == .committeeIsUnknown })
    }

    // MARK: - Committee previously resigned

    @Test("committeeHasPreviouslyResigned when authorizing resigned member")
    func committeeResigned() throws {
        let coldCred = CommitteeColdCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x52, count: 28))
            )
        )
        let hotCred = CommitteeHotCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x53, count: 28))
            )
        )
        let coldId = "\(coldCred)"
        let cert = Certificate.authCommitteeHot(
            AuthCommitteeHot(
                committeeColdCredential: coldCred,
                committeeHotCredential: hotCred
            )
        )
        let ctx = ValidationContext(
            accountContexts: [AccountInputContext(rewardAddress: "dummy", isRegistered: false)],
            currentCommitteeMembers: [
                CommitteeInputContext(
                    committeeColdCredential: coldId,
                    isResigned: true
                )
            ]
        )
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.contains { $0.kind == .committeeHasPreviouslyResigned })
    }

    // MARK: - No chain state → skip

    @Test("RegistrationRule skips all checks when no chain state is present")
    func skipsWithoutChainState() throws {
        let cred = makeStakeCred(0x60)
        let cert = Certificate.register(Register(stakeCredential: cred, coin: 2_000_000))
        let ctx = ValidationContext()
        let issues = try runRule(certs: [cert], context: ctx)
        #expect(issues.isEmpty, "Expected no issues when chain state is absent")
    }
}
