#!/usr/bin/env python3
"""Run a documented Phase 2 selector and visualize real MAST footprints.

The input is produced by ``phase1.py`` or by the existing composite pipeline.
Selection is entirely offline. The renderer uses real ``s_region`` geometry,
but it does not download FITS data or preview images. Coloured footprints are
filled with deterministic synthetic dark patches to suggest bright and dark
image structure without pretending to show astronomical pixels.

Example::

    .venv/bin/python research/process-graphs/scripts/phase2.py \
      --input research/process-graphs/runs/ngc628/phase-1-qualified.json \
      --algorithm 02-greedy-group-rank \
      --max-total-mib 2000 \
      --max-products 150 \
      --output-dir research/process-graphs/runs/ngc628/group-rank
"""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import importlib.util
import json
import logging
import math
import os
import random
import statistics
import sys
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from typing import Any, Callable


# Matplotlib needs a writable cache even when the user's home cache is locked.
_MPL_CACHE = Path(tempfile.gettempdir()) / "swiftmast-process-graphs-matplotlib"
_MPL_CACHE.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_MPL_CACHE))

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import to_hex, to_rgb, to_rgba
from matplotlib.lines import Line2D
from matplotlib.patches import Circle, Ellipse, Patch, Polygon


ROOT = Path(__file__).resolve().parents[3]
GREEDY_PATH = ROOT / "Sources" / "scripts" / "greedy_mast_tap_selection.py"
MIB = 1_048_576
SCHEMA_VERSION = 1
LOGGER = logging.getLogger("swiftmast.process_graphs.phase2")

ALGORITHMS = {
    "01-wavelength-palette": "Wavelength RGB policy and complete-group purchase",
    "02-greedy-group-rank": "Whole groups ranked by distinct filters per exact MiB",
    "03-rgb-triple-vote": "Globally supported three-filter RGB composition",
    "04-degree-coloring": "Group-rank selection with conflict-graph display colours",
    "05-wavelength-bins": "Multi-bin spectral diversity per exact byte",
    "06-file-knapsack": "Individual products ranked by marginal channel value",
    "07-lp-relaxation": "Fractional value/byte relaxation followed by feasible rounding",
    "08-integer-linear-program": "Binary group-opening model solved with SciPy MILP",
    "09-constraint-program": "Binary selection with common-filter primary-colour gate",
    "10-footprint-search": "Iterative marginal footprint and filter coverage search",
}

COMPARISON_NOTES = {
    "04-degree-coloring": (
        "The source diagram assigns colours but does not select products; "
        "the comparison uses option 02's selected products before colouring."
    ),
    "07-lp-relaxation": (
        "The comparison solves the documented fractional value/byte budget relaxation "
        "and applies deterministic feasible rounding; it omits full link-variable channels."
    ),
    "08-integer-linear-program": (
        "SciPy MILP implements binary product inclusion, group opening, product count, "
        "and byte budget; display channels are assigned after selection."
    ),
    "09-constraint-program": (
        "Uses option 08's binary selection and applies the common-filter primary-colour "
        "gate deterministically because OR-Tools is not installed."
    ),
    "10-footprint-search": (
        "Uses deterministic marginal footprint/filter search for reproducible comparison; "
        "the stochastic annealing/population variants remain future refinements."
    ),
}

CHANNEL_COLORS = {
    "blue": "#0072B2",
    "green": "#009E73",
    "red": "#D55E00",
}
MISSION_COLORS = {"JWST": "#CC79A7", "HST": "#0072B2", "HLA": "#E69F00"}


@dataclass(frozen=True)
class PreparedProduct:
    identity: str
    group_id: str
    group_name: str
    filters: frozenset[str]
    bytes: int
    shapes: tuple[tuple[str, tuple[float, ...]], ...]
    cells: frozenset[int]
    row: dict[str, Any]


def load_tap_helpers():
    spec = importlib.util.spec_from_file_location("swiftmast_process_graph_tap", GREEDY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {GREEDY_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def safe_slug(value: str) -> str:
    text = "".join(character.lower() if character.isalnum() else "-" for character in value)
    return "-".join(part for part in text.split("-") if part) or "observation"


def finite(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if math.isfinite(number) else None


def exact_bytes(row: dict[str, Any]) -> int:
    value = finite(row.get("contentlength_bytes") or row.get("contentlength"))
    return int(value) if value is not None and value > 0 else 0


def product_identity(row: dict[str, Any]) -> str:
    return str(row.get("datauri") or row.get("obs_id") or "").strip()


def footprint_text(row: dict[str, Any]) -> str:
    region = " ".join(str(row.get("s_region") or "").upper().split())
    bounds = " ".join(str(row.get("posboundsstcs") or "").upper().split())
    return bounds if bounds and bounds != region else region


def load_phase1(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    decoded = read_json(path)
    artifact = decoded.get("artifact")
    if artifact == "mast-composite-phase-1-qualified":
        return decoded.get("configuration", {}), list(decoded.get("qualified_rows", []))
    if artifact == "process-graphs-phase-1-prepared":
        return decoded.get("configuration", {}), list(decoded.get("products", []))
    raise ValueError(
        "--input must be phase-1-qualified.json or phase-1-process-graph-input.json"
    )


def prepare_products(
    rows: list[dict[str, Any]],
    config: dict[str, Any],
    tap,
    grid_dimension: int,
    max_file_bytes: int,
) -> tuple[list[PreparedProduct], Any, list[dict[str, str]]]:
    grid = tap.make_coverage_grid(
        float(config["ra"]),
        float(config["dec"]),
        float(config["radius_degrees"]),
        grid_dimension,
    )
    prepared: list[PreparedProduct] = []
    rejected: list[dict[str, str]] = []
    seen: set[str] = set()
    for row in rows:
        identity = product_identity(row)
        size = exact_bytes(row)
        shapes = tap.parse_s_region(footprint_text(row))
        filters = frozenset(tap.filter_keys(row.get("filters")))
        reason = None
        if not identity:
            reason = "missing_identity"
        elif identity in seen:
            reason = "duplicate_identity"
        elif size <= 0:
            reason = "missing_size"
        elif size > max_file_bytes:
            reason = "exceeds_max_file_size"
        elif not filters:
            reason = "missing_filter"
        elif shapes is None:
            reason = "invalid_footprint"
        if reason:
            rejected.append({"identity": identity, "reason": reason})
            continue
        seen.add(identity)
        cells = frozenset(
            index
            for index, point in enumerate(grid.points)
            if tap.region_contains(point, shapes)
        )
        group_id = str(
            row.get("observation_group_id")
            or ":".join(
                (
                    str(row.get("obs_collection") or "UNKNOWN"),
                    str(row.get("instrument_name") or "UNKNOWN"),
                    str(row.get("obs_id") or identity),
                )
            )
        )
        prepared.append(
            PreparedProduct(
                identity=identity,
                group_id=group_id,
                group_name=str(row.get("observation_group") or group_id),
                filters=filters,
                bytes=size,
                shapes=shapes,
                cells=cells,
                row=row,
            )
        )
    return prepared, grid, rejected


def group_products(products: list[PreparedProduct]) -> dict[str, list[PreparedProduct]]:
    groups: dict[str, list[PreparedProduct]] = defaultdict(list)
    for product in products:
        groups[product.group_id].append(product)
    for members in groups.values():
        members.sort(key=lambda product: (str(product.row.get("obs_id") or ""), product.identity))
    return dict(groups)


def unique_products(products: list[PreparedProduct]) -> list[PreparedProduct]:
    """Deduplicate products by stable identity without hashing their row dictionaries."""

    return list(
        {
            product.identity: product
            for product in sorted(products, key=lambda item: item.identity)
        }.values()
    )


def wavelength_table(products: list[PreparedProduct]) -> dict[str, float]:
    values: dict[str, list[float]] = defaultdict(list)
    for product in products:
        low = finite(product.row.get("em_min"))
        high = finite(product.row.get("em_max"))
        if low is None and high is None:
            continue
        midpoint = statistics.fmean(value for value in (low, high) if value is not None)
        for filter_name in product.filters:
            values[filter_name].append(midpoint)
    return {name: statistics.median(items) for name, items in values.items()}


def global_group_counts(groups: dict[str, list[PreparedProduct]]) -> Counter[str]:
    result: Counter[str] = Counter()
    for members in groups.values():
        result.update({name for product in members for name in product.filters})
    return result


def add_group_if_fits(
    members: list[PreparedProduct],
    selected: list[PreparedProduct],
    selected_ids: set[str],
    spent: int,
    budget: int,
    max_products: int,
) -> tuple[int, bool]:
    fresh = [product for product in members if product.identity not in selected_ids]
    cost = sum(product.bytes for product in fresh)
    if not fresh or len(selected) + len(fresh) > max_products or spent + cost > budget:
        return spent, False
    selected.extend(fresh)
    selected_ids.update(product.identity for product in fresh)
    return spent + cost, True


def select_group_rank(context: dict[str, Any]) -> dict[str, Any]:
    groups = context["groups"]
    ranked = []
    for group_id, members in groups.items():
        filters = {name for product in members for name in product.filters}
        size = sum(product.bytes for product in members)
        score = len(filters) / max(size / MIB, 0.001)
        ranked.append((score, group_id, members, filters, size))
    ranked.sort(key=lambda item: (-item[0], item[1]))

    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    spent = 0
    decisions = []
    for score, group_id, members, filters, size in ranked:
        before = spent
        spent, accepted = add_group_if_fits(
            members, selected, selected_ids, spent, context["budget"], context["max_products"]
        )
        decisions.append(
            {
                "group_id": group_id,
                "score": score,
                "filter_count": len(filters),
                "candidate_bytes": size,
                "status": "selected" if accepted else "skipped",
                "budget_before_bytes": before,
                "budget_after_bytes": spent,
            }
        )
    return {"selected": selected, "decisions": decisions, "filter_colors": {}}


def channel_for(wavelength: float | None, blue_max: float, green_max: float) -> str | None:
    if wavelength is None:
        return None
    if wavelength < blue_max:
        return "blue"
    if wavelength < green_max:
        return "green"
    return "red"


def select_wavelength_palette(context: dict[str, Any]) -> dict[str, Any]:
    group_count = context["group_count"]
    wavelength = context["wavelength"]
    channel_of = {
        name: channel_for(value, context["blue_max"], context["green_max"])
        for name, value in wavelength.items()
    }
    candidates = []
    for group_id, members in context["groups"].items():
        winners = {}
        for channel in ("blue", "green", "red"):
            matching = [
                product
                for product in members
                if any(channel_of.get(name) == channel for name in product.filters)
            ]
            if matching:
                winners[channel] = min(
                    matching,
                    key=lambda product: (
                        -max(
                            group_count[name]
                            for name in product.filters
                            if channel_of.get(name) == channel
                        ),
                        product.identity,
                    ),
                )
        if len(winners) < context["primary_channels"]:
            continue
        kept = unique_products(list(winners.values()))
        kept_filters = {name for product in kept for name in product.filters}
        preferred = int({"F435W", "F555W", "F814W"} <= kept_filters)
        candidates.append((preferred, len(winners), sum(item.bytes for item in kept), group_id, kept))
    candidates.sort(key=lambda item: (-item[0], -item[1], item[2], item[3]))

    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    spent = 0
    decisions = []
    for preferred, channel_count, cost, group_id, members in candidates:
        before = spent
        spent, accepted = add_group_if_fits(
            members, selected, selected_ids, spent, context["budget"], context["max_products"]
        )
        decisions.append({
            "group_id": group_id,
            "canonical_hit": preferred,
            "channel_count": channel_count,
            "candidate_bytes": cost,
            "status": "selected" if accepted else "skipped",
            "budget_before_bytes": before,
            "budget_after_bytes": spent,
        })
    colors = {
        name: CHANNEL_COLORS[channel]
        for name, channel in channel_of.items()
        if channel is not None
    }
    return {"selected": selected, "decisions": decisions, "filter_colors": colors}


def select_rgb_triple(context: dict[str, Any]) -> dict[str, Any]:
    known_filters = sorted(context["wavelength"])
    groups = context["groups"]
    group_filters = {
        group_id: {name for product in members for name in product.filters}
        for group_id, members in groups.items()
    }
    evaluated = []
    for triple in combinations(known_filters, 3):
        supporting = [group_id for group_id, names in group_filters.items() if set(triple) <= names]
        cheapness = sum(
            1 / max(sum(product.bytes for product in groups[group_id]), 1)
            for group_id in supporting
        )
        evaluated.append((-len(supporting), -cheapness, triple, supporting))
    if not evaluated:
        return {"selected": [], "decisions": [], "filter_colors": {}, "stop_reason": "no_triple"}
    _, _, best_triple, supporting = min(evaluated)
    ordered = sorted(best_triple, key=context["wavelength"].get)
    colors = dict(zip(ordered, (CHANNEL_COLORS["blue"], CHANNEL_COLORS["green"], CHANNEL_COLORS["red"])))

    openable = []
    for group_id in supporting:
        members = groups[group_id]
        chosen = []
        for filter_name in best_triple:
            matching = [product for product in members if filter_name in product.filters]
            if not matching:
                break
            chosen.append(min(matching, key=lambda product: product.identity))
        if len(chosen) == 3:
            unique = unique_products(chosen)
            openable.append((sum(product.bytes for product in unique), group_id, unique))
    openable.sort(key=lambda item: (item[0], item[1]))

    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    spent = 0
    decisions = []
    for cost, group_id, members in openable:
        before = spent
        spent, accepted = add_group_if_fits(
            members, selected, selected_ids, spent, context["budget"], context["max_products"]
        )
        decisions.append({
            "group_id": group_id,
            "triple": list(best_triple),
            "candidate_bytes": cost,
            "status": "selected" if accepted else "skipped",
            "budget_before_bytes": before,
            "budget_after_bytes": spent,
        })
    return {
        "selected": selected,
        "decisions": decisions,
        "filter_colors": colors,
        "selected_triple": list(best_triple),
    }


def wavelength_bin(value: float | None, edges: list[float]) -> int | None:
    if value is None:
        return None
    for index, (low, high) in enumerate(zip(edges, edges[1:])):
        if low <= value < high:
            return index
    return None


def distributed_color(index: int, count: int) -> str:
    hue = ((300.0 - 180.0 / count) + index / count * 360.0 + 360.0) % 360.0
    return to_hex(colorsys.hsv_to_rgb(hue / 360.0, 1.0, 1.0)).upper()


def select_wavelength_bins(context: dict[str, Any]) -> dict[str, Any]:
    edges = context["bin_edges"]
    bin_count = len(edges) - 1
    bin_of = {name: wavelength_bin(value, edges) for name, value in context["wavelength"].items()}
    group_count = context["group_count"]
    openable = []
    for group_id, members in context["groups"].items():
        winners = {}
        for bin_index in range(bin_count):
            matching = [
                product for product in members
                if any(bin_of.get(name) == bin_index for name in product.filters)
            ]
            if matching:
                winners[bin_index] = min(
                    matching,
                    key=lambda product: (
                        -max(
                            group_count[name]
                            for name in product.filters
                            if bin_of.get(name) == bin_index
                        ),
                        product.identity,
                    ),
                )
        if len(winners) < context["minimum_bins"]:
            continue
        kept = unique_products(list(winners.values()))
        cost = sum(product.bytes for product in kept)
        density = len(winners) / max(cost, 1)
        openable.append((-density, group_id, len(winners), cost, kept))
    openable.sort()

    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    spent = 0
    decisions = []
    for negative_density, group_id, filled, cost, members in openable:
        before = spent
        spent, accepted = add_group_if_fits(
            members, selected, selected_ids, spent, context["budget"], context["max_products"]
        )
        decisions.append({
            "group_id": group_id,
            "filled_bins": filled,
            "density": -negative_density,
            "candidate_bytes": cost,
            "status": "selected" if accepted else "skipped",
            "budget_before_bytes": before,
            "budget_after_bytes": spent,
        })
    colors = {
        name: distributed_color(index, bin_count)
        for name, index in bin_of.items()
        if index is not None
    }
    return {"selected": selected, "decisions": decisions, "filter_colors": colors}


def select_file_knapsack(context: dict[str, Any]) -> dict[str, Any]:
    edges = context["bin_edges"]
    bin_of = {name: wavelength_bin(value, edges) for name, value in context["wavelength"].items()}
    valid = [
        product for product in context["products"]
        if product.filters and all(bin_of.get(name) is not None for name in product.filters)
    ]
    held: dict[str, set[int]] = defaultdict(set)
    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    spent = 0
    decisions = []
    iteration = 0
    while len(selected) < context["max_products"]:
        candidates = []
        for product in valid:
            if product.identity in selected_ids or spent + product.bytes > context["budget"]:
                continue
            channels = {bin_of[name] for name in product.filters}
            added = channels - held[product.group_id]
            if not added:
                continue
            before = len(held[product.group_id])
            after = len(held[product.group_id] | channels)
            completes = before < context["primary_channels"] <= after
            value = len(added) + (context["completion_bonus"] if completes else 0)
            candidates.append((-(value / product.bytes), -value, product.identity, product, channels))
        if not candidates:
            break
        _, negative_value, _, winner, channels = min(candidates)
        iteration += 1
        selected.append(winner)
        selected_ids.add(winner.identity)
        spent += winner.bytes
        held[winner.group_id].update(channels)
        decisions.append({
            "iteration": iteration,
            "identity": winner.identity,
            "group_id": winner.group_id,
            "marginal_value": -negative_value,
            "selected_bytes": winner.bytes,
            "budget_after_bytes": spent,
            "status": "selected",
        })
    bin_count = len(edges) - 1
    colors = {
        name: distributed_color(index, bin_count)
        for name, index in bin_of.items()
        if index is not None
    }
    return {"selected": selected, "decisions": decisions, "filter_colors": colors}


def conflict_color_map(
    context: dict[str, Any],
    selected: list[PreparedProduct],
    *,
    common_filter_gate: bool = False,
) -> dict[str, str]:
    """Greedily colour the selected filter-conflict graph."""

    selected_filters = {name for product in selected for name in product.filters}
    adjacency: dict[str, set[str]] = defaultdict(set)
    for members in context["groups"].values():
        names = sorted(
            selected_filters
            & {name for product in members for name in product.filters}
        )
        for left, right in combinations(names, 2):
            adjacency[left].add(right)
            adjacency[right].add(left)
    group_count = context["group_count"]
    common = sorted(selected_filters, key=lambda name: (-group_count[name], name))
    gated = common[: min(3, len(common))] if common_filter_gate else []
    remaining = sorted(
        selected_filters - set(gated),
        key=lambda name: (-len(adjacency[name]), -group_count[name], name),
    )
    order = [*gated, *remaining]
    hue_index: dict[str, int] = {}
    for filter_name in order:
        forbidden = {
            hue_index[neighbor]
            for neighbor in adjacency[filter_name]
            if neighbor in hue_index
        }
        candidate = 0
        while candidate in forbidden:
            candidate += 1
        hue_index[filter_name] = candidate
    hue_count = 1 + max(hue_index.values(), default=-1)
    palette = [CHANNEL_COLORS["blue"], CHANNEL_COLORS["green"], CHANNEL_COLORS["red"]]
    if hue_count > len(palette):
        palette.extend(
            distributed_color(index, hue_count)
            for index in range(len(palette), hue_count)
        )
    return {name: palette[index] for name, index in hue_index.items()}


def select_degree_coloring(context: dict[str, Any]) -> dict[str, Any]:
    result = select_group_rank(context)
    result["filter_colors"] = conflict_color_map(context, result["selected"])
    result["implementation_note"] = COMPARISON_NOTES["04-degree-coloring"]
    return result


def select_lp_relaxation(context: dict[str, Any]) -> dict[str, Any]:
    """Solve the budget-only fractional relaxation and round it feasibly."""

    group_count = context["group_count"]
    ranked = []
    for product in context["products"]:
        weight = sum(group_count[name] for name in product.filters)
        ranked.append((-(weight / product.bytes), -weight, product.identity, product))
    ranked.sort()
    remaining_budget = context["budget"]
    remaining_slots = context["max_products"]
    fractional = []
    for _, negative_weight, _, product in ranked:
        if remaining_budget <= 0 or remaining_slots <= 0:
            break
        fraction = min(1.0, remaining_budget / product.bytes)
        fractional.append((fraction, -negative_weight, product))
        remaining_budget -= int(fraction * product.bytes)
        remaining_slots -= 1

    selected = []
    spent = 0
    decisions = []
    for fraction, weight, product in sorted(
        fractional, key=lambda item: (-item[0], -item[1], item[2].identity)
    ):
        accepted = (
            fraction >= 1.0 - 1e-12
            and spent + product.bytes <= context["budget"]
            and len(selected) < context["max_products"]
        )
        if accepted:
            selected.append(product)
            spent += product.bytes
        decisions.append(
            {
                "identity": product.identity,
                "fractional_include": fraction,
                "weight": weight,
                "status": "selected" if accepted else "rounded_down",
                "budget_after_bytes": spent,
            }
        )
    return {
        "selected": selected,
        "decisions": decisions,
        "filter_colors": conflict_color_map(context, selected),
        "implementation_note": COMPARISON_NOTES["07-lp-relaxation"],
    }


def select_integer_program(context: dict[str, Any]) -> dict[str, Any]:
    """Solve a compact binary product/group model with SciPy MILP."""

    import numpy as np
    from scipy.optimize import Bounds, LinearConstraint, milp

    products = list(context["products"])
    group_ids = sorted(context["groups"])
    product_index = {product.identity: index for index, product in enumerate(products)}
    group_index = {group_id: len(products) + index for index, group_id in enumerate(group_ids)}
    variable_count = len(products) + len(group_ids)
    objective = np.zeros(variable_count)
    max_secondary = max(1, sum(len(product.filters) for product in products))
    group_priority = max_secondary + len(products) + 1
    for product in products:
        index = product_index[product.identity]
        objective[index] = -len(product.filters) + product.bytes / max(context["budget"], 1)
    for group_id in group_ids:
        objective[group_index[group_id]] = -group_priority

    rows = []
    lower = []
    upper = []
    budget_row = np.zeros(variable_count)
    count_row = np.zeros(variable_count)
    for product in products:
        index = product_index[product.identity]
        budget_row[index] = product.bytes
        count_row[index] = 1
    rows.extend((budget_row, count_row))
    lower.extend((-np.inf, -np.inf))
    upper.extend((context["budget"], context["max_products"]))
    for group_id in group_ids:
        members = context["groups"][group_id]
        minimum_row = np.zeros(variable_count)
        closed_row = np.zeros(variable_count)
        for product in members:
            index = product_index[product.identity]
            minimum_row[index] = -1
            closed_row[index] = 1
        minimum_row[group_index[group_id]] = context["primary_channels"]
        closed_row[group_index[group_id]] = -len(members)
        rows.extend((minimum_row, closed_row))
        lower.extend((-np.inf, -np.inf))
        upper.extend((0, 0))

    solution = milp(
        c=objective,
        integrality=np.ones(variable_count),
        bounds=Bounds(np.zeros(variable_count), np.ones(variable_count)),
        constraints=LinearConstraint(np.vstack(rows), np.array(lower), np.array(upper)),
        options={"time_limit": 30.0},
    )
    if solution.x is None:
        fallback = select_group_rank(context)
        fallback["implementation_note"] = (
            COMPARISON_NOTES["08-integer-linear-program"]
            + f" Solver status {solution.message!r}; option 02 fallback used."
        )
        return fallback
    selected = [
        product
        for product in products
        if solution.x[product_index[product.identity]] >= 0.5
    ]
    decisions = [
        {
            "group_id": group_id,
            "opened": bool(solution.x[group_index[group_id]] >= 0.5),
            "selected_product_count": int(
                sum(
                    solution.x[product_index[product.identity]] >= 0.5
                    for product in context["groups"][group_id]
                )
            ),
        }
        for group_id in group_ids
    ]
    return {
        "selected": selected,
        "decisions": decisions,
        "filter_colors": conflict_color_map(context, selected),
        "solver": {"name": "scipy.optimize.milp", "status": solution.message},
        "implementation_note": COMPARISON_NOTES["08-integer-linear-program"],
    }


def select_constraint_program(context: dict[str, Any]) -> dict[str, Any]:
    result = select_integer_program(context)
    result["filter_colors"] = conflict_color_map(
        context, result["selected"], common_filter_gate=True
    )
    result["implementation_note"] = COMPARISON_NOTES["09-constraint-program"]
    return result


def select_footprint_search(context: dict[str, Any]) -> dict[str, Any]:
    selected: list[PreparedProduct] = []
    selected_ids: set[str] = set()
    covered_cells: set[int] = set()
    selected_filters: set[str] = set()
    spent = 0
    decisions = []
    while len(selected) < context["max_products"]:
        candidates = []
        for product in context["products"]:
            if product.identity in selected_ids or spent + product.bytes > context["budget"]:
                continue
            new_cells = product.cells - covered_cells
            new_filters = product.filters - selected_filters
            benefit = (
                len(new_cells) / max(context["grid_size"], 1)
                + 0.05 * len(new_filters)
            )
            if benefit <= 0:
                continue
            score = benefit / max(product.bytes / MIB, 0.001)
            candidates.append((-score, -len(new_cells), -len(new_filters), product.identity, product))
        if not candidates:
            break
        negative_score, negative_cells, negative_filters, _, winner = min(candidates)
        selected.append(winner)
        selected_ids.add(winner.identity)
        covered_cells.update(winner.cells)
        selected_filters.update(winner.filters)
        spent += winner.bytes
        decisions.append(
            {
                "iteration": len(selected),
                "identity": winner.identity,
                "new_cells": -negative_cells,
                "new_filter_count": -negative_filters,
                "score": -negative_score,
                "budget_after_bytes": spent,
            }
        )
    colors = {
        name: distributed_color(index, max(len(selected_filters), 1))
        for index, name in enumerate(sorted(selected_filters))
    }
    return {
        "selected": selected,
        "decisions": decisions,
        "filter_colors": colors,
        "implementation_note": COMPARISON_NOTES["10-footprint-search"],
    }


SELECTORS: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {
    "01-wavelength-palette": select_wavelength_palette,
    "02-greedy-group-rank": select_group_rank,
    "03-rgb-triple-vote": select_rgb_triple,
    "04-degree-coloring": select_degree_coloring,
    "05-wavelength-bins": select_wavelength_bins,
    "06-file-knapsack": select_file_knapsack,
    "07-lp-relaxation": select_lp_relaxation,
    "08-integer-linear-program": select_integer_program,
    "09-constraint-program": select_constraint_program,
    "10-footprint-search": select_footprint_search,
}


def local_offset(ra: float, dec: float, center_ra: float, center_dec: float) -> tuple[float, float]:
    wrapped_ra = (ra - center_ra + 180.0) % 360.0 - 180.0
    return wrapped_ra * math.cos(math.radians(center_dec)) * 60.0, (dec - center_dec) * 60.0


def projected_shape(
    shape: str, numbers: tuple[float, ...], center_ra: float, center_dec: float, **style: Any
):
    if shape == "CIRCLE":
        x, y = local_offset(numbers[0], numbers[1], center_ra, center_dec)
        radius = numbers[2] * 60.0
        return Circle((x, y), radius, **style), (x - radius, x + radius, y - radius, y + radius)
    points = [
        local_offset(numbers[index], numbers[index + 1], center_ra, center_dec)
        for index in range(0, len(numbers), 2)
    ]
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return Polygon(points, closed=True, **style), (min(xs), max(xs), min(ys), max(ys))


def average_color(colors: list[str]) -> str:
    rgb = [to_rgb(color) for color in colors]
    return to_hex(tuple(sum(channel) / len(rgb) for channel in zip(*rgb))).upper()


def mix_color(color: str, target: str, amount: float) -> tuple[float, float, float]:
    """Linearly mix two colours; ``amount`` is the target-colour proportion."""

    source_rgb = to_rgb(color)
    target_rgb = to_rgb(target)
    return tuple(
        source + (destination - source) * amount
        for source, destination in zip(source_rgb, target_rgb)
    )


def texture_keys(product: PreparedProduct) -> tuple[str, str]:
    """Return stable observation and filter keys for synthetic image texture.

    Phase 1's observation-group identifier represents one aligned observation
    stack and is shared by its filter products. If it is unavailable, the CAOM
    ``obs_id`` is the fallback. The filter key changes only the small variation
    layer, leaving the dominant structure identical within the observation.
    """

    observation_key = str(
        product.row.get("observation_group_id")
        or product.row.get("obs_id")
        or product.group_id
    )
    filter_key = "+".join(sorted(product.filters)) or "UNKNOWN"
    return observation_key, filter_key


def color_plan(
    selected: list[PreparedProduct],
    filter_colors: dict[str, str],
    color_by: str,
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    legend: dict[str, str] = {}
    if color_by == "mission":
        for product in selected:
            key = str(product.row.get("obs_collection") or "UNKNOWN").upper()
            legend.setdefault(key, MISSION_COLORS.get(key, "#009E73"))
            assignments[product.identity] = legend[key]
        return assignments, legend
    if color_by == "observation-group":
        groups = group_products(selected)
        for group_id in sorted(groups):
            members = groups[group_id]
            for index, product in enumerate(members):
                key = f"{group_id} [{index + 1}/{len(members)}]"
                legend[key] = distributed_color(index, len(members))
                assignments[product.identity] = legend[key]
        return assignments, legend

    filters = sorted({name for product in selected for name in product.filters})
    fallback = {name: distributed_color(index, len(filters)) for index, name in enumerate(filters)}
    for name in filters:
        legend[name] = filter_colors.get(name, fallback[name])
    for product in selected:
        assignments[product.identity] = average_color([legend[name] for name in sorted(product.filters)])
    return assignments, legend


def add_synthetic_texture(
    axis,
    clip_patch,
    bounds: tuple[float, float, float, float],
    observation_key: str,
    filter_key: str,
    filter_color: str,
    shape_index: int,
    density: int,
    zorder: int,
) -> None:
    left, right, bottom, top = bounds
    width, height = max(right - left, 1e-6), max(top - bottom, 1e-6)

    # The large structures belong to the observation and are identical for
    # all of its filters and across repeated runs. The layers approximate the
    # visual balance of MIRI previews: a dark field, broad faint emission,
    # compact glows, many stellar points, and a smaller dust component.
    base_seed = hashlib.sha256(
        f"observation:{observation_key}:{shape_index}".encode()
    ).digest()[:8]
    rng = random.Random(int.from_bytes(base_seed, "big"))
    jitter_seed = hashlib.sha256(
        f"jitter:{observation_key}:{filter_key}:{shape_index}".encode()
    ).digest()[:8]
    jitter_rng = random.Random(int.from_bytes(jitter_seed, "big"))

    def jitter(value: float, span: float, fraction: float) -> float:
        return value + jitter_rng.uniform(-fraction, fraction) * span

    # Colourization is luminance multiplication: black stays black and the
    # brightest individual-filter pixel reaches the filter colour, never white.
    # White is reserved for balanced additive mixtures of multiple filters.
    full_tint = to_rgb(filter_color)

    # Broad, faint luminous clouds establish the large-scale morphology.
    for _ in range(max(5, density // 2)):
        center_x, center_y = rng.uniform(left, right), rng.uniform(bottom, top)
        cloud = Ellipse(
            (jitter(center_x, width, 0.018), jitter(center_y, height, 0.018)),
            width=rng.uniform(0.22, 0.85) * width,
            height=rng.uniform(0.10, 0.55) * height,
            angle=rng.uniform(0, 180) + jitter_rng.uniform(-3.0, 3.0),
            facecolor=(*full_tint, rng.uniform(0.025, 0.10)),
            edgecolor="none",
            zorder=zorder,
        )
        cloud.set_clip_path(clip_patch)
        axis.add_patch(cloud)

    # Mid-scale emission knots create several shades between black and white.
    for _ in range(max(6, density)):
        center_x, center_y = rng.uniform(left, right), rng.uniform(bottom, top)
        glow = Ellipse(
            (jitter(center_x, width, 0.014), jitter(center_y, height, 0.014)),
            width=rng.uniform(0.035, 0.24) * width,
            height=rng.uniform(0.025, 0.18) * height,
            angle=rng.uniform(0, 180),
            facecolor=(*full_tint, rng.uniform(0.04, 0.17)),
            edgecolor="none",
            zorder=zorder + 0.1,
        )
        glow.set_clip_path(clip_patch)
        axis.add_patch(glow)

    # Dust is present, but it occupies less visual area than in the first
    # renderer. This leaves room for light from multiple filters to mix.
    for _ in range(max(2, density // 5)):
        center_x, center_y = rng.uniform(left, right), rng.uniform(bottom, top)
        dust = Ellipse(
            (jitter(center_x, width, 0.012), jitter(center_y, height, 0.012)),
            width=rng.uniform(0.06, 0.26) * width,
            height=rng.uniform(0.035, 0.18) * height,
            angle=rng.uniform(0, 180),
            facecolor=(0.0, 0.0, 0.0, rng.uniform(0.08, 0.24)),
            edgecolor="none",
            zorder=zorder + 0.2,
        )
        dust.set_clip_path(clip_patch)
        axis.add_patch(dust)

    # A dense mixture of faint and bright points resembles the white stellar
    # population in the two reference MIRI JPEGs.
    scale = min(width, height)
    for _ in range(max(24, density * 5)):
        base_x, base_y = rng.uniform(left, right), rng.uniform(bottom, top)
        x = jitter(base_x, width, 0.006)
        y = jitter(base_y, height, 0.006)
        bright = rng.random() < 0.12
        radius = scale * (
            rng.uniform(0.006, 0.015) if bright else rng.uniform(0.0015, 0.005)
        )
        if bright:
            halo = Circle(
                (x, y),
                radius * rng.uniform(1.8, 3.2),
                facecolor=(*full_tint, rng.uniform(0.06, 0.18)),
                edgecolor="none",
                zorder=zorder + 0.3,
            )
            halo.set_clip_path(clip_patch)
            axis.add_patch(halo)
        star = Circle(
            (x, y),
            radius,
            facecolor=(*full_tint, rng.uniform(0.42, 0.96)),
            edgecolor="none",
            zorder=zorder + 0.4,
        )
        star.set_clip_path(clip_patch)
        axis.add_patch(star)

    # A filter contributes only a few smaller, lighter dark structures. The
    # main morphology above remains stable, while filters are not exact clones.
    variation_seed = hashlib.sha256(
        f"filter:{observation_key}:{filter_key}:{shape_index}".encode()
    ).digest()[:8]
    variation_rng = random.Random(int.from_bytes(variation_seed, "big"))
    for _ in range(max(1, density // 6)):
        variation = Ellipse(
            (variation_rng.uniform(left, right), variation_rng.uniform(bottom, top)),
            width=variation_rng.uniform(0.025, 0.11) * width,
            height=variation_rng.uniform(0.02, 0.09) * height,
            angle=variation_rng.uniform(0, 180),
            facecolor=(*full_tint, variation_rng.uniform(0.05, 0.14)),
            edgecolor="none",
            zorder=zorder + 1,
        )
        variation.set_clip_path(clip_patch)
        axis.add_patch(variation)


def additive_mix(colors: list[str]) -> tuple[float, float, float]:
    """Add filter light by channel; balanced strong channels approach white."""

    totals = [0.0, 0.0, 0.0]
    for color in colors:
        for index, value in enumerate(to_rgb(color)):
            totals[index] += value
    return tuple(min(1.0, value) for value in totals)


def add_combined_light(
    axis,
    clip_patch,
    bounds: tuple[float, float, float, float],
    observation_key: str,
    mixed_color: tuple[float, float, float],
    density: int,
    zorder: int,
) -> None:
    """Draw highlights that exist only after multiple filter lights combine."""

    left, right, bottom, top = bounds
    width, height = max(right - left, 1e-6), max(top - bottom, 1e-6)
    scale = min(width, height)
    seed = hashlib.sha256(f"combined:{observation_key}".encode()).digest()[:8]
    rng = random.Random(int.from_bytes(seed, "big"))

    for _ in range(max(3, density // 4)):
        glow = Ellipse(
            (rng.uniform(left, right), rng.uniform(bottom, top)),
            width=rng.uniform(0.08, 0.30) * width,
            height=rng.uniform(0.05, 0.22) * height,
            angle=rng.uniform(0, 180),
            facecolor=(*mixed_color, rng.uniform(0.05, 0.16)),
            edgecolor="none",
            zorder=zorder,
        )
        glow.set_clip_path(clip_patch)
        axis.add_patch(glow)

    for _ in range(max(10, density * 2)):
        x, y = rng.uniform(left, right), rng.uniform(bottom, top)
        radius = scale * rng.uniform(0.002, 0.009)
        star = Circle(
            (x, y),
            radius,
            facecolor=(*mixed_color, rng.uniform(0.38, 0.92)),
            edgecolor="none",
            zorder=zorder + 0.1,
        )
        star.set_clip_path(clip_patch)
        axis.add_patch(star)


def render_selection(
    output: Path,
    selected: list[PreparedProduct],
    config: dict[str, Any],
    filter_colors: dict[str, str],
    algorithm: str,
    color_by: str,
    texture_density: int,
    dpi: int,
) -> dict[str, Any]:
    if not selected:
        raise ValueError("selection contains no products to render")
    center_ra = float(config["ra"])
    center_dec = float(config["dec"])
    radius_arcmin = float(config["radius_degrees"]) * 60.0
    assignments, legend = color_plan(selected, filter_colors, color_by)
    product_textures = []
    combined_layers: dict[str, list[dict[str, Any]]] = defaultdict(list)
    figure, axis = plt.subplots(figsize=(11, 9), facecolor="#080A0F")
    axis.set_facecolor("#080A0F")
    axis.add_patch(
        Circle((0, 0), radius_arcmin, fill=False, edgecolor="#FFFFFF", linewidth=1.2, linestyle="--", alpha=0.7)
    )

    all_bounds = []
    for rank, product in enumerate(selected, start=1):
        color = assignments[product.identity]
        observation_key, filter_key = texture_keys(product)
        product_textures.append(
            {
                "identity": product.identity,
                "obs_id": product.row.get("obs_id"),
                "observation_texture_key": observation_key,
                "filter_variation_key": filter_key,
            }
        )
        for shape_index, (shape, numbers) in enumerate(product.shapes):
            dark_field = mix_color(color, "#000000", 0.86)
            patch, bounds = projected_shape(
                shape,
                numbers,
                center_ra,
                center_dec,
                # Keep the dark substrate translucent. With aligned products,
                # no single filter should hide the light from earlier layers.
                facecolor=(*dark_field, 0.38),
                edgecolor=to_rgba(color, 0.95),
                linewidth=1.0,
                zorder=10 + rank,
            )
            axis.add_patch(patch)
            add_synthetic_texture(
                axis,
                patch,
                bounds,
                observation_key,
                filter_key,
                color,
                shape_index,
                texture_density,
                11 + rank,
            )
            combined_layers[product.group_id].append(
                {
                    "identity": product.identity,
                    "filter_key": filter_key,
                    "color": color,
                    "patch": patch,
                    "bounds": bounds,
                    "observation_key": observation_key,
                    "zorder": 11 + rank,
                }
            )
            all_bounds.append(bounds)

    # Individual coloured layers never contain white. In a filter composite,
    # common bright regions are added afterwards using the summed RGB channel
    # proportions. Equal strong red, green, and blue can therefore reach white.
    if color_by == "filter":
        for entries in combined_layers.values():
            colors_by_filter = {
                entry["filter_key"]: entry["color"] for entry in entries
            }
            if len(colors_by_filter) < 2:
                continue
            mixed_color = additive_mix(list(colors_by_filter.values()))
            reference_identity = entries[0]["identity"]
            for reference in (
                entry for entry in entries if entry["identity"] == reference_identity
            ):
                add_combined_light(
                    axis,
                    reference["patch"],
                    reference["bounds"],
                    reference["observation_key"],
                    mixed_color,
                    texture_density,
                    max(entry["zorder"] for entry in entries) + 2,
                )

    if all_bounds:
        padding = max(radius_arcmin * 0.08, 0.05)
        axis.set_xlim(min(item[0] for item in all_bounds) - padding, max(item[1] for item in all_bounds) + padding)
        axis.set_ylim(min(item[2] for item in all_bounds) - padding, max(item[3] for item in all_bounds) + padding)
    axis.set_aspect("equal", adjustable="box")
    axis.invert_xaxis()
    axis.set_xlabel("RA offset (arcmin)", color="white")
    axis.set_ylabel("Dec offset (arcmin)", color="white")
    axis.tick_params(colors="white")
    axis.set_title(
        f"{config.get('target', 'MAST target')} — {algorithm}\n"
        "Real s_region footprints; dark field and multi-level light are simulated",
        color="white",
    )
    handles = [Patch(facecolor=color, edgecolor=color, label=key, alpha=0.75) for key, color in list(legend.items())[:24]]
    handles.append(Line2D([0], [0], color="white", linestyle="--", label="Target search radius"))
    axis.legend(handles=handles, loc="upper left", bbox_to_anchor=(1.02, 1), fontsize=7, framealpha=0.9)
    figure.text(
        0.01,
        0.01,
        "No FITS/preview pixels were downloaded. Clouds, stars, and dust are deterministic synthetic luminance.",
        color="#D0D0D0",
        fontsize=8,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=dpi, bbox_inches="tight", facecolor=figure.get_facecolor())
    plt.close(figure)
    return {
        "path": str(output),
        "color_by": color_by,
        "legend": legend,
        "texture_model": {
            "base_structure_seed": "observation_group_id; obs_id fallback",
            "filter_variation_seed": "observation key plus sorted filter names",
            "layers": [
                "dark tinted field",
                "broad faint emission",
                "mid-scale glow",
                "stellar points and halos",
                "limited dust",
                "small filter-specific emission",
                "additive multi-filter highlights (combined view only)",
            ],
            "individual_colour_rule": "output RGB = luminance times filter RGB",
            "combined_colour_rule": "clip(sum of contributing filter RGB channels)",
            "deterministic": True,
            "astronomical_pixels_used": False,
        },
        "product_textures": product_textures,
    }


def render_stage_sequence(
    output_dir: Path,
    selected: list[PreparedProduct],
    config: dict[str, Any],
    filter_colors: dict[str, str],
    algorithm: str,
    texture_density: int,
    dpi: int,
) -> dict[str, Any]:
    """Render luminance, colourized, and combined stages for review."""

    stages_dir = output_dir / "render-stages"
    stages_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for rank, product in enumerate(selected, start=1):
        label = "+".join(sorted(product.filters))
        stem = f"{rank:02d}-{safe_slug(str(product.row.get('obs_id') or product.identity))}"
        luminance_path = stages_dir / f"{stem}-luminance.png"
        colored_path = stages_dir / f"{stem}-colored.png"
        white_filters = {name: "#FFFFFF" for name in product.filters}
        render_selection(
            luminance_path,
            [product],
            config,
            white_filters,
            f"Stage 1 luminance — {label}",
            "filter",
            texture_density,
            dpi,
        )
        render_selection(
            colored_path,
            [product],
            config,
            filter_colors,
            f"Stage 2 colourized — {label}",
            "filter",
            texture_density,
            dpi,
        )
        entries.append(
            {
                "selection_rank": rank,
                "obs_id": product.row.get("obs_id"),
                "filters": sorted(product.filters),
                "luminance": str(luminance_path),
                "colored": str(colored_path),
            }
        )

    combined_path = stages_dir / "stage-3-combined.png"
    render_selection(
        combined_path,
        selected,
        config,
        filter_colors,
        f"Stage 3 combined — {algorithm}",
        "filter",
        texture_density,
        dpi,
    )

    sheet_path = stages_dir / "luminance-color-combined-comparison.png"
    figure = plt.figure(
        figsize=(15, max(8, 5 * (len(entries) + 1))),
        facecolor="#080A0F",
    )
    grid_spec = figure.add_gridspec(len(entries) + 1, 2, hspace=0.16, wspace=0.04)
    for index, entry in enumerate(entries):
        for column, key, title in (
            (0, "luminance", f"{entry['filters'][0]} — luminance"),
            (1, "colored", f"{entry['filters'][0]} — colourized"),
        ):
            axis = figure.add_subplot(grid_spec[index, column])
            axis.imshow(plt.imread(entry[key]))
            axis.set_title(title, color="white", fontsize=13)
            axis.axis("off")
    combined_axis = figure.add_subplot(grid_spec[len(entries), :])
    combined_axis.imshow(plt.imread(combined_path))
    combined_axis.set_title("Combined filter result", color="white", fontsize=15)
    combined_axis.axis("off")
    figure.suptitle(
        f"{config.get('target', 'MAST target')} — luminance → colour → combination",
        color="white",
        fontsize=18,
    )
    figure.savefig(sheet_path, dpi=max(80, min(dpi, 140)), bbox_inches="tight", facecolor=figure.get_facecolor())
    plt.close(figure)
    return {
        "directory": str(stages_dir),
        "products": entries,
        "combined": str(combined_path),
        "comparison_sheet": str(sheet_path),
    }


def selection_summary(selected: list[PreparedProduct], grid: Any) -> dict[str, Any]:
    covered = set().union(*(product.cells for product in selected)) if selected else set()
    filters = {name for product in selected for name in product.filters}
    return {
        "selected_product_count": len(selected),
        "selected_group_count": len({product.group_id for product in selected}),
        "selected_filter_count": len(filters),
        "selected_filters": sorted(filters),
        "selected_size_bytes": sum(product.bytes for product in selected),
        "selected_size_mib": round(sum(product.bytes for product in selected) / MIB, 6),
        "coverage_fraction": len(covered) / len(grid.points) if grid.points else 0.0,
        "coverage_percentage": round(100 * len(covered) / len(grid.points), 4) if grid.points else 0.0,
    }


def render_observation_sample(
    products: list[PreparedProduct],
    config: dict[str, Any],
    observation_id: str,
    requested_filter: str | None,
    output_dir: Path,
    texture_density: int,
    dpi: int,
) -> dict[str, Any]:
    """Render one real product footprint and record its source properties."""

    matches = [
        product
        for product in products
        if str(product.row.get("obs_id") or "") == observation_id
        and (
            requested_filter is None
            or requested_filter.upper() in product.filters
        )
    ]
    if not matches:
        raise ValueError(
            f"no eligible product found for obs_id={observation_id!r}"
            + (f" filter={requested_filter!r}" if requested_filter else "")
        )
    product = min(matches, key=lambda item: item.identity)
    observation_key, filter_key = texture_keys(product)
    suffix = f"-{safe_slug(requested_filter)}" if requested_filter else ""
    stem = f"sample-{safe_slug(observation_id)}{suffix}"
    image_path = output_dir / f"{stem}.png"
    render = render_selection(
        image_path,
        [product],
        config,
        {},
        f"sample observation {observation_id}",
        "filter",
        texture_density,
        dpi,
    )
    properties = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "process-graphs-observation-sample",
        "target": {
            "name": config.get("target"),
            "ra": config.get("ra"),
            "dec": config.get("dec"),
            "radius_degrees": config.get("radius_degrees"),
        },
        "product": {
            "obs_id": product.row.get("obs_id"),
            "observation_group_id": product.group_id,
            "observation_group": product.group_name,
            "identity": product.identity,
            "mission": product.row.get("obs_collection"),
            "instrument": product.row.get("instrument_name"),
            "filters": sorted(product.filters),
            "productfilename": product.row.get("productfilename"),
            "contentlength_bytes": product.bytes,
            "s_ra": product.row.get("s_ra"),
            "s_dec": product.row.get("s_dec"),
            "em_min_nm": product.row.get("em_min"),
            "em_max_nm": product.row.get("em_max"),
            "exposure_seconds": product.row.get("timexposure")
            or product.row.get("t_exptime"),
            "s_region": footprint_text(product.row),
            "parsed_shapes": [
                {"type": shape, "coordinates": list(numbers)}
                for shape, numbers in product.shapes
            ],
        },
        "synthetic_image": {
            "path": str(image_path),
            "observation_texture_key": observation_key,
            "filter_variation_key": filter_key,
            "base_structure_is_repeatable": True,
            "filter_variation_is_repeatable": True,
            "astronomical_pixels_used": False,
        },
        "render": render,
    }
    properties_path = output_dir / f"{stem}-properties.json"
    write_json(properties_path, properties)
    return {"properties": str(properties_path), "image": str(image_path), "product": properties["product"]}


def parse_edges(value: str) -> list[float]:
    edges = [float(part.strip()) for part in value.split(",") if part.strip()]
    if len(edges) < 2 or any(left >= right for left, right in zip(edges, edges[1:])):
        raise argparse.ArgumentTypeError("bin edges must be a strictly increasing comma-separated list")
    return edges


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list-algorithms", action="store_true")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--algorithm", choices=tuple(ALGORITHMS))
    parser.add_argument(
        "--sample-observation-id",
        help="Render one exact CAOM obs_id instead of running selection.",
    )
    parser.add_argument(
        "--sample-filter",
        help="Optional filter used to disambiguate a sample observation ID.",
    )
    parser.add_argument("--output-dir", type=Path, default=Path("process-graph-output"))
    parser.add_argument("--max-file-mib", type=positive_float, default=2048)
    parser.add_argument("--max-total-mib", type=positive_float, default=2000)
    parser.add_argument("--max-products", type=positive_int, default=150)
    parser.add_argument("--grid-dimension", type=positive_int, default=48)
    parser.add_argument("--primary-channels", type=positive_int, default=3)
    parser.add_argument("--blue-max-nm", type=positive_float, default=500)
    parser.add_argument("--green-max-nm", type=positive_float, default=650)
    parser.add_argument("--minimum-bins", type=positive_int, default=3)
    parser.add_argument("--completion-bonus", type=float, default=3)
    parser.add_argument(
        "--bin-edges-nm",
        type=parse_edges,
        default=parse_edges("0,300,450,600,800,2000,5000,30000"),
    )
    parser.add_argument(
        "--color-by",
        choices=("algorithm", "filter", "observation-group", "mission"),
        default="algorithm",
    )
    parser.add_argument("--texture-density", type=positive_int, default=18)
    parser.add_argument("--dpi", type=positive_int, default=180)
    parser.add_argument(
        "--render-stages",
        action="store_true",
        help="Also render each product as luminance, colourized, and combined.",
    )
    parser.add_argument(
        "--log-level", choices=("DEBUG", "INFO", "WARNING", "ERROR"), default="INFO"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.list_algorithms:
        for name, description in ALGORITHMS.items():
            print(f"implemented  {name:27s} {description}")
        return 0
    if args.input is None:
        parser.error("--input is required unless --list-algorithms is used")
    if args.algorithm is None and args.sample_observation_id is None:
        parser.error("provide --algorithm or --sample-observation-id")
    if args.algorithm is not None and args.sample_observation_id is not None:
        parser.error("use either --algorithm or --sample-observation-id, not both")

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    tap = load_tap_helpers()
    input_path = args.input.expanduser().resolve()
    config, rows = load_phase1(input_path)
    products, grid, rejected = prepare_products(
        rows,
        config,
        tap,
        args.grid_dimension,
        int(args.max_file_mib * MIB),
    )
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.sample_observation_id is not None:
        sample = render_observation_sample(
            products,
            config,
            args.sample_observation_id,
            args.sample_filter,
            output_dir,
            args.texture_density,
            args.dpi,
        )
        print(json.dumps(sample, indent=2))
        return 0

    groups = group_products(products)
    context = {
        "products": products,
        "groups": groups,
        "group_count": global_group_counts(groups),
        "wavelength": wavelength_table(products),
        "budget": int(args.max_total_mib * MIB),
        "max_products": args.max_products,
        "primary_channels": args.primary_channels,
        "blue_max": args.blue_max_nm,
        "green_max": args.green_max_nm,
        "minimum_bins": args.minimum_bins,
        "completion_bonus": args.completion_bonus,
        "bin_edges": args.bin_edges_nm,
        "grid_size": len(grid.points),
    }
    LOGGER.info(
        "Running algorithm=%s eligible_products=%s groups=%s budget_mib=%.1f",
        args.algorithm,
        len(products),
        len(groups),
        args.max_total_mib,
    )
    result = SELECTORS[args.algorithm](context)
    selected = result["selected"]
    summary = selection_summary(selected, grid)
    selection_path = output_dir / f"phase-2-{args.algorithm}-selection.json"
    selected_rows = []
    for rank, product in enumerate(selected, start=1):
        row = dict(product.row)
        row["selection_rank"] = rank
        row["selection_algorithm"] = args.algorithm
        selected_rows.append(row)
    report = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "process-graphs-phase-2-selection",
        "source": {"path": str(input_path)},
        "configuration": config,
        "algorithm": args.algorithm,
        "algorithm_description": ALGORITHMS[args.algorithm],
        "implementation_note": result.get("implementation_note"),
        "solver": result.get("solver"),
        "options": {
            "max_file_mib": args.max_file_mib,
            "max_total_mib": args.max_total_mib,
            "max_products": args.max_products,
            "grid_dimension": args.grid_dimension,
            "primary_channels": args.primary_channels,
            "blue_max_nm": args.blue_max_nm,
            "green_max_nm": args.green_max_nm,
            "minimum_bins": args.minimum_bins,
            "completion_bonus": args.completion_bonus,
            "bin_edges_nm": args.bin_edges_nm,
        },
        "summary": summary,
        "preparation": {
            "input_product_count": len(rows),
            "eligible_product_count": len(products),
            "rejected_product_count": len(rejected),
            "rejection_counts": dict(sorted(Counter(item["reason"] for item in rejected).items())),
        },
        "selected_triple": result.get("selected_triple"),
        "filter_colors": result.get("filter_colors", {}),
        "selected_products": selected_rows,
        "decisions": result.get("decisions", []),
    }
    write_json(selection_path, report)
    color_by = "filter" if args.color_by == "algorithm" else args.color_by
    image_path = output_dir / f"phase-2-{args.algorithm}-footprints.png"
    render = render_selection(
        image_path,
        selected,
        config,
        result.get("filter_colors", {}),
        args.algorithm,
        color_by,
        args.texture_density,
        args.dpi,
    )
    if args.render_stages:
        render["stages"] = render_stage_sequence(
            output_dir,
            selected,
            config,
            result.get("filter_colors", {}),
            args.algorithm,
            args.texture_density,
            args.dpi,
        )
    write_json(output_dir / f"phase-2-{args.algorithm}-render.json", render)
    LOGGER.info(
        "Complete products=%s groups=%s filters=%s MiB=%.2f coverage=%.2f%%",
        summary["selected_product_count"],
        summary["selected_group_count"],
        summary["selected_filter_count"],
        summary["selected_size_mib"],
        summary["coverage_percentage"],
    )
    print(json.dumps({"selection": str(selection_path), "render": str(image_path), "summary": summary}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
