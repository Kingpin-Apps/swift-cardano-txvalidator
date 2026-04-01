import Testing
import Foundation
import BigInt
import SwiftCardanoCore
import SwiftCardanoChain
import SwiftCardanoUPLC
@testable import SwiftCardanoTxValidator

// MARK: - Phase-2 Validator Tests

@Suite("Phase2Validator")
struct Phase2ValidatorTests {

    // MARK: - Smoke tests (no ChainContext required)

    @Test("Phase2Validator initialises without arguments")
    func initialises() {
        let validator = Phase2Validator()
        _ = validator  // existence check
    }

    @Test("ValidationError.plutusScriptFailed has correct kind")
    func plutusScriptFailedKind() {
        let err = ValidationError(
            kind: .plutusScriptFailed,
            fieldPath: "transaction_witness_set.redeemers[0]",
            message: "Script execution failed: expected True, got False",
            hint: "Check the redeemer and datum values."
        )
        #expect(err.kind == .plutusScriptFailed)
        #expect(!err.isWarning)
        #expect(err.fieldPath.contains("redeemers[0]"))
    }

    @Test("ValidationError kinds for all Phase-2 error cases")
    func allPhase2ErrorKinds() {
        let kinds: [ValidationError.Kind] = [
            .plutusScriptFailed,
            .missingRedeemer,
            .missingDatum,
            .missingScript,
            .extraneousRedeemer,
            .executionBudgetExceeded,
        ]
        for kind in kinds {
            let err = ValidationError(kind: kind, fieldPath: "test", message: "test")
            #expect(err.kind == kind)
        }
    }

    // MARK: - Integration tests

    @Test("Phase2 skipped when no redeemers present")
    func phase2SkippedNoRedeemers() async throws {
        let pp = try loadProtocolParams()
        let ctx = MockChainContext(protocolParams: pp)

        // Build a minimal transaction with no redeemers
        let txId = TransactionId(payload: Data(repeating: 0xAA, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let addr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x01, count: 28))
            ),
            network: .testnet
        )
        let output = TransactionOutput(
            address: addr,
            amount: Value(coin: 2_000_000),
            postAlonzo: true
        )
        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [output],
            fee: 200_000
        )
        let witnessSet = TransactionWitnessSet()
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let validator = Phase2Validator()
        let outcome = try await validator.evaluate(
            transaction: tx,
            resolvedInputs: [],
            chainContext: ctx
        )
        #expect(outcome.result.isValid)
    }

    @Test("Phase2 passes for always-succeeds PlutusV2 script")
    func phase2PassingScript() async throws {
        let pp = try loadProtocolParams()
        let ctx = MockChainContext(protocolParams: pp)

        // Build the "always succeeds" PlutusV2 script: (lam _ (lam _ (lam _ (con unit ()))))
        let scriptData = try makePlutusV2ScriptData(
            program: DeBruijnProgram(
                version: (1, 1, 0),
                term: .lambda(
                    parameterName: DeBruijn(0),
                    body: .lambda(
                        parameterName: DeBruijn(0),
                        body: .lambda(
                            parameterName: DeBruijn(0),
                            body: .constant(.unit)
                        )
                    )
                )
            )
        )
        let script = PlutusV2Script(data: scriptData)
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(script))

        // Build script-locked address
        let scriptAddr = try Address(
            paymentPart: .scriptHash(scriptHash),
            network: .testnet
        )

        // Build UTxO at that address with inline datum
        let datum = PlutusData.bigInt(.int(42))
        let datumOption = DatumOption(datum: datum)
        let txId = TransactionId(payload: Data(repeating: 0xBB, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000),
            datumOption: datumOption,
            postAlonzo: true
        )
        let utxo = UTxO(input: input, output: utxoOutput)

        // Build redeemer (spend index 0)
        let redeemer = Redeemer(
            tag: .spend,
            index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 14_000_000, steps: 10_000_000_000)
        )

        // Build a change output so we have at least one output
        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x02, count: 28))
            ),
            network: .testnet
        )
        let changeOutput = TransactionOutput(
            address: changeAddr,
            amount: Value(coin: 1_500_000),
            postAlonzo: true
        )

        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [changeOutput],
            fee: 200_000,
            collateral: .list([
                TransactionInput(
                    transactionId: TransactionId(payload: Data(repeating: 0xCC, count: 32)),
                    index: 0
                )
            ])
        )
        let witnessSet = TransactionWitnessSet(
            plutusV2Script: .list([script]),
            redeemers: .list([redeemer])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let validator = Phase2Validator()
        let outcome = try await validator.evaluate(
            transaction: tx,
            resolvedInputs: [utxo],
            chainContext: ctx
        )
        // Script passed — no hard errors. A warning may fire if declared ex-units
        // greatly exceed calculated units (the test declares max budget intentionally).
        #expect(outcome.result.errors.isEmpty)
        #expect(outcome.redeemerEvalResults.count == 1)
        #expect(outcome.redeemerEvalResults[0].passed)
    }

    @Test("Phase2 reports error for always-fails PlutusV2 script")
    func phase2FailingScript() async throws {
        let pp = try loadProtocolParams()
        let ctx = MockChainContext(protocolParams: pp)

        // Build the "always fails" PlutusV2 script: (lam _ (lam _ (lam _ error)))
        let scriptData = try makePlutusV2ScriptData(
            program: DeBruijnProgram(
                version: (1, 1, 0),
                term: .lambda(
                    parameterName: DeBruijn(0),
                    body: .lambda(
                        parameterName: DeBruijn(0),
                        body: .lambda(
                            parameterName: DeBruijn(0),
                            body: .error
                        )
                    )
                )
            )
        )
        let script = PlutusV2Script(data: scriptData)
        let scriptHash = try plutusScriptHash(script: .plutusV2Script(script))

        let scriptAddr = try Address(
            paymentPart: .scriptHash(scriptHash),
            network: .testnet
        )

        let datum = PlutusData.bigInt(.int(42))
        let datumOption = DatumOption(datum: datum)
        let txId = TransactionId(payload: Data(repeating: 0xDD, count: 32))
        let input = TransactionInput(transactionId: txId, index: 0)
        let utxoOutput = TransactionOutput(
            address: scriptAddr,
            amount: Value(coin: 2_000_000),
            datumOption: datumOption,
            postAlonzo: true
        )
        let utxo = UTxO(input: input, output: utxoOutput)

        let redeemer = Redeemer(
            tag: .spend,
            index: 0,
            data: PlutusData.bigInt(.int(0)),
            exUnits: ExecutionUnits(mem: 14_000_000, steps: 10_000_000_000)
        )

        let changeAddr = try Address(
            paymentPart: .verificationKeyHash(
                VerificationKeyHash(payload: Data(repeating: 0x03, count: 28))
            ),
            network: .testnet
        )
        let changeOutput = TransactionOutput(
            address: changeAddr,
            amount: Value(coin: 1_500_000),
            postAlonzo: true
        )

        let body = TransactionBody(
            inputs: .list([input]),
            outputs: [changeOutput],
            fee: 200_000,
            collateral: .list([
                TransactionInput(
                    transactionId: TransactionId(payload: Data(repeating: 0xEE, count: 32)),
                    index: 0
                )
            ])
        )
        let witnessSet = TransactionWitnessSet(
            plutusV2Script: .list([script]),
            redeemers: .list([redeemer])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnessSet)

        let validator = Phase2Validator()
        let outcome = try await validator.evaluate(
            transaction: tx,
            resolvedInputs: [utxo],
            chainContext: ctx
        )
        #expect(!outcome.result.isValid)
        #expect(outcome.result.errors.first?.kind == .plutusScriptFailed)
    }
}

// MARK: - Script construction helpers

/// Flat-encode a DeBruijn UPLC program and CBOR-wrap it as a bytestring,
/// matching the PlutusV*Script.data format expected by PhaseTwo.
private func makePlutusV2ScriptData(program: DeBruijnProgram) throws -> Data {
    let flatBytes = try FlatEncoder().encode(program)
    return cborWrapBytestring(flatBytes)
}

/// Encode `bytes` as a CBOR bytestring (major type 2).
private func cborWrapBytestring(_ bytes: Data) -> Data {
    var result = Data()
    let n = bytes.count
    if n <= 23 {
        result.append(0x40 | UInt8(n))
    } else if n <= 0xFF {
        result.append(0x58)
        result.append(UInt8(n))
    } else {
        result.append(0x59)
        result.append(UInt8(n >> 8))
        result.append(UInt8(n & 0xFF))
    }
    result.append(contentsOf: bytes)
    return result
}

// MARK: - Fixture loader helper

private func loadFixture(_ name: String) throws -> String {
    // Bundle.module is generated by SPM for test targets with declared resources.
    guard let url = Bundle.module.url(
        forResource: name,
        withExtension: nil,
        subdirectory: "Resources/Transactions"
    ) else {
        throw FixtureError.notFound(name)
    }
    return try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum FixtureError: Error {
    case notFound(String)
}
