# MAST API Enum Source Documentation

The enums in this directory are derived from the official MAST (Mikulski Archive for Space Telescopes) API documentation.
Visit the URLs below to get the latest field definitions and update the corresponding Swift enum files.

## API Documentation URLs

| Swift File | Enum | Documentation URL |
|---|---|---|
| `Service.swift` | `MASTService` | https://mast.stsci.edu/api/v0/_services.html |
| `Coam.swift` | `MASTCoamField` | https://mast.stsci.edu/api/v0/_c_a_o_mfields.html |
| `ResultField.swift` | `ResultField` | https://mast.stsci.edu/api/v0/_c_a_o_mfields.html |
| `Tic.swift` | `MASTTicField` | https://mast.stsci.edu/api/v0/_t_i_cfields.html |
| `JwsInstrument.swift` | `MASTJwstInstrumentField` | https://mast.stsci.edu/api/v0/_jwst_inst_keywd.html |
| `Gaia.swift` | `MASTGaiaField` | https://mast.stsci.edu/api/v0/_gaiafields.html |
| `DiskDetected.swift` | `MASTDiskdetectedField` | https://mast.stsci.edu/api/v0/_disk__detectivefields.html |
| `Hsc.swift` | `MASTHscField` | https://mast.stsci.edu/api/v0/_h_s_cfields.html |
| `HscMatches.swift` | `MASTHscmatchesField` | https://mast.stsci.edu/api/v0/_h_s_c__matchesfields.html |
| `HscSpectra.swift` | `MASTHscspectraField` | https://mast.stsci.edu/api/v0/_h_s_c__spectrafields.html |
| `Galex.swift` | `MASTGalexField` | https://mast.stsci.edu/api/v0/_g_a_l_e_xfields.html |
| `Products.swift` | `MASTProductsField` | https://mast.stsci.edu/api/v0/_productsfields.html |

## Additional Resources

| Resource | URL |
|---|---|
| MAST API Home | https://mast.stsci.edu/api/v0/ |
| JWST Keyword Dictionary | https://mast.stsci.edu/portal/Mashup/Clients/jwkeywords/index.html |
| JWST Schematic Headers | https://archive.stsci.edu/jwst/keyword/latest/ |
| General VO Search Help | https://archive.stsci.edu/vo/help/search_help.html |
| Python Examples | https://mast.stsci.edu/api/v0/pyex.html |
| MAST Portal | https://mast.stsci.edu/portal/Mashup/Clients/Mast/Portal.html |

## Notes

- Column Names in the documentation tables correspond directly to the Swift enum `rawValue` strings.
- The `id` property on each enum returns the raw value used in API requests.
- The `description` property provides a human-readable label for each field.
- Last updated from documentation: 2025
