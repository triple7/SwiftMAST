# Wavelength bins

Source: [`../05-wavelength-bins.mmd`](../05-wavelength-bins.mmd)

## Purpose

The wavelength-bins algorithm partitions filters into configured spectral ranges, chooses representative products for occupied bins, and purchases groups that contain a minimum number of bins.

## Inputs

- Qualified groups and representative IDs
- Parsed filters and global `groupCount`
- `WavelengthTable`
- `BinEdgesNm`, default `0, 300, 450, 600, 800, 2000, 5000, 30000`
- One `DisplayHues` entry per bin
- `minimumBins`, default 3
- `budgetBytes`

## Flow

### 1. Create spectral bins

For consecutive edges `edge[i]` and `edge[i+1]`, a wavelength belongs to bin `i` when:

```text
edge[i] <= wavelength < edge[i+1]
```

Each bin receives `DisplayHues[i]`. The algorithm stops if the palette is shorter than the number of bins.

### 2. Assign filters

Known filters receive a `binOf` value. Unknown or out-of-range wavelengths are `UNASSIGNED`. An ID containing an unassigned token is not a candidate.

### 3. Choose one winner per group and bin

For a group and bin, candidates are representative IDs containing at least one token in that bin. The candidate's bin score is the largest `groupCount` among its tokens in that bin. Highest score wins; alphabetical ID breaks ties.

### 4. Evaluate group completeness

Winners are deduplicated into `keptIDs`, and `filledBins` counts bins with winners. A group opens only if `filledBins >= minimumBins`.

### 5. Rank by bin density

```text
estimatedCost = averageFileBytes * number of kept IDs
density = filledBins / estimatedCost
```

Openable groups are sorted by density descending and name ascending.

### 6. Apply the budget

Groups are accepted in order when their estimated cost fits the remaining budget. Later smaller groups can still be accepted after a larger group is skipped.

## Implementation by diagram node

### Validate the spectral bins and display palette

```python
if len(bin_edges_nm) < 2:
    raise ValueError("at least two bin edges are required")
if any(left >= right for left, right in zip(bin_edges_nm, bin_edges_nm[1:])):
    raise ValueError("bin edges must be strictly increasing")

bin_count = len(bin_edges_nm) - 1
if len(display_hues) < bin_count:
    raise ValueError(f"need {bin_count} display hues")
```

### Assign each filter to a half-open wavelength interval

```python
def bin_for(wavelength, edges):
    if wavelength is None:
        return None
    for index, (low, high) in enumerate(zip(edges, edges[1:])):
        if low <= wavelength < high:
            return index
    return None

bin_of = {
    name: bin_for(wavelength_table.get(name), bin_edges_nm)
    for name in all_filters
}
bin_color = {index: display_hues[index] for index in range(bin_count)}
```

The upper edge is excluded, so a wavelength exactly equal to an interior boundary enters the following bin.

### Reject invalid IDs and find candidates for each bin

```python
valid_ids = []
for obs_id in group["representative_ids"]:
    tokens = group["tokens_by_id"][obs_id]
    if any(bin_of[token] is None for token in tokens):
        continue
    valid_ids.append(obs_id)

candidates_by_bin = {
    index: [
        obs_id for obs_id in valid_ids
        if any(bin_of[token] == index for token in group["tokens_by_id"][obs_id])
    ]
    for index in range(bin_count)
}
```

### Score and select one winner per bin

```python
def score_in_bin(obs_id, bin_index):
    return max(
        group_count[token]
        for token in group["tokens_by_id"][obs_id]
        if bin_of[token] == bin_index
    )

winners = {
    index: min(
        candidates,
        key=lambda obs_id: (-score_in_bin(obs_id, index), obs_id),
        default=None,
    )
    for index, candidates in candidates_by_bin.items()
}
```

### Deduplicate winners and test `minimumBins`

```python
kept_ids = {winner for winner in winners.values() if winner is not None}
filled_bins = sum(winner is not None for winner in winners.values())
openable = filled_bins >= minimum_bins
```

`filled_bins` counts occupied bins; it does not count distinct filter names.

### Calculate density and rank openable rows

```python
estimated_cost = group["average_file_bytes"] * len(kept_ids)
density = filled_bins / estimated_cost

openable_rows.sort(key=lambda item: (-item["density"], item["group"]))
```

### Traverse rows under the budget

```python
spent = 0
accepted = []
for candidate in openable_rows:
    if spent + candidate["estimated_cost"] > budget_bytes:
        continue
    accepted.append(candidate)
    spent += candidate["estimated_cost"]
```

## Output

- Accepted representative IDs
- Estimated bytes spent
- Filter-to-bin and bin-to-display-colour mapping
- Filled-bin count per accepted group

## Advantages

- Spectral meaning is stable and easy to explain.
- Supports more than three wavelength regions.
- Keeps the same filter colour across groups.
- Configurable minimum spectral diversity.
- Deterministic and inexpensive.

## Limitations

- Does not use spatial coverage.
- Bin edges are policy choices that can strongly change results.
- Seven default bins require at least seven distinguishable colours.
- Unknown wavelengths remove products.
- Uses popularity and alphabetical ties instead of exact product utility.
- Uses average file sizes.
- A multi-filter product can fill multiple bins.
- The diagram's claim that F110W and F160W fill two default bins appears inconsistent: standard wavelengths near 1100 and 1600 nm both fall in `[800, 2000)`.

## Complexity

With a fixed number of bins, preparation and winner selection are approximately `O(P * B)`, followed by `O(G log G)` ranking.

## Recommended implementation changes

Publish and validate the wavelength table and units. Test bin-boundary behaviour explicitly. Use exact product rows and sizes. Score groups by new spectral bins plus per-bin footprint coverage. Decide whether a multi-filter artifact genuinely supplies independent layers before allowing it to fill multiple bins.

## Worked example

Using the default edges:

```text
0, 300, 450, 600, 800, 2000, 5000, 30000 nm
```

these sample filters map as follows:

| Filter | Representative wavelength | Bin |
|---|---:|---:|
| F275W | 275 nm | 0: `[0,300)` |
| F435W | 435 nm | 1: `[300,450)` |
| F555W | 555 nm | 2: `[450,600)` |
| F606W | 590–600 nm, table-dependent | 2 or boundary-sensitive |
| F814W | 814 nm | 4: `[800,2000)` |
| F110W | 1100 nm | 4: `[800,2000)` |
| F160W | 1600 nm | 4: `[800,2000)` |
| F2550W | 25,500 nm | 6: `[5000,30000)` |

A group containing F435W, F555W, and F814W fills three bins and opens when `minimumBins = 3`. A group containing only F110W and F160W fills one default bin, despite containing two filters.

## Reference pseudocode

```python
def bin_for(wavelength, edges):
    for index, (low, high) in enumerate(pairwise(edges)):
        if low <= wavelength < high:
            return index
    return None

for group in qualified_groups:
    winners = {}
    for bin_index in range(bin_count):
        candidates = ids_with_token_in_bin(group, bin_index)
        winners[bin_index] = highest_group_count_candidate(candidates)

    kept = set(value for value in winners.values() if value)
    filled = count_non_null(winners)
    if filled >= minimum_bins:
        cost = average_bytes(group) * len(kept)
        density = filled / cost
        add_openable(group, kept, density, cost)
```

## Conceptual output

```json
{
  "bin_edges_nm": [0, 300, 450, 600, 800, 2000, 5000, 30000],
  "accepted_groups": [
    {
      "group": "example-group",
      "filled_bins": [1, 2, 4],
      "kept_ids": ["..._f435w", "..._f555w", "..._f814w"],
      "estimated_cost_bytes": 90000000
    }
  ],
  "spent_bytes": 90000000
}
```

## Compact flow

```text
Wavelength table and bin edges
  -> assign every filter to a spectral bin
  -> reject IDs with unassigned tokens
  -> choose popular winner per group/bin
  -> count filled bins
  -> require minimum spectral diversity
  -> rank by bins per estimated byte
  -> buy groups within budget
```

## Improved density formula

```text
binValue =
    newBinWeight * newBins
  + coverageWeight * newPerBinCoverage
  + overlapWeight * sharedRequiredBinCoverage

density = binValue / exactSelectedBytesMiB
```

The wavelength table should store effective or pivot wavelengths explicitly; inferring wavelength from the digits in a filter name is unsafe.
