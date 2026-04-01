import Foundation

/// The outcome of a validation pass — either clean or carrying a list of errors/warnings.
public enum ValidationResult: Sendable {
    case valid
    case invalid([ValidationError])

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public var errors: [ValidationError] {
        guard case .invalid(let errs) = self else { return [] }
        return errs.filter { !$0.isWarning }
    }

    public var warnings: [ValidationError] {
        guard case .invalid(let errs) = self else { return [] }
        return errs.filter { $0.isWarning }
    }

    public var allIssues: [ValidationError] {
        guard case .invalid(let errs) = self else { return [] }
        return errs
    }
}

// MARK: - Codable

extension ValidationResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case status, issues
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        if status == "valid" {
            self = .valid
        } else {
            let issues = try container.decode([ValidationError].self, forKey: .issues)
            self = .invalid(issues)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .valid:
            try container.encode("valid", forKey: .status)
            try container.encode([ValidationError](), forKey: .issues)
        case .invalid(let issues):
            try container.encode("invalid", forKey: .status)
            try container.encode(issues, forKey: .issues)
        }
    }
}

// MARK: - Merging

extension ValidationResult {
    /// Merge two results; any errors from either appear in the combined result.
    func merged(with other: ValidationResult) -> ValidationResult {
        let combined = allIssues + other.allIssues
        return combined.isEmpty ? .valid : .invalid(combined)
    }
}
