#!/usr/bin/env python3
"""Qualify, select, and visualize MAST mosaics for a multi-filter composite.

Phase 1 (``qualify``) performs TAP metadata queries and creates a reviewable
set of observation groups. Phase 2 (``select``) is offline: it reads Phase 1,
applies group-aware greedy selection, and emits a Phase 3 download manifest.
``render`` plots the selected CAOM sky footprints and their colour assignments.
No FITS pixels are downloaded by this script.

Example::

    python Sources/scripts/mast_composite_pipeline.py render \
      --input research/pipeline-runs/ngc628/phase-2-download-manifest.json \
      --color-by filter

The renderer can colour footprints by ``filter``, ``observation-group``, or
``mission``. Observation-group mode resets the AOSImage fallback palette in
each image stack, so the overlapping product colours preview that stack's
composition.
"""

from __future__ import annotations

import argparse
import colorsys
import csv
import hashlib
import importlib.util
import json
import logging
import math
import re
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import to_hex, to_rgba
from matplotlib.lines import Line2D
from matplotlib.patches import Circle as MatCircle
from matplotlib.patches import Patch
from matplotlib.patches import Polygon as MatPolygon


SCHEMA_VERSION = 1
MIB = 1_048_576
ROOT = Path(__file__).resolve().parents[2]
GREEDY_PATH = Path(__file__).with_name("greedy_mast_tap_selection.py")
LOGGER = logging.getLogger("swiftmast.composite_pipeline")
QUALITY_COLUMNS = (
    ("timexposure", "p.timexposure"),
    ("mtrmaglimit", "p.mtrmaglimit"),
    ("posresolution", "p.posresolution"),
)
EXTRA_COLUMNS = (
    "p.posboundsstcs AS posboundsstcs",
    "a.contentchecksum AS contentchecksum",
    *(f"{expression} AS {name}" for name, expression in QUALITY_COLUMNS),
)
COLOR_BY_OPTIONS = ("filter", "observation-group", "mission")
MISSION_COLORS = {
    "JWST": "#CC79A7",
    "HST": "#0072B2",
    "HLA": "#E69F00",
}
FALLBACK_COLOR = "#009E73"
HEX_COLOR = re.compile(r"^#?[0-9A-Fa-f]{6}$")


def load_greedy():
    """Load production TAP/geometry helpers without invoking its CLI."""

    spec = importlib.util.spec_from_file_location("swiftmast_greedy", GREEDY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {GREEDY_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(MIB), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_slug(value: str) -> str:
    text = "".join(char.lower() if char.isalnum() else "-" for char in value)
    return "-".join(part for part in text.split("-") if part) or "coordinates"


def cached_rows(tap, path: Path, adql: str, timeout: float, retries: int) -> list[dict[str, Any]]:
    """Read an exact-ADQL cache hit, otherwise call TAP and store named rows."""

    if path.exists():
        cached = read_json(path)
        if cached.get("adql") == adql:
            LOGGER.info("TAP cache hit path=%s rows=%s", path, len(cached.get("rows", [])))
            return cached["rows"]
    response = tap.query_tap(adql, timeout=timeout, retries=retries)
    rows = [
        {str(key).lower(): value for key, value in row.items()}
        for row in tap.named_rows(response)
    ]
    write_json(path, {"schema_version": SCHEMA_VERSION, "adql": adql, "rows": rows})
    LOGGER.info("TAP cache stored path=%s rows=%s", path, len(rows))
    return rows


def cone_clause(ra: float, dec: float, radius: float) -> str:
    return (
        "CONTAINS(POINT('ICRS', o.s_ra, o.s_dec), "
        f"CIRCLE('ICRS', {ra:.12g}, {dec:.12g}, {radius:.12g})) = 1"
    )


def count_query(ra: float, dec: float, radius: float, missions: list[str]) -> str:
    quoted = ",".join(f"'{value.replace(chr(39), chr(39) * 2)}'" for value in missions)
    return (
        "SELECT o.filters, COUNT(*) AS count_available\n"
        "FROM dbo.obspointing AS o\n"
        "JOIN dbo.caomplane AS p ON p.planetid = o.objid\n"
        "JOIN dbo.caomartifact AS a ON a.planetid = p.planetid\n"
        f"WHERE {cone_clause(ra, dec, radius)}\n"
        f"  AND o.obs_collection IN ({quoted})\n"
        "  AND o.datarights = 'PUBLIC'\n"
        "  AND o.calib_level IN (3,4)\n"
        "  AND LOWER(o.dataproduct_type) IN ('image','cube')\n"
        "GROUP BY o.filters"
    )


def filter_query(
    tap,
    ra: float,
    dec: float,
    radius: float,
    missions: list[str],
    filter_name: str,
    limit: int,
) -> str:
    quoted = ",".join(f"'{value.replace(chr(39), chr(39) * 2)}'" for value in missions)
    escaped_filter = filter_name.replace("'", "''")
    columns = ",\n        ".join((*tap.APPLICATION_COLUMNS, *EXTRA_COLUMNS))
    return (
        f"SELECT TOP {limit}\n        {columns}\n"
        "FROM dbo.obspointing AS o\n"
        "JOIN dbo.caomplane AS p ON p.planetid = o.objid\n"
        "JOIN dbo.caomartifact AS a ON a.planetid = p.planetid\n"
        f"WHERE {cone_clause(ra, dec, radius)}\n"
        f"  AND o.obs_collection IN ({quoted})\n"
        "  AND o.datarights = 'PUBLIC'\n"
        "  AND o.calib_level IN (3,4)\n"
        "  AND LOWER(o.dataproduct_type) IN ('image','cube')\n"
        f"  AND UPPER(o.filters) LIKE '%{escaped_filter}%'\n"
        "ORDER BY o.obs_collection, o.instrument_name, o.obs_id, o.filters"
    )


def finite_number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if math.isfinite(number) else None


def size_bytes(row: dict[str, Any]) -> int | None:
    value = finite_number(row.get("contentlength"))
    return int(value) if value is not None and value > 0 else None


def is_science_mosaic(row: dict[str, Any]) -> bool:
    filename = str(row.get("productfilename") or "").lower()
    mission = str(row.get("obs_collection") or "").upper()
    if mission == "JWST":
        return filename.endswith("_i2d.fits")
    if mission in {"HST", "HLA"}:
        return filename.endswith("_drz.fits") or filename.endswith("_drc.fits")
    return False


def footprint_text(row: dict[str, Any]) -> str:
    region = " ".join(str(row.get("s_region") or "").upper().split())
    bounds = " ".join(str(row.get("posboundsstcs") or "").upper().split())
    return bounds if bounds and bounds != region else region


def first_rejection(
    tap,
    row: dict[str, Any],
    *,
    max_file_bytes: int,
    seen_uris: set[str],
    seen_checksums: set[str],
) -> str | None:
    filename = str(row.get("productfilename") or "").lower()
    if not filename.endswith(".fits"):
        return "not_fits"
    if not is_science_mosaic(row):
        return "not_science_mosaic"
    uri = str(row.get("datauri") or "").strip()
    if not uri:
        return "missing_download_url"
    size = size_bytes(row)
    if size is None:
        return "missing_file_size"
    if size > max_file_bytes:
        return "exceeds_product_size_limit"
    region = footprint_text(row)
    if not region:
        return "missing_footprint"
    if tap.parse_s_region(region) is None:
        return "invalid_footprint"
    if not tap.filter_keys(row.get("filters")):
        return "missing_filter"
    if not str(row.get("instrument_name") or "").strip():
        return "missing_instrument"
    checksum = str(row.get("contentchecksum") or "").strip()
    if checksum and checksum in seen_checksums:
        return "duplicate_checksum"
    if uri in seen_uris:
        return "duplicate_datauri"
    seen_uris.add(uri)
    if checksum:
        seen_checksums.add(checksum)
    return None


def metric_quality(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    reports = []
    for name, _expression in QUALITY_COLUMNS:
        values = [finite_number(row.get(name)) for row in rows]
        present = [value for value in values if value is not None]
        fill = len(present) / len(rows) if rows else 0.0
        keep = fill >= 0.5 and len(set(present)) > 1
        reports.append(
            {
                "column": name,
                "non_null_count": len(present),
                "total_rows": len(rows),
                "non_null_percent": round(fill * 100, 1),
                "decision": "keep" if keep else "drop",
                "reason": (
                    "filled at least 50% and varies"
                    if keep
                    else ("filled below 50%" if fill < 0.5 else "filled but constant")
                ),
                "min": min(present) if present else None,
                "median": statistics.median(present) if present else None,
                "max": max(present) if present else None,
            }
        )
    return reports


def group_identity(tap, row: dict[str, Any]) -> str:
    collection = str(row.get("obs_collection") or "").upper()
    instrument = str(row.get("instrument_name") or "").upper()
    return f"{collection}:{instrument}:{tap.observation_group_key(row)}"


def display_group_names(groups: dict[str, list[dict[str, Any]]]) -> dict[str, str]:
    bare = {key: key.split(":", 2)[-1] for key in groups}
    counts = Counter(bare.values())
    return {
        key: (key if counts[name] > 1 else name)
        for key, name in bare.items()
    }


def group_summaries(
    tap,
    rows: list[dict[str, Any]],
    minimum_ids: int,
) -> tuple[list[dict[str, Any]], set[str], dict[str, str]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[group_identity(tap, row)].append(row)
    names = display_group_names(grouped)
    summaries = []
    passing = set()
    for key in sorted(grouped):
        members = grouped[key]
        obs_ids = sorted({str(row.get("obs_id") or "") for row in members if row.get("obs_id")})
        uris = {str(row.get("datauri") or "") for row in members}
        sizes = [size_bytes(row) or 0 for row in members]
        filters = sorted({token for row in members for token in tap.filter_keys(row.get("filters"))})
        footprints = {hashlib.sha1(footprint_text(row).encode()).hexdigest()[:16] for row in members}
        qualifies = len(obs_ids) >= minimum_ids
        if qualifies:
            passing.add(key)
        summaries.append(
            {
                "group_id": key,
                "observation_group": names[key],
                "qualifies": qualifies,
                "rejection_reason": "" if qualifies else "fewer_than_minimum_observation_ids",
                "observation_id_count": len(obs_ids),
                "observation_ids": obs_ids,
                "uri_count": len(uris),
                "total_bytes": sum(sizes),
                "median_bytes": statistics.median(sizes) if sizes else 0,
                "max_bytes": max(sizes, default=0),
                "filter_count": len(filters),
                "filters": filters,
                "footprint_count": len(footprints),
            }
        )
    return summaries, passing, names


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_groups_csv(path: Path, groups: list[dict[str, Any]]) -> None:
    width = max((len(group["observation_ids"]) for group in groups), default=0)
    fields = [
        "observationGroup",
        "qualifies",
        "observationIDCount",
        "uriCount",
        "filterCount",
        "footprintCount",
        "totalBytes",
        "medianBytes",
        "maxBytes",
        *[f"observationID{index}" for index in range(1, width + 1)],
    ]
    rows = []
    for group in groups:
        row = {
            "observationGroup": group["observation_group"],
            "qualifies": group["qualifies"],
            "observationIDCount": group["observation_id_count"],
            "uriCount": group["uri_count"],
            "filterCount": group["filter_count"],
            "footprintCount": group["footprint_count"],
            "totalBytes": group["total_bytes"],
            "medianBytes": group["median_bytes"],
            "maxBytes": group["max_bytes"],
        }
        row.update(
            {
                f"observationID{index}": value
                for index, value in enumerate(group["observation_ids"], start=1)
            }
        )
        rows.append(row)
    write_csv(path, fields, rows)


def plot_filter_funnel(
    path: Path,
    filters: list[dict[str, Any]],
    *,
    title: str,
    selected_counts: dict[str, int] | None = None,
) -> None:
    """Draw a readable per-filter table whose columns are pipeline stages."""

    selected_counts = selected_counts or {}
    headers = ["Filter", "Catalog", ".fits", "Mosaic", "Eligible", "Group ≥3 IDs"]
    if selected_counts:
        headers.append("Selected")
    rows = []
    for item in filters:
        row = [
            item["filter"],
            str(item["count_available"]),
            str(item["after_fits"]),
            str(item["after_mosaic"]),
            str(item["after_eligibility"]),
            str(item["after_group"]),
        ]
        if selected_counts:
            row.append(str(selected_counts.get(item["filter"], 0)))
        rows.append(row)
    figure_height = max(7, 1.5 + 0.34 * len(rows))
    figure, axis = plt.subplots(figsize=(12, figure_height))
    axis.axis("off")
    axis.set_title(title, loc="left", fontsize=13, pad=34)
    explanation = (
        "Catalog: public calib 3/4 image/cube rows.  FITS: filename ends .fits.  "
        "Mosaic: JWST i2d or HST/HLA drz/drc.  Eligible: URL, bytes, footprint, "
        "filter and instrument; within file cap.  Group: visit has ≥3 distinct observation IDs."
    )
    axis.text(0, 0.985, explanation, transform=axis.transAxes, va="top", fontsize=8, wrap=True)
    table = axis.table(
        cellText=rows,
        colLabels=headers,
        cellLoc="right",
        colLoc="right",
        bbox=[0, 0, 1, 0.93],
    )
    table.auto_set_font_size(False)
    table.set_fontsize(7)
    for row_index in range(len(rows) + 1):
        table[(row_index, 0)].set_text_props(ha="left")
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(figure)


def resolve_position(tap, args: argparse.Namespace) -> tuple[float, float, str]:
    if (args.ra is None) != (args.dec is None):
        raise ValueError("provide both --ra and --dec")
    if args.ra is not None:
        label = args.target or f"ra-{args.ra:.6f}_dec-{args.dec:.6f}"
        return float(args.ra), float(args.dec), label
    if not args.target:
        raise ValueError("provide --target or both --ra and --dec")
    ra, dec = tap.resolve_target(args.target, timeout=args.timeout, retries=args.retries)
    return ra, dec, args.target


def run_qualify(args: argparse.Namespace) -> int:
    tap = load_greedy()
    ra, dec, target_label = resolve_position(tap, args)
    run_dir = args.run_dir.expanduser().resolve()
    cache_dir = run_dir / "tap-cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    missions = tap.parse_csv_values(args.missions)
    query = count_query(ra, dec, args.radius, missions)
    count_rows = cached_rows(
        tap, cache_dir / "filter-counts.json", query, args.timeout, args.retries
    )
    counts: dict[str, int] = defaultdict(int)
    for row in count_rows:
        count = int(finite_number(row.get("count_available")) or 0)
        for token in tap.filter_keys(row.get("filters")):
            counts[token] += count
    tokens = sorted(counts, key=lambda name: (int("".join(c for c in name if c.isdigit()) or 99999), name))
    LOGGER.info("Discovered filters=%s", len(tokens))

    per_filter_rows: dict[str, list[dict[str, Any]]] = {}
    for name in tokens:
        adql = filter_query(tap, ra, dec, args.radius, missions, name, args.per_filter_limit)
        per_filter_rows[name] = cached_rows(
            tap,
            cache_dir / f"filter-{name}.json",
            adql,
            args.timeout,
            args.retries,
        )
        LOGGER.info("Filter=%s rows=%s", name, len(per_filter_rows[name]))

    max_file_bytes = int(args.max_file_mib * MIB)
    audits = []
    filter_stages = []
    globally_qualified: dict[str, dict[str, Any]] = {}
    for name in tokens:
        seen_uris: set[str] = set()
        seen_checksums: set[str] = set()
        stage = Counter()
        accepted = []
        for row in per_filter_rows[name]:
            filename = str(row.get("productfilename") or "").lower()
            if filename.endswith(".fits"):
                stage["after_fits"] += 1
            if filename.endswith(".fits") and is_science_mosaic(row):
                stage["after_mosaic"] += 1
            reason = first_rejection(
                tap,
                row,
                max_file_bytes=max_file_bytes,
                seen_uris=seen_uris,
                seen_checksums=seen_checksums,
            )
            if reason is None:
                stage["after_eligibility"] += 1
                accepted.append(row)
                uri = str(row.get("datauri") or "")
                globally_qualified.setdefault(uri, row)
            audits.append(
                {
                    "thread_filter": name,
                    "obs_collection": row.get("obs_collection"),
                    "instrument_name": row.get("instrument_name"),
                    "obs_id": row.get("obs_id"),
                    "filters": row.get("filters"),
                    "productfilename": row.get("productfilename"),
                    "datauri": row.get("datauri"),
                    "contentlength": row.get("contentlength"),
                    "status": "eligible" if reason is None else "rejected",
                    "first_rejection_reason": reason or "",
                }
            )
        filter_stages.append(
            {
                "filter": name,
                "requested": args.per_filter_limit,
                "count_available": counts[name],
                "not_in_catalog": max(args.per_filter_limit - counts[name], 0),
                "returned": len(per_filter_rows[name]),
                "after_fits": stage["after_fits"],
                "after_mosaic": stage["after_mosaic"],
                "after_eligibility": stage["after_eligibility"],
                "after_group": 0,
            }
        )

    eligible_rows = list(globally_qualified.values())
    groups, passing_groups, names = group_summaries(
        tap, eligible_rows, args.min_group_observation_ids
    )
    qualified_rows = [
        row for row in eligible_rows if group_identity(tap, row) in passing_groups
    ]
    for row in qualified_rows:
        row["observation_group_id"] = group_identity(tap, row)
        row["observation_group"] = names[row["observation_group_id"]]
        row["contentlength_bytes"] = size_bytes(row)
    for stage in filter_stages:
        stage["after_group"] = sum(
            stage["filter"] in tap.filter_keys(row.get("filters"))
            for row in qualified_rows
        )

    quality = metric_quality(eligible_rows)
    config = {
        "target": target_label,
        "ra": ra,
        "dec": dec,
        "radius_degrees": args.radius,
        "missions": missions,
        "per_filter_limit": args.per_filter_limit,
        "max_file_mib": args.max_file_mib,
        "min_group_observation_ids": args.min_group_observation_ids,
    }
    report = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "mast-composite-phase-1-qualified",
        "created_at": now_iso(),
        "configuration": config,
        "adql": {"filter_counts": query},
        "summary": {
            "filter_count": len(tokens),
            "thread_row_count": sum(len(rows) for rows in per_filter_rows.values()),
            "unique_eligible_uri_count": len(eligible_rows),
            "qualified_group_count": len(passing_groups),
            "qualified_uri_count": len(qualified_rows),
            "qualified_bytes": sum(size_bytes(row) or 0 for row in qualified_rows),
        },
        "column_quality": quality,
        "filter_funnel": filter_stages,
        "rejection_counts": dict(
            sorted(Counter(row["first_rejection_reason"] or "eligible" for row in audits).items())
        ),
        "groups": groups,
        "qualified_rows": qualified_rows,
    }
    qualified_path = run_dir / "phase-1-qualified.json"
    write_json(qualified_path, report)
    write_csv(
        run_dir / "phase-1-rejections.csv",
        [
            "thread_filter",
            "obs_collection",
            "instrument_name",
            "obs_id",
            "filters",
            "productfilename",
            "datauri",
            "contentlength",
            "status",
            "first_rejection_reason",
        ],
        audits,
    )
    write_groups_csv(run_dir / "phase-1-observation-groups.csv", groups)
    write_json(
        run_dir / "phase-1-filter-funnel.json",
        {
            "schema_version": SCHEMA_VERSION,
            "configuration": config,
            "filters": filter_stages,
        },
    )
    plot_filter_funnel(
        run_dir / "phase-1-filter-funnel.png",
        filter_stages,
        title=f"{target_label}: Phase 1 qualification",
    )
    LOGGER.info(
        "Phase 1 complete groups=%s URIs=%s GiB=%.2f path=%s",
        len(passing_groups),
        len(qualified_rows),
        report["summary"]["qualified_bytes"] / (1024**3),
        qualified_path,
    )
    return 0


def candidate_from_row(
    tap,
    row: dict[str, Any],
    grid,
    quality_columns: set[str],
) -> dict[str, Any] | None:
    shapes = tap.parse_s_region(footprint_text(row))
    if shapes is None:
        return None
    cells = frozenset(
        index for index, point in enumerate(grid.points) if tap.region_contains(point, shapes)
    )
    filters = frozenset(tap.filter_keys(row.get("filters")))
    return {
        "row": row,
        "uri": str(row.get("datauri") or ""),
        "obs_id": str(row.get("obs_id") or ""),
        "group_id": str(row["observation_group_id"]),
        "group_name": str(row["observation_group"]),
        "filters": filters,
        "cells": cells,
        "bytes": size_bytes(row) or 0,
        "exposure": (
            finite_number(row.get("timexposure"))
            if "timexposure" in quality_columns
            else None
        ),
        "magnitude_limit": (
            finite_number(row.get("mtrmaglimit"))
            if "mtrmaglimit" in quality_columns
            else None
        ),
        "position_resolution": (
            finite_number(row.get("posresolution"))
            if "posresolution" in quality_columns
            else None
        ),
    }


def candidate_metrics(
    candidates: list[dict[str, Any]],
    *,
    covered_cells: set[int],
    selected_group_filters: set[str],
    grid_size: int,
    coverage_weight: float,
    filter_weight: float,
    exponent: float,
) -> dict[str, Any]:
    cells = set().union(*(candidate["cells"] for candidate in candidates))
    filters = set().union(*(candidate["filters"] for candidate in candidates))
    new_cells = cells - covered_cells
    new_filters = filters - selected_group_filters
    bytes_count = sum(candidate["bytes"] for candidate in candidates)
    new_fraction = len(new_cells) / grid_size if grid_size else 0.0
    numerator = coverage_weight * new_fraction + filter_weight * len(new_filters)
    cost = max(bytes_count / MIB, 0.001) ** exponent
    return {
        "new_cells": len(new_cells),
        "new_coverage_fraction": new_fraction,
        "new_filters": sorted(new_filters),
        "new_filter_count": len(new_filters),
        "bytes": bytes_count,
        "score_numerator": numerator,
        "score_cost": cost,
        "score": numerator / max(cost, 0.000001),
    }


def candidate_order(value: dict[str, Any]) -> tuple[Any, ...]:
    metrics = value["metrics"]
    exposure_values = [
        candidate["exposure"]
        for candidate in value["candidates"]
        if candidate["exposure"] is not None
    ]
    exposure = statistics.fmean(exposure_values) if exposure_values else float("-inf")
    magnitude_values = [
        candidate["magnitude_limit"]
        for candidate in value["candidates"]
        if candidate["magnitude_limit"] is not None
    ]
    magnitude = statistics.fmean(magnitude_values) if magnitude_values else float("-inf")
    resolution_values = [
        candidate["position_resolution"]
        for candidate in value["candidates"]
        if candidate["position_resolution"] is not None
    ]
    resolution = (
        statistics.fmean(resolution_values) if resolution_values else float("inf")
    )
    identity = "|".join(candidate["uri"] for candidate in value["candidates"])
    return (
        -metrics["score"],
        -metrics["score_numerator"],
        -metrics["new_filter_count"],
        -exposure,
        -magnitude,
        resolution,
        metrics["bytes"],
        value["group_id"],
        identity,
    )


def simulate_starter(
    group_id: str,
    available: list[dict[str, Any]],
    *,
    minimum: int,
    covered_cells: set[int],
    grid_size: int,
    options: argparse.Namespace,
) -> dict[str, Any] | None:
    chosen: list[dict[str, Any]] = []
    remaining = list(available)
    temporary_cells = set(covered_cells)
    temporary_filters: set[str] = set()
    while remaining and len({item["obs_id"] for item in chosen}) < minimum:
        scored = []
        for candidate in remaining:
            if candidate["obs_id"] in {item["obs_id"] for item in chosen}:
                continue
            metrics = candidate_metrics(
                [candidate],
                covered_cells=temporary_cells,
                selected_group_filters=temporary_filters,
                grid_size=grid_size,
                coverage_weight=options.coverage_weight,
                filter_weight=options.filter_weight,
                exponent=options.size_penalty_exponent,
            )
            scored.append(
                {
                    "type": "starter_member",
                    "group_id": group_id,
                    "candidates": [candidate],
                    "metrics": metrics,
                }
            )
        if not scored:
            return None
        winner = min(scored, key=candidate_order)["candidates"][0]
        chosen.append(winner)
        temporary_cells.update(winner["cells"])
        temporary_filters.update(winner["filters"])
        remaining.remove(winner)
    if len({item["obs_id"] for item in chosen}) < minimum:
        return None
    return {
        "type": "group_activation",
        "group_id": group_id,
        "candidates": chosen,
        "metrics": candidate_metrics(
            chosen,
            covered_cells=covered_cells,
            selected_group_filters=set(),
            grid_size=grid_size,
            coverage_weight=options.coverage_weight,
            filter_weight=options.filter_weight,
            exponent=options.size_penalty_exponent,
        ),
    }


def plot_beauty(path: Path, tap, grid, selected: list[dict[str, Any]], target_count: int, title: str) -> None:
    covered = [set() for _ in grid.points]
    for candidate in selected:
        for index in candidate["cells"]:
            covered[index].update(candidate["filters"])
    values = [len(filters) / target_count if target_count else 0 for filters in covered]
    figure, axis = plt.subplots(figsize=(8, 7))
    plot = axis.scatter(
        [point[0] for point in grid.points],
        [point[1] for point in grid.points],
        c=values,
        cmap="viridis",
        vmin=0,
        vmax=1,
        s=8,
    )
    for candidate in selected:
        shapes = tap.parse_s_region(footprint_text(candidate["row"])) or []
        for kind, numbers in shapes:
            if kind == "CIRCLE":
                axis.add_patch(
                    MatCircle(
                        (numbers[0], numbers[1]),
                        numbers[2],
                        fill=False,
                        edgecolor="white",
                        linewidth=0.35,
                        alpha=0.45,
                    )
                )
            elif kind == "POLYGON":
                axis.add_patch(
                    MatPolygon(
                        list(zip(numbers[0::2], numbers[1::2])),
                        closed=True,
                        fill=False,
                        edgecolor="white",
                        linewidth=0.35,
                        alpha=0.45,
                    )
                )
    axis.set_title(title)
    axis.set_xlabel("RA deg")
    axis.set_ylabel("Dec deg")
    axis.invert_xaxis()
    axis.set_aspect("equal")
    figure.colorbar(plot, ax=axis, label="Beautiful coverage (0–1)")
    figure.tight_layout()
    figure.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(figure)


def natural_key(value: str) -> tuple[Any, ...]:
    """Sort names containing numbers in the order a person expects."""

    return tuple(
        int(part) if part.isdigit() else part.upper()
        for part in re.split(r"(\d+)", value)
    )


def distributed_color(index: int, count: int) -> tuple[float, str]:
    """Return the fallback colour used by AOSImage's distributed HSV palette."""

    hue = ((300.0 - 180.0 / count) + index / count * 360.0 + 360.0) % 360.0
    red, green, blue = colorsys.hsv_to_rgb(hue / 360.0, 1.0, 1.0)
    return hue, to_hex((red, green, blue), keep_alpha=False).upper()


def load_preferred_colors(path: Path | None) -> dict[str, str]:
    """Load optional category-to-hex overrides for the footprint renderer."""

    if path is None:
        return {}
    decoded = read_json(path.expanduser().resolve())
    if not isinstance(decoded, dict):
        raise ValueError("--preferred-colors must contain a JSON object")
    colors: dict[str, str] = {}
    for raw_key, raw_color in decoded.items():
        key = str(raw_key)
        color = str(raw_color)
        if HEX_COLOR.fullmatch(color) is None:
            raise ValueError(
                f"invalid preferred colour for {key!r}: {color!r}; use #RRGGBB"
            )
        colors[key] = "#" + color.lstrip("#").upper()
    return colors


def render_product_identity(product: dict[str, Any]) -> str:
    """Return a stable identifier for one selected science product."""

    uri = str(product.get("datauri") or "").strip()
    if uri:
        return uri
    return "\x1f".join(
        str(product.get(key) or "")
        for key in ("obs_collection", "obs_id", "instrument_name", "filters")
    )


def render_group_identity(product: dict[str, Any]) -> str:
    """Return the observation-stack identity stored by Phase 1/2."""

    explicit = str(product.get("observation_group_id") or "").strip()
    if explicit:
        return explicit
    return ":".join(
        (
            str(product.get("obs_collection") or "UNKNOWN").upper(),
            str(product.get("instrument_name") or "UNKNOWN").upper(),
            str(product.get("observation_key") or product.get("obs_id") or "UNKNOWN"),
        )
    )


def selected_drawables(tap, products: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Parse Phase 2 products into drawable CAOM footprint records."""

    drawables = []
    seen: set[str] = set()
    for product in products:
        identity = render_product_identity(product)
        if identity in seen:
            LOGGER.warning("Skipping duplicate selected product datauri=%s", identity)
            continue
        seen.add(identity)
        shapes = tap.parse_s_region(footprint_text(product))
        if shapes is None:
            LOGGER.warning("Skipping selected product with invalid footprint datauri=%s", identity)
            continue
        filters = tuple(sorted(tap.filter_keys(product.get("filters")), key=natural_key))
        drawables.append(
            {
                "identity": identity,
                "product": product,
                "mission": str(product.get("obs_collection") or "UNKNOWN").upper(),
                "group": render_group_identity(product),
                "filters": filters or ("UNKNOWN",),
                "shapes": shapes,
            }
        )
    return drawables


def drawable_order(drawable: dict[str, Any]) -> tuple[Any, ...]:
    """Provide stable ordering within an observation stack."""

    product = drawable["product"]
    rank = int(finite_number(product.get("selection_rank")) or 1_000_000)
    return (
        rank,
        natural_key("+".join(drawable["filters"])),
        natural_key(str(product.get("obs_id") or "")),
        drawable["identity"],
    )


def render_color_plan(
    drawables: list[dict[str, Any]],
    color_by: str,
    preferred_colors: dict[str, str],
) -> tuple[dict[str, tuple[str, ...]], dict[str, dict[str, Any]]]:
    """Assign global colours or AOSImage group-local colours to products."""

    assignments: dict[str, tuple[str, ...]] = {}
    usage: Counter[str] = Counter()
    entries: dict[str, dict[str, Any]] = {}

    if color_by == "observation-group":
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for drawable in drawables:
            groups[drawable["group"]].append(drawable)
        for group in sorted(groups, key=natural_key):
            members = sorted(groups[group], key=drawable_order)
            count = len(members)
            for index, drawable in enumerate(members):
                preferred_key = next(
                    (
                        key
                        for key in (
                            drawable["identity"],
                            group,
                            *drawable["filters"],
                        )
                        if key in preferred_colors
                    ),
                    None,
                )
                if preferred_key is None:
                    key = f"N{count}:P{index + 1}"
                    hue, color = distributed_color(index, count)
                    label = f"{count} products / position {index + 1}"
                    source = "aosimage_group_local_hsv"
                else:
                    key = f"preferred:{preferred_key}"
                    hue = None
                    color = preferred_colors[preferred_key]
                    label = f"Preferred {preferred_key}"
                    source = "preferred_hex"
                assignments[drawable["identity"]] = (key,)
                usage[key] += 1
                entries.setdefault(
                    key,
                    {
                        "key": key,
                        "label": label,
                        "color": color,
                        "hue_degrees": round(hue, 9) if hue is not None else None,
                        "source": source,
                        "product_count": 0,
                    },
                )
        for key, count in usage.items():
            entries[key]["product_count"] = count
        return assignments, entries

    if color_by == "mission":
        categories = sorted({drawable["mission"] for drawable in drawables}, key=natural_key)
    else:
        categories = sorted(
            {name for drawable in drawables for name in drawable["filters"]},
            key=natural_key,
        )
    for index, category in enumerate(categories):
        if color_by == "mission":
            hue = None
            color = MISSION_COLORS.get(category, FALLBACK_COLOR)
            source = "fixed_mission_palette"
        else:
            hue, color = distributed_color(index, len(categories))
            source = "aosimage_distributed_hsv"
        if category in preferred_colors:
            color = preferred_colors[category]
            source = "preferred_hex"
        entries[category] = {
            "key": category,
            "label": category,
            "color": color,
            "hue_degrees": round(hue, 9) if hue is not None else None,
            "source": source,
            "product_count": 0,
        }
    for drawable in drawables:
        keys = (
            (drawable["mission"],)
            if color_by == "mission"
            else tuple(drawable["filters"])
        )
        assignments[drawable["identity"]] = keys
        for key in keys:
            entries[key]["product_count"] += 1
    return assignments, entries


def local_offset(
    ra: float,
    dec: float,
    center_ra: float,
    center_dec: float,
) -> tuple[float, float]:
    """Project ICRS coordinates to small-angle offsets in arcminutes."""

    wrapped_ra = (ra - center_ra + 180.0) % 360.0 - 180.0
    return (
        wrapped_ra * math.cos(math.radians(center_dec)) * 60.0,
        (dec - center_dec) * 60.0,
    )


def render_shape_bounds(
    shape: str,
    numbers: tuple[float, ...],
    center_ra: float,
    center_dec: float,
) -> tuple[float, float, float, float]:
    """Return local bounds for a CAOM circle or polygon."""

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


def add_render_shape(
    axis,
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
    """Add one projected CAOM shape to a Matplotlib axis."""

    style = {
        "edgecolor": to_rgba(edgecolor, edge_alpha),
        "facecolor": to_rgba(facecolor, face_alpha),
        "linewidth": linewidth,
        "zorder": zorder,
    }
    if shape == "CIRCLE":
        x, y = local_offset(numbers[0], numbers[1], center_ra, center_dec)
        axis.add_patch(MatCircle((x, y), numbers[2] * 60.0, **style))
        return
    points = [
        local_offset(numbers[index], numbers[index + 1], center_ra, center_dec)
        for index in range(0, len(numbers), 2)
    ]
    axis.add_patch(MatPolygon(points, closed=True, **style))


def read_render_input(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    """Read a compatible Phase 2 selection or download manifest."""

    report = read_json(path)
    artifact = report.get("artifact")
    if artifact == "mast-composite-phase-2-selection":
        config = report.get("configuration") or {}
        position = {
            "target": config.get("target"),
            "ra": config.get("ra"),
            "dec": config.get("dec"),
            "radius_degrees": config.get("radius_degrees"),
        }
    elif artifact == "mast-composite-download-manifest":
        position = {"target": report.get("target"), **(report.get("position") or {})}
    else:
        raise ValueError(
            "--input must be a Phase 2 selection or Phase 2 download manifest"
        )
    try:
        normalized = {
            "target": str(position.get("target") or "Coordinate target"),
            "ra": float(position["ra"]),
            "dec": float(position["dec"]),
            "radius_degrees": float(position["radius_degrees"]),
        }
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("render input is missing a valid target position") from error
    products = report.get("selected_products")
    if not isinstance(products, list) or not products:
        raise ValueError("render input contains no selected products")
    return normalized, products, report.get("summary") or {}


def render_product_label(drawable: dict[str, Any], label_by: str) -> str:
    """Return the optional short label drawn at a product centre."""

    product = drawable["product"]
    if label_by == "rank":
        return str(product.get("selection_rank") or "")
    if label_by == "filter":
        return "+".join(drawable["filters"])
    if label_by == "group":
        return str(product.get("observation_group") or drawable["group"].split(":")[-1])
    return ""


def run_render(args: argparse.Namespace) -> int:
    """Render selected Phase 2 products without querying TAP or reading FITS."""

    tap = load_greedy()
    input_path = args.input.expanduser().resolve()
    position, products, summary = read_render_input(input_path)
    drawables = selected_drawables(tap, products)
    if not drawables:
        raise ValueError("none of the selected products has a drawable CAOM footprint")
    skipped = len(products) - len(drawables)
    preferred = load_preferred_colors(args.preferred_colors)
    assignments, color_entries = render_color_plan(
        drawables, args.color_by, preferred
    )

    center_ra = position["ra"]
    center_dec = position["dec"]
    radius_arcminutes = position["radius_degrees"] * 60.0
    bounds = [
        render_shape_bounds(shape, numbers, center_ra, center_dec)
        for drawable in drawables
        for shape, numbers in drawable["shapes"]
    ]
    bounds.append(
        (-radius_arcminutes, radius_arcminutes, -radius_arcminutes, radius_arcminutes)
    )
    minimum_x = min(bound[0] for bound in bounds)
    maximum_x = max(bound[1] for bound in bounds)
    minimum_y = min(bound[2] for bound in bounds)
    maximum_y = max(bound[3] for bound in bounds)
    padding = max(maximum_x - minimum_x, maximum_y - minimum_y) * 0.055

    figure, axis = plt.subplots(figsize=(11, 9))
    axis.add_patch(
        MatCircle(
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
    for drawable in drawables:
        keys = assignments[drawable["identity"]]
        colors = [color_entries[key]["color"] for key in keys]
        for shape, numbers in drawable["shapes"]:
            add_render_shape(
                axis,
                shape,
                numbers,
                center_ra,
                center_dec,
                edgecolor=colors[0],
                facecolor=colors[0],
                edge_alpha=0.0,
                face_alpha=0.16,
                linewidth=0.0,
                zorder=2,
            )
            for layer, color in enumerate(reversed(colors)):
                add_render_shape(
                    axis,
                    shape,
                    numbers,
                    center_ra,
                    center_dec,
                    edgecolor=color,
                    facecolor=color,
                    edge_alpha=0.8,
                    face_alpha=0.0,
                    linewidth=1.0 + 0.65 * (len(colors) - layer - 1),
                    zorder=3,
                )
        label = render_product_label(drawable, args.label_by)
        if label:
            product = drawable["product"]
            ra = finite_number(product.get("s_ra"))
            dec = finite_number(product.get("s_dec"))
            if ra is not None and dec is not None:
                x, y = local_offset(ra, dec, center_ra, center_dec)
                axis.annotate(
                    label,
                    (x, y),
                    fontsize=6.5,
                    ha="center",
                    va="center",
                    color="#263238",
                    zorder=5,
                )

    groups = {drawable["group"] for drawable in drawables}
    filters = {name for drawable in drawables for name in drawable["filters"]}
    selected_mib = float(summary.get("selected_size_mib") or 0.0)
    coverage = 100.0 * float(summary.get("coverage_fraction") or 0.0)
    axis.scatter([0.0], [0.0], marker="+", s=42, linewidths=1.4, color="#222222", zorder=6)
    axis.set_title(
        f"{position['target']} selected science-product footprints\n"
        f"{len(drawables)} products • {len(groups)} observation groups • "
        f"{len(filters)} filters • {selected_mib:.1f} MiB • {coverage:.2f}% coverage",
        fontsize=13,
        pad=12,
    )
    axis.set_xlabel("Right-ascension offset (arcmin; east is left)")
    axis.set_ylabel("Declination offset (arcmin)")
    axis.set_xlim(maximum_x + padding, minimum_x - padding)
    axis.set_ylim(minimum_y - padding, maximum_y + padding)
    axis.set_aspect("equal", adjustable="box")
    axis.grid(True, color="#B0BEC5", linewidth=0.45, alpha=0.36)
    axis.set_axisbelow(True)

    ordered_entries = sorted(color_entries.values(), key=lambda item: natural_key(item["key"]))
    legend_limit = 36
    visible_entries = ordered_entries[:legend_limit]
    handles = [
        Patch(
            facecolor=entry["color"],
            edgecolor=entry["color"],
            alpha=0.45,
            label=f"{entry['label']} ({entry['product_count']})",
        )
        for entry in visible_entries
    ]
    if len(visible_entries) < len(ordered_entries):
        handles.append(
            Line2D(
                [],
                [],
                color="none",
                label=f"+{len(ordered_entries) - len(visible_entries)} more in colour-key JSON",
            )
        )
    handles.append(
        Line2D(
            [0],
            [0],
            color="#222222",
            linewidth=1.4,
            linestyle=(0, (5, 4)),
            label="Target boundary",
        )
    )
    figure.legend(
        handles=handles,
        loc="lower center",
        bbox_to_anchor=(0.5, 0.015),
        ncol=min(6, max(1, len(handles))),
        frameon=False,
        fontsize=8,
        title=f"Colour by {args.color_by}; number in parentheses is selected-product usage",
        title_fontsize=9,
    )
    figure.subplots_adjust(bottom=0.19)

    output = (
        args.output.expanduser().resolve()
        if args.output is not None
        else input_path.with_name("phase-2-selected-product-footprints.png")
    )
    color_key_output = (
        args.color_key_output.expanduser().resolve()
        if args.color_key_output is not None
        else output.with_name(f"{output.stem}-colors.json")
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(output, dpi=args.dpi, facecolor="white", bbox_inches="tight")
    svg_output = args.svg_output.expanduser().resolve() if args.svg_output else None
    if svg_output is not None:
        svg_output.parent.mkdir(parents=True, exist_ok=True)
        figure.savefig(svg_output, format="svg", facecolor="white", bbox_inches="tight")
    plt.close(figure)

    product_assignments = []
    for drawable in sorted(drawables, key=drawable_order):
        keys = assignments[drawable["identity"]]
        product = drawable["product"]
        product_assignments.append(
            {
                "selection_rank": product.get("selection_rank"),
                "datauri": product.get("datauri"),
                "observation_group": drawable["group"],
                "mission": drawable["mission"],
                "filters": list(drawable["filters"]),
                "palette_keys": list(keys),
                "colors": [color_entries[key]["color"] for key in keys],
            }
        )
    color_payload = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "mast-composite-selected-product-render",
        "source": str(input_path),
        "color_by": args.color_by,
        "fallback_formula": "hue = (300 - 180/count + index * 360/count) mod 360",
        "categories": ordered_entries,
        "products": product_assignments,
    }
    write_json(color_key_output, color_payload)
    render_summary = {
        "input": str(input_path),
        "output": str(output),
        "svg_output": str(svg_output) if svg_output is not None else None,
        "color_key_output": str(color_key_output),
        "color_by": args.color_by,
        "selected_product_count": len(products),
        "rendered_product_count": len(drawables),
        "skipped_product_count": skipped,
        "observation_group_count": len(groups),
        "filter_count": len(filters),
    }
    LOGGER.info(
        "Render complete products=%s groups=%s filters=%s color_by=%s output=%s",
        len(drawables),
        len(groups),
        len(filters),
        args.color_by,
        output,
    )
    print(json.dumps(render_summary, indent=2))
    return 0


def run_select(args: argparse.Namespace) -> int:
    tap = load_greedy()
    input_path = args.input.expanduser().resolve()
    phase1 = read_json(input_path)
    if phase1.get("schema_version") != SCHEMA_VERSION or phase1.get("artifact") != "mast-composite-phase-1-qualified":
        raise ValueError("input is not a compatible Phase 1 qualified artifact")
    config = phase1["configuration"]
    rows = phase1["qualified_rows"]
    quality_columns = {
        report["column"]
        for report in phase1.get("column_quality", [])
        if report.get("decision") == "keep"
    }
    grid = tap.make_coverage_grid(
        float(config["ra"]),
        float(config["dec"]),
        float(config["radius_degrees"]),
        args.grid_dimension,
    )
    max_file_bytes = int(args.max_file_mib * MIB)
    candidates = [
        candidate
        for row in rows
        if (
            candidate := candidate_from_row(
                tap,
                row,
                grid,
                quality_columns,
            )
        )
        is not None
        and candidate["bytes"] <= max_file_bytes
    ]
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for candidate in candidates:
        groups[candidate["group_id"]].append(candidate)

    selected: list[dict[str, Any]] = []
    selected_uris: set[str] = set()
    active_groups: set[str] = set()
    disabled_groups: set[str] = set()
    disabled_uris: set[str] = set()
    covered_cells: set[int] = set()
    group_filters: dict[str, set[str]] = defaultdict(set)
    global_filters: set[str] = set()
    decisions: list[dict[str, Any]] = []
    group_dispositions: dict[str, str] = {}
    total_bytes = 0
    max_total = int(args.max_total_mib * MIB) if args.max_total_mib is not None else None
    stop_reason = "no_additional_gain"
    budget_blocked = False
    iteration = 0
    while len(selected) < args.max_products:
        coverage = len(covered_cells) / len(grid.points) if grid.points else 0.0
        if coverage >= args.target_coverage and len(global_filters) >= args.minimum_filters:
            stop_reason = "target_satisfied"
            break
        proposals = []
        remaining_slots = args.max_products - len(selected)
        remaining_budget = None if max_total is None else max_total - total_bytes
        for group_id, members in groups.items():
            available = [
                item
                for item in members
                if item["uri"] not in selected_uris and item["uri"] not in disabled_uris
            ]
            if group_id in disabled_groups or not available:
                continue
            if group_id not in active_groups:
                proposal = simulate_starter(
                    group_id,
                    available,
                    minimum=args.min_group_observation_ids,
                    covered_cells=covered_cells,
                    grid_size=len(grid.points),
                    options=args,
                )
                if proposal is None:
                    disabled_groups.add(group_id)
                    group_dispositions[group_id] = "insufficient_group_observation_ids_after_file_cap"
                    continue
            else:
                proposal_candidates = []
                for item in available:
                    metrics = candidate_metrics(
                        [item],
                        covered_cells=covered_cells,
                        selected_group_filters=group_filters[group_id],
                        grid_size=len(grid.points),
                        coverage_weight=args.coverage_weight,
                        filter_weight=args.filter_weight,
                        exponent=args.size_penalty_exponent,
                    )
                    proposal_candidates.append(
                        {
                            "type": "additional_product",
                            "group_id": group_id,
                            "candidates": [item],
                            "metrics": metrics,
                        }
                    )
                if not proposal_candidates:
                    continue
                proposal = min(proposal_candidates, key=candidate_order)
            reason = ""
            if len(proposal["candidates"]) > remaining_slots:
                reason = "insufficient_product_slots"
            elif remaining_budget is not None and proposal["metrics"]["bytes"] > remaining_budget:
                reason = "insufficient_group_budget" if proposal["type"] == "group_activation" else "exceeds_remaining_budget"
            if reason:
                budget_blocked = budget_blocked or "budget" in reason
                if proposal["type"] == "group_activation":
                    disabled_groups.add(group_id)
                    group_dispositions[group_id] = reason
                else:
                    disabled_uris.add(proposal["candidates"][0]["uri"])
                decisions.append(
                    decision_row(iteration + 1, proposal, total_bytes, total_bytes, "skipped", reason)
                )
                continue
            proposals.append(proposal)
        if not proposals:
            stop_reason = (
                "total_budget_exhausted"
                if max_total is not None and budget_blocked
                else "no_additional_gain"
            )
            break
        best = min(proposals, key=candidate_order)
        iteration += 1
        for proposal in proposals:
            if proposal is best:
                continue
            decisions.append(
                decision_row(iteration, proposal, total_bytes, total_bytes, "compared", "lower_score")
            )
        if best["metrics"]["score_numerator"] <= 0:
            decisions.append(
                decision_row(iteration, best, total_bytes, total_bytes, "skipped", "no_additional_gain")
            )
            stop_reason = "no_additional_gain"
            break
        before = total_bytes
        active_groups.add(best["group_id"])
        group_dispositions[best["group_id"]] = "selected"
        for candidate in best["candidates"]:
            selected.append(candidate)
            selected_uris.add(candidate["uri"])
            covered_cells.update(candidate["cells"])
            group_filters[best["group_id"]].update(candidate["filters"])
            global_filters.update(candidate["filters"])
            total_bytes += candidate["bytes"]
        decisions.append(
            decision_row(iteration, best, before, total_bytes, "selected", "highest_score")
        )
    else:
        stop_reason = "maximum_products_reached"

    selected_products = []
    for rank, candidate in enumerate(selected, start=1):
        product = dict(candidate["row"])
        product["selection_rank"] = rank
        product["observation_key"] = candidate["group_name"]
        selected_products.append(product)
    selected_by_group: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for candidate in selected:
        selected_by_group[candidate["group_id"]].append(candidate)
    group_rows = []
    phase1_groups = {
        group["group_id"]: group
        for group in phase1["groups"]
        if group.get("qualifies")
    }
    for group_id in sorted(phase1_groups):
        available = groups.get(group_id, [])
        chosen = selected_by_group.get(group_id, [])
        phase1_group = phase1_groups[group_id]
        group_rows.append(
            {
                "observation_group": (
                    available[0]["group_name"]
                    if available
                    else phase1_group["observation_group"]
                ),
                "available_ids": len({item["obs_id"] for item in available}),
                "available_uris": len(available),
                "available_bytes": sum(item["bytes"] for item in available),
                "selected_ids": len({item["obs_id"] for item in chosen}),
                "selected_uris": len(chosen),
                "selected_bytes": sum(item["bytes"] for item in chosen),
                "disposition": (
                    "selected"
                    if chosen
                    else group_dispositions.get(
                        group_id,
                        (
                            "no_products_within_file_cap"
                            if not available
                            else "no_additional_gain"
                        ),
                    )
                ),
                "phase1_total_bytes": phase1_group.get("total_bytes", 0),
            }
        )

    coverage_fraction = len(covered_cells) / len(grid.points) if grid.points else 0.0
    target_filters = sorted({token for row in rows for token in tap.filter_keys(row.get("filters"))})
    per_cell_filters = [set() for _ in grid.points]
    for candidate in selected:
        for cell in candidate["cells"]:
            per_cell_filters[cell].update(candidate["filters"])
    mean_beauty = (
        sum(len(value) / len(target_filters) for value in per_cell_filters) / len(per_cell_filters)
        if target_filters and per_cell_filters
        else 0.0
    )
    options = {
        "max_file_mib": args.max_file_mib,
        "max_total_mib": args.max_total_mib,
        "max_products": args.max_products,
        "target_coverage": args.target_coverage,
        "minimum_filters": args.minimum_filters,
        "min_group_observation_ids": args.min_group_observation_ids,
        "coverage_weight": args.coverage_weight,
        "filter_weight": args.filter_weight,
        "size_penalty_exponent": args.size_penalty_exponent,
        "grid_dimension": args.grid_dimension,
    }
    summary = {
        "qualified_group_count": len(phase1_groups),
        "selected_group_count": len(selected_by_group),
        "selected_product_count": len(selected_products),
        "selected_size_bytes": total_bytes,
        "selected_size_mib": round(total_bytes / MIB, 6),
        "coverage_fraction": coverage_fraction,
        "mean_beautiful_coverage": mean_beauty,
        "selected_filter_count": len(global_filters),
        "stop_reason": stop_reason,
    }
    output_dir = args.output_dir.expanduser().resolve()
    selection_path = output_dir / "phase-2-selection.json"
    selection = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "mast-composite-phase-2-selection",
        "created_at": now_iso(),
        "source": {"path": str(input_path), "sha256": sha256_file(input_path)},
        "configuration": config,
        "options": options,
        "summary": summary,
        "selected_products": selected_products,
        "selected_groups": group_rows,
        "decisions": decisions,
    }
    write_json(selection_path, selection)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "mast-composite-download-manifest",
        "created_at": now_iso(),
        "source": {"path": str(selection_path), "sha256": sha256_file(selection_path)},
        "target": config["target"],
        "position": {
            "ra": config["ra"],
            "dec": config["dec"],
            "radius_degrees": config["radius_degrees"],
        },
        "summary": summary,
        "selected_products": selected_products,
    }
    write_json(output_dir / "phase-2-download-manifest.json", manifest)
    write_csv(
        output_dir / "phase-2-decisions.csv",
        [
            "iteration",
            "candidate_type",
            "observation_group",
            "observation_ids",
            "new_cells",
            "new_coverage_fraction",
            "new_filters",
            "new_filter_count",
            "score_numerator",
            "score_cost",
            "score",
            "candidate_bytes",
            "budget_before_bytes",
            "budget_after_bytes",
            "status",
            "reason",
        ],
        decisions,
    )
    write_csv(
        output_dir / "phase-2-groups.csv",
        list(group_rows[0]) if group_rows else ["observation_group"],
        group_rows,
    )
    selected_counts = Counter(
        token for product in selected_products for token in tap.filter_keys(product.get("filters"))
    )
    plot_filter_funnel(
        output_dir / "phase-2-filter-funnel.png",
        phase1["filter_funnel"],
        title=f"{config['target']}: Phase 2 selection ({summary['selected_product_count']} files)",
        selected_counts=dict(selected_counts),
    )
    plot_beauty(
        output_dir / "phase-2-beauty-overlay.png",
        tap,
        grid,
        selected,
        len(target_filters),
        (
            f"{config['target']} beauty={mean_beauty:.3f}, "
            f"coverage={coverage_fraction:.3f}, files={len(selected)}"
        ),
    )
    LOGGER.info(
        "Phase 2 complete groups=%s files=%s MiB=%.2f coverage=%.3f stop=%s",
        len(selected_by_group),
        len(selected),
        total_bytes / MIB,
        coverage_fraction,
        stop_reason,
    )
    return 0


def decision_row(
    iteration: int,
    proposal: dict[str, Any],
    budget_before: int,
    budget_after: int,
    status: str,
    reason: str,
) -> dict[str, Any]:
    candidates = proposal["candidates"]
    metrics = proposal["metrics"]
    return {
        "iteration": iteration,
        "candidate_type": proposal["type"],
        "observation_group": candidates[0]["group_name"],
        "observation_ids": ";".join(candidate["obs_id"] for candidate in candidates),
        "new_cells": metrics["new_cells"],
        "new_coverage_fraction": metrics["new_coverage_fraction"],
        "new_filters": ";".join(metrics["new_filters"]),
        "new_filter_count": metrics["new_filter_count"],
        "score_numerator": metrics["score_numerator"],
        "score_cost": metrics["score_cost"],
        "score": metrics["score"],
        "candidate_bytes": metrics["bytes"],
        "budget_before_bytes": budget_before,
        "budget_after_bytes": budget_after,
        "status": status,
        "reason": reason,
    }


def positive_float(value: str) -> float:
    number = float(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--log-level", choices=("DEBUG", "INFO", "WARNING", "ERROR"), default="INFO")
    subparsers = parser.add_subparsers(dest="command", required=True)

    qualify = subparsers.add_parser("qualify", help="Phase 1: query TAP and qualify observation groups")
    qualify.add_argument("--target")
    qualify.add_argument("--ra", type=float)
    qualify.add_argument("--dec", type=float)
    qualify.add_argument("--radius", type=positive_float, default=0.05)
    qualify.add_argument("--missions", default="JWST,HST,HLA")
    qualify.add_argument("--per-filter-limit", type=positive_int, default=1000)
    qualify.add_argument("--max-file-mib", type=positive_float, default=2048)
    qualify.add_argument("--min-group-observation-ids", type=positive_int, default=3)
    qualify.add_argument("--timeout", type=positive_float, default=180)
    qualify.add_argument("--retries", type=int, default=5)
    qualify.add_argument("--run-dir", type=Path, required=True)
    qualify.set_defaults(func=run_qualify)

    select = subparsers.add_parser("select", help="Phase 2: choose groups and products offline")
    select.add_argument("--input", type=Path, required=True)
    select.add_argument("--output-dir", type=Path, required=True)
    select.add_argument("--max-file-mib", type=positive_float, default=2048)
    select.add_argument("--max-total-mib", type=positive_float)
    select.add_argument("--max-products", type=positive_int, default=200)
    select.add_argument("--target-coverage", type=float, default=0.8)
    select.add_argument("--minimum-filters", type=int, default=3)
    select.add_argument("--min-group-observation-ids", type=positive_int, default=3)
    select.add_argument("--coverage-weight", type=float, default=0.65)
    select.add_argument("--filter-weight", type=float, default=0.35)
    select.add_argument("--size-penalty-exponent", type=float, default=1.0)
    select.add_argument("--grid-dimension", type=positive_int, default=48)
    select.set_defaults(func=run_select)

    render = subparsers.add_parser(
        "render",
        help="Visualize the selected Phase 2 science-product footprints",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  # Colour every selected footprint by filter (default)
  mast_composite_pipeline.py render --input phase-2-download-manifest.json

  # Preview each observation stack with the AOSImage group-local palette
  mast_composite_pipeline.py render --input phase-2-selection.json \\
    --color-by observation-group --label-by rank

The command uses only saved Phase 2 metadata. It does not query TAP or
download/open FITS pixel data.
""",
    )
    render.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Phase 2 selection JSON or Phase 2 download manifest.",
    )
    render.add_argument(
        "--output",
        type=Path,
        help="PNG/PDF/SVG output; defaults beside the input manifest.",
    )
    render.add_argument(
        "--svg-output",
        type=Path,
        help="Optional additional vector SVG output.",
    )
    render.add_argument(
        "--color-by",
        choices=COLOR_BY_OPTIONS,
        default="filter",
        help="Colour footprints by filter, observation-group stack, or mission.",
    )
    render.add_argument(
        "--preferred-colors",
        type=Path,
        help="Optional JSON object mapping filters/categories to #RRGGBB colours.",
    )
    render.add_argument(
        "--color-key-output",
        type=Path,
        help="Colour/product assignment JSON; defaults beside the rendered image.",
    )
    render.add_argument(
        "--label-by",
        choices=("none", "rank", "filter", "group"),
        default="none",
        help="Optional label drawn at each product centre (default: none).",
    )
    render.add_argument(
        "--dpi",
        type=positive_int,
        default=180,
        help="Raster output resolution (default: 180).",
    )
    render.set_defaults(func=run_render)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    if getattr(args, "retries", 0) < 0:
        parser.error("--retries cannot be negative")
    if args.command == "select":
        if not 0 <= args.target_coverage <= 1:
            parser.error("--target-coverage must be in [0,1]")
        if args.minimum_filters < 0:
            parser.error("--minimum-filters cannot be negative")
        if args.coverage_weight < 0 or args.filter_weight < 0:
            parser.error("selection weights cannot be negative")
        if args.size_penalty_exponent < 0:
            parser.error("--size-penalty-exponent cannot be negative")
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        LOGGER.exception("Composite pipeline failed")
        raise
