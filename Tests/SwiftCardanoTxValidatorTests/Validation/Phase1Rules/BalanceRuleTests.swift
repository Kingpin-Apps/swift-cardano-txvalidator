import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoTxValidator

// MARK: - BalanceRule Tests

@Suite("BalanceRule")
struct BalanceRuleTests {

    // MARK: - Deposit mismatch — Register cert

    @Test("BalanceRule emits depositMismatch when Register cert coin != stakeAddressDeposit")
    func registerDepositMismatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let stakeCred = StakeCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x10, count: 28))
            )
        )
        // Wrong deposit — should be pp.stakeAddressDeposit
        let wrongDeposit: Coin = Coin(pp.stakeAddressDeposit) + 1_000_000
        let cert = Certificate.register(Register(stakeCredential: stakeCred, coin: wrongDeposit))

        let txId = TransactionId(payload: Data(repeating: 0xA1, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([cert])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        // No resolved inputs — deposit check should still fire.
        let ctx = ValidationContext()

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let depositIssues = issues.filter { $0.kind == .depositMismatch }
        #expect(!depositIssues.isEmpty, "Expected depositMismatch for wrong Register deposit")
        #expect(depositIssues.first?.fieldPath.contains("certificates") == true)
    }

    @Test("BalanceRule passes when Register cert coin matches stakeAddressDeposit")
    func registerDepositCorrect() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let stakeCred = StakeCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x10, count: 28))
            )
        )
        let cert = Certificate.register(
            Register(stakeCredential: stakeCred, coin: Coin(pp.stakeAddressDeposit))
        )

        let txId = TransactionId(payload: Data(repeating: 0xA2, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([cert])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext()

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        let depositIssues = issues.filter { $0.kind == .depositMismatch }
        #expect(depositIssues.isEmpty, "Expected no depositMismatch for correct deposit")
    }

    // MARK: - Deposit mismatch — Unregister cert

    @Test("BalanceRule emits depositMismatch when Unregister cert refund != stakeAddressDeposit")
    func unregisterRefundMismatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let stakeCred = StakeCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x11, count: 28))
            )
        )
        let wrongRefund: Coin = 0
        let cert = Certificate.unregister(Unregister(stakeCredential: stakeCred, coin: wrongRefund))

        let txId = TransactionId(payload: Data(repeating: 0xA3, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([cert])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let depositIssues = issues.filter { $0.kind == .depositMismatch }
        #expect(!depositIssues.isEmpty, "Expected depositMismatch for wrong Unregister refund")
    }

    // MARK: - Deposit mismatch — RegisterDRep cert

    @Test("BalanceRule emits depositMismatch when RegisterDRep cert coin != dRepDeposit")
    func registerDRepDepositMismatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let drepCred = DRepCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x12, count: 28))
            )
        )
        let wrongDeposit: Coin = Coin(pp.dRepDeposit) + 500_000
        let cert = Certificate.registerDRep(
            RegisterDRep(drepCredential: drepCred, coin: wrongDeposit)
        )

        let txId = TransactionId(payload: Data(repeating: 0xA4, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([cert])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let depositIssues = issues.filter { $0.kind == .depositMismatch }
        #expect(!depositIssues.isEmpty, "Expected depositMismatch for wrong RegisterDRep deposit")
    }

    // MARK: - Deposit mismatch — UnRegisterDRep cert

    @Test("BalanceRule emits depositMismatch when UnRegisterDRep cert refund != dRepDeposit")
    func unRegisterDRepRefundMismatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let drepCred = DRepCredential(
            credential: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x13, count: 28))
            )
        )
        let wrongRefund: Coin = 0
        let cert = Certificate.unRegisterDRep(
            UnregisterDRep(drepCredential: drepCred, coin: wrongRefund)
        )

        let txId = TransactionId(payload: Data(repeating: 0xA5, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            certificates: .list([cert])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let issues = try rule.validate(transaction: tx, context: ValidationContext(), protocolParams: pp)
        let depositIssues = issues.filter { $0.kind == .depositMismatch }
        #expect(!depositIssues.isEmpty, "Expected depositMismatch for wrong UnRegisterDRep refund")
    }

    // MARK: - Treasury value mismatch

    @Test("BalanceRule emits treasuryValueMismatch when declared != actual")
    func treasuryValueMismatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let txId = TransactionId(payload: Data(repeating: 0xB1, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            currentTreasuryAmount: 100_000_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(treasuryValue: 200_000_000)

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .treasuryValueMismatch })
    }

    @Test("BalanceRule passes when treasury values match")
    func treasuryValueMatch() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let txId = TransactionId(payload: Data(repeating: 0xB2, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            currentTreasuryAmount: 100_000_000
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(treasuryValue: 100_000_000)

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(!issues.contains { $0.kind == .treasuryValueMismatch })
    }

    // MARK: - Withdrawal: reward account not existing

    @Test("BalanceRule emits rewardAccountNotExisting when account not found")
    func withdrawalAccountNotExisting() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let rewardAccountData = Data(repeating: 0xC0, count: 29)
        _ = rewardAccountData.toHexString()

        let txId = TransactionId(payload: Data(repeating: 0xB3, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let withdrawals = Withdrawals([rewardAccountData: 1_000_000])
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            withdrawals: withdrawals
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        // Account context exists but with a DIFFERENT address
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(rewardAddress: "other_address", isRegistered: true)
            ]
        )

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .rewardAccountNotExisting })
    }

    // MARK: - Withdrawal: wrong amount

    @Test("BalanceRule emits wrongWithdrawalAmount when amount != balance")
    func withdrawalWrongAmount() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let rewardAccountData = Data(repeating: 0xC1, count: 29)
        let rewardAddress = rewardAccountData.toHexString()

        let txId = TransactionId(payload: Data(repeating: 0xB4, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let withdrawals = Withdrawals([rewardAccountData: 1_000_000])
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            withdrawals: withdrawals
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(
                    rewardAddress: rewardAddress,
                    isRegistered: true,
                    delegatedToDRep: "drep1abc",
                    balance: 500_000  // Different from withdrawal amount
                )
            ]
        )

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .wrongWithdrawalAmount })
    }

    // MARK: - Withdrawal: not delegated to DRep

    @Test("BalanceRule emits withdrawalNotDelegatedToDRep when no DRep delegation")
    func withdrawalNotDelegatedToDRep() throws {
        let pp = try loadProtocolParams()
        let rule = BalanceRule()

        let rewardAccountData = Data(repeating: 0xC2, count: 29)
        let rewardAddress = rewardAccountData.toHexString()

        let txId = TransactionId(payload: Data(repeating: 0xB5, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let withdrawals = Withdrawals([rewardAccountData: 1_000_000])
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [TransactionOutput(address: addr, amount: Value(coin: 2_000_000))],
            fee: 200_000,
            withdrawals: withdrawals
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = ValidationContext(
            accountContexts: [
                AccountInputContext(
                    rewardAddress: rewardAddress,
                    isRegistered: true,
                    delegatedToDRep: nil,  // Not delegated
                    balance: 1_000_000
                )
            ]
        )

        let issues = try rule.validate(transaction: tx, context: ctx, protocolParams: pp)
        #expect(issues.contains { $0.kind == .withdrawalNotDelegatedToDRep })
    }

    // MARK: - Smoke

    @Test("BalanceRule name is correct")
    func ruleName() {
        #expect(BalanceRule().name == "balance")
    }
}
