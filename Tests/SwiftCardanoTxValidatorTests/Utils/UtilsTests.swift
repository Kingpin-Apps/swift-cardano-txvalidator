import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoTxValidator

@Suite("Utils")
struct UtilsTests {

    // MARK: - blake2b256

    @Test("blake2b256 of empty data matches known vector")
    func blake2b256EmptyVector() throws {
        let result = try Utils.blake2b256(Data())
        let hex = result.toHex
        // Blake2b-256 of empty input (RFC 7693 / BLAKE2 reference)
        #expect(hex == "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8")
    }

    @Test("blake2b256 of 'abc' matches known vector")
    func blake2b256KnownVector() throws {
        let input = Data("abc".utf8)
        let result = try Utils.blake2b256(input)
        let hex = result.toHex
        // Blake2b-256 of "abc" (well-known reference value)
        #expect(hex == "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319")
    }

    @Test("blake2b256 produces 32-byte output")
    func blake2b256OutputLength() throws {
        let result = try Utils.blake2b256(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(result.count == 32)
    }

    @Test("blake2b256 is deterministic")
    func blake2b256Deterministic() throws {
        let input = Data("Cardano".utf8)
        let result1 = try Utils.blake2b256(input)
        let result2 = try Utils.blake2b256(input)
        #expect(result1 == result2)
    }

    // MARK: - languageViewsCostModels

    @Test("languageViewsCostModels returns empty map when no Plutus scripts are present")
    func languageViewsEmptyWhenNoScripts() throws {
        let params = try loadProtocolParams()
        let witnessSet = TransactionWitnessSet(
            redeemers: .list([sampleRedeemer(index: 0)])
        )

        let models = try Utils.languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: params
        )

        #expect(models.isEmpty)
    }

    @Test("languageViewsCostModels includes only used Plutus versions")
    func languageViewsIncludesOnlyUsedVersions() throws {
        let params = try loadProtocolParams()
        let witnessSet = TransactionWitnessSet(
            plutusV1Script: .list([PlutusV1Script(data: Data([0x01]))]),
            plutusV3Script: .list([PlutusV3Script(data: Data([0x03]))])
        )

        let models = try Utils.languageViewsCostModels(
            witnessSet: witnessSet,
            protocolParams: params
        )

        #expect(models[0] == params.costModels.getVersion(1))
        #expect(models[2] == params.costModels.getVersion(3))
        #expect(models[1] == nil)
        #expect(models.count == 2)
    }

    // MARK: - scriptDataHash

    @Test("scriptDataHash is deterministic for the same witness and protocol params")
    func scriptDataHashDeterministic() throws {
        let params = try loadProtocolParams()
        let witnessSet = makeWitnessSetWithV2ScriptAndDatum()

        let first = try Utils.scriptDataHash(
            witnessSet: witnessSet,
            protocolParams: params
        )
        let second = try Utils.scriptDataHash(
            witnessSet: witnessSet,
            protocolParams: params
        )

        #expect(first == second)
    }

    @Test("scriptDataHash changes when datum changes")
    func scriptDataHashChangesWhenDatumChanges() throws {
        let params = try loadProtocolParams()

        let baseWitness = makeWitnessSetWithV2ScriptAndDatum(datumValue: 42)
        let changedDatumWitness = makeWitnessSetWithV2ScriptAndDatum(datumValue: 43)

        let baseHash = try Utils.scriptDataHash(
            witnessSet: baseWitness,
            protocolParams: params
        )
        let changedHash = try Utils.scriptDataHash(
            witnessSet: changedDatumWitness,
            protocolParams: params
        )

        #expect(baseHash != changedHash)
    }

    @Test("scriptDataHash changes when used script language changes")
    func scriptDataHashChangesAcrossScriptLanguages() throws {
        let params = try loadProtocolParams()

        let redeemer = sampleRedeemer(index: 0)
        let datum = PlutusData.bigInt(.int(42))

        let v1Witnesses = TransactionWitnessSet(
            plutusV1Script: .list([PlutusV1Script(data: Data([0x01]))]),
            plutusData: .list([datum]),
            redeemers: .list([redeemer])
        )

        let v2Witnesses = TransactionWitnessSet(
            plutusV2Script: .list([PlutusV2Script(data: Data([0x02]))]),
            plutusData: .list([datum]),
            redeemers: .list([redeemer])
        )

        let v1Hash = try Utils.scriptDataHash(
            witnessSet: v1Witnesses,
            protocolParams: params
        )
        let v2Hash = try Utils.scriptDataHash(
            witnessSet: v2Witnesses,
            protocolParams: params
        )

        #expect(v1Hash != v2Hash)
    }

    // MARK: - Helpers

    private func makeWitnessSetWithV2ScriptAndDatum(datumValue: Int = 42) -> TransactionWitnessSet {
        TransactionWitnessSet(
            plutusV2Script: .list([PlutusV2Script(data: Data([0x02]))]),
            plutusData: .list([PlutusData.bigInt(.int(Int64(datumValue)))]),
            redeemers: .list([sampleRedeemer(index: 0)])
        )
    }

    private func sampleRedeemer(index: UInt64) -> Redeemer {
        Redeemer(
            tag: .spend,
            index: Int(index),
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 1_000_000, steps: 1_000_000)
        )
    }
}

/// The size the ledger charges for: the bytes as written, less the validity flag.
@Suite("Fee-relevant size")
struct FeeRelevantSizeTests {
    @Test("A transaction is sized from its written bytes, without the validity flag, however its parts are encoded")
    func writtenBytes() throws {
        // Body with a tagged certificate set, witnesses as a tagged set: as cardano-cli writes them.
        let hex = "84a400d901028182582077d8cd0fcfff03416252650f726791626582ae6f57c58edda269bdefd274758e0001818258390157330328870a37311d9ca0f064ac870d9a75ae436111952f999248e75a15bb387f2c67792f3143439854a4bb8cefb1259e230550b02f1b2e1a005358fd021a00029e0904d901028183078200581cc6faa2b3aefd8d833901921bb17eaa4655ad05ae7fa18506b9c4215f1a001e8480a100d901028282582000000000000000000000000000000000000000000000000000000000000000015840000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018258200000000000000000000000000000000000000000000000000000000000000002584000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f5f6"
        let bytes = Data(hex: hex)
        let transaction = try Transaction.fromCBOR(data: bytes)
        #expect(bytes.count == 370)
        #expect(try Utils.feeRelevantSize(of: transaction) == 369)
        // Dropping the witnesses re-encodes that part alone; the body keeps its bytes.
        var unsigned = transaction
        unsigned.transactionWitnessSet = TransactionWitnessSet()
        #expect(try Utils.feeRelevantSize(of: unsigned) == 369 - 208 + 1)
    }
}
