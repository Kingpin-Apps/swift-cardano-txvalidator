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

    // MARK: - Methods required by ChainContext

    func protocolParameters() async throws -> ProtocolParameters {
        _protocolParams
    }

    func genesisParameters() async throws -> GenesisParameters {
        throw MockError.notImplemented
    }

    func epoch() async throws -> Int {
        0
    }

    func era() async throws -> Era? {
        .conway
    }

    func lastBlockSlot() async throws -> Int {
        0
    }

    func chainTip() async throws -> ChainTip {
        throw MockError.notImplemented
    }

    // MARK: - Stub methods

    func utxos(address: Address) async throws -> [UTxO] {
        throw MockError.notImplemented
    }

    func utxo(input: TransactionInput) async throws -> (UTxO, isSpent: Bool)? {
        // nil = "UTxO not found", the behavior of cli/Ogmios-style backends that only
        // return unspent UTxOs. Lets `ValidationContext.from` resolve to an empty input set
        // rather than failing.
        nil
    }

    func submitTxCBOR(cbor: Data) async throws -> String {
        throw MockError.notImplemented
    }

    func evaluateTx(tx: Transaction) async throws -> [String: ExecutionUnits] {
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
    func treasury() async throws -> SwiftCardanoCore.Coin {
        throw MockError.notImplemented
    }
    
    func drepInfo(drep: SwiftCardanoCore.DRep) async throws -> SwiftCardanoChain.DRepInfo {
        throw MockError.notImplemented
    }
    
    func govActionInfo(govActionID: SwiftCardanoCore.GovActionID) async throws -> SwiftCardanoChain.GovActionInfo {
        throw MockError.notImplemented
    }
    
    func committeeMemberInfo(cold: SwiftCardanoCore.CommitteeColdCredential) async throws -> SwiftCardanoChain.CommitteeMemberInfo {
        throw MockError.notImplemented
    }

    func committeeMemberInfo(hot: SwiftCardanoCore.CommitteeHotCredential) async throws -> SwiftCardanoChain.CommitteeMemberInfo {
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
