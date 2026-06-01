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

// MARK: - Raw FITS Observation Products

/// Semantic role for an image HDU inside a FITS observation product.
public enum FITSHDURole: String, Codable, CaseIterable, Equatable, Hashable {
    case science
    case weight
    case error
    case dataQuality
    case unknown
}

/// A raw numeric FITS image buffer decoded into scaled floating-point values.
public struct FITSPixelBuffer: Codable, Equatable, Hashable {
    public let width: Int
    public let height: Int
    public let axisCount: Int
    public let channelCount: Int
    public let bitpix: Int
    public let values: [Float]
    public let invalidValueCount: Int

    public var pixelCount: Int { width * height }
    public var expectedValueCount: Int { pixelCount * max(channelCount, 1) }
}

/// Sky coordinate in degrees.
public struct FITSWorldCoordinate: Codable, Equatable, Hashable {
    public let ra: Double
    public let dec: Double
}

/// Zero-based FITS pixel coordinate used by app/image rendering code.
public struct FITSPixelCoordinate: Codable, Equatable, Hashable {
    public let x: Double
    public let y: Double
}

/// Minimal WCS transform parsed from FITS headers.
///
/// This is intentionally small for phase one. It supports the common linear CD
/// matrix form and the PC + CDELT form. Pixel coordinates accepted by these
/// methods are zero-based; the FITS CRPIX calculation is applied internally as
/// one-based, per the FITS convention.
public struct FITSWCS: Codable, Equatable, Hashable {
    public let crpix1: Double
    public let crpix2: Double
    public let crval1: Double
    public let crval2: Double
    public let ctype1: String
    public let ctype2: String
    public let cd1_1: Double
    public let cd1_2: Double
    public let cd2_1: Double
    public let cd2_2: Double

    public init?(
        crpix1: Double?,
        crpix2: Double?,
        crval1: Double?,
        crval2: Double?,
        ctype1: String?,
        ctype2: String?,
        cd1_1: Double?,
        cd1_2: Double?,
        cd2_1: Double?,
        cd2_2: Double?,
        cdelt1: Double?,
        cdelt2: Double?,
        pc1_1: Double? = nil,
        pc1_2: Double? = nil,
        pc2_1: Double? = nil,
        pc2_2: Double? = nil
    ) {
        guard let crpix1, let crpix2, let crval1, let crval2 else { return nil }

        let resolvedCtype1 = ctype1 ?? "RA---TAN"
        let resolvedCtype2 = ctype2 ?? "DEC--TAN"

        let matrix: (Double, Double, Double, Double)?
        if let cd1_1, let cd1_2, let cd2_1, let cd2_2 {
            matrix = (cd1_1, cd1_2, cd2_1, cd2_2)
        } else if let cdelt1, let cdelt2 {
            let pc1_1 = pc1_1 ?? 1
            let pc1_2 = pc1_2 ?? 0
            let pc2_1 = pc2_1 ?? 0
            let pc2_2 = pc2_2 ?? 1
            matrix = (cdelt1 * pc1_1, cdelt1 * pc1_2, cdelt2 * pc2_1, cdelt2 * pc2_2)
        } else {
            matrix = nil
        }

        guard let matrix else { return nil }

        self.crpix1 = crpix1
        self.crpix2 = crpix2
        self.crval1 = crval1
        self.crval2 = crval2
        self.ctype1 = resolvedCtype1
        self.ctype2 = resolvedCtype2
        self.cd1_1 = matrix.0
        self.cd1_2 = matrix.1
        self.cd2_1 = matrix.2
        self.cd2_2 = matrix.3
    }

    public init?(headers: [FITSHeaderUnit]) {
        self.init(
            crpix1: Self.doubleValue("CRPIX1", in: headers),
            crpix2: Self.doubleValue("CRPIX2", in: headers),
            crval1: Self.doubleValue("CRVAL1", in: headers),
            crval2: Self.doubleValue("CRVAL2", in: headers),
            ctype1: Self.stringValue("CTYPE1", in: headers),
            ctype2: Self.stringValue("CTYPE2", in: headers),
            cd1_1: Self.doubleValue("CD1_1", in: headers),
            cd1_2: Self.doubleValue("CD1_2", in: headers),
            cd2_1: Self.doubleValue("CD2_1", in: headers),
            cd2_2: Self.doubleValue("CD2_2", in: headers),
            cdelt1: Self.doubleValue("CDELT1", in: headers),
            cdelt2: Self.doubleValue("CDELT2", in: headers),
            pc1_1: Self.doubleValue("PC1_1", in: headers),
            pc1_2: Self.doubleValue("PC1_2", in: headers),
            pc2_1: Self.doubleValue("PC2_1", in: headers),
            pc2_2: Self.doubleValue("PC2_2", in: headers)
        )
    }

    public func worldCoordinate(x: Double, y: Double) -> FITSWorldCoordinate {
        let dx = (x + 1) - crpix1
        let dy = (y + 1) - crpix2
        return FITSWorldCoordinate(
            ra: crval1 + cd1_1 * dx + cd1_2 * dy,
            dec: crval2 + cd2_1 * dx + cd2_2 * dy
        )
    }

    public func pixelCoordinate(ra: Double, dec: Double) -> FITSPixelCoordinate? {
        let determinant = cd1_1 * cd2_2 - cd1_2 * cd2_1
        guard abs(determinant) > .ulpOfOne else { return nil }

        let dra = ra - crval1
        let ddec = dec - crval2
        let dx = (cd2_2 * dra - cd1_2 * ddec) / determinant
        let dy = (-cd2_1 * dra + cd1_1 * ddec) / determinant

        return FITSPixelCoordinate(x: dx + crpix1 - 1, y: dy + crpix2 - 1)
    }

    public func cornerWorldCoordinates(width: Int, height: Int) -> [FITSWorldCoordinate] {
        guard width > 0, height > 0 else { return [] }
        let maxX = Double(width - 1)
        let maxY = Double(height - 1)
        return [
            worldCoordinate(x: 0, y: 0),
            worldCoordinate(x: maxX, y: 0),
            worldCoordinate(x: maxX, y: maxY),
            worldCoordinate(x: 0, y: maxY),
        ]
    }

    public func isApproximatelyEqual(to other: FITSWCS, tolerance: Double = 1e-9) -> Bool {
        abs(crpix1 - other.crpix1) <= tolerance
            && abs(crpix2 - other.crpix2) <= tolerance
            && abs(crval1 - other.crval1) <= tolerance
            && abs(crval2 - other.crval2) <= tolerance
            && abs(cd1_1 - other.cd1_1) <= tolerance
            && abs(cd1_2 - other.cd1_2) <= tolerance
            && abs(cd2_1 - other.cd2_1) <= tolerance
            && abs(cd2_2 - other.cd2_2) <= tolerance
    }

    private static func doubleValue(_ keyword: String, in headers: [FITSHeaderUnit]) -> Double? {
        headers.first { $0.keyword == keyword }?.value.doubleValue
    }

    private static func stringValue(_ keyword: String, in headers: [FITSHeaderUnit]) -> String? {
        headers.first { $0.keyword == keyword }?.value.rawString
    }
}

/// A single raw image HDU extracted from a FITS file.
public struct FITSImagePlane: Codable, Equatable {
    public let role: FITSHDURole
    public let extName: String?
    public let extIndex: Int
    public let width: Int
    public let height: Int
    public let headers: [FITSHeaderUnit]
    public let pixels: FITSPixelBuffer
    public let wcs: FITSWCS?
}

/// A science image plane with its matching weight map, if one is available.
public struct FITSImagePlanePair: Codable, Equatable {
    public let science: FITSImagePlane
    public let weight: FITSImagePlane?
}

/// Raw image planes and metadata extracted from one FITS observation product.
public struct FITSObservationProduct: Codable, Equatable {
    public let coamResult: CoamResult
    public let sourceFileLocation: URL
    public let primaryHeaders: [FITSHeaderUnit]
    public let planes: [FITSImagePlane]

    public var sciencePlanes: [FITSImagePlane] {
        planes.filter { $0.role == .science }
    }

    public var weightPlanes: [FITSImagePlane] {
        planes.filter { $0.role == .weight }
    }

    public var preferredSciencePlane: FITSImagePlane? {
        sciencePlanes.first ?? planes.first { $0.role == .unknown }
    }

    public var preferredScienceWeightPair: FITSImagePlanePair? {
        guard let science = preferredSciencePlane else { return nil }
        return FITSImagePlanePair(science: science, weight: weightPlane(matching: science))
    }

    public func weightPlane(matching sciencePlane: FITSImagePlane) -> FITSImagePlane? {
        weightPlanes.first { candidate in
            candidate.matchesDimensions(of: sciencePlane) && candidate.matchesWCS(of: sciencePlane)
        } ?? weightPlanes.first { candidate in
            candidate.matchesDimensions(of: sciencePlane)
        }
    }
}

/// Header-only metadata fetched from a remote FITS product without downloading image data.
public struct FITSHeaderSummary: Codable, Equatable {
    public let sourceURL: URL
    public let bytesFetched: Int
    public let remoteFileSizeBytes: Int64?
    public let primaryHeaders: [FITSHeaderUnit]
    public let imageHDUs: [FITSHeaderHDUSummary]
    public let parsedHeaderCount: Int
    public let reachedEndOfAvailableHeaders: Bool

    public var preferredImageHDU: FITSHeaderHDUSummary? {
        imageHDUs.first { $0.role == .science } ?? imageHDUs.first
    }
}

/// Header-only metadata for one image HDU inside a FITS product.
public struct FITSHeaderHDUSummary: Codable, Equatable {
    public let extIndex: Int
    public let extName: String?
    public let role: FITSHDURole
    public let width: Int
    public let height: Int
    public let axisCount: Int
    public let bitpix: Int
    public let dataSizeBytes: Int
    public let headerOffset: Int
    public let dataOffset: Int
    public let headers: [FITSHeaderUnit]
    public let wcs: FITSWCS?
}

private extension FITSImagePlane {
    func matchesDimensions(of other: FITSImagePlane) -> Bool {
        width == other.width && height == other.height
    }

    func matchesWCS(of other: FITSImagePlane) -> Bool {
        switch (wcs, other.wcs) {
        case let (lhs?, rhs?):
            return lhs.isApproximatelyEqual(to: rhs)
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

/// Rule-based HDU role classifier for common mission/product conventions.
public enum FITSHDURoleClassifier {
    public static func classify(
        headers: [FITSHeaderUnit],
        sourceFilename: String? = nil
    ) -> FITSHDURole {
        let extName = headerString("EXTNAME", in: headers)
        let btype = headerString("BTYPE", in: headers)
        let imageType = headerString("IMAGETYP", in: headers)
        let hduClass1 = headerString("HDUCLAS1", in: headers)
        let hduClass2 = headerString("HDUCLAS2", in: headers)

        let exactTerms = [extName, btype, imageType, hduClass1, hduClass2]
            .compactMap { $0?.normalizedHDUClassifierToken }

        let filename = sourceFilename?.normalizedHDUClassifierToken ?? ""

        if exactTerms.contains(where: isWeightTerm) || filenameContainsWeight(filename) {
            return .weight
        }
        if exactTerms.contains(where: isErrorTerm) || filenameContainsError(filename) {
            return .error
        }
        if exactTerms.contains(where: isDataQualityTerm) || filenameContainsDataQuality(filename) {
            return .dataQuality
        }
        if exactTerms.contains(where: isScienceTerm) || filenameContainsScience(filename) {
            return .science
        }

        return .unknown
    }

    private static func headerString(_ keyword: String, in headers: [FITSHeaderUnit]) -> String? {
        headers.first { $0.keyword == keyword }?.value.rawString
    }

    private static func isScienceTerm(_ term: String) -> Bool {
        term == "SCI" || term == "SCIENCE" || term == "IMAGE" || term == "RATE"
    }

    private static func isWeightTerm(_ term: String) -> Bool {
        term == "WHT" || term == "WEIGHT" || term == "WEIGHTS" || term == "IVM"
            || term == "VAR_POISSON" || term == "VAR_RNOISE"
    }

    private static func isErrorTerm(_ term: String) -> Bool {
        term == "ERR" || term == "ERROR" || term == "RMS" || term == "UNCERT" || term == "UNCERTAINTY"
    }

    private static func isDataQualityTerm(_ term: String) -> Bool {
        term == "DQ" || term == "DQUALITY" || term == "QUALITY" || term == "MASK"
    }

    private static func filenameContainsScience(_ filename: String) -> Bool {
        filename.hasToken("SCI") || filename.hasToken("SCIENCE")
    }

    private static func filenameContainsWeight(_ filename: String) -> Bool {
        filename.hasToken("WHT") || filename.hasToken("WEIGHT") || filename.hasToken("IVM")
    }

    private static func filenameContainsError(_ filename: String) -> Bool {
        filename.hasToken("ERR") || filename.hasToken("ERROR") || filename.hasToken("RMS")
    }

    private static func filenameContainsDataQuality(_ filename: String) -> Bool {
        filename.hasToken("DQ") || filename.hasToken("QUALITY") || filename.hasToken("MASK")
    }
}

private extension String {
    var normalizedHDUClassifierToken: String {
        uppercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasToken(_ token: String) -> Bool {
        let separators = CharacterSet.alphanumerics.inverted
        return components(separatedBy: separators).contains(token)
    }
}
