//
//  ScienceProduct.swift
//  SwiftMAST
//
//  Represents a science image product extracted from a MAST query result.
//  For FITS files, each image HDU produces a separate ScienceProduct entry
//  with merged headers (primary overridden by individual HDU headers).
//

import Foundation

/// Represents a single extracted science image from a CoamResult download.
/// A single FITS file may produce multiple ScienceProduct entries (one per image HDU).
///
/// Each product contains structured headers as an array of ``FITSHeaderUnit``
/// entries that provide the keyword, typed value, FITS comment, and metadata
/// (keyword descriptions, categorical enum information).
///
/// Example:
/// ```swift
/// for header in product.headers {
///     print("\(header.keyword): \(header.value) — \(header.keywordDescription)")
///     if header.isCategorical, let desc = header.valueDescription {
///         print("  Value meaning: \(desc)")
///     }
/// }
/// ```
public struct ScienceProduct: Codable {
    /// Display name derived from the source file and HDU index
    public let name: String

    /// Local URL of the saved image (JPEG converted from FITS, or direct JPEG)
    public let imageLocation: URL?

    /// Local URL of the source file (FITS file or downloaded JPEG)
    public let sourceFileLocation: URL?

    /// Structured FITS headers — each entry has a keyword, typed value, comment,
    /// keyword description, and categorical enum information where applicable.
    /// For extension HDU products, headers are merged: primary HDU headers as
    /// base, overridden by individual HDU headers.
    public let headers: [FITSHeaderUnit]

    /// The original CoamResult that produced this product
    public let coamResult: CoamResult

    /// Look up a header by keyword name.
    /// - Parameter keyword: The FITS keyword (e.g. "BITPIX", "TELESCOP")
    /// - Returns: The first matching header unit, or nil
    public func header(forKeyword keyword: String) -> FITSHeaderUnit? {
        headers.first { $0.keyword == keyword }
    }

    /// Look up all headers matching a keyword.
    /// Useful for keywords that can appear multiple times (COMMENT, HISTORY).
    public func headers(forKeyword keyword: String) -> [FITSHeaderUnit] {
        headers.filter { $0.keyword == keyword }
    }
}
