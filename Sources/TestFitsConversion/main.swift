//
//  main.swift
//  TestFitsConversion
//
//  Test script to verify FITS to JPEG conversion works
//

import CoreGraphics
import FITS
import FITSKit
import Foundation
import ImageIO
import SwiftQValue
import UniformTypeIdentifiers

print("Testing FITS to JPEG Conversion\n")

// Ensure FITS files are available in Resources/fits
let fitsDir = "Resources/fits"
let fileManager = FileManager.default
if let contents = try? fileManager.contentsOfDirectory(atPath: fitsDir) {
    let fitsFiles = contents.filter { $0.hasSuffix(".fits") }
    print("Available FITS files in \(fitsDir):")
    for file in fitsFiles {
        print(" - \(file)")
    }
    print()
} else {
    print("Warning: \(fitsDir) directory not found or empty. Please ensure FITS files are placed in \(fitsDir)/")
}

// FITS files to test - mix of different types
// For experimenting, you can pass filenames as command line arguments, e.g., swift run TestFitsConversion _UV_u27h0901t.fits
var testFiles: [String]
if CommandLine.arguments.count > 1 {
    testFiles = CommandLine.arguments.dropFirst().map { "Resources/fits/\($0)" }
} else {
    testFiles = [
        "Resources/fits/_UV_u27h0901t.fits",
        "Resources/fits/_INFRARED_jw05627-o003_t002_miri_f1500w.fits",
        "Resources/fits/_UV_hst_9422_01_acs_hrc_f220w_j8d001.fits",
        "Resources/fits/Aldebaran_PS1_i_2287753.fits",
    ]
}

func getStringValue(_ qvalue: QValue?) -> String {
    guard let qv = qvalue else { return "" }
    return String(describing: qv.value)
}

func saveCGImageToFile(image: CGImage, to outputPath: URL) -> Bool {
    guard
        let destination = CGImageDestinationCreateWithURL(
            outputPath as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else {
        return false
    }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func analyzeAndConvertFits(filePath: String) {
    print("\n" + String(repeating: "=", count: 70))
    print("Analyzing: \(filePath)")
    print(String(repeating: "=", count: 70))

    let url = URL(fileURLWithPath: filePath)

    guard FileManager.default.fileExists(atPath: filePath) else {
        print("File does not exist")
        return
    }

    guard let data = try? Data(contentsOf: url),
        let fits = FitsFile.read(data)
    else {
        print("Failed to read FITS file")
        return
    }

    print("\n HDU Summary:")
    print("   Total HDUs (extensions): \(fits.HDUs.count)")

    // First check the primary HDU
    var primeMetadata = [String: QValue]()
    for unit in fits.prime.headerUnit {
        primeMetadata[unit.keyword.rawValue] = QValue(
            value: (unit.value != nil) ? unit.value!.toString : "")
    }

    let primeNaxis = Int(getStringValue(primeMetadata["NAXIS"])) ?? 0
    let primeNaxis1 = Int(getStringValue(primeMetadata["NAXIS1"])) ?? 0
    let primeNaxis2 = Int(getStringValue(primeMetadata["NAXIS2"])) ?? 0
    let primeBitpix = getStringValue(primeMetadata["BITPIX"])
    let primeDataCount = fits.prime.dataUnit?.count ?? 0

    print("\n   PRIMARY HDU:")
    print(
        "      NAXIS=\(primeNaxis), NAXIS1=\(primeNaxis1), NAXIS2=\(primeNaxis2), BITPIX=\(primeBitpix)"
    )
    print("      Data size: \(primeDataCount) bytes")

    let isPrimaryImage =
        primeNaxis >= 2 && primeNaxis1 > 10 && primeNaxis2 > 10 && primeDataCount > 0
    print("      Is Image: \(isPrimaryImage)")

    if isPrimaryImage {
        print("      Attempting conversion of PRIMARY HDU...")

        let baseName = url.deletingPathExtension().lastPathComponent
        let outputPath = url.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_primary_converted.jpg")

        do {
            let image: CGImage
            if primeNaxis == 3 {
                image = try fits.prime.decode(RGB_Decoder<RGB>.self, ())
            } else {
                image = try fits.prime.decode(GrayscaleDecoder.self, ())
            }

            if saveCGImageToFile(image: image, to: outputPath) {
                print("      SUCCESS! Saved: \(outputPath.lastPathComponent)")
                print("         Full path: \(outputPath.path)")
                print("         Size: \(image.width) x \(image.height)")
                return
            } else {
                print("      Failed to save image")
            }

        } catch {
            print("      Conversion failed: \(error)")
        }
    }

    // Check extension HDUs and try to convert the first ImageHDU
    var convertedOne = false
    for (index, hdu) in fits.HDUs.enumerated() {
        var hduMetadata = [String: QValue]()
        for unit in hdu.headerUnit {
            hduMetadata[unit.keyword.rawValue] = QValue(
                value: (unit.value != nil) ? unit.value!.toString : "")
        }

        let naxis = getStringValue(hduMetadata["NAXIS"])
        let naxisValue = Int(naxis) ?? 0
        let naxis1 = getStringValue(hduMetadata["NAXIS1"])
        let naxis1Value = Int(naxis1) ?? 0
        let naxis2 = getStringValue(hduMetadata["NAXIS2"])
        let naxis2Value = Int(naxis2) ?? 0
        let xtension = getStringValue(hduMetadata["XTENSION"])
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
        let bitpix = getStringValue(hduMetadata["BITPIX"])

        let hduDataCount = hdu.dataUnit?.count ?? 0
        let isExtensionImage = xtension == "image" && hduDataCount > 0

        print("\n   EXTENSION[\(index)]:")
        print("      Type: '\(xtension)'")
        print(
            "      NAXIS=\(naxisValue), NAXIS1=\(naxis1Value), NAXIS2=\(naxis2Value), BITPIX=\(bitpix)"
        )
        print("      Data size: \(hduDataCount) bytes")
        print("      Is Image Extension: \(isExtensionImage)")

        // Try to convert the first ImageHDU extension
        if isExtensionImage && !convertedOne {
            if let imageHDU = hdu as? ImageHDU {
                print("     Attempting conversion of Extension[\(index)]...")

                let baseName = url.deletingPathExtension().lastPathComponent
                let outputPath = url.deletingLastPathComponent()
                    .appendingPathComponent("\(baseName)_ext\(index)_converted.jpg")

                do {
                    let image: CGImage
                    if naxisValue == 3 {
                        image = try imageHDU.decode(RGB_Decoder<RGB>.self, ())
                    } else {
                        image = try imageHDU.decode(GrayscaleDecoder.self, ())
                    }

                    if saveCGImageToFile(image: image, to: outputPath) {
                        print("      SUCCESS! Saved: \(outputPath.lastPathComponent)")
                        print("         Full path: \(outputPath.path)")
                        print("         Size: \(image.width) x \(image.height)")
                        convertedOne = true
                    } else {
                        print("      Failed to save image")
                    }

                } catch {
                    print("      Conversion failed: \(error)")
                }
            } else {
                print("       HDU is not an ImageHDU, cannot convert")
            }
        }
    }

    if !convertedOne && !isPrimaryImage {
        print("\n    No convertible image data found in this file")
    }
}

// Test each file
for file in testFiles {
    analyzeAndConvertFits(filePath: file)
}

print("\n\n" + String(repeating: "=", count: 70))
print("Test Complete!")
print(String(repeating: "=", count: 70))
