//
//  HLAParams.swift
//  SwiftMAST
//
//  Created by Yuma decaux on 6/10/2024.
//


public enum HLAParams: String, Codable, Identifiable {
    case red
    case green
    case blue
    case caseless
    case align
    case qext
    case badpix
    case badvalue
    case size
    case ra
    case dec
    case x
    case y
    case wcs
    case corner
    case zoom
    case outputSize
    case applyOmega
    case autoscale
    case asinh
    case invert
    case autoscaleMax
    case autoscaleMin
    case userMax
    case userMin
    case format
    case callback
    case compass
    case palette
    case getWCS
    case download
    case tile
    case maxZoom
    case textErrors
    
    public var id:String {
        return self.rawValue
    }

    var description: String {
        switch self {
        case .red:
            return "Name of the image for the red band"
        case .green:
            return "Name of the image for the green band"
        case .blue:
            return """
            Name of the image for the blue band.
            At least one image must be specified (in which case a monochrome image is produced.)
            If more than one is given then a color image is generated. The image names may be
            MAST datasets (which are located using rules based on the name), paths in the web
            server space (so /file.fits would be a file in the web server's home directory) or
            an absolute path name on the server. Filenames must be resolvable to FITS files
            (though .fits and some other extensions may be omitted). Filenames can include a
            FITS extension identifier in brackets (e.g., [1] or [SCI]); the default is to use the
            primary data or the first image extension if the primary is null. Note that fitscut
            does support compressed FITS images and transparently uncompresses them if required
            (though that may be slow for some compression algorithms.)
            """
        case .caseless:
            return """
            If set to a true Boolean value, the image names are
            matched ignoring the case of characters. The default is to require the case of the
            name to match exactly (so "HST_10188_10_ACS_WFC_F814W" is not the same as
            "hst_10188_10_acs_wfc_f814w").
            """
        case .align:
            return """
            If set to a true Boolean value, the green and blue images
            are resampled using the FITS header world coordinates to match the red image pixels.
            By default the red/green/blue images are assumed to have matched coordinates so that
            the color images can be created pixel-by-pixel without any resampling. The only
            exceptions (at the moment) are the PHAT HLSP images, where Align is
            True by default because those images are known to be misaligned. The
            Align parameter can be used to generate color images when the
            red/green/blue images are not on the same coordinate grid. Note however that (1)
            this can be somewhat time-consuming compared with the usual fitscut color images,
            and (2) the HLA coordinates for images are not necessarily well-aligned for
            independent visits, so the color images may still not be well aligned after
            resampling. This parameter works with the Tile parameter, which is used by
            the interactive display.
            """
        case .qext:
            return """
            Number of extension with data quality/weight information. This is an optional
            parameter that is needed only for images where bad pixels have non-zero values
            (e.g., the current version of the WFPC2 combined images). The program assumes that
            the specified FITS extension is an image of the same size as the primary data array
            with zeros indicating bad pixels. For the usual drizzled WFPC2 images,
            Qext=4 is a good value. FITS extension numbers start at 0 for the primary
            header-data unit, 1 for the first extension, etc. For color images this can
            also be a comma-separated list of integers (Qext=4,3,2), although that is
            probably rarely needed.
            """
        case .badpix:
            return """
            Boolean parameter indicating whether the BADPIX
            FITS header keyword is used to identify bad pixels in the image. The default is
            Badpix = True for most HLSP images and False for other
            images.
            """
        case .badvalue:
            return """
            Floating point value for pixels that should be treated as missing values in the
            image. Default is Badvalue=0; if the image has real data values that are
            exactly zero, Badvalue should be set to some other value.
            """
        case .size:
            return """
            Size in pixels for cutout (default 512). May either be a single integer for
            square cutouts or ncolumns,nrows for a rectangular cutout. May also be the
            special value ALL, in which case the entire image is extracted
            rather than a subset.
            """
        case .ra:
            return """
            Central position in degrees for the cutout. These are ignored
            if Size=ALL is specified.
            """
        case .dec:
            return """
            Central position in degrees for the cutout. These are ignored
            if Size=ALL is specified.
            """
        case .x:
            return """
            Central position in pixels for the cutout (both default to 500). These are ignored
            if Size=ALL or RA, Dec are specified.
            """
        case .y:
            return """
            Central position in pixels for the cutout (both default to 500). These are ignored
            if Size=ALL or RA, Dec are specified.
            """
        case .wcs:
            return """
            If set to a true Boolean value, then the X,Y
            values are interpreted as RA and Dec in degrees. Default is X,Y in pixels. If set,
            X,Y are converted from degrees to pixels using WCS information in the FITS
            header. Note that it is better to use the RA,Dec parameters
            to specify positions in degrees. This parameter is retained for backward-compatibility.
            """
        case .corner:
            return """
            If set to a true Boolean value, then the X,Y
            or RA,Dec
            positions specify the lower left corner of the cutout section rather than the center
            position.
            """
        case .zoom:
            return """
            Zoom factor for image (default 1). Values smaller than unity shrink the image
            (useful for large cutouts), and values larger than unity expand the image (possibly
            useful for very small cutouts). This is rounded to the nearest integral factor, so
            useful values are 1, 0.5, 0.33, 0.25, etc.
            """
        case .outputSize:
            return """
            Exact output size for image in pixels. If specified this overrides the
            Zoom factor in determining the image size. Default is to use the zoom
            factor and the Size to produce an output image of Size x
            Zoom pixels. If the cutout image is rectangular, the longest dimension
            (width or height) will be Output_Size pixels.
            """
        case .applyOmega:
            return """
            (Relevant only for HLA images.) If set to a true Boolean value, the image rotation and
            shift determined in the construction of the Hubble Source Catalog are applied to the
            HLA image to determine a more accurate position for the cutout extraction. This
            should be used when extracting cutouts based on HSC source positions. If set to a false
            Boolean value, the original (uncorrected) HLA image coordinates
            are used. The default is
            true, so that the coordinates used have the HSC corrections applied.
            """
        case .autoscale:
            return """
            Contrast adjustment: Percentage of image histogram to retain (default 99.5).
            Smaller values turn up the contrast. For Autoscale=99.5, the image is
            scaled from the 99.5 percentile (bright) to the 0.5 (= 100-99.5) percentile
            (dark).
            """
        case .asinh:
            return """
            If set to a true Boolean value, use the
            Lupton
            asinh contrast algorithm. This is similar to a logarithmic scale but is usable
            for both positive and negative pixels. Default is on.
            """
        case .invert:
            return """
            If set to a true Boolean value, invert the display scale
            so that the brightest pixels are black and the faintest pixels are white. Default is
            False.
            """
        case .autoscaleMax:
            return """
            Alternative contrast adjustment. These can set the lower and upper percentiles
            separately (e.g., 99.5 at the top and 1.5 at the bottom instead of the default
            99.5,0.5). These can also be comma-separated triples to set different autoscale
            values for the red,green,blue band images. These parameters allow more flexibility in
            the contrast and color balance.
            """
        case .autoscaleMin:
            return """
            Alternative contrast adjustment. These can set the lower and upper percentiles
            separately (e.g., 99.5 at the top and 1.5 at the bottom instead of the default
            99.5,0.5). These can also be comma-separated triples to set different autoscale
            values for the red,green,blue band images. These parameters allow more flexibility in
            the contrast and color balance.
            """
        case .userMax:
            return """
            If given, use these value as the maximum for mapping the pixel values to
            grayscales. Default is to use the autoscale values. These may be single values or
            three comma-separated values to specify independent values for the red,green,blue
            bands. These parameters provide maximum control over the contrast but also require
            knowing the dynamic range of the image pixel values. Note that the Range
            parameter (described below) can be used to query the image to determine good values
            for the UserMax and UserMin parameters.
            """
        case .userMin:
            return """
            If given, use these value as the minimum for mapping the pixel values to
            grayscales. Default is to use the autoscale values. These may be single values or
            three comma-separated values to specify independent values for the red,green,blue
            bands. These parameters provide maximum control over the contrast but also require
            knowing the dynamic range of the image pixel values. Note that the Range
            parameter (described below) can be used to query the image to determine good values
            for the UserMax and UserMin parameters.
            """
        case .format:
            return """
            Specify the image format. Options are jpg (the default), png,
            fits, json, or range. FITS images have a copy of the
            header from the original FITS file with the WCS keywords modified to describe the
            cutout regions. JSON format is used to get the pixel values for a small
            region of the image (e.g., for the pixel value readout in the HLA interactive
            display). The RANGE format uses the specified contrast parameters
            (autoscale, etc.) to compute the min/max values for the image, which are
            returned in a JSON value. Note that the RANGE return values can be used in
            a later fitscut call as UserMax, UserMin parameters to set the
            contrast.
            """
        case .callback:
            return """
            If specified, wrap the JSON return result in a callback to the named
            JavaScript function. This applies only to JSON format returns.
            """
        case .compass:
            return """
            If set to a true Boolean value, draws compass arrows
            showing north and east.
            """
        case .palette:
            return """
            Specify color palette used for single-filter (non-color) images. Options are
            gray (default), heat, cool, rainbow,
            red, green, or blue. * (png format only) *
            """
        case .getWCS:
            return """
            If set to a true Boolean value, returns a JSON format
            dictionary containing the FITS world-coordinate system rather than an image. This
            is a utility function useful for the interactive display. Here is a sample URL that
            shows the return format:
            https://hla.stsci.edu/cgi-bin/fitscut.cgi?red=hst_10188_10_acs_wfc_f814w&getWCS=yes
            """
        case .download:
            return """
            If set to a true Boolean value, the HTTP header is set to force the output
            JPEG/PNG image to be downloaded rather than displayed in the browser. By default FITS
            format images are downloaded and other formats are handled by the browser. This
            parameter is relevant only if the image URL is embedded within a web page.
            """
        case .tile:
            return """
            If given, the image is being accessed in "tile" mode. This is used
            for the interactive display (and is unlikely to be useful in other contexts). The
            parameter is of the form "tile-zoom-x-y" where the zoom, x, y parameters
            are indices into the tiled image. See Rick White if you need the details. The same
            contrast is used for all tiles. The returned tile size is 256×256 pixels. A
            special HTTP redirect to a blank image is returned if the requested tile is off the
            edge of the image or if the parameter is "tile-none".
            """
        case .maxZoom:
            return """
            In Tile mode, sets the highest zoom-out level (compared to the default
            1:1 scale.) See Rick White if you need the details.
            """
        case .textErrors:
            return """
            If set to a true Boolean value, on failure produces a
            simple text error message. The default is to produce an HTML error message.
            """
        }
    }

    
}
