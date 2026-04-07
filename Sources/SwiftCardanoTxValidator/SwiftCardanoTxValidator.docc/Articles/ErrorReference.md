# Error Reference

A complete catalogue of every ``ValidationError/Kind`` case, which rule produces it, and how to fix it.

## Overview

Every ``ValidationError`` carries a ``ValidationError/kind`` that identifies the category of failure. This article lists every kind, the built-in rule that emits it, and the most common fix.

Errors where ``ValidationError/isWarning`` is `true` are advisory — the transaction will still be accepted by the node.

---

## Phase-1 Errors

Phase-1 errors are produced by the built-in ``Phase1Validator`` rules and any custom rules you add.

### Auxiliary Data Errors

#### `auxiliaryDataHashMissing`

- **Rule:** ``AuxiliaryDataRule``
- **Field path:** `transaction_body.auxiliary_data_hash`
- **Cause:** The transaction contains auxiliary data but the `auxiliary_data_hash` field in the body is absent.
- **Fix:** Compute `Blake2b256(CBOR(auxiliaryData))` and set `auxiliary_data_hash` in the transaction body.

#### `auxiliaryDataHashUnexpected`

- **Rule:** ``AuxiliaryDataRule``
- **Field path:** `transaction_body.auxiliary_data_hash`
- **Cause:** The body declares an `auxiliary_data_hash` but the transaction contains no auxiliary data.
- **Fix:** Remove the `auxiliary_data_hash` field, or attach the corresponding auxiliary data to the transaction.

#### `auxiliaryDataHashMismatch`

- **Rule:** ``AuxiliaryDataRule``
- **Field path:** `transaction_body.auxiliary_data_hash`
- **Cause:** The `auxiliary_data_hash` field does not match `Blake2b256(CBOR(auxiliaryData))`.
- **Fix:** Recompute the hash after any change to the transaction's auxiliary data.

---

### Transaction Limit Errors

#### `inputSetEmpty`

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_body.inputs`
- **Cause:** The transaction has no spending inputs. At least one is required by the ledger.
- **Fix:** Add at least one UTxO as a spending input.

#### `maximumTransactionSizeExceeded`

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_body` or `transaction_body.reference_inputs`
- **Cause:** The serialised CBOR of the transaction exceeds `maxTxSize` bytes, or the total size of inline reference scripts referenced by the transaction exceeds the protocol limit.
- **Fix:** Remove unnecessary witnesses, datums, or scripts, or split the work across multiple transactions.

#### `executionUnitsTooLarge`

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_witness_set.redeemers`
- **Cause:** The sum of all declared execution units (CPU steps or memory) in the transaction's redeemers exceeds `maxTxExecutionUnits`.
- **Fix:** Reduce declared execution units or split scripts across multiple transactions.

#### `referenceInputOverlapsWithInput`

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_body.reference_inputs[n]`
- **Cause:** A UTxO appears in both the spending input set and the reference input set.
- **Fix:** A UTxO can appear in only one set. Use it as a spending input if you intend to consume it, or a reference input if you only need to read it.

#### `badInput`

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_body.inputs[n]`
- **Cause:** A spending input is not present in `context.resolvedInputs` — it either does not exist or has already been spent.
- **Fix:** Remove the stale input or provide the correct resolved UTxO.

#### `inputsNotSorted` *(warning)*

- **Rule:** ``TransactionLimitsRule``
- **Field path:** `transaction_body.inputs`
- **Cause:** The spending inputs are not in canonical lexicographic order (sort by transaction ID, then by output index). Most nodes accept this, but some tooling enforces the canonical order.
- **Fix:** Sort spending inputs lexicographically.

---

### Fee Errors

#### `feeTooSmall`

- **Rule:** ``FeeRule``
- **Field path:** `transaction_body.fee`
- **Cause:** The declared fee is below the protocol minimum, computed as `txFeeFixed + txFeePerByte × tx_size_bytes`.
- **Fix:** Increase the fee to at least the computed minimum. Most transaction builders do this automatically; check that `txFeePerByte` and `txFeeFixed` are sourced from current protocol parameters.

#### `feeTooBig` *(warning)*

- **Rule:** ``FeeRule``
- **Field path:** `transaction_body.fee`
- **Cause:** The declared fee is more than 10% above the protocol minimum.
- **Fix:** This is a warning, not a rejection. If you're building the transaction, reduce the fee toward the computed minimum to avoid overpaying.

---

### Balance Errors

#### `valueNotConserved`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body`
- **Cause:** The equation `Σ(inputs) + Σ(withdrawals) + Σ(refunds) ≠ Σ(outputs) + fee + Σ(deposits) + donation` does not hold.
- **Fix:** Check that all spending inputs are accounted for in `resolvedInputs`, that the change output is correctly sized, and that certificate deposits/refunds and governance proposal deposits are modelled correctly.

#### `wrongWithdrawalAmount`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body.withdrawals`
- **Cause:** A withdrawal amount does not match the reward account's actual balance on-chain.
- **Fix:** Withdraw the exact reward balance. Partial withdrawals are not permitted on Cardano.

#### `withdrawalNotDelegatedToDRep`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body.withdrawals`
- **Cause:** (Conway+) A reward withdrawal was attempted but the stake key is not delegated to a DRep, which is required before withdrawals are permitted in the Conway era.
- **Fix:** Delegate the stake key to a DRep before withdrawing rewards.

#### `rewardAccountNotExisting`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body.withdrawals`
- **Cause:** A withdrawal references a reward account that does not exist in the ledger.
- **Fix:** Remove the withdrawal or verify the reward address.

#### `treasuryValueMismatch`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body`
- **Cause:** The treasury withdrawal amount declared in a governance proposal does not match the actual treasury value in ledger state.
- **Fix:** Ensure the treasury withdrawal amount matches `context.treasuryValue`.

---

### Collateral Errors

#### `noCollateralInputs`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral`
- **Cause:** The transaction contains redeemers but declares no collateral inputs.
- **Fix:** Add at least one ADA-only, non-script-locked UTxO as a collateral input.

#### `tooManyCollateralInputs`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral`
- **Cause:** The number of collateral inputs exceeds `protocolParameters.maxCollateralInputs`.
- **Fix:** Remove collateral inputs until the count is at or below the maximum (typically 3).

#### `insufficientCollateral`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral`
- **Cause:** The total ADA in collateral inputs (minus the collateral return, if any) is less than `fee × collateralPercentage ÷ 100`.
- **Fix:** Add higher-value collateral UTxOs, or reduce the transaction fee.

#### `incorrectTotalCollateral`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.total_collateral`
- **Cause:** The `totalCollateral` field does not match `Σ(collateral_inputs) − collateral_return`.
- **Fix:** Recompute `totalCollateral` as the net collateral amount and update the field.

#### `collateralLockedByScript`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral[n]`
- **Cause:** One of the collateral inputs is locked by a script rather than a plain key hash address.
- **Fix:** Use only wallet (vkey) UTxOs as collateral.

#### `collateralContainsNonAdaAssets`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral[n]`
- **Cause:** A collateral input contains native tokens and there is no collateral return to capture the change.
- **Fix:** Either use ADA-only UTxOs for collateral, or add a `collateralReturn` output that returns the native tokens to a wallet address.

#### `collateralUnnecessary` *(warning)*

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral`
- **Cause:** Collateral inputs are declared but no redeemers are present — collateral is not needed.
- **Fix:** Remove the collateral field if this transaction does not execute scripts.

#### `collateralReturnTooSmall`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral_return`
- **Cause:** The collateral return output is below the minimum ADA (minUTxO) requirement.
- **Fix:** Increase the ADA in the collateral return output to meet the minimum.

---

### Script Integrity Errors

#### `scriptDataHashMismatch`

- **Rule:** ``ScriptIntegrityRule``
- **Field path:** `transaction_body.script_data_hash`
- **Cause:** The `script_data_hash` field does not match `Blake2b256(redeemers_cbor ‖ datums_cbor ‖ language_views_cbor)` as computed from the witness set and current cost models.
- **Fix:** Regenerate the script data hash after any change to redeemers, datums, or cost models. Most transaction builders do this automatically.

---

### Validity Interval Errors

#### `outsideValidityInterval`

- **Rule:** ``ValidityIntervalRule``
- **Field path:** `transaction_body.ttl` / `transaction_body.validity_start`
- **Cause:** `currentSlot` falls outside `[validityStart, ttl)`. Either the transaction has expired or its validity start has not yet been reached.
- **Fix:** Resubmit with an updated TTL, or wait until the validity start is reached.

---

### Witness Errors

#### `missingRequiredSigner`

- **Rule:** ``RequiredSignersRule``, ``SignatureRule``
- **Field path:** `transaction_body.required_signers[n]` or `transaction_witness_set.vkeyWitnesses`
- **Cause:** A key hash listed in `required_signers`, or required to authorise a spending input or withdrawal, has no matching vkey witness in the witness set.
- **Fix:** Sign the transaction with the corresponding private key.

#### `missingScript`

- **Rule:** ``WitnessRule``
- **Field path:** `transaction_body.inputs[n]` or `transaction_body.mint.policy[n]`
- **Cause:** A script-locked spending input or minting policy requires a script that is not present in the witness set and not available as an inline reference script.
- **Fix:** Include the script in the witness set, or provide a reference input that carries the script inline.

#### `extraneousScript` *(warning)*

- **Rule:** ``WitnessRule``
- **Field path:** `transaction_witness_set.scripts`
- **Cause:** A script is present in the witness set but not required by any spending input, minting policy, certificate, or withdrawal.
- **Fix:** Remove the unused script to reduce transaction size.

#### `nativeScriptFailed`

- **Rule:** ``WitnessRule``
- **Field path:** `transaction_body.inputs[n]` or `transaction_body.mint.policy[n]`
- **Cause:** A native script's multisig or timelock evaluation failed against the transaction body and witness set.
- **Fix:** Ensure all required signers are present in the witness set and that the transaction's validity interval satisfies any `invalidBefore` / `invalidHereAfter` timelock bounds.

#### `missingDatum`

- **Rule:** ``WitnessRule``
- **Field path:** `transaction_body.inputs[n]`
- **Cause:** A PlutusV1 or PlutusV2 script-locked input requires a datum, but none is provided inline in the UTxO or in the transaction witness set.
- **Fix:** Either attach the datum inline to the UTxO (Babbage/Conway) or include the datum bytes in the witness set.

#### `extraneousDatum` *(warning)*

- **Rule:** ``WitnessRule``
- **Field path:** `transaction_witness_set.plutusData`
- **Cause:** A datum is present in the witness set but not referenced by any spending input.
- **Fix:** Remove the unused datum to reduce transaction size.

#### `missingRedeemer`

- **Rule:** ``WitnessRule``, ``Phase2Validator``
- **Field path:** `transaction_witness_set.redeemers`
- **Cause:** Plutus scripts are required (by spending inputs or minting policies) but no redeemers are present in the witness set.
- **Fix:** Add a redeemer for each Plutus script invocation.

#### `extraneousRedeemer` *(warning)*

- **Rule:** ``WitnessRule``, ``Phase2Validator``
- **Field path:** `transaction_witness_set.redeemers`
- **Cause:** Redeemers are present but no Plutus scripts appear to be required by the resolved inputs or minting policies.
- **Fix:** Remove the redeemers if no scripts are being executed.

---

### Signature Errors

#### `invalidSignature`

- **Rule:** ``SignatureRule``
- **Field path:** `transaction_witness_set.vkeyWitnesses[n]` or `transaction_witness_set.bootstrapWitness[n]`
- **Cause:** Ed25519 signature verification failed — the signature does not match the transaction body hash for the given vkey.
- **Fix:** Ensure the transaction was signed with the correct private key and the transaction body has not been modified after signing.

#### `missingBootstrapWitness`

- **Rule:** ``SignatureRule``
- **Field path:** `transaction_witness_set.bootstrapWitness`
- **Cause:** The transaction spends one or more Byron-addressed inputs but no bootstrap witnesses are present.
- **Fix:** Sign the transaction with the Byron private key(s) corresponding to the spending inputs and include the bootstrap witnesses.

#### `extraneousSignature` *(warning)*

- **Rule:** ``SignatureRule``
- **Field path:** `transaction_witness_set.vkeyWitnesses[n]` or `transaction_witness_set.bootstrapWitness`
- **Cause:** A vkey or bootstrap witness is present but not required by any spending input, withdrawal, certificate, minting policy, or `requiredSigners`.
- **Fix:** Remove unreferenced witnesses to reduce transaction size.

---

### Output Value Errors

#### `outputTooSmall`

- **Rule:** ``OutputValueRule``
- **Field path:** `transaction_body.outputs[n]`
- **Cause:** An output's ADA value is below `utxoCostPerByte × (160 + serialized_output_size)`.
- **Fix:** Increase the output's ADA to meet the minimum. This threshold rises with the size of the output.

#### `outputValueTooBig`

- **Rule:** ``OutputValueRule``
- **Field path:** `transaction_body.outputs[n]`
- **Cause:** The serialised value of an output exceeds `maxValueSize` bytes (typically 5000 bytes).
- **Fix:** Reduce the number of distinct native token policies or asset names in the output.

---

### Network Errors

#### `networkIdMismatch`

- **Rule:** ``NetworkIdRule``
- **Field path:** `transaction_body.outputs[n].address` / `transaction_body.collateral_return.address`
- **Cause:** An output address or collateral return uses a different network tag than the expected network.
- **Fix:** Ensure all addresses are generated for the correct network (mainnet vs. testnet).

---

### Registration Errors

#### `stakeAlreadyRegistered`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A `stakeRegistration` or `register` certificate was submitted for a stake key that is already registered on-chain.
- **Fix:** Remove the duplicate registration, or deregister the key first.

#### `stakeNotRegistered`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A deregistration or delegation certificate references a stake key that is not registered.
- **Fix:** Register the stake key before delegating or deregistering.

#### `stakeNonZeroAccountBalance`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A stake key deregistration was attempted but the reward account has a non-zero balance.
- **Fix:** Withdraw all rewards before deregistering the stake key.

#### `stakePoolNotRegistered`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A delegation or pool retirement certificate references a pool that is not registered.
- **Fix:** Ensure the pool is registered before delegating to it or retiring it.

#### `stakePoolCostTooLow`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** The pool's declared operating cost is below `minPoolCost`.
- **Fix:** Set the pool cost to at least `minPoolCost` lovelace.

#### `wrongRetirementEpoch`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** The pool retirement epoch is outside the valid range `[currentEpoch + 1, currentEpoch + poolRetireMaxEpoch]`.
- **Fix:** Set the retirement epoch within the valid range.

#### `committeeIsUnknown`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** An `authCommitteeHot` or `resignCommitteeCold` certificate references a cold credential that is not known to the ledger.
- **Fix:** Verify the committee cold credential is correct.

#### `committeeHasPreviouslyResigned`

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** An `authCommitteeHot` certificate references a committee member who has already resigned on-chain or in this transaction.
- **Fix:** A resigned member cannot authorize a new hot key. Coordinate with the committee governance process.

#### `poolAlreadyRegistered` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A `poolRegistration` certificate was submitted for a pool that is already registered. This is a pool update, not an error.
- **Fix:** This is advisory. No action required if you intend to update pool parameters.

#### `drepAlreadyRegistered` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** A `registerDRep` certificate was submitted for a DRep that is already registered.
- **Fix:** This is advisory. Remove the certificate if you don't intend to re-register.

#### `drepNotRegistered` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** An `unRegisterDRep` or `updateDRep` certificate references a DRep that is not registered.
- **Fix:** Verify the DRep credential or register the DRep first.

#### `committeeAlreadyAuthorized` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** An `authCommitteeHot` certificate targets a committee member who already has an authorized hot credential.
- **Fix:** This is advisory. The new authorization will replace the existing one.

#### `duplicateRegistrationInTx` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** The same entity (stake key, pool, or DRep) is registered more than once in a single transaction.
- **Fix:** Remove the duplicate certificate.

#### `duplicateCommitteeColdResignationInTx` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** The same committee cold credential appears in more than one `resignCommitteeCold` certificate within the transaction.
- **Fix:** Remove the duplicate resignation certificate.

#### `duplicateCommitteeHotRegistrationInTx` *(warning)*

- **Rule:** ``RegistrationRule``
- **Field path:** `transaction_body.certificates[n]`
- **Cause:** The same committee cold credential is authorized in more than one `authCommitteeHot` certificate within the transaction.
- **Fix:** Remove the duplicate authorization certificate.

---

### Governance Proposal Errors (Conway)

#### `proposalProcedureNetworkIdMismatch`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].reward_account`
- **Cause:** The proposal's reward account uses a different network than the transaction's target network.
- **Fix:** Use a reward address encoded for the correct network.

#### `proposalReturnAccountDoesNotExist`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].reward_account`
- **Cause:** The proposal's return account is not registered in the ledger.
- **Fix:** Register the stake key that corresponds to the return address before submitting the proposal.

#### `invalidPrevGovActionId`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action`
- **Cause:** The previous governance action ID referenced by the proposal either does not exist in the ledger or has a different action type than expected.
- **Fix:** Verify the previous action ID references an existing, enacted governance action of the correct type.

#### `zeroTreasuryWithdrawals`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action.withdrawals`
- **Cause:** A `TreasuryWithdrawalsAction` proposal specifies withdrawal amounts that sum to zero.
- **Fix:** Include at least one non-zero treasury withdrawal amount.

#### `treasuryWithdrawalsNetworkIdMismatch`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action.withdrawals`
- **Cause:** A treasury withdrawal recipient address uses a different network than the transaction's target network.
- **Fix:** Use a recipient reward address for the correct network.

#### `treasuryWithdrawalReturnAccountDoesNotExist`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action.withdrawals`
- **Cause:** A treasury withdrawal recipient account does not exist in the ledger.
- **Fix:** Register the stake key for each withdrawal recipient before proposing.

#### `conflictingCommitteeUpdate`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action`
- **Cause:** An `UpdateCommittee` action includes the same committee cold credential in both the add set (with expiry epoch) and the remove set.
- **Fix:** A credential cannot be added and removed in the same action. Remove it from one of the sets.

#### `expirationEpochTooSmall`

- **Rule:** ``GovernanceProposalRule``
- **Field path:** `transaction_body.proposal_procedures[n].gov_action`
- **Cause:** A committee member's expiration epoch in an `UpdateCommittee` action is not strictly greater than the current epoch.
- **Fix:** Set the expiration epoch to a value after the current epoch.

---

### Voting Errors (Conway)

#### `govActionsDoNotExist`

- **Rule:** ``VotingRule``
- **Field path:** `transaction_body.voting_procedures[txId#index]`
- **Cause:** A vote references a governance action ID that does not exist in the ledger.
- **Fix:** Verify the governance action ID is correct.

#### `votingOnExpiredGovAction`

- **Rule:** ``VotingRule``
- **Field path:** `transaction_body.voting_procedures[txId#index]`
- **Cause:** A vote targets a governance action that is no longer active (it has expired or been enacted).
- **Fix:** Remove the vote for the inactive action.

#### `disallowedVoter`

- **Rule:** ``VotingRule``
- **Field path:** `transaction_body.voting_procedures[txId#index]`
- **Cause:** The voter type (constitutional committee, DRep, or SPO) is not permitted to vote on the referenced action type per the CIP-1694 permission matrix.

  | Action Type | CC | DRep | SPO |
  |---|---|---|---|
  | `NoConfidence` | ✗ | ✓ | ✓ |
  | `UpdateCommittee` | ✗ | ✓ | ✓ |
  | `NewConstitution` | ✓ | ✓ | ✗ |
  | `HardForkInitiation` | ✓ | ✓ | ✓ |
  | `ParameterChange` | ✓ | ✓ | ✗ |
  | `TreasuryWithdrawals` | ✓ | ✓ | ✗ |
  | `InfoAction` | ✓ | ✓ | ✓ |

- **Fix:** Remove the vote or ensure the voter type matches the CIP-1694 matrix.

#### `voterDoesNotExist`

- **Rule:** ``VotingRule``
- **Field path:** `transaction_body.voting_procedures[txId#index]`
- **Cause:** The voter (constitutional committee hot key, DRep, or stake pool) is not registered in the ledger.
- **Fix:** Ensure the voter is registered before casting a vote.

---

## Phase-2 Errors

Phase-2 errors are produced by ``Phase2Validator`` when Plutus scripts are executed via the CEK machine.

#### `plutusScriptFailed`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** A Plutus script evaluated to `Error`. The script's own logic rejected the transaction.
- **Fix:** Debug the script with the redeemer and datum that caused the failure.

#### `executionBudgetExceeded`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** The script consumed more execution units (CPU steps or memory) than the budget declared in its redeemer.
- **Fix:** Increase the execution units in the redeemer, or optimise the script.

#### `excessiveExecutionUnits` *(warning)*

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** The declared execution units are significantly higher than the units actually consumed by the script. The transaction will be accepted but you are over-estimating.
- **Fix:** Lower the declared execution units closer to the calculated cost.

---

## Generic / Parse Errors

#### `malformedCBOR`

- **Field path:** `transaction`
- **Cause:** The input hex could not be decoded as valid CBOR, or the decoded CBOR does not conform to the Cardano transaction structure.
- **Fix:** Verify that the CBOR hex is complete and correctly encoded.

#### `unknown`

- **Field path:** varies
- **Cause:** Catch-all for errors that do not fit a more specific category, including errors thrown by custom rules or unexpected internal failures.
- **Fix:** Inspect the `message` field for details.
