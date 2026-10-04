import Foundation
import SwiftCardanoCore

/// One key per stake account, pool or DRep: the hex of its credential's hash.
///
/// Certificates carry typed credentials while chain contexts name the same
/// things by bech32 reward address, pool id or DRep id, so both are brought to
/// the hash before the registration rule compares them.
enum RegistrationKey {
    static func of(_ credential: StakeCredential) -> String { credential.credential.payload.toHex }
    static func of(_ credential: DRepCredential) -> String { credential.credential.payload.toHex }
    static func of(_ pool: PoolKeyHash) -> String { pool.payload.toHex }

    /// A delegation target's key; empty for abstain and no-confidence, which
    /// are never registered.
    static func of(_ drep: DRep) -> String {
        switch drep.credential {
        case .verificationKeyHash(let hash): hash.payload.toHex
        case .scriptHash(let hash): hash.payload.toHex
        default: ""
        }
    }

    /// The key for an id from a chain context: a reward address, pool id or
    /// DRep id in bech32, a reward address in hex, or a bare hash.
    static func normalize(_ id: String) -> String {
        let text = id.trimmingCharacters(in: .whitespaces)
        if text.count == 56, text.allSatisfy(\.isHexDigit) { return text.lowercased() }
        if let address = try? Address(from: .string(text)) ?? (text.allSatisfy(\.isHexDigit) ? try? Address(from: .bytes(text.hexStringToData)) : nil) {
            switch address.stakingPart {
            case .verificationKeyHash(let hash): return hash.payload.toHex
            case .scriptHash(let hash): return hash.payload.toHex
            default: break
            }
        }
        if let pool = try? PoolOperator(from: text) { return pool.poolKeyHash.payload.toHex }
        if let drep = try? DRep.fromBech32(text) {
            let key = of(drep)
            if !key.isEmpty { return key }
        }
        // A typed value's description holds its hash.
        if let match = text.firstMatch(of: /[0-9a-fA-F]{56}/) { return String(match.output).lowercased() }
        return text
    }
}
