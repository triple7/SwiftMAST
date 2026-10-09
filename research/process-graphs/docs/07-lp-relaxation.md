# Linear-programming relaxation

Source: [`../07-lp-relaxation.mmd`](../07-lp-relaxation.mmd)

## Purpose

The LP-relaxation option models product inclusion and filter-to-channel assignment as continuous values between zero and one. It solves the fractional optimization problem, then rounds the result into a real product list.

Its strongest role is to provide a diagnostic upper bound or an initializer. The rounded result is not an exact solution to the original discrete problem.

## Inputs

- Qualified groups and representative IDs
- Filter tokens and global `groupCount`
- Estimated `averageFileBytes`
- `channelCount`, default 3
- `budgetBytes`

## Variables

- `include[group, id]` in `[0,1]`: fractional product inclusion
- `assign[filter, channel]` in `[0,1]`: fractional channel assignment
- `link[group, id, token, channel]` in `[0,1]`: linearized product of inclusion and assignment

## Model flow

### 1. Limit each filter to one channel

The sum of a filter's assignments across channels is at most one. A sum of zero means the filter is unused.

### 2. Require included products to have coloured tokens

For every token belonging to an ID, product inclusion cannot exceed the total channel assignment of that token.

### 3. Linearize inclusion times assignment

Three bounds force `link` to represent the product of `include` and `assign` in an integer model and its convex relaxation in the LP:

```text
link <= include
link <= assign
link >= include + assign - 1
```

### 4. Avoid channel collisions in a group

For every group and channel, the sum of links over its IDs and tokens is at most one.

### 5. Apply the budget

```text
sum(include * averageFileBytes) <= budgetBytes
```

### 6. Maximize weighted inclusion

Each ID's weight is the sum of `groupCount` values for its tokens. The LP maximizes fractional included weight.

## Rounding flow

### 7. Convert assignments to channels

For each filter, the channel with largest fractional assignment is chosen. Smaller channel index breaks ties. If all assignments are zero, the filter receives `NONE`.

### 8. Sort products by inclusion

Representative IDs are ordered by fractional inclusion descending and ID ascending.

### 9. Greedily construct a feasible list

An ID is skipped if a token has no chosen channel, its channels clash with those already held by the group, or its estimated/max-size guards do not fit. Otherwise it is accepted and its channels are recorded.

## Implementation by diagram node

### Create continuous decision variables

```python
include = {
    product: model.continuous_var(0, 1, name=f"include_{product}")
    for product in products
}
assign = {
    (filter_name, channel): model.continuous_var(0, 1)
    for filter_name in filters
    for channel in range(channel_count)
}
link = {
    (product, token, channel): model.continuous_var(0, 1)
    for product in products
    for token in tokens_of[product]
    for channel in range(channel_count)
}
```

The values are fractions, not yes/no decisions.

### Limit a filter to at most one channel

```python
for filter_name in filters:
    model.add(
        sum(assign[filter_name, channel] for channel in channels) <= 1
    )
```

A sum of zero leaves the filter unused.

### Require every token of an included product to be assigned

```python
for product in products:
    for token in tokens_of[product]:
        model.add(
            include[product]
            <= sum(assign[token, channel] for channel in channels)
        )
```

This is applied per token. A two-token product cannot be included unless both tokens receive assignment mass.

### Linearize `include * assign` with link bounds

```python
for product in products:
    for token in tokens_of[product]:
        for channel in channels:
            z = link[product, token, channel]
            x = include[product]
            y = assign[token, channel]
            model.add(z <= x)
            model.add(z <= y)
            model.add(z >= x + y - 1)
```

For binary variables these equations force an exact product. In an LP they form its convex relaxation.

### Prevent two token occurrences from occupying one group/channel

```python
for group in groups:
    for channel in channels:
        model.add(
            sum(
                link[product, token, channel]
                for product in products_by_group[group]
                for token in tokens_of[product]
            ) <= 1
        )
```

The rule counts token occurrences. A multi-token product can occupy more than one channel.

### Apply the estimated-byte budget

```python
model.add(
    sum(include[p] * average_file_bytes[group_of[p]] for p in products)
    <= budget_bytes
)
```

### Build and solve the weighted objective

```python
weight = {
    product: sum(group_count[token] for token in tokens_of[product])
    for product in products
}
model.maximize(sum(include[p] * weight[p] for p in products))
status = model.solve()
```

The objective rewards globally common filters; it does not measure new footprint coverage.

### Convert fractional assignments into one chosen channel

```python
chosen_channel = {}
for filter_name in filters:
    values = [solution(assign[filter_name, c]) for c in channels]
    chosen_channel[filter_name] = (
        None if max(values, default=0) <= 0
        else min(channels, key=lambda c: (-values[c], c))
    )
```

Smaller channel index breaks equal fractional values.

### Sort products by fractional inclusion

```python
rounded_order = sorted(
    products,
    key=lambda product: (-solution(include[product]), product),
)
```

### Restore discrete feasibility during rounding

```python
spent = 0
held_channels = defaultdict(set)
rounded_products = []

for product in rounded_order:
    product_channels = {chosen_channel[token] for token in tokens_of[product]}
    if None in product_channels:
        continue
    group = group_of[product]
    if product_channels & held_channels[group]:
        continue
    price = average_file_bytes[group]
    if spent + price > budget_bytes:
        continue
    rounded_products.append(product)
    spent += price
    held_channels[group].update(product_channels)
```

This stage creates the downloadable result, but it can be much worse than the fractional objective and does not guarantee three channels per group.

## Output

- Rounded representative-ID list
- Chosen channel per filter
- Estimated spending
- Fractional LP solution for diagnostics

The rounding does not require every opened group to contain three channels.

## Advantages

- Considers all products together instead of making only local choices.
- Solves in polynomial time with standard LP solvers.
- Gives an upper bound on the stated fractional objective.
- Highlights which products and assignments are strongly or weakly preferred.
- Can initialize greedy or integer methods.

## Limitations

- Fractional products and colours are not directly usable.
- Rounding can lose objective value and does not preserve LP optimality.
- The final result may not meet group-completion goals.
- Objective rewards popular filter occurrences, not spatial coverage.
- Uses estimated prices.
- A dual-token ID may create unintuitive link/channel behaviour.
- No explicit requirement ties the output to three-channel coverage.
- Solver output may contain many equivalent fractional assignments.

## Complexity

LP solving is polynomial in theory, although practical cost depends on variable and constraint counts. Link variables scale with product-token-channel combinations, approximately `O(T * C)`, where `T` is total token occurrences.

## Recommended implementation changes

Use exact product costs. Add product-to-footprint or precomputed coverage-cell variables when feasible. Define a group-completion requirement. Use the relaxation primarily as an upper bound for a corresponding corrected integer model, and measure the rounding gap explicitly.

## Worked example

Assume one group has two products and two channels:

| Product | Filter | Price | Weight |
|---|---|---:|---:|
| P1 | F435W | 60 MiB | 10 |
| P2 | F814W | 60 MiB | 8 |

With a 90 MiB budget, the LP can choose fractional values such as:

```text
include(P1) = 1.0
include(P2) = 0.5
cost = 60 + 30 = 90 MiB
objective contribution = 10 + 4 = 14
```

A real downloader cannot fetch half of P2. Rounding P2 down produces a 60 MiB result with objective 10; rounding it up violates the budget. This is the central LP-relaxation trade-off.

## Constraint example

For product P1 containing F435W and channel 0:

```text
link(P1,F435W,0) <= include(P1)
link(P1,F435W,0) <= assign(F435W,0)
link(P1,F435W,0) >= include(P1) + assign(F435W,0) - 1
```

When both binary inputs are one, link must be one. In the relaxation, all three may be fractional.

## Reference pseudocode

```python
model = LinearProgram(maximize=True)
include = continuous_vars(products, low=0, high=1)
assign = continuous_vars(filters_x_channels, low=0, high=1)
link = continuous_vars(token_occurrences_x_channels, low=0, high=1)

add_one_channel_per_filter(model, assign)
add_inclusion_requires_assignment(model, include, assign)
add_mccormick_link_bounds(model, include, assign, link)
add_one_token_per_group_channel(model, link)
model.add(sum(include[p] * price[p] for p in products) <= budget)
model.maximize(sum(include[p] * weight[p] for p in products))

fractional_solution = model.solve()
rounded = deterministic_feasible_round(fractional_solution)
```

## Conceptual output

```json
{
  "lp_status": "optimal",
  "fractional_objective": 14.0,
  "fractional_include": {"P1": 1.0, "P2": 0.5},
  "rounded_products": ["P1"],
  "rounded_spent_bytes": 62914560,
  "rounded_objective": 10.0,
  "rounding_gap": 4.0,
  "chosen_channels": {"F435W": 0, "F814W": 1}
}
```

## Compact flow

```text
Products, filters, channels, and budget
  -> create fractional include/assign/link variables
  -> add channel, link, conflict, and budget constraints
  -> maximize weighted fractional inclusion
  -> solve LP
  -> choose largest channel assignment per filter
  -> sort IDs by inclusion fraction
  -> greedily round while restoring feasibility
  -> report fractional bound and rounded result
```

## Improved optimization role

The LP should be paired with the equivalent integer model and reported as:

```text
integralityGap =
    (LP upper bound - integer feasible value)
    / max(abs(LP upper bound), epsilon)
```

This quantifies how informative the relaxation is. A large gap means its fractional recommendation is not a reliable guide to the real selection problem.
