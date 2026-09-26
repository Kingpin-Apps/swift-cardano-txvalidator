import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxValidator

/// Real transactions of every era from Shelley to Conway, each accepted by the
/// ledger, named by their on-chain id.
enum EraCorpus {
    struct Entry: Sendable, CustomTestStringConvertible {
        var era: Era
        var hash: String
        var network: String
        var features: [String]

        var testDescription: String { "\(era)/\(hash.prefix(12)) \(features.joined(separator: ","))" }

        func hex() throws -> String {
            try EraCorpus.read("\(era.rawValue)/\(hash).hex").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The corpus directory. Toolchains lay out a test bundle's copied
    /// `Resources` folder differently, so each place it can land is tried.
    static let directory: URL? = {
        let candidates = [
            Bundle.module.url(forResource: "tx-corpus", withExtension: nil, subdirectory: "Resources"),
            Bundle.module.url(forResource: "tx-corpus", withExtension: nil),
            Bundle.module.resourceURL?.appendingPathComponent("Resources/tx-corpus"),
            Bundle.module.resourceURL?.appendingPathComponent("tx-corpus"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    static func read(_ path: String) throws -> String {
        let url = try #require(directory, "tx-corpus not found in \(Bundle.module.bundlePath)")
        return try String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    static let entries: [Entry] = [Era.shelley, .allegra, .mary, .alonzo, .babbage, .conway].flatMap { era -> [Entry] in
        guard let manifest = try? read("\(era.rawValue)/MANIFEST.tsv") else { return [] }
        return manifest.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { return nil }
            return Entry(era: era, hash: fields[0], network: fields[1], features: fields[4].split(separator: ",").map(String.init))
        }
    }
}

@Suite("Era corpus")
struct EraCorpusTests {
    @Test func corpusIsPresent() {
        #expect(EraCorpus.directory != nil, "tx-corpus not found in \(Bundle.module.bundlePath)")
        #expect(EraCorpus.entries.count == 74)
    }

    @Test("Phase 1 raises no errors on a transaction the ledger accepted", arguments: EraCorpus.entries)
    func acceptedTransactionsPass(_ entry: EraCorpus.Entry) async throws {
        let validator = TxValidator()
        let context = ValidationContext(
            network: entry.network == "mainnet" ? .mainnet : .testnet,
            era: entry.era
        )
        let report = try await validator.validatePhase1(
            cborHex: try entry.hex(), protocolParams: try loadProtocolParams(), context: context
        )
        let errors = report.phase1Result.errors
        #expect(errors.isEmpty, "\(errors.map { "\($0.kind) @ \($0.fieldPath): \($0.message)" })")
    }
}

@Suite("Transaction era range")
struct TransactionEraRangeTests {
    @Test("Every corpus transaction's era is within its inferred range", arguments: EraCorpus.entries)
    func eraIsInRange(_ entry: EraCorpus.Entry) throws {
        let tx = try TransactionParser().parse(cborHex: try entry.hex())
        let range = tx.possibleEras
        #expect(range.contains(entry.era), "\(range)")
    }

    @Test("Features pin the range")
    func featuresPinTheRange() throws {
        func range(_ feature: String) throws -> TransactionEraRange? {
            guard let entry = EraCorpus.entries.first(where: { $0.features.contains(feature) }) else { return nil }
            return try TransactionParser().parse(cborHex: try entry.hex()).possibleEras
        }
        #expect(try range("votes")?.earliest == .conway)
        #expect(try range("reference-inputs")?.earliest ?? .conway >= .babbage)
        #expect(try range("update")?.latest ?? .shelley <= .babbage)
        #expect(try range("mint").map { $0.earliest >= .mary } ?? false)
    }

    @Test("Clamping keeps a possible era and moves an impossible one to the nearest")
    func clamping() {
        let babbageOnly = TransactionEraRange(earliest: .alonzo, latest: .babbage)
        #expect(babbageOnly.clamp(.conway) == .babbage)
        #expect(babbageOnly.clamp(.alonzo) == .alonzo)
        #expect(TransactionEraRange(earliest: .conway, latest: .conway).clamp(.babbage) == .conway)
    }

    @Test("Without an era, Phase 1 uses the latest era the transaction allows")
    func defaultEraFollowsTheTransaction() async throws {
        for entry in EraCorpus.entries where entry.era < .conway {
            let report = try await TxValidator().validatePhase1(
                cborHex: try entry.hex(), protocolParams: try loadProtocolParams(),
                context: ValidationContext(network: entry.network == "mainnet" ? .mainnet : .testnet)
            )
            #expect(report.phase1Result.errors.isEmpty, "\(entry.testDescription): \(report.phase1Result.errors.map(\.kind))")
        }
    }
}

@Suite("Era from the chain, clamped to the transaction")
struct ChainEraClampTests {
    @Test("An older transaction keeps its era; a current one gets the chain's", arguments: EraCorpus.entries.filter { [.mary, .babbage, .conway].contains($0.era) }.prefix(12))
    func clampedToTransaction(_ entry: EraCorpus.Entry) async throws {
        let tx = try TransactionParser().parse(cborHex: try entry.hex())
        let context = try await ValidationContext.from(
            transaction: tx, chainContext: MockChainContext(protocolParams: try loadProtocolParams())
        )
        let tipEra = try await MockChainContext(protocolParams: try loadProtocolParams()).era() ?? .conway
        let era = try #require(context.era)
        #expect(tx.possibleEras.contains(era))
        #expect(era == tx.possibleEras.clamp(tipEra))
    }
}
