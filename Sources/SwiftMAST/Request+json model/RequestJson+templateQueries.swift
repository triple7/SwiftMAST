//
//  File.swift
//  
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation
import SwiftQValue


/** MAST request filter parameters
 These preconstructed filter parameters provide templates
 to use for the most useful investigations. These help cut down the number of returned entries, and package the essential data for each type of investigation.
 
 For example, the scienceImageFilters returns science images in calibrated mode for public data products in all filter categories. This is useful for astronomical imagery and presenting a full spectrum image of the chosen object.
 */
extension MASTJson {
    
    public func scienceImageFilters() -> [MASTJsonFilter] {
//        print("scienceImageFilters")
        return [
//            MASTJsonFilter(paramName: Coam.filters.id, values: QObject(values: [QValue(value: "NUV"), QValue(value: "FUV")] as Any), separator: ";"),
            MASTJsonFilter(paramName: Coam.calib_level.id, values: QObject(values: [QValue(value: "3"), QValue(value: "4")] as Any)),
            MASTJsonFilter(paramName: Coam.dataRights.id, values: QObject(values: [QValue(value: "PUBLIC")] as Any)),
            MASTJsonFilter(paramName: Coam.dataproduct_type.id, values: QObject(values: [QValue(value: "IMAGE")] as Any)),
            MASTJsonFilter(paramName: Coam.intentType.id, values: QObject(values: [QValue(value: "science")] as Any)),
//            MASTJsonFilter(paramName: Coam.obs_collection.id, values: QObject(values: [QValue(value: "SWIFT"), QValue(value: "HST"), QValue(value: "PS1"), QValue(value: "IUV"), QValue(value: "JWST"), QValue(value: "WIZE")] as Any), separator: ";"),
//            MASTJsonFilter(paramName: Coam.obs_collection.id, values: QObject(values: [QValue(value: "GALEX")] as Any), separator: ";"),
//            MASTJsonFilter(paramName: Coam.wavelength_region.id, values: QObject(values: [QValue(value: "OPTICAL"), QValue(value: "EUV"), QValue(value: "XRAY"), QValue(value: "INFRARED"), QValue(value: "IR")] as Any), separator: ";")
        ]
    }
    

    public func previewImage(waveBand: String = "OPTICAL") -> [MASTJsonFilter] {
        return [
            MASTJsonFilter(paramName: Coam.calib_level.id, values: QObject(values: [QValue(value: "3"), QValue(value: "4")] as Any)),
            MASTJsonFilter(paramName: Coam.dataRights.id, values: QObject(values: [QValue(value: "PUBLIC")] as Any)),
            MASTJsonFilter(paramName: Coam.dataproduct_type.id, values: QObject(values: [QValue(value: "IMAGE")] as Any)),
            MASTJsonFilter(paramName: Coam.intentType.id, values: QObject(values: [QValue(value: "science")] as Any)),
            MASTJsonFilter(paramName: Coam.wavelength_region.id, values: QObject(values: QValue(value: waveBand) as Any))
        ]
    }

}
