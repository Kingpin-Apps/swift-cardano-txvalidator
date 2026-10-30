import Foundation
import SwiftCardanoCore

/// Reports each chain-state lookup that failed while the
/// ``ValidationContext`` was built, so that a check reporting something as
/// absent can be told apart from one whose data could not be read.
public struct ChainLookupRule: ValidationRule {
    public let name = "chainLookup"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {
        context.lookupFailures.map { failure in
            ValidationError(
                kind: .chainLookupFailed,
                fieldPath: "context",
                message: "Chain lookup failed: \(failure). Checks that depend on it may report it as absent.",
                hint: "Retry once the chain backend is reachable.",
                isWarning: true
            )
        }
    }
}
