//
//  SwiftMAST+API.swift
//
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation
import QuartzCore

/** SwiftMAST common API calls
 These convenience functions allow quick access to some of the more interesting MAST API data requests.
 The MAST portal can be very complex to navigate, however most users would be looking to do the following investigations:
 * Download a preview of a given target object
 * download calibrated scientific images of a chosen object in full spectrum
 * Find TESS candidates within a given cone search and download time series for analysis
 * Download the spectra of a given object in one of the available missions
 * Download 3D star mappings from the SDSS (Sloan Digital Sky Survey) in CUBE format
 * Download GAIA point crossMatch parameters for conversion to 3D point cloud mapping
 * Download TESS crossMatch parameters for investigating light curves
 */
extension SwiftMAST {
    
    /** Lookup a target by its name
     Parameters:
     * name: String
     */
public func lookupTargetByName(targetName: String, result: @escaping ([NameLookupJson]) -> Void) {
        print("lookupTargetByName: \(targetName)")
        var output:[NameLookupJson] = []
        let service = Service.Mast_Name_Lookup
        var params = service.serviceRequest(requestType: .lookup)
        params.setParameter(param: .input, value: targetName)
    self.queryMast(service: service, params: params, returnType: .json, { success in
            for target in self.targets.keys {
                let table = self.targets[target]
                let resolved = table!.getNameLookupResults()
                output += resolved
            }
            result(output)
        })
    }
    
    /** Get the missions list
     */
    public func getMissionsList(result: @escaping ([String]) -> Void ) {
        print("getMissionsList")
        let service = Service.Mast_Missions_List
        let params = service.serviceRequest(requestType: .missionList)
        var output:[String] = []
        // Here target is not some object but jus a mission list
        self.setTargetId(targetId: "missions")
        self.queryMast(service: service, params: params, returnType: .json, { success in
            for target in self.targets.keys {
                let table = self.targets[target]
                let values = table!.getValues(for: "distinctValue")
                output.append(contentsOf: values.map {$0.value as! String})
            }
            result(output)
        })
    }

    /** Make a cone search for data products in the MAST archives
     
     */
    public func getConeSearch(targetId: String, ra: Float, dec: Float, radius: Float=0.2, preview: Bool=false, pageSize: Int = 0, result: @escaping ([CoamResult]) -> Void) {
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
        self.queryMast(service: service, params: params, returnType: .json, { success in
            let end = CACurrentMediaTime()
            print("getConeSearch: search completed in \(end - start)")
            let table = self.targets[targetId]!
            let results = table.getCoamResults()

            // Get dataUrls which are fits for the metadata
            var dataURLs = results.filter{!$0.dataURL.isEmpty}

            if preview {
                // Filter down to those which are not TESS
                dataURLs = dataURLs.filter{$0.obs_collection != "TESS"}
                print("getConeSearch: preview found \(dataURLs.count) dataURLs")

                result(dataURLs)
                return
            }
            // Normal collection of images
            let jpgUrls = results.filter{!$0.jpegURL.isEmpty}
            print("getConeSearch: found \(jpgUrls.count) jpegURLs and \(dataURLs.count) dataURLs")
            result(jpgUrls + dataURLs)
        })
    }

    
    /** Make a filtered cone search for data products in the MAST archives
     
     */
public func getFilteredConeSearch(ra: Float, dec: Float, radius: Float=0.2, filters:[ResultField] = [.filters, .wavelength_region, .instrument_name, .obs_collection, .dataURL], filterParams: [MASTJsonFilter]? = nil, result: @escaping ([ResultField: [String]]) -> Void) {
        print("getFilteredConeSearch: ra: \(ra) dec: \(dec)")
        
        var output = [ResultField: [String]]()
        let service = Service.Mast_Caom_Cone
        var params = service.serviceRequest(requestType: .coneSearch)
        params.setParameters(params: [MAP.ra: ra, MAP.dec: dec, MAP.radius: radius])
        self.queryMast(service: service, params: params, returnType: .json, { success in
            for target in self.targets.keys {
                let table = self.targets[target]
                let resolved = table!.getRows(filters: filters)
                for key in resolved.keys {
                    output[key] = resolved[key]!.map{$0.value as! String}
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
    public func getPS1ImageList(targetName: String, ra: Float, dec: Float, imageSize: Int = 8000, completion: @escaping (MASTTable?) -> Void) {
        print("getPS1ImageList: \(targetName) imagesize: \(imageSize)")

        let ps1Request = PS1Request(ra: ra, dec: dec, size: imageSize)
        queryPS1(ps1Request: ps1Request, { success in
           
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
    public func getMASTPreviewImage(targetName: String, ra: Float, dec: Float, radius: Float, pageSize: Int = 30, token: String?, result: @escaping (URL) -> Void) {
        print("getPreviewImage: \(targetName)")
        
        self.getConeSearch(targetId: targetName, ra: ra, dec: dec, radius: radius, preview: true, pageSize: pageSize, result: { coamResults in
            
            // Filter products which use MAST to download
            let directDownloadproducts = coamResults.filter{($0.jpegURL.isEmpty ? $0.dataURL : $0.jpegURL).contains("http")}
            let mastDownloadproducts = Array(Set(coamResults).subtracting(directDownloadproducts))
            
            // Prioritize mastDownload products
            print("getPreviewImage: mastDownloadproducts: \(mastDownloadproducts.count) directDownloads: \(directDownloadproducts.count)")
            if !mastDownloadproducts.isEmpty {
                let productType:ProductType = mastDownloadproducts.first!.jpegURL.isEmpty ? .Fits : .Jpeg
                
                let start = CACurrentMediaTime()
                    self.getDataproducts(targetName: targetName,service: .Download_file, products: [mastDownloadproducts.first!], productType: productType, token: token) { fitsResults in
                        let end = CACurrentMediaTime()
                        print("downloaded \(fitsResults.count) in \(end - start)")
                        result(fitsResults.first!.url)
                    }
            } else {
                // Direct download
                let productType:ProductType = directDownloadproducts.first!.jpegURL.isEmpty ? .Fits : .Jpeg
                self.getDirectDataproducts(targetName: targetName,service: .Download_file, products: [directDownloadproducts.first!], productType: productType, token: token) { (directUrls) in
                    
                    result(directUrls.first!)
                }
            }
    })
    }


    /** Make a Science image only cone search
     Parameters:
     * ra: Float
     * dec: Float
     * radius: Float
     * waveband: String (comma separated single string
     * returnFilters:[FilterResult]
     */
    public func getScienceImageProducts(targetName: String, ra: Float, dec: Float, radius: Float, productType: ProductType = .Fits, waveBand: String, token: String?, result: @escaping ([URL]) -> Void) {
        
    let service = Service.Mast_Caom_Filtered_Position
    var params = service.serviceRequest(requestType: .advancedSearch)
        
    params.setGeneralParameters(params: MAP.values.defaultGeneralParameters())
        params.setParameter(param: MAP.pagesize, value: 10)
    let filterParams = params.scienceImageFilters(waveBand: waveBand)
    params.setFilterParameters(params: filterParams)
        params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])

        let start = CACurrentMediaTime()
        self.queryMast(service: service, params: params, returnType: .json, { success in
            let end = CACurrentMediaTime()
            print("target products downloaded in \(end - start)")
            // we are looking for the targetId set previously
                let table = self.targets[targetName]!
                var coamResults = table.getCoamResults()
                coamResults.sort()
                //            let collections = table!.getUniqueString(for: Coam.obs_collection.id)
                //            print("Unique observation collections")
                //            for c in collections {
                //                print(c)
                //            }
                
                    let uniqueFilters = table.getUniqueString(for: Coam.filters.id)
                    print("getScienceImageProducts: \(uniqueFilters.count) unique filters")
                    
                    // dictionary of products by filter
                    var products = [String:[CoamResult]]()
                    for result in coamResults {
                        let filter = result.filters
                        if let filterList = products[filter] {
                            products[filter] = filterList + [result]
                        } else {
                            products[filter] = [result]
                        }
                    }
                    
                    // Append the first image of each filter
                    var allFilterProducts = [CoamResult]()
                    for filter in uniqueFilters {
                        let coamResult = products[filter]!
                        if coamResult.count > 0 {
                            allFilterProducts.append(coamResult.first!)
                        }
                    }
                    
                    // Some products are meant to be ddirect downloads
                    let directDownloadproducts = allFilterProducts.filter{(productType == .Fits ? $0.dataURL : $0.jpegURL).contains("http")}
                    
                    let mastDownloadProducts = allFilterProducts.filter{!(productType == .Fits ? $0.dataURL : $0.jpegURL).contains("http")}
                    
                    // Get the MAST query url downloads and return the URLs
                    self.getDataproducts(targetName: targetName,service: .Download_file, products: mastDownloadProducts, productType: productType, token: token) { allFitsDataResults in
                        
                        let secondaryUrls = allFitsDataResults.map{$0.url}
                        
                        // Secondary non MAST direct downloads
                        self.getDirectDataproducts(targetName: targetName,service: .Download_file, products: directDownloadproducts, productType: productType, token: token) { directUrls in
                            
                            result(secondaryUrls + directUrls)
                        }
                    }
    })
    }

    /** Get GAIA crossmatch
     parameters:
     * ra: Float
     dec: Float
     radius: Float
     */
public func getGaiaCrossmatch(ra: Float, dec: Float, radius: Float, result: @escaping ([[Float]]) -> Void) {
        print("getGaiaCrossmatch:  at radius \(radius)")
        
        let service = Service.Mast_GaiaDR3_Crossmatch
        var params = service.serviceRequest(requestType: .crossMatch)
        params.setCrossmatchinput(coordinates: [["ra": ra, "dec": dec, "radius": radius]])
        params.setParameters(params: [MAP.raColumn: "ra", MAP.decColumn: "dec", MAP.radius: radius, MAP.columns: "MatchRA,MatchDEC"])
        var output = [[Float]]()
        self.queryMast(service: service, params: params, returnType: .json, { success in
            for target in self.targets.keys {
                let table = self.targets[target]
                let RA = table!.getValues(for: "ra").map{$0.value as! Float}
                let DEC = table!.getValues(for: "dec").map{$0.value as! Float}
                let PARALLAX = table!.getValues(for: "parallax").map{$0.value as! Float}
                let MAG = table!.getValues(for: "mag").map{$0.value as! Float}
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
func getTicCrossmatch(ra: Float, dec: Float, radius: Float, result: @escaping ([[Float]]) -> Void) {
        print("getTicCrossmatch:  at radius \(radius)")
        
        let service = Service.Mast_Tic_Crossmatch
        var params = service.serviceRequest(requestType: .crossMatch)
        params.setCrossmatchinput(coordinates: [["ra": ra, "dec": dec, "radius": radius]])
        params.setParameters(params: [MAP.raColumn: "ra", MAP.decColumn: "dec", MAP.radius: radius, MAP.columns: "MatchRA,MatchDEC"])
        var output = [[Float]]()
        self.queryMast(service: service, params: params, returnType: .json, { success in
            for target in self.targets.keys {
                let table = self.targets[target]
                let RA = table!.getValues(for: "ra").map{$0.value as! Float}
                let DEC = table!.getValues(for: "dec").map{$0.value as! Float}
                let PLX = table!.getValues(for: "plx").map{$0.value as! Float}
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
    public func downloadPreview(targetName: String, pageSize: Int = 30, token: String? = nil, completion: @escaping (URL?) -> Void ) {
        print("downloadpreview: \(targetName)")
        self.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(targetName: targetName, result: { targetLookup in
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
            self.getMASTPreviewImage(targetName: targetName, ra: resolved.ra, dec: resolved.dec, radius: resolved.radius, pageSize: pageSize, token: token) { urls in
                completion(urls)
            }
            
    })
                       }
    

    /** Get a PS1 multi filter stacked fits cutout
         Parameters:
         * target: string
         * size: squared image pixel size (0.25 arsec/pixel)
         */
    public func getPS1ImagePreview(targetName: String, imageSize: Int = 8000, downloadUrl: @escaping ([URL]) -> Void) {
        print("getPS1ImagePreview: \(targetName)")

        self.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(targetName: targetName, result: { targetLookup in
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
            let pixelSize = Int(radius/0.25)
            print("\(targetName) radius \(radius) pixels \(pixelSize)")
            self.getPS1ImageList(targetName: targetName, ra: ra, dec: dec, imageSize: imageSize, completion: { filesTable in
                
                guard let filesTable = filesTable else {
                    downloadUrl([])
                    return
                }
                // Get the r g and b filters
                            // https://ps1images.stsci.edu/ps1image.html
                var fileNames = filesTable.getStringValues(for: "filename")
                            let filters = filesTable.getStringValues(for: "filter")

                
                            let yzirg = "yzirg"
                            var filterList = filters.map{yzirg.range(of: $0)!.lowerBound.utf16Offset(in: yzirg)}
                            filterList = filterList.enumerated().sorted{$0.element < $1.element}.map{$0.offset}
                filterList = Array(filterList[0..<3])
                            fileNames = filterList.map{fileNames[$0]}
                
                // Form a request URL
                let ps1Request = PS1Request(ra: ra, dec: dec, size: imageSize)
                            let url = ps1Request.getFitsColorImageUrl(fileNames: fileNames)
                            
                self.downloadPS1Cutouts( targetName: targetName, urls: [url], completion: { jpgUrls in
                    print("Download complete: adding files to documents folder")
                    downloadUrl(jpgUrls)
                    
                })
            })
            
        })
        
    }
    
    /** Select a target by name and download all selectively filtered images
     to the documents folder under MAST/target_name/instrument_name/
     */
    public func downloadImagery(targetName: String, waveBand: String = "optical", token: String? = nil, completion: @escaping ([URL]) -> Void ) {
        print("downloadImagery: \(targetName)")
        let targetStart = CACurrentMediaTime()
        self.lookupTargetByName(targetName: targetName, result: { targetLookup in
            guard !targetLookup.isEmpty, let table = self.targets[targetName] else {
                print("Could not resolve \(targetName)")
                return
            }
                                let targetEnd = CACurrentMediaTime()
            print("target found in \(targetEnd - targetStart)")
            let resolved = table.getNameLookupResults().first!
            // Save the initial target info
            self.setTargetAssets(target: targetName, targetInfo: resolved)

            // Get the images
            // And save them in the targets dictionary for future downloads if required
            self.getScienceImageProducts(targetName: targetName, ra: resolved.ra, dec: resolved.dec, radius: resolved.radius, productType: .Jpeg, waveBand: waveBand, token: token) { urls in
                completion(urls)
            }
            
    })
                       }

    
    /** Make a MAST TAP request to get the current TESS Input Catalog entries
     */
    public func getTIC( completion: @escaping (MASTTAPResponse)-> Void) {
        let selectQuery = "SELECT id, hip FROM dbo.catalogrecord WHERE hip IS NOT NULL"
        queryMASTTap(selectQuery: selectQuery, table: .dbo_catalog_record, fields: [], parameters: [], format: .json, closure: { response in
            completion(response)
        })
        
    }

    
    /** Make a MAST TAP request to ge get tic and hip values given a position and radius
     */
    public func getTICByPos(ra: Double, dec: Double, radius: Double, completion: @escaping (MASTTAPResponse)-> Void) {
        let selectQuery = "SELECT TOP 50000 id, hip FROM dbo.catalogrecord WHERE 1 = CONTAINS(POINT('ICRS', ra, dec),CIRCLE('ICRS', \(ra),\(dec),\(radius))"
        
        queryMASTTap(selectQuery: selectQuery, table: .dbo_catalog_record, fields: [], parameters: [], format: .json, closure: { response in
            completion(response)
        })
        
    }

}
