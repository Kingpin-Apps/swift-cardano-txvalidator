import Foundation
import SwiftCardanoCore

/// Parses raw Cardano transaction CBOR into structured types.
public struct TransactionParser: Sendable {

    public init() {}

    // MARK: - Parse to Transaction

    /// Decode a hex-encoded CBOR string to a `Transaction`.
    /// - Throws: `TxValidatorError.malformedCBOR` wrapping the underlying decode error.
    public func parse(cborHex: String) throws -> Transaction {
        do {
            return try Transaction.fromCBORHex(cborHex)
        } catch {
            throw TxValidatorError.malformedCBOR(
                "Failed to decode transaction from CBOR hex: \(error.localizedDescription)"
            )
        }
    }

    /// Decode raw CBOR bytes to a `Transaction`.
    public func parse(cborBytes: Data) throws -> Transaction {
        do {
            return try Transaction.fromCBOR(data: cborBytes)
        } catch {
            throw TxValidatorError.malformedCBOR(
                "Failed to decode transaction from CBOR bytes: \(error.localizedDescription)"
            )
        }
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
        return extractFields(from: tx)
    }

    private func extractFields(from tx: Transaction) -> [FieldView] {
        var fields: [FieldView] = []
        let body = tx.transactionBody

        fields.append(FieldView(path: "transaction_body.tx_id", value: "\(body.id)"))
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
