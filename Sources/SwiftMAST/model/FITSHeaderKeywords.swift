//
//  FITSHeaderKeywords.swift
//  SwiftMAST
//
//  Lookup tables for FITS header keyword descriptions and
//  categorical value metadata. Based on the FITS Standard
//  (NOST 100-2.0) and HEASARC FITS keyword dictionary.
//
//  Descriptions and categories are loaded from FITSHeaderKeywords.json
//  in the package root directory.
//

import Foundation

/// Provides descriptions and categorical metadata for FITS header keywords.
///
/// Keyword descriptions and categories are loaded from the
/// `FITSHeaderKeywords.json` file in the package root directory.
///
/// Use the static methods to query keyword meanings:
/// ```swift
/// let desc = FITSHeaderKeywords.description(for: "BITPIX")
/// // "Number of bits per data pixel"
///
/// let options = FITSHeaderKeywords.categoricalOptions(for: "XTENSION")
/// // [CategoricalOption(value: "IMAGE", ...), ...]
/// ```
public enum FITSHeaderKeywords {

    // MARK: - JSON Data Model

    /// Represents a single keyword entry in the JSON file.
    private struct KeywordEntry: Codable {
        let description: String
        let category: String
    }

    // MARK: - JSON Loading

    /// Returns the URL for the package root directory.
    private static func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // model/
            .deletingLastPathComponent()  // SwiftMAST/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // package root
    }

    /// Loaded keyword entries from the JSON file, keyed by keyword name.
    private static let jsonEntries: [String: KeywordEntry] = {
        let jsonURL = packageRootURL()
            .appendingPathComponent("FITSHeaderKeywords.json")
        do {
            let data = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([String: KeywordEntry].self, from: data)
        } catch {
            print("Warning: Failed to load FITSHeaderKeywords.json: \(error)")
            return [:]
        }
    }()

    // MARK: - Public API

    /// Returns the human-readable description for a FITS keyword.
    /// Falls back to a generic message for unknown keywords.
    public static func description(for keyword: String) -> String {
        keywordDescriptions[keyword] ?? "FITS header keyword"
    }

    /// Returns whether the keyword has a well-known set of categorical values.
    public static func isCategorical(keyword: String) -> Bool {
        categoricalKeywords.keys.contains(keyword)
    }

    /// Returns all valid values with descriptions for a categorical keyword.
    public static func categoricalOptions(for keyword: String) -> [CategoricalOption]? {
        categoricalKeywords[keyword]
    }

    /// Returns the description of a specific value for a categorical keyword.
    public static func valueDescription(
        for keyword: String, value: FITSHeaderValue
    ) -> String? {
        guard let options = categoricalKeywords[keyword] else { return nil }
        let raw = value.rawString.uppercased()
        return options.first { $0.value.uppercased() == raw }?.description
    }

    /// Returns the header keyword category for a given FITS keyword.
    ///
    /// Covers both general FITS structural, scaling, WCS, and time keywords as well as
    /// JWST-specific keywords from the MAST Instrument Keyword Dictionary at
    /// https://mast.stsci.edu/api/v0/_jwst_inst_keywd.html
    /// Returns `.unknown` for keywords not in the category map.
    public static func category(for keyword: String) -> HeaderKeywordCategory {
        keywordCategories[keyword] ?? .unknown
    }

    // MARK: - Keyword Descriptions (loaded from JSON)

    /// Descriptions for FITS header keywords, loaded from FITSHeaderKeywords.json.
    private static let keywordDescriptions: [String: String] = {
        var d = [String: String]()
        for (keyword, entry) in jsonEntries {
            d[keyword] = entry.description
        }
        return d
    }()

    // MARK: - Keyword Categories (loaded from JSON)

    /// Header keyword → category mapping, loaded from FITSHeaderKeywords.json.
    private static let keywordCategories: [String: HeaderKeywordCategory] = {
        var c = [String: HeaderKeywordCategory]()
        for (keyword, entry) in jsonEntries {
            if let cat = HeaderKeywordCategory(rawValue: entry.category) {
                c[keyword] = cat
            }
        }
        return c
    }()

    // MARK: - Categorical Keywords

    /// Keywords whose values come from a well-defined set per the FITS standard.
    private static let categoricalKeywords: [String: [CategoricalOption]] = [
        "XTENSION": FITSXtension.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
        "BITPIX": FITSBitpix.allCases.map {
            CategoricalOption(value: String($0.rawValue), description: $0.description)
        },
        "RADESYS": FITSRaDesys.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
        "TIMESYS": FITSTimeSys.allCases.map {
            CategoricalOption(value: $0.rawValue, description: $0.description)
        },
    ]
}
