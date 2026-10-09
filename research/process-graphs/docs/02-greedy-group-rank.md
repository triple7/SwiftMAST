# Greedy group ranking

Source: [`../02-greedy-group-rank.mmd`](../02-greedy-group-rank.mmd)

## Purpose

The greedy group-ranking algorithm selects complete observation groups according to how many filters they provide per MiB. After selection, it assigns categorical display colours so filters that occur together receive different colours.

Its primary selection rule is:

> Prefer the qualified observation group with the greatest filter count relative to its complete download size.

Unlike the wavelength-palette algorithm, its colours have no wavelength meaning. They are conflict-free display categories.

## 1. Required inputs

The algorithm reads `phase-1-observation-groups.csv`.

Each row supplies:

| Field | Meaning |
|---|---|
| `observationGroup` | Stable group name |
| `qualifies` | Whether Phase 1 accepted the group |
| `observationIDCount` | Number of distinct observation IDs |
| `uriCount` | Number of product URIs summarized by the group |
| `filterCount` | Number of distinct parsed filters |
| `totalBytes` | Size of every product in the group |
| `observationID1...N` | Products retained if the group is purchased |

The caller also supplies:

```python
budget_bytes: int
display_hues: list[str]  # index 0 is most preferred
```

The shared preparation supplies:

```python
filters_in_group: dict[str, set[str]]
group_count: dict[str, int]
adjacent: dict[str, set[str]]
```

## 2. Keep qualified groups

Every CSV row first passes through the qualification gate:

```python
qualified_groups = [
    row for row in group_rows
    if row["qualifies"] is True
]
```

Rows rejected during Phase 1 do not contribute to ranking, spending, selected-filter totals, or colouring.

The algorithm assumes Phase 1 has already checked the science-mosaic filename, download URI, positive file size, product-size limit, valid footprint, filter, instrument, and minimum number of distinct observation IDs.

## 3. Calculate the group-ranking score

The intended score is filters per mebibyte:

```text
sizeMiB = totalBytes / 1,048,576
score   = filterCount / sizeMiB
```

Equivalent code:

```python
MIB = 1_048_576

def group_score(group: dict) -> float:
    size_mib = group["totalBytes"] / MIB
    return group["filterCount"] / size_mib
```

The parentheses are important:

```text
Correct:   filterCount / (totalBytes / 1,048,576)
Incorrect: filterCount / totalBytes / 1,048,576
```

### Score example

```text
Group A: 8 filters / 400 MiB = 0.020 filters per MiB
Group B: 3 filters / 100 MiB = 0.030 filters per MiB
```

Group B ranks higher even though Group A contains more filters, because B provides more filters for each MiB downloaded.

## 4. Sort the observation groups

Qualified groups are sorted by score descending and observation-group name ascending:

```python
ranked_groups = sorted(
    qualified_groups,
    key=lambda group: (
        -group_score(group),
        group["observationGroup"],
    ),
)
```

The alphabetical tie-break makes repeated runs deterministic.

| Group | Filters | Size | Score | Order |
|---|---:|---:|---:|---:|
| B | 3 | 100 MiB | 0.030 | 1 |
| A | 8 | 400 MiB | 0.020 | 2 |
| C | 4 | 250 MiB | 0.016 | 3 |
| D | 3 | 300 MiB | 0.010 | 4 |

## 5. Initialize budget state

```python
spent = 0
accepted_rows = []
```

`spent` represents the complete size of accepted groups, not an estimate for a subset of their products.

## 6. Traverse groups in ranked order

Each group is considered exactly once:

```python
for group in ranked_groups:
    fits = spent + group["totalBytes"] <= budget_bytes

    if fits:
        accepted_rows.append(group)
        spent += group["totalBytes"]
    else:
        continue
```

A group that does not fit is skipped, but traversal continues. A smaller lower-ranked group may still be accepted.

### Budget example

With a 500 MiB budget:

```text
B: accept -> spent = 100 MiB
A: accept -> spent = 500 MiB
C: skip   -> 500 + 250 > 500 MiB
D: skip   -> 500 + 300 > 500 MiB
```

The algorithm does not ask whether A and B cover the same sky area or repeat the same filters.

## 7. Retain every product in an accepted group

Purchasing a row means purchasing all its observation IDs:

```python
accepted_ids = [
    observation_id
    for group in accepted_rows
    for observation_id in group["observationIDs"]
]
```

If a group contains:

```text
..._f110w_all
..._f110w_coarse-all
..._f160w_all
..._f160w_coarse-all
```

all four are retained. This preserves group integrity, but it can download spatially or scientifically redundant representations.

## 8. Build the selected-filter set

```python
selected_filters = set().union(
    *(filters_in_group[group["observationGroup"]] for group in accepted_rows)
)
```

Example:

```text
Group A = {F435W, F555W, F814W}
Group B = {F555W, F606W, F814W}

SelectedFilters = {F435W, F555W, F606W, F814W}
```

Repeated filters appear once in `SelectedFilters`, even though their products remain in every accepted group.

## 9. Build the selected-filter conflict graph

Two selected filters are adjacent when they share a qualified observation group:

```python
selected_adjacency = {
    filter_name: {
        other
        for other in adjacent[filter_name]
        if other in selected_filters
    }
    for filter_name in selected_filters
}
```

For a group containing F435W, F555W, and F814W, the graph contains:

```text
F435W <-> F555W
F435W <-> F814W
F555W <-> F814W
```

These three filters form a clique and need three different categorical colours.

The diagram derives adjacency from all qualified rows, not only accepted rows. This supports future global compatibility but may require colours for conflicts absent from the selected result.

## 10. Calculate degree within the selected set

```python
degree_in_set = {
    filter_name: len(selected_adjacency[filter_name])
    for filter_name in selected_filters
}
```

| Filter | Adjacent selected filters | Degree |
|---|---|---:|
| F435W | F555W, F814W | 2 |
| F555W | F435W, F606W, F814W | 3 |
| F606W | F555W, F814W | 2 |
| F814W | F435W, F555W, F606W | 3 |

`degreeInSet` measures colour difficulty. `groupCount` separately measures how frequently the filter occurs in all qualified groups.

## 11. Determine the colouring order

Filters are ordered by degree descending, group count descending, and filter name ascending:

```python
color_order = sorted(
    selected_filters,
    key=lambda filter_name: (
        -degree_in_set[filter_name],
        -group_count[filter_name],
        filter_name,
    ),
)
```

Highly connected filters are coloured first because they are the hardest to place. Among equally connected filters, common filters receive priority.

## 12. Assign the smallest available hue index

For each filter, hue indexes already used by coloured neighbours are forbidden:

```python
hue_index = {}

for filter_name in color_order:
    forbidden = {
        hue_index[neighbor]
        for neighbor in selected_adjacency[filter_name]
        if neighbor in hue_index
    }

    candidate = 0
    while candidate in forbidden:
        candidate += 1

    hue_index[filter_name] = candidate
```

Example:

```text
F555W -> hue 0
F814W -> hue 1
F435W is adjacent to both -> hue 2
F606W is adjacent to hues 0 and 1, but not F435W -> reuse hue 2
```

## 13. Calculate the required hue count

```python
hue_count = 1 + max(hue_index.values(), default=-1)
```

If used indexes are `0, 1, 2, 3`, four hues are required. A ten-filter group forms a clique of ten and requires at least ten categorical colours.

Greedy colouring can use more colours than the graph's theoretical minimum because its result depends on processing order.

## 14. Validate display-palette capacity

```python
if len(display_hues) < hue_count:
    shortfall = hue_count - len(display_hues)
    return {
        "status": "insufficient_display_hues",
        "required": hue_count,
        "available": len(display_hues),
        "shortfall": shortfall,
    }
```

Example:

```text
required hues = 10
available display hues = 6
shortfall = 4
```

This failure occurs after group selection, so the algorithm can select a valid download set that cannot be coloured with the supplied palette.

## 15. Calculate display-colour salience

Earlier palette indexes are preferred:

```python
def salience(display_index: int, display_hues: list[str]) -> int:
    return len(display_hues) - display_index
```

| Display index | Salience with six colours |
|---:|---:|
| 0 | 6 |
| 1 | 5 |
| 2 | 4 |
| 3 | 3 |
| 4 | 2 |
| 5 | 1 |

## 16. Find the best hue-to-display permutation

Abstract hue indexes are mapped onto actual display colours. The diagram tries every permutation:

```python
from itertools import permutations

def permutation_score(mapping):
    return sum(
        group_count[filter_name]
        * salience(mapping[hue_index[filter_name]], display_hues)
        for filter_name in selected_filters
    )

best_mapping = max(
    permutations(range(hue_count)),
    key=lambda mapping: (
        permutation_score(mapping),
        tuple(-value for value in mapping),
    ),
)
```

Suppose the combined popularity of hue classes is:

```text
hue 0 -> 40
hue 1 -> 15
hue 2 -> 25
```

The best mapping gives the most salient display colour to hue 0, the second to hue 2, and the third to hue 1.

## 17. Assign final display colours

```python
filter_colors = {
    filter_name: display_hues[best_mapping[hue_index[filter_name]]]
    for filter_name in selected_filters
}
```

Adjacent filters have different colours. Non-adjacent filters can reuse a colour. The colours are visual categories rather than wavelength-based RGB meanings.

## 18. Conceptual output

```json
{
  "status": "complete",
  "budget_bytes": 524288000,
  "spent_bytes": 524288000,
  "accepted_groups": ["group-b", "group-a"],
  "accepted_observation_ids": ["..."],
  "selected_filters": ["F435W", "F555W", "F606W", "F814W"],
  "hue_count": 3,
  "hue_indexes": {
    "F555W": 0,
    "F814W": 1,
    "F435W": 2,
    "F606W": 2
  },
  "filter_colors": {
    "F555W": "#0072B2",
    "F814W": "#D55E00",
    "F435W": "#009E73",
    "F606W": "#009E73"
  }
}
```

## Compact flow

```text
Read group CSV
  -> retain qualifies=True rows
  -> calculate filters per MiB
  -> sort groups by score
  -> accept complete groups within budget
  -> union filters from accepted groups
  -> build selected-filter conflict graph
  -> order filters by degree and popularity
  -> greedily assign abstract hue indexes
  -> calculate required hue count
  -> validate DisplayHues capacity
  -> map important hue classes to preferred display colours
  -> output accepted groups, spending, and colours
```

## Main advantages

### Simple and auditable ranking

Filters per MiB is easy to calculate, explain, and reproduce.

### Exact group-level budget accounting

The selection stage charges `totalBytes`, so it does not rely on average per-file estimates when purchasing complete rows.

### Observation-group integrity

Every accepted group remains intact, which is useful when its products are already designed to align.

### Deterministic behaviour

Score, name, degree, popularity, and lexicographic tie-breaks make repeated runs stable.

### Globally consistent filter colours

One filter receives one display colour throughout the selected result.

### Explicit colour conflicts

Filters occurring together cannot accidentally receive the same categorical colour.

## Main disadvantages

### No spatial coverage

The algorithm does not use `s_region`, target-grid cells, new uncovered area, or shared multi-filter coverage.

### No marginal filter value

A group receives full credit for `filterCount` even when all those filters were already selected.

### Whole-group purchase can be expensive

One useful product can force the download of several redundant or very large products.

### Coarse and full products remain together

The flow deliberately retains all group IDs and does not choose the best representation.

### Colours lack wavelength meaning

The display colour is selected for graph separation, not physical wavelength ordering.

### Palette requirement can be large

A ten-filter clique needs ten distinguishable colours, which is different from a three-channel RGB composition.

### Greedy selection is myopic

A locally dense group can consume budget needed by a later combination with better coverage.

### Factorial display permutation

| Hues | Permutations |
|---:|---:|
| 6 | 720 |
| 8 | 40,320 |
| 10 | 3,628,800 |
| 12 | 479,001,600 |

### Adjacency can be over-constrained

Using every qualified group can create conflicts that never occur in accepted groups.

## Complexity

Let:

```text
G = qualified group count
F = selected filter count
E = selected-filter adjacency edges
H = required hue count
```

Then:

```text
Group scoring:       O(G)
Group sorting:       O(G log G)
Budget traversal:    O(G)
Conflict colouring:  O(F + E), with suitable adjacency sets
Hue permutation:     O(H! * F)
```

The permutation stage dominates once `H` becomes moderately large.

## Recommended selection improvement

Replace static total filter count with dynamic marginal utility:

```text
benefit(group) =
    coverageWeight * newCoverageFraction
  + filterWeight * newFilterCount
  + overlapWeight * newMultiChannelCoverage
  + qualityWeight * normalizedQuality

score(group) = benefit(group) / exactGroupSizeMiB
```

Recompute the score after every accepted group:

```python
while candidates:
    scored = [
        (marginal_group_score(group, state), group)
        for group in candidates
        if group.total_bytes <= remaining_budget
    ]
    if not scored or max(score for score, _ in scored) <= 0:
        break

    _, winner = deterministic_max(scored)
    accept_group(winner, state)
    candidates.remove(winner)
```

## Recommended colouring improvement

Build adjacency from accepted groups unless future global compatibility is required.

The factorial permutation can be removed. Calculate the aggregate importance of each hue class:

```text
classWeight[h] =
    sum(groupCount[f] for every filter f assigned hue h)
```

Then:

```python
ordered_classes = sorted(classes, key=lambda h: -class_weight[h])
# DisplayHues is already ordered from most to least preferred.
ordered_colors = display_hues[:len(ordered_classes)]
best_mapping = dict(zip(ordered_classes, ordered_colors))
```

This produces the same result for the diagram's separable popularity objective in `O(H log H)` instead of `O(H!)`.

## Recommended output additions

To compare this algorithm fairly with other Phase 2 options, also report:

```json
{
  "selected_product_count": 0,
  "selected_group_count": 0,
  "selected_size_bytes": 0,
  "selected_filter_count": 0,
  "union_coverage": 0.0,
  "per_channel_coverage": {},
  "shared_channel_coverage": 0.0,
  "runtime_seconds": 0.0,
  "deterministic": true
}
```
