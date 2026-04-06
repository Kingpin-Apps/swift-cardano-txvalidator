# SwiftCardanoTxValidator

A Swift package for parsing, inspecting, and validating Cardano transactions — covering both **Phase-1** (ledger rule checks) and **Phase-2** (Plutus script execution via the CEK machine).


---

## Features

- **Transaction parsing** — decode any raw CBOR hex into a structured, human-readable view
- **Phase-1 validation** — 15 built-in ledger rules covering fees, balance, collateral, script integrity, witnesses, signatures, output values, network IDs, registrations, and Conway-era governance
- **Phase-2 validation** — Plutus V1/V2/V3 script execution via `SwiftCardanoUPLC`
- **Conway governance** — `GovernanceProposalRule` and `VotingRule` implement the CIP-1694 validation matrix
- **Custom rules** — extend the rule set by conforming to `ValidationRule`
- **Chain-state context** — pass optional `ValidationContext` fields (accounts, pools, DReps, committee members, governance actions) for full ledger-level checks
- **`necessaryData()`** — inspect a transaction to discover exactly which chain-state records to fetch before validation
- **Structured errors** — every error carries a CBOR field path, a human-readable message, and an optional remediation hint
- **JSON export** — `TxValidatorReport` is fully `Codable`; call `.toJSON()` for pretty-printed output
- **Modern Swift** — async/await, Swift 6 strict concurrency, `Sendable` throughout

---

## Requirements

| Requirement | Version |
|---|---|
| Swift | 6.0+ |
| macOS | 15+ |
| iOS | 18+ |

---

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/Kingpin-Apps/swift-cardano-txvalidator.git",
        from: "1.0.0"
    ),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftCardanoTxValidator", package: "swift-cardano-txvalidator"),
        ]
    ),
]
```

---

## Quick Start

### Inspect a transaction

Parse a raw CBOR hex string into a human-readable `TransactionView`:

```swift
import SwiftCardanoTxValidator

let validator = TxValidator()

let view = try validator.inspect(cborHex: rawTxHex)
print(view.txId)          // Blake2b-256 hash of the transaction body
print(view.fee)           // Fee in lovelace
print(view.inputs)        // ["<txhash>#<index>", ...]
print(view.outputs)       // [OutputView]
print(try validator.inspect(cborHex: rawTxHex).toJSON())  // via TxValidatorReport
```

### Phase-1 validation (ledger rules only)

Validate a transaction against the current protocol parameters without requiring a live node:

```swift
import SwiftCardanoTxValidator
import SwiftCardanoCore

let validator = TxValidator()

// Provide resolved UTxOs for balance and collateral checking
let context = ValidationContext(
    resolvedInputs: myUTxOs,        // [UTxO] — the inputs being spent
    currentSlot: 42_000_000,        // UInt64 — for validity interval checks
    network: .mainnet               // NetworkId — for address network checks
)

let report = try await validator.validatePhase1(
    cborHex: rawTxHex,
    protocolParams: protocolParams,
    context: context
)

if report.isValid {
    print("Transaction is valid")
} else {
    for error in report.allErrors {
        print("[\(error.kind)] \(error.fieldPath): \(error.message)")
        if let hint = error.hint { print("  Hint: \(hint)") }
    }
}
```

### Full validation (Phase-1 + Phase-2 Plutus)

Pass a `ChainContext` to enable Phase-2 Plutus script execution:

```swift
import SwiftCardanoTxValidator
import SwiftCardanoChain

let validator = TxValidator()
let blockfrost = BlockFrostChainContext(projectId: "mainnetXXX...")

let report = try await validator.validate(
    cborHex: rawTxHex,
    protocolParams: try await blockfrost.protocolParameters(),
    context: ValidationContext(resolvedInputs: utxos, currentSlot: slot, network: .mainnet),
    chainContext: blockfrost
)

print(try report.toJSON())   // Pretty-printed JSON report
```

### Export to JSON

`TxValidatorReport` conforms to `Codable`:

```swift
let json = try report.toJSON()
// {
//   "transactionView": { "txId": "abc...", "fee": 180000, ... },
//   "phase1Result": { "status": "valid", "issues": [] },
//   "phase2Result": { "status": "invalid", "issues": [...] }
// }
```

---

## Validation Rules

### Built-in Phase-1 rules

| Rule | What it checks |
|---|---|
| `AuxiliaryDataRule` | `auxiliaryDataHash` presence, absence, and Blake2b-256 integrity |
| `TransactionLimitsRule` | Non-empty input set, max tx size, total execution units, reference/spending input overlap, canonical input ordering |
| `FeeRule` | `fee ≥ txFeeFixed + txFeePerByte × tx_size` (warns if >10% over minimum) |
| `BalanceRule` | `Σ(inputs) + Σ(withdrawals) + Σ(refunds) = Σ(outputs) + fee + Σ(deposits) + donation` |
| `CollateralRule` | Collateral presence, count ≤ max, ADA ≥ fee × collateralPercentage, no script-locked collateral |
| `ScriptIntegrityRule` | `scriptDataHash = Blake2b256(redeemers ‖ datums ‖ language_views)` |
| `ValidityIntervalRule` | `validityStart ≤ currentSlot < ttl` |
| `RequiredSignersRule` | Every required signer key hash has a matching vkey witness |
| `WitnessRule` | Script witness completeness, native script (multisig/timelock) evaluation, datum availability, extraneous witness detection |
| `SignatureRule` | Ed25519 vkey and bootstrap signature verification; key-hash coverage for spending inputs and withdrawals |
| `OutputValueRule` | Each output carries `minAda = utxoCostPerByte × (160 + size)` |
| `NetworkIdRule` | All output addresses (including collateral return) match expected network |
| `RegistrationRule` | Stake key, pool, DRep, and committee registration/deregistration/delegation consistency against chain state |
| `GovernanceProposalRule` | Conway proposal procedures: reward-account network, prev-action IDs, treasury withdrawals, committee-update conflicts |
| `VotingRule` | Conway voting: voter existence, action activity, CIP-1694 voter-permission matrix |

### Chain-state context

`ValidationContext` carries optional chain-state arrays. Rules that use them skip gracefully when the arrays are empty, so you can always run partial validation:

```swift
let context = ValidationContext(
    resolvedInputs: myUTxOs,
    currentSlot: 42_000_000,
    network: .mainnet,
    // Chain-state for registration / governance checks:
    accountContexts: accountContexts,    // [AccountInputContext]
    poolContexts: poolContexts,          // [PoolInputContext]
    drepContexts: drepContexts,          // [DRepInputContext]
    govActionContexts: govActionContexts,// [GovActionInputContext]
    currentCommitteeMembers: ccMembers,  // [CommitteeInputContext]
    currentEpoch: 500,
    era: .conway
)
```

Use `TxValidator.necessaryData(cborHex:)` to discover exactly which chain-state records to fetch for a given transaction before constructing the context:

```swift
let necessary = try validator.necessaryData(cborHex: rawTxHex)
// necessary.inputs            — UTxO references to resolve
// necessary.rewardAccounts    — stake addresses to query
// necessary.stakePools        — pool IDs to query
// necessary.dReps             — DRep IDs to query
// necessary.govActionIds      — governance action IDs to query
// necessary.committeeMembersCold — committee cold credentials to query
```

### Graceful degradation

Rules that need resolved inputs, the current slot, or chain-state data skip their checks rather than failing when that data is absent from `ValidationContext`. This lets you run partial validation during transaction construction.

### Adding custom rules

Conform to `ValidationRule` and pass your rule to the `TxValidator` initialiser:

```swift
struct MyCustomRule: ValidationRule {
    var name: String { "MyCustomRule" }

    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        // Return an empty array if the rule passes.
        guard someCondition(transaction) else {
            return [ValidationError(
                kind: .unknown,
                fieldPath: "transaction_body.outputs",
                message: "Custom constraint violated",
                hint: "Try doing X instead"
            )]
        }
        return []
    }
}

let validator = TxValidator(additionalRules: [MyCustomRule()])
```

---

## Error Reference

Every `ValidationError` carries:

| Property | Type | Description |
|---|---|---|
| `kind` | `ValidationError.Kind` | Enum case identifying the failure category |
| `fieldPath` | `String` | Dot-separated CBOR path, e.g. `"transaction_body.fee"` |
| `message` | `String` | Human-readable description of the failure |
| `hint` | `String?` | Optional remediation suggestion |
| `isWarning` | `Bool` | `true` for non-fatal warnings (e.g. `feeTooBig`) |

### Error kinds

**Auxiliary data**

| Kind | Description |
|---|---|
| `auxiliaryDataHashMissing` | Auxiliary data present but `auxiliaryDataHash` field absent |
| `auxiliaryDataHashUnexpected` | `auxiliaryDataHash` declared but no auxiliary data present |
| `auxiliaryDataHashMismatch` | `auxiliaryDataHash` doesn't match Blake2b-256 of auxiliary data CBOR |

**Transaction limits**

| Kind | Description |
|---|---|
| `inputSetEmpty` | Transaction has no spending inputs |
| `maximumTransactionSizeExceeded` | Serialised tx size > `maxTxSize`, or reference scripts exceed size limit |
| `executionUnitsTooLarge` | Total declared execution units exceed `maxTxExecutionUnits` |
| `referenceInputOverlapsWithInput` | A UTxO appears in both the spending and reference input sets |
| `badInput` | A spending input is not in the resolved UTxO set |
| `inputsNotSorted` | Warning — spending inputs not in canonical lexicographic order |

**Fee**

| Kind | Description |
|---|---|
| `feeTooSmall` | Fee is below the protocol minimum |
| `feeTooBig` | Warning — fee is more than 10% above minimum |

**Balance**

| Kind | Description |
|---|---|
| `valueNotConserved` | Input/output/fee/deposit/withdrawal balance equation fails |
| `missingInput` | A spending input is not in `resolvedInputs` |
| `wrongWithdrawalAmount` | Withdrawal amount doesn't match the reward account balance |
| `withdrawalNotDelegatedToDRep` | Conway reward withdrawal requires DRep delegation |
| `rewardAccountNotExisting` | Withdrawal from a non-existent reward account |
| `treasuryValueMismatch` | Treasury withdrawal amount doesn't match ledger treasury value |

**Collateral**

| Kind | Description |
|---|---|
| `noCollateralInputs` | Script transaction has no collateral inputs |
| `tooManyCollateralInputs` | Collateral count exceeds `maxCollateralInputs` |
| `insufficientCollateral` | Collateral ADA < fee × collateralPercentage |
| `incorrectTotalCollateral` | `totalCollateral` field doesn't match actual collateral − return |
| `collateralLockedByScript` | A collateral input is locked by a script |
| `collateralContainsNonAdaAssets` | Collateral inputs contain native tokens |
| `collateralUnnecessary` | Warning — collateral declared but no scripts being executed |
| `collateralReturnTooSmall` | Collateral return output is below the minimum ADA requirement |

**Script integrity**

| Kind | Description |
|---|---|
| `scriptDataHashMismatch` | `scriptDataHash` doesn't match redeemer/datum/cost-model CBOR |

**Validity interval**

| Kind | Description |
|---|---|
| `outsideValidityInterval` | `currentSlot` is outside `[validityStart, ttl)` |

**Witnesses**

| Kind | Description |
|---|---|
| `missingRequiredSigner` | A required signer has no matching vkey witness |
| `missingScript` | A script-locked input or minting policy has no script in the witness set |
| `extraneousScript` | Warning — script in witness set not required by any input/mint/cert |
| `nativeScriptFailed` | Native script multisig/timelock evaluation failed |
| `missingDatum` | PlutusV1/V2 script-locked input has no datum in witness set or inline |
| `extraneousDatum` | Warning — datum in witness set not referenced by any spending input |
| `missingRedeemer` | Plutus scripts required but no redeemers present in witness set |
| `extraneousRedeemer` | Warning — redeemers present but no Plutus scripts appear to be required |

**Signatures**

| Kind | Description |
|---|---|
| `invalidSignature` | Ed25519 signature verification failed for a vkey or bootstrap witness |
| `missingBootstrapWitness` | Byron-addressed spending input has no bootstrap witness |
| `extraneousSignature` | Warning — vkey witness not required by any input, withdrawal, or certificate |

**Output values**

| Kind | Description |
|---|---|
| `outputTooSmall` | Output is below the minimum ADA (minUTxO) requirement |
| `outputValueTooBig` | Output value serialises to more than `maxValueSize` bytes |

**Network ID**

| Kind | Description |
|---|---|
| `networkIdMismatch` | An output address or collateral return uses the wrong network |

**Registration**

| Kind | Description |
|---|---|
| `stakeAlreadyRegistered` | Stake key already registered on-chain |
| `stakeNotRegistered` | Stake key not registered (required for deregistration or delegation) |
| `stakeNonZeroAccountBalance` | Deregistration blocked by non-zero reward balance |
| `stakePoolNotRegistered` | Pool not registered (required for delegation or retirement) |
| `stakePoolCostTooLow` | Pool cost below `minPoolCost` |
| `wrongRetirementEpoch` | Pool retirement epoch outside valid range |
| `committeeIsUnknown` | Committee cold credential not known to the ledger |
| `committeeHasPreviouslyResigned` | Committee member has resigned on-chain or in this tx |
| `poolAlreadyRegistered` | Warning — pool re-registration (treated as update) |
| `drepAlreadyRegistered` | Warning — DRep already registered |
| `drepNotRegistered` | Warning — DRep not registered for update or deregistration |
| `committeeAlreadyAuthorized` | Warning — committee member already has an authorized hot key |
| `duplicateRegistrationInTx` | Warning — same entity registered more than once in this tx |
| `duplicateCommitteeColdResignationInTx` | Warning — committee cold credential resigned more than once in this tx |
| `duplicateCommitteeHotRegistrationInTx` | Warning — committee hot credential authorized more than once in this tx |

**Governance proposals (Conway)**

| Kind | Description |
|---|---|
| `proposalProcedureNetworkIdMismatch` | Proposal reward account uses wrong network |
| `proposalReturnAccountDoesNotExist` | Proposal return account not registered on-chain |
| `invalidPrevGovActionId` | Previous governance action ID not found or has wrong type |
| `zeroTreasuryWithdrawals` | Treasury withdrawal amounts sum to zero |
| `treasuryWithdrawalsNetworkIdMismatch` | Treasury withdrawal reward account uses wrong network |
| `treasuryWithdrawalReturnAccountDoesNotExist` | Treasury withdrawal account not registered |
| `conflictingCommitteeUpdate` | A credential appears in both the add and remove sets of an `UpdateCommittee` action |
| `expirationEpochTooSmall` | Committee expiration epoch ≤ current epoch |

**Voting (Conway)**

| Kind | Description |
|---|---|
| `govActionsDoNotExist` | Governance action being voted on not found in ledger state |
| `votingOnExpiredGovAction` | Governance action is expired or already enacted |
| `disallowedVoter` | Voter type not permitted for this action type per CIP-1694 |
| `voterDoesNotExist` | Voter (CC member, DRep, or SPO) not registered in ledger state |

**Phase-2 (Plutus)**

| Kind | Description |
|---|---|
| `plutusScriptFailed` | A Plutus script evaluated to `Error` |
| `executionBudgetExceeded` | Script exceeded its declared execution units budget |
| `excessiveExecutionUnits` | Warning — declared execution units far exceed the computed cost |

**Parse**

| Kind | Description |
|---|---|
| `malformedCBOR` | Input cannot be decoded as a valid Cardano transaction |
| `unknown` | Catch-all for unexpected or custom-rule errors |

---

## Architecture

```
TxValidator
├── TransactionParser          — CBOR hex → Transaction + TransactionView
├── Phase1Validator            — runs ValidationRule[] sequentially
│   ├── AuxiliaryDataRule
│   ├── TransactionLimitsRule
│   ├── FeeRule
│   ├── BalanceRule
│   ├── CollateralRule
│   ├── ScriptIntegrityRule
│   ├── ValidityIntervalRule
│   ├── RequiredSignersRule
│   ├── WitnessRule
│   ├── SignatureRule
│   ├── OutputValueRule
│   ├── NetworkIdRule
│   ├── RegistrationRule
│   ├── GovernanceProposalRule
│   └── VotingRule
└── Phase2Validator            — delegates to SwiftCardanoUPLC PhaseTwo
```

`TxValidator` is a lightweight façade. `Phase1Validator` and `Phase2Validator` are public and can be used directly if you need finer control.

---

## Generating Documentation

```bash
# Requires Swift-DocC plugin (Xcode 15+)
swift package generate-documentation \
  --target SwiftCardanoTxValidator \
  --output-path ./docs
```

Or open the package in Xcode and select **Product → Build Documentation**.

---

## Development

```bash
# Build
just build          # or: swift build

# Test
just test           # or: swift test

# Release build
just release        # or: swift build -c release
```

---

## License

[Apache 2.0](LICENSE) — © Kingpin Apps
