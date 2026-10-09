# Integer linear program

Source: [`../08-integer-linear-program.mmd`](../08-integer-linear-program.mmd)

## Purpose

The ILP option jointly selects products, assigns filters to channels, and opens observation groups using binary variables. It solves three lexicographic objectives: open the most groups, colour the most filters, then minimize estimated bytes.

## Inputs

- Qualified groups and representative IDs
- Filter tokens
- Estimated `averageFileBytes`
- `channelCount`, default 3
- `primaryChannelCount`, default 3
- `minimumGroupsPerChannel`, default 1
- `budgetBytes`

## Variables

- Binary `include[group, id]`
- Binary `assign[filter, channel]`
- Binary `link[group, id, token, channel]`
- Binary `opened[group]`
- Binary `usesChannel[group, channel]`

## Constraint flow

### 1. Apply filter/channel rules

Each filter receives at most one channel. Included product tokens must be assigned. Link variables represent inclusion combined with channel assignment. Within a group, at most one linked token occupies a channel.

### 2. Define an opened group

The model requires at least `primaryChannelCount` included IDs when `opened = 1`. Upper bounds prevent IDs from being included when the group is closed.

This counts IDs, not distinct channels; three selected IDs do not by themselves prove three-channel completeness.

### 3. Track channel use

`usesChannel` becomes one when at least one link uses that channel in a group.

### 4. Require global channel support

For each channel, at least `minimumGroupsPerChannel` groups must use it. This is a dataset-level floor, not a rule that every opened group uses every primary channel.

### 5. Apply the budget

Estimated included bytes must not exceed `budgetBytes`.

## Optimization flow

### 6. Feasibility check

If no binary solution satisfies all constraints, the algorithm reports infeasible without weakening the floor.

### 7. Lexicographic solve

1. Maximize the number of opened groups and freeze that optimum.
2. Maximize the number of filter assignments and freeze that optimum.
3. Minimize estimated included bytes.

PuLP with CBC is suggested as an implementation route.

## Implementation by diagram node

### Create binary variables

```python
include = model.binary_vars(products)
assign = model.binary_vars((f, c) for f in filters for c in channels)
link = model.binary_vars(
    (p, token, c)
    for p in products for token in tokens_of[p] for c in channels
)
opened = model.binary_vars(groups)
uses_channel = model.binary_vars((g, c) for g in groups for c in channels)
```

Unlike option 07, every value is exactly zero or one.

### Add the common assignment and link rules

```python
for filter_name in filters:
    model.add(sum(assign[filter_name, c] for c in channels) <= 1)

for product in products:
    for token in tokens_of[product]:
        model.add(include[product] <= sum(assign[token, c] for c in channels))
        for channel in channels:
            z = link[product, token, channel]
            model.add(z <= include[product])
            model.add(z <= assign[token, channel])
            model.add(z >= include[product] + assign[token, channel] - 1)
```

The group/channel sum from option 07 is also applied to prevent collisions.

### Define when a group is opened

```python
for group in groups:
    selected_count = sum(include[p] for p in products_by_group[group])
    capacity = len(products_by_group[group])
    model.add(selected_count >= primary_channel_count * opened[group])
    model.add(selected_count <= capacity * opened[group])
    model.add(opened[group] <= selected_count)
```

This is the diagram's rule. It requires a count of IDs, not proof of distinct channels, which is why the correction later in this document is important.

### Derive `usesChannel` from active links

```python
for group in groups:
    for channel in channels:
        links = [
            link[p, token, channel]
            for p in products_by_group[group]
            for token in tokens_of[p]
        ]
        for active_link in links:
            model.add(uses_channel[group, channel] >= active_link)
        model.add(uses_channel[group, channel] <= sum(links))
```

### Enforce the global minimum group count per channel

```python
for channel in channels:
    model.add(
        sum(uses_channel[group, channel] for group in groups)
        >= minimum_groups_per_channel
    )
```

This is a global floor. It does not mean that every opened group uses every channel.

### Apply the estimated budget

```python
estimated_bytes = sum(
    include[p] * average_file_bytes[group_of[p]]
    for p in products
)
model.add(estimated_bytes <= budget_bytes)
```

### Check feasibility without silently weakening constraints

```python
status = model.solve_feasibility()
if status == "infeasible":
    return {"status": "infeasible", "constraints_relaxed": []}
```

### Solve the three objectives lexicographically

```python
opened_total = sum(opened.values())
model.maximize(opened_total)
model.solve()
best_opened = model.value(opened_total)
model.add(opened_total == best_opened)

colored_total = sum(assign.values())
model.maximize(colored_total)
model.solve()
best_colored = model.value(colored_total)
model.add(colored_total == best_colored)

model.minimize(estimated_bytes)
final_status = model.solve()
```

Freezing each previous optimum prevents a later objective from trading it away.

## Output

- Selected IDs through `include`
- Global filter/channel assignment
- Opened groups
- Group/channel usage
- Minimized estimated byte total

## Advantages

- Produces an exact optimum for the written discrete model.
- Hard constraints are explicit and auditable.
- Lexicographic goals avoid arbitrary weighted-sum tuning.
- Can guarantee budget and logical requirements when costs are exact.
- Provides a strong benchmark for greedy approaches.

## Limitations and model gaps

- Opened groups require three IDs, not three distinct channels.
- A channel need only appear in some groups, not every opened group.
- `assign` is not clearly bounded by selection of a product containing that filter. The second objective could colour unused filters.
- Maximizing opened groups before coverage can favour many small, spatially redundant groups.
- No footprint or coverage variable exists.
- Costs are estimated averages.
- Binary models can become expensive as products, filters, and coverage cells grow.
- Equivalent optima may require additional tie-break rules for reproducibility.

## Complexity

ILP is NP-hard in general. The sample model is small enough to test, but adding product-level footprints or thousands of grid-cell variables can grow it substantially.

## Recommended implementation changes

Tie every assignment to at least one selected product containing that filter. Require distinct channel use per opened group, for example through `usesChannel`. Use exact product bytes. Add a coverage objective or precomputed candidate coverage benefits. Consider maximizing shared primary-channel coverage before group count.

## Worked example

Assume one group contains four products:

| Product | Filter | Channel candidate | Size |
|---|---|---:|---:|
| P1 | F435W | 0 | 20 MiB |
| P2 | F555W | 1 | 20 MiB |
| P3 | F814W | 2 | 20 MiB |
| P4 | F606W | 1 | 10 MiB |

With three required primary channels and a 65 MiB budget, the intended solution is P1, P2, and P3 for 60 MiB. P4 is cheaper but duplicates channel 1 and cannot replace the red channel.

The diagram's original opened constraint alone permits three IDs without proving channel diversity. For example, three products assigned across only channels 0 and 1 could still satisfy `sum(include) >= 3 * opened`.

## Corrected key constraints

Tie filter assignment to selected products:

```text
assign[f,c] <= sum(include[p] for p containing f)
```

Require every opened group to use the primary channels:

```text
usesChannel[g,c] >= opened[g]
for every primary channel c
```

Or, when any three distinct channels are acceptable:

```text
sum(usesChannel[g,c] for c) >= primaryChannelCount * opened[g]
```

Use exact budget coefficients:

```text
sum(include[p] * exactContentLength[p]) <= budgetBytes
```

## Reference pseudocode

```python
model = BinaryLinearProgram()
include = model.binary_vars(products)
assign = model.binary_vars(filters_x_channels)
link = model.binary_vars(token_occurrences_x_channels)
opened = model.binary_vars(groups)
uses = model.binary_vars(groups_x_channels)

add_channel_and_link_constraints(model, include, assign, link)
add_opened_group_constraints(model, include, opened)
add_channel_use_constraints(model, link, uses, opened)
add_assignment_requires_selected_product(model, assign, include)
model.add(exact_byte_sum(include) <= budget_bytes)

maximize_and_freeze(model, shared_coverage_or_opened_groups)
maximize_and_freeze(model, selected_filter_count)
model.minimize(exact_byte_sum(include))
solution = model.solve()
```

## Conceptual output

```json
{
  "status": "optimal",
  "opened_groups": ["G1"],
  "selected_products": ["P1", "P2", "P3"],
  "filter_channels": {"F435W": 0, "F555W": 1, "F814W": 2},
  "used_channels": {"G1": [0, 1, 2]},
  "selected_bytes": 62914560,
  "objectives": {
    "opened_groups": 1,
    "selected_filters": 3,
    "minimized_bytes": 62914560
  }
}
```

## Compact flow

```text
Exact products and channel candidates
  -> create binary include/assign/link/opened/use variables
  -> enforce filter and channel consistency
  -> enforce complete opened groups
  -> enforce exact byte budget
  -> check feasibility
  -> maximize primary objective and freeze it
  -> maximize filter objective and freeze it
  -> minimize bytes
  -> emit exact selected products and assignments
```

## Coverage-aware objective

If exact grid-cell variables are too large, precompute candidate coverage sets and use a binary `covered[cell,channel]` variable. A useful lexicographic order is:

```text
1. Maximize cells covered by all required channels
2. Maximize minimum per-channel coverage
3. Maximize useful filter diversity
4. Minimize exact selected bytes
```
