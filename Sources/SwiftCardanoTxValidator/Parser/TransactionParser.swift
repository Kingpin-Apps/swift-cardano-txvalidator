import Foundation
import SwiftCardanoCore

/// Parses raw Cardano transaction CBOR into structured types.
public struct TransactionParser: Sendable {

    public init() {}

    // MARK: - Parse to Transaction

    /// Decode a hex-encoded CBOR string to a `Transaction`.
    ///
    /// See ``parse(cborBytes:)`` for which era's rules it is read by.
    /// - Throws: `TxValidatorError.malformedCBOR` wrapping the underlying decode error.
    public func parse(cborHex: String) throws -> Transaction {
        guard let bytes = Data(hexString: cborHex.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw TxValidatorError.malformedCBOR("Failed to decode transaction from CBOR hex: not hex")
        }
        return try parse(cborBytes: bytes, from: "hex")
    }

    /// Decode raw CBOR bytes to a `Transaction`.
    ///
    /// Each era's ledger reads a transaction by its own rules — a Shelley
    /// body's protocol-parameter update, for one, is no field of a Conway
    /// body. The transaction is read by the latest era whose ledger accepts
    /// it, so a current transaction is read as Conway and an older one as the
    /// era it was submitted in.
    /// - Throws: `TxValidatorError.malformedCBOR` with why the current era
    ///   rejects it, when no era reads it.
    public func parse(cborBytes: Data) throws -> Transaction {
        try parse(cborBytes: cborBytes, from: "bytes")
    }

    private func parse(cborBytes: Data, from source: String) throws -> Transaction {
        var latestError: (any Error)?
        for era in Era.allCases.reversed() where era >= .shelley {
            do {
                return try Transaction.fromCBOR(data: cborBytes, era: era)
            } catch {
                latestError = latestError ?? error
            }
        }
        throw TxValidatorError.malformedCBOR(
            "Failed to decode transaction from CBOR \(source): \(latestError.map { "\($0)" } ?? "no era reads it")"
        )
    }

    // MARK: - Human-readable view

    /// Parse CBOR hex and return a `TransactionView` (human-readable flat model).
    public func view(cborHex: String) throws -> TransactionView {
        let tx = try parse(cborHex: cborHex)
        return try buildView(transaction: tx)
    }

    /// Build a `TransactionView` from an already-decoded `Transaction`.
    public func buildView(transaction: Transaction) throws -> TransactionView {
        do {
            return try TransactionView.from(transaction)
        } catch {
            throw TxValidatorError.internalError(
                "Failed to build TransactionView: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Field extraction

    /// Extract all fields of a transaction as a flat list of `FieldView` values.
    public func fields(cborHex: String) throws -> [FieldView] {
        let tx = try parse(cborHex: cborHex)
        return try extractFields(from: tx)
    }

    private func extractFields(from tx: Transaction) throws -> [FieldView] {
        var fields: [FieldView] = []
        let body = tx.transactionBody

        fields.append(FieldView(path: "transaction_body.tx_id", value: "\(try body.id)"))
        fields.append(FieldView(path: "transaction_body.fee", value: "\(body.fee) lovelace"))
        fields.append(FieldView(path: "transaction.valid", value: "\(tx.valid)"))

        if let ttl = body.ttl {
            fields.append(FieldView(path: "transaction_body.ttl", value: "\(ttl)"))
        }
        if let start = body.validityStart {
            fields.append(FieldView(path: "transaction_body.validity_start_interval", value: "\(start)"))
        }
        if let hash = body.scriptDataHash {
            fields.append(FieldView(path: "transaction_body.script_data_hash", value: "\(hash)"))
        }
        if let netId = body.networkId {
            fields.append(FieldView(path: "transaction_body.network_id", value: "\(netId)"))
        }
        if let totalCol = body.totalCollateral {
            fields.append(FieldView(path: "transaction_body.total_collateral", value: "\(totalCol) lovelace"))
        }

        for (i, input) in body.inputs.asArray.enumerated() {
            fields.append(FieldView(
                path: "transaction_body.inputs[\(i)]",
                value: "\(input.transactionId)#\(input.index)"
            ))
        }

        for (i, output) in body.outputs.enumerated() {
            let addr: String
            if let bech32 = try? output.address.toBech32() {
                addr = bech32
            } else {
                addr = output.address.toBytes().map { String(format: "%02x", $0) }.joined()
            }
            fields.append(FieldView(
                path: "transaction_body.outputs[\(i)].address",
                value: addr
            ))
            fields.append(FieldView(
                path: "transaction_body.outputs[\(i)].amount",
                value: "\(output.amount.coin) lovelace"
            ))
        }

        return fields
    }
}

// MARK: - Library-level errors

public enum TxValidatorError: Error, Sendable {
    case malformedCBOR(String)
    case internalError(String)
    case phase2UnavailableNoChainContext
    case notImplemented(String)

    public var localizedDescription: String {
        switch self {
        case .malformedCBOR(let msg):        return "Malformed CBOR: \(msg)"
        case .internalError(let msg):        return "Internal error: \(msg)"
        case .phase2UnavailableNoChainContext: return "Phase-2 validation requires a ChainContext"
        case .notImplemented(let msg):       return "Not implemented: \(msg)"
        }
    }
}
