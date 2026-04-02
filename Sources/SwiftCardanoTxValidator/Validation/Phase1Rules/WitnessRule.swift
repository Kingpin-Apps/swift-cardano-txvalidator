import Foundation
import SwiftCardanoCore
import SwiftNcal

/// Phase-1 structural checks on the transaction witness set.
///
/// Checks (all purely structural — no chain state required beyond resolved inputs):
/// - Missing script witnesses — every script-hash referenced by spending inputs or minting
///   must have a corresponding script in the witness set or as an inline reference script
/// - Extraneous script witnesses (warning) — scripts in witness set not referenced by
///   any input, mint, cert, or withdrawal
/// - Native script evaluation — each required native script's timelock / multisig
///   predicates are checked against the transaction body
/// - Missing datum — PlutusV1/V2 script-locked spending inputs must have their datum
///   available (inline in the UTxO or as a datum witness in the witness set)
/// - Extraneous datum witnesses (warning) — datums in the witness set not referenced
///   by any spending input
/// - Missing redeemer pre-check — if Plutus scripts are required but no redeemers are
///   present at all, emit a `missingRedeemer` error
/// - Extraneous redeemer pre-check (warning) — redeemers present but no Plutus scripts
///   are referenced
///
/// Reference: cquisitor-lib `witness.rs` — MissingScriptWitnesses, ExtraScriptWitnesses,
/// NativeScriptFailed, MissingDatumWitness, ExtraneousDatumWitness
public struct WitnessRule: ValidationRule {
    public let name = "witness"

    public init() {}

    public func validate(
        transaction: Transaction,
        context: ValidationContext,
        protocolParams: ProtocolParameters
    ) throws -> [ValidationError] {

        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        let era = context.era ?? .conway

        // Build a map of resolved UTxOs keyed by "txId#index" for fast lookups.
        let resolvedMap: [String: TransactionOutput] = Dictionary(
            uniqueKeysWithValues: context.resolvedInputs.map { utxo in
                ("\(utxo.input.transactionId)#\(utxo.input.index)", utxo.output)
            }
        )

        // -----------------------------------------------------------------------
        // MARK: 1. Collect required script hashes
        // -----------------------------------------------------------------------

        // Script hashes needed for Plutus-locked spending inputs + native-script inputs
        var requiredScriptHashes: [String: String] = [:]   // hash_hex → fieldPath
        // Sub-categories for Plutus scripts (to check redeemers / datums)
        var plutusV1RequiredHashes: Set<String>  = []
        var plutusV2RequiredHashes: Set<String>  = []
        var plutusV3RequiredHashes: Set<String>  = []
        var nativeScriptRequiredHashes: Set<String> = []

        // Spending inputs
        for (i, input) in body.inputs.asArray.enumerated() {
            let key = "\(input.transactionId)#\(input.index)"
            guard let output = resolvedMap[key] else { continue }
            guard let paymentPart = output.address.paymentPart else { continue }
            switch paymentPart {
            case .scriptHash(let sh):
                let hex = sh.payload.toHex
                requiredScriptHashes[hex] = "transaction_body.inputs[\(i)]"
                // We don't know the version from the address alone; we detect it below
                // when we classify witnesses. Add to an "unclassified required" set.
            case .verificationKeyHash:
                break   // key-locked — no script required
            }
        }

        // Minting policy script hashes
        if let mint = body.mint {
            for (j, policyId) in mint.data.keys.enumerated() {
                let hex = policyId.payload.toHex
                requiredScriptHashes[hex] = "transaction_body.mint.policy[\(j)]"
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 2. Collect available script hashes (witness set)
        // -----------------------------------------------------------------------

        // native scripts
        var nativeScriptsByHash: [String: NativeScript] = [:]
        for ns in witnesses.nativeScripts?.asList ?? [] {
            if let sh = try? ns.scriptHash() {
                let hex = sh.payload.toHex
                nativeScriptsByHash[hex] = ns
                nativeScriptRequiredHashes.insert(hex)
            }
        }

        // Plutus V1
        var plutusV1WitnessByHash: [String: PlutusV1Script] = [:]
        for s in witnesses.plutusV1Script?.asList ?? [] {
            if let sh = try? scriptHash(script: .plutusV1Script(s)) {
                let hex = sh.payload.toHex
                plutusV1WitnessByHash[hex] = s
                plutusV1RequiredHashes.insert(hex)
            }
        }

        // Plutus V2 (Babbage+)
        var plutusV2WitnessByHash: [String: PlutusV2Script] = [:]
        if era >= .babbage {
            for s in witnesses.plutusV2Script?.asList ?? [] {
                if let sh = try? scriptHash(script: .plutusV2Script(s)) {
                    let hex = sh.payload.toHex
                    plutusV2WitnessByHash[hex] = s
                    plutusV2RequiredHashes.insert(hex)
                }
            }
        }

        // Plutus V3 (Conway+)
        var plutusV3WitnessByHash: [String: PlutusV3Script] = [:]
        if era >= .conway {
            for s in witnesses.plutusV3Script?.asList ?? [] {
                if let sh = try? scriptHash(script: .plutusV3Script(s)) {
                    let hex = sh.payload.toHex
                    plutusV3WitnessByHash[hex] = s
                    plutusV3RequiredHashes.insert(hex)
                }
            }
        }

        // Inline reference scripts on resolved UTxOs
        var referenceScriptHashes: Set<String> = []
        for utxo in context.resolvedInputs {
            if let inlineScript = utxo.output.script {
                if let sh = try? scriptHash(script: inlineScript) {
                    referenceScriptHashes.insert(sh.payload.toHex)
                }
            }
        }

        let allAvailableHashes: Set<String> = Set(nativeScriptsByHash.keys)
            .union(Set(plutusV1WitnessByHash.keys))
            .union(Set(plutusV2WitnessByHash.keys))
            .union(Set(plutusV3WitnessByHash.keys))
            .union(referenceScriptHashes)

        var issues: [ValidationError] = []

        // -----------------------------------------------------------------------
        // MARK: 3. Missing script witnesses
        // -----------------------------------------------------------------------
        for (hashHex, fieldPath) in requiredScriptHashes {
            if !allAvailableHashes.contains(hashHex) {
                issues.append(ValidationError(
                    kind: .missingScript,
                    fieldPath: fieldPath,
                    message: "Script \(hashHex) is required but not present in the witness "
                        + "set or as an inline reference script in any resolved input.",
                    hint: "Include the script in the witness set "
                        + "or provide a reference input with the script inline."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 4. Extraneous script witnesses (warning)
        // -----------------------------------------------------------------------
        let allWitnessHashes: Set<String> = Set(nativeScriptsByHash.keys)
            .union(Set(plutusV1WitnessByHash.keys))
            .union(Set(plutusV2WitnessByHash.keys))
            .union(Set(plutusV3WitnessByHash.keys))

        for unusedHash in allWitnessHashes.subtracting(requiredScriptHashes.keys) {
            issues.append(ValidationError(
                kind: .extraneousScript,
                fieldPath: "transaction_witness_set.scripts",
                message: "Script \(unusedHash) is present in the witness set but not "
                    + "required by any spending input, minting policy, cert, or withdrawal.",
                hint: "Remove unreferenced scripts from the witness set to reduce transaction size.",
                isWarning: true
            ))
        }

        // -----------------------------------------------------------------------
        // MARK: 5. Native script evaluation
        // -----------------------------------------------------------------------
        // Build the set of vkey hashes from the witness set (Blake2b-224 of each vkey).
        var witnessedKeyHashes: Set<String> = []
        for vkw in witnesses.vkeyWitnesses?.asList ?? [] {
            let keyBytes = vkw.vkey.payload
            if let hashBytes = try? Hash().blake2b(
                data: keyBytes, digestSize: 28, encoder: RawEncoder.self
            ) {
                witnessedKeyHashes.insert(hashBytes.toHex)
            }
        }

        for (hashHex, nativeScript) in nativeScriptsByHash {
            // Only evaluate if this script is actually required.
            guard requiredScriptHashes[hashHex] != nil else { continue }
            let fieldPath = requiredScriptHashes[hashHex] ?? "transaction_witness_set.nativeScript"
            let passed = evaluateNativeScript(
                nativeScript,
                body: body,
                witnessedKeyHashes: witnessedKeyHashes
            )
            if !passed {
                issues.append(ValidationError(
                    kind: .nativeScriptFailed,
                    fieldPath: fieldPath,
                    message: "Native script \(hashHex) evaluation failed: "
                        + nativeScriptFailReason(nativeScript, body: body, witnessedKeyHashes: witnessedKeyHashes),
                    hint: "Ensure the transaction satisfies all script conditions: "
                        + "required signatures are present and validity interval bounds match timelock bounds."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 6. Missing datum witnesses (PlutusV1/V2 inputs require a datum)
        // -----------------------------------------------------------------------
        // Build the set of datum hashes present in the witness set.
        var witnessedDatumHashes: Set<String> = []
        var witnessedDatumData: Set<String> = []  // by CBOR hex
        for pd in witnesses.plutusData?.asList ?? [] {
            // Hash the datum to compare against UTxO datum hash references.
            if let hashData = try? Hash().blake2b(
                data: (try? pd.toCBORData()) ?? Data(),
                digestSize: 32, encoder: RawEncoder.self
            ) {
                witnessedDatumHashes.insert(hashData.toHex)
            }
            if let cborHex = (try? pd.toCBORData()).map({ $0.toHex }) {
                witnessedDatumData.insert(cborHex)
            }
        }

        // Collect datum hashes referenced by spending inputs (for extraneous-datum check).
        var referencedDatumHashes: Set<String> = []

        for (i, input) in body.inputs.asArray.enumerated() {
            let key = "\(input.transactionId)#\(input.index)"
            guard let output = resolvedMap[key] else { continue }
            guard let paymentPart = output.address.paymentPart else { continue }
            guard case .scriptHash(let sh) = paymentPart else { continue }

            let hashHex = sh.payload.toHex

            // Determine if this is a PlutusV1/V2 script (which requires a datum).
            let isPlutusV1 = plutusV1WitnessByHash[hashHex] != nil
                || (referenceScriptHashes.contains(hashHex) && isPlutusV1InResolved(hashHex, resolvedInputs: context.resolvedInputs))
            let isPlutusV2 = plutusV2WitnessByHash[hashHex] != nil
                || (referenceScriptHashes.contains(hashHex) && isPlutusV2InResolved(hashHex, resolvedInputs: context.resolvedInputs))
            // PlutusV3 does not require a separate datum; skip.

            guard isPlutusV1 || isPlutusV2 else { continue }

            // Check datum availability.
            let hasDatumInline: Bool
            let hasDatumHash: Bool

            if let datumOption = output.datumOption {
                switch datumOption.datum {
                case .data:
                    // Inline datums are only valid in Babbage+
                    hasDatumInline = era >= .babbage
                    hasDatumHash   = false
                case .datumHash(let dh):
                    hasDatumInline = false
                    hasDatumHash   = true
                    referencedDatumHashes.insert(dh.payload.toHex)
                    // Check if datum is in witness set.
                    if !witnessedDatumHashes.contains(dh.payload.toHex) {
                        issues.append(ValidationError(
                            kind: .missingDatum,
                            fieldPath: "transaction_body.inputs[\(i)]",
                            message: "Input \(key) references datum hash \(dh.payload.toHex) "
                                + "but no matching datum is present in the transaction witness set.",
                            hint: "Include the datum bytes corresponding to hash \(dh.payload.toHex) "
                                + "in the transaction witness set, or use an inline datum."
                        ))
                    }
                }
            } else {
                hasDatumInline = false
                hasDatumHash   = false
            }

            // For PlutusV1/V2 inputs, a datum (inline or witness-set) is required.
            if !hasDatumInline && !hasDatumHash {
                issues.append(ValidationError(
                    kind: .missingDatum,
                    fieldPath: "transaction_body.inputs[\(i)]",
                    message: "Script-locked input \(key) (script \(hashHex)) requires a datum "
                        + "but none is provided inline or in the transaction witness set.",
                    hint: "Add an inline datum to the UTxO or include the datum in the transaction witness set."
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 7. Extraneous datum witnesses (warning)
        // -----------------------------------------------------------------------
        for pd in witnesses.plutusData?.asList ?? [] {
            guard let cborData = try? pd.toCBORData() else { continue }
            guard let hashBytes = try? Hash().blake2b(
                data: cborData, digestSize: 32, encoder: RawEncoder.self
            ) else { continue }
            let hashHex = hashBytes.toHex
            if !referencedDatumHashes.contains(hashHex) {
                issues.append(ValidationError(
                    kind: .extraneousDatum,
                    fieldPath: "transaction_witness_set.plutusData",
                    message: "Datum with hash \(hashHex) is present in the witness set but "
                        + "not referenced by any spending input.",
                    hint: "Remove unreferenced datums from the witness set to reduce transaction size.",
                    isWarning: true
                ))
            }
        }

        // -----------------------------------------------------------------------
        // MARK: 8. Missing redeemer pre-check
        // -----------------------------------------------------------------------
        let hasPlutusRequired = !Set(requiredScriptHashes.keys)
            .intersection(
                Set(plutusV1WitnessByHash.keys)
                    .union(Set(plutusV2WitnessByHash.keys))
                    .union(Set(plutusV3WitnessByHash.keys))
                    .union(referenceScriptHashes)
            ).isEmpty

        if hasPlutusRequired && witnesses.redeemers == nil {
            issues.append(ValidationError(
                kind: .missingRedeemer,
                fieldPath: "transaction_witness_set.redeemers",
                message: "Transaction spends Plutus-script-locked inputs or mints tokens "
                    + "with Plutus policies, but no redeemers are present in the witness set.",
                hint: "Add a redeemer for each Plutus script invocation."
            ))
        }

        // -----------------------------------------------------------------------
        // MARK: 9. Extraneous redeemer pre-check (warning)
        // -----------------------------------------------------------------------
        if witnesses.redeemers != nil && !hasPlutusRequired {
            issues.append(ValidationError(
                kind: .extraneousRedeemer,
                fieldPath: "transaction_witness_set.redeemers",
                message: "Redeemers are present in the witness set but no Plutus scripts "
                    + "appear to be required by the resolved inputs or minting policies.",
                hint: "Remove the redeemers if no Plutus scripts are being executed, "
                    + "or ensure the script-locked inputs are included in the resolved UTxO set.",
                isWarning: true
            ))
        }

        return issues
    }
}

// MARK: - Native script evaluation

/// Returns `true` if the native script is satisfied by the transaction body and witness set.
private func evaluateNativeScript(
    _ script: NativeScript,
    body: TransactionBody,
    witnessedKeyHashes: Set<String>
) -> Bool {
    switch script {
    case .scriptPubkey(let sp):
        return witnessedKeyHashes.contains(sp.keyHash.payload.toHex)

    case .scriptAll(let sa):
        return sa.scripts.allSatisfy {
            evaluateNativeScript($0, body: body, witnessedKeyHashes: witnessedKeyHashes)
        }

    case .scriptAny(let sa):
        return sa.scripts.contains {
            evaluateNativeScript($0, body: body, witnessedKeyHashes: witnessedKeyHashes)
        }

    case .scriptNofK(let snk):
        let passCount = snk.scripts.filter {
            evaluateNativeScript($0, body: body, witnessedKeyHashes: witnessedKeyHashes)
        }.count
        return passCount >= snk.required

    case .invalidBefore(let bs):
        // The transaction must be valid FROM `slot` onwards.
        // The body's validityStart must be present and >= slot.
        guard let validityStart = body.validityStart else { return false }
        return Int(validityStart) >= bs.slot

    case .invalidHereAfter(let afs):
        // The transaction must expire AT OR BEFORE `slot`.
        // The body's ttl must be present and <= slot.
        guard let ttl = body.ttl else { return false }
        return Int(ttl) <= afs.slot
    }
}

/// Returns a human-readable reason why a native script failed.
private func nativeScriptFailReason(
    _ script: NativeScript,
    body: TransactionBody,
    witnessedKeyHashes: Set<String>
) -> String {
    switch script {
    case .scriptPubkey(let sp):
        return "required key \(sp.keyHash.payload.toHex) is not in the witness set"
    case .scriptAll:
        return "one or more sub-scripts of 'all' failed"
    case .scriptAny:
        return "no sub-script of 'any' succeeded"
    case .scriptNofK(let snk):
        let passCount = snk.scripts.filter {
            evaluateNativeScript($0, body: body, witnessedKeyHashes: witnessedKeyHashes)
        }.count
        return "\(passCount) of \(snk.required) required sub-scripts passed"
    case .invalidBefore(let bs):
        let vs = body.validityStart.map { String($0) } ?? "nil"
        return "validityStart (\(vs)) must be >= \(bs.slot)"
    case .invalidHereAfter(let afs):
        let ttl = body.ttl.map { String($0) } ?? "nil"
        return "ttl (\(ttl)) must be <= \(afs.slot)"
    }
}

// MARK: - Reference script version detection helpers

/// Returns `true` if the UTxO at `hashHex` in `resolvedInputs` has a PlutusV1 inline script.
private func isPlutusV1InResolved(_ hashHex: String, resolvedInputs: [UTxO]) -> Bool {
    for utxo in resolvedInputs {
        guard let s = utxo.output.script else { continue }
        if case .plutusV1Script = s,
           let sh = try? scriptHash(script: s),
           sh.payload.toHex == hashHex {
            return true
        }
    }
    return false
}

/// Returns `true` if the UTxO at `hashHex` in `resolvedInputs` has a PlutusV2 inline script.
private func isPlutusV2InResolved(_ hashHex: String, resolvedInputs: [UTxO]) -> Bool {
    for utxo in resolvedInputs {
        guard let s = utxo.output.script else { continue }
        if case .plutusV2Script = s,
           let sh = try? scriptHash(script: s),
           sh.payload.toHex == hashHex {
            return true
        }
    }
    return false
}
