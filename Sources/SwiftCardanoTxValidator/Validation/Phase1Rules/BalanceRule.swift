import Foundation
import SwiftCardanoCore

/// Verifies that the transaction conserves value:
/// ```
/// Σ(inputs) + Σ(withdrawals) + Σ(refunds) == Σ(outputs) + fee + Σ(deposits) + donation
/// ```
///
/// Requires `context.resolvedInputs` to be populated; skips the check otherwise.
public struct BalanceRule: ValidationRule {
    public let name = "balance"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        var issues: [ValidationError] = []

        // -----------------------------------------------------------------------
        // MARK: Per-cert deposit/refund mismatch checks
        // -----------------------------------------------------------------------
        if let certs = body.certificates {
            let expectedStakeDeposit = protocolParams.stakeAddressDeposit
            let expectedDRepDeposit  = protocolParams.dRepDeposit

            for (i, cert) in certs.asList.enumerated() {
                switch cert {
                case .register(let r):
                    if Int(r.coin) != expectedStakeDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "Register cert deposit \(r.coin) lovelace does not match "
                                + "stakeAddressDeposit \(expectedStakeDeposit) lovelace.",
                            hint: "Set the deposit to \(expectedStakeDeposit) lovelace."
                        ))
                    }
                case .unregister(let u):
                    if Int(u.coin) != expectedStakeDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "Unregister cert refund \(u.coin) lovelace does not match "
                                + "stakeAddressDeposit \(expectedStakeDeposit) lovelace.",
                            hint: "Set the refund to \(expectedStakeDeposit) lovelace."
                        ))
                    }
                case .registerDRep(let r):
                    if Int(r.coin) != expectedDRepDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "RegisterDRep cert deposit \(r.coin) lovelace does not match "
                                + "dRepDeposit \(expectedDRepDeposit) lovelace.",
                            hint: "Set the deposit to \(expectedDRepDeposit) lovelace."
                        ))
                    }
                case .unRegisterDRep(let u):
                    if Int(u.coin) != expectedDRepDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "UnRegisterDRep cert refund \(u.coin) lovelace does not match "
                                + "dRepDeposit \(expectedDRepDeposit) lovelace.",
                            hint: "Set the refund to \(expectedDRepDeposit) lovelace."
                        ))
                    }
                case .stakeRegisterDelegate(let d):
                    if Int(d.coin) != expectedStakeDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "StakeRegisterDelegate cert deposit \(d.coin) lovelace does not match "
                                + "stakeAddressDeposit \(expectedStakeDeposit) lovelace.",
                            hint: "Set the deposit to \(expectedStakeDeposit) lovelace."
                        ))
                    }
                case .voteRegisterDelegate(let d):
                    if Int(d.coin) != expectedStakeDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "VoteRegisterDelegate cert deposit \(d.coin) lovelace does not match "
                                + "stakeAddressDeposit \(expectedStakeDeposit) lovelace.",
                            hint: "Set the deposit to \(expectedStakeDeposit) lovelace."
                        ))
                    }
                case .stakeVoteRegisterDelegate(let d):
                    if Int(d.coin) != expectedStakeDeposit {
                        issues.append(ValidationError(
                            kind: .depositMismatch,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "StakeVoteRegisterDelegate cert deposit \(d.coin) lovelace does not match "
                                + "stakeAddressDeposit \(expectedStakeDeposit) lovelace.",
                            hint: "Set the deposit to \(expectedStakeDeposit) lovelace."
                        ))
                    }
                case .poolRegistration(let p):
                    // Pool registration deposit check: first-time registration requires
                    // stakePoolDeposit; re-registration (update) requires no deposit.
                    if !context.poolContexts.isEmpty {
                        let poolId = "\(p.poolParams.poolOperator)"
                        let isAlreadyRegistered = context.findPoolContext(poolId: poolId)?.isRegistered ?? false
                        if !isAlreadyRegistered {
                            // First-time registration — deposit should match stakePoolDeposit
                            // (poolRegistration cert has no explicit deposit field; the protocol
                            // expects exactly stakePoolDeposit, so we just emit a per-cert note
                            // that the deposit will be charged)
                        } else {
                            // Re-registration (update) — no deposit required, but if the balance
                            // equation counts a deposit here it would be wrong. Handled in the
                            // aggregate section below.
                        }
                    }
                default:
                    break
                }
            }
        }

        // Per-proposal deposit check
        if let proposals = body.proposalProcedures {
            let expectedGovDeposit = protocolParams.govActionDeposit
            for (i, proposal) in proposals.elementsOrdered.enumerated() {
                if Int(proposal.deposit) != expectedGovDeposit {
                    issues.append(ValidationError(
                        kind: .depositMismatch,
                        fieldPath: "transaction_body.proposal_procedures[\(i)]",
                        message: "Proposal deposit \(proposal.deposit) lovelace does not match "
                            + "govActionDeposit \(expectedGovDeposit) lovelace.",
                        hint: "Set the proposal deposit to \(expectedGovDeposit) lovelace."
                    ))
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: Treasury value mismatch check
        // -----------------------------------------------------------------------
        if let declaredTreasury = body.currentTreasuryAmount,
           let contextTreasury = context.treasuryValue {
            if declaredTreasury != Coin(contextTreasury) {
                issues.append(ValidationError(
                    kind: .treasuryValueMismatch,
                    fieldPath: "transaction_body.current_treasury_amount",
                    message: "Declared treasury value \(declaredTreasury) lovelace does not match "
                        + "actual treasury value \(contextTreasury) lovelace.",
                    hint: "Set currentTreasuryAmount to \(contextTreasury) lovelace."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: Withdrawal validation (requires accountContexts)
        // -----------------------------------------------------------------------
        if let withdrawals = body.withdrawals, !context.accountContexts.isEmpty {
            for (i, (rewardAccount, amount)) in withdrawals.data.enumerated() {
                let rewardAddress = rewardAccount.toHexString()
                if let accountCtx = context.findAccountContext(rewardAddress: rewardAddress) {
                    if accountCtx.isRegistered {
                        // Check withdrawal amount matches balance
                        if let balance = accountCtx.balance, amount != balance {
                            issues.append(ValidationError(
                                kind: .wrongWithdrawalAmount,
                                fieldPath: "transaction_body.withdrawals[\(i)]",
                                message: "Withdrawal amount \(amount) lovelace does not match "
                                    + "reward balance \(balance) lovelace for \(rewardAddress).",
                                hint: "Set the withdrawal amount to \(balance) lovelace."
                            ))
                        }
                        // Check DRep delegation
                        if accountCtx.delegatedToDRep == nil {
                            issues.append(ValidationError(
                                kind: .withdrawalNotDelegatedToDRep,
                                fieldPath: "transaction_body.withdrawals[\(i)]",
                                message: "Withdrawal from \(rewardAddress) not allowed: "
                                    + "stake credential is not delegated to a DRep."
                            ))
                        }
                    } else {
                        issues.append(ValidationError(
                            kind: .rewardAccountNotExisting,
                            fieldPath: "transaction_body.withdrawals[\(i)]",
                            message: "Reward account \(rewardAddress) is not registered."
                        ))
                    }
                } else {
                    issues.append(ValidationError(
                        kind: .rewardAccountNotExisting,
                        fieldPath: "transaction_body.withdrawals[\(i)]",
                        message: "Reward account \(rewardAddress) does not exist."
                    ))
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: Stake deregistration refund check (requires accountContexts)
        // -----------------------------------------------------------------------
        if let certs = body.certificates, !context.accountContexts.isEmpty {
            for (i, cert) in certs.asList.enumerated() {
                switch cert {
                case .unregister(let u):
                    let credStr = "\(u.stakeCredential)"
                    if let accountCtx = context.findAccountContext(rewardAddress: credStr) {
                        if let payedDeposit = accountCtx.payedDeposit {
                            if u.coin != payedDeposit {
                                issues.append(ValidationError(
                                    kind: .depositMismatch,
                                    fieldPath: "transaction_body.certificates[\(i)]",
                                    message: "Stake deregistration refund \(u.coin) lovelace does not match "
                                        + "original deposit \(payedDeposit) lovelace.",
                                    hint: "Set the refund to \(payedDeposit) lovelace."
                                ))
                            }
                        } else {
                            issues.append(ValidationError(
                                kind: .cannotCheckStakeDeregistrationRefund,
                                fieldPath: "transaction_body.certificates[\(i)]",
                                message: "Cannot verify stake deregistration refund: "
                                    + "original deposit amount is not available from chain state.",
                                isWarning: true
                            ))
                        }
                    } else {
                        issues.append(ValidationError(
                            kind: .cannotCheckStakeDeregistrationRefund,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "Cannot verify stake deregistration refund: "
                                + "account context not available.",
                            isWarning: true
                        ))
                    }
                case .stakeDeregistration(let d):
                    let credStr = "\(d.stakeCredential)"
                    if let accountCtx = context.findAccountContext(rewardAddress: credStr) {
                        if let payedDeposit = accountCtx.payedDeposit {
                            let expectedDeposit = Int(payedDeposit)
                            if protocolParams.stakeAddressDeposit != expectedDeposit {
                                // The Shelley-era cert uses protocol param as refund;
                                // if the original deposit differs, warn.
                                issues.append(ValidationError(
                                    kind: .cannotCheckStakeDeregistrationRefund,
                                    fieldPath: "transaction_body.certificates[\(i)]",
                                    message: "Shelley-era stake deregistration uses protocol param "
                                        + "(\(protocolParams.stakeAddressDeposit)) as refund, "
                                        + "but original deposit was \(payedDeposit) lovelace.",
                                    isWarning: true
                                ))
                            }
                        }
                    }
                default:
                    break
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: DRep deregistration refund check (requires drepContexts)
        // -----------------------------------------------------------------------
        if let certs = body.certificates, !context.drepContexts.isEmpty {
            for (i, cert) in certs.asList.enumerated() {
                if case .unRegisterDRep(let u) = cert {
                    let drepStr = "\(u.drepCredential)"
                    if let drepCtx = context.findDRepContext(drepId: drepStr) {
                        if let payedDeposit = drepCtx.payedDeposit {
                            if u.coin != payedDeposit {
                                issues.append(ValidationError(
                                    kind: .depositMismatch,
                                    fieldPath: "transaction_body.certificates[\(i)]",
                                    message: "DRep deregistration refund \(u.coin) lovelace does not match "
                                        + "original deposit \(payedDeposit) lovelace.",
                                    hint: "Set the refund to \(payedDeposit) lovelace."
                                ))
                            }
                        } else {
                            issues.append(ValidationError(
                                kind: .cannotCheckDRepDeregistrationRefund,
                                fieldPath: "transaction_body.certificates[\(i)]",
                                message: "Cannot verify DRep deregistration refund: "
                                    + "original deposit amount is not available from chain state.",
                                isWarning: true
                            ))
                        }
                    } else {
                        issues.append(ValidationError(
                            kind: .cannotCheckDRepDeregistrationRefund,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "Cannot verify DRep deregistration refund: "
                                + "DRep context not available.",
                            isWarning: true
                        ))
                    }
                }
            }
        }

        // -----------------------------------------------------------------------
        // MARK: Aggregate balance check
        // -----------------------------------------------------------------------

        guard !context.resolvedInputs.isEmpty else {
            // Without resolved inputs we cannot check the aggregate balance.
            return issues
        }

        // Build a lookup from (txId, index) → output for fast resolution
        let utxoMap: [String: TransactionOutput] = Dictionary(
            uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                let key = "\(utxo.input.transactionId)#\(utxo.input.index)"
                return (key, utxo.output)
            }
        )

        // Sum of spending input values — ListOrOrderedSet requires .asArray for iteration
        var inputLovelace: Int = 0
        for input in body.inputs.asArray {
            let key = "\(input.transactionId)#\(input.index)"
            guard let resolved = utxoMap[key] else {
                issues.append(ValidationError(
                    kind: .missingInput,
                    fieldPath: "transaction_body.inputs",
                    message: "Spending input \(key) was not found in resolvedInputs.",
                    hint: "Ensure all spending inputs are included in resolvedInputs."
                ))
                return issues
            }
            inputLovelace += resolved.amount.coin
        }

        // Sum of withdrawals (add to input side) — Coin = UInt64, reduce then convert to Int
        let withdrawalLovelace: Int
        if let withdrawals = body.withdrawals {
            let total: Coin = withdrawals.data.values.reduce(0 as Coin) { acc, coin in acc + coin }
            withdrawalLovelace = Int(total)
        } else {
            withdrawalLovelace = 0
        }

        // Sum of output values
        let outputLovelace = body.outputs.reduce(0) { $0 + $1.amount.coin }

        // Fee — Coin = UInt64, safe to Int on 64-bit platforms
        let feeLovelace = Int(bitPattern: UInt(body.fee))

        // Net deposits: Σ(deposits) - Σ(refunds), goes on the output side.
        // Positive = net ADA locked with protocol; negative = net ADA returned to wallet.
        var netDepositLovelace: Int = 0
        if let certs = body.certificates {
            for cert in certs.asList {
                switch cert {
                    case .stakeRegistration:
                        netDepositLovelace += protocolParams.stakeAddressDeposit
                    case .stakeDeregistration:
                        netDepositLovelace -= protocolParams.stakeAddressDeposit
                    case .register(let r):
                        netDepositLovelace += Int(r.coin)
                    case .unregister(let u):
                        netDepositLovelace -= Int(u.coin)
                    case .poolRegistration(let p):
                        // Only count deposit for first-time registration.
                        // Re-registration (pool already exists) is a parameter update — no deposit.
                        let poolId = "\(p.poolParams.poolOperator)"
                        let isReRegistration = context.findPoolContext(poolId: poolId)?.isRegistered ?? false
                        if !isReRegistration {
                            netDepositLovelace += protocolParams.stakePoolDeposit
                        }
                    case .registerDRep(let r):
                        netDepositLovelace += Int(r.coin)
                    case .unRegisterDRep(let u):
                        netDepositLovelace -= Int(u.coin)
                    case .stakeRegisterDelegate(let d):
                        netDepositLovelace += Int(d.coin)
                    case .voteRegisterDelegate(let d):
                        netDepositLovelace += Int(d.coin)
                    case .stakeVoteRegisterDelegate(let d):
                        netDepositLovelace += Int(d.coin)
                    default:
                        break
                }
            }
        }
        // Governance action deposits (Conway)
        if let proposals = body.proposalProcedures {
            netDepositLovelace += proposals.elementsOrdered.count * protocolParams.govActionDeposit
        }

        // Treasury donation (Conway) — PositiveCoin.value is UInt
        let donationLovelace = body.treasuryDonation.map { Int($0.value) } ?? 0

        let inputTotal  = inputLovelace + withdrawalLovelace
        let outputTotal = outputLovelace + feeLovelace + netDepositLovelace + donationLovelace

        if inputTotal != outputTotal {
            let diff = inputTotal - outputTotal
            issues.append(ValidationError(
                kind: .valueNotConserved,
                fieldPath: "transaction_body",
                message: "Value not conserved: "
                    + "inputs+withdrawals=\(inputTotal) lovelace, "
                    + "outputs+fee+deposits+donation=\(outputTotal) lovelace, "
                    + "difference=\(diff) lovelace.",
                hint: diff > 0
                    ? "Outputs are under-spending by \(diff) lovelace. Check for missing outputs or miscalculated fees."
                    : "Outputs exceed inputs by \(-diff) lovelace. Check for missing inputs or overcounted outputs."
            ))
        }

        return issues
    }
}
