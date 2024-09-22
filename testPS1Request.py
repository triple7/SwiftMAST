import numpy as np
from io import StringIO
import requests


ps1filename = " https://ps1images.stsci.edu/cgi-bin/ps1filenames.py"

def getimages(tra, tdec, size=240, filters="grizy", format="fits", imagetypes="stack"):
     
    """Query ps1filenames.py service for multiple positions to get a list of images
    This adds a url column to the table to retrieve the cutout.
     
    tra, tdec = list of positions in degrees
    size = image size in pixels (0.25 arcsec/pixel)
    filters = string with filters to include
    format = data format (options are "fits", "jpg", or "png")
    imagetypes = list of any of the acceptable image types.  Default is stack;
        other common choices include warp (single-epoch images), stack.wt (weight image),
        stack.mask, stack.exp (exposure time), stack.num (number of exposures),
        warp.wt, and warp.mask.  This parameter can be a list of strings or a
        comma-separated string.
 
    Returns an astropy table with the results
    """
     
    if format not in ("jpg","png","fits"):
        raise ValueError("format must be one of jpg, png, fits")
    # if imagetypes is a list, convert to a comma-separated string
    if not isinstance(imagetypes,str):
        imagetypes = ",".join(imagetypes)
    # put the positions in an in-memory file object
    cbuf = StringIO()
    cbuf.write('\n'.join(["{} {}".format(ra, dec) for (ra, dec) in zip(tra,tdec)]))
    cbuf.seek(0)
    print(f"cbuff {cbuf}")
    # use requests.post to pass in positions as a file
    r = requests.post(ps1filename, data=dict(filters=filters, type=imagetypes),
        files=dict(file=cbuf))
    r.raise_for_status()
    breakpoint()
    print(f"response {r.text}")


# create a test set of image positions
tdec = np.append(np.arange(31)*3.95 - 29.1, 88.0)
tra = np.append(np.arange(31)*12., 0.0)

# get the PS1 info for those positions
getimages(tra,tdec,filters="ri")
