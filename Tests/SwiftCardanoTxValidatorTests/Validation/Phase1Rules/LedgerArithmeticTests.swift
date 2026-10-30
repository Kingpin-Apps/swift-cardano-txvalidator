import BigInt
import Foundation
import SwiftCardanoCore
import Testing
@testable import SwiftCardanoTxValidator

/// The fee, collateral, balance and governance checks as the ledger computes them.
@Suite("Ledger arithmetic")
struct LedgerArithmeticTests {
    private func address(_ byte: UInt8) throws -> Address {
        try Address(
            paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: 28))),
            network: .testnet)
    }

    private func input(_ byte: UInt8) -> TransactionInput {
        TransactionInput(transactionId: TransactionId(payload: Data(repeating: byte, count: 32)), index: 0)
    }

    // MARK: - Fees

    @Test("The script fee is the ledger's txscriptfee: the exact sum rounded up once")
    func scriptFeeRoundsOnce() throws {
        let prices = try loadProtocolParams().executionUnitPrices
        // 0.0577 + 0.0000721 = 0.0577721: one lovelace, not one for each.
        #expect(LedgerFees.scriptFee(prices: prices, memory: 1, steps: 1) == 1)
        #expect(LedgerFees.scriptFee(prices: prices, memory: 1_000_000, steps: 1_000_000_000) == 129_800)
    }

    @Test("A per-byte price is charged in Conway's tiers and the sum rounded down, as tierRefScriptFee does")
    func referenceScriptTiers() throws {
        let params = try loadProtocolParams()
        #expect(params.minFeeReferenceScripts == nil)
        // 15 a byte, then 18 past 25 KiB: 25,600 × 15 + 1,000 × 18.
        #expect(LedgerFees.referenceScriptFee(bytes: 25_600 + 1_000, parameters: params) == 402_000)
        // 384,000 + 460,800 + 552,960 + 5,120 × 25.92 = 1,530,470.4.
        #expect(LedgerFees.referenceScriptFee(bytes: 80 * 1024, parameters: params) == 1_530_470)
        #expect(LedgerFees.referenceScriptFee(bytes: 0, parameters: params) == 0)
    }

    // MARK: - Collateral

    @Test("Collateral must satisfy collateral × 100 ≥ fee × collateralPercentage exactly", arguments: [
        (UInt64(255_001), true), (UInt64(255_002), false),
    ])
    func collateralRoundsUp(_ collateral: UInt64, insufficient: Bool) throws {
        let params = try loadProtocolParams()
        #expect(params.collateralPercentage == 150)
        let collateralInput = input(0xC1)
        // 170,001 × 1.5 = 255,001.5, so 255,001 falls half a lovelace short.
        let body = TransactionBody(
            inputs: .list([input(0xA1)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 170_001,
            collateral: .list([collateralInput]))
        let witnesses = TransactionWitnessSet(redeemers: .map(RedeemerMap([
            RedeemerKey(tag: .spend, index: 0): RedeemerValue(
                data: .bigInt(.int(1)), exUnits: ExecutionUnits(mem: 1_000, steps: 2_000)),
        ])))
        let context = ValidationContext(resolvedInputs: [
            UTxO(input: collateralInput, output: TransactionOutput(address: try address(2), amount: Value(coin: collateral))),
        ])
        let issues = try CollateralRule().validate(
            transaction: Transaction(transactionBody: body, transactionWitnessSet: witnesses),
            context: context, protocolParams: params)
        #expect(issues.contains { $0.kind == .insufficientCollateral } == insufficient)
    }

    @Test("An unresolved collateral input leaves the net collateral unchecked, not short")
    func unresolvedCollateral() throws {
        let body = TransactionBody(
            inputs: .list([input(0xA1)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 170_001,
            collateral: .list([input(0xC1), input(0xC2)]))
        let witnesses = TransactionWitnessSet(redeemers: .map(RedeemerMap([
            RedeemerKey(tag: .spend, index: 0): RedeemerValue(
                data: .bigInt(.int(1)), exUnits: ExecutionUnits(mem: 1_000, steps: 2_000)),
        ])))
        let context = ValidationContext(resolvedInputs: [
            UTxO(input: input(0xC1), output: TransactionOutput(address: try address(2), amount: Value(coin: 1))),
        ])
        let issues = try CollateralRule().validate(
            transaction: Transaction(transactionBody: body, transactionWitnessSet: witnesses),
            context: context, protocolParams: try loadProtocolParams())
        #expect(!issues.contains { $0.kind == .insufficientCollateral })
    }

    // MARK: - Balance

    private func balanceIssues(_ body: TransactionBody, resolved: [UTxO]) throws -> [ValidationError] {
        try BalanceRule().validate(
            transaction: Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet()),
            context: ValidationContext(resolvedInputs: resolved), protocolParams: try loadProtocolParams())
    }

    @Test("A proposal is balanced with its own deposit; a wrong one is reported as a mismatch")
    func proposalDepositBalances() throws {
        let proposal = try ProposalProcedure(
            deposit: 1_000,
            rewardAccount: Data([0xE0] + [UInt8](repeating: 1, count: 28)),
            govAction: .infoAction(InfoAction()),
            anchor: Anchor(
                anchorUrl: try Url("https://test.example.com"),
                anchorDataHash: AnchorDataHash(payload: Data(repeating: 0xAA, count: 32))))
        let body = TransactionBody(
            inputs: .list([input(0xA1)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            proposalProcedures: NonEmptyOrderedSet([proposal]))
        let issues = try balanceIssues(body, resolved: [
            UTxO(input: input(0xA1), output: TransactionOutput(address: try address(1), amount: Value(coin: 2_201_000))),
        ])
        #expect(!issues.contains { $0.kind == .valueNotConserved })
        #expect(issues.contains { $0.kind == .depositMismatch })
    }

    @Test("An unresolved input leaves the balance unchecked rather than unbalanced")
    func unresolvedInput() throws {
        let body = TransactionBody(
            inputs: .list([input(0xA1), input(0xA2)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 200_000)
        let issues = try balanceIssues(body, resolved: [
            UTxO(input: input(0xA1), output: TransactionOutput(address: try address(1), amount: Value(coin: 1_000_000))),
        ])
        #expect(!issues.contains { $0.kind == .valueNotConserved })
    }

    @Test("A pool registered twice in one transaction takes its deposit once")
    func poolRegisteredTwice() throws {
        let params = PoolParams(
            poolOperator: PoolKeyHash(payload: Data(repeating: 0x20, count: 28)),
            vrfKeyHash: VrfKeyHash(payload: Data(repeating: 0x30, count: 32)),
            pledge: 100_000_000,
            cost: 340_000_000,
            margin: UnitInterval(numerator: 1, denominator: 100),
            rewardAccount: RewardAccountHash(payload: Data([0xE0] + [UInt8](repeating: 0x40, count: 28))),
            poolOwners: .list([VerificationKeyHash(payload: Data(repeating: 0x50, count: 28))]),
            relays: nil,
            poolMetadata: nil)
        let registration = Certificate.poolRegistration(try PoolRegistration(poolParams: params))
        let body = TransactionBody(
            inputs: .list([input(0xA1)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([registration, registration]))
        let issues = try balanceIssues(body, resolved: [
            UTxO(input: input(0xA1), output: TransactionOutput(
                address: try address(1), amount: Value(coin: 2_200_000 + 500_000_000))),
        ])
        #expect(!issues.contains { $0.kind == .valueNotConserved })
    }

    // MARK: - Governance

    @Test("A previous action may be the last enacted one, whose type the chain may no longer know")
    func previousActionLastEnacted() throws {
        let previous = GovActionID(
            transactionID: TransactionId(payload: Data(repeating: 0xAB, count: 32)), govActionIndex: 0)
        let proposal = try ProposalProcedure(
            deposit: 100_000_000_000,
            rewardAccount: Data([0xE0] + [UInt8](repeating: 1, count: 28)),
            govAction: .hardForkInitiationAction(
                HardForkInitiationAction(id: previous, protocolVersion: ProtocolVersion(major: 10, minor: 0))),
            anchor: Anchor(
                anchorUrl: try Url("https://test.example.com"),
                anchorDataHash: AnchorDataHash(payload: Data(repeating: 0xAA, count: 32))))
        let body = TransactionBody(
            inputs: .list([input(0xA1)]),
            outputs: [TransactionOutput(address: try address(1), amount: Value(coin: 2_000_000))],
            fee: 200_000,
            proposalProcedures: NonEmptyOrderedSet([proposal]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let enacted = GovActionInputContext(
            transactionId: "\(previous.transactionID)", govActionIndex: 0, actionType: nil, isActive: true)
        let issues = try GovernanceProposalRule().validate(
            transaction: tx, context: ValidationContext(lastEnactedGovAction: [enacted]),
            protocolParams: try loadProtocolParams())
        #expect(!issues.contains { $0.kind == .invalidPrevGovActionId })

        let wrongType = GovActionInputContext(
            transactionId: "\(previous.transactionID)", govActionIndex: 0, actionType: .parameterChange, isActive: true)
        let mismatched = try GovernanceProposalRule().validate(
            transaction: tx, context: ValidationContext(lastEnactedGovAction: [wrongType]),
            protocolParams: try loadProtocolParams())
        #expect(mismatched.contains { $0.kind == .invalidPrevGovActionId })
    }

    // MARK: - Views

    @Test("An output's view holds a quantity past Int64.max, as the ledger's Word64 does")
    func outputViewQuantities() throws {
        let policy = ScriptHash(payload: Data(repeating: 0x31, count: 28))
        let name = try AssetName(payload: Data("T".utf8))
        let output = TransactionOutput(
            address: try address(1),
            amount: Value(coin: BigInt(UInt64.max), multiAsset: MultiAsset([policy: Asset([name: BigInt(UInt64.max)])])))
        let view = try OutputView.from(output)
        #expect(view.lovelace == UInt64.max)
        #expect(view.multiAsset?.values.first?.values.first == UInt64.max)
    }
}
