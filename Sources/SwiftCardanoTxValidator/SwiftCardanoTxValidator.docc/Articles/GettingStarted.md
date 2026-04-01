# Getting Started

Set up SwiftCardanoTxValidator and run your first validation in minutes.

## Overview

`SwiftCardanoTxValidator` is structured around a single entry point — ``TxValidator`` — which handles parsing, Phase-1 ledger rule checks, and Phase-2 Plutus script execution. This article walks through each layer from basic inspection through full two-phase validation.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(
    url: "https://github.com/Kingpin-Apps/swift-cardano-txvalidator.git",
    from: "1.0.0"
)
```

Then add `SwiftCardanoTxValidator` to your target:

```swift
.product(name: "SwiftCardanoTxValidator", package: "swift-cardano-txvalidator")
```

## Step 1 — Inspect a Transaction

Parsing a transaction requires only its raw CBOR hex. No protocol parameters or live node connection are needed:

```swift
import SwiftCardanoTxValidator

let validator = TxValidator()

let view = try validator.inspect(cborHex: rawTxHex)

print(view.txId)               // "a3b4c5..."
print(view.fee)                // 180481
print(view.inputs)             // ["abc123#0", "def456#1"]
print(view.hasPlutusScripts)   // true / false
print(view.redeemerCount)      // 2
```

The returned ``TransactionView`` is `Codable`, so you can also serialise it directly:

```swift
let json = try JSONEncoder().encode(view)
```

For a flat list of every field in dot-notation, use ``TxValidator/fields(cborHex:)``:

```swift
let fields = try validator.fields(cborHex: rawTxHex)
for field in fields {
    print("\(field.path): \(field.value)")
}
// transaction_body.fee: 180481
// transaction_body.inputs[0]: abc123#0
// ...
```

## Step 2 — Phase-1 Validation (Ledger Rules)

Phase-1 validates the transaction's structural correctness against the Cardano ledger rules. You need current ``ProtocolParameters``, and optionally a ``ValidationContext`` carrying resolved UTxOs, the current slot, and the expected network.

```swift
import SwiftCardanoCore

// Build context from whatever data you have available.
// All fields are optional — rules skip checks they cannot perform without them.
let context = ValidationContext(
    resolvedInputs: myUTxOs,      // [UTxO] — the inputs being spent
    currentSlot: 42_000_000,      // UInt64 — required for validity interval checks
    network: .mainnet             // NetworkId — required for address network checks
)

let report = try await validator.validatePhase1(
    cborHex: rawTxHex,
    protocolParams: protocolParams,
    context: context
)

print(report.isValid)            // true / false
print(report.allErrors.count)    // number of hard errors
print(report.allWarnings.count)  // number of warnings (e.g. fee too high)
```

### Interpreting the result

``TxValidatorReport`` separates hard errors from warnings:

```swift
for error in report.allErrors {
    // Hard errors — transaction will be rejected by the node
    print("ERROR [\(error.kind.rawValue)]")
    print("  Path   : \(error.fieldPath)")
    print("  Message: \(error.message)")
    if let hint = error.hint {
        print("  Hint   : \(hint)")
    }
}

for warning in report.allWarnings {
    // Warnings — transaction will be accepted but something looks unusual
    print("WARNING [\(warning.kind.rawValue)]: \(warning.message)")
}
```

### Partial validation

If you don't have resolved UTxOs or the current slot, you can still run validation — rules that need those values skip gracefully:

```swift
// No resolved inputs: BalanceRule and CollateralRule will skip their checks
let report = try await validator.validatePhase1(
    cborHex: rawTxHex,
    protocolParams: protocolParams
    // context defaults to ValidationContext() — all fields nil/empty
)
```

## Step 3 — Phase-2 Validation (Plutus Scripts)

To run Plutus scripts, provide a `ChainContext` (from `SwiftCardanoChain`). The chain context is used to fetch protocol parameters and evaluate execution units via the CEK machine:

```swift
import SwiftCardanoChain

let blockfrost = BlockFrostChainContext(projectId: "mainnetXXX...")
let protocolParams = try await blockfrost.protocolParameters()()

let report = try await validator.validate(
    cborHex: rawTxHex,
    protocolParams: protocolParams,
    context: ValidationContext(
        resolvedInputs: utxos,
        currentSlot: currentSlot,
        network: .mainnet
    ),
    chainContext: blockfrost
)
```

Phase-2 runs after Phase-1. If Phase-1 finds hard errors, Phase-2 still runs independently.

> Note: Pass `chainContext: nil` (or use ``TxValidator/validatePhase1(cborHex:protocolParams:context:)`` directly) to skip Phase-2 entirely.

## Step 4 — Export to JSON

The full report is `Codable`. Use ``TxValidatorReport/toJSON()`` for pretty-printed output suitable for logging or API responses:

```swift
let json = try report.toJSON()
print(json)
// {
//   "transactionView": {
//     "txId": "a3b4c5...",
//     "fee": 180481,
//     "inputs": ["abc123#0"],
//     ...
//   },
//   "phase1Result": {
//     "status": "valid",
//     "issues": []
//   },
//   "phase2Result": {
//     "status": "invalid",
//     "issues": [
//       {
//         "kind": "plutusScriptFailed",
//         "fieldPath": "transaction_witness_set.redeemers[0]",
//         "message": "Script evaluation failed",
//         "isWarning": false
//       }
//     ]
//   }
// }
```

## Next Steps

- <doc:CustomRules> — add your own validation logic
- <doc:ErrorReference> — full catalogue of error kinds and their meanings
