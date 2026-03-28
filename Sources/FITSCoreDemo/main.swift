//
//  main.swift
//  FITSCoreDemo
//
//  Demonstrates the full capabilities of FITSKit/FITSCore for analyzing FITS files.
//  This script shows how to:
//    1. Open and read FITS files
//    2. List all HDUs (Header Data Units) and identify their types
//    3. Read headers from each HDU
//    4. Access data from each HDU
//    5. Decode image HDUs to CGImage and save as JPEG/PNG
//    6. Read binary table and ASCII table data
//    7. Export table data to CSV
//

import CoreGraphics
import FITS
import FITSKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Helpers

/// Print a section divider with a title
func printSection(_ title: String) {
    print("\n" + String(repeating: "─", count: 72))
    print("  \(title)")
    print(String(repeating: "─", count: 72))
}

/// Print a sub-section title
func printSubSection(_ title: String) {
    print("\n  ┌─ \(title)")
}

/// Clean a FITS string value (remove quotes, trim whitespace)
func cleanString(_ raw: String?) -> String {
    guard let raw = raw else { return "" }
    return
        raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "'", with: "")
        .trimmingCharacters(in: .whitespaces)
}

/// Format byte count into human-readable size
func humanReadableSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024.0
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024.0
    if mb < 1024 { return String(format: "%.1f MB", mb) }
    let gb = mb / 1024.0
    return String(format: "%.1f GB", gb)
}

// MARK: - 1. Opening a FITS File

/// Demonstrates how to open/read a FITS file from disk.
///
/// FITSKit reads a FITS file by:
///   1. Loading the file into a `Data` buffer
///   2. Parsing it with `FitsFile.read(_:)` which returns an optional `FitsFile`
///
/// The `FitsFile` object contains:
///   - `prime`: The Primary HDU (always present in every FITS file)
///   - `HDUs`: An array of extension HDUs (images, binary tables, ASCII tables)
func openFitsFile(at path: String) -> FitsFile? {
    let url = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: path) else {
        print("  ERROR: File not found: \(path)")
        return nil
    }

    guard let data = try? Data(contentsOf: url) else {
        print("  ERROR: Could not read file data")
        return nil
    }

    guard let fits = FitsFile.read(data) else {
        print("  ERROR: Could not parse FITS structure")
        return nil
    }

    print("  File size: \(humanReadableSize(data.count))")
    return fits
}

// MARK: - 2. Listing HDUs and Identifying Types

/// Identifies the type of an HDU based on its class and XTENSION keyword.
///
/// FITS HDU types:
///   - **PrimaryHDU**: Always the first HDU. May contain image data or just headers.
///   - **ImageHDU**: An image extension (XTENSION = 'IMAGE')
///   - **BintableHDU**: A binary table (XTENSION = 'BINTABLE')
///   - **TableHDU**: An ASCII table (XTENSION = 'TABLE')
///   - **AnyHDU**: Unknown/generic extension
func identifyHDUType(_ hdu: AnyHDU) -> String {
    switch hdu {
    case is PrimaryHDU:
        return "PRIMARY"
    case is ImageHDU:
        return "IMAGE"
    case is BintableHDU:
        return "BINTABLE"
    case is TableHDU:
        return "ASCII TABLE"
    default:
        return "UNKNOWN"
    }
}

/// Lists all HDUs in a FITS file and summarizes their properties.
///
/// Every FITS file has at least one HDU (the Primary HDU). Each HDU has:
///   - A header unit: collection of keyword=value pairs (80-char records)
///   - An optional data unit: the actual image/table/binary data
func listHDUs(fits: FitsFile) {
    printSection("HDU Inventory")

    // The Primary HDU
    let primeDataSize = fits.prime.dataUnit?.count ?? 0
    let primeNaxis = fits.prime.naxis ?? 0
    print("  HDU #0  [PRIMARY]")
    print("         NAXIS: \(primeNaxis), BITPIX: \(fits.prime.bitpix?.rawValue ?? 0)")
    print("         Data size: \(humanReadableSize(primeDataSize))")
    print("         Headers: \(fits.prime.headerUnit.count) records")

    if primeNaxis >= 2 {
        let width = fits.prime.naxis(1) ?? 0
        let height = fits.prime.naxis(2) ?? 0
        print("         Dimensions: \(width) x \(height)", terminator: "")
        if primeNaxis >= 3 {
            let depth = fits.prime.naxis(3) ?? 0
            print(" x \(depth) (color channels or slices)")
        } else {
            print(" (grayscale)")
        }
    }

    // Extension HDUs
    for (index, hdu) in fits.HDUs.enumerated() {
        let hduType = identifyHDUType(hdu)
        let dataSize = hdu.dataUnit?.count ?? 0
        let naxis = hdu.naxis ?? 0
        let extname = hdu.extname ?? "(unnamed)"

        print("\n  HDU #\(index + 1)  [\(hduType)] \"\(cleanString(extname))\"")
        print("         NAXIS: \(naxis), BITPIX: \(hdu.bitpix?.rawValue ?? 0)")
        print("         Data size: \(humanReadableSize(dataSize))")
        print("         Headers: \(hdu.headerUnit.count) records")

        // Type-specific info
        if let imageHDU = hdu as? ImageHDU {
            let width = imageHDU.naxis(1) ?? 0
            let height = imageHDU.naxis(2) ?? 0
            if naxis >= 2 && width > 0 && height > 0 {
                print("         Image size: \(width) x \(height) pixels")
            }
        } else if let bintable = hdu as? BintableHDU {
            let nrows = bintable.naxis(2) ?? 0
            let ncols = bintable.tfields ?? 0
            print("         Table: \(nrows) rows x \(ncols) columns")
        } else if let table = hdu as? TableHDU {
            let nrows = table.naxis(2) ?? 0
            let ncols = table.tfields ?? 0
            print("         Table: \(nrows) rows x \(ncols) columns")
        }
    }
}

// MARK: - 3. Reading Headers

/// Reads and displays all header keyword-value-comment triplets from an HDU.
///
/// FITS headers are 80-character records with format:
///   KEYWORD = VALUE / COMMENT
///
/// Key properties of HeaderBlock:
///   - `keyword`: The HDUKeyword (accessible via `.rawValue` for the string name)
///   - `value`: An optional HDUValue (use `.toString` to get string representation)
///   - `comment`: An optional inline comment string
func readHeaders(hdu: AnyHDU, label: String, maxHeaders: Int = 30) {
    printSubSection("Headers for \(label)")

    let totalHeaders = hdu.headerUnit.count
    let displayCount = min(totalHeaders, maxHeaders)

    print("  │  Total header records: \(totalHeaders)")
    if totalHeaders > maxHeaders {
        print("  │  (Showing first \(maxHeaders) of \(totalHeaders))")
    }
    print("  │")
    print(
        "  │  \(pad("KEYWORD", 10))  \(pad("VALUE", 30))  COMMENT")
    print("  │  \(String(repeating: "─", count: 60))")

    for i in 0..<displayCount {
        let block = hdu.headerUnit[i]
        let keyword = block.keyword.rawValue
        let value = block.value?.toString ?? ""
        let comment = block.comment ?? ""

        // Skip blank/padding records
        if keyword.trimmingCharacters(in: .whitespaces).isEmpty && value.isEmpty { continue }

        let displayValue = value.count > 28 ? String(value.prefix(28)) + ".." : value
        let displayComment = comment.count > 30 ? String(comment.prefix(30)) + ".." : comment
        print("  │  \(pad(keyword, 10))  \(pad(displayValue, 30))  \(displayComment)")
    }
    print("  └")
}

/// Pad or truncate a string to a given width
func pad(_ string: String, _ width: Int) -> String {
    if string.count >= width {
        return String(string.prefix(width))
    }
    return string + String(repeating: " ", count: width - string.count)
}

// MARK: - 4. Accessing HDU Data

/// Shows how to access raw data from each HDU.
///
/// The data unit (`dataUnit`) is an optional `Data` (byte buffer).
/// For images, this contains pixel values in the format specified by BITPIX.
/// For tables, this contains row/column data in fixed-width or binary format.
///
/// BITPIX values:
///   8  = UInt8 (unsigned byte)
///   16 = Int16
///   32 = Int32
///   64 = Int64
///  -32 = Float32
///  -64 = Float64
func inspectData(hdu: AnyHDU, label: String) {
    printSubSection("Data Inspection for \(label)")

    guard let data = hdu.dataUnit, data.count > 0 else {
        print("  │  No data unit present (header-only HDU)")
        print("  └")
        return
    }

    let bitpix = hdu.bitpix?.rawValue ?? 0
    let naxis = hdu.naxis ?? 0
    let bytesPerPixel = abs(bitpix) / 8

    print("  │  Data size: \(humanReadableSize(data.count))")
    print("  │  BITPIX: \(bitpix) (\(bitpixDescription(bitpix)))")
    print("  │  NAXIS: \(naxis)")
    if bytesPerPixel > 0 {
        print("  │  Bytes per element: \(bytesPerPixel)")
        print("  │  Total elements: \(data.count / max(bytesPerPixel, 1))")
    }

    // Show first few raw bytes as hex
    let previewBytes = min(32, data.count)
    let hexPreview = data.withUnsafeBytes { ptr -> String in
        let bytes = ptr.bindMemory(to: UInt8.self)
        return (0..<previewBytes).map { String(format: "%02X", bytes[$0]) }.joined(separator: " ")
    }
    print("  │  First \(previewBytes) bytes (hex): \(hexPreview)")
    print("  └")
}

func bitpixDescription(_ bitpix: Int) -> String {
    switch bitpix {
    case 8: return "UInt8 - unsigned 8-bit integer"
    case 16: return "Int16 - signed 16-bit integer"
    case 32: return "Int32 - signed 32-bit integer"
    case 64: return "Int64 - signed 64-bit integer"
    case -32: return "Float32 - IEEE single-precision"
    case -64: return "Float64 - IEEE double-precision"
    default: return "unknown"
    }
}

// MARK: - 5. Image Decoding and Export

/// Decodes an image HDU to CGImage and saves it as JPEG.
///
/// FITSKit provides built-in decoders:
///   - `GrayscaleDecoder` : for 2D images (NAXIS=2)
///   - `RGB_Decoder<RGB>` : for 3D images (NAXIS=3, color)
///
/// Usage:
///   let image: CGImage = try hdu.decode(GrayscaleDecoder.self, ())
///   let image: CGImage = try hdu.decode(RGB_Decoder<RGB>.self, ())
///
/// The resulting CGImage can be saved to JPEG, PNG, TIFF, etc. via ImageIO.
func decodeAndSaveImage(hdu: AnyImageHDU, label: String, outputDir: URL) -> Bool {
    let naxis = hdu.naxis ?? 0
    let naxis1 = hdu.naxis(1) ?? 0
    let naxis2 = hdu.naxis(2) ?? 0
    let hasData = (hdu.dataUnit?.count ?? 0) > 0

    guard naxis >= 2 && naxis1 > 0 && naxis2 > 0 && hasData else {
        print("  │  Not a decodable image (NAXIS=\(naxis), \(naxis1)x\(naxis2), data=\(hasData))")
        return false
    }

    print("  │  Decoding \(naxis1)x\(naxis2) image (NAXIS=\(naxis))...")

    do {
        let image: CGImage
        if naxis == 3 {
            // 3D data: color image (e.g., RGB channels)
            image = try hdu.decode(RGB_Decoder<RGB>.self, ())
            print("  │  Decoded as RGB color image")
        } else {
            // 2D data: grayscale image
            image = try hdu.decode(GrayscaleDecoder.self, ())
            print("  │  Decoded as grayscale image")
        }

        print("  │  CGImage: \(image.width)x\(image.height), \(image.bitsPerPixel) bpp")

        // Save as JPEG
        let jpegPath = outputDir.appendingPathComponent("\(label).jpg")
        if saveCGImage(image, format: UTType.jpeg, to: jpegPath) {
            print("  │  Saved JPEG: \(jpegPath.lastPathComponent)")
        }

        // Save as PNG (lossless)
        let pngPath = outputDir.appendingPathComponent("\(label).png")
        if saveCGImage(image, format: UTType.png, to: pngPath) {
            print("  │  Saved PNG: \(pngPath.lastPathComponent)")
        }

        return true
    } catch {
        print("  │  Decode failed: \(error)")
        return false
    }
}

/// Save a CGImage to disk in the specified format (JPEG, PNG, TIFF).
///
/// Uses Apple's ImageIO framework (CGImageDestination).
func saveCGImage(_ image: CGImage, format: UTType, to url: URL) -> Bool {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.identifier as CFString, 1, nil)
    else {
        return false
    }

    // For JPEG, set quality
    let properties: CFDictionary?
    if format == .jpeg {
        properties =
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
    } else {
        properties = nil
    }

    CGImageDestinationAddImage(destination, image, properties)
    return CGImageDestinationFinalize(destination)
}

// MARK: - 6. Binary Table Data Access

/// Reads data from a Binary Table HDU and displays it.
///
/// BintableHDU (XTENSION='BINTABLE') stores tabular data in compact binary format.
///
/// Key properties:
///   - `columns`: Array of `TableColumn<BFIELD>` — each column has:
///       - `TTYPE`: Column name (e.g., "RA", "DEC", "MAG")
///       - `TFORM`: Data format (e.g., BFORM.D for double, BFORM.A for string)
///       - `TUNIT`: Physical unit (e.g., "deg", "mag")
///       - `values`: Array of BFIELD values for each row
///   - `rows`: Array of `TableRow<BFIELD>` — each row gives access to all columns
///   - `tfields`: Number of columns
///   - `naxis(2)`: Number of rows
///
/// BFIELD types map to Swift types:
///   BFIELD.A → String (character)
///   BFIELD.I → Int16
///   BFIELD.J → Int32
///   BFIELD.K → Int64
///   BFIELD.E → Float
///   BFIELD.D → Double
///   BFIELD.L → Bool (logical)
func readBinaryTable(hdu: BintableHDU, label: String) {
    printSubSection("Binary Table: \(label)")

    let ncols = hdu.tfields ?? 0
    let nrows = hdu.naxis(2) ?? 0

    print("  │  Columns: \(ncols), Rows: \(nrows)")

    if hdu.columns.isEmpty {
        print("  │  (No column data parsed — table may use variable-length arrays)")
        print("  └")
        return
    }

    // Show column definitions
    print("  │")
    print("  │  Column Definitions:")
    print("  │  \(pad("#", 4))  \(pad("TTYPE (Name)", 20))  \(pad("TFORM (Format)", 16))  TUNIT")
    print("  │  \(String(repeating: "─", count: 56))")

    for (i, col) in hdu.columns.enumerated() {
        let name = col.TTYPE ?? "(unnamed)"
        let form = col.TFORM.map { "\($0)" } ?? "?"
        let unit = col.TUNIT ?? ""
        print("  │  \(pad("\(i)", 4))  \(pad(cleanString(name), 20))  \(pad(form, 16))  \(unit)")
    }

    // Show first few rows of data
    let displayRows = min(nrows, 5)
    if displayRows > 0 && !hdu.columns.isEmpty {
        print("  │")
        print("  │  First \(displayRows) rows of data:")

        // Column header line
        var headerLine = "  │  "
        for col in hdu.columns.prefix(8) {
            let name = cleanString(col.TTYPE ?? "?")
            headerLine += pad(String(name.prefix(14)), 16)
        }
        if hdu.columns.count > 8 { headerLine += "..." }
        print(headerLine)
        print("  │  \(String(repeating: "─", count: min(hdu.columns.count, 8) * 16))")

        // Data rows
        let rows = hdu.rows
        for rowIdx in 0..<min(displayRows, rows.count) {
            var line = "  │  "
            let row = rows[rowIdx]
            for colIdx in 0..<min(hdu.columns.count, 8) {
                let field = row[colIdx]
                let str = "\(field)"
                let truncated = str.count > 14 ? String(str.prefix(12)) + ".." : str
                line += pad(truncated, 16)
            }
            if hdu.columns.count > 8 { line += "..." }
            print(line)
        }
        if nrows > displayRows {
            print("  │  ... (\(nrows - displayRows) more rows)")
        }
    }
    print("  └")
}

// MARK: - 7. ASCII Table Data Access

/// Reads data from an ASCII Table HDU.
///
/// TableHDU (XTENSION='TABLE') stores tabular data in fixed-width ASCII format.
/// The API is the same as BintableHDU but uses TFIELD values instead of BFIELD.
///
/// TFIELD types:
///   TFIELD.A → Character string
///   TFIELD.I → Integer
///   TFIELD.F → Fixed-point float
///   TFIELD.E → Exponential float
///   TFIELD.D → Double-precision float
func readAsciiTable(hdu: TableHDU, label: String) {
    printSubSection("ASCII Table: \(label)")

    let ncols = hdu.tfields ?? 0
    let nrows = hdu.naxis(2) ?? 0

    print("  │  Columns: \(ncols), Rows: \(nrows)")

    if hdu.columns.isEmpty {
        print("  │  (No column data parsed)")
        print("  └")
        return
    }

    print("  │")
    print("  │  Column Definitions:")
    for (i, col) in hdu.columns.enumerated() {
        let name = col.TTYPE ?? "(unnamed)"
        let form = col.TFORM.map { "\($0)" } ?? "?"
        let unit = col.TUNIT ?? ""
        print("  │  [\(i)] \(cleanString(name)) — Format: \(form), Unit: \(unit)")
    }

    let displayRows = min(nrows, 5)
    if displayRows > 0 && !hdu.columns.isEmpty {
        print("  │")
        print("  │  Sample data (\(displayRows) rows):")
        let rows = hdu.rows
        for rowIdx in 0..<min(displayRows, rows.count) {
            let row = rows[rowIdx]
            var values: [String] = []
            for colIdx in 0..<hdu.columns.count {
                values.append("\(row[colIdx])")
            }
            print("  │  Row \(rowIdx): \(values.joined(separator: ", "))")
        }
    }
    print("  └")
}

// MARK: - 8. Export Table to CSV

/// Exports a Binary Table HDU to a CSV file.
///
/// This demonstrates converting FITS tabular data to a widely-usable format.
/// Each column's TTYPE becomes a CSV header, and BFIELD values are converted
/// to their string representations.
func exportBinaryTableToCSV(hdu: BintableHDU, label: String, outputDir: URL) {
    guard !hdu.columns.isEmpty else {
        print("  │  Cannot export: no column data")
        return
    }

    let csvPath = outputDir.appendingPathComponent("\(label).csv")
    var csvContent = ""

    // Header row: column names
    let headers = hdu.columns.map { cleanString($0.TTYPE ?? "col") }
    csvContent += headers.joined(separator: ",") + "\n"

    // Data rows
    let rows = hdu.rows
    for row in rows {
        var values: [String] = []
        for colIdx in 0..<hdu.columns.count {
            let field = row[colIdx]
            // Convert BFIELD to a CSV-safe string
            var str = "\(field)"
            // Escape commas and quotes for CSV
            if str.contains(",") || str.contains("\"") || str.contains("\n") {
                str = "\"" + str.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            values.append(str)
        }
        csvContent += values.joined(separator: ",") + "\n"
    }

    do {
        try csvContent.write(to: csvPath, atomically: true, encoding: .utf8)
        print("  │  Exported CSV: \(csvPath.lastPathComponent) (\(rows.count) rows)")
    } catch {
        print("  │  CSV export failed: \(error)")
    }
}

// MARK: - 9. Export Headers to JSON

/// Exports all headers from all HDUs to a JSON file.
///
/// This is useful for programmatic analysis of FITS metadata.
func exportHeadersToJSON(fits: FitsFile, fileName: String, outputDir: URL) {
    var allHeaders: [[String: String]] = []

    // Primary HDU headers
    var primeHeaders: [String: String] = ["_HDU": "PRIMARY"]
    for block in fits.prime.headerUnit {
        let key = block.keyword.rawValue.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { continue }
        primeHeaders[key] = block.value?.toString ?? ""
    }
    allHeaders.append(primeHeaders)

    // Extension HDU headers
    for (index, hdu) in fits.HDUs.enumerated() {
        var hduHeaders: [String: String] = ["_HDU": "EXT_\(index)_\(identifyHDUType(hdu))"]
        for block in hdu.headerUnit {
            let key = block.keyword.rawValue.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            hduHeaders[key] = block.value?.toString ?? ""
        }
        allHeaders.append(hduHeaders)
    }

    let jsonPath = outputDir.appendingPathComponent("\(fileName)_headers.json")
    do {
        let jsonData = try JSONSerialization.data(
            withJSONObject: allHeaders, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: jsonPath)
        print("  Exported headers JSON: \(jsonPath.lastPathComponent)")
    } catch {
        print("  JSON export failed: \(error)")
    }
}

// MARK: - 10. Using the plot() method for table display

/// Demonstrates the built-in `plot(data:)` method on table HDUs.
///
/// `plot(data:)` writes a formatted ASCII table to a Data buffer, including:
///   - Column headers (TTYPE names)
///   - Aligned columns with formatted values
///   - Separator lines
func plotTable(hdu: AnyHDU, label: String) {
    printSubSection("Formatted Table Plot: \(label)")

    if let bintable = hdu as? BintableHDU {
        var outputData = Data()
        bintable.plot(data: &outputData)
        if let str = String(data: outputData, encoding: .ascii), !str.isEmpty {
            // Show first 20 lines
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
            let showLines = min(lines.count, 20)
            for i in 0..<showLines {
                print("  │  \(lines[i])")
            }
            if lines.count > showLines {
                print("  │  ... (\(lines.count - showLines) more lines)")
            }
        } else {
            print("  │  (plot produced no output)")
        }
    } else if let table = hdu as? TableHDU {
        var outputData = Data()
        table.plot(data: &outputData)
        if let str = String(data: outputData, encoding: .ascii), !str.isEmpty {
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
            let showLines = min(lines.count, 20)
            for i in 0..<showLines {
                print("  │  \(lines[i])")
            }
            if lines.count > showLines {
                print("  │  ... (\(lines.count - showLines) more lines)")
            }
        } else {
            print("  │  (plot produced no output)")
        }
    }
    print("  └")
}

// MARK: - Main: Full Analysis Pipeline

func analyzeFitsFile(path: String, outputDir: URL) {
    let fileName =
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

    printSection("FITS FILE ANALYSIS: \(fileName)")
    print("  Path: \(path)")

    // Step 1: Open the file
    guard let fits = openFitsFile(at: path) else { return }

    // Step 2: List all HDUs
    listHDUs(fits: fits)

    // Step 3: Read headers from Primary HDU
    readHeaders(hdu: fits.prime, label: "PRIMARY HDU (#0)")

    // Step 4: Inspect Primary HDU data
    inspectData(hdu: fits.prime, label: "PRIMARY HDU (#0)")

    // Step 5: Try to decode and save Primary HDU image
    let primeNaxis = fits.prime.naxis ?? 0
    if primeNaxis >= 2 {
        printSubSection("Image Export: PRIMARY HDU")
        let success = decodeAndSaveImage(
            hdu: fits.prime, label: "\(fileName)_primary", outputDir: outputDir)
        if success {
            print("  └")
        } else {
            print("  │  Primary HDU is not a decodable image")
            print("  └")
        }
    }

    // Step 6: Process each extension HDU
    for (index, hdu) in fits.HDUs.enumerated() {
        let extLabel = "EXT #\(index + 1) (\(identifyHDUType(hdu)))"

        // Read headers (show first 15)
        readHeaders(hdu: hdu, label: extLabel, maxHeaders: 15)

        // Inspect data
        inspectData(hdu: hdu, label: extLabel)

        // Type-specific processing
        if let imageHDU = hdu as? ImageHDU {
            printSubSection("Image Export: \(extLabel)")
            let _ = decodeAndSaveImage(
                hdu: imageHDU,
                label: "\(fileName)_ext\(index + 1)",
                outputDir: outputDir
            )
            print("  └")
        } else if let bintable = hdu as? BintableHDU {
            readBinaryTable(hdu: bintable, label: extLabel)
            exportBinaryTableToCSV(
                hdu: bintable,
                label: "\(fileName)_ext\(index + 1)",
                outputDir: outputDir
            )
            plotTable(hdu: bintable, label: extLabel)
        } else if let table = hdu as? TableHDU {
            readAsciiTable(hdu: table, label: extLabel)
            plotTable(hdu: table, label: extLabel)
        }
    }

    // Step 7: Export all headers to JSON
    exportHeadersToJSON(fits: fits, fileName: fileName, outputDir: outputDir)
}

// MARK: - Entry Point

print(String(repeating: "═", count: 72))
print("  FITSCore / FITSKit — Capabilities Demonstration")
print("  Analyzing FITS files from Resources/fits/")
print(String(repeating: "═", count: 72))

// Create output directory for converted files
let outputDir = URL(fileURLWithPath: "Resources/results/fits_demo_output")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Gather all .fits files
let fitsDir = "Resources/fits"
var fitsFiles: [String] = []

if CommandLine.arguments.count > 1 {
    // Allow specifying files via command line
    fitsFiles = CommandLine.arguments.dropFirst().map { arg in
        if arg.contains("/") { return arg }
        return "\(fitsDir)/\(arg)"
    }
} else {
    // Default: analyze all .fits files in the directory
    if let contents = try? FileManager.default.contentsOfDirectory(atPath: fitsDir) {
        fitsFiles = contents.filter { $0.hasSuffix(".fits") }.sorted().map { "\(fitsDir)/\($0)" }
    }
}

if fitsFiles.isEmpty {
    print("\nNo FITS files found. Place .fits files in \(fitsDir)/")
    print("Or pass file paths as arguments: swift run FITSCoreDemo myfile.fits")
} else {
    print("\nFound \(fitsFiles.count) FITS file(s) to analyze.\n")

    for filePath in fitsFiles {
        analyzeFitsFile(path: filePath, outputDir: outputDir)
    }
}

print("\n" + String(repeating: "═", count: 72))
print("  Analysis Complete!")
print("  Output files saved to: \(outputDir.path)")
print(String(repeating: "═", count: 72))
