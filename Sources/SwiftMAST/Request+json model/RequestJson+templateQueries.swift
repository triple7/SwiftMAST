//
//  File.swift
//  
//
//  Created by Yuma decaux on 13/1/2024.
//

import Foundation

/** MAST request filter parameters
 These preconstructed filter parameters provide templates
 to use for the most useful investigations. These help cut down the number of returned entries, and package the essential data for each type of investigation.
 
 For example, the scienceImageFilters returns science images in calibrated mode for public data products in all filter categories. This is useful for astronomical imagery and presenting a full spectrum image of the chosen object.
 */
extension MASTJson {
    
    public func scienceImageFilters(waveBand: String = "OPTICAL") -> [MASTJsonFilter] {
        print("scienceImageFilters")
        return [
//            MASTJsonFilter(paramName: Coam.filters.id, values: FilterValues(values: [QValue(value: "NUV"), QValue(value: "FUV")] as Any), separator: ";"),
            MASTJsonFilter(paramName: Coam.calib_level.id, values: FilterValues(values: [QValue(value: "3"), QValue(value: "4")] as Any)),
            MASTJsonFilter(paramName: Coam.dataRights.id, values: FilterValues(values: [QValue(value: "PUBLIC")] as Any)),
            MASTJsonFilter(paramName: Coam.dataproduct_type.id, values: FilterValues(values: [QValue(value: "IMAGE")] as Any)),
            MASTJsonFilter(paramName: Coam.intentType.id, values: FilterValues(values: [QValue(value: "science")] as Any)),
            MASTJsonFilter(paramName: Coam.obs_collection.id, values: FilterValues(values: [QValue(value: "HST"), QValue(value: "GALEX")] as Any), separator: ";")
        ]
    }
    

    public func previewImage(waveBand: String = "OPTICAL") -> [MASTJsonFilter] {
        return [
            MASTJsonFilter(paramName: Coam.calib_level.id, values: FilterValues(values: [QValue(value: "3"), QValue(value: "4")] as Any)),
            MASTJsonFilter(paramName: Coam.dataRights.id, values: FilterValues(values: [QValue(value: "PUBLIC")] as Any)),
            MASTJsonFilter(paramName: Coam.dataproduct_type.id, values: FilterValues(values: [QValue(value: "IMAGE")] as Any)),
            MASTJsonFilter(paramName: Coam.intentType.id, values: FilterValues(values: [QValue(value: "science")] as Any)),
            MASTJsonFilter(paramName: Coam.wavelength_region.id, values: FilterValues(values: QValue(value: waveBand) as Any))
        ]
    }

}
