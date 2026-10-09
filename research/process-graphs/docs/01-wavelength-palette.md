# Wavelength palette

Source: [`../01-wavelength-palette.mmd`](../01-wavelength-palette.mmd)

## Purpose

The wavelength-palette algorithm creates observation groups with usable blue, green, and red wavelength channels, then purchases those groups in a deterministic order while respecting a download budget.

It is primarily a channel-assignment policy combined with a simple group selector. It does not optimize spatial coverage.

## Inputs

- Qualified Phase 1 group rows
- Parsed representative IDs and filter tokens
- `WavelengthTable` in nanometres
- `BlueMaxNm`, default 500
- `GreenMaxNm`, default 650
- Ordered `DisplayHues`
- `primaryChannelCount`, default 3
- `PreferredTriple`, shown as F435W, F555W, and F814W
- `budgetBytes`

## Flow

### 1. Assign every known filter to a channel

```text
wavelength < 500 nm       -> blue
500 <= wavelength < 650   -> green
wavelength >= 650 nm      -> red
```

An unknown wavelength produces `UNASSIGNED`.

### 2. Validate representative IDs

Every token of an ID must have a channel. If one token is unassigned, the entire ID is dropped. Otherwise, `channelsOf` is the set of channels represented by its tokens. A multi-token ID may contain more than one channel.

### 3. Choose one winner per group and channel

For each group and channel, candidates are representative IDs containing that channel. Candidate preference is based on the global `groupCount` of the relevant filter. The most common filter wins; alphabetical observation ID breaks ties.

The channel winners are collected into `keptIDs`. If one multi-token ID wins two channels, it is stored once.

### 4. Require sufficient channels

`distinctChannelCount` counts blue, green, and red channels with winners. With the default `primaryChannelCount = 3`, all three must be present or the group is closed.

### 5. Estimate cost

```text
estimatedCost = averageFileBytes * number of kept IDs
```

This is an estimate because the CSV does not retain exact per-ID sizes.

### 6. Detect the preferred triple

`canonicalHit` is one when the retained tokens include F435W, F555W, and F814W. It is otherwise zero.

### 7. Rank openable groups

Groups are sorted by:

1. Canonical hit descending
2. Distinct channel count descending
3. Estimated cost ascending
4. Observation-group name ascending

### 8. Apply the budget

The sorted groups are visited once. A group is accepted if its estimated cost fits the remaining budget; otherwise it is skipped and later groups are still considered.

## Implementation by diagram node

### Map every filter to blue, green, red, or unassigned

```python
def channel_for(filter_name, wavelength_table, blue_max=500, green_max=650):
    wavelength = wavelength_table.get(filter_name)
    if wavelength is None:
        return None
    if wavelength < blue_max:
        return "blue"
    if wavelength < green_max:
        return "green"
    return "red"

channel_of = {name: channel_for(name, wavelength_table) for name in all_filters}
channel_color = dict(zip(("blue", "green", "red"), display_hues[:3]))
```

### Drop IDs containing an unassigned token

```python
channels_of = {}
for obs_id in group["representative_ids"]:
    tokens = group["tokens_by_id"][obs_id]
    if any(channel_of[token] is None for token in tokens):
        continue
    channels_of[obs_id] = {channel_of[token] for token in tokens}
```

One unknown wavelength rejects the whole ID at this gate.

### Find candidates and select one winner per channel

```python
def score_for_channel(obs_id, channel):
    tokens = [
        token for token in group["tokens_by_id"][obs_id]
        if channel_of[token] == channel
    ]
    return max(group_count[token] for token in tokens)

winners = {}
for channel in ("blue", "green", "red"):
    candidates = [
        obs_id for obs_id, channels in channels_of.items()
        if channel in channels
    ]
    winners[channel] = min(
        candidates,
        key=lambda obs_id: (-score_for_channel(obs_id, channel), obs_id),
        default=None,
    )
```

An empty candidate list leaves that channel empty. `min` implements largest score followed by alphabetically smallest ID.

### Deduplicate winners and test channel completeness

```python
kept_ids = {winner for winner in winners.values() if winner is not None}
distinct_channel_count = sum(winner is not None for winner in winners.values())
openable = distinct_channel_count >= primary_channel_count
```

One dual-token product may win two channels but appears once in `kept_ids`.

### Estimate the purchase cost

```python
estimated_cost = group["average_file_bytes"] * len(kept_ids)
```

The flow intentionally uses the group average; an exact implementation should sum selected product sizes.

### Detect the preferred triple

```python
kept_tokens = {
    token
    for obs_id in kept_ids
    for token in group["tokens_by_id"][obs_id]
}
canonical_hit = int(preferred_triple <= kept_tokens)
```

### Sort openable rows

```python
openable_groups.sort(
    key=lambda candidate: (
        -candidate["canonical_hit"],
        -candidate["distinct_channel_count"],
        candidate["estimated_cost"],
        candidate["observation_group"],
    )
)
```

### Traverse the ranking under the budget

```python
spent = 0
accepted = []
for candidate in openable_groups:
    if spent + candidate["estimated_cost"] > budget_bytes:
        continue
    accepted.append(candidate)
    spent += candidate["estimated_cost"]
```

Skipping an oversized row does not stop the loop; a smaller later row may still fit.

## Output

- Accepted observation IDs
- Estimated bytes spent
- Filter-to-blue/green/red assignment
- Display colour associated with each channel

## Advantages

- Easy to explain and deterministic.
- Same filter retains the same channel across groups.
- Wavelength ordering gives colours physical meaning.
- Produces groups ready for a three-channel composition.
- Computationally inexpensive.

## Limitations

- Does not use `s_region` or measure common RGB coverage.
- Uses average rather than exact product sizes.
- Popularity is preferred over image quality and new coverage.
- An unknown token removes the whole product.
- A multi-filter product can satisfy multiple channels while remaining one image.
- The preferred optical triple biases results toward a particular HST-style composition.
- It can combine missions and instruments without first checking whether that is desirable.

## Complexity

With three fixed channels, candidate collection and ranking are approximately `O(P + G log G)`, where `P` is representative products and `G` is qualified groups.

## Recommended implementation changes

Use exact products from the Phase 1 JSON. Select channel representatives by marginal channel coverage, exact size, and quality rather than popularity and alphabetical order. Make the preferred triple an optional user policy. Require measurable overlap among the selected blue, green, and red footprints.

## Worked example

Consider a qualified group containing:

| Product | Wavelength | Channel | Global group count | Exact size |
|---|---:|---|---:|---:|
| F435W product | 435 nm | Blue | 18 | 28 MiB |
| F438W product | 438 nm | Blue | 5 | 25 MiB |
| F555W product | 555 nm | Green | 29 | 28 MiB |
| F814W product | 814 nm | Red | 25 | 28 MiB |

The blue candidates are F435W and F438W. F435W wins because its `groupCount` is larger, even though F438W is smaller. F555W wins green and F814W wins red.

The group has all three channels:

```text
keptIDs = {F435W product, F555W product, F814W product}
distinctChannelCount = 3
canonicalHit = 1
```

If the CSV average is 27 MiB, the diagram estimates:

```text
estimatedCost = 27 MiB * 3 = 81 MiB
```

### Multi-token example

An ID containing `F405N-F770W` maps to both blue and red. If it wins both channels, it is downloaded once, but the implementation must decide whether one combined artifact really supplies two independently colourable image planes.

## Reference pseudocode

```python
for filter_name in all_filters:
    wavelength = wavelength_table.get(filter_name)
    channel_of[filter_name] = classify_rgb(wavelength) if wavelength else None

openable = []
for group in qualified_groups:
    candidates = valid_representative_ids(group, channel_of)
    winners = {}
    for channel in ("blue", "green", "red"):
        winners[channel] = max(
            ids_containing_channel(candidates, channel),
            key=lambda item: (channel_score(item), reverse_alpha(item.id)),
            default=None,
        )

    if count_non_null(winners) >= primary_channel_count:
        kept = set(winners.values())
        openable.append((group, kept, average_bytes(group) * len(kept)))

for candidate in sorted(openable, key=palette_rank):
    if spent + candidate.cost <= budget_bytes:
        accept(candidate)
```

## Conceptual output

```json
{
  "accepted_groups": [
    {
      "group": "hst_9733_01_acs_hrc",
      "kept_ids": ["..._f435w", "..._f555w", "..._f814w"],
      "channels": {
        "F435W": "blue",
        "F555W": "green",
        "F814W": "red"
      },
      "estimated_cost_bytes": 87462720,
      "canonical_hit": true
    }
  ],
  "spent_bytes": 87462720
}
```

## Compact flow

```text
Qualified groups
  -> look up filter wavelengths
  -> map filters to blue/green/red
  -> drop IDs with unknown filters
  -> choose popular winner per group/channel
  -> require three represented channels
  -> estimate group cost
  -> prefer canonical optical triple
  -> buy ranked groups within budget
  -> return IDs and channel colours
```

## Improved scoring formula

Replace popularity-only winner selection with:

```text
winnerScore(product, channel) =
    coverageWeight * newChannelCoverage
  + overlapWeight * newThreeChannelOverlap
  + qualityWeight * normalizedImageQuality
  - sizeWeight * exactSizeMiB
```

At group level:

```text
groupDensity =
    (sharedRGBGain + spectralDiversityGain)
    / exactSelectedBytesMiB
```
