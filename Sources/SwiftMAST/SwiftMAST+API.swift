//
//  SwiftMAST+API.swift
//
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation

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
func lookupTargetByName(targetName: String, result: @escaping ([NameLookupJson]) -> Void) {
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
    public func getScienceImageProducts(ra: Float, dec: Float, radius: Float, result: @escaping ([URL]) -> Void) {
        print("getScienceImageProducts ra \(ra) dec \(dec) radius \(radius)")
        
    let service = Service.Mast_Caom_Filtered_Position
    var params = service.serviceRequest(requestType: .advancedSearch)
    params.setGeneralParameter(params: MAP.values.defaultGeneralParameters())
    let filterParams = params.scienceImageFilters()
    params.setFilterParameters(params: filterParams)
    params.setParameters(params: [MAP.columns: "*", MAP.position: "\(ra), \(dec), \(radius)"])
    self.queryMast(service: service, params: params, returnType: .json, { success in
        // we are looping through 1 key
        for target in self.targets.keys {
            let table = self.targets[target]
            var coamResults = table!.getCoamResults()
            coamResults.sort()
            let uniqueFilters = table!.getUniqueString(for: Coam.filters.id)
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
            // Download the first image of each filter
            var allFilterProducts = [CoamResult]()
            for filter in uniqueFilters {
                let coamResult = products[filter]!
                if coamResult.count > 0 {
                    allFilterProducts.append(coamResult.first!)
                }
            }
                                     
                                     // Finally get the URLS to the files and return them
            self.requestProductBundle(service: .Download_bundle, coamResults: allFilterProducts) { (success, urls) in
                result(urls)
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

}
