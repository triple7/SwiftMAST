//
//  main.swift
//  TestM31Metadata
//
//  Test script to download M31 imagery and extract FITS metadata
//

import Foundation
import SwiftMAST

print("🚀 Starting M31 FITS Metadata Extraction Test\n")

let mast = SwiftMAST()

// Test with M31 (Andromeda Galaxy)
let targetName = "M31"

print("📡 Downloading imagery for \(targetName)...\n")

// Download FITS files for M31
// Using default science filter options and requesting FITS files
mast.downloadImagery(
    targetName: targetName,
    productType: .Fits,  // Changed from .Jpeg to .Fits to enable metadata extraction
    filterOptions: .defaultScience,
    pageSize: 5,  // Limit to 5 for testing
    token: nil
) { urls in
    print("\n✅ Download complete!")
    print("📦 Downloaded \(urls.count) FITS files\n")

    // Print all the URLs with their metadata
    for (index, url) in urls.enumerated() {
        print("[\(index + 1)] \(url.lastPathComponent)")

        // Get metadata for this specific URL
        if let metadata = mast.getFitsMetadata(target: targetName, forUrl: url) {
            print(
                "    📐 NAXIS: \(metadata.naxis ?? 0), Dimensions: \(metadata.dimensionDescription)")
            if let filter = metadata.filter {
                print("    🔭 Filter: \(filter)")
            }
            if let expTime = metadata.exposureTime {
                print("    ⏱️ Exposure: \(String(format: "%.2f", expTime))s")
            }
        }
    }

    print("\n" + String(repeating: "=", count: 80))
    print("📊 FITS METADATA ANALYSIS")
    print(String(repeating: "=", count: 80) + "\n")

    // Print all extracted metadata
    mast.printFitsMetadata(target: targetName)

    // Get metadata as dictionary keyed by URL
    let metadataByUrl = mast.getFitsMetadata(target: targetName, forUrls: urls)
    print("\n📎 Metadata lookup by URL: \(metadataByUrl.count)/\(urls.count) URLs have metadata")

    // Access the metadata programmatically
    if let metadataList = mast.getFitsMetadata(target: targetName) {
        print("\n" + String(repeating: "=", count: 80))
        print("📈 METADATA STATISTICS")
        print(String(repeating: "=", count: 80) + "\n")

        // Analyze dimensions
        let dimensions = metadataList.compactMap { $0.naxis }
        if !dimensions.isEmpty {
            print("📐 Dimension Analysis:")
            let dim2D = dimensions.filter { $0 == 2 }.count
            let dim3D = dimensions.filter { $0 == 3 }.count
            print("  - 2D Images: \(dim2D)")
            print("  - 3D Images: \(dim3D)")
        }

        // Analyze filters
        let filters = metadataList.compactMap { $0.filter }
        if !filters.isEmpty {
            let uniqueFilters = Set(filters)
            print("\n🔭 Filters Used: \(uniqueFilters.sorted().joined(separator: ", "))")
        }

        // Analyze telescopes
        let telescopes = metadataList.compactMap { $0.telescope }
        if !telescopes.isEmpty {
            let uniqueTelescopes = Set(telescopes)
            print("\n🛰️ Telescopes: \(uniqueTelescopes.sorted().joined(separator: ", "))")
        }

        // Analyze instruments
        let instruments = metadataList.compactMap { $0.instrument }
        if !instruments.isEmpty {
            let uniqueInstruments = Set(instruments)
            print("\n📷 Instruments: \(uniqueInstruments.sorted().joined(separator: ", "))")
        }

        // Exposure times
        let exposureTimes = metadataList.compactMap { $0.exposureTime }
        if !exposureTimes.isEmpty {
            let avgExposure = exposureTimes.reduce(0, +) / Double(exposureTimes.count)
            let minExposure = exposureTimes.min() ?? 0
            let maxExposure = exposureTimes.max() ?? 0
            print("\n⏱️ Exposure Times:")
            print("  - Average: \(String(format: "%.2f", avgExposure)) s")
            print("  - Min: \(String(format: "%.2f", minExposure)) s")
            print("  - Max: \(String(format: "%.2f", maxExposure)) s")
        }

        // WCS information
        let wcsImages = metadataList.filter { $0.crval1 != nil && $0.crval2 != nil }
        print("\n🌍 World Coordinate System:")
        print("  - Images with WCS: \(wcsImages.count)/\(metadataList.count)")

        // Pixel scales
        let pixelScales = metadataList.compactMap { $0.cdelt1 }
        if !pixelScales.isEmpty {
            let avgScale = abs(pixelScales.reduce(0, +) / Double(pixelScales.count))
            print("  - Average pixel scale: \(String(format: "%.6f", avgScale))°/pixel")
            print("    (≈ \(String(format: "%.3f", avgScale * 3600)) arcsec/pixel)")
        }
    }

    print("\n" + String(repeating: "=", count: 80))
    print("✨ Test complete! Check FITS_METADATA_GUIDE.md for field explanations")
    print(String(repeating: "=", count: 80) + "\n")

    exit(0)
}

// Keep the program running
RunLoop.main.run()
