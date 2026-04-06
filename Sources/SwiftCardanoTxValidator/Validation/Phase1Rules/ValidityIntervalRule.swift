import Foundation
import SwiftCardanoCore

/// Checks that the transaction's validity interval contains the current slot.
///
/// - Lower bound: `transaction_body.validity_start_interval` (inclusive)
/// - Upper bound: `transaction_body.ttl` (exclusive)
///
/// Skips the check if `context.currentSlot` is not provided.
public struct ValidityIntervalRule: ValidationRule {
    public let name = "validityInterval"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        guard let currentSlot = context.currentSlot else {
            // Cannot check without the current slot — skip gracefully.
            return []
        }

        let body = transaction.transactionBody
        let start = body.validityStart.map { UInt64($0) }
        let end   = body.ttl.map { UInt64($0) }

        // Neither bound set — transaction is always valid
        if start == nil && end == nil {
            return []
        }

        var issues: [ValidationError] = []

        if let start, currentSlot < start {
            issues.append(ValidationError(
                kind: .outsideValidityInterval,
                fieldPath: "transaction_body.validity_start_interval",
                message: "Current slot \(currentSlot) is before the transaction's "
                    + "validity_start_interval \(start).",
                hint: "Wait until slot \(start) before submitting this transaction, "
                    + "or rebuild with an earlier start interval."
            ))
        }

        if let end, currentSlot >= end {
            issues.append(ValidationError(
                kind: .outsideValidityInterval,
                fieldPath: "transaction_body.ttl",
                message: "Current slot \(currentSlot) is at or after the transaction's TTL \(end). "
                    + "The transaction has expired.",
                hint: "Rebuild the transaction with a later TTL."
            ))
        }

        return issues
    }
}
