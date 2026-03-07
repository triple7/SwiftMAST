//
//  ScienceProduct.swift
//  SwiftMAST
//
//  Represents a science image product extracted from a MAST query result.
//  For FITS files, each image HDU produces a separate ScienceProduct entry
//  with merged headers (primary overridden by individual HDU headers).
//

import Foundation
import SwiftQValue

/// Represents a single extracted science image from a CoamResult download.
/// A single FITS file may produce multiple ScienceProduct entries (one per image HDU).
public struct ScienceProduct: Codable {
    /// Display name derived from the source file and HDU index
    public let name: String

    /// Local URL of the saved image (JPEG converted from FITS, or direct JPEG)
    public let imageLocation: URL?

    /// Local URL of the source file (FITS file or downloaded JPEG)
    public let sourceFileLocation: URL?

    /// Merged headers: primary HDU headers as base, overridden by individual HDU headers
    public let headers: [String: QValue]

    /// The original CoamResult that produced this product
    public let coamResult: CoamResult
}
