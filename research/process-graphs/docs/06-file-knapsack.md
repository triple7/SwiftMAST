# File knapsack

Source: [`../06-file-knapsack.mmd`](../06-file-knapsack.mmd)

## Purpose

The file-knapsack algorithm incrementally purchases individual representative products. A product's value is the number of new wavelength channels it contributes to its group, plus a bonus when it completes the configured primary-channel requirement.

## Inputs

- Qualified groups and representative IDs
- Wavelength bins from option 05
- Estimated `averageFileBytes` and row `maxBytes`
- `primaryChannelCount`, default 3
- `completionBonus`, default 3
- `budgetBytes`

## Flow

### 1. Build product items

Every token of a representative ID must have a wavelength bin. Otherwise the ID is dropped. A valid item contains its group, ID, represented channel set, and estimated price equal to its row's `averageFileBytes`.

### 2. Track group state

The algorithm maintains:

- `spent`
- `purchased` IDs
- `heldChannels` for every group

### 3. Calculate marginal value

For an unpurchased item:

```text
added = item.channels - heldChannels[group]
base value = number of added channels
```

If adding the item moves the group from fewer than `primaryChannelCount` channels to at least that threshold, `completionBonus` is added. Items adding no new channel have zero value.

### 4. Check budget guards

The estimated price must fit the remaining budget. The row's `maxBytes` must also fit as a conservative guard because the exact selected-file size is unknown.

### 5. Choose the next item

Eligible items are ranked by:

1. `value / estimatedPrice` descending
2. Value descending
3. Observation ID ascending
4. Observation-group name ascending

The winner is purchased, spending and held channels are updated, and all marginal values are recomputed. The loop stops when no positive-value item fits.

## Implementation by diagram node

### Convert valid representative IDs into items

```python
items = []
for group in qualified_groups:
    for obs_id in group["representative_ids"]:
        tokens = group["tokens_by_id"][obs_id]
        if any(bin_of[token] is None for token in tokens):
            continue
        channels = {bin_of[token] for token in tokens}
        items.append({
            "group": group["group"],
            "observation_id": obs_id,
            "channels": channels,
            "estimated_price": group["average_file_bytes"],
            "max_bytes": group["max_bytes"],
        })
```

Every item from the same row receives the same estimated price.

### Initialize changing selection state

```python
from collections import defaultdict

spent = 0
purchased = set()
held_channels = defaultdict(set)
```

### Recalculate one item's marginal value

```python
def marginal_value(item):
    held = held_channels[item["group"]]
    added = item["channels"] - held
    if not added:
        return 0

    before = len(held)
    after = len(held | item["channels"])
    completes = before < primary_channel_count <= after
    return len(added) + (completion_bonus if completes else 0)
```

The value changes after every purchase in the same group, which is why it cannot be permanently precomputed.

### Reject zero-value or unaffordable items

```python
def candidate_tuple(item):
    value = marginal_value(item)
    price = item["estimated_price"]
    if value <= 0:
        return None
    if spent + price > budget_bytes:
        return None
    if spent + item["max_bytes"] > budget_bytes:
        return None
    return (value / price, value, item)
```

The `max_bytes` check is a conservative guard; it is not an exact cost for this item.

### Pick the best item and update only its group

```python
while True:
    candidates = [
        result
        for item in items
        if item["observation_id"] not in purchased
        if (result := candidate_tuple(item)) is not None
    ]
    if not candidates:
        break

    ratio, value, winner = min(
        candidates,
        key=lambda entry: (
            -entry[0],
            -entry[1],
            entry[2]["observation_id"],
            entry[2]["group"],
        ),
    )
    purchased.add(winner["observation_id"])
    spent += winner["estimated_price"]
    held_channels[winner["group"]].update(winner["channels"])
```

After the update, products in other groups retain their previous marginal values; only products in the winning group need recomputation in an optimized implementation.

## Output

- Purchased representative IDs
- Estimated bytes spent
- Channel set accumulated by each group
- Filter/channel assignment inherited from the bins

## Advantages

- Selects individual products rather than forcing complete-group purchase.
- Dynamically values new channels instead of static total filter count.
- Completion bonus encourages composable groups.
- Lightweight, deterministic, and easier to audit than solver models.
- Natural starting point for later local search.

## Limitations

- Estimated spending is not guaranteed to equal actual bytes.
- `maxBytes` per-item checks do not prove the final actual total is within budget.
- Ignores footprints and spatial overlap.
- Can leave groups partially filled.
- Greedy choices can block a better global combination.
- A multi-token item may add several channels although it remains one image artifact.
- No product-count or quality constraint is shown.

## Complexity

A direct implementation recomputes all remaining item values after each purchase, giving approximately `O(P^2)` time. Indexing items by group and newly affected channels can reduce recomputation.

## Recommended implementation changes

Use exact `contentlength` for each product and remove the average/max approximation. Add marginal footprint coverage per channel and a hard rule or penalty for incomplete groups. Include maximum product count and product quality. Keep the greedy result as a fast baseline or initializer for option 10.

## Worked example

Assume one group currently holds only the blue channel and has these remaining products:

| Product | Channels | Estimated size | Newly added channels | Completion bonus | Value | Value/MiB |
|---|---|---:|---:|---:|---:|---:|
| A | Green | 20 MiB | 1 | 0 | 1 | 0.050 |
| B | Red | 25 MiB | 1 | 0 | 1 | 0.040 |
| C | Green, Red | 60 MiB | 2 | 3 | 5 | 0.083 |

With `primaryChannelCount = 3`, product C completes the group in one purchase. Its completion bonus makes it the winner despite being the largest file.

After C is selected, A and B add no new channels and their value becomes zero.

## Reference pseudocode

```python
spent = 0
purchased = set()
held_channels = defaultdict(set)

while True:
    candidates = []
    for item in items - purchased:
        added = item.channels - held_channels[item.group]
        if not added:
            continue

        before = len(held_channels[item.group])
        after = len(held_channels[item.group] | item.channels)
        bonus = completion_bonus if before < required <= after else 0
        value = len(added) + bonus

        if exact_or_estimated_fit(item, spent, budget_bytes):
            candidates.append((value / item.price, value, item))

    if not candidates:
        break
    winner = deterministic_max(candidates)
    purchase(winner.item)
```

## Conceptual output

```json
{
  "purchased": [
    {"group": "G1", "observation_id": "product-c", "channels": ["green", "red"]}
  ],
  "held_channels": {"G1": ["blue", "green", "red"]},
  "estimated_spent_bytes": 62914560,
  "completed_group_count": 1,
  "stop_reason": "no_positive_value_item_fits"
}
```

## Compact flow

```text
Representative products
  -> assign wavelength channels
  -> create one item per product
  -> calculate channels newly added to its group
  -> add completion bonus when threshold is crossed
  -> reject items outside remaining budget
  -> pick highest value per byte
  -> update group channels and recompute values
  -> stop when no positive item fits
```

## Improved marginal-value formula

```text
value(product) =
    channelWeight * newChannelCount
  + completionWeight * completesRequiredChannels
  + coverageWeight * newCoverageInProductChannels
  + overlapWeight * newSharedChannelCoverage
  + qualityWeight * normalizedQuality

density(product) = value(product) / exactSizeMiB
```

Hard constraints should independently enforce `spent + exactBytes <= budgetBytes` and `selectedCount < maxProducts`.
