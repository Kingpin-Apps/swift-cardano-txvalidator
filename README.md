# SwiftCardanoTxValidator

A Swift package for parsing, inspecting, and validating Cardano transactions — covering both **Phase-1** (ledger rule checks) and **Phase-2** (Plutus script execution via the CEK machine).

Part of the [Kingpin-Apps](https://github.com/Kingpin-Apps) Swift Cardano ecosystem.

---

## Features

- **Transaction parsing** — decode any raw CBOR hex into a structured, human-readable view
- **Phase-1 validation** — 8 built-in ledger rules (fee, balance, collateral, script integrity, validity interval, required signers, output value, network ID)
- **Phase-2 validation** — Plutus V1/V2/V3 script execution via `SwiftCardanoUPLC`
- **Custom rules** — extend the rule set by conforming to `ValidationRule`
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
| `FeeRule` | `fee ≥ txFeeFixed + txFeePerByte × tx_size` (warns if >10% over minimum) |
| `BalanceRule` | `Σ(inputs) + Σ(withdrawals) + Σ(refunds) = Σ(outputs) + fee + Σ(deposits) + donation` |
| `CollateralRule` | Collateral presence, count ≤ max, ADA ≥ fee × collateralPercentage, no script-locked collateral |
| `ScriptIntegrityRule` | `scriptDataHash = Blake2b256(redeemers ‖ datums ‖ language_views)` |
| `ValidityIntervalRule` | `validityStart ≤ currentSlot < ttl` |
| `RequiredSignersRule` | Every required signer key hash has a matching vkey witness |
| `OutputValueRule` | Each output carries `minAda = utxoCostPerByte × (160 + size)` |
| `NetworkIdRule` | All output addresses (including collateral return) match expected network |

### Graceful degradation

Rules that need resolved inputs, the current slot, or a chain context skip their checks rather than failing if that data is absent from `ValidationContext`. This lets you run partial validation during transaction construction.

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

**Phase-1**

| Kind | Description |
|---|---|
| `feeTooSmall` | Fee is below the protocol minimum |
| `feeTooBig` | Warning — fee is more than 10% above minimum |
| `valueNotConserved` | Input/output/fee balance equation fails |
| `missingInput` | A spending input is not in `resolvedInputs` |
| `noCollateralInputs` | Script transaction has no collateral inputs |
| `tooManyCollateralInputs` | Collateral count exceeds `maxCollateralInputs` |
| `insufficientCollateral` | Collateral ADA < fee × collateralPercentage |
| `incorrectTotalCollateral` | `totalCollateral` field doesn't match actual collateral − return |
| `collateralLockedByScript` | A collateral input is locked by a script |
| `collateralContainsNonAdaAssets` | Collateral inputs contain native tokens |
| `scriptDataHashMismatch` | `scriptDataHash` doesn't match redeemer/datum/cost-model CBOR |
| `outsideValidityInterval` | `currentSlot` is outside `[validityStart, ttl)` |
| `missingRequiredSigner` | A required signer has no matching vkey witness |
| `outputTooSmall` | Output is below the minimum ADA requirement |
| `outputValueTooBig` | Output value exceeds `maxValueSize` bytes |
| `networkIdMismatch` | An address uses a different network than expected |

**Phase-2**

| Kind | Description |
|---|---|
| `plutusScriptFailed` | A Plutus script evaluated to `Error` |
| `missingRedeemer` | A script input has no matching redeemer |
| `missingDatum` | A script input's datum cannot be resolved |
| `missingScript` | A redeemer references a script not in the witness set |
| `executionBudgetExceeded` | Script exceeded its execution units budget |

---

## Architecture

```
TxValidator
├── TransactionParser          — CBOR hex → Transaction + TransactionView
├── Phase1Validator            — runs ValidationRule[] sequentially
│   ├── FeeRule
│   ├── BalanceRule
│   ├── CollateralRule
│   ├── ScriptIntegrityRule
│   ├── ValidityIntervalRule
│   ├── RequiredSignersRule
│   ├── OutputValueRule
│   └── NetworkIdRule
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
