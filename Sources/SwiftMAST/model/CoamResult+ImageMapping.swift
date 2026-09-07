//
//  CoamResult+ImageMapping.swift
//  SwiftMAST
//
//  Product-owned identity, filter, and image-assignment metadata.
//

import Foundation

/// Controls how locally renderable science products are selected by WCS capability.
public enum ObservationProductWCSPolicy: Equatable, Sendable {
    /// Return only products whose local metadata can provide a WCS.
    case required

    /// Prefer WCS products when at least `minimumCount` are available; otherwise
    /// retain all locally renderable science products.
    case preferred(minimumCount: Int)

    /// Do not consider WCS capability during product selection.
    case ignored
}

/// Primitive rendering metadata that lets image packages consume a CAOM product
/// without importing SwiftMAST-specific filter enums.
public struct ObservationImageAssignment: Codable, Equatable, Hashable {
    public let imageKey: String
    public let fileSafeKey: String
    public let filterName: String
    public let wavelengthMicrons: Double?
    public let paletteIndex: Int
    public let paletteCount: Int
    public let catalogHexColor: String?
    public let intensity: Float

    public init(
        imageKey: String,
        fileSafeKey: String,
        filterName: String,
        wavelengthMicrons: Double?,
        paletteIndex: Int,
        paletteCount: Int,
        catalogHexColor: String?,
        intensity: Float
    ) {
        self.imageKey = imageKey
        self.fileSafeKey = fileSafeKey
        self.filterName = filterName
        self.wavelengthMicrons = wavelengthMicrons
        self.paletteIndex = paletteIndex
        self.paletteCount = paletteCount
        self.catalogHexColor = catalogHexColor
        self.intensity = intensity
    }
}

extension CoamResult {
    /// The first normalized science-filter token represented by this product.
    public var primaryFilterName: String {
        filterTokens.first ?? filters.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The mission catalog color associated with the primary filter, when known.
    public var primaryFilterColor: ObservationFilterColor? {
        for token in filterTokens {
            if let color = filterColorMap[token] {
                return color
            }
        }
        return filterColors.first
    }

    /// Stable dictionary/stack key for mapping this product to a runtime image.
    ///
    /// This deliberately uses the same identity as cache enrichment so remote,
    /// downloaded, and locally reconstructed representations address one image.
    public var imageMappingKey: String {
        productIdentifier
    }

    /// Human-readable, filesystem-safe form of ``imageMappingKey`` for previews.
    public var imageFileSafeKey: String {
        let components = [
            observationGroupKey(self),
            primaryFilterName.isEmpty ? "unknown-filter" : primaryFilterName,
            objID > 0 ? String(objID) : nil,
        ].compactMap { $0 }
        return Self.imageSafeComponent(components.joined(separator: "_"))
    }

    /// Whether this locally available product is suitable for science-image rendering.
    public func isRenderableScienceImage(
        includeSegmentationProducts: Bool = false
    ) -> Bool {
        !isDetectionProduct
            && (includeSegmentationProducts || !isSegmentationProduct)
            && isLocallyRenderable
    }

    /// Build the primitive image assignment for this product's position in a
    /// wavelength-ordered palette.
    public func imageAssignment(
        paletteIndex: Int,
        paletteCount: Int,
        intensity: Float = 0.78
    ) -> ObservationImageAssignment {
        ObservationImageAssignment(
            imageKey: imageMappingKey,
            fileSafeKey: imageFileSafeKey,
            filterName: primaryFilterName,
            wavelengthMicrons: wavelengthMicrons,
            paletteIndex: max(0, paletteIndex),
            paletteCount: max(1, paletteCount),
            catalogHexColor: primaryFilterColor?.hexColor,
            intensity: max(0, min(1, intensity))
        )
    }

    private static func imageSafeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let safe = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(safe).replacingOccurrences(
            of: "__+",
            with: "_",
            options: .regularExpression
        )
    }
}

extension Array where Element == CoamResult {
    /// Products suitable for local science-image rendering.
    public func renderableScienceImages(
        includeSegmentationProducts: Bool = false
    ) -> [CoamResult] {
        filter {
            $0.isRenderableScienceImage(
                includeSegmentationProducts: includeSegmentationProducts
            )
        }
    }

    /// Assign palette positions by wavelength and return them by each product's
    /// stable image key. The receiver's order is otherwise left unchanged.
    public func observationImageAssignments(
        intensity: Float = 0.78
    ) -> [String: ObservationImageAssignment] {
        let spectrallyOrdered = enumerated().sorted { lhs, rhs in
            switch (lhs.element.wavelengthMicrons, rhs.element.wavelengthMicrons) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                let leftFilter = lhs.element.primaryFilterName
                let rightFilter = rhs.element.primaryFilterName
                if leftFilter != rightFilter { return leftFilter < rightFilter }
                return lhs.offset < rhs.offset
            }
        }

        return spectrallyOrdered.enumerated().reduce(into: [:]) { assignments, entry in
            let product = entry.element.element
            let assignment = product.imageAssignment(
                paletteIndex: entry.offset,
                paletteCount: spectrallyOrdered.count,
                intensity: intensity
            )
            assignments[assignment.imageKey] = assignment
        }
    }
}

extension ObservationGroup {
    /// Canonical locally renderable science products for this observation.
    public func renderableScienceProducts(
        includeSegmentationProducts: Bool = false
    ) -> [CoamResult] {
        products.renderableScienceImages(
            includeSegmentationProducts: includeSegmentationProducts
        )
    }

    /// Select locally renderable science products using a reusable WCS policy.
    ///
    /// Product order is preserved. The maximum is applied after WCS selection so
    /// callers receive up to the requested number of products from the selected
    /// candidate set.
    public func selectedScienceProducts(
        maximumCount: Int,
        includeSegmentationProducts: Bool = false,
        wcsPolicy: ObservationProductWCSPolicy = .ignored
    ) -> [CoamResult] {
        guard maximumCount > 0 else { return [] }

        let renderable = renderableScienceProducts(
            includeSegmentationProducts: includeSegmentationProducts
        )
        let wcsCapable = renderable.filter(\.hasWCS)
        let selected: [CoamResult]

        switch wcsPolicy {
        case .required:
            selected = wcsCapable
        case let .preferred(minimumCount):
            selected = wcsCapable.count >= max(1, minimumCount)
                ? wcsCapable
                : renderable
        case .ignored:
            selected = renderable
        }

        return Array(selected.prefix(maximumCount))
    }
}
