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
    
    public func scienceImageFilters() -> [MASTJsonFilter] {
        return [
            MASTJsonFilter(paramName: Coam.filters.id, values: ["NUV" , "FUV"]),
            MASTJsonFilter(paramName: Coam.calib_level.id, values: ["3", "4"]),
            MASTJsonFilter(paramName: Coam.dataRights.id, values: ["public"]),
            MASTJsonFilter(paramName: Coam.dataproduct_type.id, values: ["IMAGE"]),
            MASTJsonFilter(paramName: Coam.intentType.id, values: ["science"])
        ]
    }
    

}
