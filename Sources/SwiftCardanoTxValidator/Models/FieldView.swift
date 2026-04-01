import Foundation

/// A human-readable view of a single named field in a Cardano transaction.
public struct FieldView: Sendable, Codable, Equatable {
    /// Dot-separated path, e.g. `"transaction_body.fee"`.
    public let path: String
    /// Display value as a human-readable string.
    public let value: String
    /// Raw hex bytes, if applicable.
    public let raw: String?

    public init(path: String, value: String, raw: String? = nil) {
        self.path = path
        self.value = value
        self.raw = raw
    }
}
