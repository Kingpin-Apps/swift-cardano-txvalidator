# Custom Validation Rules

Extend the Phase-1 rule set with your own application-specific checks.

## Overview

Every built-in Phase-1 rule conforms to ``ValidationRule``. You can implement the same protocol to add checks that the standard ledger rules don't cover — for example, policy-specific token minting constraints, address allow-listing, or metadata requirements.

Custom rules are passed to ``TxValidator`` at initialisation and run alongside the built-in rules in every ``TxValidator/validatePhase1(cborHex:protocolParams:context:)`` and ``TxValidator/validate(cborHex:protocolParams:context:chainContext:)`` call.

## Implementing `ValidationRule`

The protocol has two requirements:

```swift
public protocol ValidationRule: Sendable {
    var name: String { get }

    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError]
}
```

- **`name`** — identifies the rule in error reports and log output. Use a short, unique string.
- **`validate(...)`** — return an empty array for a passing rule, or one or more ``ValidationError`` values for failures. Throw only for unexpected internal errors, not for validation failures.
- **`Sendable`** — required because rules may be evaluated across task boundaries. Use value types (`struct`) or ensure your reference type is safe for concurrent access.

### Example — require a specific metadata label

```swift
import SwiftCardanoCore
import SwiftCardanoTxValidator

struct MetadataLabelRule: ValidationRule {
    var name: String { "MetadataLabelRule" }

    let requiredLabel: UInt64

    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        guard let metadata = transaction.auxiliaryData?.metadata else {
            return [ValidationError(
                kind: .unknown,
                fieldPath: "auxiliary_data.metadata",
                message: "Transaction must carry auxiliary metadata",
                hint: "Add a metadata map with label \(requiredLabel)"
            )]
        }

        guard metadata[requiredLabel] != nil else {
            return [ValidationError(
                kind: .unknown,
                fieldPath: "auxiliary_data.metadata[\(requiredLabel)]",
                message: "Required metadata label \(requiredLabel) is missing"
            )]
        }

        return []
    }
}
```

### Example — restrict minting to a known policy

```swift
struct AllowedPolicyRule: ValidationRule {
    var name: String { "AllowedPolicyRule" }

    let allowedPolicies: Set<String>

    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        guard let mint = transaction.transactionBody.mint else {
            return []   // No minting — rule passes
        }

        var errors: [ValidationError] = []

        for (policyId, _) in mint.data {
            let policyHex = "\(policyId)"
            if !allowedPolicies.contains(policyHex) {
                errors.append(ValidationError(
                    kind: .unknown,
                    fieldPath: "transaction_body.mint",
                    message: "Policy \(policyHex) is not in the allowed policy list",
                    hint: "Only policies \(allowedPolicies.joined(separator: ", ")) may be minted"
                ))
            }
        }

        return errors
    }
}
```

### Example — warn when fee is over a budget threshold

```swift
struct FeeBudgetRule: ValidationRule {
    var name: String { "FeeBudgetRule" }

    let maxAcceptableFee: UInt64

    func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        let fee = transaction.transactionBody.fee
        guard fee > maxAcceptableFee else { return [] }

        return [ValidationError(
            kind: .feeTooBig,
            fieldPath: "transaction_body.fee",
            message: "Fee \(fee) lovelace exceeds budget of \(maxAcceptableFee) lovelace",
            hint: "Reduce the number of inputs or simplify the script to lower execution units",
            isWarning: true   // This is advisory, not a hard rejection
        )]
    }
}
```

## Registering Custom Rules

Pass your rules in the ``TxValidator`` initialiser. They are appended **after** the default rule set and run in the order supplied:

```swift
let validator = TxValidator(
    additionalRules: [
        MetadataLabelRule(requiredLabel: 674),
        AllowedPolicyRule(allowedPolicies: ["abc123...", "def456..."]),
        FeeBudgetRule(maxAcceptableFee: 2_000_000),
    ]
)

let report = try await validator.validatePhase1(
    cborHex: rawTxHex,
    protocolParams: protocolParams,
    context: context
)
```

## Using `ValidationContext` in Custom Rules

``ValidationContext`` exposes the resolved UTxOs, the current slot, and the expected network. Use its optional fields defensively — skip checks when data is unavailable, just as the built-in rules do:

```swift
func validate(
    transaction: Transaction,
    context: ValidationContext,
    protocolParams: ProtocolParameters
) throws -> [ValidationError] {
    // Only check if we have resolved inputs
    guard !context.resolvedInputs.isEmpty else { return [] }

    // ... inspect context.resolvedInputs ...
}
```

## Choosing `kind` for Custom Errors

Use ``ValidationError/Kind/unknown`` for application-specific checks that don't map to a standard ledger error. If your check is a specialisation of an existing error (e.g., a fee budget check), you may reuse the closest existing kind (e.g., ``ValidationError/Kind/feeTooBig``) so tooling that inspects error kinds can handle it consistently.

## Testing Custom Rules

Rules are pure synchronous functions and are easy to unit-test without a full `TxValidator`:

```swift
import Testing
import SwiftCardanoTxValidator

@Test("MetadataLabelRule passes when label 674 present")
func metadataRulePasses() throws {
    let rule = MetadataLabelRule(requiredLabel: 674)
    let tx = buildTestTransactionWithMetadata(label: 674)
    let errors = try rule.validate(
        transaction: tx,
        context: ValidationContext(),
        protocolParams: testProtocolParams
    )
    #expect(errors.isEmpty)
}
```
