//
//  SwiftMAST+API.swift
//
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation
import QuartzCore
import SwiftQValue

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

    /** Search science image CAOM results inside or overlapping a CAOM `s_region` footprint.

     MAST's CAOM position endpoint accepts a cone (`ra, dec, radius`), not a polygon. This method
     parses the input footprint, queries MAST with its bounding cone, then applies the requested
     local footprint match mode to the returned `CoamResult.s_region` values.

     Parameters:
     * targetName: String - Label used to store this query's result table
     * spaceRegion: String - Source CAOM `s_region` value (CIRCLE or POLYGON)
     * containment: SpaceRegionContainmentMode - local footprint matching rule
     * filterOptions: ImageryFilterOptions - Filter criteria for the search (default: science images)
     * pageSize: Int - Number of candidate rows to request from MAST
     * page: Int - Page number for pagination
     * result: Closure returning footprint-filtered CoamResult entries
     */
    public func getScienceImageQueryResults(
        targetName: String,
        spaceRegion: String,
        containment: SpaceRegionContainmentMode = .footprintIntersects,
        filterOptions: ImageryFilterOptions = .defaultScience,
        pageSize: Int = 400,
        page: Int = 1,
        result: @escaping ([CoamResult]) -> Void
    ) {
        guard let sourceRegion = SpaceRegion(spaceRegion),
              let cone = sourceRegion.boundingCone
        else {
            self.log(
                .RequestError,
                message: "getScienceImageQueryResults: Could not parse source s_region"
            )
            result([])
            return
        }

        self.getScienceImageQueryResults(
            targetName: targetName,
            ra: Float(cone.ra),
            dec: Float(cone.dec),
            radius: Float(cone.radius),
            filterOptions: filterOptions,
            pageSize: pageSize,
            page: page
        ) { candidates in
            result(
                candidates.filter {
                    guard let candidateRegion = $0.spaceRegion else { return false }
                    return sourceRegion.matches(
                        candidate: candidateRegion,
                        candidateCenter: $0.spaceRegionCenter,
                        mode: containment
                    )
                }
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

    /** Query observation groups for one mission/collection.

     This convenience overload avoids wrapping a single selection in an array.
     Use the `missions:` overload to query any combination of collections.
     */
    public func getObservationGroups(
        targetName: String,
        mission: ObservationMission,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        getObservationGroups(
            targetName: targetName,
            missions: [mission],
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder,
            result: result
        )
    }

    /** Query science products and group them by observation session for supported MAST collections.

     This is the mission-generic version of `getJWSTObservationGroups`. Existing JWST-specific
     functions remain available and call through the same grouping model.
     */
    public func getObservationGroups(
        targetName: String,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates = coordinates else {
                self.log(
                    .RequestError,
                    message: "Could not resolve target for observation search",
                    metadata: [
                        "event": "observationSearchTargetResolutionFailed",
                        "targetName": targetName,
                    ]
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
                dataProductTypes: dataProductTypes,
                pageSize: pageSize,
                limit: limit,
                sortOrder: sortOrder,
                result: result
            )
        }
    }

    /** Query observation groups inside or overlapping a CAOM `s_region` footprint.

     The MAST API is queried with a bounding cone derived from `spaceRegion`; returned products are
     then locally filtered by their own `s_region` using `containment`.
     */
    public func getObservationGroups(
        targetName: String,
        spaceRegion: String,
        containment: SpaceRegionContainmentMode = .footprintIntersects,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        guard let sourceRegion = SpaceRegion(spaceRegion),
              let cone = sourceRegion.boundingCone
        else {
            self.log(
                .RequestError,
                message: "Could not parse observation search region",
                metadata: [
                    "event": "observationSearchRegionParseFailed",
                    "spaceRegion": spaceRegion,
                ]
            )
            result([])
            return
        }

        self.log(
            .OK,
            message: "Prepared observation search region",
            metadata: [
                "audience": "developer",
                "event": "observationSearchRegionPrepared",
                "ra": String(cone.ra),
                "dec": String(cone.dec),
                "radius": String(cone.radius),
                "containment": containment.rawValue,
            ]
        )

        self.getObservationGroups(
            targetName: targetName,
            ra: Float(cone.ra),
            dec: Float(cone.dec),
            radius: Float(cone.radius),
            missions: missions,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder
        ) { groups in
            let candidateProductCount = groups.reduce(0) { $0 + $1.products.count }
            self.log(
                .OK,
                message: "Filtering observations by footprint",
                metadata: [
                    "audience": "developer",
                    "event": "observationFootprintFilterStarted",
                    "candidateGroups": String(groups.count),
                    "candidateProducts": String(candidateProductCount),
                ]
            )

            let filteredGroups = groups.compactMap { group -> ObservationGroup? in
                let products = group.products.filter {
                    guard let candidateRegion = $0.spaceRegion else { return false }
                    return sourceRegion.matches(
                        candidate: candidateRegion,
                        candidateCenter: $0.spaceRegionCenter,
                        mode: containment
                    )
                }

                guard !products.isEmpty else { return nil }
                return ObservationGroup(
                    mission: group.mission,
                    observationKey: group.observationKey,
                    instrument: group.instrument,
                    products: products
                )
            }

            let effectiveLimit = self.effectiveObservationGroupLimit(pageSize: pageSize, limit: limit)
            let limitedGroups = self.limitedObservationGroups(
                filteredGroups, effectiveLimit: effectiveLimit)
            let matchedProductCount = filteredGroups.reduce(0) { $0 + $1.products.count }
            self.log(
                .OK,
                message: "Filtered observations by footprint",
                metadata: [
                    "audience": "developer",
                    "event": "observationFootprintFilterFinished",
                    "matchedGroups": String(filteredGroups.count),
                    "matchedProducts": String(matchedProductCount),
                    "returnedGroups": String(limitedGroups.count),
                ]
            )
            result(limitedGroups)
        }
    }

    /** Query observation groups for one mission/collection inside or overlapping an `s_region`. */
    public func getObservationGroups(
        targetName: String,
        spaceRegion: String,
        containment: SpaceRegionContainmentMode = .footprintIntersects,
        mission: ObservationMission,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        getObservationGroups(
            targetName: targetName,
            spaceRegion: spaceRegion,
            containment: containment,
            missions: [mission],
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder,
            result: result
        )
    }

    /** Query observation groups at coordinates for one mission/collection.

     Use the `missions:` overload to query any combination of collections.
     */
    public func getObservationGroups(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        mission: ObservationMission,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        getObservationGroups(
            targetName: targetName,
            ra: ra,
            dec: dec,
            radius: radius,
            missions: [mission],
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder,
            result: result
        )
    }

    /** Query science products at given coordinates and group them by observation session.

     Parameters:
     * targetName: String - the target identifier
     * ra: Float - Right Ascension (degrees, J2000)
     * dec: Float - Declination (degrees, J2000)
     * radius: Float - Search radius in degrees
     * missions: [ObservationMission] - supported MAST mission/collection families
     * instruments: [String]? - optional instrument filter
     * filterBands: [String]? - optional filter band filter (e.g. ["F150W"])
     * calibLevels: [String]? - calibration levels; nil chooses collection-aware defaults
     * dataProductTypes: [String]? - CAOM product types; nil chooses collection-aware imagery defaults
     * pageSize: Int - number of results per page (default: 400)
     * limit: Int? - maximum observation groups to return; also caps the MAST page size
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
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        if let limit, limit <= 0 {
            self.log(
                .OK,
                message: "Finished grouping observations",
                metadata: [
                    "event": "observationSearchSkipped",
                    "limit": String(limit),
                    "returnedGroups": "0",
                ]
            )
            result([])
            return
        }

        let effectiveLimit = effectiveObservationGroupLimit(pageSize: pageSize, limit: limit)
        let effectivePageSize = limitedPageSize(pageSize, effectiveLimit: effectiveLimit)
        let collections = Array(Set(missions.flatMap(\.collectionNames))).sorted()
        let resolvedCalibLevels = calibLevels
            ?? Array(Set(missions.flatMap(\.defaultCalibrationLevels))).sorted()
        let resolvedDataProductTypes = dataProductTypes
            ?? Array(Set(missions.flatMap(\.imageryDataProductTypes))).sorted()
        self.log(
            .OK,
            message: "Started observation search",
            metadata: [
                "event": "observationSearchStarted",
                "targetName": targetName,
                "collections": collections.joined(separator: ","),
                "ra": String(ra),
                "dec": String(dec),
                "radius": String(radius),
            ]
        )
        self.log(
            .OK,
            message: "Prepared observation search settings",
            metadata: [
                "audience": "developer",
                "event": "observationSearchSettingsPrepared",
                "pageSize": String(pageSize),
                "effectivePageSize": String(effectivePageSize),
                "limit": String(effectiveLimit),
                "sortOrder": String(describing: sortOrder),
            ]
        )
        self.log(
            .OK,
            message: "Prepared observation search filters",
            metadata: [
                "audience": "developer",
                "event": "observationSearchFiltersPrepared",
                "instruments": instruments?.joined(separator: ",") ?? "any",
                "filterBands": filterBands?.joined(separator: ",") ?? "any",
                "calibLevels": resolvedCalibLevels.joined(separator: ","),
                "dataProductTypes": resolvedDataProductTypes.joined(separator: ","),
            ]
        )

        let filterOptions = ImageryFilterOptions(
            collections: collections,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: resolvedCalibLevels,
            dataProductTypes: resolvedDataProductTypes
        )

        self.setTargetId(targetId: targetName)
        let service = Service.Mast_Caom_Filtered_Position
        var params = service.serviceRequest(requestType: .advancedSearch)

        self.log(
            .OK,
            message: "Preparing observation search request",
            metadata: [
                "audience": "developer",
                "event": "observationSearchRequestPrepared",
                "service": service.id,
            ]
        )
        params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        params.setParameter(param: MAP.pagesize, value: effectivePageSize)
        params.setParameter(param: MAP.page, value: 1)
        let filterParams = filterOptions.toMASTFilters()
        params.setFilterParameters(params: filterParams)
        params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])
        self.log(
            .OK,
            message: "Submitting observation search",
            metadata: [
                "audience": "developer",
                "event": "observationSearchRequestSubmitted",
                "position": "\(ra), \(dec), \(radius)",
                "filterCount": String(filterParams.count),
            ]
        )

        let start = CACurrentMediaTime()
        self.queryMast(
            service: service, params: params, returnType: .json,
            { success in
                let end = CACurrentMediaTime()
                self.log(
                    .OK,
                    message: "Finished observation search",
                    durationSeconds: end - start,
                    metadata: ["event": "observationSearchFinished"]
                )
                self.log(
                    success ? .OK : .RequestError,
                    message: success ? "Observation search returned results" : "Observation search failed",
                    metadata: [
                        "audience": success ? "developer" : "user",
                        "event": "observationSearchQueryResult",
                        "success": String(success),
                    ]
                )

                guard let table = self.targets[targetName] else {
                    self.log(
                        .RequestError,
                        message: "Observation search returned no table",
                        metadata: [
                            "event": "observationSearchMissingTable",
                            "targetName": targetName,
                        ]
                    )
                    result([])
                    return
                }

                let coamResults = table.getCoamResults()
                self.log(
                    .OK,
                    message: "Found observation products",
                    metadata: [
                        "event": "observationProductsFound",
                        "productCount": String(coamResults.count),
                    ]
                )

                let lowerCollections = Set(collections.map { $0.lowercased() })
                var filteredResults = coamResults.filter {
                    lowerCollections.contains($0.obs_collection.lowercased())
                }
                self.log(
                    .OK,
                    message: "Filtered observations by collection",
                    metadata: [
                        "audience": "developer",
                        "event": "observationCollectionFilterFinished",
                        "remainingProducts": String(filteredResults.count),
                        "inputProducts": String(coamResults.count),
                    ]
                )

                if let instruments = instruments {
                    let beforeInstrumentFilter = filteredResults.count
                    let lowerInstruments = Set(instruments.map { $0.lowercased() })
                    filteredResults = filteredResults.filter {
                        lowerInstruments.contains($0.instrument_name.lowercased())
                    }
                    self.log(
                        .OK,
                        message: "Filtered observations by instrument",
                        metadata: [
                            "audience": "developer",
                            "event": "observationInstrumentFilterFinished",
                            "remainingProducts": String(filteredResults.count),
                            "inputProducts": String(beforeInstrumentFilter),
                        ]
                    )
                } else {
                    self.log(
                        .OK,
                        message: "No instrument filter applied",
                        metadata: [
                            "audience": "developer",
                            "event": "observationInstrumentFilterSkipped",
                        ]
                    )
                }

                if let filterBands = filterBands, !filterBands.isEmpty {
                    let beforeFilterBandFilter = filteredResults.count
                    filteredResults = filteredResults.filter {
                        $0.matchesObservationFilterBands(filterBands)
                    }
                    self.log(
                        .OK,
                        message: "Filtered observations by filter band",
                        metadata: [
                            "audience": "developer",
                            "event": "observationFilterBandFilterFinished",
                            "remainingProducts": String(filteredResults.count),
                            "inputProducts": String(beforeFilterBandFilter),
                        ]
                    )
                } else {
                    self.log(
                        .OK,
                        message: "No filter-band filter applied",
                        metadata: [
                            "audience": "developer",
                            "event": "observationFilterBandFilterSkipped",
                        ]
                    )
                }

                guard !filteredResults.isEmpty else {
                    self.log(
                        .OK,
                        message: "Finished grouping observations",
                        metadata: [
                            "event": "observationGroupingFinished",
                            "returnedGroups": "0",
                        ]
                    )
                    result([])
                    return
                }

                self.log(
                    .OK,
                    message: "Checking product file sizes",
                    metadata: [
                        "event": "observationFileSizeEnrichmentStarted",
                        "productCount": String(filteredResults.count),
                    ]
                )
                self.enrichCoamResultsWithFileSizes(filteredResults) { enrichedResults in
                    let sizedProducts = enrichedResults.filter { $0.preferredDownloadSizeBytes != nil }.count
                    self.log(
                        .OK,
                        message: "Checked product file sizes",
                        metadata: [
                            "event": "observationFileSizeEnrichmentFinished",
                            "sizedProducts": String(sizedProducts),
                            "productCount": String(enrichedResults.count),
                        ]
                    )
                    self.log(
                        .OK,
                        message: "Reading FITS image headers",
                        metadata: [
                            "event": "observationFITSHeaderEnrichmentStarted",
                            "productCount": String(enrichedResults.count),
                        ]
                    )
                    self.enrichCoamResultsWithFITSImageMetadata(enrichedResults) {
                        enrichedImageResults in
                        let metadataProducts =
                            enrichedImageResults.filter { $0.fitsImageHeaderMetadata != nil }.count
                        self.log(
                            .OK,
                            message: "Read FITS image headers",
                            metadata: [
                                "event": "observationFITSHeaderEnrichmentFinished",
                                "metadataProducts": String(metadataProducts),
                                "productCount": String(enrichedImageResults.count),
                            ]
                        )
                        self.log(
                            .OK,
                            message: "Grouping observations",
                            metadata: [
                                "event": "observationGroupingStarted",
                                "productCount": String(enrichedImageResults.count),
                            ]
                        )
                        let groups = self.buildObservationGroups(
                            from: enrichedImageResults, sortOrder: sortOrder)

                        let limitedGroups = self.limitedObservationGroups(
                            groups, effectiveLimit: effectiveLimit)
                        self.log(
                            .OK,
                            message: "Finished grouping observations",
                            metadata: [
                                "event": "observationGroupingFinished",
                                "builtGroups": String(groups.count),
                                "returnedGroups": String(limitedGroups.count),
                            ]
                        )

                        result(limitedGroups)
                    }
                }
            })
    }

    /** Query science products using MAST CAOM TAP and group them by observation session.

     This TAP-backed variant returns the same ``ObservationGroup`` model as `getObservationGroups`,
     but uses ADQL against the CAOM TAP service instead of the Mast.Caom Mashup endpoint. TAP rows
     include artifact `contentlength` when available, so FITS file sizes can be attached without a
     separate product-size lookup. FITS header metadata enrichment remains available for WCS details.
     */
    public func getObservationGroupsUsingTAP(
        targetName: String,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        includeFITSImageHeaderMetadata: Bool = true,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates = coordinates else {
                self.log(
                    .RequestError,
                    message: "Could not resolve target for TAP observation search",
                    metadata: [
                        "event": "tapObservationSearchTargetResolutionFailed",
                        "targetName": targetName,
                    ]
                )
                result([])
                return
            }

            self.getObservationGroupsUsingTAP(
                targetName: targetName,
                ra: coordinates.ra,
                dec: coordinates.dec,
                radius: coordinates.radius,
                missions: missions,
                instruments: instruments,
                filterBands: filterBands,
                calibLevels: calibLevels,
                dataProductTypes: dataProductTypes,
                pageSize: pageSize,
                limit: limit,
                sortOrder: sortOrder,
                includeFITSImageHeaderMetadata: includeFITSImageHeaderMetadata,
                result: result
            )
        }
    }

    /** Query TAP observation groups inside or overlapping a CAOM `s_region` footprint. */
    public func getObservationGroupsUsingTAP(
        targetName: String,
        spaceRegion: String,
        containment: SpaceRegionContainmentMode = .footprintIntersects,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        includeFITSImageHeaderMetadata: Bool = true,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        guard let sourceRegion = SpaceRegion(spaceRegion),
              let cone = sourceRegion.boundingCone
        else {
            self.log(
                .RequestError,
                message: "Could not parse TAP observation search region",
                metadata: [
                    "event": "tapObservationSearchRegionParseFailed",
                    "spaceRegion": spaceRegion,
                ]
            )
            result([])
            return
        }

        self.getObservationGroupsUsingTAP(
            targetName: targetName,
            ra: Float(cone.ra),
            dec: Float(cone.dec),
            radius: Float(cone.radius),
            missions: missions,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder,
            includeFITSImageHeaderMetadata: includeFITSImageHeaderMetadata
        ) { groups in
            let filteredGroups = groups.compactMap { group -> ObservationGroup? in
                let products = group.products.filter {
                    guard let candidateRegion = $0.spaceRegion else { return false }
                    return sourceRegion.matches(
                        candidate: candidateRegion,
                        candidateCenter: $0.spaceRegionCenter,
                        mode: containment
                    )
                }

                guard !products.isEmpty else { return nil }
                return ObservationGroup(
                    mission: group.mission,
                    observationKey: group.observationKey,
                    instrument: group.instrument,
                    products: products
                )
            }

            let effectiveLimit = self.effectiveObservationGroupLimit(pageSize: pageSize, limit: limit)
            let limitedGroups = self.limitedObservationGroups(
                filteredGroups, effectiveLimit: effectiveLimit)
            self.log(
                .OK,
                message: "Filtered observations by footprint",
                metadata: [
                    "event": "tapObservationFootprintFilterFinished",
                    "matchedGroups": String(filteredGroups.count),
                    "matchedProducts": String(filteredGroups.reduce(0) { $0 + $1.products.count }),
                    "returnedGroups": String(limitedGroups.count),
                ]
            )
            result(limitedGroups)
        }
    }

    /** Query science products at coordinates using MAST CAOM TAP and group them by observation session. */
    public func getObservationGroupsUsingTAP(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int = 400,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder = .filter,
        includeFITSImageHeaderMetadata: Bool = true,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        let policy: ObservationFITSHeaderFetchPolicy = includeFITSImageHeaderMetadata ? .all : .none
        getObservationGroupsUsingTAP(
            targetName: targetName,
            ra: ra,
            dec: dec,
            radius: radius,
            missions: missions,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: calibLevels,
            dataProductTypes: dataProductTypes,
            pageSize: pageSize,
            limit: limit,
            sortOrder: sortOrder,
            columnProfile: .observationGroupDefault,
            productKinds: [],
            headerFetchPolicy: policy,
            result: result
        )
    }

    /// Query target-composite science FITS candidates using a narrow CAOM TAP profile.
    public func getTargetCompositeCandidates(
        targetName: String?,
        ra: Double?,
        dec: Double?,
        radiusDegrees: Double,
        missions: [ObservationMission] = ObservationMission.jwstAndHST,
        filters: [String]? = nil,
        columns: ObservationTAPColumnProfile = .targetCompositeSelection,
        productKinds: [ObservationTAPProductKind] = [.scienceFITS],
        pageSize: Int = 400,
        maxProductsPerFilter: Int? = nil,
        headerFetchPolicy: ObservationFITSHeaderFetchPolicy = .shortlistedOnly(maxPerFilter: 1),
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        if let ra, let dec {
            getObservationGroupsUsingTAP(
                targetName: targetName ?? "Coordinate target",
                ra: Float(ra),
                dec: Float(dec),
                radius: Float(radiusDegrees),
                missions: missions,
                filterBands: filters,
                pageSize: pageSize,
                limit: nil,
                sortOrder: .filter,
                columnProfile: columns,
                productKinds: productKinds,
                maxProductsPerFilter: maxProductsPerFilter,
                headerFetchPolicy: headerFetchPolicy,
                result: result
            )
            return
        }

        guard let targetName else {
            self.log(
                .RequestError,
                message: "Target composite TAP search requires coordinates or a target name",
                metadata: [
                    "event": "tapObservationSearchTargetResolutionFailed"
                ]
            )
            result([])
            return
        }

        self.lookupTargetCoordinates(targetName: targetName) { coordinates in
            guard let coordinates else {
                self.log(
                    .RequestError,
                    message: "Could not resolve target for target composite TAP search",
                    metadata: [
                        "event": "tapObservationSearchTargetResolutionFailed",
                        "targetName": targetName,
                    ]
                )
                result([])
                return
            }

            self.getTargetCompositeCandidates(
                targetName: targetName,
                ra: Double(coordinates.ra),
                dec: Double(coordinates.dec),
                radiusDegrees: radiusDegrees,
                missions: missions,
                filters: filters,
                columns: columns,
                productKinds: productKinds,
                pageSize: pageSize,
                maxProductsPerFilter: maxProductsPerFilter,
                headerFetchPolicy: headerFetchPolicy,
                result: result
            )
        }
    }

    private func getObservationGroupsUsingTAP(
        targetName: String,
        ra: Float,
        dec: Float,
        radius: Float,
        missions: [ObservationMission],
        instruments: [String]? = nil,
        filterBands: [String]? = nil,
        calibLevels: [String]? = nil,
        dataProductTypes: [String]? = nil,
        pageSize: Int,
        limit: Int? = nil,
        sortOrder: ObservationProductSortOrder,
        columnProfile: ObservationTAPColumnProfile,
        productKinds: [ObservationTAPProductKind],
        maxProductsPerFilter: Int? = nil,
        headerFetchPolicy: ObservationFITSHeaderFetchPolicy,
        result: @escaping ([ObservationGroup]) -> Void
    ) {
        if let limit, limit <= 0 {
            self.log(
                .OK,
                message: "Finished grouping observations",
                metadata: [
                    "event": "tapObservationSearchSkipped",
                    "limit": String(limit),
                    "returnedGroups": "0",
                ]
            )
            result([])
            return
        }

        let effectiveLimit = effectiveObservationGroupLimit(pageSize: pageSize, limit: limit)
        let effectivePageSize = limitedPageSize(pageSize, effectiveLimit: effectiveLimit)
        let collections = Array(Set(missions.flatMap(\.collectionNames))).sorted()
        let resolvedCalibLevels = calibLevels
            ?? Array(Set(missions.flatMap(\.defaultCalibrationLevels))).sorted()
        let resolvedDataProductTypes = dataProductTypes
            ?? Array(Set(missions.flatMap(\.imageryDataProductTypes))).sorted()
        let query = caomObservationGroupsTAPQuery(
            ra: ra,
            dec: dec,
            radius: radius,
            collections: collections,
            instruments: instruments,
            filterBands: filterBands,
            calibLevels: resolvedCalibLevels,
            dataProductTypes: resolvedDataProductTypes,
            pageSize: effectivePageSize,
            columnProfile: columnProfile,
            productKinds: productKinds
        )

        self.log(
            .OK,
            message: "Started TAP observation search",
            metadata: [
                "event": "tapObservationSearchStarted",
                "targetName": targetName,
                "collections": collections.joined(separator: ","),
                "ra": String(ra),
                "dec": String(dec),
                "radius": String(radius),
            ]
        )

        let start = CACurrentMediaTime()
        self.queryMASTTap(
            selectQuery: query,
            table: .tap_schema_columns,
            fields: [],
            parameters: [],
            endpoint: .caom
        ) { response in
            let queryDuration = CACurrentMediaTime() - start
            let tapResults = self.coamResultsFromCAOMTapResponse(
                response,
                columnProfile: columnProfile
            )
            let sizedProducts = tapResults.filter { $0.preferredDownloadSizeBytes != nil }.count
            self.log(
                .OK,
                message: "Finished TAP observation search",
                durationSeconds: queryDuration,
                metadata: [
                    "event": "tapObservationSearchFinished",
                    "productCount": String(tapResults.count),
                    "sizedProducts": String(sizedProducts),
                    "fitsHeaderMetadataRequested": String(headerFetchPolicy != .none),
                ]
            )

            guard !tapResults.isEmpty else {
                self.log(
                    .OK,
                    message: "Finished grouping observations",
                    metadata: [
                        "event": "tapObservationGroupingFinished",
                        "returnedGroups": "0",
                    ]
                )
                result([])
                return
            }

            let finish: ([CoamResult]) -> Void = { products in
                let filteredProducts = self.limitTargetCompositeProductsPerFilter(
                    products,
                    maxProductsPerFilter: maxProductsPerFilter
                )
                let groups = self.buildObservationGroups(from: filteredProducts, sortOrder: sortOrder)
                let limitedGroups = self.limitedObservationGroups(groups, effectiveLimit: effectiveLimit)
                self.log(
                    .OK,
                    message: "Finished grouping observations",
                    metadata: [
                        "event": "tapObservationGroupingFinished",
                        "builtGroups": String(groups.count),
                        "returnedGroups": String(limitedGroups.count),
                    ]
                )
                result(limitedGroups)
            }

            let productsToEnrich = self.productsForHeaderPolicy(
                tapResults,
                headerFetchPolicy: headerFetchPolicy
            )
            guard !productsToEnrich.isEmpty else {
                finish(tapResults)
                return
            }

            self.log(
                .OK,
                message: "Reading FITS image headers",
                metadata: [
                    "event": "tapObservationFITSHeaderEnrichmentStarted",
                    "productCount": String(productsToEnrich.count),
                ]
            )
            let metadataStart = CACurrentMediaTime()
            self.enrichCoamResultsWithFITSImageMetadata(productsToEnrich) { enrichedResults in
                let metadataDuration = CACurrentMediaTime() - metadataStart
                let metadataProducts =
                    enrichedResults.filter { $0.fitsImageHeaderMetadata != nil }.count
                let mergedResults = self.mergeFITSHeaderMetadata(
                    enrichedResults,
                    into: tapResults
                )
                self.log(
                    .OK,
                    message: "Read FITS image headers",
                    durationSeconds: metadataDuration,
                    metadata: [
                        "event": "tapObservationFITSHeaderEnrichmentFinished",
                        "metadataProducts": String(metadataProducts),
                        "productCount": String(enrichedResults.count),
                    ]
                )
                finish(mergedResults)
            }
        }
    }

    internal func effectiveObservationGroupLimit(pageSize: Int, limit: Int?) -> Int {
        limit ?? pageSize
    }

    internal func limitedPageSize(_ pageSize: Int, effectiveLimit: Int) -> Int {
        max(1, min(pageSize, effectiveLimit))
    }

    internal func limitedObservationGroups(
        _ groups: [ObservationGroup],
        effectiveLimit: Int
    ) -> [ObservationGroup] {
        Array(groups.prefix(max(0, effectiveLimit)))
    }

    internal func caomObservationGroupsTAPQuery(
        ra: Float,
        dec: Float,
        radius: Float,
        collections: [String],
        instruments: [String]?,
        filterBands: [String]?,
        calibLevels: [String],
        dataProductTypes: [String],
        pageSize: Int,
        columnProfile: ObservationTAPColumnProfile = .observationGroupDefault,
        productKinds: [ObservationTAPProductKind] = []
    ) -> String {
        var predicates = [
            "CONTAINS(POINT('ICRS', o.s_ra, o.s_dec), CIRCLE('ICRS', \(ra), \(dec), \(radius))) = 1",
            "o.obs_collection IN (\(adqlQuotedList(collections)))",
            "o.datarights = 'PUBLIC'",
            "LOWER(a.productfilename) LIKE '%.fits'",
        ]

        if productKinds.contains(.scienceFITS) {
            predicates.append(
                """
                (
                    (o.obs_collection = 'JWST' AND LOWER(a.productfilename) LIKE '%_i2d.fits')
                    OR (o.obs_collection IN ('HST', 'HLA') AND (LOWER(a.productfilename) LIKE '%_drz.fits' OR LOWER(a.productfilename) LIKE '%_drc.fits'))
                    OR (o.obs_collection NOT IN ('JWST', 'HST', 'HLA'))
                )
                """
            )
        }

        let numericCalibLevels = calibLevels.compactMap { Int($0) }.map { String($0) }
        if !numericCalibLevels.isEmpty {
            predicates.append("o.calib_level IN (\(numericCalibLevels.joined(separator: ",")))")
        }

        let productTypes = dataProductTypes.map { $0.lowercased() }
        if !productTypes.isEmpty {
            predicates.append("LOWER(o.dataproduct_type) IN (\(adqlQuotedList(productTypes)))")
        }

        if let instruments, !instruments.isEmpty {
            predicates.append("o.instrument_name IN (\(adqlQuotedList(instruments)))")
        }

        if let filterBands, !filterBands.isEmpty {
            let filterPredicates = filterBands.map {
                "UPPER(o.filters) LIKE '%\(adqlEscaped($0.uppercased()))%'"
            }
            predicates.append("(\(filterPredicates.joined(separator: " OR ")))")
        }

        let selectColumns: String
        switch columnProfile {
        case .observationGroupDefault:
            selectColumns = """
                o.calib_level,
                o.datarights,
                COALESCE(a.datauri, o.dataurl),
                o.dataproduct_type,
                o.em_max,
                o.em_min,
                o.filters,
                o.instrument_name,
                o.intenttype,
                o.jpegurl,
                o.mtflag,
                o.objid,
                o.obs_collection,
                o.obs_id,
                o.obs_title,
                o.obsid,
                o.project,
                o.proposal_id,
                o.proposal_pi,
                o.proposal_type,
                o.provenance_name,
                o.s_dec,
                o.s_ra,
                o.s_region,
                o.sequence_number,
                o.srcden,
                o.t_exptime,
                o.t_max,
                o.t_min,
                o.t_obs_release,
                o.target_classification,
                o.target_name,
                o.wavelength_region,
                a.contentlength
            """
        case .targetCompositeSelection:
            selectColumns = """
                o.obsid,
                o.obs_id,
                o.obs_collection,
                o.instrument_name,
                o.target_name,
                o.filters,
                o.calib_level,
                o.dataproduct_type,
                o.intenttype,
                o.datarights,
                o.s_ra,
                o.s_dec,
                o.s_region,
                o.t_exptime,
                o.t_min,
                o.t_max,
                o.em_min,
                o.em_max,
                o.wavelength_region,
                o.proposal_id,
                o.project,
                o.provenance_name,
                p.posdimension1,
                p.posdimension2,
                p.possamplesize,
                COALESCE(a.datauri, o.dataurl),
                COALESCE(p.previewuri, o.jpegurl),
                a.productfilename,
                a.contenttype,
                a.contentlength
            """
        }

        return """
            SELECT TOP \(max(pageSize, 1))
                \(selectColumns)
            FROM dbo.obspointing AS o
            JOIN dbo.caomplane AS p ON p.planetid = o.objid
            JOIN dbo.caomartifact AS a ON a.planetid = p.planetid
            WHERE \(predicates.joined(separator: "\n                AND "))
            ORDER BY o.obs_collection, o.instrument_name, o.obs_id, o.filters, o.t_min
            """
    }

    private func coamResultsFromCAOMTapResponse(
        _ response: MASTTAPResponse,
        columnProfile: ObservationTAPColumnProfile
    ) -> [CoamResult] {
        response.data.q2dArray.compactMap {
            coamResultFromCAOMTapRow($0, columnProfile: columnProfile)
        }
    }

    private func coamResultFromCAOMTapRow(
        _ row: [QValue],
        columnProfile: ObservationTAPColumnProfile
    ) -> CoamResult? {
        if columnProfile == .targetCompositeSelection {
            return coamResultFromTargetCompositeTAPRow(row)
        }

        guard row.count >= 34 else { return nil }
        let contentLength = row[33].int64Value
        return CoamResult(
            calib_level: row[0].intValue ?? 0,
            dataRights: row[1].stringValue,
            dataURL: row[2].stringValue,
            dataproduct_type: row[3].stringValue.uppercased(),
            distance: 0,
            em_max: Int(row[4].floatValue ?? 0),
            em_min: Int(row[5].floatValue ?? 0),
            filters: row[6].stringValue,
            instrument_name: row[7].stringValue,
            intentType: row[8].stringValue,
            jpegURL: row[9].stringValue,
            mtFlag: row[10].boolValue ?? false,
            objID: row[11].intValue ?? 0,
            obs_collection: row[12].stringValue,
            obs_id: row[13].stringValue,
            obs_title: row[14].stringValue,
            obsid: row[15].intValue ?? 0,
            project: row[16].stringValue,
            proposal_id: row[17].stringValue,
            proposal_pi: row[18].stringValue,
            proposal_type: row[19].stringValue,
            provenance_name: row[20].stringValue,
            s_dec: row[21],
            s_ra: row[22],
            s_region: row[23].stringValue,
            sequence_number: row[24].intValue ?? 0,
            srcDen: row[25].intValue ?? Int(row[25].floatValue ?? 0),
            t_exptime: row[26].floatValue ?? 0,
            t_max: row[27].floatValue ?? 0,
            t_min: row[28].floatValue ?? 0,
            t_obs_release: row[29].floatValue ?? 0,
            target_classification: row[30].stringValue,
            target_name: row[31].stringValue,
            wavelength_region: row[32].stringValue,
            dataURLSizeBytes: contentLength,
            jpegURLSizeBytes: nil
        )
    }

    internal func coamResultFromTargetCompositeTAPRow(_ row: [QValue]) -> CoamResult? {
        guard row.count >= 30 else { return nil }
        return CoamResult(
            calib_level: row[6].intValue ?? 0,
            dataRights: row[9].stringValue,
            dataURL: row[25].stringValue,
            dataproduct_type: row[7].stringValue.uppercased(),
            distance: 0,
            em_max: Int(row[17].floatValue ?? 0),
            em_min: Int(row[16].floatValue ?? 0),
            filters: row[5].stringValue,
            instrument_name: row[3].stringValue,
            intentType: row[8].stringValue,
            jpegURL: row[26].stringValue,
            mtFlag: false,
            objID: 0,
            obs_collection: row[2].stringValue,
            obs_id: row[1].stringValue,
            obs_title: "",
            obsid: row[0].intValue ?? 0,
            project: row[20].stringValue,
            proposal_id: row[19].stringValue,
            proposal_pi: "",
            proposal_type: "",
            provenance_name: row[21].stringValue,
            s_dec: row[11],
            s_ra: row[10],
            s_region: row[12].stringValue,
            sequence_number: 0,
            srcDen: 0,
            t_exptime: row[13].floatValue ?? 0,
            t_max: row[15].floatValue ?? 0,
            t_min: row[14].floatValue ?? 0,
            t_obs_release: 0,
            target_classification: "",
            target_name: row[4].stringValue,
            wavelength_region: row[18].stringValue,
            dataURLSizeBytes: row[29].int64Value,
            jpegURLSizeBytes: nil,
            productFilename: row[27].stringValue,
            artifactContentType: row[28].stringValue,
            positionDimension1: row[22].intValue,
            positionDimension2: row[23].intValue,
            positionSampleSize: row[24].floatValue.map(Double.init)
        )
    }

    internal func productsForHeaderPolicy(
        _ products: [CoamResult],
        headerFetchPolicy: ObservationFITSHeaderFetchPolicy
    ) -> [CoamResult] {
        switch headerFetchPolicy {
        case .none:
            return []
        case .all:
            return products
        case .shortlistedOnly(let maxPerFilter):
            return limitTargetCompositeProductsPerFilter(
                products,
                maxProductsPerFilter: maxPerFilter
            )
        }
    }

    internal func limitTargetCompositeProductsPerFilter(
        _ products: [CoamResult],
        maxProductsPerFilter: Int?
    ) -> [CoamResult] {
        guard let maxProductsPerFilter else { return products }
        guard maxProductsPerFilter > 0 else { return [] }

        var counts = [String: Int]()
        var limited = [CoamResult]()
        for product in products.sorted(by: targetCompositeProductSort) {
            let key = product.filters.uppercased()
            let count = counts[key, default: 0]
            guard count < maxProductsPerFilter else { continue }
            counts[key] = count + 1
            limited.append(product)
        }
        return limited
    }

    private func targetCompositeProductSort(_ lhs: CoamResult, _ rhs: CoamResult) -> Bool {
        let leftSize = lhs.preferredDownloadSizeBytes ?? Int64.max
        let rightSize = rhs.preferredDownloadSizeBytes ?? Int64.max
        if leftSize != rightSize { return leftSize < rightSize }
        if lhs.t_exptime != rhs.t_exptime { return lhs.t_exptime > rhs.t_exptime }
        return lhs.obs_id < rhs.obs_id
    }

    private func mergeFITSHeaderMetadata(
        _ enrichedProducts: [CoamResult],
        into products: [CoamResult]
    ) -> [CoamResult] {
        let metadataByKey = Dictionary(
            uniqueKeysWithValues: enrichedProducts.compactMap { product in
                product.fitsImageHeaderMetadata.map {
                    (targetCompositeProductIdentity(product), $0)
                }
            }
        )
        return products.map { product in
            guard let metadata = metadataByKey[targetCompositeProductIdentity(product)] else {
                return product
            }
            return product.withFITSImageHeaderMetadata(metadata)
        }
    }

    private func targetCompositeProductIdentity(_ product: CoamResult) -> String {
        [
            product.obs_collection,
            product.obs_id,
            product.instrument_name,
            product.filters,
            product.dataURL,
        ].joined(separator: "\u{1f}")
    }

    private func adqlQuotedList(_ values: [String]) -> String {
        values.map { "'\(adqlEscaped($0))'" }.joined(separator: ",")
    }

    private func adqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
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
     * limit: Int? - maximum observation groups to return; also caps the MAST page size
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
        limit: Int? = nil,
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
            limit: limit,
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
     * limit: Int? - maximum observation groups to return; also caps the MAST page size
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
        limit: Int? = nil,
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
            limit: limit,
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
        // Mission and instrument are part of the identity so unrelated
        // collections cannot be merged when they happen to reuse an obs_id.
        var grouped = [GroupIdentity: [CoamResult]]()
        for coam in results {
            let identity = GroupIdentity(
                mission: coam.observationMission?.rawValue ?? coam.obs_collection.uppercased(),
                observationKey: observationGroupKey(coam),
                instrument: coam.instrument_name
            )
            grouped[identity, default: []].append(coam)
        }

        // Build sorted groups
        var groups = [ObservationGroup]()
        for (identity, products) in grouped {
            let sorted = products.sorted { compareObservationProducts($0, $1, by: sortOrder) }
            groups.append(
                ObservationGroup(
                    mission: identity.mission,
                    observationKey: identity.observationKey,
                    instrument: identity.instrument,
                    products: sorted
                ))
        }

        groups.sort {
            if $0.mission != $1.mission { return $0.mission < $1.mission }
            if $0.observationKey != $1.observationKey {
                return $0.observationKey < $1.observationKey
            }
            return $0.instrument < $1.instrument
        }
        return groups
    }

}

private extension QValue {
    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .float(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .float(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        case .bool:
            return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case .int(let value):
            return Int64(value)
        case .float(let value):
            return Int64(value)
        case .string(let value):
            return Int64(value)
        case .bool:
            return nil
        }
    }

    var floatValue: Float? {
        switch self {
        case .float(let value):
            return value
        case .int(let value):
            return Float(value)
        case .string(let value):
            return Float(value)
        case .bool:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return Bool(value)
        case .int(let value):
            return value != 0
        case .float(let value):
            return value != 0
        }
    }
}
