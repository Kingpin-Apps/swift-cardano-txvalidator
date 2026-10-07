import Foundation
import SwiftCardanoCore
import SwiftNaCl

/// The size the ledger will charge a transaction for once it is signed.
///
/// The node only ever sees signed transactions, and signatures are part of
/// what it charges for: each vkey witness is about a hundred bytes. A
/// transaction checked before it is signed is checked as it will be, with a
/// witness of a real one's size for every key that must still sign, so that
/// a fee which covers the unsigned bytes but not the signed ones is caught
/// before anyone signs. Signing cannot fix it: the fee is part of what is
/// signed.
///
/// The keys counted are the ones the ledger requires: key-locked spending
/// and collateral inputs (when their UTxOs are resolved), required signers,
/// key credentials in certificates, withdrawals and votes, and the fewest
/// keys that satisfy each native script. Witnesses are written as the Conway
/// ledger writes them, a set tagged 258, unless the transaction already
/// writes its witnesses as a plain list. A transaction that is fully signed
/// is sized as written, as the node sizes it.
public struct SignedSize: Sendable, Equatable {
    /// What the ledger will charge for: ``Utils/feeRelevantSize(of:)`` of the
    /// transaction with its missing witnesses added.
    public let bytes: Int
    /// Vkey witnesses still to be added, counted in ``bytes``.
    public let missingWitnesses: Int

    public static func of(_ transaction: Transaction, context: ValidationContext) throws -> SignedSize {
        let missing = RequiredWitnesses.vkeyHashes(transaction: transaction, context: context)
            .subtracting(RequiredWitnesses.witnessed(transaction))
        guard !missing.isEmpty else {
            return SignedSize(bytes: try Utils.feeRelevantSize(of: transaction), missingWitnesses: 0)
        }
        var signed = transaction
        let existing = transaction.transactionWitnessSet.vkeyWitnesses
        let placeholders = try (0..<missing.count).map { try placeholder($0) }
        let all = (existing?.asList ?? []) + placeholders
        switch existing {
        case .list?, .indefiniteList?:
            signed.transactionWitnessSet.vkeyWitnesses = .list(all)
        default:
            signed.transactionWitnessSet.vkeyWitnesses = .nonEmptyOrderedSet(NonEmptyOrderedSet(all))
        }
        return SignedSize(bytes: try Utils.feeRelevantSize(of: signed), missingWitnesses: missing.count)
    }

    /// A vkey witness the size of a real one: a 32-byte key and a 64-byte
    /// signature, distinct for each index so a set keeps them all.
    static func placeholder(_ index: Int) throws -> VerificationKeyWitness {
        var bytes = [UInt8](repeating: 0xA5, count: 32)
        withUnsafeBytes(of: UInt64(index).bigEndian) { bytes.replaceSubrange(24..<32, with: $0) }
        return VerificationKeyWitness(
            vkey: .verificationKey(try VerificationKey(payload: Data(bytes))),
            signature: Data(repeating: 0x5A, count: 64)
        )
    }
}

/// The vkey witnesses the ledger requires of a transaction.
enum RequiredWitnesses {
    /// Key hashes (hex) that must sign `transaction`.
    static func vkeyHashes(transaction: Transaction, context: ValidationContext) -> Set<String> {
        let body = transaction.transactionBody
        var hashes = Set(body.requiredSigners?.asList.map { $0.payload.toHex } ?? [])

        let resolved = Dictionary(
            context.resolvedInputs.map { ("\($0.input.transactionId)#\($0.input.index)", $0.output) },
            uniquingKeysWith: { first, _ in first }
        )
        let spent = body.inputs.asArray + (body.collateral?.asList ?? [])
        for input in spent {
            guard let output = resolved["\(input.transactionId)#\(input.index)"],
                output.address.addressType != .byron,
                case .verificationKeyHash(let hash)? = output.address.paymentPart
            else { continue }
            hashes.insert(hash.payload.toHex)
        }
        for certificate in body.certificates?.asList ?? [] {
            collectCertificateKeyHashes(certificate, into: &hashes)
        }
        for (account, _) in body.withdrawals?.data ?? [:] where account.count == 29 && account[0] & 0x10 == 0 {
            hashes.insert(account.dropFirst().toHex)
        }
        for (voter, _, _) in body.votingProcedures?.allVotes ?? [] {
            switch voter.credential {
            case .constitutionalCommitteeHotKeyhash(let hash): hashes.insert(hash.payload.toHex)
            case .drepKeyhash(let hash): hashes.insert(hash.payload.toHex)
            case .stakePoolKeyhash(let hash): hashes.insert(hash.payload.toHex)
            case .constitutionalCommitteeHotScriptHash, .drepScriptHash: break
            }
        }
        for script in transaction.transactionWitnessSet.nativeScripts?.asList ?? [] {
            hashes.formUnion(fewestKeys(script))
        }
        return hashes
    }

    /// Key hashes (hex) the transaction's vkey witnesses sign for.
    static func witnessed(_ transaction: Transaction) -> Set<String> {
        Set((transaction.transactionWitnessSet.vkeyWitnesses?.asList ?? []).compactMap { witness in
            (try? Hash().blake2b(data: witness.vkey.payload.prefix(32), digestSize: 28, encoder: RawEncoder.self))?.toHex
        })
    }

    /// The fewest keys whose signatures satisfy `script`.
    static func fewestKeys(_ script: NativeScript) -> Set<String> {
        switch script {
        case .scriptPubkey(let key):
            return [key.keyHash.payload.toHex]
        case .scriptAll(let all):
            return all.scripts.reduce(into: Set<String>()) { $0.formUnion(fewestKeys($1)) }
        case .scriptAny(let any):
            return any.scripts.map(fewestKeys).min { $0.count < $1.count } ?? []
        case .scriptNofK(let nOfK):
            let options = nOfK.scripts.map(fewestKeys).sorted { $0.count < $1.count }
            return options.prefix(Int(nOfK.required)).reduce(into: Set<String>()) { $0.formUnion($1) }
        case .invalidBefore, .invalidHereAfter:
            return []
        }
    }
}
