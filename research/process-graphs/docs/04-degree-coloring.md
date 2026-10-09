# Degree colouring

Source: [`../04-degree-coloring.mmd`](../04-degree-coloring.mmd)

## Purpose

Degree colouring assigns categorical display colours to filters so that filters occurring in the same qualified group never share a colour. It does not select or download products.

## Inputs

- All qualified groups
- All parsed filters
- Filter adjacency graph
- Global `groupCount` per filter
- Ordered `DisplayHues`

No download budget or footprint metadata is used.

## Flow

### 1. Build the conflict graph

Each filter is a node. Two filters are adjacent when a qualified group contains both. A group of `K` filters creates a `K`-node clique, whose members must all have different colours.

### 2. Order nodes

Filters are sorted by degree descending, group count descending, and name ascending. Highly constrained and common filters are coloured first.

### 3. Greedy graph colouring

For each filter, hue indexes already assigned to coloured neighbours are forbidden. The smallest available non-negative index is assigned. Non-adjacent filters may reuse the same hue.

### 4. Count required hues

`hueCount` is one plus the largest index. Because the sample has a ten-filter clique, at least ten colours are necessary for a strict categorical colouring of the full graph. Greedy order may require even more than the graph's minimum chromatic number.

### 5. Validate the palette

If `DisplayHues` contains fewer than `hueCount` colours, the flow stops and reports the shortfall instead of inventing colours.

### 6. Give preferred colours to important classes

Every permutation of hue classes onto display indexes is evaluated. The score weights display salience by `groupCount`. The best mapping gives prominent colours to classes containing frequently occurring filters.

## Implementation by diagram node

### Connect every pair of co-occurring filters

```python
from collections import Counter, defaultdict
from itertools import combinations

adjacent = defaultdict(set)
group_count = Counter()

for group in qualified_groups:
    filters = sorted(group["filters"])
    group_count.update(filters)
    for left, right in combinations(filters, 2):
        adjacent[left].add(right)
        adjacent[right].add(left)
```

Each group creates a clique because every pair in that group is a colour conflict.

### Calculate degree and choose visit order

```python
degree = {name: len(adjacent[name]) for name in all_filters}
color_order = sorted(
    all_filters,
    key=lambda name: (-degree[name], -group_count[name], name),
)
```

The most constrained filters are visited first; frequency and name make ties deterministic.

### Assign the smallest non-conflicting hue

```python
hue_index = {}
for filter_name in color_order:
    forbidden = {
        hue_index[neighbor]
        for neighbor in adjacent[filter_name]
        if neighbor in hue_index
    }
    candidate = 0
    while candidate in forbidden:
        candidate += 1
    hue_index[filter_name] = candidate
```

Non-adjacent filters can reuse a hue because they never occur together in a qualified row.

### Count hues and validate palette capacity

```python
hue_count = 1 + max(hue_index.values(), default=-1)
if len(display_hues) < hue_count:
    result = {
        "status": "insufficient_display_hues",
        "required": hue_count,
        "available": len(display_hues),
        "shortfall": hue_count - len(display_hues),
    }
```

The ten-filter clique in the example proves that fewer than ten strict categorical colours cannot work.

### Score every hue-to-display permutation

```python
from itertools import permutations

def salience(display_index):
    return len(display_hues) - display_index

def mapping_score(mapping):
    return sum(
        group_count[name] * salience(mapping[hue_index[name]])
        for name in all_filters
    )

best_mapping = min(
    permutations(range(hue_count)),
    key=lambda mapping: (-mapping_score(mapping), mapping),
)
```

The lexicographically smallest mapping wins equal scores.

### Paint every filter

```python
display_color = {
    name: display_hues[best_mapping[hue_index[name]]]
    for name in all_filters
}
```

This output is a colour legend only. It does not select or buy a product.

## Output

- Abstract hue index for every filter
- Final display colour for every filter
- Required hue count or palette shortfall

It produces no accepted product list.

## Advantages

- Makes colour conflicts explicit.
- Guarantees adjacent filters differ under the produced greedy colouring.
- Same filter has the same display colour throughout the dataset.
- Separates reusable colour classes from specific RGB semantics.
- Deterministic.

## Limitations

- It is not a Phase 2 selection algorithm by itself.
- Uses conflicts from all qualified groups, including groups that may never be selected.
- Greedy colouring is not guaranteed to minimize the number of colours.
- Ten or more categorical colours can be difficult to distinguish visually.
- Exhaustive permutation is factorial.
- Display hue is not the same as a scientific RGB channel.

## Complexity

Graph construction is approximately `O(G * K^2)`. Greedy colouring is `O(F + E)` with suitable sets. Palette permutation is `O(H! * F)` and dominates at larger hue counts.

## Recommended implementation changes

Run colouring after product selection so only actual conflicts remain. Decide whether the output represents categorical overlay colours or physical composition channels. Replace exhaustive permutation with a weighted assignment: calculate each hue class's aggregate importance, sort classes by weight, and map them to display colours ordered by salience.

## Worked example

Suppose the selected groups are:

```text
G1 = {F435W, F555W, F814W}
G2 = {F555W, F606W, F814W}
```

The adjacency lists are:

| Filter | Adjacent filters | Degree |
|---|---|---:|
| F435W | F555W, F814W | 2 |
| F555W | F435W, F606W, F814W | 3 |
| F606W | F555W, F814W | 2 |
| F814W | F435W, F555W, F606W | 3 |

If F555W is visited first it gets hue 0. F814W is adjacent and gets hue 1. F435W is adjacent to both and gets hue 2. F606W is adjacent to hue 0 and hue 1 but not F435W, so it can reuse hue 2.

## Reference pseudocode

```python
adjacent = defaultdict(set)
for group in groups:
    for left, right in combinations(group.filters, 2):
        adjacent[left].add(right)
        adjacent[right].add(left)

order = sorted(
    all_filters,
    key=lambda f: (-len(adjacent[f]), -group_count[f], f),
)

hue = {}
for filter_name in order:
    forbidden = {hue[n] for n in adjacent[filter_name] if n in hue}
    hue[filter_name] = smallest_non_negative_not_in(forbidden)
```

## Conceptual output

```json
{
  "hue_count": 3,
  "filters": {
    "F555W": {"hue_index": 0, "display_color": "#0072B2"},
    "F814W": {"hue_index": 1, "display_color": "#D55E00"},
    "F435W": {"hue_index": 2, "display_color": "#009E73"},
    "F606W": {"hue_index": 2, "display_color": "#009E73"}
  },
  "palette_shortfall": 0
}
```

## Compact flow

```text
Qualified or selected groups
  -> connect filters that occur together
  -> calculate node degree and popularity
  -> visit most constrained filters first
  -> assign smallest non-conflicting hue
  -> calculate required hue count
  -> verify display palette
  -> give preferred colours to important hue classes
```

## Improved colour-class mapping

The diagram's permutation objective can be solved without enumerating `H!` mappings. First calculate:

```text
classWeight[h] = sum(groupCount[f] for f where hueIndex[f] == h)
```

Then sort hue classes by `classWeight` descending and display colours by salience descending. Pair them in order. If additional compatibility costs exist, use a polynomial assignment algorithm such as the Hungarian algorithm.
