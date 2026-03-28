# FITSKit / FITSCore — Capabilities Guide

A comprehensive guide to working with FITS (Flexible Image Transport System) files in Swift using the **FITSKit** library (which wraps FITSCore). This document covers the full API surface for reading, inspecting, and converting FITS data.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Core Concepts](#core-concepts)
- [1. Opening a FITS File](#1-opening-a-fits-file)
- [2. HDU Structure — Listing and Identifying](#2-hdu-structure--listing-and-identifying)
- [3. Reading Headers](#3-reading-headers)
- [4. Accessing Raw Data](#4-accessing-raw-data)
- [5. Image Decoding](#5-image-decoding)
- [6. Saving Images (JPEG, PNG, TIFF)](#6-saving-images-jpeg-png-tiff)
- [7. Binary Table Access](#7-binary-table-access)
- [8. ASCII Table Access](#8-ascii-table-access)
- [9. Exporting Data](#9-exporting-data)
- [10. Formatted Table Display](#10-formatted-table-display)
- [API Quick Reference](#api-quick-reference)
- [Running the Demo](#running-the-demo)

---

## Overview

**FITS** (Flexible Image Transport System) is the standard file format in astronomy for storing images, tables, and metadata. A FITS file is organized into **HDUs (Header Data Units)**, each containing a header (keyword-value metadata) and an optional data section.

**FITSKit** is a Swift library that can:
- Parse FITS files into structured Swift objects
- Decode image data into `CGImage` for display or export
- Read binary and ASCII table data with typed column access
- Write/modify FITS files
- Format tables for display

### Imports

```swift
import FITS      // Core types: FitsFile, HDU classes, HeaderUnit, etc.
import FITSKit   // Extended functionality: image decoders (GrayscaleDecoder, RGB_Decoder)
```

---

## Setup

The library is included via Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ifeLight/fitskit.git", branch: "master"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "FITSKit", package: "fitskit"),
        ]),
]
```

---

## Core Concepts

### FITS File Structure

```
┌──────────────────────────┐
│  FitsFile                │
│  ├── prime (PrimaryHDU)  │  ← Always present; may contain image data or just headers
│  └── HDUs: [AnyHDU]      │  ← Zero or more extension HDUs
│       ├── ImageHDU        │  ← Image extension (XTENSION='IMAGE')
│       ├── BintableHDU     │  ← Binary table (XTENSION='BINTABLE')
│       └── TableHDU        │  ← ASCII table (XTENSION='TABLE')
└──────────────────────────┘
```

### HDU Components

Each HDU has two parts:

| Component | Type | Description |
|-----------|------|-------------|
| `headerUnit` | `HeaderUnit` | Collection of 80-char keyword=value records |
| `dataUnit` | `DataUnit?` | Raw binary data (pixels, table rows, etc.) |

### Key Header Keywords

| Keyword | Meaning |
|---------|---------|
| `SIMPLE` | `T` if file conforms to FITS standard |
| `BITPIX` | Data type: 8=UInt8, 16=Int16, 32=Int32, -32=Float32, -64=Float64 |
| `NAXIS` | Number of data axes (0=no data, 2=image, 3=color image) |
| `NAXIS1` | Size of axis 1 (width in pixels, or row length in bytes) |
| `NAXIS2` | Size of axis 2 (height in pixels, or number of rows) |
| `NAXIS3` | Size of axis 3 (color channels or spectral slices) |
| `XTENSION` | Extension type: `'IMAGE'`, `'BINTABLE'`, or `'TABLE'` |
| `EXTNAME` | Extension name (e.g., `'SCI'`, `'ERR'`, `'DQ'`) |
| `TFIELDS` | Number of columns in a table extension |
| `TTYPE*n*` | Column name for column *n* |
| `TFORM*n*` | Data format for column *n* |

---

## 1. Opening a FITS File

```swift
import FITS
import Foundation

let url = URL(fileURLWithPath: "path/to/file.fits")
let data = try Data(contentsOf: url)

guard let fits = FitsFile.read(data) else {
    print("Failed to parse FITS file")
    return
}

// The file is now accessible:
// fits.prime  — the Primary HDU
// fits.HDUs   — array of extension HDUs
```

**Key points:**
- `FitsFile.read(_:)` takes a `Data` buffer and returns an optional `FitsFile`
- Returns `nil` if the file is malformed or not a valid FITS file
- The entire file is parsed into memory on read

---

## 2. HDU Structure — Listing and Identifying

### Accessing HDUs

```swift
// Primary HDU (always present)
let primary = fits.prime

// Extension HDUs
let extensions = fits.HDUs              // [AnyHDU]
let extensionCount = fits.HDUs.count

// Iterate all extensions
for (index, hdu) in fits.HDUs.enumerated() {
    print("Extension #\(index): \(type(of: hdu))")
}
```

### Identifying HDU Types

```swift
for hdu in fits.HDUs {
    switch hdu {
    case let img as ImageHDU:
        print("Image extension: \(img.naxis(1) ?? 0) x \(img.naxis(2) ?? 0)")
    case let bin as BintableHDU:
        print("Binary table: \(bin.tfields ?? 0) columns, \(bin.naxis(2) ?? 0) rows")
    case let tbl as TableHDU:
        print("ASCII table: \(tbl.tfields ?? 0) columns")
    default:
        print("Unknown HDU type")
    }
}
```

### HDU Type Hierarchy

```
AnyHDU (base class)
├── AnyImageHDU
│   ├── PrimaryHDU      (fits.prime)
│   └── ImageHDU         (XTENSION='IMAGE')
└── AnyTableHDU<F>
    ├── BintableHDU      (XTENSION='BINTABLE')
    └── TableHDU         (XTENSION='TABLE')
```

### Common AnyHDU Properties

```swift
hdu.naxis           // Int? — number of axes
hdu.naxis(1)        // Int? — size of axis 1
hdu.naxis(2)        // Int? — size of axis 2
hdu.bitpix          // BITPIX? — data type enum
hdu.extname         // String? — extension name
hdu.bscale          // Float? — data scaling factor (default 1.0)
hdu.bzero           // Float? — data zero offset (default 0.0)
hdu.bunit           // String? — physical unit of data
hdu.headerUnit      // HeaderUnit — all header records
hdu.dataUnit        // DataUnit? — raw data bytes
```

---

## 3. Reading Headers

### Iterating All Header Records

```swift
for block in fits.prime.headerUnit {
    let keyword = block.keyword.rawValue   // String, e.g., "TELESCOP"
    let value = block.value?.toString      // String?, e.g., "'JWST    '"
    let comment = block.comment            // String?, e.g., "Telescope name"
    
    print("\(keyword) = \(value ?? "") / \(comment ?? "")")
}
```

### HeaderBlock Properties

| Property | Type | Description |
|----------|------|-------------|
| `keyword` | `HDUKeyword` | Keyword name (access via `.rawValue`) |
| `value` | `HDUValue?` | Value (access via `.toString`) |
| `comment` | `String?` | Inline comment |
| `isEnd` | `Bool` | True if this is the END marker |
| `isComment` | `Bool` | True if this is a COMMENT record |
| `isXtension` | `Bool` | True if this defines an extension type |

### Type-Safe Keyword Access

```swift
// Access header values by keyword with type casting
let headerUnit = fits.prime.headerUnit

// Get a typed value directly
let naxis: Int? = headerUnit[HDUKeyword.NAXIS]
let bitpix: BITPIX? = fits.prime.bitpix
```

### Collecting Metadata into a Dictionary

```swift
var metadata: [String: String] = [:]
for block in hdu.headerUnit {
    let key = block.keyword.rawValue.trimmingCharacters(in: .whitespaces)
    if !key.isEmpty {
        metadata[key] = block.value?.toString ?? ""
    }
}
```

---

## 4. Accessing Raw Data

### Check Data Presence

```swift
// dataUnit is optional — nil means header-only HDU
if let data = hdu.dataUnit {
    print("Data size: \(data.count) bytes")
} else {
    print("No data in this HDU")
}
```

### Interpret Raw Bytes

The `DataUnit` protocol provides `withUnsafeBytes` and typed subscripts:

```swift
// Read data as a specific type using subscript
if let data = hdu.dataUnit {
    // Read as array of a specific byte type
    let floatValues: [Float] = data[0..<100]   // First 100 Float values
    let intValues: [Int16] = data[0..<50]       // First 50 Int16 values

    // Read a single value at an offset
    let singleFloat: Float = data[0]
    
    // Raw byte access
    data.withUnsafeBytes { ptr in
        let bytes = ptr.bindMemory(to: UInt8.self)
        // Access bytes[0], bytes[1], etc.
    }
}
```

### BITPIX Data Type Mapping

| BITPIX Value | Swift Type | Description |
|--------------|-----------|-------------|
| 8 | `UInt8` | Unsigned 8-bit integer |
| 16 | `Int16` | Signed 16-bit integer |
| 32 | `Int32` | Signed 32-bit integer |
| 64 | `Int64` | Signed 64-bit integer |
| -32 | `Float` | IEEE 754 single-precision |
| -64 | `Double` | IEEE 754 double-precision |

---

## 5. Image Decoding

FITSKit provides decoders that convert FITS image data directly to `CGImage`.

### Grayscale Images (NAXIS=2)

```swift
import FITSKit
import CoreGraphics

// From Primary HDU
let image: CGImage = try fits.prime.decode(GrayscaleDecoder.self, ())

// From ImageHDU extension
if let imageHDU = hdu as? ImageHDU {
    let image: CGImage = try imageHDU.decode(GrayscaleDecoder.self, ())
    print("Decoded: \(image.width) x \(image.height)")
}
```

### Color Images (NAXIS=3)

```swift
// RGB color image (3 channels)
let colorImage: CGImage = try fits.prime.decode(RGB_Decoder<RGB>.self, ())
```

### Choosing the Right Decoder

```swift
func decodeImage(from hdu: AnyImageHDU) throws -> CGImage {
    let naxis = hdu.naxis ?? 0
    
    if naxis == 3 {
        return try hdu.decode(RGB_Decoder<RGB>.self, ())
    } else {
        return try hdu.decode(GrayscaleDecoder.self, ())
    }
}
```

### Checking if an HDU Contains a Decodable Image

```swift
func isDecodableImage(_ hdu: AnyHDU) -> Bool {
    let naxis = hdu.naxis ?? 0
    let naxis1 = hdu.naxis(1) ?? 0
    let naxis2 = hdu.naxis(2) ?? 0
    let hasData = (hdu.dataUnit?.count ?? 0) > 0
    
    return naxis >= 2 && naxis1 > 0 && naxis2 > 0 && hasData
}
```

---

## 6. Saving Images (JPEG, PNG, TIFF)

Once decoded to `CGImage`, use Apple's **ImageIO** framework to save:

```swift
import ImageIO
import UniformTypeIdentifiers

func saveCGImage(_ image: CGImage, format: UTType, to url: URL, quality: CGFloat = 0.9) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, format.identifier as CFString, 1, nil
    ) else { return false }
    
    var properties: CFDictionary? = nil
    if format == .jpeg {
        properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    }
    
    CGImageDestinationAddImage(destination, image, properties)
    return CGImageDestinationFinalize(destination)
}

// Usage
let image = try fits.prime.decode(GrayscaleDecoder.self, ())
saveCGImage(image, format: .jpeg, to: URL(fileURLWithPath: "output.jpg"))
saveCGImage(image, format: .png, to: URL(fileURLWithPath: "output.png"))
saveCGImage(image, format: .tiff, to: URL(fileURLWithPath: "output.tiff"))
```

### Supported Output Formats

| Format | UTType | Lossy? | Best For |
|--------|--------|--------|----------|
| JPEG | `.jpeg` | Yes | Web/previews |
| PNG | `.png` | No | Lossless archival |
| TIFF | `.tiff` | No | Scientific/print |

---

## 7. Binary Table Access

Binary tables (`BintableHDU`, XTENSION='BINTABLE') store tabular data in compact binary format.

### Column Access

```swift
if let bintable = hdu as? BintableHDU {
    // Number of columns and rows
    let ncols = bintable.tfields ?? 0
    let nrows = bintable.naxis(2) ?? 0
    
    // Iterate columns
    for (i, column) in bintable.columns.enumerated() {
        let name = column.TTYPE ?? "(unnamed)"    // Column name
        let format = column.TFORM                  // Data format (BFORM enum)
        let unit = column.TUNIT ?? ""              // Physical unit
        
        print("Column \(i): \(name)  Format: \(format)  Unit: \(unit)")
        
        // Access column values
        for value in column.values {
            print("  \(value)")
        }
    }
}
```

### Row Access

```swift
if let bintable = hdu as? BintableHDU {
    let rows = bintable.rows
    
    for (i, row) in rows.enumerated() {
        // Access cells by column index
        let firstCol = row[0]
        let secondCol = row[1]
        
        // Get all values in the row
        let allValues = row.values
        
        // Get column format info for a cell
        let format = row.TFORM(0)  // BFORM of first column
    }
}
```

### BFIELD Data Types (Binary Table Columns)

| BFIELD Type | BFORM Code | Swift Equivalent | Description |
|-------------|-----------|-----------------|-------------|
| `BFIELD.L` | `L` | `Bool` | Logical |
| `BFIELD.B` | `B` | `UInt8` | Unsigned byte |
| `BFIELD.I` | `I` | `Int16` | 16-bit integer |
| `BFIELD.J` | `J` | `Int32` | 32-bit integer |
| `BFIELD.K` | `K` | `Int64` | 64-bit integer |
| `BFIELD.A` | `A` | `String` | Character string |
| `BFIELD.E` | `E` | `Float` | Single-precision |
| `BFIELD.D` | `D` | `Double` | Double-precision |
| `BFIELD.C` | `C` | Complex | Single complex |
| `BFIELD.M` | `M` | Complex | Double complex |
| `BFIELD.P*` | `P*` | Array | Variable-length |

---

## 8. ASCII Table Access

ASCII tables (`TableHDU`, XTENSION='TABLE') have the same API but use `TFIELD` instead of `BFIELD`.

```swift
if let table = hdu as? TableHDU {
    for column in table.columns {
        let name = column.TTYPE ?? "(unnamed)"
        let format = column.TFORM       // TFORM enum (A, I, F, E, D)
        let unit = column.TUNIT ?? ""
        
        print("Column: \(name)  Format: \(format)  Unit: \(unit)")
        
        for value in column.values {
            print("  \(value)")
        }
    }
    
    // Row access works identically
    for row in table.rows {
        print(row.values)
    }
}
```

### TFIELD Data Types (ASCII Table Columns)

| TFIELD Type | TFORM Code | Description |
|-------------|-----------|-------------|
| `TFIELD.A` | `Aw` | Character string (width w) |
| `TFIELD.I` | `Iw` | Integer (width w) |
| `TFIELD.F` | `Fw.d` | Fixed-point float |
| `TFIELD.E` | `Ew.d` | Exponential float |
| `TFIELD.D` | `Dw.d` | Double precision |

---

## 9. Exporting Data

### Export Table to CSV

```swift
func exportToCSV(table: BintableHDU, to url: URL) throws {
    var csv = ""
    
    // Header row
    let headers = table.columns.map { 
        ($0.TTYPE ?? "col").trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "'", with: "")
    }
    csv += headers.joined(separator: ",") + "\n"
    
    // Data rows
    for row in table.rows {
        var values: [String] = []
        for i in 0..<table.columns.count {
            var str = "\(row[i])"
            // CSV-escape if needed
            if str.contains(",") || str.contains("\"") || str.contains("\n") {
                str = "\"" + str.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            values.append(str)
        }
        csv += values.joined(separator: ",") + "\n"
    }
    
    try csv.write(to: url, atomically: true, encoding: .utf8)
}
```

### Export Headers to JSON

```swift
func exportHeadersToJSON(fits: FitsFile, to url: URL) throws {
    var allHeaders: [[String: String]] = []
    
    // Primary HDU
    var primeHeaders: [String: String] = ["_HDU": "PRIMARY"]
    for block in fits.prime.headerUnit {
        let key = block.keyword.rawValue.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            primeHeaders[key] = block.value?.toString ?? ""
        }
    }
    allHeaders.append(primeHeaders)
    
    // Extensions
    for (i, hdu) in fits.HDUs.enumerated() {
        var hduHeaders: [String: String] = ["_HDU": "EXT_\(i)"]
        for block in hdu.headerUnit {
            let key = block.keyword.rawValue.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                hduHeaders[key] = block.value?.toString ?? ""
            }
        }
        allHeaders.append(hduHeaders)
    }
    
    let jsonData = try JSONSerialization.data(
        withJSONObject: allHeaders, 
        options: [.prettyPrinted, .sortedKeys]
    )
    try jsonData.write(to: url)
}
```

---

## 10. Formatted Table Display

FITSKit has a built-in `plot(data:)` method for ASCII-formatted table display:

```swift
if let bintable = hdu as? BintableHDU {
    var output = Data()
    bintable.plot(data: &output)
    
    if let text = String(data: output, encoding: .ascii) {
        print(text)
    }
}
```

This produces a formatted table with column headers, separators, and aligned values.

---

## API Quick Reference

### FitsFile

| Method/Property | Returns | Description |
|----------------|---------|-------------|
| `FitsFile.read(_: Data)` | `FitsFile?` | Parse a FITS file from Data |
| `.prime` | `PrimaryHDU` | The primary HDU |
| `.HDUs` | `[AnyHDU]` | Extension HDU array |
| `.write(to: URL, ...)` | `Void` | Write FITS file to disk |
| `.validate(...)` | `Void` | Validate FITS structure |

### AnyHDU (Base)

| Property | Type | Description |
|----------|------|-------------|
| `.headerUnit` | `HeaderUnit` | Header records collection |
| `.dataUnit` | `DataUnit?` | Raw data bytes |
| `.naxis` | `Int?` | Number of axes |
| `.naxis(_: Int)` | `Int?` | Size of specific axis |
| `.bitpix` | `BITPIX?` | Data type |
| `.extname` | `String?` | Extension name |
| `.bscale` | `Float?` | Scale factor |
| `.bzero` | `Float?` | Zero offset |

### AnyImageHDU

| Method | Returns | Description |
|--------|---------|-------------|
| `.decode(GrayscaleDecoder.self, ())` | `CGImage` | Decode 2D grayscale |
| `.decode(RGB_Decoder<RGB>.self, ())` | `CGImage` | Decode 3D color |

### BintableHDU / TableHDU

| Property/Method | Type | Description |
|----------------|------|-------------|
| `.columns` | `[TableColumn]` | All columns |
| `.rows` | `[TableRow]` | All rows |
| `.tfields` | `Int?` | Number of columns |
| `.plot(data: &Data)` | `Void` | Format as ASCII table |

### TableColumn

| Property | Type | Description |
|----------|------|-------------|
| `.TTYPE` | `String?` | Column name |
| `.TFORM` | `FORM?` | Column data format |
| `.TUNIT` | `String?` | Physical unit |
| `.values` | `[FIELD]` | All values |
| `[index]` | `FIELD` | Value at row index |

### HeaderBlock

| Property | Type | Description |
|----------|------|-------------|
| `.keyword` | `HDUKeyword` | Keyword (use `.rawValue` for String) |
| `.value` | `HDUValue?` | Value (use `.toString` for String) |
| `.comment` | `String?` | Comment text |

---

## Running the Demo

The `FITSCoreDemo` executable demonstrates all of the above capabilities:

```bash
# Build
swift build --target FITSCoreDemo

# Run against all FITS files in Resources/fits/
swift run FITSCoreDemo

# Run against specific files
swift run FITSCoreDemo myfile.fits
swift run FITSCoreDemo Resources/fits/_UV_u27h0901t.fits
```

### What the Demo Does

1. **Opens** each FITS file and reports file size
2. **Lists all HDUs** with type, dimensions, and data size
3. **Displays headers** (keyword/value/comment) for each HDU
4. **Inspects raw data** — shows byte count, BITPIX type, first bytes
5. **Decodes images** — converts image HDUs to JPEG and PNG files
6. **Reads tables** — displays column definitions and sample data rows
7. **Exports CSV** — writes binary table data to CSV files
8. **Exports JSON** — writes all headers to a structured JSON file
9. **Plots tables** — uses the built-in `plot()` method for formatted display

### Output Location

All generated files (images, CSVs, JSON) are saved to:
```
Resources/results/fits_demo_output/
```

### Sample Output

```
═══════════════════════════════════════════
  FITSCore / FITSKit — Capabilities Demonstration
═══════════════════════════════════════════

────────────────────────────────────────────
  HDU Inventory
────────────────────────────────────────────
  HDU #0  [PRIMARY]
         NAXIS: 0, BITPIX: 8
         Data size: 0 B
         Headers: 24 records

  HDU #1  [IMAGE] "SCI"
         NAXIS: 2, BITPIX: -32
         Data size: 2.3 MB
         Image size: 1032 x 1024 pixels

  HDU #2  [IMAGE] "ERR"
         ...
```
