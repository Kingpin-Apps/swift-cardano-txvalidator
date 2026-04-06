import Foundation
import SwiftCardanoCore

/// Verifies that every output address's network ID matches the network ID declared
/// in `transaction_body.network_id` (or the context network if the body omits it).
public struct NetworkIdRule: ValidationRule {
    public let name = "networkId"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody

        // Determine the expected network ID:
        // 1. From the transaction body field, if present
        // 2. From the validation context network, if provided
        // 3. Inferred from the first output address
        let expectedNetworkId: NetworkId?

        if let bodyNetworkId = body.networkId {
            expectedNetworkId = bodyNetworkId == 1 ? .mainnet : .testnet
        } else if let contextNetwork = context.network {
            expectedNetworkId = contextNetwork
        } else if let firstOutput = body.outputs.first {
            expectedNetworkId = firstOutput.address.network
        } else {
            return []  // Nothing to check
        }

        guard let expected = expectedNetworkId else { return [] }

        var issues: [ValidationError] = []

        // Check body networkId declaration matches expected
        if let bodyNetworkInt = body.networkId {
            let bodyNetwork: NetworkId = bodyNetworkInt == 1 ? .mainnet : .testnet
            if bodyNetwork != expected {
                issues.append(ValidationError(
                    kind: .networkIdMismatch,
                    fieldPath: "transaction_body.network_id",
                    message: "Declared network_id \(bodyNetworkInt) does not match "
                        + "the expected network \(expected).",
                    hint: "Set transaction_body.network_id to match the target network."
                ))
            }
        }

        // Check each output address
        for (i, output) in body.outputs.enumerated() {
            let addrNetwork = output.address.network
            if addrNetwork != expected {
                issues.append(ValidationError(
                    kind: .networkIdMismatch,
                    fieldPath: "transaction_body.outputs[\(i)].address",
                    message: "Output[\(i)] address has network \(addrNetwork) "
                        + "but the transaction targets \(expected).",
                    hint: "Use the correct address for the \(expected) network."
                ))
            }
        }

        // Check collateral return address
        if let ret = body.collateralReturn {
            if ret.address.network != expected {
                issues.append(ValidationError(
                    kind: .networkIdMismatch,
                    fieldPath: "transaction_body.collateral_return.address",
                    message: "Collateral return address has network \(ret.address.network) "
                        + "but the transaction targets \(expected).",
                    hint: "Use a \(expected) address for the collateral return output."
                ))
            }
        }

        return issues
    }
}
