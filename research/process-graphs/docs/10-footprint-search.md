# Footprint search

Source: [`../10-footprint-search.mmd`](../10-footprint-search.mmd)

## Purpose

The footprint-search option improves a product/channel state using either simulated annealing or population-based search. It is the only example that joins selected IDs back to Phase 1 products and directly evaluates `s_region` footprint coverage.

## Inputs

- Initial purchased IDs from option 06
- Initial filter channels from option 05
- Phase 1 qualified JSON with exact `obs_id` and `s_region`
- Target RA, Dec, radius, and coverage-grid dimension
- `budgetBytes`
- `primaryChannelCount`, default 3
- Fitness weights
- Annealing or population-search configuration

## State and fitness preparation

### 1. Initialize selection and channels

`kept` starts with the file-knapsack result. `channelOf` starts with wavelength-bin assignments for filters in those products.

The diagram's defaults are inconsistent here: option 05 has seven bins while option 10 declares three valid channels. A seven-to-three mapping is required before search.

### 2. Calculate penalties

- `conflictCount`: extra products occupying the same channel in a group
- `budgetOverage`: estimated spending above the budget
- `underfilled`: missing channels in each non-empty group
- `unmatchedIDCount`: selected IDs not found in Phase 1 JSON

### 3. Calculate benefits

- `diversity`: number of groups occupying each channel
- `coverageFraction`: target-grid points inside the union of selected footprints

### 4. Calculate fitness

The default formula is conceptually:

```text
10 * coverageFraction
+ diversity
- 1000 * conflictCount
- 1000 * normalizedBudgetOverage
- 100 * underfilled
- 100 * unmatchedIDCount
```

The large penalties strongly discourage invalid states, while coverage and diversity distinguish valid ones.

## Simulated-annealing flow

### 5. Propose a move

Add, drop, or recolour is selected with equal probability. Add chooses an unselected representative ID; drop chooses a selected ID; recolour changes a filter to another primary channel.

### 6. Accept or reject

Improving moves are always accepted. A worse move is accepted with probability:

```text
exp(delta / temperature)
```

Temperature is multiplied by `coolingRate` after every step. The highest-fitness state ever seen is retained and returned after `stepCount` iterations.

## Population-search flow

### 7. Encode chromosomes

A chromosome contains one inclusion bit per representative ID plus one channel value per filter.

### 8. Evolve the population

Children copy each gene from either parent. Product bits and channel genes mutate at configured per-gene rates. Tournaments of three favour higher-fitness individuals. After the configured generations, the highest-fitness final chromosome is returned.

## Implementation by diagram node

### Initialize `kept` and reduce wavelength bins to valid channels

```python
kept = set(file_knapsack_result.get("purchased", []))

def primary_channel(bin_index, primary_channel_count=3):
    # This policy must be declared; modulo is only an example mapping.
    return bin_index % primary_channel_count

channel_of = {
    filter_name: primary_channel(bin_of[filter_name], primary_channel_count)
    for filter_name in filters_present_in(kept)
}
```

Option 05 can produce seven bin indexes while this search accepts only `0..C-1`. The conversion policy must therefore be explicit; the example modulo rule is not automatically scientifically correct.

### Count same-channel conflicts inside groups

```python
from collections import Counter

def conflict_count(state):
    total = 0
    for group in groups_touched_by(state.kept):
        occupants = Counter()
        for product in kept_products_in(group, state.kept):
            for token in tokens_of[product]:
                occupants[state.channel_of[token]] += 1
        total += sum(max(0, count - 1) for count in occupants.values())
    return total
```

Three products on one channel contribute two conflicts because only the first occupant is free.

### Calculate spending and normalized overage

```python
def spending(state):
    return sum(average_file_bytes[group_of[p]] for p in state.kept)

spent = spending(state)
budget_overage = max(0, spent - budget_bytes)
normalized_overage = budget_overage / budget_bytes
```

The diagram requires `budgetBytes > 0` because overage is divided by it.

### Count missing primary channels in non-empty groups

```python
def underfilled_count(state):
    total = 0
    for group in groups_touched_by(state.kept):
        channels = {
            state.channel_of[token]
            for product in kept_products_in(group, state.kept)
            for token in tokens_of[product]
        }
        total += max(0, primary_channel_count - len(channels))
    return total
```

An empty group is not penalized; once a group has one kept product, every missing required channel counts.

### Measure channel diversity across groups

```python
def diversity_score(state):
    return sum(
        sum(
            any(
                state.channel_of[token] == channel
                for product in kept_products_in(group, state.kept)
                for token in tokens_of[product]
            )
            for group in groups_touched_by(state.kept)
        )
        for channel in range(primary_channel_count)
    )
```

This counts group/channel occupancy, not unique filters and not sky area.

### Join kept IDs to Phase 1 footprint records

```python
records_by_obs_id = {
    record["obs_id"]: record
    for record in phase_1_qualified_records
}
matched = [records_by_obs_id[p] for p in state.kept if p in records_by_obs_id]
unmatched_id_count = sum(p not in records_by_obs_id for p in state.kept)
```

Unmatched IDs cannot contribute `s_region` coverage and receive a separate penalty.

### Create the target grid

```python
grid_points = make_sky_grid(
    center_ra=target_ra,
    center_dec=target_dec,
    radius_degrees=target_radius_degrees,
    dimension=grid_dimension,
)
```

RA, Dec, radius, and grid dimension are not present in the group CSV; they come from Phase 1 metadata and caller configuration.

### Calculate union footprint coverage

```python
footprints = [parse_stcs(record["s_region"]) for record in matched]
covered_points = sum(
    any(footprint.contains(point) for footprint in footprints)
    for point in grid_points
)
coverage_fraction = covered_points / len(grid_points) if grid_points else 0.0
```

This is union coverage. It does not prove that all primary channels cover the same point.

### Combine benefits and penalties into fitness

```python
def evaluate(state):
    coverage = coverage_fraction_for(state)
    diversity = diversity_score(state)
    conflicts = conflict_count(state)
    spent = spending(state)
    overage = max(0, spent - budget_bytes) / budget_bytes
    underfilled = underfilled_count(state)
    unmatched = unmatched_count(state)

    fitness = (
        10 * coverage
        + 1 * diversity
        - 1000 * conflicts
        - 1000 * overage
        - 100 * underfilled
        - 100 * unmatched
    )
    return fitness
```

The coefficients encode priorities. They are not derived from the data and must be treated as configuration.

### Propose annealing moves

```python
def propose_move(state, rng):
    available = ["add"]
    if state.kept:
        available.extend(["drop", "recolor"])
    move = rng.choice(available)

    proposal = state.copy()
    if move == "add":
        proposal.kept.add(rng.choice(sorted(all_product_ids - state.kept)))
    elif move == "drop":
        proposal.kept.remove(rng.choice(sorted(state.kept)))
    else:
        filter_name = rng.choice(sorted(filters_present_in(state.kept)))
        alternatives = set(range(primary_channel_count)) - {state.channel_of[filter_name]}
        proposal.channel_of[filter_name] = rng.choice(sorted(alternatives))
    return proposal
```

The Mermaid flow gives add, drop, and recolour equal conceptual status; boundary states may make some moves unavailable.

### Accept, reject, cool, and remember the best state

```python
current = initial_state
best = current.copy()
temperature = start_temperature

for step in range(step_count):
    proposal = propose_move(current, rng)
    delta = evaluate(proposal) - evaluate(current)
    accept = delta >= 0 or rng.random() < exp(delta / temperature)
    if accept:
        current = proposal
    if evaluate(current) > evaluate(best):
        best = current.copy()
    temperature *= cooling_rate
```

Returning `best`, rather than merely the final `current`, prevents a late exploratory move from replacing the best result seen.

### Encode the population-search chromosome

```python
product_order = sorted(products, key=lambda p: (group_of[p], p))
filter_order = sorted(all_filters)

chromosome = {
    "included": [int(p in state.kept) for p in product_order],
    "channel": [state.channel_of[f] for f in filter_order],
}
```

The stable orders are required so that the same gene always refers to the same product or filter.

### Crossover and mutate genes

```python
def make_child(parent_a, parent_b, rng):
    child_bits = [rng.choice(pair) for pair in zip(parent_a.bits, parent_b.bits)]
    child_channels = [
        rng.choice(pair) for pair in zip(parent_a.channels, parent_b.channels)
    ]

    for index in range(len(child_bits)):
        if rng.random() < 1 / len(child_bits):
            child_bits[index] ^= 1
    for index in range(len(child_channels)):
        if rng.random() < 1 / len(child_channels):
            child_channels[index] = rng.randrange(primary_channel_count)
    return Chromosome(child_bits, child_channels)
```

### Select the next generation by tournaments

```python
def tournament(population, rng, size=3):
    contestants = rng.sample(population, k=min(size, len(population)))
    return max(contestants, key=evaluate_chromosome)

for generation in range(generations):
    next_population = []
    while len(next_population) < population_size:
        parent_a = tournament(population, rng)
        parent_b = tournament(population, rng)
        next_population.append(make_child(parent_a, parent_b, rng))
    population = next_population

population_result = max(population, key=evaluate_chromosome)
```

The source diagram returns the best chromosome in the final generation. The recommended version later in this guide adds explicit elitism so the global best cannot disappear.

## Output

- Selected IDs
- Global filter/channel mapping
- Fitness and component metrics
- Coverage fraction
- Estimated bytes spent

## Advantages

- Directly evaluates real footprints.
- Can escape the local decisions made by a greedy initializer.
- Can jointly adjust selection and channel mapping.
- Flexible fitness can incorporate additional scientific goals.
- Provides usable intermediate states even without proving optimality.

## Limitations

- Stochastic results require an explicit random seed for comparison.
- Spending still uses estimated average costs.
- Union coverage can be high even when only one channel covers most of the target.
- Default diversity scale can dominate the maximum coverage contribution.
- Seven-bin initialization conflicts with three-channel state.
- Fitness weights are difficult to calibrate and combine quantities with different ranges.
- Search cannot prove global optimality.
- Population flow does not explicitly describe elitism or preservation of the best state across generations.
- Recolouring one global filter can change many groups simultaneously.

## Complexity

If fitness recomputes every selected footprint over `Q` grid points, annealing costs roughly `O(steps * P * Q)` in a naive implementation. Cached coverage counts and incremental add/drop updates can reduce this substantially. Population search multiplies fitness cost by population size and generation count.

## Recommended implementation changes

Use exact file sizes and a fixed seed. Map wavelength bins to valid channels before initialization. Track coverage separately per channel and optimize shared primary-channel coverage, such as the fraction covered by all three channels. Normalize every fitness component to a comparable range. Preserve the global best state explicitly and update coverage incrementally.

## Worked example: fitness calculation

Assume a candidate state has:

```text
coverageFraction = 0.60
diversity = 12
conflictCount = 0
budgetOverage = 0
underfilled = 1
unmatchedIDCount = 0
```

Using the diagram's defaults:

```text
fitness = 10*0.60 + 12 - 100*1
        = 6 + 12 - 100
        = -82
```

Completing the underfilled group is worth far more than any possible coverage gain. Also, diversity can reach values much larger than the maximum coverage contribution of 10. This demonstrates why fitness components need normalization and documented priority.

## Multi-channel coverage example

Suppose union coverage is 80%, but channel coverage is:

| Channel | Coverage |
|---|---:|
| Blue | 80% |
| Green | 35% |
| Red | 20% |

The union is not a useful RGB coverage measure. Better metrics are:

```text
minimumChannelCoverage = 20%
sharedThreeChannelCoverage = cells covered by blue AND green AND red
```

## Annealing pseudocode

```python
rng = Random(seed)
current = initial_state
best = current
temperature = start_temperature

for _ in range(step_count):
    proposal = random_add_drop_or_recolor(current, rng)
    delta = fitness(proposal) - fitness(current)
    if delta >= 0 or rng.random() < exp(delta / temperature):
        current = proposal
    if fitness(current) > fitness(best):
        best = current
    temperature *= cooling_rate

return best
```

## Population-search pseudocode

```python
population = initialize_population(seed_state, population_size, rng)
best = max(population, key=fitness)

for _ in range(generations):
    next_population = [best]  # explicit elitism
    while len(next_population) < population_size:
        parent_a = tournament(population, 3, rng)
        parent_b = tournament(population, 3, rng)
        child = mutate(crossover(parent_a, parent_b, rng), rng)
        next_population.append(child)
    population = next_population
    best = max(best, *population, key=fitness)
```

## Conceptual output

```json
{
  "search": "annealing",
  "random_seed": 42,
  "selected_products": ["product-a", "product-b", "product-c"],
  "filter_channels": {"F435W": 0, "F555W": 1, "F814W": 2},
  "exact_spent_bytes": 1980000000,
  "union_coverage": 0.72,
  "per_channel_coverage": {"0": 0.68, "1": 0.61, "2": 0.57},
  "shared_primary_coverage": 0.49,
  "conflict_count": 0,
  "underfilled_group_count": 0,
  "fitness": 0.783
}
```

## Compact flow

```text
Greedy initial selection
  -> map bins to valid primary channels
  -> join IDs to exact Phase 1 products
  -> build target coverage grid
  -> score validity, budget, per-channel coverage, and diversity
  -> repeatedly add, drop, or recolour
  -> accept improvements and controlled exploratory moves
  -> preserve best state
  -> return exact products, channels, coverage, and fitness audit
```

## Improved normalized fitness

Use components in `[0,1]` and separate hard validity from soft quality:

```text
if conflicts > 0 or exactBytes > budgetBytes or unmatched > 0:
    state is infeasible

fitness =
    0.45 * sharedPrimaryCoverage
  + 0.25 * minimumChannelCoverage
  + 0.15 * meanChannelCoverage
  + 0.10 * normalizedFilterDiversity
  + 0.05 * normalizedQuality
```

If incomplete groups are allowed, make their penalty normalized and explicit. If they are forbidden, treat them as infeasible instead of mixing them into the soft score.
