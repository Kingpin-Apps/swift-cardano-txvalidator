import BigInt
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
                        // Check DRep delegation. Only key-hash accounts need
                        // one; header bit 4 marks a script-hash account.
                        let isScriptAccount = rewardAccount.first.map { $0 & 0x10 != 0 } ?? false
                        if accountCtx.delegatedToDRep == nil, !isScriptAccount {
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
                    if let accountCtx = context.findAccountContext(stakeCredential: u.stakeCredential) {
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
                    if let accountCtx = context.findAccountContext(stakeCredential: d.stakeCredential),
                       let payedDeposit = accountCtx.payedDeposit,
                       payedDeposit != protocolParams.stakeAddressDeposit {
                        // The ledger refunds the deposit that was paid, which
                        // a wallet working from today's parameter gets wrong.
                        issues.append(ValidationError(
                            kind: .cannotCheckStakeDeregistrationRefund,
                            fieldPath: "transaction_body.certificates[\(i)]",
                            message: "This deregistration refunds the \(payedDeposit) lovelace deposit that was "
                                + "paid, not today's stakeAddressDeposit of \(protocolParams.stakeAddressDeposit).",
                            isWarning: true
                        ))
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

        // -----------------------------------------------------------------------
        // MARK: Spent input check (requires spentInputRefs from chain context)
        // -----------------------------------------------------------------------
        if !context.spentInputRefs.isEmpty {
            for (i, input) in body.inputs.asArray.enumerated() {
                let isSpent = context.spentInputRefs.contains {
                    $0.transactionId == input.transactionId && $0.index == input.index
                }
                if isSpent {
                    issues.append(ValidationError(
                        kind: .inputAlreadySpent,
                        fieldPath: "transaction_body.inputs[\(i)]",
                        message: "Input \(input.transactionId)#\(input.index) has already been spent on-chain.",
                        hint: "This UTxO no longer exists. The transaction will be rejected as a double-spend.",
                    ))
                }
            }
        }

        // Build a lookup from (txId, index) → output for fast resolution
        let utxoMap: [String: TransactionOutput] = Dictionary(
            uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                let key = "\(utxo.input.transactionId)#\(utxo.input.index)"
                return (key, utxo.output)
            }
        )

        // Sum of spending input values. An input that cannot be resolved
        // leaves the sum unknown — TransactionLimitsRule reports it as a bad
        // input — so the balance is not checked rather than misreported.
        var inputLovelace = BigInt(0)
        for input in body.inputs.asArray {
            let key = "\(input.transactionId)#\(input.index)"
            guard let resolved = utxoMap[key] else {
                issues.append(ValidationError(
                    kind: .cannotCheckBalance,
                    fieldPath: "transaction_body.inputs",
                    message: "Value conservation was not checked: input \(key) could not be resolved.",
                    isWarning: true
                ))
                return issues
            }
            inputLovelace += resolved.amount.coin
        }

        // Sum of withdrawals (add to input side)
        let withdrawalLovelace = body.withdrawals?.data.values.reduce(BigInt(0)) { $0 + BigInt($1) } ?? 0

        // Sum of output values
        let outputLovelace = body.outputs.reduce(BigInt(0)) { $0 + $1.amount.coin }

        let feeLovelace = BigInt(body.fee)

        // Net deposits: Σ(deposits) - Σ(refunds), goes on the output side.
        // Positive = net ADA locked with protocol; negative = net ADA returned to wallet.
        var netDepositLovelace = BigInt(0)
        // A pool registered earlier in this transaction is re-registered by a
        // later certificate, which takes no second deposit.
        var poolsRegisteredHere = Set<String>()
        if let certs = body.certificates {
            for cert in certs.asList {
                switch cert {
                    case .stakeRegistration:
                        netDepositLovelace += BigInt(protocolParams.stakeAddressDeposit)
                    case .stakeDeregistration(let d):
                        // The ledger refunds the deposit that was paid, when
                        // the chain state says what it was.
                        let paid = context.findAccountContext(stakeCredential: d.stakeCredential)?.payedDeposit
                        netDepositLovelace -= BigInt(paid ?? protocolParams.stakeAddressDeposit)
                    case .register(let r):
                        netDepositLovelace += BigInt(r.coin)
                    case .unregister(let u):
                        netDepositLovelace -= BigInt(u.coin)
                    case .poolRegistration(let p):
                        // Only count deposit for first-time registration.
                        // Re-registration (pool already exists) is a parameter update — no deposit.
                        let poolId = "\(p.poolParams.poolOperator)"
                        let isReRegistration = context.findPoolContext(poolId: poolId)?.isRegistered ?? false
                        if !isReRegistration && poolsRegisteredHere.insert(poolId).inserted {
                            netDepositLovelace += BigInt(protocolParams.stakePoolDeposit)
                        }
                    case .registerDRep(let r):
                        netDepositLovelace += BigInt(r.coin)
                    case .unRegisterDRep(let u):
                        netDepositLovelace -= BigInt(u.coin)
                    case .stakeRegisterDelegate(let d):
                        netDepositLovelace += BigInt(d.coin)
                    case .voteRegisterDelegate(let d):
                        netDepositLovelace += BigInt(d.coin)
                    case .stakeVoteRegisterDelegate(let d):
                        netDepositLovelace += BigInt(d.coin)
                    default:
                        break
                }
            }
        }
        // Governance action deposits (Conway): each proposal's own deposit,
        // as the ledger balances them. Whether that deposit is the right one
        // is the per-proposal check above.
        if let proposals = body.proposalProcedures {
            netDepositLovelace += proposals.elementsOrdered.reduce(BigInt(0)) { $0 + BigInt($1.deposit) }
        }

        // Treasury donation (Conway)
        let donationLovelace = body.treasuryDonation.map { BigInt($0.value) } ?? 0
        
        if inputLovelace > 0 {
            
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
            
        }

        return issues
    }
}
