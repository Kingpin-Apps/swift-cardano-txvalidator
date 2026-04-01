# Error Reference

A complete catalogue of every ``ValidationError/Kind`` case, which rule produces it, and how to fix it.

## Overview

Every ``ValidationError`` carries a ``ValidationError/kind`` that identifies the category of failure. This article lists every kind, the built-in rule that emits it, and the most common fix.

Errors where ``ValidationError/isWarning`` is `true` are advisory — the transaction will still be accepted by the node.

---

## Phase-1 Errors

Phase-1 errors are produced by the eight built-in ``Phase1Validator`` rules and any custom rules you add.

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
- **Fix:** Check that all spending inputs are accounted for in `resolvedInputs`, that the change output is correctly sized, and that certificate deposits/refunds are modelled correctly.

#### `missingInput`

- **Rule:** ``BalanceRule``
- **Field path:** `transaction_body.inputs[n]`
- **Cause:** One or more spending inputs are not present in the `ValidationContext.resolvedInputs` list provided to the validator.
- **Fix:** Ensure every input referenced in the transaction body is included in `context.resolvedInputs`.

---

### Collateral Errors

#### `noCollateralInputs`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral`
- **Cause:** The transaction contains redeemers (i.e., it uses Plutus scripts) but declares no collateral inputs.
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
- **Cause:** The `totalCollateral` field in the transaction body does not match the computed value `Σ(collateral_inputs) − collateral_return`.
- **Fix:** Recompute `totalCollateral` as the net collateral amount and update the field.

#### `collateralLockedByScript`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral[n]`
- **Cause:** One of the collateral inputs is locked by a script rather than a plain key hash address.
- **Fix:** Use only wallet (vkey) UTxOs as collateral.

#### `collateralContainsNonAdaAssets`

- **Rule:** ``CollateralRule``
- **Field path:** `transaction_body.collateral[n]`
- **Cause:** A collateral input contains native tokens in addition to ADA, and there is no collateral return to capture the change.
- **Fix:** Either use ADA-only UTxOs for collateral, or add a `collateralReturn` output that returns the native tokens to a wallet address.

---

### Script Integrity Errors

#### `scriptDataHashMismatch`

- **Rule:** ``ScriptIntegrityRule``
- **Field path:** `transaction_body.script_data_hash`
- **Cause:** The `script_data_hash` field does not match `Blake2b256(redeemers_cbor ‖ datums_cbor ‖ language_views_cbor)` as computed from the witness set and current cost models.
- **Fix:** Regenerate the script data hash after any change to redeemers, datums, or cost models in the witness set. Most transaction builders do this automatically.

---

### Validity Interval Errors

#### `outsideValidityInterval`

- **Rule:** ``ValidityIntervalRule``
- **Field path:** `transaction_body.ttl` / `transaction_body.validity_start`
- **Cause:** `currentSlot` falls outside `[validityStart, ttl)`. Either the transaction has expired or its validity start has not yet been reached.
- **Fix:** Resubmit with an updated TTL, or wait until the validity start is reached. If you are testing, make sure `ValidationContext.currentSlot` reflects the actual current slot.

---

### Signer Errors

#### `missingRequiredSigner`

- **Rule:** ``RequiredSignersRule``
- **Field path:** `transaction_body.required_signers[n]`
- **Cause:** A key hash listed in `required_signers` has no matching vkey witness in the witness set.
- **Fix:** Sign the transaction with the corresponding private key.

---

### Output Value Errors

#### `outputTooSmall`

- **Rule:** ``OutputValueRule``
- **Field path:** `transaction_body.outputs[n]`
- **Cause:** An output's ADA value is below `utxoCostPerByte × (160 + serialized_output_size)`.
- **Fix:** Increase the output's ADA to meet the minimum. This threshold rises with the size of the output (more native tokens = larger output = higher minimum).

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
- **Cause:** An output address (or collateral return) uses a different network tag than the expected network (mainnet vs. testnet).
- **Fix:** Ensure all addresses in the transaction are generated for the correct network.

---

## Phase-2 Errors

Phase-2 errors are produced by ``Phase2Validator`` when Plutus scripts are executed via the CEK machine.

#### `plutusScriptFailed`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** A Plutus script evaluated to `Error`. The script's own logic rejected the transaction.
- **Fix:** Debug the script with the redeemer and datum that caused the failure. Use the `message` field for any error detail provided by the CEK machine.

#### `missingRedeemer`

- **Field path:** `transaction_body.inputs[n]`
- **Cause:** A script-locked input has no corresponding redeemer in the witness set.
- **Fix:** Add a redeemer for the script at the correct index in the sorted input list.

#### `missingDatum`

- **Field path:** `transaction_body.inputs[n]`
- **Cause:** A script-locked input's datum cannot be resolved — it is neither an inline datum in the UTxO nor in the transaction's datum witness list.
- **Fix:** Either attach the datum inline to the UTxO (Babbage/Conway style) or include it in the witness set datums.

#### `missingScript`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** A redeemer references a script hash that is not present in the transaction's Plutus script witnesses.
- **Fix:** Add the referenced Plutus script to the witness set.

#### `extraneousRedeemer`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** The witness set contains a redeemer that does not correspond to any script-locked input, minting policy, withdrawal, or certificate.
- **Fix:** Remove the unnecessary redeemer.

#### `executionBudgetExceeded`

- **Field path:** `transaction_witness_set.redeemers[n]`
- **Cause:** The script consumed more execution units (CPU steps or memory) than the budget declared in its redeemer.
- **Fix:** Increase the execution units in the redeemer, or optimise the script to use fewer resources.

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
