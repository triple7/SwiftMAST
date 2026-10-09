# NGC 628 Phase 2 comparison

Every algorithm used the same qualified Phase 1 products and limits:

- Maximum file: 300 MiB
- Total budget: 2000 MiB
- Maximum products: 40
- Coverage grid: 48 × 48

[Open the ten-algorithm gallery](algorithm-comparison-gallery.png)

| Algorithm | Products | Groups | Filters | Size MiB | Coverage | Image |
|---|---:|---:|---:|---:|---:|---|
| `01-wavelength-palette` | 21 | 7 | 4 | 1865.32 | 51.33% | [PNG](01-wavelength-palette/phase-2-01-wavelength-palette-footprints.png) |
| `02-greedy-group-rank` | 39 | 9 | 17 | 1241.81 | 27.11% | [PNG](02-greedy-group-rank/phase-2-02-greedy-group-rank-footprints.png) |
| `03-rgb-triple-vote` | 12 | 4 | 3 | 1065.56 | 31.60% | [PNG](03-rgb-triple-vote/phase-2-03-rgb-triple-vote-footprints.png) |
| `04-degree-coloring` | 39 | 9 | 17 | 1241.81 | 27.11% | [PNG](04-degree-coloring/phase-2-04-degree-coloring-footprints.png) |
| `05-wavelength-bins` | 21 | 6 | 5 | 1270.49 | 23.45% | [PNG](05-wavelength-bins/phase-2-05-wavelength-bins-footprints.png) |
| `06-file-knapsack` | 29 | 13 | 12 | 1924.34 | 66.35% | [PNG](06-file-knapsack/phase-2-06-file-knapsack-footprints.png) |
| `07-lp-relaxation` | 40 | 10 | 16 | 1431.44 | 57.32% | [PNG](07-lp-relaxation/phase-2-07-lp-relaxation-footprints.png) |
| `08-integer-linear-program` | 40 | 10 | 18 | 1787.99 | 57.32% | [PNG](08-integer-linear-program/phase-2-08-integer-linear-program-footprints.png) |
| `09-constraint-program` | 40 | 10 | 18 | 1787.99 | 57.32% | [PNG](09-constraint-program/phase-2-09-constraint-program-footprints.png) |
| `10-footprint-search` | 25 | 11 | 21 | 1983.94 | 66.96% | [PNG](10-footprint-search/phase-2-10-footprint-search-footprints.png) |

## Comparison-policy notes

- **04-degree-coloring:** The source diagram assigns colours but does not select products; the comparison uses option 02's selected products before colouring.
- **07-lp-relaxation:** The comparison solves the documented fractional value/byte budget relaxation and applies deterministic feasible rounding; it omits full link-variable channels.
- **08-integer-linear-program:** SciPy MILP implements binary product inclusion, group opening, product count, and byte budget; display channels are assigned after selection.
- **09-constraint-program:** Uses option 08's binary selection and applies the common-filter primary-colour gate deterministically because OR-Tools is not installed.
- **10-footprint-search:** Uses deterministic marginal footprint/filter search for reproducible comparison; the stochastic annealing/population variants remain future refinements.
