#!/usr/bin/env python3
"""Render MAST science-product footprints from a greedy selection report.

The left panel shows every product that passes the greedy selector's compulsory
metadata checks. The right panel shows only the selected products. Footprints
are projected as local sky offsets around the report target so CAOM ``CIRCLE``
and ``POLYGON`` regions can be compared on one image without downloading FITS
pixels or headers.

Example:
    MPLCONFIGDIR=/private/tmp/matplotlib-cache \
    .venv/bin/python Sources/scripts/plot_mast_science_product_footprints.py \
        Resources/results/ngc628-greedy-10gb.json \
        --color-by filter \
        --output Resources/results/ngc628-science-product-footprints.png \
        --svg-output Resources/results/ngc628-science-product-footprints.svg
"""

from __future__ import annotations

import argparse
import colorsys
import json
import math
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import to_hex, to_rgba
    from matplotlib.lines import Line2D
    from matplotlib.patches import Circle, Patch, Polygon
except ImportError as error:  # pragma: no cover - depends on the caller's environment
    raise SystemExit("matplotlib is required: python3 -m pip install matplotlib") from error

from greedy_mast_tap_selection import (
    filter_keys,
    observation_group_key,
    parse_s_region,
    wrapped_degrees,
)


MIB = 1_048_576
MISSION_COLORS = {
    "JWST": "#CC79A7",
    "HST": "#0072B2",
    "HLA": "#E69F00",
}
FALLBACK_COLOR = "#009E73"
COLOR_BY_OPTIONS = ("filter", "observation-group", "mission")
HEX_COLOR = re.compile(r"^#?[0-9A-Fa-f]{6}$")


@dataclass(frozen=True)
class DrawableProduct:
    """One eligible product and its parsed CAOM footprint."""

    product: dict[str, Any]
    identity: str
    mission: str
    group_id: tuple[str, str, str]
    filters: tuple[str, ...]
    shapes: tuple[tuple[str, tuple[float, ...]], ...]
    selected: bool


@dataclass(frozen=True)
class ColorKeyEntry:
    """One deterministic category-to-colour assignment."""

    key: str
    label: str
    short_label: str
    index: int
    count: int
    color: str
    hue_degrees: float | None
    source: str
    eligible_product_count: int
    selected_product_count: int

    def as_dict(self) -> dict[str, Any]:
        """Return a JSON-ready description for debugging and AOSImage comparison."""

        return {
            "key": self.key,
            "label": self.label,
            "short_label": self.short_label,
            "index": self.index,
            "count": self.count,
            "color": self.color,
            "hue_degrees": self.hue_degrees,
            "source": self.source,
            "eligible_product_count": self.eligible_product_count,
            "selected_product_count": self.selected_product_count,
        }


@dataclass(frozen=True)
class ColorPlan:
    """Colour key plus panel-specific product assignments."""

    entries: tuple[ColorKeyEntry, ...]
    lookup: dict[str, ColorKeyEntry]
    eligible_assignments: dict[str, tuple[str, ...]]
    selected_assignments: dict[str, tuple[str, ...]]


def distributed_hue_degrees(index: int, count: int) -> float:
    """Match ``AOSColorPalette.distributedHueDegrees`` exactly."""

    if count <= 0:
        return 0.0
    return ((300.0 - 180.0 / count) + index / count * 360.0 + 360.0) % 360.0


def distributed_color(index: int, count: int) -> tuple[float, str]:
    """Return the AOSImage fallback hue and full-saturation/value RGB hex."""

    hue = distributed_hue_degrees(index, count)
    red, green, blue = colorsys.hsv_to_rgb(hue / 360.0, 1.0, 1.0)
    return hue, to_hex((red, green, blue), keep_alpha=False).upper()


def load_preferred_colors(path: Path | None) -> dict[str, str]:
    """Load optional catalog-style ``category: #RRGGBB`` overrides."""

    if path is None:
        return {}
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("--preferred-colors must contain a JSON object")
    output: dict[str, str] = {}
    for raw_key, raw_color in decoded.items():
        key = str(raw_key)
        color = str(raw_color)
        if HEX_COLOR.fullmatch(color) is None:
            raise ValueError(
                f"invalid preferred hex colour for {key!r}: {color!r}; use #RRGGBB"
            )
        output[key] = "#" + color.lstrip("#").upper()
    return output


def product_identity(product: dict[str, Any]) -> str:
    """Return the same stable identity used by the greedy selector."""

    data_uri = str(product.get("datauri") or "").strip()
    if data_uri:
        return data_uri
    return "\x1f".join(
        str(product.get(key) or "")
        for key in ("obs_collection", "obs_id", "instrument_name", "filters")
    )


def selected_identities(report: dict[str, Any]) -> set[str]:
    """Return the selected product identities recorded in the report."""

    selection = report.get("selection") or {}
    return {
        product_identity(product)
        for product in selection.get("selected_products", [])
        if isinstance(product, dict)
    }


def eligible_products(report: dict[str, Any]) -> list[DrawableProduct]:
    """Reapply the selector's compulsory checks to the report's fetched rows."""

    selected = selected_identities(report)
    maximum_size = int(
        (report.get("query_strategy") or {}).get("max_product_size_bytes")
        or 300 * MIB
    )
    seen_by_mission: dict[str, set[str]] = {}
    drawables: list[DrawableProduct] = []

    for product in report.get("rows", []):
        if not isinstance(product, dict):
            continue
        mission = str(product.get("obs_collection") or "UNKNOWN").strip().upper()
        identity = product_identity(product)
        seen = seen_by_mission.setdefault(mission, set())
        if identity in seen:
            continue
        seen.add(identity)

        data_uri = str(product.get("datauri") or "").strip()
        instrument = str(product.get("instrument_name") or "").strip().upper()
        try:
            size = int(product.get("contentlength"))
        except (TypeError, ValueError):
            continue
        shapes = parse_s_region(str(product.get("s_region") or "").strip())
        filters = tuple(sorted(filter_keys(product.get("filters"))))
        if (
            not data_uri
            or not instrument
            or size <= 0
            or size > maximum_size
            or shapes is None
            or not filters
        ):
            continue

        key = (
            mission,
            instrument,
            str(product.get("observation_key") or observation_group_key(product)),
        )
        drawables.append(
            DrawableProduct(
                product=product,
                identity=identity,
                mission=mission,
                group_id=key,
                filters=filters,
                shapes=shapes,
                selected=identity in selected,
            )
        )
    return drawables


def natural_key(value: str) -> tuple[Any, ...]:
    """Sort filter and observation names predictably when they contain numbers."""

    return tuple(
        int(part) if part.isdigit() else part.upper()
        for part in re.split(r"(\d+)", value)
    )


def group_category_key(group_id: tuple[str, str, str]) -> str:
    """Encode a group tuple as a stable colour-key identifier."""

    return " | ".join(group_id)


def drawable_category_keys(
    drawable: DrawableProduct,
    color_by: str,
) -> tuple[str, ...]:
    """Return global mission/filter categories used to draw a product."""

    if color_by == "mission":
        return (drawable.mission,)
    if color_by == "observation-group":
        raise ValueError("observation-group colours require group-local assignment")
    return drawable.filters


def build_color_key(
    drawables: list[DrawableProduct],
    color_by: str,
    preferred_colors: dict[str, str],
) -> tuple[list[ColorKeyEntry], dict[str, ColorKeyEntry]]:
    """Assign deterministic colours and usage counts to every plotted category."""

    if color_by not in {"filter", "mission"}:
        raise ValueError(f"unsupported --color-by value: {color_by}")

    categories: set[str] = set()
    eligible_counts: Counter[str] = Counter()
    selected_counts: Counter[str] = Counter()
    for drawable in drawables:
        keys = drawable_category_keys(drawable, color_by)
        for key in keys:
            categories.add(key)
            eligible_counts[key] += 1
            if drawable.selected:
                selected_counts[key] += 1
    ordered = sorted(categories, key=natural_key)

    count = len(ordered)
    entries: list[ColorKeyEntry] = []
    for index, key in enumerate(ordered):
        if color_by == "mission":
            hue = None
            color = MISSION_COLORS.get(key, FALLBACK_COLOR)
            source = "fixed_mission_palette"
            label = key
            short_label = key
        else:
            hue, color = distributed_color(index, count)
            source = "aosimage_distributed_hsv"
            label = key
            short_label = key

        preferred = (
            preferred_colors.get(key)
            or preferred_colors.get(label)
            or preferred_colors.get(short_label)
        )
        if preferred is not None:
            color = preferred
            source = "preferred_hex"

        entries.append(
            ColorKeyEntry(
                key=key,
                label=label,
                short_label=short_label,
                index=index,
                count=count,
                color=color,
                hue_degrees=round(hue, 9) if hue is not None else None,
                source=source,
                eligible_product_count=eligible_counts[key],
                selected_product_count=selected_counts[key],
            )
        )
    return entries, {entry.key: entry for entry in entries}


def product_order_key(drawable: DrawableProduct) -> tuple[Any, ...]:
    """Order products deterministically inside one observation stack."""

    filter_label = "+".join(drawable.filters)
    observation_id = str(drawable.product.get("obs_id") or "")
    return natural_key(filter_label), natural_key(observation_id), drawable.identity


def preferred_product_color(
    drawable: DrawableProduct,
    preferred_colors: dict[str, str],
) -> tuple[str, str] | None:
    """Resolve an optional product/filter override like AOSImage's preferred hex."""

    candidates = (
        drawable.identity,
        group_category_key(drawable.group_id),
        *drawable.filters,
    )
    for key in candidates:
        color = preferred_colors.get(key)
        if color is not None:
            return key, color
    return None


def _products_by_group(
    drawables: list[DrawableProduct],
) -> dict[tuple[str, str, str], list[DrawableProduct]]:
    """Partition drawable products by their observation-stack identity."""

    groups: dict[tuple[str, str, str], list[DrawableProduct]] = {}
    for drawable in drawables:
        groups.setdefault(drawable.group_id, []).append(drawable)
    return groups


def assign_group_local_colors(
    drawables: list[DrawableProduct],
    preferred_colors: dict[str, str],
) -> tuple[
    dict[str, tuple[str, ...]],
    Counter[str],
    dict[str, tuple[int, int]],
    dict[str, tuple[str, str]],
]:
    """Reset the AOSImage palette inside every observation group.

    A group with ``count`` science products receives indices ``0..<count``.
    Consequently, every one-product group is green, every two-product group is
    blue/orange, and so on. Preferred product/filter hex values override only
    the matching product's generated fallback colour.
    """

    groups = _products_by_group(drawables)

    assignments: dict[str, tuple[str, ...]] = {}
    counts: Counter[str] = Counter()
    local_positions: dict[str, tuple[int, int]] = {}
    preferred_entries: dict[str, tuple[str, str]] = {}
    for members in groups.values():
        ordered = sorted(members, key=product_order_key)
        count = len(ordered)
        for index, drawable in enumerate(ordered):
            preferred = preferred_product_color(drawable, preferred_colors)
            if preferred is None:
                key = f"N{count}:P{index + 1}"
            else:
                preferred_key, color = preferred
                key = f"preferred:{preferred_key}"
                preferred_entries[key] = preferred_key, color
            assignments[drawable.identity] = (key,)
            counts[key] += 1
            local_positions[drawable.identity] = index, count
    return assignments, counts, local_positions, preferred_entries


def local_palette_sort_key(key: str) -> tuple[Any, ...]:
    """Sort generated N<count>:P<position> entries before preferred overrides."""

    match = re.fullmatch(r"N(\d+):P(\d+)", key)
    if match is not None:
        return 0, int(match.group(1)), int(match.group(2))
    return 1, key


def build_observation_group_color_plan(
    drawables: list[DrawableProduct],
    preferred_colors: dict[str, str],
) -> ColorPlan:
    """Build independent eligible/selected palettes for every observation group."""

    eligible_assignments, eligible_counts, _, eligible_preferred = assign_group_local_colors(
        drawables, preferred_colors
    )
    selected_drawables = [drawable for drawable in drawables if drawable.selected]
    selected_assignments, selected_counts, _, selected_preferred = assign_group_local_colors(
        selected_drawables, preferred_colors
    )
    preferred_entries = {**eligible_preferred, **selected_preferred}
    keys = sorted(
        set(eligible_counts) | set(selected_counts),
        key=local_palette_sort_key,
    )
    entries: list[ColorKeyEntry] = []
    for key in keys:
        match = re.fullmatch(r"N(\d+):P(\d+)", key)
        if match is not None:
            count = int(match.group(1))
            position = int(match.group(2))
            index = position - 1
            hue, color = distributed_color(index, count)
            source = "aosimage_group_local_hsv"
            label = f"{count} products / position {position}"
            short_label = f"N{count}·P{position}"
        else:
            preferred_key, color = preferred_entries[key]
            count = 0
            index = -1
            hue = None
            source = "preferred_hex"
            label = f"Preferred {preferred_key}"
            short_label = preferred_key
        entries.append(
            ColorKeyEntry(
                key=key,
                label=label,
                short_label=short_label,
                index=index,
                count=count,
                color=color,
                hue_degrees=round(hue, 9) if hue is not None else None,
                source=source,
                eligible_product_count=eligible_counts[key],
                selected_product_count=selected_counts[key],
            )
        )
    lookup = {entry.key: entry for entry in entries}
    return ColorPlan(
        entries=tuple(entries),
        lookup=lookup,
        eligible_assignments=eligible_assignments,
        selected_assignments=selected_assignments,
    )


def build_color_plan(
    drawables: list[DrawableProduct],
    color_by: str,
    preferred_colors: dict[str, str],
) -> ColorPlan:
    """Build global filter/mission colours or group-local product palettes."""

    if color_by == "observation-group":
        return build_observation_group_color_plan(drawables, preferred_colors)
    entries, lookup = build_color_key(drawables, color_by, preferred_colors)
    eligible_assignments = {
        drawable.identity: drawable_category_keys(drawable, color_by)
        for drawable in drawables
    }
    return ColorPlan(
        entries=tuple(entries),
        lookup=lookup,
        eligible_assignments=eligible_assignments,
        selected_assignments={
            drawable.identity: eligible_assignments[drawable.identity]
            for drawable in drawables
            if drawable.selected
        },
    )


def observation_group_assignment_records(
    drawables: list[DrawableProduct],
    assignments: dict[str, tuple[str, ...]],
    color_key: dict[str, ColorKeyEntry],
) -> list[dict[str, Any]]:
    """Describe each stack's local product order and resolved colours."""

    groups = _products_by_group(drawables)
    records: list[dict[str, Any]] = []
    for group_id, members in sorted(groups.items()):
        products = []
        ordered = sorted(members, key=product_order_key)
        for fallback_index, drawable in enumerate(ordered):
            key = assignments[drawable.identity][0]
            entry = color_key[key]
            products.append(
                {
                    "position": fallback_index + 1,
                    "product_count": len(ordered),
                    "observation_id": drawable.product.get("obs_id"),
                    "product_uri": drawable.product.get("datauri"),
                    "filters": list(drawable.filters),
                    "palette_key": key,
                    "hue_degrees": entry.hue_degrees,
                    "color": entry.color,
                    "source": entry.source,
                }
            )
        records.append(
            {
                "mission": group_id[0],
                "instrument": group_id[1],
                "observation_key": group_id[2],
                "product_count": len(ordered),
                "products": products,
            }
        )
    return records


def local_offset(
    ra: float,
    dec: float,
    center_ra: float,
    center_dec: float,
) -> tuple[float, float]:
    """Project ICRS coordinates to small-angle offsets in arcminutes."""

    x = wrapped_degrees(ra - center_ra) * math.cos(math.radians(center_dec)) * 60.0
    y = (dec - center_dec) * 60.0
    return x, y


def shape_bounds(
    shape: str,
    numbers: tuple[float, ...],
    center_ra: float,
    center_dec: float,
) -> tuple[float, float, float, float]:
    """Return local x/y bounds for one parsed footprint component."""

    if shape == "CIRCLE":
        x, y = local_offset(numbers[0], numbers[1], center_ra, center_dec)
        radius = numbers[2] * 60.0
        return x - radius, x + radius, y - radius, y + radius

    points = [
        local_offset(numbers[index], numbers[index + 1], center_ra, center_dec)
        for index in range(0, len(numbers), 2)
    ]
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), max(xs), min(ys), max(ys)


def add_shape(
    axis: Any,
    shape: str,
    numbers: tuple[float, ...],
    center_ra: float,
    center_dec: float,
    *,
    edgecolor: str,
    facecolor: str,
    edge_alpha: float,
    face_alpha: float,
    linewidth: float,
    zorder: int,
) -> None:
    """Add one CAOM circle or polygon to a Matplotlib axis."""

    common = {
        "edgecolor": to_rgba(edgecolor, edge_alpha),
        "facecolor": "none" if facecolor == "none" else to_rgba(facecolor, face_alpha),
        "linewidth": linewidth,
        "zorder": zorder,
    }
    if shape == "CIRCLE":
        x, y = local_offset(numbers[0], numbers[1], center_ra, center_dec)
        axis.add_patch(Circle((x, y), numbers[2] * 60.0, **common))
        return

    points = [
        local_offset(numbers[index], numbers[index + 1], center_ra, center_dec)
        for index in range(0, len(numbers), 2)
    ]
    axis.add_patch(Polygon(points, closed=True, **common))


def draw_product(
    axis: Any,
    drawable: DrawableProduct,
    center_ra: float,
    center_dec: float,
    *,
    emphasize: bool,
    assignment_keys: tuple[str, ...],
    color_key: dict[str, ColorKeyEntry],
) -> None:
    """Draw every component belonging to one product footprint."""

    colors = [
        color_key[key].color
        for key in assignment_keys
        if key in color_key
    ]
    if not colors:
        colors = [FALLBACK_COLOR]
    for shape, numbers in drawable.shapes:
        # Fill once, then layer coloured outlines. Multiple filter tokens on one
        # product remain visible as nested outline widths rather than silently
        # dropping every token except the first.
        add_shape(
            axis,
            shape,
            numbers,
            center_ra,
            center_dec,
            edgecolor=colors[0],
            facecolor=colors[0],
            edge_alpha=0.0,
            face_alpha=0.18 if emphasize else 0.055,
            linewidth=0.0,
            zorder=4 if emphasize else 2,
        )
        for position, color in enumerate(reversed(colors)):
            add_shape(
                axis,
                shape,
                numbers,
                center_ra,
                center_dec,
                edgecolor=color,
                facecolor="none",
                edge_alpha=0.78 if emphasize else 0.32,
                face_alpha=0.0,
                linewidth=(1.05 if emphasize else 0.45) + 0.65 * (len(colors) - position - 1),
                zorder=5 if emphasize else 3,
            )


def calculate_extent(
    drawables: Iterable[DrawableProduct],
    center_ra: float,
    center_dec: float,
    radius_arcminutes: float,
) -> tuple[float, float, float, float]:
    """Fit every eligible footprint and the target circle in a shared extent."""

    bounds = [
        shape_bounds(shape, numbers, center_ra, center_dec)
        for drawable in drawables
        for shape, numbers in drawable.shapes
    ]
    bounds.append(
        (-radius_arcminutes, radius_arcminutes, -radius_arcminutes, radius_arcminutes)
    )
    minimum_x = min(value[0] for value in bounds)
    maximum_x = max(value[1] for value in bounds)
    minimum_y = min(value[2] for value in bounds)
    maximum_y = max(value[3] for value in bounds)
    padding = max(maximum_x - minimum_x, maximum_y - minimum_y) * 0.055
    return (
        minimum_x - padding,
        maximum_x + padding,
        minimum_y - padding,
        maximum_y + padding,
    )


def configure_axis(
    axis: Any,
    *,
    title: str,
    subtitle: str,
    extent: tuple[float, float, float, float],
    radius_arcminutes: float,
) -> None:
    """Apply the shared target boundary, projection, labels, and grid."""

    axis.add_patch(
        Circle(
            (0.0, 0.0),
            radius_arcminutes,
            facecolor="#ECEFF1",
            edgecolor="#222222",
            linewidth=1.4,
            linestyle=(0, (5, 4)),
            alpha=0.55,
            zorder=0,
        )
    )
    axis.scatter([0.0], [0.0], marker="+", s=38, linewidths=1.3, color="#222222", zorder=7)
    axis.set_title(f"{title}\n{subtitle}", fontsize=12, fontweight="normal", pad=10)
    axis.set_xlabel("Right-ascension offset (arcmin; east is left)")
    axis.set_ylabel("Declination offset (arcmin)")
    axis.set_xlim(extent[1], extent[0])
    axis.set_ylim(extent[2], extent[3])
    axis.set_aspect("equal", adjustable="box")
    axis.grid(True, color="#B0BEC5", linewidth=0.45, alpha=0.36)
    axis.set_axisbelow(True)


def render_report(
    report: dict[str, Any],
    output: Path,
    *,
    svg_output: Path | None,
    color_key_output: Path,
    color_by: str,
    preferred_colors: dict[str, str],
    dpi: int,
) -> dict[str, Any]:
    """Render the report and return a compact machine-readable plot summary."""

    position = report.get("position") or {}
    try:
        center_ra = float(position["ra"])
        center_dec = float(position["dec"])
        radius_degrees = float(position["radius_degrees"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("report.position must contain ra, dec, and radius_degrees") from error

    selection = report.get("selection")
    if not isinstance(selection, dict):
        raise ValueError("the report must contain a greedy selection result")

    drawables = eligible_products(report)
    if not drawables:
        raise ValueError("the report contains no drawable eligible products")
    selected = [drawable for drawable in drawables if drawable.selected]
    unselected = [drawable for drawable in drawables if not drawable.selected]
    color_plan = build_color_plan(drawables, color_by, preferred_colors)
    color_entries = list(color_plan.entries)
    color_key = color_plan.lookup
    radius_arcminutes = radius_degrees * 60.0
    extent = calculate_extent(drawables, center_ra, center_dec, radius_arcminutes)

    selected_groups = {drawable.group_id for drawable in selected}
    eligible_groups = {drawable.group_id for drawable in drawables}
    coverage = float((selection.get("summary") or {}).get("coverage_percentage") or 0.0)
    selected_mib = float((selection.get("summary") or {}).get("selected_size_mib") or 0.0)
    target_name = str(report.get("target") or "Coordinate target")

    large_key = len(color_entries) > 6
    figure_height = 10.4 if large_key else 8.4
    bottom_margin = 0.255 if large_key else 0.145
    figure, axes = plt.subplots(1, 2, figsize=(16, figure_height), sharex=True, sharey=True)
    figure.subplots_adjust(
        left=0.065,
        right=0.985,
        top=0.855,
        bottom=bottom_margin,
        wspace=0.16,
    )
    figure.suptitle(
        f"{target_name} science-product sky footprints",
        fontsize=17,
        fontweight="normal",
        y=0.96,
    )
    figure.text(
        0.5,
        0.918,
        f"ICRS centre RA {center_ra:.6f}°, Dec {center_dec:.6f}° • "
        f"target radius {radius_arcminutes:.1f} arcmin • colour by {color_by}",
        ha="center",
        va="center",
        fontsize=10,
        color="#455A64",
    )

    configure_axis(
        axes[0],
        title="Eligible candidate frontier",
        subtitle=f"{len(drawables)} products • {len(eligible_groups)} observation groups",
        extent=extent,
        radius_arcminutes=radius_arcminutes,
    )
    for drawable in unselected:
        draw_product(
            axes[0],
            drawable,
            center_ra,
            center_dec,
            emphasize=False,
            assignment_keys=color_plan.eligible_assignments[drawable.identity],
            color_key=color_key,
        )
    for drawable in selected:
        draw_product(
            axes[0],
            drawable,
            center_ra,
            center_dec,
            emphasize=True,
            assignment_keys=color_plan.eligible_assignments[drawable.identity],
            color_key=color_key,
        )

    configure_axis(
        axes[1],
        title="Greedy-selected footprints",
        subtitle=(
            f"{len(selected)} products • {len(selected_groups)} groups • "
            f"{coverage:.2f}% target coverage • {selected_mib:.1f} MiB"
        ),
        extent=extent,
        radius_arcminutes=radius_arcminutes,
    )
    for drawable in selected:
        draw_product(
            axes[1],
            drawable,
            center_ra,
            center_dec,
            emphasize=True,
            assignment_keys=color_plan.selected_assignments[drawable.identity],
            color_key=color_key,
        )

    legend_limit = 36 if color_by == "filter" else 24
    if len(color_entries) <= legend_limit:
        visible_entries = color_entries
    else:
        visible_entries = sorted(
            color_entries,
            key=lambda entry: (
                -entry.selected_product_count,
                -entry.eligible_product_count,
                entry.index,
            ),
        )[:legend_limit]
    category_handles = [
        Patch(
            facecolor=entry.color,
            edgecolor=entry.color,
            alpha=0.42,
            label=(
                (
                    f"{entry.short_label}  "
                    if color_by == "observation-group"
                    else f"{entry.index + 1:02d} {entry.short_label}  "
                )
                + f"E{entry.eligible_product_count}/S{entry.selected_product_count}"
            ),
        )
        for entry in visible_entries
    ]
    if len(visible_entries) < len(color_entries):
        category_handles.append(
            Line2D(
                [],
                [],
                color="none",
                label=f"+{len(color_entries) - len(visible_entries)} more in colour-key JSON",
            )
        )
    style_handles = [
        Line2D([0], [0], color="#455A64", linewidth=0.6, alpha=0.45, label="Eligible outline"),
        Line2D([0], [0], color="#263238", linewidth=1.4, alpha=0.8, label="Selected emphasis"),
        Line2D([0], [0], color="#222222", linewidth=1.4, linestyle=(0, (5, 4)), label="Target boundary"),
    ]
    legend_columns = 6 if large_key else len(category_handles) + len(style_handles)
    legend_title = (
        f"AOSImage group-local palette: {len(color_entries)} used positions • "
        "E = eligible products, S = selected products"
        if color_by == "observation-group"
        else (
            f"Colour key: {len(color_entries)} {color_by} categories • "
            "E = eligible products, S = selected products"
        )
    )
    figure.legend(
        handles=category_handles + style_handles,
        loc="lower center",
        bbox_to_anchor=(0.5, 0.046 if large_key else 0.052),
        ncol=legend_columns,
        frameon=False,
        fontsize=8.2 if large_key else 9,
        title=legend_title,
        title_fontsize=9,
    )
    figure.text(
        0.5,
        0.012,
        (
            "Each observation group resets the AOSImage palette; overlapping layers show its colour combination."
            if color_by == "observation-group"
            else "Footprints come from CAOM s_region metadata; darker intersections show spatial overlap."
        ),
        ha="center",
        va="bottom",
        fontsize=9,
        color="#546E7A",
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=dpi, facecolor="white", bbox_inches="tight")
    if svg_output is not None:
        svg_output.parent.mkdir(parents=True, exist_ok=True)
        figure.savefig(svg_output, format="svg", facecolor="white", bbox_inches="tight")
    plt.close(figure)

    color_key_output.parent.mkdir(parents=True, exist_ok=True)
    color_key_payload: dict[str, Any] = {
        "color_by": color_by,
        "category_count": len(color_entries),
        "assignment_scope": (
            "observation_group_local_science_products"
            if color_by == "observation-group"
            else "global_categories"
        ),
        "fallback_algorithm": "aosimage_distributed_hsv",
        "fallback_formula": (
            "hue = (300 - 180/count + index * 360/count) mod 360"
        ),
        "fallback_saturation": 1.0,
        "fallback_brightness": 1.0,
        "preferred_hex_overrides_fallback": True,
        "categories": [entry.as_dict() for entry in color_entries],
    }
    if color_by == "observation-group":
        eligible_group_sizes = Counter(
            len(members)
            for members in _products_by_group(drawables).values()
        )
        selected_group_sizes = Counter(
            len(members)
            for members in _products_by_group(selected).values()
        )
        color_key_payload.update(
            {
                "eligible_group_size_distribution": dict(sorted(eligible_group_sizes.items())),
                "selected_group_size_distribution": dict(sorted(selected_group_sizes.items())),
                "eligible_observation_groups": observation_group_assignment_records(
                    drawables,
                    color_plan.eligible_assignments,
                    color_key,
                ),
                "selected_observation_groups": observation_group_assignment_records(
                    selected,
                    color_plan.selected_assignments,
                    color_key,
                ),
            }
        )
    color_key_output.write_text(
        json.dumps(
            color_key_payload,
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    shape_counts = Counter(
        shape for drawable in drawables for shape, _ in drawable.shapes
    )
    return {
        "input_row_count": len(report.get("rows", [])),
        "eligible_product_count": len(drawables),
        "eligible_observation_group_count": len(eligible_groups),
        "selected_product_count": len(selected),
        "selected_observation_group_count": len(selected_groups),
        "color_by": color_by,
        "color_category_count": len(color_entries),
        "color_assignment_scope": color_key_payload["assignment_scope"],
        "color_key_output": str(color_key_output),
        "shape_component_counts": dict(sorted(shape_counts.items())),
        "output": str(output),
        "svg_output": str(svg_output) if svg_output is not None else None,
    }


def parse_args() -> argparse.Namespace:
    """Parse report and output paths for the footprint renderer."""

    parser = argparse.ArgumentParser(
        description="Plot eligible and greedy-selected MAST CAOM science-product footprints."
    )
    parser.add_argument("report", type=Path, help="Greedy MAST TAP selection JSON report.")
    parser.add_argument("--output", type=Path, help="PNG/PDF/SVG output path.")
    parser.add_argument("--svg-output", type=Path, help="Optional additional vector SVG output.")
    parser.add_argument(
        "--color-by",
        choices=COLOR_BY_OPTIONS,
        default="filter",
        help="Footprint colour category (default: filter).",
    )
    parser.add_argument(
        "--preferred-colors",
        type=Path,
        help="Optional JSON object mapping category names to preferred #RRGGBB colours.",
    )
    parser.add_argument(
        "--color-key-output",
        type=Path,
        help="Colour assignment JSON path; defaults beside the rendered image.",
    )
    parser.add_argument("--dpi", type=int, default=180, help="Raster output resolution (default: 180).")
    return parser.parse_args()


def main() -> int:
    """Load the greedy report and render its sky-footprint overview."""

    args = parse_args()
    if args.dpi <= 0:
        raise ValueError("--dpi must be greater than zero")
    report = json.loads(args.report.read_text(encoding="utf-8"))
    output = args.output or args.report.with_name(f"{args.report.stem}-footprints.png")
    color_key_output = args.color_key_output or output.with_name(
        f"{output.stem}-colors.json"
    )
    summary = render_report(
        report,
        output,
        svg_output=args.svg_output,
        color_key_output=color_key_output,
        color_by=args.color_by,
        preferred_colors=load_preferred_colors(args.preferred_colors),
        dpi=args.dpi,
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"error: {error}") from error
