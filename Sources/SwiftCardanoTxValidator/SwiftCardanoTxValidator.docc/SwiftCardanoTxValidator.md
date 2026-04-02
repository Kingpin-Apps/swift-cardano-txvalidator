# ``SwiftCardanoTxValidator``

Parse, inspect, and validate Cardano transactions — from ledger rule checks through Plutus script execution.

## Overview

`SwiftCardanoTxValidator` provides a complete, production-grade validation pipeline for Cardano transactions, covering both Phase-1 (ledger rules) and Phase-2 (Plutus script execution via the CEK machine).

The main entry point is ``TxValidator``. Construct one, optionally supply custom rules, then call ``TxValidator/inspect(cborHex:)``, ``TxValidator/validatePhase1(cborHex:protocolParams:context:)``, or ``TxValidator/validate(cborHex:protocolParams:context:chainContext:)`` to receive a ``TxValidatorReport``.

```swift
let validator = TxValidator()

// Inspect only — no protocol params required
let view = try validator.inspect(cborHex: rawTxHex)
print(view.txId, view.fee)

// Full validation
let report = try await validator.validate(
    cborHex: rawTxHex,
    protocolParams: protocolParams,
    context: ValidationContext(
        resolvedInputs: utxos,
        currentSlot: 42_000_000,
        network: .mainnet
    ),
    chainContext: blockfrost   // nil to skip Phase-2
)

if report.isValid {
    print("Transaction is valid")
} else {
    for error in report.allErrors {
        print("[\(error.kind)] \(error.fieldPath): \(error.message)")
    }
}
```

## Topics

### Getting Started

- <doc:GettingStarted>

### Core API

- ``TxValidator``
- ``TxValidatorReport``
- ``ValidationContext``
- ``NecessaryData``

### Validation Results

- ``ValidationResult``
- ``ValidationError``

### Transaction Inspection

- ``TransactionView``
- ``OutputView``
- ``FieldView``

### Extending with Custom Rules

- <doc:CustomRules>
- ``ValidationRule``

### Built-in Phase-1 Rules

- ``AuxiliaryDataRule``
- ``TransactionLimitsRule``
- ``FeeRule``
- ``BalanceRule``
- ``CollateralRule``
- ``ScriptIntegrityRule``
- ``ValidityIntervalRule``
- ``RequiredSignersRule``
- ``WitnessRule``
- ``SignatureRule``
- ``OutputValueRule``
- ``NetworkIdRule``
- ``RegistrationRule``
- ``GovernanceProposalRule``
- ``VotingRule``

### Chain-State Context Types

- ``AccountInputContext``
- ``PoolInputContext``
- ``DRepInputContext``
- ``GovActionInputContext``
- ``CommitteeInputContext``
- ``GovActionType``
- ``TransactionInputRef``
- ``GovActionIdRef``

### Validators

- ``Phase1Validator``
- ``Phase2Validator``

### Error Reference

- <doc:ErrorReference>

### Utilities

- ``CBORUtils``
- ``TxValidatorError``
