# RGB triple vote

Source: [`../03-rgb-triple-vote.mmd`](../03-rgb-triple-vote.mmd)

## Purpose

The RGB-triple-vote algorithm finds one globally well-supported set of three filters, maps it to blue, green, and red by wavelength, and purchases observation groups that can supply the full triple. If six display hues are available, it may repeat the process for a second disjoint triple.

## Inputs

- Qualified groups and representative IDs
- Parsed filter tokens and global group counts
- `WavelengthTable`
- Ordered `DisplayHues`
- `budgetBytes`

## Flow

### 1. Build candidate filters

Filters missing from `WavelengthTable` are excluded because a three-filter set cannot be ordered by wavelength without that information.

### 2. Enumerate triples

Every unordered three-filter subset is generated. With 33 filters, this is `C(33,3) = 5,456` triples.

### 3. Score each triple

For triple `T`, `supportingRows` are qualified groups containing all three members. The primary score is `supportCount`. A secondary `cheapness` score sums `1 / totalBytes` over supporting rows. Alphabetical triple order breaks remaining ties.

### 4. Assign RGB colours

The winning triple is sorted by wavelength. Shortest becomes blue, middle becomes green, and longest becomes red through the first three `DisplayHues` indexes.

### 5. Open compatible groups

For each winning filter, the alphabetically first representative ID containing it is chosen. A group is openable only when all three filters have chosen IDs. Duplicate IDs are removed when one multi-token product covers multiple triple members.

### 6. Estimate cost and apply budget

```text
estimatedCost = averageFileBytes * number of distinct kept IDs
```

Openable groups are sorted by estimated cost and name, then purchased greedily while they fit.

### 7. Optional second triple

If six display hues exist, purchased rows are removed, filters from idle rows are considered, and the triple search is repeated using display indexes 3, 4, and 5. Spending continues from the first pass.

## Implementation by diagram node

### Keep only filters with known wavelengths

```python
candidate_filters = sorted(
    name for name in all_filters
    if wavelength_table.get(name) is not None
)
excluded_filters = sorted(all_filters - set(candidate_filters))
```

An excluded filter cannot be ordered reliably onto blue, green, and red.

### Enumerate every unordered triple

```python
from itertools import combinations

triples = list(combinations(candidate_filters, 3))
```

For 33 wavelength-known filters, this creates `33 choose 3 = 5,456` candidates. The tuple is already alphabetically ordered because `candidate_filters` was sorted.

### Find supporting rows and calculate both votes

```python
def triple_metrics(triple, rows):
    required = set(triple)
    supporting = [row for row in rows if required <= row["filters"]]
    support_count = len(supporting)
    cheapness = sum(1 / row["total_bytes"] for row in supporting)
    return supporting, support_count, cheapness

evaluated = []
for triple in triples:
    supporting, support_count, cheapness = triple_metrics(triple, qualified_rows)
    evaluated.append((triple, supporting, support_count, cheapness))
```

`cheapness` is a tie-break score, not the byte cost of purchasing the rows.

### Choose the winning triple deterministically

```python
best_triple, supporting_rows, support_count, cheapness = min(
    evaluated,
    key=lambda item: (-item[2], -item[3], item[0]),
)
```

This implements maximum support, then maximum cheapness, then alphabetically first triple.

### Order the triple by wavelength and assign display hues

```python
ordered_triple = sorted(best_triple, key=lambda name: wavelength_table[name])
display_color = {
    filter_name: display_hues[index]
    for index, filter_name in enumerate(ordered_triple)
}
```

The shortest wavelength uses index 0, the middle index 1, and the longest index 2.

### Choose one product for each triple member

```python
def chosen_ids_for_row(row, triple):
    chosen = {}
    for filter_name in triple:
        matching = sorted(
            obs_id for obs_id in row["representative_ids"]
            if filter_name in row["tokens_by_id"][obs_id]
        )
        chosen[filter_name] = matching[0] if matching else None
    return chosen

chosen = chosen_ids_for_row(row, best_triple)
openable = all(chosen.values())
```

A missing member closes the row. Product choice is alphabetical, not based on footprint or size.

### Deduplicate products and estimate group cost

```python
kept_ids = set(chosen.values())
estimated_cost = row["average_file_bytes"] * len(kept_ids)
```

One dual-token product can cover two members and is charged once.

### Sort openable rows and apply the remaining budget

```python
openable_rows.sort(key=lambda item: (item["estimated_cost"], item["group"]))

for candidate in openable_rows:
    if spent + candidate["estimated_cost"] > budget_bytes:
        continue
    accepted.append(candidate)
    spent += candidate["estimated_cost"]
```

### Decide whether to run a second triple

```python
if len(display_hues) < 6:
    second_pass = None
else:
    bought_groups = {item["group"] for item in accepted}
    idle_rows = [row for row in qualified_rows if row["group"] not in bought_groups]
    idle_filters = {
        name for row in idle_rows for name in row["filters"]
        if name not in best_triple and name in wavelength_table
    }
    second_pass = select_triple(
        rows=idle_rows,
        filters=idle_filters,
        display_hues=display_hues[3:6],
        initial_spent=spent,
    )
```

The second pass is disjoint from the first triple and continues using the already-spent budget.

## Output

- One or two selected filter triples
- RGB/display hue assignment
- Accepted group IDs and representative IDs
- Estimated total bytes spent

## Advantages

- Ensures consistent filter meaning across many groups.
- Produces an understandable RGB composition.
- Triple enumeration is practical for 33 filters.
- Deterministic scoring and tie-breaking.
- Strongly favours combinations available across a broad set of observations.

## Limitations

- Support frequency is not spatial coverage.
- Groups lacking the global winning triple are discarded.
- Alphabetical file choice ignores size, footprint, and quality.
- Uses estimated file sizes.
- Rare but scientifically valuable filters are disadvantaged.
- A combined product may stand in for more than one independent channel.
- A single triple may not be appropriate across different missions or instruments.
- The cheapness sum is not the actual cost of purchasing all supporting rows.

## Complexity

Triple generation is `O(F^3)`. A direct support scan is approximately `O(F^3 * G)`, although filter-set indexes can reduce it. For the sample size, this remains manageable.

## Recommended implementation changes

Run triple selection per mission or instrument, or make that scope explicit. Score triples by shared three-channel footprint coverage and exact bytes rather than support alone. Choose exact products using size, quality, and coverage. Treat a multi-filter artifact explicitly instead of automatically counting it as independent image planes.

## Worked example

Assume five wavelength-known filters and four qualified groups:

| Group | Filters | Total size |
|---|---|---:|
| G1 | F435W, F555W, F814W | 90 MiB |
| G2 | F435W, F555W, F814W, F606W | 120 MiB |
| G3 | F435W, F606W, F814W | 80 MiB |
| G4 | F555W, F606W, F814W | 70 MiB |

Candidate triple `{F435W,F555W,F814W}` has support count 2. `{F435W,F606W,F814W}` has support count 2. Their cheapness values are:

```text
Triple 1: 1/90 + 1/120
Triple 2: 1/120 + 1/80
```

Triple 2 wins the secondary cheapness comparison. Its wavelength order becomes blue F435W, green F606W, and red F814W. Only G2 and G3 are openable for that triple.

## Reference pseudocode

```python
candidate_filters = sorted(
    filter_name for filter_name in all_filters
    if filter_name in wavelength_table
)

for triple in combinations(candidate_filters, 3):
    supporting = [g for g in groups if set(triple) <= g.filters]
    score = (
        len(supporting),
        sum(1 / g.total_bytes for g in supporting),
        tuple(sorted(triple)),
    )
    remember_best(score, triple)

rgb = sorted(best_triple, key=wavelength_table.get)
for group in groups_supporting(best_triple):
    chosen = alphabetically_first_id_per_filter(group, best_triple)
    if all(chosen):
        cost = average_bytes(group) * len(set(chosen))
        add_openable(group, chosen, cost)
```

## Conceptual output

```json
{
  "primary_triple": ["F435W", "F606W", "F814W"],
  "channel_assignment": {
    "F435W": "blue",
    "F606W": "green",
    "F814W": "red"
  },
  "support_count": 2,
  "accepted_groups": [
    {"group": "G3", "kept_ids": ["g3_f435w", "g3_f606w", "g3_f814w"]}
  ],
  "estimated_spent_bytes": 83886080
}
```

## Compact flow

```text
Known-wavelength filters
  -> enumerate all triples
  -> count groups containing each triple
  -> break ties by cheapness and name
  -> order winning triple by wavelength
  -> find one ID per filter in each group
  -> retain groups containing the full triple
  -> buy cheapest groups within budget
  -> optionally repeat for a second trio
```

## Improved triple score

Support should be supplemented by spatial and cost value:

```text
tripleScore =
    overlapWeight * sharedCoverage(triple)
  + supportWeight * normalizedSupportCount
  + qualityWeight * normalizedQuality
  - sizeWeight * exactRequiredBytesMiB
```

`sharedCoverage(triple)` should measure grid cells covered by all three triple members, not the union of their footprints.
