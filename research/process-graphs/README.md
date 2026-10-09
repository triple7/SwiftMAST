# Process-graph executable experiment

These scripts turn the Phase 1 and Phase 2 diagrams into a runnable metadata-only experiment. They query real MAST products and use real CAOM `s_region` footprints, but they never download FITS files or preview-image pixels.

## Phase 1: fetch and prepare products

```bash
.venv/bin/python research/process-graphs/scripts/phase1.py \
  --target "NGC 628" \
  --missions JWST,HST,HLA \
  --radius 0.05 \
  --per-filter-limit 1000 \
  --max-file-mib 2048 \
  --run-dir research/process-graphs/runs/ngc628
```

Phase 1 reuses the maintained TAP and qualification functions in `Sources/scripts/mast_composite_pipeline.py`. It resolves the target, queries public level 3/4 image and cube products, keeps mission-specific science mosaics, validates sizes and footprints, removes duplicates, and groups products by observation.

It produces:

- `phase-1-qualified.json`: exact qualified MAST product metadata.
- `phase-1-observation-groups.csv`: the group summary consumed conceptually by `00-shared-preparation.mmd`.
- `phase-1-process-graph-input.json`: products, groups, representative-product view, filter frequency, adjacency, degree, and maximum group size.
- TAP caches, rejection audits, and qualification charts from the maintained pipeline.

The prepared artifact preserves all exact products. Its representative-product list is an additional view and does not delete products with an equivalent filter signature.

## Phase 2: select and render

List the current implementations:

```bash
.venv/bin/python research/process-graphs/scripts/phase2.py --list-algorithms
```

Run one algorithm:

```bash
.venv/bin/python research/process-graphs/scripts/phase2.py \
  --input research/process-graphs/runs/ngc628/phase-1-qualified.json \
  --algorithm 02-greedy-group-rank \
  --max-file-mib 300 \
  --max-total-mib 2000 \
  --max-products 150 \
  --output-dir research/process-graphs/runs/ngc628/02-group-rank
```

Phase 2 accepts either `phase-1-qualified.json` or `phase-1-process-graph-input.json`. It performs no TAP request.

### Implemented selectors

| Option | Selection behavior |
|---|---|
| `01-wavelength-palette` | Selects groups with usable blue, green, and red wavelength channels. |
| `02-greedy-group-rank` | Ranks complete groups by distinct filters per exact MiB. |
| `03-rgb-triple-vote` | Finds a globally supported three-filter set and buys compatible groups. |
| `04-degree-coloring` | Applies conflict-graph colouring to option 02's selected products because the source diagram contains no selector. |
| `05-wavelength-bins` | Selects groups spanning the configured spectral bins. |
| `06-file-knapsack` | Selects individual products by marginal channels per exact byte. |
| `07-lp-relaxation` | Builds a fractional value/byte solution and performs deterministic feasible rounding. |
| `08-integer-linear-program` | Uses SciPy MILP for binary product selection and group opening under count and byte limits. |
| `09-constraint-program` | Uses the binary selection and applies the common-filter primary-colour gate deterministically. |
| `10-footprint-search` | Iteratively maximizes new footprint cells and filters per MiB. |

All ten options are runnable for comparison. Where a source diagram is not a complete standalone selector, the selection JSON records the explicit comparison policy or approximation used. In particular, option 04 inherits option 02 selection, option 09 does not claim to be an OR-Tools CP-SAT solve, and option 10 currently uses deterministic footprint search rather than stochastic annealing.

### Selection output

Each run produces:

- `phase-2-<algorithm>-selection.json`: options, summary, selected real product rows, decisions, and colour assignment.
- `phase-2-<algorithm>-footprints.png`: visual simulation of the selection.
- `phase-2-<algorithm>-render.json`: colour legend and render metadata.

The summary includes selected product, group, filter, and byte counts plus union coverage as a fraction and percentage.

## Compare every Phase 2 algorithm

Run every selector against the same Phase 1 input and limits, then assemble a
single gallery and summary:

```bash
.venv/bin/python research/process-graphs/scripts/compare_algorithms.py \
  --input research/pipeline-runs/ngc628/phase-1-qualified.json \
  --output-dir research/process-graphs/comparison-outputs/ngc628 \
  --max-file-mib 300 \
  --max-total-mib 2000 \
  --max-products 40 \
  --grid-dimension 48 \
  --texture-density 10 \
  --dpi 120
```

The command prints the absolute paths of the output folder, combined gallery,
JSON summary, and generated comparison README. Add `--reuse-existing` to rebuild
the gallery from completed algorithm runs without rerunning the selectors.

The checked-in NGC 628 comparison is under
`research/process-graphs/comparison-outputs/ngc628/`. Unlike temporary
`research/process-graphs/runs/` data, this comparison folder is not ignored by
Git, so its images and reports can be reviewed with the diagrams.

## Footprint visualization

The outer shapes come directly from each selected product's `s_region` or `posboundsstcs` metadata. Polygons remain polygons and circles remain circles after projection to local RA/Dec offsets.

The interior is deliberately synthetic:

- A near-black tinted field represents the background of the exposure.
- Broad faint emission, middle-sized glow, dense stellar points, bright halos, and limited dust create multiple luminance levels similar in balance to the local MIRI reference previews.
- Large-scale structures and star locations are deterministically seeded by `observation_group_id`, with `obs_id` as the fallback. Products from the same observation stack therefore retain the same underlying synthetic morphology across filters and repeated runs.
- Individual-filter colourization follows `output RGB = luminance × filter RGB`: black remains black and maximum luminance becomes the full filter colour. White is never inserted into an individually colourized image.
- Each filter adds only a small deterministic emission layer, so filter products remain recognizably related without becoming exact clones. The combined view adds the contributing RGB channels and clips them to the display range; balanced strong red, green, and blue approach white, while unequal proportions remain coloured.
- Synthetic texture is clipped to each real footprint.
- Overlapping translucent footprints show how the selected products are spatially arranged.
- A dashed circle shows the requested target search radius.

This visualization is suitable for comparing selection structure. It must not be interpreted as astronomical pixel data, image quality, or source brightness.

Colouring can be changed without rerunning Phase 1:

```bash
# Use the algorithm/filter colours (default)
--color-by algorithm

# Restart the AOSImage-style distributed palette within every observation group
--color-by observation-group

# Use fixed mission colours
--color-by mission
```

Control the visual texture with `--texture-density` and output resolution with `--dpi`.

Add `--render-stages` to generate, for every selected product, its grayscale
synthetic luminance, colourized version, final combined result, and a comparison
sheet containing the complete sequence.

## Render one observation for inspection

Use an exact Phase 1 `obs_id` to create a standalone sample and a properties JSON:

```bash
.venv/bin/python research/process-graphs/scripts/phase2.py \
  --input research/process-graphs/runs/ngc628/phase-1-qualified.json \
  --sample-observation-id "HST_11229_06_NIC_NIC2_F110W" \
  --sample-filter F110W \
  --output-dir research/process-graphs/runs/ngc628/sample-observation
```

The properties file records the mission, instrument, filter, wavelength bounds, size, `s_region`, parsed geometry, observation texture key, and filter-variation key used to generate the sample.
