# MAST TAP columns for science-product selection

## Recommendation

Use the `targetCompositeSelection` projection for the metadata-only discovery
step. It contains the fields needed to identify, group, filter, rank, and fetch
science image products without downloading the FITS file. Optional fields may
improve ranking or preview planning, but a missing optional value must not
reject an otherwise valid product.

The projection is kept in two places:

- Swift: `caomObservationGroupsTAPQuery(..., columnProfile: .targetCompositeSelection)`
- Python: `APPLICATION_COLUMNS` in `Sources/scripts/query_mast_tap.py`

### Selected columns

| Purpose | Columns | Requirement | Use |
|---|---|---|---|
| Product identity and grouping | `obsid`, `obs_id`, `obs_collection`, `instrument_name`, `target_name`, `filters` | Required | Create observation groups and distinguish the products and filter channels. |
| Eligibility | `calib_level`, `dataproduct_type`, `intenttype`, `datarights` | Required | Keep public, science-ready image/cube products. The query also filters mission-specific science FITS suffixes. |
| Sky coverage | `s_ra`, `s_dec`, `s_region` | Required | Locate the observation and compute footprint coverage/overlap. `s_region_area` is computed locally from `s_region`; it is not selected from TAP. |
| Observation timing | `t_exptime`, `t_min`, `t_max` | Required | `t_exptime` is the exposure duration in seconds. `t_min` and `t_max` identify the observation interval, normally as Modified Julian Dates. |
| Artifact retrieval | `COALESCE(a.datauri, o.dataurl) AS datauri`, `productfilename`, `contenttype`, `contentlength` | Required | Build the download request, confirm a FITS artifact, enforce the size limit, and show the filename/type. |
| Preview image | `COALESCE(p.previewuri, o.jpegurl) AS previewuri` | Required for preview UI; not a rejection gate | Supplies the archive JPEG preview without downloading and rendering the FITS file. The value may be a MAST `mast:` URI rather than an HTTP URL. |
| Science/ranking context | `em_min`, `em_max`, `wavelength_region`, `proposal_id`, `project`, `provenance_name` | Recommended, nullable | Rank filter diversity and retain useful spectral/provenance context. A missing value must not reject a product. |
| Image geometry | `posdimension1`, `posdimension2`, `possamplesize` | Recommended, nullable | Estimate image dimensions and sampling before reading FITS headers. HLA does not consistently populate these values, so use the FITS header as fallback. |

## Availability check

The profile was checked on 15 September 2026 around NGC 628 with a 0.1-degree
cone. Each mission was queried separately to avoid a combined `TOP` query being
filled by the first collection in `ORDER BY`. The sample contained 48 JWST, 100
HST, and 100 HLA science-product rows (248 total).

| Field group | JWST | HST | HLA | Decision |
|---|---:|---:|---:|---|
| Identity, eligibility, sky footprint, exposure and observation interval | 100% | 100% | 100% | Required |
| Product URI, preview URI, filename, MIME type, size | 100% | 100% | 100% | Required for retrieval/display |
| `project`, `provenance_name` | 100% | 100% | 100% | Keep |
| `proposal_id` | 100% | 88% | 100% | Keep as context; never a gate |
| `em_min`, `em_max`, `wavelength_region` | 100% | 80% | 74% | Optional enrichment |
| `posdimension1`, `posdimension2`, `possamplesize` | 100% | 88% | 0% | Optional enrichment; fall back to FITS headers |

Availability here means a non-null, non-empty value in this sample. It is an
empirical check, not a schema guarantee.

### Fields deliberately omitted from this lean profile

| Column | Reason |
|---|---|
| `posresolution` | Empty in all three mission samples. |
| `posboundsstcs` | Duplicates the selected `s_region` footprint for this workflow. |
| `mtflag` | Not populated by HLA and does not affect image suitability. |
| `srcden` | Mission-specific and not needed for grouping or coverage ranking. |
| `target_classification` | Inconsistently populated and not needed after resolving the requested target. |
| `obs_title` | Sparse, descriptive metadata that does not drive selection. |
| `proposal_pi`, `proposal_type`, `sequence_number` | Display/archive context, not required to choose or retrieve the science FITS artifact. |
| `t_obs_release` | Archive release time; not required to select already-public products. |

## Query and inspect 100 rows

```bash
.venv/bin/python Sources/scripts/query_mast_tap.py \
  --target "NGC 628" \
  --missions JWST,HST,HLA \
  --balanced-missions \
  --limit 100 \
  --output demo-mast-selected-columns-query.txt
```

The JSON output includes `columns`, overall and per-mission availability
summaries, the exact ADQL, and the returned rows. `--balanced-missions` sends one
query per mission and divides the total limit across them. Without that option, a combined
`TOP 100` result is not guaranteed to contain rows from every requested mission
because the final ordering groups rows by collection.

To inspect every field exposed by the three joined tables:

```bash
.venv/bin/python Sources/scripts/query_mast_tap.py --schema \
  --output mast-caom-tap-schema.json
```

The schema describes what a column can contain; only a data sample shows whether
that column is populated for JWST, HST, and HLA products.
