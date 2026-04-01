import Foundation

/// Helpers for JSON serialisation of validator outputs.
public enum JSONExport {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Encode

    /// Encode any `Encodable` value to a pretty-printed JSON string.
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONExportError.encodingFailed("UTF-8 conversion failed")
        }
        return string
    }

    /// Encode any `Encodable` value to a compact (single-line) JSON string.
    public static func encodeCompact<T: Encodable>(_ value: T) throws -> String {
        let compactEncoder = JSONEncoder()
        compactEncoder.outputFormatting = .sortedKeys
        let data = try compactEncoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw JSONExportError.encodingFailed("UTF-8 conversion failed")
        }
        return string
    }

    // MARK: - Decode

    /// Decode a JSON string to a `Decodable` value.
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw JSONExportError.decodingFailed("Failed to convert JSON string to Data")
        }
        return try decoder.decode(type, from: data)
    }

    // MARK: - Error

    public enum JSONExportError: Error {
        case encodingFailed(String)
        case decodingFailed(String)
    }
}
