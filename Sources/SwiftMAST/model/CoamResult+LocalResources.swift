//
//  CoamResult+LocalResources.swift
//  SwiftMAST
//
//  Local cache enrichment and product capabilities shared by remote and local results.
//

import Foundation
import SwiftQValue

/// Files and metadata sidecars associated with a locally available CAOM product.
///
/// Paths are stored as strings so the representation remains Codable and can also
/// describe cache entries whose files are temporarily unavailable.
public struct CoamLocalResources: Codable, Equatable, Hashable {
    public var fitsPath: String?
    public var imagePath: String?
    public var previewImagePath: String?
    public var rawMetadataPath: String?
    public var structuredMetadataPath: String?
    public var imageMetadataPath: String?
    public var cachedAt: Date?

    public init(
        fitsPath: String? = nil,
        imagePath: String? = nil,
        previewImagePath: String? = nil,
        rawMetadataPath: String? = nil,
        structuredMetadataPath: String? = nil,
        imageMetadataPath: String? = nil,
        cachedAt: Date? = nil
    ) {
        self.fitsPath = fitsPath
        self.imagePath = imagePath
        self.previewImagePath = previewImagePath
        self.rawMetadataPath = rawMetadataPath
        self.structuredMetadataPath = structuredMetadataPath
        self.imageMetadataPath = imageMetadataPath
        self.cachedAt = cachedAt
    }

    public var fitsURL: URL? { Self.fileURL(for: fitsPath) }
    public var imageURL: URL? { Self.fileURL(for: imagePath) }
    public var previewImageURL: URL? { Self.fileURL(for: previewImagePath) }
    public var rawMetadataURL: URL? { Self.fileURL(for: rawMetadataPath) }
    public var structuredMetadataURL: URL? { Self.fileURL(for: structuredMetadataPath) }
    public var imageMetadataURL: URL? { Self.fileURL(for: imageMetadataPath) }

    public var preferredImageURL: URL? {
        imageURL ?? previewImageURL
    }

    public var hasRenderableResource: Bool {
        fitsPath != nil || imagePath != nil || previewImagePath != nil
    }

    private static func fileURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

extension CoamResult {
    /// Stable identity for associating a query result with cache and enrichment state.
    public var productIdentifier: String {
        if !dataURL.isEmpty {
            return "\(obs_collection.uppercased()):\(dataURL)"
        }
        if objID > 0 {
            return "\(obs_collection.uppercased()):obj:\(objID)"
        }
        return [obs_collection.uppercased(), obs_id, instrument_name, filters]
            .joined(separator: ":")
    }

    public var localFITSURL: URL? { localResources?.fitsURL }
    public var localImageURL: URL? { localResources?.imageURL }
    public var localPreviewImageURL: URL? { localResources?.previewImageURL }
    public var preferredLocalImageURL: URL? { localResources?.preferredImageURL }

    /// A preferred local resource, using FITS first so callers can retain raw science data.
    public var preferredLocalResourceURL: URL? {
        localFITSURL ?? preferredLocalImageURL
    }

    public var hasLocalFITS: Bool { localFITSURL != nil }
    public var hasLocalImage: Bool { preferredLocalImageURL != nil }
    public var isLocallyRenderable: Bool { localResources?.hasRenderableResource == true }

    /// Normalized filter tokens from compound CAOM filter strings.
    public var filterTokens: [String] {
        filters
            .split { $0 == ";" || $0 == "," || $0 == " " }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    public var isDetectionProduct: Bool {
        filterTokens.contains("DETECTION")
    }

    public var isSegmentationProduct: Bool {
        let metadataValues = fitsImageHeaderMetadata?.headers.compactMap { header -> String? in
            switch header.keyword.uppercased() {
            case "DATAMODL", "FILENAME":
                return header.value.rawString.lowercased()
            default:
                return nil
            }
        } ?? []
        let filenames = [localFITSURL, localImageURL, localPreviewImageURL]
            .compactMap { $0?.lastPathComponent.lowercased() }
        return metadataValues.contains {
            $0.contains("segmentationmapmodel") || $0.contains("_segm")
        } || filenames.contains { $0.contains("_segm") }
    }

    public var wcs: FITSWCSData? {
        fitsImageHeaderMetadata.flatMap(FITSWCSData.wcsData(from:))
    }

    public var hasWCS: Bool {
        wcs != nil || hasLocalFITS
    }

    /// Approximate primary-filter wavelength in microns when it can be inferred.
    public var wavelengthMicrons: Double? {
        guard let token = filterTokens.first else { return nil }
        let namedNanometres: [String: Double] = [
            "FUV": 153, "NUV": 231,
            "UVW2": 193, "UVM2": 225, "UVW1": 260,
            "U": 346, "B": 439, "V": 547,
            "G": 481, "R": 617, "I": 752, "Z": 866, "Y": 962,
            "TESS": 786,
        ]
        if let nanometres = namedNanometres[token] {
            return nanometres / 1_000
        }

        guard token.first == "F" else { return nil }
        let digits = token.dropFirst().prefix { $0.isNumber }
        guard let raw = Double(digits), !digits.isEmpty else { return nil }
        if observationMission == .jwst {
            return raw / 100
        }
        return raw / 1_000
    }

    public func withLocalResources(_ resources: CoamLocalResources?) -> CoamResult {
        var copy = self
        copy.localResources = resources
        return copy
    }

    /// Build a canonical result for a product discovered without a CAOM sidecar.
    public init(
        localTargetName: String,
        mission: String,
        observationID: String,
        filter: String,
        instrument: String = "",
        dataProductType: String = "IMAGE",
        localResources: CoamLocalResources,
        rawMetadata: [String: QValue]? = nil,
        fitsImageHeaderMetadata: FITSImageHeaderMetadata? = nil
    ) {
        let resolvedTarget = Self.metadataString(
            keys: ["TARGNAME", "OBJECT", "TARGET"], in: rawMetadata
        ) ?? localTargetName
        let resolvedMission = Self.metadataString(
            keys: ["TELESCOP", "MISSION"], in: rawMetadata
        ) ?? mission
        let resolvedObservationID = Self.metadataString(
            keys: ["OBS_ID", "OBSID", "OBSERVID"], in: rawMetadata
        ) ?? observationID
        let resolvedFilter = Self.metadataString(
            keys: ["FILTER", "FILTER1", "FILTNAM", "FILTNAM1"], in: rawMetadata
        ) ?? filter
        let resolvedInstrument = Self.metadataString(
            keys: ["INSTRUME", "INSTRUMENT"], in: rawMetadata
        ) ?? instrument

        self.init(
            calib_level: 0,
            dataRights: "",
            dataURL: "",
            dataproduct_type: dataProductType,
            distance: 0,
            em_max: 0,
            em_min: 0,
            filters: resolvedFilter,
            instrument_name: resolvedInstrument,
            intentType: "science",
            jpegURL: "",
            mtFlag: false,
            objID: 0,
            obs_collection: resolvedMission,
            obs_id: resolvedObservationID,
            obs_title: "",
            obsid: 0,
            project: "",
            proposal_id: "",
            proposal_pi: "",
            proposal_type: "",
            provenance_name: "local",
            s_dec: rawMetadata?["CRVAL2"] ?? QValue(value: ""),
            s_ra: rawMetadata?["CRVAL1"] ?? QValue(value: ""),
            s_region: "",
            sequence_number: 0,
            srcDen: 0,
            t_exptime: 0,
            t_max: 0,
            t_min: 0,
            t_obs_release: 0,
            target_classification: "",
            target_name: resolvedTarget,
            wavelength_region: "",
            fitsImageHeaderMetadata: fitsImageHeaderMetadata,
            localResources: localResources
        )
    }

    private static func metadataString(
        keys: [String], in metadata: [String: QValue]?
    ) -> String? {
        for key in keys {
            guard let value = metadata?[key]?.value else { continue }
            let string = String(describing: value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !string.isEmpty { return string }
        }
        return nil
    }
}
