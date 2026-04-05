# SwiftMAST

Swift wrapper for the [MAST](https://archive.stsci.edu/vo/mast_services.html#GET) archive of astronomical data 

This package is used for the [AstreOS](https://astreos.space) platform developed by Yuma Antoine Decaux.

## Introduction

The Mikulski Archive for Space Telescopes is an astronomical data archive focused on the optical, ultraviolet, and near-infrared. MAST hosts data from over a dozen missions like Webb, Hubble, TESS, Kepler, and in the future Roman.

The MAST archive allows searching for data in csv table and FITS file formats of:
. Missions
. High Level Science Products
. Simple image formats
. simple spectral data

The main format being used is the [FITS](https://www.loc.gov/preservation/digital/formats/fdd/fdd000317.shtml) file which is a souped up image format which is used from [NASA](https://www.nasa.gov) through to the Vatican for archiving annotated data.

This package depends on [FITSCore](https://github.com/brampf/fitscore) for opening/processing/saving data to and from FITS and other image formats.

## Log Subscriber API

SwiftMAST provides a logging system that allows external applications to subscribe to log events. This is useful for monitoring download progress, debugging, or integrating with your app's logging infrastructure.

### Subscribing to Logs

```swift
let mast = SwiftMAST()

// Subscribe to all log events
mast.subscribeToLogs(id: "myAppLogger") { logEntry in
    print("[\(logEntry.log)] \(logEntry.message) at \(logEntry.timecode)")
}

// Perform operations - your callback will receive log events
mast.downloadImagery(targetName: "M31", productType: .Jpeg) { urls in
    print("Downloaded \(urls.count) images")
}
```

### Filtering Log Events

You can filter logs by type in your callback:

```swift
mast.subscribeToLogs(id: "errorLogger") { logEntry in
    // Only handle errors
    if logEntry.log == .RequestError || logEntry.log == .Cancelled {
        print("Error: \(logEntry.message)")
    }
}
```

### Unsubscribing

```swift
// Unsubscribe a specific subscriber
mast.unsubscribeFromLogs(id: "myAppLogger")

// Or remove all subscribers
mast.clearLogSubscribers()
```

### MASTSyslog Structure

Each log entry contains:
- `log`: The log type (`MASTError` enum - `.OK`, `.RequestError`, `.Cancelled`, etc.)
- `message`: The log message string
- `timecode`: Formatted timestamp string
- `date`: The `Date` object when the log was created

## Science Image Query Utilities

You can resolve target coordinates, query for filtered science image results without downloading, then build a URL for a single result.

```swift
let mast = SwiftMAST()

mast.lookupTargetCoordinates(targetName: "M31") { coordinates in
    guard let coordinates = coordinates else {
        print("Could not resolve target")
        return
    }

    mast.getScienceImageQueryResults(
        targetName: "M31",
        filterOptions: .defaultScience,
        pageSize: 5,
        page: 1
    ) { results in
        print("Query returned \(results.count) products")

        if let first = results.first {
            mast.getScienceImageProductUrl(
                targetName: "M31",
                result: first,
                productType: .Fits
            ) { url in
                if let url = url {
                    print("Download URL: \(url)")
                } else {
                    print("No URL available for first result")
                }
            }
        } else {
            print("No results returned")
        }
    }
}
```

## Science Product Extraction

The `extractScienceProducts` API downloads a FITS file from MAST and extracts individual image HDUs into `ScienceProduct` objects, each with converted JPEG imagery and structured FITS headers.

### Basic Usage

```swift
let mast = SwiftMAST()
let coamResult = ... // from a MAST query

mast.extractScienceProducts(targetName: "M31", coamResult: coamResult) { products in
    for product in products {
        print(product.name)
        print("Image: \(product.imageLocation?.path ?? "none")")
        print("Headers: \(product.headers.count)")
    }
}
```

### ScienceProduct

Each `ScienceProduct` contains:
- `name` — display name derived from the source file and HDU index
- `imageLocation` — local URL of the saved JPEG (converted from the FITS image HDU)
- `sourceFileLocation` — local URL of the original FITS file
- `headers` — array of structured `FITSHeaderUnit` entries (primary + extension merged)
- `coamResult` — the originating `CoamResult`

### Structured FITS Headers (FITSHeaderUnit)

Headers are represented as an array of `FITSHeaderUnit` structs rather than raw dictionaries. Each entry provides typed values, keyword descriptions, and categorical enum metadata.

```swift
for header in product.headers {
    print("\(header.keyword): \(header.value) — \(header.keywordDescription)")

    if header.isCategorical, let desc = header.valueDescription {
        print("  Value meaning: \(desc)")
    }
    if let options = header.categoricalOptions {
        print("  Valid values: \(options.map { $0.value })")
    }
}

// Look up a specific header
if let bitpix = product.header(forKeyword: "BITPIX") {
    print(bitpix.value.intValue!)        // -32
    print(bitpix.keywordDescription)     // "Number of bits per data pixel"
    print(bitpix.valueDescription!)      // "IEEE 754 single-precision floating-point (32-bit)"
}
```

`FITSHeaderValue` is a typed enum (`.string`, `.integer`, `.double`, `.bool`) with convenience accessors `rawString`, `intValue`, and `doubleValue`. All header types are `Codable`.

### Categorical Enums

Four FITS standard keywords have well-defined categorical values, each modeled as a `Codable`, `CaseIterable`, `Identifiable` enum:

| Keyword | Enum | Values |
|---------|------|--------|
| `XTENSION` | `FITSXtension` | IMAGE, BINTABLE, TABLE, IUEIMAGE |
| `BITPIX` | `FITSBitpix` | 8, 16, 32, 64, -32, -64 |
| `RADESYS` | `FITSRaDesys` | ICRS, FK5, FK4, FK4-NO-E, GAPPT |
| `TIMESYS` | `FITSTimeSys` | UTC, UT1, TAI, TT, TDB, TCG, TCB, GPS |

```swift
// Enumerate all valid BITPIX values
for bp in FITSBitpix.allCases {
    print("\(bp.rawValue): \(bp.description) — \(bp.byteSize) bytes")
}

// Initialize from a raw FITS value
if let radesys = FITSRaDesys(fitsValue: "'ICRS    '") {
    print(radesys.description)
    // "International Celestial Reference System (current IAU standard)"
}
```

## JWST Filter-Band Products

`getJWSTFilteredProducts` queries MAST for public JWST science products (calibration levels 3–4) around a target and returns exactly one `CoamResult` per unique filter band. When multiple observations exist for the same filter the product closest to the median observation epoch is selected, so the returned set is as contemporaneous as possible.

### By target name

The target name is resolved via the MAST name resolver before querying.

```swift
let mast = SwiftMAST()

// All JWST instruments (NIRCam + MIRI)
mast.getJWSTFilteredProducts(targetName: "NGC 628") { products in
    for (filter, coam) in products.sorted(by: { $0.key < $1.key }) {
        print("\(filter)  \(coam.instrument_name)  \(coam.obs_id)")
    }
}
// F1000W  MIRI/IMAGE  jw02666-o007_t001_miri_f1000w
// F1130W  MIRI/IMAGE  jw02666-o007_t001_miri_f1130w
// F115W   NIRCAM/IMAGE  jw02107-o039_t018_nircam_clear-f115w
// …

// MIRI only
mast.getJWSTFilteredProducts(targetName: "NGC 253", instruments: ["MIRI/IMAGE"]) { products in
    for (filter, coam) in products {
        print("\(filter): \(coam.obs_id)")
    }
}
```

### By coordinates

Use the coordinate overload when you already have RA/Dec, bypassing the resolver step.

```swift
mast.getJWSTFilteredProducts(
    targetName: "NGC 628",
    ra: 24.174,
    dec: 15.783,
    radius: 0.2,
    instruments: ["NIRCAM/IMAGE"],
    calibLevels: ["3", "4"]
) { products in
    print("NIRCam filters: \(products.keys.sorted().joined(separator: ", "))")
}
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `targetName` | `String` | — | Human-readable target identifier |
| `ra` | `Float` | — | Right Ascension (degrees, J2000) — coordinate overload only |
| `dec` | `Float` | — | Declination (degrees, J2000) — coordinate overload only |
| `radius` | `Float` | — | Search radius (degrees) — coordinate overload only |
| `instruments` | `[String]?` | `nil` | Restrict to specific instruments, e.g. `["MIRI/IMAGE"]` or `["NIRCAM/IMAGE"]`. `nil` returns all. |
| `calibLevels` | `[String]` | `["3", "4"]` | CAOM calibration levels to include |
| `pageSize` | `Int` | `200` | Maximum products fetched per MAST page |
| `result` | `([String: CoamResult]) -> Void` | — | Callback receiving the filter → product dictionary |

### Return value

A `[String: CoamResult]` dictionary keyed by filter name (e.g. `"F770W"`, `"F1000W"`). Each value is a full `CoamResult` containing `obs_id`, `instrument_name`, `dataURL`, `t_min`/`t_max`, `filters`, and all other CAOM fields.

### ImageryFilterOptions presets

Two convenience presets are provided for building filter queries manually:

```swift
// JWST MIRI imaging
let miriOptions = ImageryFilterOptions.jwstMIRI
// collections: ["JWST"], instruments: ["MIRI/IMAGE"]

// JWST NIRCam imaging
let nircamOptions = ImageryFilterOptions.jwstNIRCam
// collections: ["JWST"], instruments: ["NIRCAM/IMAGE"]

// Use with getScienceImageQueryResults
mast.getScienceImageQueryResults(
    targetName: "NGC 628",
    filterOptions: .jwstMIRI,
    pageSize: 50,
    page: 1
) { results in
    print("MIRI products: \(results.count)")
}
```

