//
//  SwiftMAST+io.swift
//  SwiftMAST
//
//  Local cache, sidecar, and filesystem IO helpers.
//

import Foundation
import SwiftQValue
import Zip

extension SwiftMAST {

    internal func mastStorageRootURL() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("MAST", isDirectory: true)
    }

    internal func storageSafePathComponent(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = source.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars).replacingOccurrences(
            of: "__+", with: "_", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_")).isEmpty
            ? fallback
            : collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    internal func productStorageFolder(
        target: String,
        mission: String,
        observationId: String,
        filter: String,
        contentType: ObservationProductContentType
    ) -> URL {

        var MASTDirectory = mastStorageRootURL()
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(target, fallback: "unknown-target"), isDirectory: true)

        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(mission, fallback: "unknown-mission"), isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(observationId, fallback: "unknown-observation"),
            isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(
            storageSafePathComponent(
                filter.replacingOccurrences(of: ";", with: "-"),
                fallback: "unknown-filter"),
            isDirectory: true)
        MASTDirectory = MASTDirectory.appendingPathComponent(contentType.rawValue, isDirectory: true)
        return MASTDirectory
    }

    internal func productStorageFolder(
        target: String,
        product: CoamResult,
        contentType: ObservationProductContentType
    ) -> URL {
        productStorageFolder(
            target: target,
            mission: product.observationMission?.rawValue ?? product.obs_collection,
            observationId: product.obs_id,
            filter: product.filters,
            contentType: contentType
        )
    }

    /// Return every product discovered in the local MAST cache as a canonical
    /// ``CoamResult`` enriched with its local files and FITS metadata.
    ///
    /// The scanner reads the standard product cache layout directly:
    /// `MAST/<target>/<mission>/<observation>/<filter>/fit|image|preview`.
    /// Products without a `coam-result.json` sidecar are reconstructed from the
    /// cache layout and available FITS metadata.
    public func getLocalCoamResults(
        targetName: String? = nil,
        sortOrder: ObservationProductSortOrder = .filter
    ) -> [CoamResult] {
        let root = mastStorageRootURL()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let targetFolders: [URL]
        if let targetName {
            let targetURL = root.appendingPathComponent(
                storageSafePathComponent(targetName, fallback: "unknown-target"),
                isDirectory: true
            )
            targetFolders = FileManager.default.fileExists(atPath: targetURL.path) ? [targetURL] : []
        } else {
            targetFolders = directoryChildren(of: root)
        }

        var results: [CoamResult] = []

        for targetFolder in targetFolders {
            for missionFolder in directoryChildren(of: targetFolder) {
                for observationFolder in directoryChildren(of: missionFolder) {
                    for filterFolder in directoryChildren(of: observationFolder) {
                        guard let product = localCoamResult(
                            targetFolder: targetFolder,
                            missionFolder: missionFolder,
                            observationFolder: observationFolder,
                            filterFolder: filterFolder
                        ) else {
                            continue
                        }
                        results.append(product)
                    }
                }
            }
        }

        return sortedLocalCoamResults(results, sortOrder: sortOrder)
    }

    /// Compatibility view of locally cached products grouped by observation.
    ///
    /// New code should use ``getLocalCoamResults(targetName:sortOrder:)`` and
    /// derive ``ObservationGroup`` values only when grouping is required. This
    /// adapter is intentionally built from canonical `CoamResult` values and is
    /// not part of the cache-scanning path.
    public func getLocalObservationGroups(
        targetName: String? = nil,
        sortOrder: ObservationProductSortOrder = .filter
    ) -> [LocalObservationGroup] {
        buildLocalObservationGroups(
            from: getLocalCoamResults(targetName: targetName, sortOrder: sortOrder),
            sortOrder: sortOrder
        )
    }

    /// Reconstruct local cache contents using the same observation-group model
    /// returned by remote MAST searches.
    public func getCachedObservationGroups(
        targetName: String? = nil,
        sortOrder: ObservationProductSortOrder = .filter
    ) -> [ObservationGroup] {
        buildObservationGroups(
            from: getLocalCoamResults(targetName: targetName, sortOrder: sortOrder),
            sortOrder: sortOrder
        )
    }

    /// Attach locally cached files and metadata to remote or previously stored
    /// products while preserving their original CAOM fields.
    ///
    /// Results are matched using ``CoamResult/productIdentifier``. Products that
    /// have not been cached are returned unchanged, which makes this suitable for
    /// progressively enriching a query result as downloads complete.
    public func enrichWithLocalCache(
        _ products: [CoamResult],
        targetName: String
    ) -> [CoamResult] {
        let cachedProducts = getLocalCoamResults(targetName: targetName)
        let cachedByIdentifier = cachedProducts.reduce(into: [String: CoamResult]()) {
            cache, product in
            cache[product.productIdentifier] = product
        }

        return products.map { product in
            guard let cached = cachedByIdentifier[product.productIdentifier] else {
                return product
            }
            return product
                .withFITSImageHeaderMetadata(
                    cached.fitsImageHeaderMetadata ?? product.fitsImageHeaderMetadata
                )
                .withLocalResources(cached.localResources)
        }
    }

    /// Delete locally cached MAST products saved under SwiftMAST's `MAST` folder.
    ///
    /// Pass a target name to delete only that target's local cache. Omit
    /// `targetName` to delete the entire local MAST cache folder. This also
    /// clears matching in-memory target assets and FITS metadata.
    public func deleteCachedMASTData(targetName: String? = nil) throws {
        let cacheURL: URL
        if let targetName {
            cacheURL = mastStorageRootURL().appendingPathComponent(
                storageSafePathComponent(targetName, fallback: "unknown-target"),
                isDirectory: true
            )
        } else {
            cacheURL = mastStorageRootURL()
        }

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }

        if let targetName {
            targetAssets.removeValue(forKey: targetName)
            fitsMetadataStore.removeValue(forKey: targetName)
            log(
                .OK,
                message: "Deleted cached MAST data for \(targetName)",
                metadata: ["event": "localMASTCacheDeleted", "targetName": targetName]
            )
        } else {
            targetAssets.removeAll()
            fitsMetadataStore.removeAll()
            log(
                .OK,
                message: "Deleted cached MAST data",
                metadata: ["event": "localMASTCacheDeleted"]
            )
        }
    }

    internal func productFileName(
        target: String,
        product: CoamResult,
        productType: ProductType
    ) -> String {
        let targetName = storageSafePathComponent(target, fallback: "unknown-target")
        let mission = storageSafePathComponent(
            product.observationMission?.rawValue ?? product.obs_collection,
            fallback: "unknown-mission")
        let observationId = storageSafePathComponent(product.obs_id, fallback: "unknown-observation")
        let filter = storageSafePathComponent(
            product.filters.replacingOccurrences(of: ";", with: "-"),
            fallback: "unknown-filter")
        return "\(targetName)_\(mission)_\(observationId)_\(filter).\(productType.id)"
    }

    internal func localProductURL(
        targetName: String,
        product: CoamResult,
        productType: ProductType
    ) -> URL {
        let contentType: ObservationProductContentType = productType == .Fits ? .fit : .preview
        return productStorageFolder(target: targetName, product: product, contentType: contentType)
            .appendingPathComponent(
                productFileName(target: targetName, product: product, productType: productType))
    }

    internal func localConvertedImageURL(targetName: String, product: CoamResult) -> URL {
        productStorageFolder(target: targetName, product: product, contentType: .image)
            .appendingPathComponent(
                productFileName(target: targetName, product: product, productType: .Fits)
                    .replacingOccurrences(of: ".fits", with: ".png"))
    }

    internal func productFilterStorageFolder(targetName: String, product: CoamResult) -> URL {
        productStorageFolder(target: targetName, product: product, contentType: .fit)
            .deletingLastPathComponent()
    }

    internal func coamResultSidecarURL(targetName: String, product: CoamResult) -> URL {
        productFilterStorageFolder(targetName: targetName, product: product)
            .appendingPathComponent("coam-result.json")
    }

    internal func fitsRawMetadataSidecarURL(targetName: String, product: CoamResult) -> URL {
        let baseName = productFileName(target: targetName, product: product, productType: .Fits)
            .replacingOccurrences(of: ".fits", with: "")
        return productStorageFolder(target: targetName, product: product, contentType: .fit)
            .appendingPathComponent("\(baseName).raw-metadata.json")
    }

    internal func fitsStructuredMetadataSidecarURL(targetName: String, product: CoamResult) -> URL {
        let baseName = productFileName(target: targetName, product: product, productType: .Fits)
            .replacingOccurrences(of: ".fits", with: "")
        return productStorageFolder(target: targetName, product: product, contentType: .fit)
            .appendingPathComponent("\(baseName).metadata.json")
    }

    internal func fitsImageMetadataSidecarURL(targetName: String, product: CoamResult) -> URL {
        let baseName = productFileName(target: targetName, product: product, productType: .Fits)
            .replacingOccurrences(of: ".fits", with: "")
        return productStorageFolder(target: targetName, product: product, contentType: .fit)
            .appendingPathComponent("\(baseName).image-metadata.json")
    }

    internal func writeJSONSidecar<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log(.RequestError, message: "Unable to write JSON sidecar \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    internal func readJSONSidecar<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    internal func saveCoamResultSidecar(targetName: String, product: CoamResult) {
        writeJSONSidecar(product, to: coamResultSidecarURL(targetName: targetName, product: product))
    }

    internal func saveFITSMetadataSidecars(
        targetName: String,
        product: CoamResult,
        fitsData: FitsData,
        fitsURL: URL
    ) {
        writeJSONSidecar(
            fitsData.metadata,
            to: fitsRawMetadataSidecarURL(targetName: targetName, product: product)
        )
        if let structuredMetadata = fitsData.structuredMetadata {
            writeJSONSidecar(
                structuredMetadata,
                to: fitsStructuredMetadataSidecarURL(targetName: targetName, product: product)
            )
        }
        if let data = try? Data(contentsOf: fitsURL),
           let imageMetadata = parseFITSHeaderSummary(
               data: data,
               sourceURL: fitsURL,
               remoteFileSizeBytes: localFileSize(fitsURL)
           )?.preferredImageMetadata {
            writeJSONSidecar(
                imageMetadata,
                to: fitsImageMetadataSidecarURL(targetName: targetName, product: product)
            )
        }
    }

    internal func cachedFITSDataSidecars(
        targetName: String,
        product: CoamResult,
        resultURL: URL
    ) -> FitsData? {
        let rawMetadataURL = fitsRawMetadataSidecarURL(targetName: targetName, product: product)
        guard
            let rawMetadata = readJSONSidecar(
                [String: QValue].self,
                from: rawMetadataURL
            )
        else {
            return nil
        }
        let structuredMetadata = readJSONSidecar(
            FITSMetadata.self,
            from: fitsStructuredMetadataSidecarURL(targetName: targetName, product: product)
        )
        return FitsData(
            metadata: rawMetadata,
            url: resultURL,
            structuredMetadata: structuredMetadata
        )
    }

    internal func existingLocalProductURL(
        targetName: String,
        product: CoamResult,
        productType: ProductType
    ) -> URL? {
        let url = localProductURL(targetName: targetName, product: product, productType: productType)
        guard FileManager.default.fileExists(atPath: url.path),
              (localFileSize(url) ?? 0) > 0
        else {
            return nil
        }
        return url
    }

    internal func localFileSize(_ url: URL) -> Int64? {
        guard
            let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
                as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    internal func localFitsData(
        targetName: String,
        product: CoamResult,
        fitsURL: URL
    ) -> FitsData {
        saveCoamResultSidecar(targetName: targetName, product: product)
        let pngURL = localConvertedImageURL(targetName: targetName, product: product)
        if FileManager.default.fileExists(atPath: pngURL.path),
           (localFileSize(pngURL) ?? 0) > 0,
           let cachedData = cachedFITSDataSidecars(
               targetName: targetName,
               product: product,
               resultURL: pngURL
           ) {
            appendFitsData(target: targetName, fitsData: cachedData)
            return cachedData
        }

        try? FileManager.default.createDirectory(
            at: pngURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fitsData = convertFitsToPNG(url: fitsURL, writeToUrl: pngURL)
        appendFitsData(target: targetName, fitsData: fitsData)
        saveFITSMetadataSidecars(
            targetName: targetName,
            product: product,
            fitsData: fitsData,
            fitsURL: fitsURL
        )

        let resultURL = fitsData.url ?? fitsURL
        return FitsData(
            metadata: fitsData.metadata,
            url: resultURL,
            structuredMetadata: fitsData.structuredMetadata
        )
    }

    internal func localCachedDownloadResult(
        targetName: String,
        product: CoamResult,
        productType: ProductType
    ) -> FitsData? {
        if productType == .Fits {
            guard
                let fitsURL = existingLocalProductURL(
                    targetName: targetName, product: product, productType: .Fits)
            else {
                return nil
            }
            log(.OK, message: "Cache hit: FITS \(fitsURL.lastPathComponent) for \(targetName)")
            return localFitsData(targetName: targetName, product: product, fitsURL: fitsURL)
        }

        guard
            let imageURL = existingLocalProductURL(
                targetName: targetName, product: product, productType: productType)
        else {
            return nil
        }
        saveCoamResultSidecar(targetName: targetName, product: product)
        log(.OK, message: "Cache hit: \(productType.id) \(imageURL.lastPathComponent) for \(targetName)")
        return FitsData(metadata: [:], url: imageURL)
    }

    internal func localFITSHeaderMetadata(
        targetName: String,
        product: CoamResult
    ) -> FITSImageHeaderMetadata? {
        let metadataURL = fitsImageMetadataSidecarURL(targetName: targetName, product: product)
        if let metadata = readJSONSidecar(FITSImageHeaderMetadata.self, from: metadataURL) {
            log(.OK, message: "Cache hit: FITS metadata sidecar \(metadataURL.lastPathComponent) for \(targetName)")
            return metadata
        }

        guard
            let fitsURL = existingLocalProductURL(
                targetName: targetName, product: product, productType: .Fits),
            let data = try? Data(contentsOf: fitsURL)
        else {
            return nil
        }

        log(.OK, message: "Cache hit: FITS metadata \(fitsURL.lastPathComponent) for \(targetName)")
        let metadata = parseFITSHeaderSummary(
            data: data,
            sourceURL: fitsURL,
            remoteFileSizeBytes: localFileSize(fitsURL)
        )?.preferredImageMetadata
        if let metadata {
            writeJSONSidecar(metadata, to: metadataURL)
        }
        return metadata
    }

    internal func existingPS1CutoutURL(targetName: String) -> URL? {
        let directory = productStorageFolder(
            target: targetName,
            mission: "PS1",
            observationId: "cutout",
            filter: "OPTICAL",
            contentType: .image
        )
        let safeTarget = storageSafePathComponent(targetName, fallback: "unknown-target")
        let url = directory.appendingPathComponent("\(safeTarget)_PS1_cutout_OPTICAL.jpg")
        guard FileManager.default.fileExists(atPath: url.path),
              (localFileSize(url) ?? 0) > 0
        else {
            return nil
        }
        return url
    }

    func unzipResponseData(_ data: Data, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global().async {
            guard
                let documentsDirectory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else {
                self.log(.RequestError, message: "Unable to open Documents folder")
                completion([])
                return
            }

            let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)

            do {
                try FileManager.default.createDirectory(
                    at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)

                let temporaryZipFileURL = temporaryDirectory.appendingPathComponent("temp.tar.gz")

                let tempDoc = documentsDirectory.appendingPathComponent("temp.tar.gz")
                try data.write(to: temporaryZipFileURL)
                try data.write(to: tempDoc)
                print("tar temporarily added")
                print("Data size: \(data.count) bytes")

                try FileManager.default.createFilesAndDirectories(
                    path: temporaryDirectory.path, tarPath: temporaryZipFileURL.path)

                let unzippedFiles = try FileManager.default.contentsOfDirectory(
                    atPath: temporaryDirectory.path)

                try FileManager.default.removeItem(at: temporaryZipFileURL)
                try FileManager.default.removeItem(at: temporaryDirectory)

                print("unzipResponseData: Unzipped files to: \(documentsDirectory)")
                DispatchQueue.main.async {
                    completion(unzippedFiles.map { Foundation.URL(fileURLWithPath: $0) })
                }
            } catch let error {
                self.log(.RequestError, message: error.localizedDescription)
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    /** Saves MAST returned assets to local directory
     */
    func saveAsset(
        targetName: String, product: CoamResult, urlString: String, data: Data,
        completion: @escaping (FitsData?) -> Void
    ) {
        print("saveAsset: \(urlString)")

        let fitsDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .fit)
        let imageDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .image)

        do {
            try FileManager.default.createDirectory(
                at: fitsDirectory, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(
                at: imageDirectory, withIntermediateDirectories: true, attributes: nil)

            let fileName = productFileName(target: targetName, product: product, productType: .Fits)
            let fileUrl = fitsDirectory.appendingPathComponent(fileName)

            try data.write(to: fileUrl)
            saveCoamResultSidecar(targetName: targetName, product: product)
            print("saveAsset: FITS file saved to \(fileUrl)")

            let pngURL = imageDirectory.appendingPathComponent(
                fileName.replacingOccurrences(of: ".fits", with: ".png"))
            let fitsData = convertFitsToPNG(url: fileUrl, writeToUrl: pngURL)

            // Store the FITS metadata
            self.appendFitsData(target: targetName, fitsData: fitsData)
            self.saveFITSMetadataSidecars(
                targetName: targetName,
                product: product,
                fitsData: fitsData,
                fitsURL: fileUrl
            )

            // If PNG conversion succeeded, use the PNG URL; otherwise use the FITS file URL
            let resultUrl = fitsData.url ?? fileUrl
            let resultFitsData = FitsData(
                metadata: fitsData.metadata, url: resultUrl,
                structuredMetadata: fitsData.structuredMetadata)

            if fitsData.url != nil {
                print("saveAsset: PNG image saved to \(pngURL)")
            } else {
                print("saveAsset: PNG conversion failed, returning FITS URL instead")
            }

            DispatchQueue.main.async {
                completion(resultFitsData)
            }
        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    /** Saves COAM jpegURL/preview image only.

     Direct JPEG products are kept separate from FITS-rendered images so the
     cache can preserve both the server-provided preview and the local render.
     no fits data
     */
    func saveImageFile(
        target: String, collection: String, filter: String, observationId: String? = nil,
        productType: ProductType = .Jpeg,
        contentType: ObservationProductContentType = .image,
        url: URL? = nil,
        data: Data? = nil
    ) -> URL? {
        print("saveImageFile: \(target)_\(collection)_\(filter).\(productType.id)")

        let MASTDirectory = productStorageFolder(
            target: target,
            mission: collection,
            observationId: observationId ?? "unknown-observation",
            filter: filter,
            contentType: contentType
        )

        let safeTarget = storageSafePathComponent(target, fallback: "unknown-target")
        let safeCollection = storageSafePathComponent(collection, fallback: "unknown-mission")
        let safeObservationId = storageSafePathComponent(
            observationId ?? "unknown-observation",
            fallback: "unknown-observation")
        let safeFilter = storageSafePathComponent(
            filter.replacingOccurrences(of: ";", with: "-"),
            fallback: "unknown-filter")
        let fileExtension =
            "\(safeTarget)_\(safeCollection)_\(safeObservationId)_\(safeFilter).\(productType.id)"
        let imageUrl = MASTDirectory.appendingPathComponent(fileExtension)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)

            if let url = url {
                let data = try Data(contentsOf: url)
                try data.write(to: imageUrl)
            } else if let data = data {
                try data.write(to: imageUrl)
            } else {
                assertionFailure("No url or data specified.")
            }
            // Set the preview image if it's not set

            return imageUrl

        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            return nil
        }
    }

    func saveTempUrlToFile(
        targetName: String, product: CoamResult, tempUrl: URL, productType: ProductType,
        completion: @escaping (URL?) -> Void
    ) {
        print("saveTempUrlToFile: \(targetName)")

        let contentType: ObservationProductContentType = productType == .Fits ? .fit : .preview
        let MASTDirectory = productStorageFolder(
            target: targetName, product: product, contentType: contentType)
        let imageDirectory = productStorageFolder(
            target: targetName, product: product, contentType: .image)

        do {
            try FileManager.default.createDirectory(
                at: MASTDirectory, withIntermediateDirectories: true, attributes: nil)
            if productType == .Fits {
                try FileManager.default.createDirectory(
                    at: imageDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            let fileExtension = productFileName(
                target: targetName, product: product, productType: productType)
            let saveUrl = MASTDirectory.appendingPathComponent(fileExtension)

            // Remove existing file if it exists to avoid "item already exists" error
            if FileManager.default.fileExists(atPath: saveUrl.path) {
                try FileManager.default.removeItem(at: saveUrl)
            }

            try FileManager.default.moveItem(at: tempUrl, to: saveUrl)
            saveCoamResultSidecar(targetName: targetName, product: product)

            // Add the fits or jpeg data to the target
            if productType == .Fits {
                print("saveTempUrlToFile: FITS file saved to \(saveUrl)")

                // Convert FITS to PNG for viewing
                let pngURL = imageDirectory.appendingPathComponent(
                    fileExtension.replacingOccurrences(of: ".fits", with: ".png"))
                let fitsData = convertFitsToPNG(url: saveUrl, writeToUrl: pngURL)

                // Store the FITS metadata
                self.appendFitsData(target: targetName, fitsData: fitsData)
                self.saveFITSMetadataSidecars(
                    targetName: targetName,
                    product: product,
                    fitsData: fitsData,
                    fitsURL: saveUrl
                )

                // Return the PNG URL if conversion succeeded, otherwise return the FITS file URL
                let resultUrl = fitsData.url ?? saveUrl

                if fitsData.url != nil {
                    print("saveTempUrlToFile: PNG image saved to \(pngURL)")
                } else {
                    print("saveTempUrlToFile: PNG conversion failed, returning FITS URL instead")
                }

                DispatchQueue.main.async {
                    completion(resultUrl)
                }
            } else {
                DispatchQueue.main.async {
                    completion(saveUrl)
                }
            }
        } catch let error {
            self.log(.RequestError, message: error.localizedDescription)
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

    private func localCoamResult(
        targetFolder: URL,
        missionFolder: URL,
        observationFolder: URL,
        filterFolder: URL
    ) -> CoamResult? {
        let fitFolder = filterFolder.appendingPathComponent(
            ObservationProductContentType.fit.rawValue,
            isDirectory: true
        )
        let imageFolder = filterFolder.appendingPathComponent(
            ObservationProductContentType.image.rawValue,
            isDirectory: true
        )
        let previewFolder = filterFolder.appendingPathComponent(
            ObservationProductContentType.preview.rawValue,
            isDirectory: true
        )

        let fitFileURL = firstLocalFile(in: fitFolder, extensions: ["fits", "fit"])
        let imageFileURL = firstLocalFile(in: imageFolder, extensions: ["jpg", "jpeg", "png"])
        let previewImageFileURL = firstLocalFile(in: previewFolder, extensions: ["jpg", "jpeg", "png"])
        let rawMetadataURL = firstLocalFile(in: fitFolder, suffix: ".raw-metadata.json")
        let structuredMetadataURL = firstLocalFile(in: fitFolder, suffix: ".metadata.json")
        let imageMetadataURL = firstLocalFile(in: fitFolder, suffix: ".image-metadata.json")
        let rawMetadata = rawMetadataURL
            .flatMap { readJSONSidecar([String: QValue].self, from: $0) }
        let metadata = structuredMetadataURL
            .flatMap { readJSONSidecar(FITSMetadata.self, from: $0) }
        let imageMetadata = imageMetadataURL
            .flatMap { readJSONSidecar(FITSImageHeaderMetadata.self, from: $0) }
        let parsedImageMetadata = imageMetadata ?? fitFileURL.flatMap {
            localFITSImageHeaderMetadata(from: $0)
        }
        let resources = CoamLocalResources(
            fitsPath: fitFileURL?.path,
            imagePath: imageFileURL?.path,
            previewImagePath: previewImageFileURL?.path,
            rawMetadataPath: rawMetadataURL?.path,
            structuredMetadataPath: structuredMetadataURL?.path,
            imageMetadataPath: imageMetadataURL?.path
        )
        let sidecarURL = filterFolder.appendingPathComponent("coam-result.json")
        let storedCoamResult = readJSONSidecar(CoamResult.self, from: sidecarURL)
        let resolvedImageMetadata = parsedImageMetadata ?? storedCoamResult?.fitsImageHeaderMetadata
        let coamResult = (storedCoamResult ?? CoamResult(
            localTargetName: targetFolder.lastPathComponent,
            mission: missionFolder.lastPathComponent,
            observationID: observationFolder.lastPathComponent,
            filter: filterFolder.lastPathComponent,
            instrument: metadata?.instrument ?? "",
            localResources: resources,
            rawMetadata: rawMetadata,
            fitsImageHeaderMetadata: resolvedImageMetadata
        ))
        .withFITSImageHeaderMetadata(resolvedImageMetadata)
        .withLocalResources(resources)

        guard fitFileURL != nil
            || imageFileURL != nil
            || previewImageFileURL != nil
            || storedCoamResult != nil
            || rawMetadata != nil
            || metadata != nil
            || parsedImageMetadata != nil
        else {
            return nil
        }

        return coamResult
    }

    private func localWCSData(
        imageMetadata: FITSImageHeaderMetadata?,
        metadata: FITSMetadata?,
        rawMetadata: [String: QValue]?
    ) -> FITSWCSData? {
        if let imageMetadata, let wcs = FITSWCSData.wcsData(from: imageMetadata) {
            return wcs
        }
        if let metadata, let wcs = FITSWCSData.wcsData(from: metadata) {
            return wcs
        }
        if let rawMetadata, let wcs = FITSWCSData.wcsData(from: rawMetadata) {
            return wcs
        }
        return nil
    }

    private func localFITSImageHeaderMetadata(from fitsURL: URL) -> FITSImageHeaderMetadata? {
        guard let data = try? Data(contentsOf: fitsURL) else { return nil }
        return parseFITSHeaderSummary(
            data: data,
            sourceURL: fitsURL,
            remoteFileSizeBytes: localFileSize(fitsURL)
        )?.preferredImageMetadata
    }

    private func sortedLocalCoamResults(
        _ products: [CoamResult],
        sortOrder: ObservationProductSortOrder
    ) -> [CoamResult] {
        products.sorted { lhs, rhs in
            let leftIdentity = GroupIdentity(
                targetName: lhs.target_name,
                mission: lhs.observationMission?.rawValue ?? lhs.obs_collection.uppercased(),
                observationKey: observationGroupKey(lhs),
                instrument: lhs.instrument_name
            )
            let rightIdentity = GroupIdentity(
                targetName: rhs.target_name,
                mission: rhs.observationMission?.rawValue ?? rhs.obs_collection.uppercased(),
                observationKey: observationGroupKey(rhs),
                instrument: rhs.instrument_name
            )
            if leftIdentity.targetName != rightIdentity.targetName {
                return leftIdentity.targetName < rightIdentity.targetName
            }
            if leftIdentity.mission != rightIdentity.mission {
                return leftIdentity.mission < rightIdentity.mission
            }
            if leftIdentity.observationKey != rightIdentity.observationKey {
                return leftIdentity.observationKey < rightIdentity.observationKey
            }
            if leftIdentity.instrument != rightIdentity.instrument {
                return leftIdentity.instrument < rightIdentity.instrument
            }
            if compareObservationProducts(lhs, rhs, by: sortOrder) {
                return true
            }
            if compareObservationProducts(rhs, lhs, by: sortOrder) {
                return false
            }
            return lhs.productIdentifier < rhs.productIdentifier
        }
    }

    private func buildLocalObservationGroups(
        from results: [CoamResult],
        sortOrder: ObservationProductSortOrder
    ) -> [LocalObservationGroup] {
        var grouped = [GroupIdentity: [CoamResult]]()
        for product in results {
            let identity = GroupIdentity(
                targetName: product.target_name,
                mission: product.observationMission?.rawValue
                    ?? product.obs_collection.uppercased(),
                observationKey: observationGroupKey(product),
                instrument: product.instrument_name
            )
            grouped[identity, default: []].append(product)
        }

        return grouped.map { identity, products in
            LocalObservationGroup(
                targetName: identity.targetName,
                mission: identity.mission,
                observationKey: identity.observationKey,
                instrument: identity.instrument,
                filters: products
                    .sorted { compareObservationProducts($0, $1, by: sortOrder) }
                    .map(localObservationFilterProduct)
            )
        }
        .sorted {
            if $0.targetName != $1.targetName { return $0.targetName < $1.targetName }
            if $0.mission != $1.mission { return $0.mission < $1.mission }
            if $0.observationKey != $1.observationKey {
                return $0.observationKey < $1.observationKey
            }
            return $0.instrument < $1.instrument
        }
    }

    private func localObservationFilterProduct(
        from product: CoamResult
    ) -> LocalObservationFilterProduct {
        let resources = product.localResources
        let rawMetadata = resources?.rawMetadataURL.flatMap {
            readJSONSidecar([String: QValue].self, from: $0)
        }
        let metadata = resources?.structuredMetadataURL.flatMap {
            readJSONSidecar(FITSMetadata.self, from: $0)
        }
        let imageMetadata = product.fitsImageHeaderMetadata
            ?? resources?.imageMetadataURL.flatMap {
                readJSONSidecar(FITSImageHeaderMetadata.self, from: $0)
            }

        return LocalObservationFilterProduct(
            filterName: product.filters,
            fitFileURL: resources?.fitsURL,
            imageFileURL: resources?.imageURL,
            previewImageFileURL: resources?.previewImageURL,
            coamResult: product,
            rawMetadata: rawMetadata,
            metadata: metadata,
            imageMetadata: imageMetadata,
            wcs: localWCSData(
                imageMetadata: imageMetadata,
                metadata: metadata,
                rawMetadata: rawMetadata
            )
        )
    }

    private func directoryChildren(of url: URL) -> [URL] {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return children
            .filter { ($0.resourceValue(forKey: .isDirectoryKey) ?? false) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func firstLocalFile(in directory: URL, extensions: [String]) -> URL? {
        let allowed = Set(extensions.map { $0.lowercased() })
        return localFiles(in: directory)
            .first { allowed.contains($0.pathExtension.lowercased()) }
    }

    private func firstLocalFile(in directory: URL, suffix: String) -> URL? {
        localFiles(in: directory)
            .first { $0.lastPathComponent.lowercased().hasSuffix(suffix.lowercased()) }
    }

    private func localFiles(in directory: URL) -> [URL] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return files
            .filter { ($0.resourceValue(forKey: .isRegularFileKey) ?? false) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private extension URL {
    func resourceValue(forKey key: URLResourceKey) -> Bool? {
        (try? resourceValues(forKeys: [key]))?.allValues[key] as? Bool
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
