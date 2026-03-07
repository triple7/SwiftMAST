//
//  FITSHeaderUnit.swift
//  SwiftMAST
//
//  Structured representation of a single FITS header entry.
//  Provides typed values, keyword descriptions, and categorical
//  enum information for well-known FITS standard keywords.
//

import Foundation

/// A single FITS header entry with keyword, typed value, comment, and metadata.
///
/// Each header unit corresponds to one 80-character card image in the FITS header.
/// For known keywords, `keywordDescription` provides a human-readable explanation.
/// For categorical keywords (e.g. BITPIX, XTENSION), `categoricalOptions` lists
/// all valid values with descriptions.
///
/// Example:
/// ```swift
/// let unit = FITSHeaderUnit(keyword: "BITPIX", value: .integer(-32), comment: "array data type")
/// print(unit.keywordDescription)       // "Number of bits per data pixel"
/// print(unit.isCategorical)            // true
/// print(unit.categoricalOptions?.count) // 6
/// ```
public struct FITSHeaderUnit: Codable, Identifiable, Equatable, Hashable {
    public var id: String { keyword }

    /// The FITS keyword name (e.g. "BITPIX", "TELESCOP", "NAXIS1")
    public let keyword: String

    /// The typed value of this header entry
    public let value: FITSHeaderValue

    /// The inline comment from the FITS header card (after the '/' separator)
    public let comment: String

    /// Human-readable description of what this keyword means in the FITS standard
    public var keywordDescription: String {
        FITSHeaderKeywords.description(for: keyword)
    }

    /// Whether this keyword has a well-known set of categorical values
    public var isCategorical: Bool {
        FITSHeaderKeywords.isCategorical(keyword: keyword)
    }

    /// All valid values with descriptions for this keyword, if categorical
    public var categoricalOptions: [CategoricalOption]? {
        FITSHeaderKeywords.categoricalOptions(for: keyword)
    }

    /// Description of the current value, if this keyword is categorical
    public var valueDescription: String? {
        FITSHeaderKeywords.valueDescription(for: keyword, value: value)
    }
}

// MARK: - FITSHeaderValue

/// A typed value from a FITS header entry.
///
/// FITS headers contain values of four primitive types: strings, integers,
/// floating-point numbers, and booleans. This enum preserves the original
/// type from the FITS file.
public enum FITSHeaderValue: Codable, Equatable, Hashable, CustomStringConvertible {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)

    /// The value as a display string
    public var description: String {
        switch self {
        case .string(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "T" : "F"
        }
    }

    /// The raw string representation suitable for lookups
    public var rawString: String {
        switch self {
        case .string(let s):
            return s.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "'", with: "")
                .trimmingCharacters(in: .whitespaces)
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "T" : "F"
        }
    }

    /// The value as an optional Int (returns nil for non-integer values)
    public var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .double(let d): return Int(exactly: d)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        case .bool: return nil
        }
    }

    /// The value as an optional Double (returns nil for non-numeric values)
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .integer(let i): return Double(i)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool: return nil
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ValueType: String, Codable {
        case string, integer, double, bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(s, forKey: .value)
        case .integer(let i):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(i, forKey: .value)
        case .double(let d):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(d, forKey: .value)
        case .bool(let b):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(b, forKey: .value)
        }
    }
}

// MARK: - CategoricalOption

/// Describes one valid value for a categorical FITS keyword.
///
/// Used to enumerate all possible values of keywords like BITPIX, XTENSION, etc.
public struct CategoricalOption: Codable, Identifiable, Equatable, Hashable {
    public var id: String { value }

    /// The raw value (e.g. "IMAGE", "-32", "ICRS")
    public let value: String

    /// Human-readable description of this value
    public let description: String
}
