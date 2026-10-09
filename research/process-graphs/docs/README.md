# Phase 2 algorithm documentation

These documents explain the Mermaid pipeline examples in the parent directory. Each document describes the algorithm's purpose, inputs, flow, output, strengths, limitations, complexity, and implementation cautions.

The diagrams do not all solve the same problem. Some select science products, some assign colours, and some attempt both. They should therefore be compared by responsibility as well as by output quality.

| Diagram | Primary responsibility | Uses budget | Uses footprints | Exact optimization |
|---|---|---:|---:|---:|
| [00 Shared preparation](00-shared-preparation.md) | Prepare group/filter graph | No | No | No |
| [01 Wavelength palette](01-wavelength-palette.md) | RGB channel policy and group purchase | Yes | No | No |
| [02 Greedy group ranking](02-greedy-group-rank.md) | Whole-group selection and graph colouring | Yes | No | No |
| [03 RGB triple vote](03-rgb-triple-vote.md) | Select globally supported RGB triples | Yes | No | No |
| [04 Degree colouring](04-degree-coloring.md) | Assign conflict-free display colours | No | No | No |
| [05 Wavelength bins](05-wavelength-bins.md) | Spectral bins and group purchase | Yes | No | No |
| [06 File knapsack](06-file-knapsack.md) | Incremental product selection | Yes | No | Greedy |
| [07 LP relaxation](07-lp-relaxation.md) | Fractional global model and rounding | Yes | No | Fractional only |
| [08 Integer linear program](08-integer-linear-program.md) | Exact discrete group/filter model | Yes | No | Yes, for its model |
| [09 Constraint program](09-constraint-program.md) | Exact discrete model with preferred-filter rules | Yes | No | Yes, for its model |
| [10 Footprint search](10-footprint-search.md) | Stochastic coverage refinement | Yes | Yes | No |

## Shared evaluation rule

For a fair comparison, every selector should receive the same exact Phase 1 products, target grid, byte budget, product limit, wavelength table, and channel definitions. Reports should include actual selected bytes, product and group counts, filters, union coverage, coverage per channel, shared multi-channel coverage, runtime, and whether repeated runs are deterministic.

The group CSV is useful for summaries, but production selection should read `phase-1-qualified.json` so exact `datauri`, `contentlength`, `filters`, and `s_region` values are retained.

## How to read each document

Every companion document follows the same review structure:

1. Purpose and responsibility
2. Required inputs and definitions
3. Step-by-step pipeline flow
4. Implementation code or equations for each diagram node and decision branch
5. Worked example with concrete values
6. Reference pseudocode
7. Conceptual JSON output
8. Compact flow summary
9. Main advantages and limitations
10. Complexity discussion
11. Recommended changes and improved formulas

The node-level implementation sections describe the Mermaid source as written. Code and formulas under “recommended” or “improved” sections are proposals and are labelled separately.

## Cross-cutting review cautions

- `averageFileBytes` is an estimate; use exact product `contentlength` for an enforceable budget.
- An observation ID is not guaranteed to be a unique downloadable artifact; retain `datauri`.
- Filter tokens should come from the authoritative `filters` field, with ID parsing only as validation or fallback.
- Union footprint coverage does not prove multi-frequency coverage. Report coverage per channel and coverage shared by all required channels.
- A display hue, physical filter, wavelength bin, and RGB output channel are different concepts and should use different variable types.
- Deterministic comparison requires fixed inputs, tie-break rules, solver settings, and random seeds.

## Current NGC 628 baseline

The saved current Phase 2 result can be used as a comparison point:

| Metric | Value |
|---|---:|
| Selected products | 44 |
| Selected observation groups | 10 |
| Selected filters | 18 |
| Selected size | 1,974.147 MiB |
| Union coverage | 57.317% |
| Mean multi-filter coverage | 10.954% |
| Stop reason | Total budget exhausted |

Any alternative should report the same metrics plus per-channel and shared-channel coverage.
