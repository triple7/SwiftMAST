# SwiftMAST

Swift wrapper for the [MAST](https://archive.stsci.edu/vo/mast_services.html#GET) archive of astronomical data 

This package is used for the [AstreOS](https://astreos.space) platform developed by Yuma Antoine Decaux.

## Introduction

The Mikulski Archive for Space Telescopes is an astronomical data archive focused on the optical, ultraviolet, and near-infrared. MAST hosts data from over a dozen missions like Webb, Hubble, TESS, Kepler, and in the future Roman.

The MAST archive allows searching for data in csv table and FITS file formats of:
. Missions
. High Level Science Products
. Simple image formats
. simple spectral data

The main format being used is the [FITS](https://www.loc.gov/preservation/digital/formats/fdd/fdd000317.shtml) file which is a souped up image format which is used from [NASA](https://www.nasa.gov) through to the Vatican for archiving annotated data.

This package depends on [FITSCore](https://github.com/brampf/fitscore) for opening/processing/saving data to and from FITS and other image formats.


