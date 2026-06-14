//
//  SwiftMAST+API.swift
//
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation
import QuartzCore

public typealias TargetCoordinates = (ra: Float, dec: Float, radius: Float)

/// SwiftMAST common API calls
/// These convenience functions allow quick access to some of the more interesting MAST API data requests.
/// The MAST portal can be very complex to navigate, however most users would be looking to do the following investigations:
/// * Download a preview of a given target object
/// * download calibrated scientific images of a chosen object in full spectrum
/// * Find TESS candidates within a given cone search and download time series for analysis
/// * Download the spectra of a given object in one of the available missions
/// * Download 3D star mappings from the SDSS (Sloan Digital Sky Survey) in CUBE format
/// * Download GAIA point crossMatch parameters for conversion to 3D point cloud mapping
/// * Download TESS crossMatch parameters for investigating light curves
extension SwiftMAST {

    /** Lookup a target by its name
     Parameters:
     * name: String
     */
    public func lookupTargetByName(targetName: String, result: @escaping ([NameLookupJson]) -> Void)
    {
        print("lookupTargetByName: \(targetName)")
        var output: [NameLookupJson] = []
        self.setTargetId(targetId: targetName)
        let service = Service.Mast_Name_Lookup
        var params = service.serviceRequest(requestType: .lookup)
        params.setParameter(param: .input, value: targetName)
        params.setParameter(param: .searchRadius, value: 0.1)
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                if let table = self.targets[targetName] {
                    let resolved = table.getNameLookupResults()
                    output += resolved
                }
                result(output)
            })
    }

    /** Lookup a target by name and return its coordinates
     Parameters:
     * targetName: String
     * result: Closure returning TargetCoordinates or nil if unresolved
     */
    public func lookupTargetCoordinates(
        targetName: String, result: @escaping (TargetCoordinates?) -> Void
    ) {
        self.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(
            targetName: targetName,
            result: { targetLookup in
                guard !targetLookup.isEmpty, let table = self.targets[targetName] else {
                    self.log(
                        .RequestError,
                        message: "lookupTargetCoordinates: Could not resolve target '\(targetName)'"
                    )
                    result(nil)
                    return
                }
                let targetEnd = CACurrentMediaTime()
                self.log(
                    .OK,
                    message:
                        "lookupTargetCoordinates: Target '\(targetName)' resolved in \(String(format: "%.2f", targetEnd - targetStart))s"
                )
                let resolved = table.getNameLookupResults().first!
                self.setTargetAssets(target: targetName, targetInfo: resolved)
                result((ra: resolved.ra, dec: resolved.dec, radius: resolved.radius))
            })
    }

    /** Get the missions list
     */
    public func getMissionsList(result: @escaping ([String]) -> Void) {
        print("getMissionsList")
        let service = Service.Mast_Missions_List
        let params = service.serviceRequest(requestType: .missionList)
        var output: [String] = []
        // Here target is not some object but jus a mission list
        self.setTargetId(targetId: "missions")
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                for target in self.targets.keys {
                    let table = self.targets[target]
                    let values = table!.getValues(for: "distinctValue")
                    output.append(contentsOf: values.map { $0.value as! String })
                }
                result(output)
            })
    }

    /** Make a cone search for data products in the MAST archives

     */
    public func getConeSearch(
        targetId: String, ra: Float, dec: Float, radius: Float = 0.2, preview: Bool = false,
        pageSize: Int = 50, result: @escaping ([CoamResult]) -> Void
    ) {
        print("getConeSearch: ra: \(ra) dec: \(dec)")

        let start = CACurrentMediaTime()
        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: ra, MAP.dec: dec, MAP.radius: radius])
        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        if preview {
            params.setGeneralParameter(param: MAP.pagesize, value: pageSize)
            params.setGeneralParameter(param: MAP.timeout, value: 30)
        }
        self.setTargetId(targetId: targetId)
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                print("getConeSearch: search completed in \(end - start)")
                let table = self.targets[targetId]!
                let results = table.getCoamResults()

                // Get dataUrls which are fits for the metadata
                var dataURLs = results.filter { !$0.dataURL.isEmpty }

                if preview {
                    // Filter down to those which are not TESS
                    dataURLs = dataURLs.filter { $0.obs_collection != "TESS" }
                    print("getConeSearch: preview found \(dataURLs.count) dataURLs")

                    self.enrichCoamResultsWithFileSizes(dataURLs, completion: result)
                    return
                }
                // Normal collection of images
                let jpgUrls = results.filter { !$0.jpegURL.isEmpty }
                print(
                    "getConeSearch: found \(jpgUrls.count) jpegURLs and \(dataURLs.count) dataURLs")
                self.enrichCoamResultsWithFileSizes(jpgUrls + dataURLs, completion: result)
            })
    }

    /** Make a filtered cone search for data products in the MAST archives

     */
    public func getFilteredConeSearch(
        ra: Float, dec: Float, radius: Float = 0.2,
        filters: [ResultField] = [
            .filters, .wavelength_region, .instrument_name, .obs_collection, .dataURL,
        ], filterParams: [MASTJsonFilter]? = nil,
        result: @escaping ([ResultField: [String]]) -> Void
    ) {
        print("getFilteredConeSearch: ra: \(ra) dec: \(dec)")

        var output = [ResultField: [String]]()
        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: ra, MAP.dec: dec, MAP.radius: radius])
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                for target in self.targets.keys {
                    let table = self.targets[target]
                    let resolved = table!.getRows(filters: filters)
                    for key in resolved.keys {
                        output[key] = resolved[key]!.map { $0.value as! String }
                    }
                }
                result(output)
            })
    }

    /** Get image file list from PS1
     Parameters:
     * ra: Float
     * dec: Float
     * size: squared image pixel size (0.25 arsec/pixel)
     */
    public func getPS1ImageList(
        targetName: String, ra: Float, dec: Float, imageSize: Int = 8000,
        completion: @escaping (MASTTable?) -> Void
    ) {
        print("getPS1ImageList: \(targetName) imagesize: \(imageSize)")

        let ps1Request = PS1Request(ra: ra, dec: dec, size: imageSize)
        queryPS1(
            ps1Request: ps1Request,
            { success in

                guard let target = self.currentTargetId, let table = self.targets[target] else {
                    print("Unable to find target \(self.currentTargetId!)")
                    completion(nil)
                    return
                }

                completion(table)
            })
    }

    /** Make a preview image cone search
     Parameters:
     * ra: Float
     * dec: Float
     * radius: Float
     */
    public func getMASTPreviewImage(
        targetName: String, ra: Float, dec: Float, radius: Float, pageSize: Int = 30,
        token: String?, result: @escaping (URL) -> Void
    ) {
        print("getPreviewImage: \(targetName)")

        self.getConeSearch(
            targetId: targetName, ra: ra, dec: dec, radius: radius, preview: true,
            pageSize: pageSize,
            result: { coamResults in

                // Filter products which use MAST to download
                let directDownloadproducts = coamResults.filter {
                    ($0.jpegURL.isEmpty ? $0.dataURL : $0.jpegURL).contains("http")
                }
                let mastDownloadproducts = Array(
                    Set(coamResults).subtracting(directDownloadproducts))

                // Prioritize mastDownload products
                print(
                    "getPreviewImage: mastDownloadproducts: \(mastDownloadproducts.count) directDownloads: \(directDownloadproducts.count)"
                )
                if !mastDownloadproducts.isEmpty {
                    let productType: ProductType =
                        mastDownloadproducts.first!.jpegURL.isEmpty ? .Fits : .Jpeg

                    let start = CACurrentMediaTime()
                    self.getDataproducts(
                        targetName: targetName, service: .Download_file,
                        products: [mastDownloadproducts.first!], productType: productType,
                        token: token
                    ) { fitsResults in
                        let end = CACurrentMediaTime()
                        print("downloaded \(fitsResults.count) in \(end - start)")
                        result(fitsResults.first!.url!)
                    }
                } else {
                    // Direct download
                    let productType: ProductType =
                        directDownloadproducts.first!.jpegURL.isEmpty ? .Fits : .Jpeg
                    self.getDirectDataproducts(
                        targetName: targetName, service: .Download_file,
                        products: [directDownloadproducts.first!], productType: productType,
                        token: token
                    ) { (directUrls) in

                        result(directUrls.first!)
                    }
                }
            })
    }

    /** Make a Science image only cone search
     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension
     * dec: Float - Declination
     * radius: Float - Search radius
     * productType: ProductType - .Fits or .Jpeg (default: .Fits)
     * filterOptions: ImageryFilterOptions - Filter criteria for the search (default: science images)
     * pageSize: Int - Number of results per page (default: 50)
     * page: Int - Page number for pagination (default: 1)
     * token: String? - MAST authentication token
     * result: Closure returning array of downloaded URLs
     */
    public func getScienceImageProducts(
        targetName: String, ra: Float, dec: Float, radius: Float, productType: ProductType = .Fits,
        filterOptions: ImageryFilterOptions = .defaultScience, pageSize: Int = 50, page: Int = 1,
        token: String?, result: @escaping ([URL]) -> Void
    ) {
        self.getScienceImageQueryResults(
            targetName: targetName, ra: ra, dec: dec, radius: radius,
            filterOptions: filterOptions, pageSize: pageSize, page: page
        ) { allFilterProducts in

            // Some products are meant to be direct downloads
            let directDownloadproducts = allFilterProducts.filter {
                (productType == .Fits ? $0.dataURL : $0.jpegURL).contains("http")
            }

            self.log(
                .OK,
                message:
                    "getScienceImageProducts: \(directDownloadproducts.count) direct downloads, \(allFilterProducts.count - directDownloadproducts.count) MAST downloads"
            )
            let mastDownloadProducts = allFilterProducts.filter {
                !(productType == .Fits ? $0.dataURL : $0.jpegURL).contains("http")
            }
            // Get the MAST query url downloads and return the URLs
            self.getDataproducts(
                targetName: targetName, service: .Download_file, products: mastDownloadProducts,
                productType: productType, token: token
            ) { allFitsDataResults in

                let existingUrls = allFitsDataResults.filter { $0.url != nil }
                let secondaryUrls = existingUrls.map { $0.url! }

                // Secondary non MAST direct downloads
                self.getDirectDataproducts(
                    targetName: targetName, service: .Download_file,
                    products: directDownloadproducts, productType: productType, token: token
                ) { directUrls in

                    result(secondaryUrls + directUrls)
                }
            }
        }
    }

    /** Make a Science image only cone search and return filtered results
     Parameters:
     * targetName: String - the target identifier
     * filterOptions: ImageryFilterOptions - Filter criteria for the search (default: science images)
     * pageSize: Int - Number of results per page (default: 50)
     * page: Int - Page number for pagination (default: 1)
     * result: Closure returning filtered CoamResult entries
     */
    public func getScienceImageQueryResults(
        targetName: String, filterOptions: ImageryFilterOptions = .defaultScience,
        pageSize: Int = 50, page: Int = 1, result: @escaping ([CoamResult]) -> Void
    ) {
        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates = coordinates else {
                result([])
                return
            }
            self.getScienceImageQueryResults(
                targetName: targetName,
                ra: coordinates.ra,
                dec: coordinates.dec,
                radius: coordinates.radius,
                filterOptions: filterOptions,
                pageSize: pageSize,
                page: page,
                result: result
            )
        }
    }

    /** Make a Science image only cone search and return filtered results
     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension
     * dec: Float - Declination
     * radius: Float - Search radius
     * filterOptions: ImageryFilterOptions - Filter criteria for the search (default: science images)
     * pageSize: Int - Number of results per page (default: 50)
     * page: Int - Page number for pagination (default: 1)
     * result: Closure returning filtered CoamResult entries
     */
    public func getScienceImageQueryResults(
        targetName: String, ra: Float, dec: Float, radius: Float,
        filterOptions: ImageryFilterOptions = .defaultScience, pageSize: Int = 50, page: Int = 1,
        result: @escaping ([CoamResult]) -> Void
    ) {
        self.log(
            .OK,
            message:
                "getScienceImageQueryResults: Starting search for \(targetName) at RA=\(ra), Dec=\(dec), radius=\(radius), page=\(page), pageSize=\(pageSize)"
        )

        self.setTargetId(targetId: targetName)
        let service = Service.Mast_Caom_Filtered_Position
        var params = service.serviceRequest(requestType: .advancedSearch)

        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        params.setParameter(param: MAP.pagesize, value: pageSize)
        params.setParameter(param: MAP.page, value: page)
        let filterParams = filterOptions.toMASTFilters()
        params.setFilterParameters(params: filterParams)
        params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])

        let start = CACurrentMediaTime()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                self.log(
                    .OK,
                    message:
                        "getScienceImageQueryResults: Search completed in \(String(format: "%.2f", end - start))s"
                )
                // we are looking for the targetId set previously
                guard let table = self.targets[targetName] else {
                    self.log(
                        .RequestError,
                        message: "getScienceImageQueryResults: No target table for '\(targetName)'")
                    result([])
                    return
                }
                var coamResults = table.getCoamResults()
                coamResults.sort()
                self.log(
                    .OK,
                    message:
                        "getScienceImageQueryResults: Found \(coamResults.count) data products on page \(page)"
                )
                let uniqueFilters = table.getUniqueString(for: Coam.filters.id)

                self.printUniqueSets(table: table)
                // dictionary of products by filter
                self.pruneProductsByFilterBand(results: coamResults)
                var products = [String: [CoamResult]]()
                for coamResult in coamResults {
                    let filter = coamResult.filters
                    if let filterList = products[filter] {
                        products[filter] = filterList + [coamResult]
                    } else {
                        products[filter] = [coamResult]
                    }
                }
                // Append the first image of each filter
                var allFilterProducts = [CoamResult]()
                for filter in uniqueFilters {
                    if let coamResult = products[filter], !coamResult.isEmpty {
                        allFilterProducts.append(coamResult[0])
                    }
                }

                self.log(
                    .OK,
                    message:
                        "getScienceImageQueryResults: \(allFilterProducts.count) unique filter products returned"
                )
                self.enrichCoamResultsWithFileSizes(allFilterProducts, completion: result)
            })
    }

    /** Download a single science image query result and return its saved URL
     Parameters:
     * targetName: String - the target identifier
     * result: CoamResult - a single query result
     * productType: ProductType - .Fits or .Jpeg (default: .Fits)
     * token: String? - MAST authentication token
     * completion: Closure returning the saved URL or nil when unavailable
     */
    public func getScienceImageProductUrl(
        targetName: String, result: CoamResult, productType: ProductType = .Fits,
        token: String? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        let productUrl = productType == .Fits ? result.dataURL : result.jpegURL
        guard !productUrl.isEmpty else {
            completion(nil)
            return
        }

        if productUrl.contains("http") {
            self.getDirectDataproducts(
                targetName: targetName, service: .Download_file, products: [result],
                productType: productType, token: token
            ) { urls in
                completion(urls.first)
            }
            return
        }

        self.getDataproducts(
            targetName: targetName, service: .Download_file, products: [result],
            productType: productType, token: token
        ) { allFitsDataResults in
            let url = allFitsDataResults.first { $0.url != nil }?.url
            completion(url)
        }
    }

    /** Download and extract science products from a CoamResult.

     Downloads the product (FITS or image) for the given CoamResult and returns
     an array of `ScienceProduct` objects. For FITS files, each image HDU produces
     a separate entry with:
       - The image saved as JPEG and its location
       - The source FITS file location
       - Merged headers (primary HDU headers as base, overridden by individual HDU headers)
       - The original CoamResult

     For non-FITS (JPEG) results, a single `ScienceProduct` is returned with the
     downloaded image location.

     Parameters:
     * targetName: String - the target identifier
     * coamResult: CoamResult - the query result to download and extract
     * token: String? - MAST authentication token
     * completion: Closure returning array of ScienceProduct
     */
    public func extractScienceProducts(
        targetName: String, coamResult: CoamResult, token: String? = nil,
        completion: @escaping ([ScienceProduct]) -> Void
    ) {
        let hasFits = !coamResult.dataURL.isEmpty
        let hasJpeg = !coamResult.jpegURL.isEmpty

        // Prefer FITS for richer metadata; fall back to JPEG
        let productType: ProductType = hasFits ? .Fits : .Jpeg

        guard hasFits || hasJpeg else {
            self.log(
                .RequestError,
                message: "extractScienceProducts: No download URL for \(coamResult.obs_id)")
            completion([])
            return
        }

        let productUrl = productType == .Fits ? coamResult.dataURL : coamResult.jpegURL

        // Choose download path based on URL type
        if productUrl.contains("http") {
            // Direct download
            self.getDirectDataproducts(
                targetName: targetName, service: .Download_file, products: [coamResult],
                productType: productType, token: token
            ) { urls in
                guard let savedUrl = urls.first else {
                    completion([])
                    return
                }
                self.buildScienceProducts(
                    savedUrl: savedUrl, productType: productType,
                    coamResult: coamResult, completion: completion
                )
            }
        } else {
            // MAST download
            self.getDataproducts(
                targetName: targetName, service: .Download_file, products: [coamResult],
                productType: productType, token: token
            ) { fitsDataResults in
                guard let fitsData = fitsDataResults.first, let savedUrl = fitsData.url else {
                    completion([])
                    return
                }
                self.buildScienceProducts(
                    savedUrl: savedUrl, productType: productType,
                    coamResult: coamResult, completion: completion
                )
            }
        }
    }

    /// Internal helper: builds ScienceProduct array from a downloaded file.
    private func buildScienceProducts(
        savedUrl: URL, productType: ProductType, coamResult: CoamResult,
        completion: @escaping ([ScienceProduct]) -> Void
    ) {
        if productType == .Fits {
            // Find the original FITS file — savedUrl may be the converted JPEG
            let fitsUrl: URL
            if savedUrl.pathExtension.lowercased() == "fits" {
                fitsUrl = savedUrl
            } else {
                // The FITS file should be alongside the JPEG with .fits extension
                let fitsPath = savedUrl.deletingPathExtension().appendingPathExtension("fits")
                if FileManager.default.fileExists(atPath: fitsPath.path) {
                    fitsUrl = fitsPath
                } else {
                    // Fall back to what we have
                    completion([
                        ScienceProduct(
                            name: savedUrl.deletingPathExtension().lastPathComponent,
                            imageLocation: savedUrl,
                            sourceFileLocation: savedUrl,
                            headers: [],
                            coamResult: coamResult
                        )
                    ])
                    return
                }
            }
            let outputDir = fitsUrl.deletingLastPathComponent()
            let products = self.extractScienceProductsFromFits(
                fitsUrl: fitsUrl, outputDirectory: outputDir, coamResult: coamResult
            )
            completion(products)
        } else {
            // JPEG — single product, no FITS metadata
            let name = savedUrl.deletingPathExtension().lastPathComponent
            completion([
                ScienceProduct(
                    name: name,
                    imageLocation: savedUrl,
                    sourceFileLocation: savedUrl,
                    headers: [],
                    coamResult: coamResult
                )
            ])
        }
    }

    /** Get GAIA crossmatch
     parameters:
     * ra: Float
     dec: Float
     radius: Float
     */
    public func getGaiaCrossmatch(
        ra: Float, dec: Float, radius: Float, result: @escaping ([[Float]]) -> Void
    ) {
        print("getGaiaCrossmatch:  at radius \(radius)")

        let service = Service.Mast_GaiaDR3_Crossmatch
        var params = service.serviceRequest(requestType: .crossMatch)
        params.setCrossmatchinput(coordinates: [["ra": ra, "dec": dec, "radius": radius]])
        params.setParameters(params: [
            MAP.raColumn: "ra", MAP.decColumn: "dec", MAP.radius: radius,
            MAP.columns: "MatchRA,MatchDEC",
        ])
        var output = [[Float]]()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                for target in self.targets.keys {
                    let table = self.targets[target]
                    let RA = table!.getValues(for: "ra").map { $0.value as! Float }
                    let DEC = table!.getValues(for: "dec").map { $0.value as! Float }
                    let PARALLAX = table!.getValues(for: "parallax").map { $0.value as! Float }
                    let MAG = table!.getValues(for: "mag").map { $0.value as! Float }
                    for (i, _) in RA.enumerated() {
                        output.append([RA[i], DEC[i], PARALLAX[i], MAG[i]])
                    }
                }
                result(output)
            })
    }

    /** Get TIC crossmatch
     parameters:
     * ra: Float
     dec: Float
     radius: Float
     */
    func getTicCrossmatch(
        ra: Float, dec: Float, radius: Float, result: @escaping ([[Float]]) -> Void
    ) {
        print("getTicCrossmatch:  at radius \(radius)")

        let service = Service.Mast_Tic_Crossmatch
        var params = service.serviceRequest(requestType: .crossMatch)
        params.setCrossmatchinput(coordinates: [["ra": ra, "dec": dec, "radius": radius]])
        params.setParameters(params: [
            MAP.raColumn: "ra", MAP.decColumn: "dec", MAP.radius: radius,
            MAP.columns: "MatchRA,MatchDEC",
        ])
        var output = [[Float]]()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                for target in self.targets.keys {
                    let table = self.targets[target]
                    let RA = table!.getValues(for: "ra").map { $0.value as! Float }
                    let DEC = table!.getValues(for: "dec").map { $0.value as! Float }
                    let PLX = table!.getValues(for: "plx").map { $0.value as! Float }
                    for (i, _) in RA.enumerated() {
                        output.append([RA[i], DEC[i], PLX[i]])
                    }
                }
                result(output)
            })
    }

    /** Select a target by name and download preview image
     to the documents folder under MAST/target_name/instrument_name/
     */
    public func downloadPreview(
        targetName: String, pageSize: Int = 30, token: String? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        print("downloadpreview: \(targetName)")
        self.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(
            targetName: targetName,
            result: { targetLookup in
                guard !targetLookup.isEmpty, let table = self.targets[targetName] else {
                    print("downloadpreview: Unable to resolve \(targetName)")
                    completion(nil)
                    return
                }
                let targetEnd = CACurrentMediaTime()
                print("downloadpreview: target found in \(targetEnd - targetStart)")
                let resolved = table.getNameLookupResults().first!
                // Save the initial target info
                self.setTargetAssets(target: targetName, targetInfo: resolved)

                // Get the preview
                self.getMASTPreviewImage(
                    targetName: targetName, ra: resolved.ra, dec: resolved.dec,
                    radius: resolved.radius, pageSize: pageSize, token: token
                ) { urls in
                    completion(urls)
                }

            })
    }

    /** Get a PS1 multi filter stacked fits cutout
         Parameters:
         * target: string
         * size: squared image pixel size (0.25 arsec/pixel)
         */
    public func getPS1ImagePreview(
        targetName: String, imageSize: Int = 8000, downloadUrl: @escaping ([URL]) -> Void
    ) {
        print("getPS1ImagePreview: \(targetName)")

        self.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(
            targetName: targetName,
            result: { targetLookup in
                guard !targetLookup.isEmpty, let table = self.targets[targetName] else {
                    print("Unable to resolve \(targetName)")
                    downloadUrl([])
                    return
                }
                let targetEnd = CACurrentMediaTime()
                print("getPS1ImagePreview: target found in \(targetEnd - targetStart)")

                let resolved = table.getNameLookupResults().first!
                // Save the initial target info
                self.setTargetAssets(target: targetName, targetInfo: resolved)

                let ra = resolved.ra
                let dec = resolved.dec
                // radius is used to get pixel cutout
                // 0.25 arcsec / pixel
                let radius = resolved.radius
                let pixelSize = Int(radius / 0.25)
                print("\(targetName) radius \(radius) pixels \(pixelSize)")
                self.getPS1ImageList(
                    targetName: targetName, ra: ra, dec: dec, imageSize: imageSize,
                    completion: { filesTable in

                        guard let filesTable = filesTable else {
                            downloadUrl([])
                            return
                        }
                        // Get the r g and b filters
                        // https://ps1images.stsci.edu/ps1image.html
                        var fileNames = filesTable.getStringValues(for: "filename")
                        let filters = filesTable.getStringValues(for: "filter")

                        let yzirg = "yzirg"
                        var filterList = filters.map {
                            yzirg.range(of: $0)!.lowerBound.utf16Offset(in: yzirg)
                        }
                        filterList = filterList.enumerated().sorted { $0.element < $1.element }.map
                        { $0.offset }
                        filterList = Array(filterList[0..<3])
                        fileNames = filterList.map { fileNames[$0] }

                        // Form a request URL
                        let ps1Request = PS1Request(ra: ra, dec: dec, size: imageSize)
                        let url = ps1Request.getFitsColorImageUrl(fileNames: fileNames)

                        self.downloadPS1Cutouts(
                            targetName: targetName, urls: [url],
                            completion: { jpgUrls in
                                print("Download complete: adding files to documents folder")
                                downloadUrl(jpgUrls)

                            })
                    })

            })

    }

    /** Select a target by name and download all selectively filtered images
     to the documents folder under MAST/target_name/instrument_name/

     Parameters:
     * targetName: String - Name of the astronomical target (e.g., "M31", "NGC 1234")
     * productType: ProductType - .Fits or .Jpeg (default: .Jpeg)
       - When .Fits is selected: Downloads FITS files, extracts metadata, converts to JPEG for viewing
       - When .Jpeg is selected: Downloads JPEG preview images directly
     * filterOptions: ImageryFilterOptions - Filter criteria for the search (default: science images)
     * pageSize: Int - Number of results per page (default: 50)
     * page: Int - Page number for pagination (default: 1, first page)
     * token: String? - MAST authentication token for proprietary data
     * completion: Closure returning array of downloaded image URLs (JPEG format)

     Note: When using productType .Fits, the function:
     1. Filters for FITS files in the MAST archive
     2. Downloads and saves FITS files
     3. Extracts comprehensive metadata (accessible via getFitsMetadata())
     4. Converts FITS to JPEG for easy viewing
     5. Returns JPEG URLs in the completion handler

     Example usage:
     ```swift
     // Download UV-only imagery
     mast.downloadImagery(targetName: "M31", filterOptions: .uvOnly) { urls in
         print("Downloaded \(urls.count) UV images")
     }

     // Download Hubble images only
     mast.downloadImagery(targetName: "NGC 1234", filterOptions: .hubbleOnly) { urls in
         print("Downloaded \(urls.count) HST images")
     }

     // Download FITS files with metadata extraction
     mast.downloadImagery(targetName: "M31", productType: .Fits, filterOptions: .defaultScience) { urls in
         print("Downloaded \(urls.count) images (converted from FITS)")
         // Access metadata
         if let metadata = mast.getFitsMetadata(target: "M31") {
             print("Extracted metadata from \(metadata.count) FITS files")
         }
     }

     // Custom filter: JWST infrared images
     let customFilter = ImageryFilterOptions(
         wavelengthRegions: ["INFRARED"],
         collections: ["JWST"]
     )
     mast.downloadImagery(targetName: "M42", filterOptions: customFilter) { urls in
         print("Downloaded \(urls.count) JWST IR images")
     }

     // Pagination: Download page 2 of results
     mast.downloadImagery(targetName: "M31", pageSize: 10, page: 2) { urls in
         print("Downloaded \(urls.count) images from page 2")
     }
     ```
     */
    public func downloadImagery(
        targetName: String, productType: ProductType = .Jpeg,
        filterOptions: ImageryFilterOptions = .defaultScience, pageSize: Int = 50,
        page: Int = 1, token: String? = nil, completion: @escaping ([URL]) -> Void
    ) {
        self.log(
            .OK,
            message:
                "downloadImagery: Starting for '\(targetName)' with page=\(page), pageSize=\(pageSize)"
        )
        self.lookupTargetCoordinates(
            targetName: targetName,
            result: { coordinates in
                guard let coordinates = coordinates else {
                    self.log(
                        .RequestError,
                        message: "downloadImagery: Could not resolve target '\(targetName)'")
                    completion([])
                    return
                }

                self.getScienceImageProducts(
                    targetName: targetName, ra: coordinates.ra, dec: coordinates.dec,
                    radius: coordinates.radius, productType: productType,
                    filterOptions: filterOptions, pageSize: pageSize, page: page, token: token
                ) { urls in
                    self.log(
                        .OK,
                        message:
                            "downloadImagery: Completed with \(urls.count) images for '\(targetName)'"
                    )
                    completion(urls)
                }
            })
    }

    /** Make a MAST TAP request to get the current TESS Input Catalog entries
     */
    public func getTIC(completion: @escaping (MASTTAPResponse) -> Void) {
        let selectQuery = "SELECT id, hip FROM dbo.catalogrecord WHERE hip IS NOT NULL"
        queryMASTTap(
            selectQuery: selectQuery, table: .dbo_catalog_record, fields: [], parameters: [],
            format: .json,
            closure: { response in
                completion(response)
            })

    }

    /** Make a MAST TAP request to ge get tic and hip values ra/dec bounds
     */
    public func getTICBYRaDec(
        ra1: Double, ra2: Double, dec1: Double, dec2: Double,
        completion: @escaping (MASTTAPResponse) -> Void
    ) {
        //        let selectQuery = "SELECT TOP 100000 id,hip FROM dbo.catalogrecord WHERE ra > \(ra1) AND ra < \(ra2) AND dec > \(dec1) AND dec < \(dec2) AND hip IS NOT null"

        let selectQuery =
            "SELECT TOP 100000 id,HIP FROM dbo.catalogrecord WHERE (ra BETWEEN \(ra1) AND \(ra2)) AND (dec BETWEEN \(dec1) AND \(dec2)) AND hip IS NOT null"

        queryMASTTap(
            selectQuery: selectQuery, table: .dbo_catalog_record, fields: [], parameters: [],
            format: .json,
            closure: { response in
                completion(response)
            })

    }

    /** Make a MAST TAP request to ge get tic and hip from a list of hip
     */
    public func getTICByHipList(hips: [Int], completion: @escaping (MASTTAPResponse) -> Void) {

        let selectQuery =
            "SELECT TOP 100000 id,HIP FROM dbo.catalogrecord WHERE hip > \(hips[0]) and hip < \(hips[1]) "

        queryMASTTap(
            selectQuery: selectQuery, table: .dbo_catalog_record, fields: [], parameters: [],
            format: .json,
            closure: { response in
                completion(response)
            })

    }

    /** Make a MAST TAP request to get disc detection info on a given coordinate
     */
    public func getDiscDetection(
        target: String, ra: Float, dec: Float, radius: Float,
        completion: @escaping ([CoamResult]) -> Void
    ) {
        print("getDiscDetection: \(target) ra: \(ra) dec: \(dec) radiuss \(radius)")

        let start = CACurrentMediaTime()
        let service = Service.Mast_Catalogs_DiskDetective_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: ra, MAP.dec: dec, MAP.radius: radius])
        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        self.setTargetId(targetId: target)
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                print("getDiscDetection: search completed in \(end - start)")
                let table = self.targets[target]!
                let results = table.getCoamResults()
                self.enrichCoamResultsWithFileSizes(results, completion: completion)
            })
    }

    // MARK: - JWST Multi-Filter Science Products

    /** Query JWST science image products for a target, grouped by filter band.

     This function resolves the target, queries MAST for JWST public science images
     at calibration level 3–4, groups results by unique filter, and returns one
     ``CoamResult`` per filter — preferring products observed closest together in time.

     Use this to build a catalogue of available imagery across different wavelengths
     for a single target (e.g. F770W, F1000W, F1500W, …).

     Parameters:
     * targetName: String - the target identifier (e.g. "NGC 628", "NGC 253")
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE", "NIRCAM/IMAGE"])
       When nil, all JWST instruments are included.
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 200)
     * result: Closure returning a dictionary mapping filter name → CoamResult

     The returned dictionary maps each unique filter string (e.g. "F1000W") to the
     single best ``CoamResult`` for that filter. When multiple observations exist for
     the same filter, the one closest to the median observation epoch is chosen so
     that the selected products are as contemporaneous as possible.

     Example usage:
     ```swift
     let mast = SwiftMAST()
     // All JWST filters for NGC 628
     mast.getJWSTFilteredProducts(targetName: "NGC 628") { products in
         for (filter, coam) in products {
             print("\(filter): \(coam.obs_id)")
         }
     }

     // MIRI-only filters
     mast.getJWSTFilteredProducts(targetName: "NGC 253", instruments: ["MIRI/IMAGE"]) { products in
         for (filter, coam) in products {
             print("\(filter): \(coam.instrument_name) \(coam.obs_id)")
         }
     }
     ```
     */
    public func getJWSTFilteredProducts(
        targetName: String,
        instruments: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 200,
        result: @escaping ([String: CoamResult]) -> Void
    ) {
        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates = coordinates else {
                self.log(
                    .RequestError,
                    message:
                        "getJWSTFilteredProducts: Could not resolve target '\(targetName)'"
                )
                result([:])
                return
            }
            self.getJWSTFilteredProducts(
                targetName: targetName,
                ra: coordinates.ra,
                dec: coordinates.dec,
                radius: coordinates.radius,
                instruments: instruments,
                calibLevels: calibLevels,
                pageSize: pageSize,
                result: result
            )
        }
    }

    /** Query JWST science image products at given coordinates, grouped by filter band.

     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension
     * dec: Float - Declination
     * radius: Float - Search radius in degrees
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 200)
     * result: Closure returning a dictionary mapping filter name → CoamResult
     */
    public func getJWSTFilteredProducts(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        instruments: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 200,
        result: @escaping ([String: CoamResult]) -> Void
    ) {
        self.log(
            .OK,
            message:
                "getJWSTFilteredProducts: Starting for \(targetName) at RA=\(ra), Dec=\(dec), radius=\(radius)"
        )

        var filterOptions = ImageryFilterOptions(
            collections: ["JWST"],
            instruments: instruments,
            calibLevels: calibLevels
        )

        self.setTargetId(targetId: targetName)
        let service = Service.Mast_Caom_Filtered_Position
        var params = service.serviceRequest(requestType: .advancedSearch)

        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        params.setParameter(param: MAP.pagesize, value: pageSize)
        params.setParameter(param: MAP.page, value: 1)
        let filterParams = filterOptions.toMASTFilters()
        params.setFilterParameters(params: filterParams)
        params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])

        let start = CACurrentMediaTime()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                self.log(
                    .OK,
                    message:
                        "getJWSTFilteredProducts: Query completed in \(String(format: "%.2f", end - start))s"
                )

                guard let table = self.targets[targetName] else {
                    self.log(
                        .RequestError,
                        message:
                            "getJWSTFilteredProducts: No target table for '\(targetName)'"
                    )
                    result([:])
                    return
                }

                let coamResults = table.getCoamResults()
                self.log(
                    .OK,
                    message:
                        "getJWSTFilteredProducts: Found \(coamResults.count) total JWST products"
                )

                // Optionally filter by instrument in obs_id (e.g. "miri" in filename)
                let filteredResults: [CoamResult]
                if let instruments = instruments {
                    let lowerInstruments = instruments.map { $0.lowercased() }
                    filteredResults = coamResults.filter { coam in
                        lowerInstruments.contains(coam.instrument_name.lowercased())
                    }
                } else {
                    filteredResults = coamResults
                }

                guard !filteredResults.isEmpty else {
                    self.log(
                        .OK,
                        message:
                            "getJWSTFilteredProducts: No products after instrument filtering"
                    )
                    result([:])
                    return
                }

                // Group by filter
                var productsByFilter = [String: [CoamResult]]()
                for coam in filteredResults {
                    let filter = coam.filters
                    if productsByFilter[filter] == nil {
                        productsByFilter[filter] = [coam]
                    } else {
                        productsByFilter[filter]!.append(coam)
                    }
                }

                self.log(
                    .OK,
                    message:
                        "getJWSTFilteredProducts: \(productsByFilter.count) unique filters found: \(productsByFilter.keys.sorted().joined(separator: ", "))"
                )

                // Pick the best product per filter, preferring the closest common epoch
                let selected = self.selectClosestEpochProducts(productsByFilter: productsByFilter)

                self.log(
                    .OK,
                    message:
                        "getJWSTFilteredProducts: Selected \(selected.count) products across filters"
                )

                self.enrichCoamResultsWithFileSizes(Array(selected.values)) { enrichedAssets in
                    var enrichedSelected = [String: CoamResult]()
                    for coam in enrichedAssets {
                        enrichedSelected[coam.filters] = coam
                    }

                    if self.targetAssets[targetName] != nil {
                        self.targetAssets[targetName]!.setAssets(assets: enrichedAssets)
                    }

                    result(enrichedSelected)
                }
            })
    }

    // MARK: - JWST Multi-Filter Science Product Extraction

    /** Extract science products for each unique JWST filter band of a target.

     This is a convenience function that chains `getJWSTFilteredProducts` with
     `extractScienceProducts`: it first queries MAST for one ``CoamResult`` per
     unique filter, then downloads and extracts the FITS data for each, returning
     a dictionary mapping filter name → array of ``ScienceProduct`` (one per HDU
     in the FITS file).

     Parameters:
     * targetName: String - the target identifier (e.g. "NGC 628")
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 200)
     * token: String? - MAST authentication token (optional)
     * result: Closure returning a dictionary mapping filter name → [ScienceProduct]

     Example usage:
     ```swift
     let mast = SwiftMAST()
     mast.getJWSTScienceProducts(targetName: "NGC 628") { products in
         for (filter, scienceProducts) in products {
             print("\(filter): \(scienceProducts.count) HDU(s)")
             for sp in scienceProducts {
                 print("  \(sp.name) — \(sp.headers.count) headers")
             }
         }
     }
     ```
     */
    public func getJWSTScienceProducts(
        targetName: String,
        instruments: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 200,
        token: String? = nil,
        result: @escaping ([String: [ScienceProduct]]) -> Void
    ) {
        self.getJWSTFilteredProducts(
            targetName: targetName,
            instruments: instruments,
            calibLevels: calibLevels,
            pageSize: pageSize
        ) { filteredProducts in
            guard !filteredProducts.isEmpty else {
                result([:])
                return
            }

            self.log(
                .OK,
                message:
                    "getJWSTScienceProducts: Extracting science products for \(filteredProducts.count) filters"
            )

            var scienceProducts = [String: [ScienceProduct]]()
            let group = DispatchGroup()
            let lock = NSLock()

            for (filter, coam) in filteredProducts {
                group.enter()
                self.extractScienceProducts(
                    targetName: targetName, coamResult: coam, token: token
                ) { products in
                    if !products.isEmpty {
                        lock.lock()
                        scienceProducts[filter] = products
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.log(
                    .OK,
                    message:
                        "getJWSTScienceProducts: Extracted \(scienceProducts.count) science products across filters"
                )
                result(scienceProducts)
            }
        }
    }

    /** Extract science products for each unique JWST filter band at given coordinates.

     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension (degrees, J2000)
     * dec: Float - Declination (degrees, J2000)
     * radius: Float - Search radius in degrees
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 200)
     * token: String? - MAST authentication token (optional)
     * result: Closure returning a dictionary mapping filter name → [ScienceProduct]
     */
    public func getJWSTScienceProducts(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        instruments: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 200,
        token: String? = nil,
        result: @escaping ([String: [ScienceProduct]]) -> Void
    ) {
        self.getJWSTFilteredProducts(
            targetName: targetName,
            ra: ra,
            dec: dec,
            radius: radius,
            instruments: instruments,
            calibLevels: calibLevels,
            pageSize: pageSize
        ) { filteredProducts in
            guard !filteredProducts.isEmpty else {
                result([:])
                return
            }

            self.log(
                .OK,
                message:
                    "getJWSTScienceProducts: Extracting science products for \(filteredProducts.count) filters"
            )

            var scienceProducts = [String: [ScienceProduct]]()
            let group = DispatchGroup()
            let lock = NSLock()

            for (filter, coam) in filteredProducts {
                group.enter()
                self.extractScienceProducts(
                    targetName: targetName, coamResult: coam, token: token
                ) { products in
                    if !products.isEmpty {
                        lock.lock()
                        scienceProducts[filter] = products
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.log(
                    .OK,
                    message:
                        "getJWSTScienceProducts: Extracted \(scienceProducts.count) science products across filters"
                )
                result(scienceProducts)
            }
        }
    }

    /// Select one product per filter, choosing observations closest to the median epoch
    /// across all filters. This ensures the returned products are as contemporaneous as possible.
    internal func selectClosestEpochProducts(
        productsByFilter: [String: [CoamResult]]
    ) -> [String: CoamResult] {
        // Collect all observation timestamps
        var allTimestamps = [Float]()
        for products in productsByFilter.values {
            for p in products where p.t_min > 0 {
                allTimestamps.append(p.t_min)
            }
        }

        guard !allTimestamps.isEmpty else {
            // Fallback: just take first product per filter
            var output = [String: CoamResult]()
            for (filter, products) in productsByFilter {
                output[filter] = products.first
            }
            return output
        }

        // Find median timestamp as reference epoch
        allTimestamps.sort()
        let medianTimestamp: Float
        if allTimestamps.count % 2 == 0 {
            medianTimestamp =
                (allTimestamps[allTimestamps.count / 2 - 1]
                    + allTimestamps[allTimestamps.count / 2]) / 2.0
        } else {
            medianTimestamp = allTimestamps[allTimestamps.count / 2]
        }

        // For each filter, pick the product closest to the median epoch
        var output = [String: CoamResult]()
        for (filter, products) in productsByFilter {
            let best = products.min { a, b in
                let aDist = abs(a.t_min - medianTimestamp)
                let bDist = abs(b.t_min - medianTimestamp)
                return aDist < bDist
            }
            if let best = best {
                output[filter] = best
            }
        }

        return output
    }

    // MARK: - Observation Groups

    /** Query science products and group them by observation session for JWST, HST, or both.

     This is the mission-generic version of `getJWSTObservationGroups`. Existing JWST-specific
     functions remain available and call through the same grouping model.
     */
    public func getObservationGroups(
        targetName: String,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 400,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates = coordinates else {
                self.log(
                    .RequestError,
                    message: "getObservationGroups: Could not resolve target '\(targetName)'"
                )
                result([])
                return
            }

            self.getObservationGroups(
                targetName: targetName,
                ra: coordinates.ra,
                dec: coordinates.dec,
                radius: coordinates.radius,
                missions: missions,
                instruments: instruments,
                filterBands: filterBands,
                calibLevels: calibLevels,
                pageSize: pageSize,
                sortOrder: sortOrder,
                result: result
            )
        }
    }

    /** Query science products at given coordinates and group them by observation session.

     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension (degrees, J2000)
     * dec: Float - Declination (degrees, J2000)
     * radius: Float - Search radius in degrees
     * missions: [ObservationMission] - `.jwst`, `.hst`, or both
     * instruments: [String]? - optional instrument filter
     * filterBands: [String]? - optional filter band filter (e.g. ["F150W"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 400)
     * result: Closure returning an array of ``ObservationGroup``
     */
    public func getObservationGroups(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 400,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        let collections = Array(Set(missions.flatMap(\.collectionNames))).sorted()
        self.log(
            .OK,
            message:
                "getObservationGroups: Starting for \(targetName) collections=\(collections.joined(separator: ",")) at RA=\(ra), Dec=\(dec), radius=\(radius)"
        )

        let filterOptions = ImageryFilterOptions(
            collections: collections,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels
        )

        self.setTargetId(targetId: targetName)
        let service = Service.Mast_Caom_Filtered_Position
        var params = service.serviceRequest(requestType: .advancedSearch)

        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        params.setParameter(param: MAP.pagesize, value: pageSize)
        params.setParameter(param: MAP.page, value: 1)
        let filterParams = filterOptions.toMASTFilters()
        params.setFilterParameters(params: filterParams)
        params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])

        let start = CACurrentMediaTime()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                self.log(
                    .OK,
                    message:
                        "getObservationGroups: Query completed in \(String(format: "%.2f", end - start))s"
                )

                guard let table = self.targets[targetName] else {
                    self.log(
                        .RequestError,
                        message: "getObservationGroups: No target table for '\(targetName)'"
                    )
                    result([])
                    return
                }

                let coamResults = table.getCoamResults()
                self.log(
                    .OK,
                    message: "getObservationGroups: Found \(coamResults.count) total products"
                )

                let lowerCollections = Set(collections.map { $0.lowercased() })
                var filteredResults = coamResults.filter {
                    lowerCollections.contains($0.obs_collection.lowercased())
                }

                if let instruments = instruments {
                    let lowerInstruments = Set(instruments.map { $0.lowercased() })
                    filteredResults = filteredResults.filter {
                        lowerInstruments.contains($0.instrument_name.lowercased())
                    }
                }

                if let filterBands = filterBands, !filterBands.isEmpty {
                    filteredResults = filteredResults.filter {
                        $0.matchesObservationFilterBands(filterBands)
                    }
                }

                guard !filteredResults.isEmpty else {
                    self.log(.OK, message: "getObservationGroups: No products after filtering")
                    result([])
                    return
                }

                self.enrichCoamResultsWithFileSizes(filteredResults) { enrichedResults in
                    self.enrichCoamResultsWithFITSImageMetadata(enrichedResults) {
                        enrichedImageResults in
                        let groups = self.buildObservationGroups(
                            from: enrichedImageResults, sortOrder: sortOrder)

                        self.log(
                            .OK,
                            message: "getObservationGroups: Built \(groups.count) observation groups"
                        )

                        result(groups)
                    }
                }
            })
    }

    // MARK: - JWST Observation Groups

    /** Query JWST science products and group them by observation session.

     Each observation group shares the same program, observation number, target,
     and instrument (derived from the `obs_id` prefix). Within each group, products
     are sorted by filter wavelength in ascending order (e.g. F200W before F1000W).

     This is useful for viewing all filter bands captured in a single observation
     session, organized by instrument.

     Parameters:
     * targetName: String - the target identifier (e.g. "NGC 628", "NGC 253")
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE"])
     * filterBands: [String]? - optional filter band filter (e.g. ["F150W"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 400)
     * result: Closure returning an array of ``JWSTObservationGroup``, sorted by observation key

     Example usage:
     ```swift
     let mast = SwiftMAST()
     mast.getJWSTObservationGroups(targetName: "NGC 628") { groups in
         for group in groups {
             print(group.observationKey)
             print("  instrument: \(group.instrument)")
             for product in group.products {
                 print("  \(product.filters): \(product.obs_id)")
             }
         }
     }
     ```
     */
    public func getJWSTObservationGroups(
        targetName: String,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 400,
        sortOrder: JWSTProductSortOrder = .filter,
        result: @escaping ([JWSTObservationGroup]) -> Void
    ) {
        self.getObservationGroups(
            targetName: targetName,
            missions: ObservationMission.jwstOnly,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            pageSize: pageSize,
            sortOrder: sortOrder,
            result: result
        )
    }

    /** Query JWST science products at given coordinates and group by observation session.

     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension (degrees, J2000)
     * dec: Float - Declination (degrees, J2000)
     * radius: Float - Search radius in degrees
     * instruments: [String]? - optional instrument filter (e.g. ["MIRI/IMAGE"])
     * filterBands: [String]? - optional filter band filter (e.g. ["F150W"])
     * calibLevels: [String] - calibration levels (default: ["3", "4"])
     * pageSize: Int - number of results per page (default: 400)
     * result: Closure returning an array of ``JWSTObservationGroup``
     */
    public func getJWSTObservationGroups(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String] = ["3", "4"],
        pageSize: Int = 400,
        sortOrder: JWSTProductSortOrder = .filter,
        result: @escaping ([JWSTObservationGroup]) -> Void
    ) {
        self.getObservationGroups(
            targetName: targetName,
            ra: ra,
            dec: dec,
            radius: radius,
            missions: ObservationMission.jwstOnly,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            pageSize: pageSize,
            sortOrder: sortOrder,
            result: result
        )
    }

    /// Build observation groups from a flat array of CoamResults.
    /// Groups by obs_id prefix, sorts products within each group by the given sort order,
    /// and sorts groups by observation key.
    internal func buildObservationGroups(
        from results: [CoamResult],
        sortOrder: ObservationProductSortOrder = .filter
    ) -> [ObservationGroup] {
        // Group by observation key
        var grouped = [String: [CoamResult]]()
        for coam in results {
            let key = observationGroupKey(coam)
            if grouped[key] == nil {
                grouped[key] = [coam]
            } else {
                grouped[key]!.append(coam)
            }
        }

        // Build sorted groups
        var groups = [ObservationGroup]()
        for (key, products) in grouped {
            let sorted = products.sorted { compareObservationProducts($0, $1, by: sortOrder) }
            let instrument = sorted.first?.instrument_name ?? ""
            let mission = sorted.first?.observationMission?.rawValue ?? sorted.first?.obs_collection ?? ""
            groups.append(
                ObservationGroup(
                    mission: mission,
                    observationKey: key,
                    instrument: instrument,
                    products: sorted
                ))
        }

        // Sort groups by key
        groups.sort { $0.observationKey < $1.observationKey }
        return groups
    }

}
