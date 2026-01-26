//
//  main.swift
//  TestM31Metadata
//
//  Test script to download FITS imagery and extract metadata for multiple targets
//

import Foundation
import SwiftMAST

print("Starting FITS Metadata Extraction Test\n")

let mast = SwiftMAST()

// Test targets
let targetNames = ["M31"]
var currentIndex = 0

func processTarget(_ targetName: String, completion: @escaping () -> Void) {
    print("\n" + String(repeating: "=", count: 80))
    print("Processing target: \(targetName)")
    print(String(repeating: "=", count: 80) + "\n")

    print("Downloading imagery for \(targetName)...\n")

    // Download FITS files
    // Using default science filter options and requesting FITS files
    mast.downloadImagery(
        targetName: targetName,
        productType: .Fits,  // Download FITS files and convert to JPEG
        filterOptions: .defaultScience,
        pageSize: 2,  // Limit to 2 per target for testing
        token: nil
    ) { urls in
        print("\nDownload complete for \(targetName)!")
        print("Downloaded \(urls.count) files\n")

        // Print download logs
        print("\nDownload logs:")
        print(String(repeating: "-", count: 60))
        for log in mast.sysLog {
            print(log.description)
        }
        print(String(repeating: "-", count: 60) + "\n")

        // Print all the URLs with their metadata
        for (index, url) in urls.enumerated() {
            print("[\(index + 1)] \(url.lastPathComponent)")

            // Get metadata for this specific URL
            if let metadata = mast.getFitsMetadata(target: targetName, forUrl: url) {
                print(
                    "    NAXIS: \(metadata.naxis ?? 0), Dimensions: \(metadata.dimensionDescription)"
                )
                if let filter = metadata.filter {
                    print("    Filter: \(filter)")
                }
                if let expTime = metadata.exposureTime {
                    print("    Exposure: \(String(format: "%.2f", expTime))s")
                }
                if let telescope = metadata.telescope {
                    print("    Telescope: \(telescope)")
                }
                if let instrument = metadata.instrument {
                    print("    Instrument: \(instrument)")
                }
            } else {
                print("   No metadata found for this file.")
            }
        }

        print("\n" + String(repeating: "-", count: 60))
        print("FITS METADATA ANALYSIS for \(targetName)")
        print(String(repeating: "-", count: 60) + "\n")

        // Print all extracted metadata
        mast.printFitsMetadata(target: targetName)

        // Get metadata as dictionary keyed by URL
        let metadataByUrl = mast.getFitsMetadata(target: targetName, forUrls: urls)

        print("\nMetadata lookup by URL: \(metadataByUrl.count)/\(urls.count) URLs have metadata")

        // Access the metadata programmatically
        if let metadataList = mast.getFitsMetadata(target: targetName) {
            // Save metadata to JSON file
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(metadataList) {
                let safeTargetName = targetName.replacingOccurrences(of: " ", with: "_")
                let fileURL = URL(fileURLWithPath: "\(safeTargetName)_metadata.json")
                try? data.write(to: fileURL)
                print("Metadata written to \(safeTargetName)_metadata.json")
            }

            print("\nMETADATA STATISTICS for \(targetName)")
            print(String(repeating: "-", count: 40))

            // Analyze dimensions
            let dimensions = metadataList.compactMap { $0.naxis }
            if !dimensions.isEmpty {
                print("\nDimension Analysis:")
                let dim2D = dimensions.filter { $0 == 2 }.count
                let dim3D = dimensions.filter { $0 == 3 }.count
                print("  - 2D Images: \(dim2D)")
                print("  - 3D Images: \(dim3D)")
            }

            // Analyze filters
            let filters = metadataList.compactMap { $0.filter }
            if !filters.isEmpty {
                let uniqueFilters = Set(filters)
                print("\nFilters Used: \(uniqueFilters.sorted().joined(separator: ", "))")
            }

            // Analyze telescopes
            let telescopes = metadataList.compactMap { $0.telescope }
            if !telescopes.isEmpty {
                let uniqueTelescopes = Set(telescopes)
                print("\nTelescopes: \(uniqueTelescopes.sorted().joined(separator: ", "))")
            }

            // Analyze instruments
            let instruments = metadataList.compactMap { $0.instrument }
            if !instruments.isEmpty {
                let uniqueInstruments = Set(instruments)
                print("\nInstruments: \(uniqueInstruments.sorted().joined(separator: ", "))")
            }

            // Exposure times
            let exposureTimes = metadataList.compactMap { $0.exposureTime }
            if !exposureTimes.isEmpty {
                let avgExposure = exposureTimes.reduce(0, +) / Double(exposureTimes.count)
                let minExposure = exposureTimes.min() ?? 0
                let maxExposure = exposureTimes.max() ?? 0
                print("\nExposure Times:")
                print("  - Average: \(String(format: "%.2f", avgExposure)) s")
                print("  - Min: \(String(format: "%.2f", minExposure)) s")
                print("  - Max: \(String(format: "%.2f", maxExposure)) s")
            }

            // WCS information
            let wcsImages = metadataList.filter { $0.crval1 != nil && $0.crval2 != nil }
            print("\nWorld Coordinate System:")
            print("  - Images with WCS: \(wcsImages.count)/\(metadataList.count)")

            // Pixel scales
            let pixelScales = metadataList.compactMap { $0.cdelt1 }
            if !pixelScales.isEmpty {
                let avgScale = abs(pixelScales.reduce(0, +) / Double(pixelScales.count))
                print("  - Average pixel scale: \(String(format: "%.6f", avgScale))°/pixel")
                print("    (≈ \(String(format: "%.3f", avgScale * 3600)) arcsec/pixel)")
            }
        }

        completion()
    }
}

func processNextTarget() {
    if currentIndex < targetNames.count {
        let target = targetNames[currentIndex]
        currentIndex += 1
        processTarget(target) {
            processNextTarget()
        }
    } else {
        print("\n" + String(repeating: "=", count: 80))
        print("All targets processed!")
        print("   Tested: \(targetNames.joined(separator: ", "))")
        print("   Check FITS_METADATA_GUIDE.md for field explanations")
        print(String(repeating: "=", count: 80) + "\n")
        exit(0)
    }
}

// Start processing targets
processNextTarget()

// Keep the program running
RunLoop.main.run()
