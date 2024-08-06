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
 * download calibrated scientific images of a chosen object in full spectrum
 * Find TESS candidates within a given cone search and download time series for analysis
 * Download the spectra of a given object in one of the available missions
 * Download 3D star mappings from the SDSS (Sloan Digital Sky Survey) in CUBE format
 * Download GAIA point crossMatch parameters for conversion to 3D point cloud mapping
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
        self.queryMast(service: service, params: params, returnType: .xml, { success in
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
public func getConeSearch(ra: Float, dec: Float, radius: Float=0.2, filters:[ResultField] = [.filters, .wavelength_region, .instrument_name, .obs_collection, .dataURL], filterParams: [MASTJsonFilter]? = nil, result: @escaping ([ResultField: [String]]) -> Void) {
        print("getConeSearch: ra: \(ra) dec: \(dec)")
        
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

    /** Make a Science image only cone search
     Parameters:
     * ra: Float
     * dec: Float
     * radius: Float
     * returnFilters:[FilterResult]
     */
    public func getScienceImageProducts(targetName: String, ra: Float, dec: Float, radius: Float, productType: ProductType = .Fits, waveLengths: [String], preview: Bool = true, token: String?, result: @escaping ([URL]) -> Void) {
        
    let service = Service.Mast_Caom_Filtered_Position
    var params = service.serviceRequest(requestType: .advancedSearch)
    params.setGeneralParameter(params: MAP.values.defaultGeneralParameters())
        print(params)
    let filterParams = params.scienceImageFilters(wavelengthRegions: waveLengths)
    params.setFilterParameters(params: filterParams)
    params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])
        params.setTargetId(targetId: targetName)

        let start = CACurrentMediaTime()
        self.queryMast(service: service, params: params, returnType: .json, { success in

            let end = CACurrentMediaTime()
            print("target products downloaded in \(end - start)")
            // we are looking for one key
            
            if let target = self.targets.keys.first {
                let table = self.targets[target]!
                var coamResults = table.getCoamResults()
                coamResults.sort()
                //            let collections = table!.getUniqueString(for: Coam.obs_collection.id)
                //            print("Unique observation collections")
                //            for c in collections {
                //                print(c)
                //            }
                
                if preview {
                    print("Getting first image for preview")
                    // Just save the first image
                    
                    let mastDownloadProducts = coamResults.filter{!(productType == .Fits ? $0.dataURL : $0.jpegURL).contains("http")}
                    
                    print("coam Result count: \(mastDownloadProducts.first!)")
                    self.getDataproducts(targetName: targetName,service: .Download_file, products: [mastDownloadProducts.first!], productType: productType, token: token) { (success, urls) in
                        
                        print("Downloaded URLs")
                        result(urls)
                    }
                    
                } else {
                    
                    // non preview, get everything
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
                    self.getDataproducts(targetName: targetName,service: .Download_file, products: mastDownloadProducts, productType: productType, token: token) { (success, urls) in
                        
                        // Secondary non MAST direct downloads
                        self.getDirectDataproducts(targetName: targetName,service: .Download_file, products: directDownloadproducts, productType: productType, token: token) { (success, directUrls) in
                            
                            result(urls + directUrls)
                        }
                    }
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

    /** Select a target by name and download all selectively filtered images
     to the documents folder under MAST/target_name/instrument_name/
     */
    public func downloadImagery(targetName: String, waveLengths: [String] = ["optical"], token: String? = nil, completion: @escaping ([URL]) -> Void ) {
        print("downloadImagery: \(targetName)")
        let service = Service.Mast_Name_Lookup
        var params = service.serviceRequest(requestType: .lookup)
        params.setParameter(param: .input, value: targetName)
        params.setTargetId(targetId: targetName)
        let targetStart = CACurrentMediaTime()
        self.queryMast(service: service, params: params, returnType: .xml, { success in
            guard let target = self.targets.keys.first, let table = self.targets[target] else {
                print("Unable to find target")
                completion([])
                return
            }
      let targetEnd = CACurrentMediaTime()
            print("target found in \(targetEnd - targetStart)")
            let resolved = table.getNameLookupResults().first!
            // stash the MAST lookup dictionary as record
            self.moveTargetToLookupHistory(target: target)
            
            // Get the images
            // And save them in the targets dictionary for future downloads if required
            self.getScienceImageProducts(targetName: targetName, ra: resolved.ra, dec: resolved.dec, radius: resolved.radius, productType: .Jpeg, waveLengths: waveLengths, token: token) { urls in
                completion(urls)
            }
            
    })
                       }
    
}
