# Shared preparation

Source: [`../00-shared-preparation.mmd`](../00-shared-preparation.mmd)

## Purpose

The shared-preparation flow converts the Phase 1 observation-group CSV into the group/filter relationships used by the other example algorithms. It is not itself a selection algorithm.

For the saved NGC 628 example, it starts with 173 group rows, retains 38 qualified rows, discovers 33 filter names, creates 116 filter-adjacency pairs, and observes a maximum group size of ten filters.

## Inputs

- `phase-1-observation-groups.csv`
- `budgetBytes`
- `WavelengthTable`, in nanometres
- Ordered `DisplayHues`
- `primaryChannelCount`, default 3
- `BlueMaxNm`, default 500
- `GreenMaxNm`, default 650

The last six values are caller configuration and are not present in the CSV.

## Flow

### 1. Read and qualify groups

Each CSV row is read and retained only when `qualifies` is true. Non-qualifying rows enter no later count or relationship.

### 2. Recover observation IDs

The non-blank `observationID1...observationID10` columns become the row's `observationIDs` list. Their CSV order is preserved.

### 3. Parse filter tokens

Filter-like tokens are extracted from each observation ID using names beginning with `F`, `FQ`, or `G` followed by digits. Tokens are uppercased and `CLEAR` is ignored. Hyphenated IDs can yield more than one token.

Examples:

```text
f405n-f444w    -> F405N, F444W
f110w_all      -> F110W
f110w_coarse-all -> F110W
```

### 4. Build each group's filter set

`filtersInGroup` is the union of all parsed tokens in the row. In the sample data, its size agrees with the CSV `filterCount` field.

### 5. Estimate a per-file price

The flow computes:

```text
averageFileBytes = totalBytes / observationIDCount
```

Every ID in the row is assigned this same estimated price.

### 6. Collapse representative IDs

IDs with the same sorted filter-token tuple are treated as equivalent. Only the alphabetically first ID is retained as the representative.

This means `_all` and `_coarse-all` products can collapse even when their exact size, footprint, or resolution differs.

### 7. Build global filter statistics

- `AllFilters` is the union of filters in qualified groups.
- `groupCount(filter)` is the number of qualified groups containing the filter.
- Two filters are adjacent when they occur together in at least one qualified group.
- `degree(filter)` is the number of adjacent filters.
- `maxFiltersInAnyGroup` is the largest qualified group filter count.

These values form a filter-conflict graph used by the colouring and optimization options.

## Implementation by diagram node

### Read and qualify each CSV row

```python
import csv

with open("phase-1-observation-groups.csv", newline="") as source:
    rows = list(csv.DictReader(source))

qualified_rows = [
    row for row in rows
    if row["qualifies"].strip().lower() == "true"
]
```

The qualification decision reduces the documented 173 input rows to 38. A dropped row contributes nothing to later totals or graph edges.

### Recover the observation IDs

```python
def observation_ids(row, maximum=10):
    return [
        row[f"observationID{index}"].strip()
        for index in range(1, maximum + 1)
        if row.get(f"observationID{index}", "").strip()
    ]
```

### Parse filter tokens from each ID

```python
import re

FILTER_TOKEN = re.compile(r"(?:FQ|F|G)\d+[A-Z]*", re.IGNORECASE)

def parse_filter_tokens(observation_id):
    return tuple(
        token.upper()
        for token in FILTER_TOKEN.findall(observation_id)
        if token.upper() != "CLEAR"
    )
```

This is a naming heuristic. Production code should use authoritative product metadata when available.

### Build `filtersInGroup`

```python
tokens_by_id = {
    obs_id: parse_filter_tokens(obs_id)
    for obs_id in observation_ids(row)
}
filters_in_group = {
    token for tokens in tokens_by_id.values() for token in tokens
}

assert len(filters_in_group) == int(row["filterCount"])
```

The assertion documents the example dataset. A real mismatch should be reported rather than silently ignored.

### Estimate one price for every ID

```python
id_count = int(row["observationIDCount"])
if id_count <= 0:
    raise ValueError("qualified row has no observation IDs")

average_file_bytes = int(row["totalBytes"]) / id_count
estimated_price = {
    obs_id: average_file_bytes for obs_id in observation_ids(row)
}
```

This is not an exact product price; Phase 1 JSON `contentlength` should be used when available.

### Collapse IDs with the same token signature

```python
from collections import defaultdict

ids_by_signature = defaultdict(list)
for obs_id, tokens in tokens_by_id.items():
    signature = tuple(sorted(set(tokens)))
    ids_by_signature[signature].append(obs_id)

representative_ids = [
    sorted(ids)[0]
    for signature, ids in sorted(ids_by_signature.items())
]
```

Consequently, `f110w_all` and `f110w_coarse-all` compete under the same `(F110W)` signature even when their resolution and size differ.

### Build counts and the filter-conflict graph

```python
from collections import Counter, defaultdict
from itertools import combinations

all_filters = set()
group_count = Counter()
adjacent = defaultdict(set)

for group in prepared_groups:
    filters = group["filters"]
    all_filters.update(filters)
    group_count.update(filters)
    for left, right in combinations(sorted(filters), 2):
        adjacent[left].add(right)
        adjacent[right].add(left)

degree = {name: len(adjacent[name]) for name in all_filters}
max_filters_in_any_group = max(
    (len(group["filters"]) for group in prepared_groups),
    default=0,
)
```

A row containing ten filters contributes a ten-node clique and up to `C(10,2) = 45` edges.

### Attach caller-only configuration

```python
config = {
    "budgetBytes": budget_bytes,
    "WavelengthTable": wavelength_table,
    "DisplayHues": display_hues,
    "primaryChannelCount": primary_channel_count,
    "BlueMaxNm": blue_max_nm,
    "GreenMaxNm": green_max_nm,
}

if budget_bytes <= 0:
    raise ValueError("budgetBytes must be positive")
if len(display_hues) < primary_channel_count:
    raise ValueError("not enough display hues")
```

These values do not come from the CSV and should remain explicit run configuration.

## Output

The conceptual output contains:

- Qualified group rows
- Observation IDs and representative IDs
- Filter sets per group
- Estimated per-ID costs
- Global filter names and group counts
- Filter adjacency and degree
- Maximum group size
- Caller budget, wavelength, channel, and colour configuration

## Advantages

- Gives every example algorithm a common vocabulary.
- Deterministic and inexpensive.
- Makes filter co-occurrence explicit as a graph.
- Produces useful frequency and conflict statistics.

## Limitations

- It discards exact per-product sizes and footprints.
- Filter names are inferred from IDs rather than the authoritative `filters` column.
- Alphabetical representative selection is not a scientific or cost-based rule.
- Equal `uriCount` and `observationIDCount` is a property of this run, not a general archive guarantee.
- Group-average cost can substantially overestimate or underestimate individual products.
- It combines selection channels and display-colour configuration before their responsibilities are defined.

## Complexity

Let `P` be the number of IDs, `F` the number of filters, and `K` the maximum filters per group. Token extraction is approximately `O(P)`. Building all within-group adjacency pairs is `O(G * K^2)`. With the current small group sizes, preparation is inexpensive.

## Recommended implementation changes

Build the same graph from `phase-1-qualified.json`. Preserve exact `datauri`, `contentlength`, `filters`, `s_region`, mission, instrument, quality metadata, and observation group. Collapse products only after explicitly comparing footprint, size, resolution, and provenance.

## Worked example

Suppose one qualified CSV row contains:

| Field | Value |
|---|---|
| `observationGroup` | `hst_skycell-p1596x12y18_wfc3_ir` |
| `observationIDCount` | 4 |
| `totalBytes` | 3,164,803,200 |
| `observationID1` | `..._f110w_all` |
| `observationID2` | `..._f110w_coarse-all` |
| `observationID3` | `..._f160w_all` |
| `observationID4` | `..._f160w_coarse-all` |

Token extraction produces two token tuples:

```text
(F110W) -> two IDs
(F160W) -> two IDs
```

The diagram keeps the alphabetically first ID in each tuple and estimates every file as:

```text
averageFileBytes = 3,164,803,200 / 4
                 = 791,200,800 bytes
                 ≈ 754.55 MiB
```

The actual sample products are approximately 1,358 MiB for `_all` and 151 MiB for `_coarse-all`. This shows why token equality and average price are insufficient for choosing representatives.

## Reference pseudocode

```python
qualified = [row for row in csv_rows if row["qualifies"]]
all_filters = set()
group_count = Counter()
adjacent = set()

for row in qualified:
    ids = non_blank_observation_ids(row)
    token_sets = {obs_id: parse_filter_tokens(obs_id) for obs_id in ids}
    filters = set().union(*token_sets.values())
    average_bytes = row["totalBytes"] / row["observationIDCount"]
    representatives = alphabetically_first_per_token_tuple(token_sets)

    all_filters.update(filters)
    group_count.update(filters)
    adjacent.update(all_unordered_pairs(filters))
```

## Conceptual output

```json
{
  "qualified_group_count": 38,
  "filter_count": 33,
  "adjacent_pair_count": 116,
  "max_filters_in_group": 10,
  "groups": [
    {
      "group": "hst_9733_01_acs_hrc",
      "observation_ids": ["..._f435w", "..._f555w", "..._f814w"],
      "filters": ["F435W", "F555W", "F814W"],
      "average_file_bytes": 29157120
    }
  ]
}
```

## Compact flow

```text
Group CSV
  -> retain qualified rows
  -> read observation IDs
  -> parse filter tokens
  -> estimate average price
  -> collapse equal token sets
  -> count filter frequency
  -> build filter-conflict graph
  -> attach caller configuration
```

## Improved preparation model

The production structure should remain product-based:

```python
Product = {
    "identity": datauri,
    "group": observation_group_id,
    "filters": authoritative_filter_tokens,
    "bytes": exact_contentlength,
    "footprint": parsed_s_region,
    "mission": obs_collection,
    "instrument": instrument_name,
}
```

Two products should be considered interchangeable only when their scientific and operational properties meet explicit tolerances. A representative score could be:

```text
representativeUtility =
    coverageWeight * targetCoverage
  + qualityWeight * normalizedQuality
  - sizeWeight * sizeMiB
```
