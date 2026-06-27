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

### File Logging and Request Telemetry

Logs are always kept in memory on `mast.sysLog`. To also append them to a file, enable file logging:

```swift
let mast = SwiftMAST()

// Defaults to Documents/SwiftMAST.log when no URL is supplied.
mast.enableFileLogging()

// Or provide your own destination.
mast.enableFileLogging(to: customLogURL)
```

MAST network requests log the request that was sent, response status, bytes fetched, and response time. This includes MAST API queries, TAP queries, product downloads, file-size lookups, and FITS metadata byte-range requests. Authorization headers are redacted before logging.

```text
MAST API Mast.Caom.Filtered.Position: Request sent method=GET, ...
MAST API Mast.Caom.Filtered.Position: Response received status=200, bytes=123456, time=0.842s, ...
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

### Fast FITS Image Header Metadata

Use `fetchPreferredFITSImageHeaderMetadata` when you only need the main image headers from a FITS `dataURL` and do not want to download or decode the image pixels. It streams the FITS response by default, walks FITS HDU headers as bytes arrive, and closes the transfer after the first usable image HDU: the primary image if present, otherwise the first image/science extension it reaches. HTTP byte-range mode is still available with `fetchMode: .range`.

```swift
mast.fetchPreferredFITSImageHeaderMetadata(for: coamResult) { metadata in
    guard let metadata else { return }

    print("Size: \(metadata.width) x \(metadata.height)")
    print("Axes: \(metadata.axisLengths)")
    print("Image bytes: \(metadata.dataSizeBytes)")
    print("Remote FITS file bytes: \(metadata.remoteFileSizeBytes ?? 0)")
    print("Pixel scale: \(metadata.pixelScaleArcsecondsX ?? 0) arcsec/pixel")
    print("Reference sky coordinate: \(metadata.referenceCoordinate?.ra ?? 0), \(metadata.referenceCoordinate?.dec ?? 0)")
}

mast.fetchPreferredFITSImageHeaderMetadata(for: coamResult, fetchMode: .range) { metadata in
    print(metadata?.width ?? 0, metadata?.height ?? 0)
}
```

Batch file-size and FITS metadata enrichment uses at most 20 concurrent requests by default.
Configure the ceiling on the `SwiftMAST` instance before starting a query:

```swift
let mast = SwiftMAST()
mast.maxConcurrentRequests = 8
```

`dataSizeBytes` is the size of the selected FITS image HDU payload in bytes. It is computed from FITS header keywords such as `BITPIX`, `NAXIS`, `NAXIS1`, `NAXIS2`, `PCOUNT`, and `GCOUNT`; the image pixels do not need to be downloaded to calculate it. `remoteFileSizeBytes` is the size of the whole remote FITS file when the server reports it through HTTP headers such as `Content-Range` or `Content-Length`.

For all parsed image HDUs instead of the quick preferred image, use `fetchFITSHeaderSummary(from:)`.

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

## JWST Science Product Extraction by Filter

`getJWSTScienceProducts` extends the filter-band query by downloading each FITS file and extracting its science products. It returns a `[String: [ScienceProduct]]` dictionary — one array of `ScienceProduct` per unique filter band (one per HDU in the FITS file).

### Usage

```swift
let mast = SwiftMAST()

mast.getJWSTScienceProducts(targetName: "NGC 628", instruments: ["MIRI/IMAGE"]) { products in
    for (filter, scienceProducts) in products.sorted(by: { $0.key < $1.key }) {
        print("\(filter): \(scienceProducts.count) HDU(s)")
        for sp in scienceProducts {
            print("  \(sp.name)")
            print("  Image: \(sp.imageLocation?.path ?? "none")")
            print("  Headers: \(sp.headers.count)")
        }
    }
}
```

### Parameters

Accepts the same parameters as `getJWSTFilteredProducts`, plus an optional `token` for MAST authentication:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `targetName` | `String` | — | Human-readable target identifier |
| `instruments` | `[String]?` | `nil` | Restrict to specific instruments |
| `calibLevels` | `[String]` | `["3", "4"]` | CAOM calibration levels |
| `pageSize` | `Int` | `200` | Maximum products per MAST page |
| `token` | `String?` | `nil` | MAST authentication token |
| `result` | `([String: [ScienceProduct]]) -> Void` | — | Callback receiving the filter → products dictionary |

A coordinate-based overload is also available with additional `ra`, `dec`, and `radius` parameters.

## Footprint-based CAOM and Observation Group Search

MAST returns CAOM footprints in the `s_region` column, but the MAST API position endpoint accepts only a cone search (`ra, dec, radius`). SwiftMAST handles footprint search by deriving a bounding cone from a source `s_region`, querying MAST for candidates, then locally filtering each candidate's own `s_region`.

```swift
let sourceRegion = product.coamResult.s_region

mast.getObservationGroups(
    targetName: "same-footprint-search",
    spaceRegion: sourceRegion,
    containment: .footprintIntersects,
    missions: ObservationMission.majorImaging,
    limit: 25
) { groups in
    for group in groups {
        print(group.description)
    }
}
```

You can also fetch raw CAOM rows:

```swift
mast.getScienceImageQueryResults(
    targetName: "same-footprint-search",
    spaceRegion: sourceRegion,
    containment: .centerInside
) { results in
    print("Matched \(results.count) CAOM products")
}
```

### Footprint containment modes

| Mode | Meaning | Best for |
|------|---------|----------|
| `.centerInside` | Candidate product center (`s_ra`, `s_dec`) is inside the source footprint. | Fast pointing-center searches; can miss overlapping products whose center is outside. |
| `.footprintIntersects` | Candidate footprint overlaps or touches the source footprint. | Broad “find related/overlapping products” searches. |
| `.footprintContained` | Candidate footprint is fully inside the source footprint. | Strict searches where partial overlap is not enough. |

Supported source and candidate footprints are CAOM `CIRCLE` and `POLYGON` `s_region` values, including multi-polygon regions commonly returned by HLA products.

For observation-group searches, SwiftMAST uses an effective limit of `limit ?? pageSize`. The MAST `pagesize` never exceeds that effective limit, and the callback never receives more groups than that effective limit.

## JWST Observation Groups

`getJWSTObservationGroups` queries JWST products and groups them by observation session. Each group shares the same program, observation number, target, and instrument — derived from the `obs_id` prefix (e.g. `jw02666-o007_t004_miri`). Within each group, products are sorted by filter wavelength in ascending order (F200W before F1000W).

### Usage

```swift
let mast = SwiftMAST()

mast.getJWSTObservationGroups(targetName: "NGC 628") { groups in
    for group in groups {
        print(group.observationKey)
        print("  instrument: \(group.instrument)")
        print("  filters: \(group.filterNames.joined(separator: ", "))")
        for product in group.products {
            print("  \(product.filters): \(product.obs_id)")
        }
    }
}
```

To narrow the query to one or more filters, pass `filterBands`:

```swift
mast.getJWSTObservationGroups(
    targetName: "NGC 628",
    filterBands: ["F150W"]
) { groups in
    for group in groups {
        print("\(group.observationKey): \(group.filterNames.joined(separator: ", "))")
    }
}
```

### Example Output

```
jw01783-o004_t008_nircam [NIRCAM/IMAGE] — 8 filters: F115W, F150W, F187N, F200W, F277W, F335M, F444W, F444W;F405N
jw02666-o007_t004_miri [MIRI/IMAGE] — 8 filters: F560W, F1000W, F1130W, F1280W, F1500W, F1800W, F2100W, F2550W
jw02107-o040_t018_nircam [NIRCAM/IMAGE] — 4 filters: F200W, F300M, F335M, F360M
```

### Filter Wavelength Sorting

Filters are sorted by the numeric wavelength extracted from the filter name:

- `F200W` → 200, `F1000W` → 1000, `F2550W` → 2550
- Trailing digits ignored: `F150W2` → 150
- Compound filters use the first component: `F444W;F405N` → 444
- Non-standard names (e.g. `CLEAR`) sort last

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `targetName` | `String` | — | Human-readable target identifier |
| `instruments` | `[String]?` | `nil` | Restrict to specific instruments (e.g. `["MIRI/IMAGE"]`) |
| `filterBands` | `[String]?` | `nil` | Restrict to specific filters (e.g. `["F150W"]`) |
| `calibLevels` | `[String]` | `["3", "4"]` | CAOM calibration levels |
| `pageSize` | `Int` | `400` | Maximum products per MAST page |
| `limit` | `Int?` | `nil` | Maximum observation groups to return; when nil, `pageSize` is used as the effective limit |
| `result` | `([JWSTObservationGroup]) -> Void` | — | Callback receiving sorted observation groups |

A coordinate-based overload is also available with additional `ra`, `dec`, and `radius` parameters.
