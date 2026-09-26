import Foundation
import SwiftCardanoCore

/// The eras a transaction could have been written for, read off its structure.
///
/// A transaction does not name its era, but what it contains bounds it: a
/// reference input cannot come before Babbage, a vote before Conway; a
/// protocol-parameter update or a MIR certificate cannot come after Babbage,
/// and the three-element Shelley shape cannot come after Mary. Validating a
/// transaction under an era outside its range applies rules it was never
/// subject to — Conway certificate rules to a 2023 Babbage transaction, say.
public struct TransactionEraRange: Sendable, Hashable, CustomStringConvertible {
    /// The earliest era the transaction's contents allow.
    public let earliest: Era
    /// The latest era the transaction's contents allow.
    public let latest: Era

    public init(earliest: Era, latest: Era) {
        self.earliest = earliest
        self.latest = max(earliest, latest)
    }

    /// Whether the transaction could belong to `era`.
    public func contains(_ era: Era) -> Bool { earliest <= era && era <= latest }

    /// `era` when the transaction could belong to it, otherwise the nearest
    /// era it could belong to.
    public func clamp(_ era: Era) -> Era { min(max(era, earliest), latest) }

    public var description: String { earliest == latest ? "\(earliest)" : "\(earliest)…\(latest)" }
}

extension Transaction {
    /// The eras this transaction could have been written for.
    public var possibleEras: TransactionEraRange {
        let body = transactionBody
        let witnesses = transactionWitnessSet

        if isPreAlonzo {
            var earliest = Era.shelley
            if body.validityStart != nil { earliest = max(earliest, .allegra) }
            if case .shelleyMaryMetadata? = auxiliaryData?.data { earliest = max(earliest, .allegra) }
            if body.mint != nil || body.outputs.contains(where: { !$0.amount.multiAsset.data.isEmpty }) {
                earliest = max(earliest, .mary)
            }
            return TransactionEraRange(earliest: earliest, latest: .mary)
        }

        var earliest = Era.alonzo
        var latest = Era.conway

        // Babbage introduced reference inputs, collateral return and total
        // collateral, the map-shaped output with inline datums and reference
        // scripts, and Plutus V2.
        let outputs = body.outputs + (body.collateralReturn.map { [$0] } ?? [])
        if body.referenceInputs != nil || body.collateralReturn != nil || body.totalCollateral != nil
            || outputs.contains(where: { $0.postAlonzo || $0.datumOption != nil || $0.script != nil })
            || witnesses.plutusV2Script != nil
        {
            earliest = .babbage
        }

        // Conway introduced governance, treasury fields, Plutus V3, the new
        // certificates, map-shaped redeemers and `#6.258` sets.
        let conwayCertificate = body.certificates?.asList.contains { certificate in
            switch certificate {
            case .stakeRegistration, .stakeDeregistration, .stakeDelegation, .poolRegistration,
                .poolRetirement, .genesisKeyDelegation, .moveInstantaneousRewards:
                return false
            default:
                return true
            }
        } ?? false
        var redeemersAsMap = false
        if case .map? = witnesses.redeemers { redeemersAsMap = true }
        var taggedInputs = false
        if case .orderedSet = body.inputs { taggedInputs = true }
        if case .indefiniteOrderedSet = body.inputs { taggedInputs = true }
        if body.votingProcedures != nil || body.proposalProcedures != nil
            || body.currentTreasuryAmount != nil || body.treasuryDonation != nil
            || witnesses.plutusV3Script != nil || conwayCertificate || redeemersAsMap || taggedInputs
        {
            earliest = .conway
        }

        // Conway removed protocol-parameter updates, genesis delegation and MIR.
        let retiredCertificate = body.certificates?.asList.contains { certificate in
            switch certificate {
            case .genesisKeyDelegation, .moveInstantaneousRewards: return true
            default: return false
            }
        } ?? false
        if body.update != nil || retiredCertificate {
            latest = .babbage
        }

        return TransactionEraRange(earliest: earliest, latest: latest)
    }
}
