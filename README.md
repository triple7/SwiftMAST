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

