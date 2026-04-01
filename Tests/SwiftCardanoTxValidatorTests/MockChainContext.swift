import Foundation
import SwiftCardanoCore
import SwiftCardanoChain

/// Minimal `ChainContext` for unit tests.
///
/// Only `protocolParameters` returns a real value; all other requirements throw immediately.
/// `@unchecked Sendable` is legitimate here: every stored property is immutable and
/// the mock is only ever used in single-task test contexts.
struct MockChainContext: ChainContext, @unchecked Sendable {

    private let _protocolParams: ProtocolParameters

    init(protocolParams: ProtocolParameters) {
        _protocolParams = protocolParams
    }

    // MARK: - ChainContext identity

    var name: String { "MockChainContext" }
    var type: ContextType { .offline }
    var networkId: NetworkId { .testnet }

    // MARK: - Closures required by ChainContext

    var protocolParameters: () async throws -> ProtocolParameters {
        let pp = _protocolParams
        return { pp }
    }

    var genesisParameters: () async throws -> GenesisParameters {
        return { throw MockError.notImplemented }
    }

    var epoch: () async throws -> Int {
        return { 0 }
    }

    var era: () async throws -> Era? {
        return { .conway }
    }

    var lastBlockSlot: () async throws -> Int {
        return { 0 }
    }

    // MARK: - Stub methods

    func utxos(address: Address) async throws -> [UTxO] {
        throw MockError.notImplemented
    }

    func submitTxCBOR(cbor: Data) async throws -> String {
        throw MockError.notImplemented
    }

    func evaluateTxCBOR(cbor: Data) async throws -> [String: ExecutionUnits] {
        throw MockError.notImplemented
    }

    func stakeAddressInfo(address: Address) async throws -> [StakeAddressInfo] {
        throw MockError.notImplemented
    }

    func stakePools() async throws -> [PoolOperator] {
        throw MockError.notImplemented
    }

    func kesPeriodInfo(pool: PoolOperator?, opCert: OperationalCertificate?) async throws -> KESPeriodInfo {
        throw MockError.notImplemented
    }

    func stakePoolInfo(poolId: String) async throws -> StakePoolInfo {
        throw MockError.notImplemented
    }
}

private enum MockError: Error {
    case notImplemented
}

// MARK: - Fixture loader

/// Load `ProtocolParameters` from the test bundle resource `Resources/protocol_params.json`.
func loadProtocolParams() throws -> ProtocolParameters {
    guard let url = Bundle.module.url(
        forResource: "protocol_params",
        withExtension: "json",
        subdirectory: "Resources"
    ) else {
        throw MockError.notImplemented
    }
    return try ProtocolParameters.load(from: url.path)
}
