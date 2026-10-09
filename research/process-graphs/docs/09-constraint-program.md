# Constraint program

Source: [`../09-constraint-program.mmd`](../09-constraint-program.mmd)

## Purpose

The constraint-program option uses OR-Tools CP-SAT to solve a discrete model similar to the ILP, with an additional rule ensuring common filters occupy the preferred primary channels.

## Inputs

- Inputs and binary decisions from option 08
- Global `groupCount` per filter
- `primaryRankLimit`, default 5
- Primary channel indexes, normally 0, 1, and 2

## Flow

### 1. Rank filters by frequency

`frequencyRank(filter)` is one plus the number of filters with a strictly larger group count. Filters tied on group count share a rank.

### 2. Define top filters

`topFilters` contains every filter whose rank is at most `primaryRankLimit`. Because ties share ranks, this set can contain more than five filters when the limit is five.

### 3. Build the binary selection/channel model

The model reuses product inclusion, global filter assignment, link, opened-group, budget, channel-use, and minimum-groups-per-channel rules from option 08.

### 4. Add the preferred-channel gate

For each primary channel, at least one top filter must be assigned to it. The intent is to reserve prominent channels for common filters.

The diagram expects common mutually adjacent filters such as F555W, F814W, and F435W to occupy different primary channels.

### 5. Solve lexicographically

CP-SAT maximizes opened groups, then coloured filters, then minimizes estimated bytes. If the rank gate makes the model infeasible, the algorithm reports infeasible and does not automatically widen the rank limit.

## Implementation by diagram node

### Calculate competition-style frequency ranks

```python
frequency_rank = {
    filter_name: 1 + sum(
        other_count > group_count[filter_name]
        for other_count in group_count.values()
    )
    for filter_name in filters
}
```

Equal `groupCount` values produce equal ranks, so rank five does not necessarily mean only five filters are retained.

### Build the top-filter set

```python
top_filters = {
    filter_name for filter_name in filters
    if frequency_rank[filter_name] <= primary_rank_limit
}
```

### Recreate the option 08 binary model in CP-SAT

```python
from ortools.sat.python import cp_model

model = cp_model.CpModel()
include = {p: model.NewBoolVar(f"include_{p}") for p in products}
assign = {
    (f, c): model.NewBoolVar(f"assign_{f}_{c}")
    for f in filters for c in channels
}
link, opened, uses_channel = add_binary_selection_structure(
    model, include, assign, products, groups, channels
)
add_budget(model, include, average_file_bytes, budget_bytes)
add_minimum_group_channel_use(model, uses_channel, minimum_groups_per_channel)
```

The helper represents the same constraints as option 08; it is not a different selection model yet.

### Require a common filter on each primary channel

```python
for channel in range(primary_channel_count):
    model.Add(sum(assign[f, channel] for f in top_filters) >= 1)
```

This is the rank gate. A top filter can satisfy it even if the original model fails to tie assignments to selected products.

### Express the intended adjacency responsibility explicitly

```python
for left, right in adjacent_pairs:
    for channel in channels:
        model.Add(assign[left, channel] + assign[right, channel] <= 1)
```

The Mermaid prose relies on adjacent common filters taking different hues; this constraint is the direct way to guarantee it.

### Solve the same three objectives

```python
best_opened = solve_and_freeze_max(model, sum(opened.values()))
best_colored = solve_and_freeze_max(model, sum(assign.values()))
status = solve_min(model, estimated_byte_expression)

if status == cp_model.INFEASIBLE:
    return {
        "status": "infeasible",
        "primary_rank_limit": primary_rank_limit,
        "automatically_widened": False,
    }
```

The strict diagram reports infeasibility rather than changing `primaryRankLimit` behind the user's back.

## Output

- Product inclusion decisions
- Global filter/channel assignment
- Opened groups and channel use
- Objective values and feasibility status

## Advantages

- CP-SAT is well suited to discrete logical requirements.
- Easier to extend with implications, counts, alternatives, and conditional constraints.
- Exact for the declared model when solved to optimality.
- Common-filter colour preference is explicit rather than hidden in a heuristic score.
- Strong benchmark for simpler selectors.

## Limitations and model gaps

- Inherits the ILP's missing coverage and approximate-cost problems.
- Top-filter assignment is not sufficient unless assigned filters are tied to selected products.
- Pairwise adjacency should be enforced explicitly on global assignments if it must hold even outside selected links.
- The gate is global; it does not ensure each opened group has all primary channels.
- Rank ties can enlarge `topFilters` unexpectedly.
- Strict floors can make the model infeasible even when a useful partial composite exists.
- Solver dependency and model debugging add operational complexity.

## Complexity

CP-SAT solves an NP-hard combinatorial problem. Performance depends strongly on constraint propagation, symmetry, and objective structure. Explicit symmetry breaking and deterministic solver settings are important for repeatable evaluation.

## Recommended implementation changes

Correct the option 08 model first. Add `assign <= selected occurrences` constraints, per-opened-group distinct-channel rules, exact bytes, and coverage. Add explicit adjacency constraints when global colour consistency is required. Report the best feasible result and optimality gap when time-limited rather than only success or infeasibility.

## Worked example: frequency ranks

Suppose filter counts are:

| Filter | Group count | Frequency rank |
|---|---:|---:|
| F555W | 29 | 1 |
| F814W | 25 | 2 |
| F435W | 18 | 3 |
| F606W | 18 | 3 |
| F200W | 10 | 5 |
| F300M | 10 | 5 |

With `primaryRankLimit = 5`, all six filters are top filters because tied counts share ranks. The name “top five” would therefore be misleading.

For three primary channels, the gate requires at least one top filter assigned to each channel. It does not by itself require those filters to appear in downloaded products unless the corrected selection link is added.

## Explicit adjacency rule

If two filters must never share a global channel because they occur together, add:

```text
assign[A,c] + assign[B,c] <= 1
for every adjacent pair (A,B) and channel c
```

This is clearer than relying only on link variables activated by selected products.

## Reference pseudocode

```python
model = cp_model.CpModel()
include, assign, link, opened, uses = create_boolean_variables(model)

add_corrected_selection_constraints(model, include, assign, link, opened, uses)
add_exact_budget(model, include, exact_bytes)

top_filters = {
    f for f in filters
    if frequency_rank(group_count, f) <= primary_rank_limit
}
for channel in primary_channels:
    model.Add(sum(assign[f, channel] for f in top_filters) >= 1)

for left, right in adjacent_pairs:
    for channel in channels:
        model.Add(assign[left, channel] + assign[right, channel] <= 1)

solve_lexicographically(model)
```

## Conceptual output

```json
{
  "status": "FEASIBLE",
  "optimality_proven": false,
  "best_bound": 12,
  "opened_group_count": 10,
  "selected_products": ["..."],
  "primary_channel_top_filters": {
    "0": ["F435W"],
    "1": ["F555W"],
    "2": ["F814W"]
  },
  "selected_bytes": 2070043200,
  "solver_seconds": 30.0
}
```

## Compact flow

```text
Corrected binary selection model
  -> rank filters by group frequency
  -> identify top-filter set with ties
  -> require a top filter on every primary channel
  -> enforce adjacency and group completeness
  -> enforce exact byte budget
  -> solve with CP-SAT
  -> report optimum or best feasible solution and bound
```

## Graceful infeasibility strategy

Instead of silently widening constraints, report which assumption caused failure and optionally run declared fallback profiles:

```text
strict: 3 complete channels + rank gate + coverage target
balanced: 3 complete channels + rank gate
fallback: 3 complete channels without rank gate
```

Each profile must remain auditable; the solver should never relax a rule without recording it.
