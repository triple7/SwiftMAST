#!/usr/bin/env python3
"""Query MAST CAOM TAP and greedily select useful science-image products.

The initial query is metadata-only: it does not download FITS headers or FITS
pixels. It returns the product URI, archive metadata, sky footprint, dimensions,
pixel scale, and estimated file size needed for preliminary selection/ranking.

Flow:
    1. Resolve --target, unless explicit --ra/--dec coordinates are supplied.
    2. Build and submit one TAP query, or one query per mission when
       --balanced-missions is enabled.
    3. Convert TAP array rows into named Python dictionaries.
    4. When --select-products is enabled, prepare each mission independently,
       group candidates by observation, and run hierarchical incremental greedy
       selection using coverage/filter indexes and priority heaps.
    5. Optionally cache selected FITS files with ``--download-selected``.
    6. Emit the original query rows plus availability statistics and, when
       requested, the ordered product and observation-group selection.

The query and selector are metadata-only unless ``--download-selected`` is
supplied. That option downloads only the greedy result into SwiftMAST's normal
``Documents/MAST`` cache layout, writes the CAOM sidecar used by the Swift cache
scanner, and reuses complete files already present there.

Dependency:
    python3 -m pip install requests

Examples:
    python3 Sources/scripts/greedy_mast_tap_selection.py --target "NGC 628" --limit 10

    python3 Sources/scripts/greedy_mast_tap_selection.py \
        --ra 24.174 --dec 15.783 --radius 0.1 \
        --missions JWST,HST,HLA --balanced-missions --limit 100 \
        --output demo-mast-selected-columns-query.txt

    python3 Sources/scripts/greedy_mast_tap_selection.py \
        --target "NGC 628" --missions JWST,HST,HLA \
        --balanced-missions --limit 100 --select-products \
        --max-products 20 --max-total-mb 500 \
        --output hierarchical-science-product-report.json

    python3 Sources/scripts/greedy_mast_tap_selection.py \
        --target "NGC 628" --missions JWST,HST,HLA \
        --balanced-missions --limit 100 --download-selected \
        --max-products 20 --max-total-mb 500 \
        --output hierarchical-science-product-report.json

    python3 Sources/scripts/greedy_mast_tap_selection.py --schema
"""

from __future__ import annotations

import argparse
import heapq
import json
import logging
import math
import os
import re
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


MAST_TAP_URL = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
MAST_API_URL = "https://mast.stsci.edu/api/v0/invoke"
MAST_DOWNLOAD_URL = "https://mast.stsci.edu/api/v0.1/Download/file"
DEFAULT_MISSIONS = ("JWST", "HST", "HLA")
TAP_TABLES = ("dbo.obspointing", "dbo.caomplane", "dbo.caomartifact")
MIB = 1_048_576
IGNORED_FILTERS = {"", "CLEAR", "DETECTION", "N/A", "NA", "NONE", "UNKNOWN", "WHITE"}
FILTER_TOKEN = re.compile(r"^(?:FQ?|G)\d{2,4}[A-Z0-9]*$")
LOGGER = logging.getLogger("swiftmast.greedy_mast_tap")
TAP_ORDERINGS = {
    "group": "o.obs_collection, o.instrument_name, o.obs_id, o.filters",
    "min-size": "a.contentlength ASC, o.instrument_name, o.obs_id, o.filters",
    "max-size": "a.contentlength DESC, o.instrument_name, o.obs_id, o.filters",
}

# Keep this projection aligned with SwiftMAST's `.targetCompositeSelection`
# profile. Required selection fields are followed by useful optional plane
# metadata; the latter is allowed to be null and must never reject a product.
APPLICATION_COLUMNS = (
    "o.obsid",
    "o.obs_id",
    "o.obs_collection",
    "o.instrument_name",
    "o.target_name",
    "o.filters",
    "o.calib_level",
    "o.dataproduct_type",
    "o.intenttype",
    "o.datarights",
    "o.s_ra",
    "o.s_dec",
    "o.s_region",
    "o.t_exptime",
    "o.t_min",
    "o.t_max",
    "o.em_min",
    "o.em_max",
    "o.wavelength_region",
    "o.proposal_id",
    "o.project",
    "o.provenance_name",
    "p.posdimension1",
    "p.posdimension2",
    "p.possamplesize",
    "COALESCE(a.datauri, o.dataurl) AS datauri",
    "COALESCE(p.previewuri, o.jpegurl) AS previewuri",
    "a.productfilename",
    "a.contenttype",
    "a.contentlength",
)


# ---------------------------------------------------------------------------
# Selection configuration and in-memory state
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class SelectionOptions:
    """Controls the optional hierarchical science-product selector."""

    max_products: int = 20
    max_product_bytes: int = 70 * MIB
    max_total_bytes: int | None = None
    target_coverage: float = 0.80
    minimum_filters: int = 3
    coverage_weight: float = 0.65
    filter_weight: float = 0.35
    size_penalty_exponent: float = 1.0
    grid_dimension: int = 48


@dataclass(frozen=True)
class CoverageGrid:
    """Fixed target samples used to approximate the union of sky footprints."""

    points: tuple[tuple[float, float], ...]
    target_area_square_degrees: float

    def fraction_for_count(self, count: int) -> float:
        """Convert a covered-cell count into a target coverage fraction."""

        return min(count / len(self.points), 1.0) if self.points else 0.0


@dataclass
class CandidateState:
    """Cached mutable score state for one eligible science FITS product."""

    product: dict[str, Any]
    identity: str
    mission: str
    instrument: str
    observation_key: str
    filters: frozenset[str]
    covered_cells: frozenset[int]
    file_size_bytes: int
    uncovered_cell_count: int
    unseen_filter_count: int
    score: float = 0.0
    version: int = 0
    active: bool = True

    @property
    def group_id(self) -> tuple[str, str, str]:
        """Identify the mission/instrument/observation group containing the product."""

        return self.mission, self.instrument, self.observation_key


@dataclass
class PreparedBranch:
    """One mission branch prepared before branches are combined for selection."""

    mission: str
    candidates: list[CandidateState]
    observation_groups: dict[tuple[str, str, str], list[CandidateState]]
    exclusions: list[dict[str, Any]]
    fetched_count: int


@dataclass
class ObservationGroupQueue:
    """Priority queue for the active products belonging to one observation."""

    group_id: tuple[str, str, str]
    candidate_heap: list[tuple[Any, ...]] = field(default_factory=list)
    version: int = 0


# ---------------------------------------------------------------------------
# Logging, HTTP, target resolution, and TAP requests
# ---------------------------------------------------------------------------

def configure_logging(level: str, log_file: Path | None) -> None:
    """Log to the terminal by default and optionally duplicate logs to a file."""

    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    if log_file is not None:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=handlers,
        force=True,
    )


def requests_session(retries: int) -> requests.Session:
    """Create a retrying MAST session for rate limits and transient server errors."""

    retry = Retry(
        total=retries,
        connect=retries,
        read=retries,
        status=retries,
        backoff_factor=2,
        allowed_methods=frozenset({"GET", "POST"}),
        status_forcelist=(429, 500, 502, 503, 504),
        respect_retry_after_header=True,
        raise_on_status=False,
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    session.headers.update(
        {
            "Accept": "application/json",
            "Accept-Encoding": "identity",
            "User-Agent": "SwiftMAST-TAP-query/2.0",
        }
    )
    return session


def post_form_json(
    url: str,
    values: dict[str, str],
    timeout: float,
    retries: int = 5,
) -> dict[str, Any]:
    """POST form-encoded values and decode a JSON response."""

    started = time.monotonic()
    LOGGER.debug(
        "HTTP POST started url=%s timeout_seconds=%s retries=%s",
        url,
        timeout,
        retries,
    )
    with requests_session(retries) as session:
        try:
            response = session.post(url, data=values, timeout=timeout)
        except requests.RequestException as error:
            LOGGER.error(
                "HTTP POST failed url=%s elapsed_seconds=%.3f error=%s",
                url,
                time.monotonic() - started,
                error,
            )
            raise RuntimeError(f"Could not query MAST: {error}") from error
        if response.status_code >= 400:
            detail = " ".join(response.text[:500].split())
            suffix = f" Response: {detail}" if detail else ""
            LOGGER.error(
                "HTTP POST failed url=%s status=%s elapsed_seconds=%.3f",
                url,
                response.status_code,
                time.monotonic() - started,
            )
            raise RuntimeError(
                f"MAST returned HTTP {response.status_code} after {retries} retries.{suffix}"
            )

    try:
        decoded = response.json()
    except requests.exceptions.JSONDecodeError as error:
        raise RuntimeError(f"MAST did not return JSON: {response.text[:500]}") from error

    if not isinstance(decoded, dict):
        raise RuntimeError("MAST returned an unexpected JSON value")
    LOGGER.debug(
        "HTTP POST finished url=%s status=%s elapsed_seconds=%.3f",
        url,
        response.status_code,
        time.monotonic() - started,
    )
    return decoded


def query_tap(adql: str, timeout: float = 120, retries: int = 5) -> dict[str, Any]:
    """Submit an ADQL query to the synchronous MAST CAOM TAP endpoint."""

    started = time.monotonic()
    LOGGER.info("TAP query started timeout_seconds=%s retries=%s", timeout, retries)
    response = post_form_json(
        MAST_TAP_URL,
        {
            "REQUEST": "doQuery",
            "LANG": "ADQL",
            "QUERY": adql,
            # MAST uses this parameter name for its JSON representation.
            "responseformat": "json",
        },
        timeout,
        retries,
    )

    # Successful MAST JSON responses contain `info` and `data`. TAP errors may
    # instead be returned as a different JSON object.
    if not isinstance(response.get("info"), list) or not isinstance(response.get("data"), list):
        raise RuntimeError(f"Unexpected TAP response: {json.dumps(response)[:500]}")
    LOGGER.info(
        "TAP query finished rows=%s elapsed_seconds=%.3f",
        len(response["data"]),
        time.monotonic() - started,
    )
    return response


def execute_tap_queries(
    jobs: list[tuple[str, str]],
    *,
    timeout: float,
    retries: int,
    workers: int,
    require_all: bool,
) -> tuple[list[tuple[str, dict[str, Any], str]], dict[str, str]]:
    """Execute labeled TAP queries with bounded concurrency and partial recovery."""

    responses: dict[str, tuple[dict[str, Any], str]] = {}
    failures: dict[str, str] = {}
    worker_count = min(max(workers, 1), max(len(jobs), 1), 4)

    def execute(label: str, adql: str) -> dict[str, Any]:
        LOGGER.info("TAP branch query started branch=%s", label)
        started = time.monotonic()
        response = query_tap(adql, timeout=timeout, retries=retries)
        LOGGER.info(
            "TAP branch query finished branch=%s rows=%s elapsed_seconds=%.3f",
            label,
            len(response.get("data", [])),
            time.monotonic() - started,
        )
        return response

    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = {
            executor.submit(execute, label, adql): (label, adql)
            for label, adql in jobs
        }
        for future in as_completed(futures):
            label, adql = futures[future]
            try:
                responses[label] = future.result(), adql
            except RuntimeError as error:
                failures[label] = str(error)
                LOGGER.warning("TAP branch query failed branch=%s error=%s", label, error)

    if failures and require_all:
        detail = "; ".join(f"{label}: {message}" for label, message in sorted(failures.items()))
        raise RuntimeError(f"One or more required TAP queries failed: {detail}")
    if not responses:
        detail = "; ".join(f"{label}: {message}" for label, message in sorted(failures.items()))
        raise RuntimeError(f"All TAP queries failed: {detail}")

    ordered = [
        (label, responses[label][0], responses[label][1])
        for label, _ in jobs
        if label in responses
    ]
    return ordered, failures


def resolve_target(target: str, timeout: float = 30, retries: int = 5) -> tuple[float, float]:
    """Resolve a target name through Mast.Name.Lookup."""

    started = time.monotonic()
    LOGGER.info("Target resolution started target=%r", target)
    mast_request = {
        "service": "Mast.Name.Lookup",
        "params": {"input": target, "format": "json"},
        "format": "json",
    }
    response = post_form_json(
        MAST_API_URL,
        {"request": json.dumps(mast_request, separators=(",", ":"))},
        timeout,
        retries,
    )
    coordinates = response.get("resolvedCoordinate")
    if not isinstance(coordinates, list) or not coordinates:
        raise RuntimeError(f"MAST could not resolve target {target!r}")

    first = coordinates[0]
    try:
        position = float(first["ra"]), float(first["decl"])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"Invalid target-resolution response: {first!r}") from error
    LOGGER.info(
        "Target resolution finished target=%r ra=%.8f dec=%.8f elapsed_seconds=%.3f",
        target,
        position[0],
        position[1],
        time.monotonic() - started,
    )
    return position


# ---------------------------------------------------------------------------
# ADQL construction and TAP response conversion
# ---------------------------------------------------------------------------

def adql_strings(values: list[str] | tuple[str, ...]) -> str:
    """Return safely quoted ADQL string literals."""

    return ",".join("'" + value.replace("'", "''") + "'" for value in values)


def parse_csv_values(raw: str) -> list[str]:
    """Parse a required comma-separated CLI value and normalize it to uppercase."""

    values = [value.strip().upper() for value in raw.split(",") if value.strip()]
    if not values:
        raise ValueError("at least one value is required")
    return values


def parse_column_values(raw: str) -> list[str]:
    """Parse simple column references accepted by the diagnostic override."""

    columns = [value.strip() for value in raw.split(",") if value.strip()]
    pattern = re.compile(r"^(?:(?:o|p|a)\.)?(?:\*|[A-Za-z_][A-Za-z0-9_]*)$")
    invalid = [column for column in columns if pattern.fullmatch(column) is None]
    if invalid:
        raise ValueError(
            "--columns accepts simple names such as o.obs_id,p.posdimension1,a.datauri; "
            f"invalid: {', '.join(invalid)}"
        )
    return columns


def build_science_product_query(
    *,
    ra: float,
    dec: float,
    radius: float,
    missions: list[str],
    filters: list[str],
    limit: int,
    calibration_levels: list[int] | None = None,
    product_types: list[str] | None = None,
    columns: list[str] | None = None,
    eligibility_filter_location: str = "local",
    max_product_bytes: int | None = None,
    tap_order: str = "group",
) -> str:
    """Build candidate ADQL with configurable static filtering and ordering.

    ``eligibility_filter_location="tap"`` pushes checks that never depend on
    prior greedy choices into MAST. Coverage/filter marginal-gain calculations
    remain local because they change after every selected product.
    """

    calibration_levels = calibration_levels or [3, 4]
    product_types = product_types or ["IMAGE", "CUBE"]
    if eligibility_filter_location not in {"local", "tap"}:
        raise ValueError("eligibility_filter_location must be 'local' or 'tap'")
    if tap_order not in TAP_ORDERINGS:
        raise ValueError(f"unsupported TAP ordering: {tap_order}")
    predicates = [
        "CONTAINS("
        "POINT('ICRS', o.s_ra, o.s_dec), "
        f"CIRCLE('ICRS', {ra:.12g}, {dec:.12g}, {radius:.12g})"
        ") = 1",
        f"o.obs_collection IN ({adql_strings(missions)})",
        "o.datarights = 'PUBLIC'",
        f"o.calib_level IN ({','.join(str(value) for value in calibration_levels)})",
        f"LOWER(o.dataproduct_type) IN ({adql_strings([value.lower() for value in product_types])})",
        "LOWER(a.productfilename) LIKE '%.fits'",
        "("
        "(o.obs_collection = 'JWST' AND LOWER(a.productfilename) LIKE '%_i2d.fits') "
        "OR (o.obs_collection IN ('HST','HLA') AND "
        "(LOWER(a.productfilename) LIKE '%_drz.fits' "
        "OR LOWER(a.productfilename) LIKE '%_drc.fits')) "
        "OR o.obs_collection NOT IN ('JWST','HST','HLA')"
        ")",
    ]

    if filters:
        escaped_filters = [value.replace("'", "''") for value in filters]
        filter_predicates = [f"UPPER(o.filters) LIKE '%{value}%'" for value in escaped_filters]
        predicates.append("(" + " OR ".join(filter_predicates) + ")")

    if eligibility_filter_location == "tap":
        predicates.extend(
            [
                "o.s_region IS NOT NULL",
                "o.filters IS NOT NULL",
                "o.instrument_name IS NOT NULL",
                "a.contentlength IS NOT NULL",
                "a.contentlength > 0",
                "(a.datauri IS NOT NULL OR o.dataurl IS NOT NULL)",
            ]
        )
        if max_product_bytes is not None:
            predicates.append(f"a.contentlength <= {max_product_bytes}")

    select_columns = ",\n        ".join(columns or APPLICATION_COLUMNS)

    return (
        f"SELECT TOP {limit}\n"
        f"    {select_columns}\n"
        "FROM dbo.obspointing AS o\n"
        "JOIN dbo.caomplane AS p ON p.planetid = o.objid\n"
        "JOIN dbo.caomartifact AS a ON a.planetid = p.planetid\n"
        "WHERE "
        + "\n  AND ".join(predicates)
        + f"\nORDER BY {TAP_ORDERINGS[tap_order]}"
    )


def build_schema_query() -> str:
    """Return the schema query for all tables used by the product query."""

    return (
        "SELECT table_name,column_name,datatype,unit,description "
        "FROM TAP_SCHEMA.columns "
        f"WHERE table_name IN ({adql_strings(TAP_TABLES)})"
    )


def coerce_tap_value(value: Any, datatype: str) -> Any:
    """Convert a TAP cell to its advertised scalar type when possible."""

    if value is None or value == "":
        return None
    try:
        if datatype in {"int", "integer", "long", "short"}:
            return int(value)
        if datatype in {"float", "double", "real"}:
            number = float(value)
            return number if math.isfinite(number) else None
        if datatype == "boolean":
            if isinstance(value, bool):
                return value
            normalized = str(value).strip().lower()
            if normalized in {"1", "true", "t"}:
                return True
            if normalized in {"0", "false", "f"}:
                return False
    except (TypeError, ValueError):
        return value
    return value


def named_rows(response: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert MAST's array rows into dictionaries using response `info`."""

    columns = response["info"]
    names = [str(column.get("name", f"column_{index}")) for index, column in enumerate(columns)]
    datatypes = [str(column.get("datatype", column.get("type", ""))).lower() for column in columns]

    output: list[dict[str, Any]] = []
    for raw_row in response["data"]:
        if not isinstance(raw_row, list):
            continue
        output.append(
            {
                name: coerce_tap_value(raw_row[index], datatypes[index])
                if index < len(raw_row)
                else None
                for index, name in enumerate(names)
            }
        )
    return output


def column_availability(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Measure non-null availability for every returned TAP field."""

    if not rows:
        return []
    keys = sorted({key for row in rows for key in row})
    total = len(rows)
    return [
        {
            "column": key,
            "available_rows": sum(row.get(key) not in (None, "") for row in rows),
            "total_rows": total,
            "availability_percent": round(
                sum(row.get(key) not in (None, "") for row in rows) * 100 / total,
                1,
            ),
        }
        for key in keys
    ]


def mission_summary(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return row counts and per-column availability for each collection."""

    missions = sorted(
        {
            str(row.get("obs_collection"))
            for row in rows
            if row.get("obs_collection") not in (None, "")
        }
    )
    summary = []
    for mission in missions:
        mission_rows = [
            row for row in rows if str(row.get("obs_collection")) == mission
        ]
        summary.append(
            {
                "mission": mission,
                "row_count": len(mission_rows),
                "column_availability": column_availability(mission_rows),
            }
        )
    return summary


# ---------------------------------------------------------------------------
# Sky-footprint, filter, and observation-group utilities
# ---------------------------------------------------------------------------

def wrapped_degrees(value: float) -> float:
    """Normalize an angular difference to the [-180, 180] degree interval."""

    value %= 360.0
    return value - 360.0 if value > 180.0 else value


def angular_distance_degrees(lhs: tuple[float, float], rhs: tuple[float, float]) -> float:
    """Return great-circle distance between two ICRS positions in degrees."""

    ra1, dec1 = (math.radians(value) for value in lhs)
    ra2, dec2 = (math.radians(value) for value in rhs)
    cosine = (
        math.sin(dec1) * math.sin(dec2)
        + math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2)
    )
    return math.degrees(math.acos(min(1.0, max(-1.0, cosine))))


def parse_s_region(value: str) -> tuple[tuple[str, tuple[float, ...]], ...] | None:
    """Parse the CIRCLE/POLYGON STC-S forms returned by the CAOM query."""

    tokens = value.split()
    index = 0
    shapes: list[tuple[str, tuple[float, ...]]] = []
    while index < len(tokens):
        shape = tokens[index].upper()
        if shape not in {"CIRCLE", "POLYGON"}:
            return None
        index += 1
        if index < len(tokens) and tokens[index].upper() in {"ICRS", "J2000"}:
            index += 1
        start = index
        while index < len(tokens) and tokens[index].upper() not in {"CIRCLE", "POLYGON"}:
            index += 1
        try:
            numbers = tuple(float(token) for token in tokens[start:index])
        except ValueError:
            return None
        if shape == "CIRCLE" and len(numbers) == 3 and numbers[2] > 0:
            shapes.append((shape, numbers))
        elif shape == "POLYGON" and len(numbers) >= 6 and len(numbers) % 2 == 0:
            shapes.append((shape, numbers))
        else:
            return None
    return tuple(shapes) if shapes else None


def polygon_contains(point: tuple[float, float], numbers: tuple[float, ...]) -> bool:
    """Test a sky point against a small STC-S polygon in a local tangent plane."""

    point_ra, point_dec = point
    scale = max(abs(math.cos(math.radians(point_dec))), 0.01)
    vertices = [
        (wrapped_degrees(numbers[index] - point_ra) * scale, numbers[index + 1] - point_dec)
        for index in range(0, len(numbers), 2)
    ]
    inside = False
    previous = len(vertices) - 1
    for current, (x_current, y_current) in enumerate(vertices):
        x_previous, y_previous = vertices[previous]
        crosses = (y_current > 0) != (y_previous > 0)
        if crosses:
            edge_x = x_current + (x_previous - x_current) * (-y_current) / (
                y_previous - y_current
            )
            if edge_x >= 0:
                inside = not inside
        previous = current
    return inside


def region_contains(
    point: tuple[float, float],
    shapes: tuple[tuple[str, tuple[float, ...]], ...],
) -> bool:
    """Return whether a point is inside any parsed CIRCLE or POLYGON component."""

    for shape, numbers in shapes:
        if shape == "CIRCLE":
            if angular_distance_degrees(point, (numbers[0], numbers[1])) <= numbers[2]:
                return True
        elif polygon_contains(point, numbers):
            return True
    return False


def make_coverage_grid(ra: float, dec: float, radius: float, dimension: int) -> CoverageGrid:
    """Sample a target cone with a deterministic grid for coverage estimation."""

    dimension = min(max(dimension, 4), 200)
    ra_scale = max(abs(math.cos(math.radians(dec))), 0.01)
    points: list[tuple[float, float]] = []
    for row in range(dimension):
        normalized_y = ((row + 0.5) / dimension) * 2.0 - 1.0
        for column in range(dimension):
            normalized_x = ((column + 0.5) / dimension) * 2.0 - 1.0
            if normalized_x * normalized_x + normalized_y * normalized_y > 1.0:
                continue
            sample_dec = min(90.0, max(-90.0, dec + normalized_y * radius))
            sample_ra = (ra + normalized_x * radius / ra_scale) % 360.0
            points.append((sample_ra, sample_dec))
    radius_radians = math.radians(radius)
    steradians = 2.0 * math.pi * (1.0 - math.cos(radius_radians))
    area = steradians * (180.0 / math.pi) ** 2
    return CoverageGrid(tuple(points or [(ra, dec)]), area)


def filter_keys(value: Any) -> frozenset[str]:
    """Extract useful normalized filter names and remove pseudo-filter labels."""

    if not isinstance(value, str):
        return frozenset()
    return frozenset(
        token
        for token in (part.strip().upper() for part in re.split(r"[;,|\s]+", value))
        if token not in IGNORED_FILTERS
    )


def observation_group_key(product: dict[str, Any]) -> str:
    """Derive a stable observation identifier shared by related filter products."""

    observation_id = str(product.get("obs_id") or "")
    collection = str(product.get("obs_collection") or "").upper()
    parts = observation_id.split("_")
    if collection == "JWST":
        return "_".join(parts[:3]) if len(parts) >= 3 else observation_id
    if collection in {"HST", "HLA"} or observation_id.lower().startswith("hst_"):
        key: list[str] = []
        for part in parts:
            if (part.upper() == "CLEAR" or FILTER_TOKEN.fullmatch(part.upper())) and key:
                break
            key.append(part)
        return "_".join(key) or observation_id
    return observation_id


def selection_exclusion(product: dict[str, Any], reason: str) -> dict[str, Any]:
    """Create a compact audit record for a rejected candidate product."""

    return {
        "observation_id": product.get("obs_id"),
        "product_uri": product.get("datauri"),
        "reason": reason,
    }


def greedy_candidate_score(
    candidate: CandidateState,
    grid: CoverageGrid,
    options: SelectionOptions,
) -> float:
    """Score current marginal coverage and filters per size-adjusted download cost."""

    new_coverage = grid.fraction_for_count(candidate.uncovered_cell_count)
    benefit = (
        options.coverage_weight * new_coverage
        + options.filter_weight * candidate.unseen_filter_count
    )
    size_mib = max(candidate.file_size_bytes / MIB, 0.001)
    size_cost = max(size_mib**options.size_penalty_exponent, 0.000001)
    return benefit / size_cost


# ---------------------------------------------------------------------------
# Per-mission candidate preparation (performed before global combination)
# ---------------------------------------------------------------------------

def prepare_mission_branch(
    mission: str,
    products: list[dict[str, Any]],
    grid: CoverageGrid,
    options: SelectionOptions,
) -> PreparedBranch:
    """Validate and index one mission before any mission branches are combined."""

    candidates: list[CandidateState] = []
    exclusions: list[dict[str, Any]] = []
    seen: set[str] = set()
    for product in products:
        data_uri = str(product.get("datauri") or "").strip()
        identity = data_uri or "\x1f".join(
            str(product.get(key) or "")
            for key in ("obs_collection", "obs_id", "instrument_name", "filters")
        )
        if identity in seen:
            exclusions.append(selection_exclusion(product, "duplicate_product"))
            continue
        seen.add(identity)
        if not data_uri:
            exclusions.append(selection_exclusion(product, "missing_download_url"))
            continue
        try:
            size = int(product.get("contentlength"))
        except (TypeError, ValueError):
            exclusions.append(selection_exclusion(product, "missing_file_size"))
            continue
        if size <= 0:
            exclusions.append(selection_exclusion(product, "missing_file_size"))
            continue
        if size > options.max_product_bytes:
            exclusions.append(selection_exclusion(product, "exceeds_product_size_limit"))
            continue
        shapes = parse_s_region(str(product.get("s_region") or "").strip())
        if shapes is None:
            reason = "missing_footprint" if not product.get("s_region") else "invalid_footprint"
            exclusions.append(selection_exclusion(product, reason))
            continue
        filters = filter_keys(product.get("filters"))
        if not filters:
            exclusions.append(selection_exclusion(product, "missing_filter"))
            continue
        instrument = str(product.get("instrument_name") or "").strip().upper()
        if not instrument:
            exclusions.append(selection_exclusion(product, "missing_instrument"))
            continue
        cells = frozenset(
            index
            for index, point in enumerate(grid.points)
            if region_contains(point, shapes)
        )
        candidate = CandidateState(
            product=product,
            identity=identity,
            mission=mission,
            instrument=instrument,
            observation_key=observation_group_key(product),
            filters=filters,
            covered_cells=cells,
            file_size_bytes=size,
            uncovered_cell_count=len(cells),
            unseen_filter_count=len(filters),
        )
        candidate.score = greedy_candidate_score(candidate, grid, options)
        candidates.append(candidate)
    observation_groups: dict[tuple[str, str, str], list[CandidateState]] = defaultdict(list)
    for candidate in candidates:
        observation_groups[candidate.group_id].append(candidate)
    branch = PreparedBranch(
        mission,
        candidates,
        dict(observation_groups),
        exclusions,
        len(products),
    )
    LOGGER.info(
        "Mission branch prepared mission=%s fetched=%s eligible=%s excluded=%s observation_groups=%s",
        mission,
        len(products),
        len(candidates),
        len(exclusions),
        len(observation_groups),
    )
    return branch


def prepare_candidate_branches(
    response_rows: list[list[dict[str, Any]]],
    grid: CoverageGrid,
    options: SelectionOptions,
) -> list[PreparedBranch]:
    """Partition every TAP response by mission before creating the global selector."""

    branches: list[PreparedBranch] = []
    for rows in response_rows:
        rows_by_mission: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for product in rows:
            mission = str(product.get("obs_collection") or "UNKNOWN").upper()
            rows_by_mission[mission].append(product)
        for mission, mission_rows in sorted(rows_by_mission.items()):
            branches.append(prepare_mission_branch(mission, mission_rows, grid, options))
    return branches


def group_selected_products(products: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Restore selected product rows to observation groups for AOSImageStack use."""

    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for product in products:
        key = (
            str(product.get("obs_collection") or "").upper(),
            str(product.get("instrument_name") or "").upper(),
            str(product.get("observation_key") or observation_group_key(product)),
        )
        grouped[key].append(product)
    return [
        {
            "mission": mission,
            "instrument": instrument,
            "observation_key": observation_key,
            "product_count": len(group_products),
            "filters": sorted(
                {
                    filter_name
                    for product in group_products
                    for filter_name in filter_keys(product.get("filters"))
                }
            ),
            "total_size_bytes": sum(int(product.get("contentlength") or 0) for product in group_products),
            "products": group_products,
        }
        for (mission, instrument, observation_key), group_products in sorted(grouped.items())
    ]


# ---------------------------------------------------------------------------
# Hierarchical incremental greedy selection
# ---------------------------------------------------------------------------

class HierarchicalIncrementalGreedySelector:
    """Traverse group heaps and update only graph-adjacent candidates.

    Each observation group owns a product heap. The root heap stores the current
    best product from every group. Inverted indexes map coverage cells and filters
    back to candidates, so selecting one product only invalidates candidates that
    share newly acquired coverage or filters. Versioned heap entries are discarded
    lazily instead of removing arbitrary entries from Python's heap implementation.
    """

    def __init__(
        self,
        branches: list[PreparedBranch],
        grid: CoverageGrid,
        options: SelectionOptions,
    ) -> None:
        """Combine prepared branch indexes without flattening observation groups."""

        self.grid = grid
        self.options = options
        self.candidates: dict[str, CandidateState] = {}
        self.groups: dict[tuple[str, str, str], ObservationGroupQueue] = {}
        self.candidates_by_cell: dict[int, set[str]] = defaultdict(set)
        # Filter novelty is local to an observation group. Selecting F435W in
        # one group must not remove the F435W benefit from another group.
        self.candidates_by_filter: dict[
            tuple[tuple[str, str, str], str], set[str]
        ] = defaultdict(set)
        self.root_heap: list[tuple[Any, ...]] = []
        self.exclusions = [value for branch in branches for value in branch.exclusions]
        self.branch_fetched_counts: Counter[str] = Counter()
        for branch in branches:
            self.branch_fetched_counts[branch.mission] += branch.fetched_count
        self.metrics = {
            "candidate_score_updates": 0,
            "coverage_edge_visits": 0,
            "filter_edge_visits": 0,
            "candidate_heap_pops": 0,
            "group_heap_pops": 0,
            "full_candidate_rescans": 0,
        }

        for branch in branches:
            for group_id, branch_candidates in branch.observation_groups.items():
                for candidate in branch_candidates:
                    if candidate.identity in self.candidates:
                        self.exclusions.append(
                            selection_exclusion(candidate.product, "duplicate_product")
                        )
                        continue
                    self.candidates[candidate.identity] = candidate
                    group = self.groups.setdefault(group_id, ObservationGroupQueue(group_id))
                    heapq.heappush(group.candidate_heap, self._candidate_entry(candidate))
                    for cell in candidate.covered_cells:
                        self.candidates_by_cell[cell].add(candidate.identity)
                    for filter_name in candidate.filters:
                        self.candidates_by_filter[
                            (candidate.group_id, filter_name)
                        ].add(candidate.identity)

        for group in self.groups.values():
            self._publish_group(group)
        LOGGER.info(
            "Hierarchical selector initialized branches=%s candidates=%s observation_groups=%s exclusions=%s",
            len(branches),
            len(self.candidates),
            len(self.groups),
            len(self.exclusions),
        )

    @staticmethod
    def _candidate_key(candidate: CandidateState) -> tuple[Any, ...]:
        """Return deterministic heap ordering: score, gains, size, then identity."""

        return (
            -candidate.score,
            -candidate.uncovered_cell_count,
            -candidate.unseen_filter_count,
            candidate.file_size_bytes,
            candidate.identity,
        )

    def _candidate_entry(self, candidate: CandidateState) -> tuple[Any, ...]:
        """Attach the candidate version used to recognize stale heap entries."""

        return (*self._candidate_key(candidate), candidate.version)

    def _clean_group(self, group: ObservationGroupQueue) -> CandidateState | None:
        """Discard stale/inactive entries and return the group's current best product."""

        while group.candidate_heap:
            entry = group.candidate_heap[0]
            identity = entry[4]
            version = entry[5]
            candidate = self.candidates.get(identity)
            if candidate is not None and candidate.active and candidate.version == version:
                return candidate
            heapq.heappop(group.candidate_heap)
            self.metrics["candidate_heap_pops"] += 1
        return None

    def _publish_group(self, group: ObservationGroupQueue) -> None:
        """Publish a group's current best product to the root traversal heap."""

        group.version += 1
        best = self._clean_group(group)
        if best is not None:
            heapq.heappush(
                self.root_heap,
                (*self._candidate_key(best), group.group_id, group.version),
            )

    def _pop_best_candidate(self) -> CandidateState | None:
        """Traverse root then group heaps to obtain the globally best product."""

        while self.root_heap:
            entry = heapq.heappop(self.root_heap)
            self.metrics["group_heap_pops"] += 1
            group_id = entry[5]
            group_version = entry[6]
            group = self.groups[group_id]
            if group.version != group_version:
                continue
            best = self._clean_group(group)
            if best is None or self._candidate_key(best) != entry[:5]:
                self._publish_group(group)
                continue
            return best
        return None

    def _update_affected_candidates(
        self,
        selected: CandidateState,
        new_cells: set[int],
        new_group_filters: set[str],
    ) -> None:
        """Rescore spatial neighbors and same-group products sharing new filters."""

        affected: set[str] = set()
        for cell in new_cells:
            identities = self.candidates_by_cell.get(cell, set())
            self.metrics["coverage_edge_visits"] += len(identities)
            for identity in identities:
                candidate = self.candidates[identity]
                if candidate.active:
                    candidate.uncovered_cell_count -= 1
                    affected.add(identity)
        for filter_name in new_group_filters:
            identities = self.candidates_by_filter.get(
                (selected.group_id, filter_name), set()
            )
            self.metrics["filter_edge_visits"] += len(identities)
            for identity in identities:
                candidate = self.candidates[identity]
                if candidate.active:
                    candidate.unseen_filter_count -= 1
                    affected.add(identity)

        affected_groups = {selected.group_id}
        for identity in affected:
            candidate = self.candidates[identity]
            candidate.score = greedy_candidate_score(candidate, self.grid, self.options)
            candidate.version += 1
            self.metrics["candidate_score_updates"] += 1
            group = self.groups[candidate.group_id]
            heapq.heappush(group.candidate_heap, self._candidate_entry(candidate))
            affected_groups.add(candidate.group_id)
        for group_id in affected_groups:
            self._publish_group(self.groups[group_id])

    def select(self) -> dict[str, Any]:
        """Run greedy selection until coverage/filter goals or limits stop it.

        At every iteration the root/group heaps expose the active product with
        the highest current marginal-benefit-per-size score. After accepting it,
        inverted cell/filter indexes identify exactly which neighboring scores
        became stale. Unrelated candidates are not scanned or recalculated.
        """

        started = time.monotonic()
        LOGGER.info(
            "Hierarchical selection started candidates=%s max_products=%s target_coverage=%.3f minimum_filters=%s",
            len(self.candidates),
            self.options.max_products,
            self.options.target_coverage,
            self.options.minimum_filters,
        )
        selected_candidates: list[CandidateState] = []
        selected_cells: set[int] = set()
        selected_filters_by_group: dict[
            tuple[str, str, str], set[str]
        ] = defaultdict(set)
        # The global union remains useful for reporting and the overall
        # minimum-filter goal, but does not control a candidate's filter bonus.
        selected_filters: set[str] = set()
        total_size = 0
        steps: list[dict[str, Any]] = []
        budget_skipped = 0
        stop_reason = "no_eligible_candidates" if not self.candidates else "no_additional_benefit"

        # Greedy loop:
        #   1. Pop the globally best current candidate from the group hierarchy.
        #   2. Accept it if it fits the remaining byte budget.
        #   3. Add its new cells and filters to the accumulated target state.
        #   4. Rescore only candidates connected to those new cells or filters.
        while len(selected_candidates) < self.options.max_products:
            if (
                self.grid.fraction_for_count(len(selected_cells)) >= self.options.target_coverage
                and len(selected_filters) >= self.options.minimum_filters
            ):
                stop_reason = "target_satisfied"
                break

            candidate = self._pop_best_candidate()
            if candidate is None or candidate.score <= 0:
                stop_reason = (
                    "no_eligible_candidates"
                    if not self.candidates
                    else "no_additional_benefit"
                )
                break
            if (
                self.options.max_total_bytes is not None
                and total_size + candidate.file_size_bytes > self.options.max_total_bytes
            ):
                candidate.active = False
                candidate.version += 1
                budget_skipped += 1
                self._publish_group(self.groups[candidate.group_id])
                continue

            new_cells = set(candidate.covered_cells) - selected_cells
            new_group_filters = (
                set(candidate.filters) - selected_filters_by_group[candidate.group_id]
            )
            selected_candidates.append(candidate)
            selected_cells.update(new_cells)
            selected_filters_by_group[candidate.group_id].update(new_group_filters)
            selected_filters.update(candidate.filters)
            total_size += candidate.file_size_bytes
            candidate.active = False
            candidate.version += 1
            steps.append(
                {
                    "iteration": len(steps) + 1,
                    "mission": candidate.mission,
                    "instrument": candidate.instrument,
                    "observation_key": candidate.observation_key,
                    "observation_id": candidate.product.get("obs_id"),
                    "filters": sorted(candidate.filters),
                    "file_size_bytes": candidate.file_size_bytes,
                    "new_coverage_fraction": self.grid.fraction_for_count(len(new_cells)),
                    "new_filter_count": len(new_group_filters),
                    "score": candidate.score,
                    "cumulative_coverage_fraction": self.grid.fraction_for_count(len(selected_cells)),
                    "cumulative_filters": sorted(selected_filters),
                    "cumulative_size_bytes": total_size,
                }
            )
            LOGGER.info(
                "Selection step iteration=%s mission=%s instrument=%r observation_id=%r "
                "filters=%s score=%.8f new_coverage=%.6f cumulative_coverage=%.6f "
                "file_mib=%.2f cumulative_mib=%.2f",
                len(steps),
                candidate.mission,
                candidate.instrument,
                candidate.product.get("obs_id"),
                ",".join(sorted(candidate.filters)),
                candidate.score,
                self.grid.fraction_for_count(len(new_cells)),
                self.grid.fraction_for_count(len(selected_cells)),
                candidate.file_size_bytes / MIB,
                total_size / MIB,
            )
            self._update_affected_candidates(candidate, new_cells, new_group_filters)

        if len(selected_candidates) >= self.options.max_products:
            stop_reason = (
                "target_satisfied"
                if self.grid.fraction_for_count(len(selected_cells)) >= self.options.target_coverage
                and len(selected_filters) >= self.options.minimum_filters
                else "maximum_products_reached"
            )
        selected_products: list[dict[str, Any]] = []
        for rank, candidate in enumerate(selected_candidates, start=1):
            product = dict(candidate.product)
            product["selection_rank"] = rank
            product["observation_key"] = candidate.observation_key
            selected_products.append(product)

        branch_candidate_counts = Counter(candidate.mission for candidate in self.candidates.values())
        selected_observation_groups = group_selected_products(selected_products)
        coverage_fraction = self.grid.fraction_for_count(len(selected_cells))
        selection_summary = {
            "coverage_fraction": coverage_fraction,
            "coverage_percentage": round(coverage_fraction * 100.0, 6),
            "selected_size_bytes": total_size,
            "selected_size_mib": round(total_size / MIB, 6),
            "selected_filter_count": len(selected_filters),
            "selected_group_filter_count": sum(
                len(filters) for filters in selected_filters_by_group.values()
            ),
            "selected_product_count": len(selected_products),
            "eligible_candidate_count": len(self.candidates),
            "observation_group_count": len(self.groups),
            "selected_observation_group_count": len(selected_observation_groups),
        }
        result = {
            "algorithm": "hierarchical_incremental_greedy",
            "filter_novelty_scope": "observation_group",
            "summary": selection_summary,
            "candidate_count": sum(self.branch_fetched_counts.values()),
            "eligible_candidate_count": len(self.candidates),
            "observation_group_count": len(self.groups),
            "branch_candidate_counts": dict(sorted(branch_candidate_counts.items())),
            "excluded_candidates": self.exclusions,
            "exclusion_reasons": dict(sorted(Counter(value["reason"] for value in self.exclusions).items())),
            "steps": steps,
            "selected_products": selected_products,
            "observation_groups": selected_observation_groups,
            "covered_fraction": coverage_fraction,
            "selected_filters": sorted(selected_filters),
            "total_selected_size_bytes": total_size,
            "budget_skipped_candidates": budget_skipped,
            "stop_reason": stop_reason,
            "complexity_metrics": self.metrics,
        }
        LOGGER.info(
            "Hierarchical selection finished selected_products=%s observation_groups=%s "
            "filters=%s covered_fraction=%.6f total_mib=%.2f stop_reason=%s "
            "score_updates=%s elapsed_seconds=%.3f",
            len(selected_products),
            len(result["observation_groups"]),
            len(selected_filters),
            result["covered_fraction"],
            total_size / MIB,
            stop_reason,
            self.metrics["candidate_score_updates"],
            time.monotonic() - started,
        )
        return result


def greedy_select_products(
    response_rows: list[list[dict[str, Any]]],
    grid: CoverageGrid,
    options: SelectionOptions,
) -> dict[str, Any]:
    """Prepare TAP branches and run the reviewable greedy selection algorithm.

    Algorithm flow:
        1. Divide TAP rows into independent mission branches.
        2. Validate required footprint, filter, instrument, size, and URI fields.
        3. Group eligible products by mission, instrument, and observation.
        4. Build group heaps plus spatial-cell and filter inverted indexes.
        5. Repeatedly choose the product with the highest marginal score. A
           filter is new when it has not yet been selected in that product's
           observation group::

               (coverage_weight * new_coverage
                + filter_weight * new_filter_count)
               / size_mib**size_penalty_exponent

        6. Incrementally update only candidates affected by newly covered cells
           or newly acquired filters.
        7. Return ordered products and regroup them for AOSImageStack creation.

    Keeping this as a named function makes the complete algorithm easy to call,
    test, profile, and review without going through the command-line interface.
    """

    branches = prepare_candidate_branches(response_rows, grid, options)
    return HierarchicalIncrementalGreedySelector(branches, grid, options).select()


# ---------------------------------------------------------------------------
# SwiftMAST-compatible selected-product download cache
# ---------------------------------------------------------------------------

def storage_safe_path_component(value: Any, fallback: str) -> str:
    """Mirror SwiftMAST's filesystem-safe path-component normalization."""

    source = str(value or "").strip() or fallback
    replaced = "".join(
        character if character.isalnum() or character in "-_." else "_"
        for character in source
    )
    collapsed = re.sub(r"__+", "_", replaced).strip("_")
    return collapsed or fallback


def swiftmast_cache_paths(
    cache_root: Path,
    target_name: str,
    product: dict[str, Any],
) -> tuple[Path, Path]:
    """Return the FITS and CAOM-sidecar paths used by SwiftMAST's cache scanner."""

    collection = str(product.get("obs_collection") or "").strip()
    mission = "HST" if collection.upper() == "HLA" else collection
    safe_target = storage_safe_path_component(target_name, "unknown-target")
    safe_mission = storage_safe_path_component(mission, "unknown-mission")
    safe_observation = storage_safe_path_component(
        product.get("obs_id"), "unknown-observation"
    )
    filter_value = str(product.get("filters") or "").replace(";", "-")
    safe_filter = storage_safe_path_component(filter_value, "unknown-filter")
    filter_folder = (
        cache_root
        / safe_target
        / safe_mission
        / safe_observation
        / safe_filter
    )
    fits_name = (
        f"{safe_target}_{safe_mission}_{safe_observation}_{safe_filter}.fits"
    )
    return filter_folder / "fit" / fits_name, filter_folder / "coam-result.json"


def integer_value(value: Any) -> int:
    """Match Swift's tolerant TAP numeric conversion for sidecar fields."""

    try:
        return int(float(value)) if value not in (None, "") else 0
    except (TypeError, ValueError, OverflowError):
        return 0


def float_value(value: Any) -> float:
    """Return a finite JSON-compatible float, or zero for missing TAP values."""

    try:
        number = float(value)
        return number if math.isfinite(number) else 0.0
    except (TypeError, ValueError, OverflowError):
        return 0.0


def string_value(value: Any) -> str:
    """Return SwiftMAST's empty-string representation for a missing TAP value."""

    return "" if value is None else str(value)


def swiftmast_coam_sidecar(product: dict[str, Any]) -> dict[str, Any]:
    """Convert one selected TAP row into SwiftMAST's Codable CoamResult shape."""

    return {
        "calib_level": integer_value(product.get("calib_level")),
        "dataRights": string_value(product.get("datarights")),
        "dataURL": string_value(product.get("datauri")),
        "dataproduct_type": string_value(product.get("dataproduct_type")).upper(),
        "distance": 0,
        "em_max": integer_value(product.get("em_max")),
        "em_min": integer_value(product.get("em_min")),
        "filters": string_value(product.get("filters")),
        "instrument_name": string_value(product.get("instrument_name")),
        "intentType": string_value(product.get("intenttype")),
        "jpegURL": string_value(product.get("previewuri")),
        "mtFlag": False,
        "objID": 0,
        "obs_collection": string_value(product.get("obs_collection")),
        "obs_id": string_value(product.get("obs_id")),
        "obs_title": "",
        "obsid": integer_value(product.get("obsid")),
        "project": string_value(product.get("project")),
        "proposal_id": string_value(product.get("proposal_id")),
        "proposal_pi": "",
        "proposal_type": "",
        "provenance_name": string_value(product.get("provenance_name")),
        "s_dec": product.get("s_dec") if product.get("s_dec") is not None else "",
        "s_ra": product.get("s_ra") if product.get("s_ra") is not None else "",
        "s_region": string_value(product.get("s_region")),
        "s_region_area": None,
        "sequence_number": 0,
        "srcDen": 0,
        "t_exptime": float_value(product.get("t_exptime")),
        "t_max": float_value(product.get("t_max")),
        "t_min": float_value(product.get("t_min")),
        "t_obs_release": 0.0,
        "target_classification": "",
        "target_name": string_value(product.get("target_name")),
        "wavelength_region": string_value(product.get("wavelength_region")),
        "productFilename": product.get("productfilename"),
        "artifactContentType": product.get("contenttype"),
        "positionDimension1": product.get("posdimension1"),
        "positionDimension2": product.get("posdimension2"),
        "positionSampleSize": product.get("possamplesize"),
        "dataURLSizeBytes": product.get("contentlength"),
        "jpegURLSizeBytes": None,
        "fitsImageHeaderMetadata": None,
        "localResources": None,
    }


def write_json_atomically(path: Path, value: dict[str, Any]) -> None:
    """Write a JSON sidecar without exposing a partially written file."""

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def is_complete_fits(path: Path, expected_size: int | None) -> bool:
    """Recognize a complete cached FITS file by size and its primary header card."""

    try:
        actual_size = path.stat().st_size
        if actual_size <= 0 or (expected_size is not None and actual_size != expected_size):
            return False
        with path.open("rb") as stream:
            return stream.read(8) == b"SIMPLE  "
    except OSError:
        return False


def product_download_request(product: dict[str, Any]) -> tuple[str, dict[str, str] | None]:
    """Return a direct URL or the MAST Download/file request for a product URI."""

    data_uri = string_value(product.get("datauri")).strip()
    if not data_uri:
        raise RuntimeError("selected product has no datauri")
    if data_uri.lower().startswith(("http://", "https://")):
        return data_uri, None
    return MAST_DOWNLOAD_URL, {"uri": data_uri}


def download_selected_product(
    session: requests.Session,
    product: dict[str, Any],
    *,
    target_name: str,
    cache_root: Path,
    timeout: float,
) -> dict[str, Any]:
    """Download one selected FITS product atomically, resuming a prior partial file."""

    destination, sidecar = swiftmast_cache_paths(cache_root, target_name, product)
    expected_size_value = integer_value(product.get("contentlength"))
    expected_size = expected_size_value if expected_size_value > 0 else None
    report = {
        "selection_rank": product.get("selection_rank"),
        "observation_id": product.get("obs_id"),
        "product_uri": product.get("datauri"),
        "expected_size_bytes": expected_size,
        "local_fits_path": str(destination),
        "coam_sidecar_path": str(sidecar),
    }

    if is_complete_fits(destination, expected_size):
        write_json_atomically(sidecar, swiftmast_coam_sidecar(product))
        report.update(
            status="cached",
            transferred_bytes=0,
            local_size_bytes=destination.stat().st_size,
        )
        LOGGER.info(
            "FITS cache hit rank=%s observation_id=%r path=%s",
            product.get("selection_rank"),
            product.get("obs_id"),
            destination,
        )
        return report

    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    if is_complete_fits(partial, expected_size):
        partial.replace(destination)
        write_json_atomically(sidecar, swiftmast_coam_sidecar(product))
        report.update(
            status="resumed",
            transferred_bytes=0,
            local_size_bytes=destination.stat().st_size,
        )
        return report

    resume_offset = partial.stat().st_size if partial.exists() else 0
    if resume_offset > 0:
        try:
            with partial.open("rb") as stream:
                prefix = stream.read(8)
        except OSError:
            prefix = b""
        if (len(prefix) == 8 and prefix != b"SIMPLE  ") or (
            expected_size is not None and resume_offset >= expected_size
        ):
            LOGGER.warning("Discarding invalid partial download path=%s", partial)
            resume_offset = 0
    request_url, parameters = product_download_request(product)
    headers = {"Accept": "application/fits, application/octet-stream"}
    token = os.environ.get("MAST_API_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"token {token}"
    if resume_offset > 0:
        headers["Range"] = f"bytes={resume_offset}-"

    LOGGER.info(
        "FITS download started rank=%s observation_id=%r expected_mib=%.2f resume_bytes=%s",
        product.get("selection_rank"),
        product.get("obs_id"),
        (expected_size or 0) / MIB,
        resume_offset,
    )
    started = time.monotonic()
    response = session.get(
        request_url,
        params=parameters,
        headers=headers,
        stream=True,
        timeout=timeout,
    )
    try:
        if response.status_code == 416 and is_complete_fits(partial, expected_size):
            partial.replace(destination)
            write_json_atomically(sidecar, swiftmast_coam_sidecar(product))
            report.update(
                status="resumed",
                transferred_bytes=0,
                local_size_bytes=destination.stat().st_size,
            )
            return report
        response.raise_for_status()
        append = resume_offset > 0 and response.status_code == 206
        transferred = 0
        with partial.open("ab" if append else "wb") as stream:
            for chunk in response.iter_content(chunk_size=MIB):
                if not chunk:
                    continue
                stream.write(chunk)
                transferred += len(chunk)
            stream.flush()
            os.fsync(stream.fileno())
    finally:
        response.close()

    if not is_complete_fits(partial, expected_size):
        actual_size = partial.stat().st_size if partial.exists() else 0
        raise RuntimeError(
            f"downloaded FITS validation failed: expected {expected_size} bytes, "
            f"found {actual_size} bytes at {partial}"
        )

    partial.replace(destination)
    write_json_atomically(sidecar, swiftmast_coam_sidecar(product))
    product["local_fits_path"] = str(destination)
    product["download_status"] = "resumed" if resume_offset > 0 else "downloaded"
    report.update(
        status=product["download_status"],
        transferred_bytes=transferred,
        local_size_bytes=destination.stat().st_size,
        elapsed_seconds=round(time.monotonic() - started, 3),
    )
    LOGGER.info(
        "FITS download finished rank=%s observation_id=%r status=%s transferred_mib=%.2f "
        "elapsed_seconds=%.3f path=%s",
        product.get("selection_rank"),
        product.get("obs_id"),
        report["status"],
        transferred / MIB,
        time.monotonic() - started,
        destination,
    )
    return report


def download_selected_products(
    products: list[dict[str, Any]],
    *,
    target_name: str,
    cache_root: Path,
    timeout: float,
    retries: int,
) -> dict[str, Any]:
    """Cache selected FITS files serially, matching SwiftMAST's download behavior."""

    started = time.monotonic()
    product_reports: list[dict[str, Any]] = []
    cache_root = cache_root.expanduser().resolve()
    LOGGER.info(
        "Selected FITS caching started products=%s target=%r cache_root=%s",
        len(products),
        target_name,
        cache_root,
    )
    with requests_session(retries) as session:
        for product in products:
            try:
                product_report = download_selected_product(
                    session,
                    product,
                    target_name=target_name,
                    cache_root=cache_root,
                    timeout=timeout,
                )
                if product_report["status"] in {"cached", "downloaded", "resumed"}:
                    product["local_fits_path"] = product_report["local_fits_path"]
                    product["download_status"] = product_report["status"]
                product_reports.append(product_report)
            except (OSError, requests.RequestException, RuntimeError) as error:
                LOGGER.error(
                    "FITS download failed rank=%s observation_id=%r error=%s",
                    product.get("selection_rank"),
                    product.get("obs_id"),
                    error,
                )
                product["download_status"] = "failed"
                product_reports.append(
                    {
                        "selection_rank": product.get("selection_rank"),
                        "observation_id": product.get("obs_id"),
                        "product_uri": product.get("datauri"),
                        "status": "failed",
                        "error": str(error),
                    }
                )

    counts = Counter(report["status"] for report in product_reports)
    summary = {
        "cache_root": str(cache_root),
        "requested_product_count": len(products),
        "downloaded_product_count": counts["downloaded"] + counts["resumed"],
        "cached_product_count": counts["cached"],
        "failed_product_count": counts["failed"],
        "transferred_bytes": sum(
            int(report.get("transferred_bytes") or 0) for report in product_reports
        ),
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "products": product_reports,
    }
    LOGGER.info(
        "Selected FITS caching finished downloaded=%s cached=%s failed=%s "
        "transferred_mib=%.2f elapsed_seconds=%.3f",
        summary["downloaded_product_count"],
        summary["cached_product_count"],
        summary["failed_product_count"],
        summary["transferred_bytes"] / MIB,
        summary["elapsed_seconds"],
    )
    return summary


# ---------------------------------------------------------------------------
# Command-line orchestration and report generation
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    """Define query, diagnostics, logging, and optional selection arguments."""

    parser = argparse.ArgumentParser(
        description=(
            "Query MAST CAOM TAP and greedily select public science FITS products "
            "when --select-products is enabled."
        )
    )
    parser.add_argument("--target", help="Target name to resolve, for example 'NGC 628'.")
    parser.add_argument("--ra", type=float, help="ICRS right ascension in degrees.")
    parser.add_argument("--dec", type=float, help="ICRS declination in degrees.")
    parser.add_argument("--radius", type=float, default=0.1, help="Search radius in degrees (default: 0.1).")
    parser.add_argument("--missions", default=",".join(DEFAULT_MISSIONS), help="Comma-separated MAST collections.")
    parser.add_argument("--filters", default="", help="Optional comma-separated filter-name fragments.")
    parser.add_argument("--calib-levels", default="3,4", help="Comma-separated calibration levels (default: 3,4).")
    parser.add_argument("--product-types", default="IMAGE,CUBE", help="Comma-separated CAOM product types.")
    parser.add_argument("--limit", type=int, default=50, help="Maximum returned rows (default: 50).")
    parser.add_argument("--timeout", type=float, default=120, help="Network timeout in seconds.")
    parser.add_argument(
        "--retries",
        type=int,
        default=5,
        help="Retries for HTTP 429/5xx responses with exponential backoff (default: 5).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        choices=range(1, 5),
        metavar="1-4",
        help="Concurrent TAP branch queries; one is the MAST-friendly default.",
    )
    parser.add_argument(
        "--require-all-missions",
        action="store_true",
        help="Fail if any mission query fails instead of retaining successful missions.",
    )
    parser.add_argument("--schema", action="store_true", help="Query the schema of the three joined CAOM tables.")
    parser.add_argument(
        "--balanced-missions",
        action="store_true",
        help=(
            "Split --limit approximately evenly across requested missions. "
            "Use this for representative availability samples."
        ),
    )
    parser.add_argument(
        "--eligibility-filter-location",
        choices=("local", "tap"),
        default="local",
        help=(
            "Apply required-field and per-product size checks after retrieval "
            "(local, default) or in TAP before TOP/transfer (tap)."
        ),
    )
    parser.add_argument(
        "--tap-order",
        choices=tuple(TAP_ORDERINGS),
        default="group",
        help=(
            "TAP row priority: observation grouping, minimum file size first, "
            "or maximum file size first (default: group)."
        ),
    )
    parser.add_argument("--show-query", action="store_true", help="Print ADQL to stderr before submitting it.")
    parser.add_argument("--output", type=Path, help="Write formatted JSON to this path instead of stdout.")
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
        help="Terminal logging level (default: INFO).",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        help="Optionally duplicate terminal logs to this file.",
    )
    parser.add_argument(
        "--columns",
        default="",
        help="Diagnostic override using comma-separated TAP column references.",
    )
    parser.add_argument(
        "--select-products",
        "--hierarchical-select",
        dest="select_products",
        action="store_true",
        help=(
            "Run hierarchical incremental greedy selection after preparing each "
            "mission result separately. The unselected TAP rows remain in the report."
        ),
    )
    parser.add_argument(
        "--download-selected",
        action="store_true",
        help=(
            "Run greedy selection and cache only its selected FITS files using "
            "SwiftMAST's Documents/MAST directory structure."
        ),
    )
    parser.add_argument(
        "--cache-root",
        type=Path,
        default=Path.home() / "Documents" / "MAST",
        help="SwiftMAST MAST cache root (default: ~/Documents/MAST).",
    )
    parser.add_argument(
        "--cache-target-name",
        help=(
            "Target folder name in the SwiftMAST cache. Defaults to --target, "
            "or a coordinate-derived name when --ra/--dec are used."
        ),
    )
    parser.add_argument("--max-products", type=int, default=20, help="Maximum selected products (default: 20).")
    parser.add_argument("--max-mb", type=float, default=70, help="Maximum size of one product in MiB (default: 70).")
    parser.add_argument("--max-total-mb", type=float, help="Optional total selected-product budget in MiB.")
    parser.add_argument("--target-coverage", type=float, default=0.80, help="Target grid coverage fraction (default: 0.80).")
    parser.add_argument(
        "--minimum-filters",
        "--min-filters",
        dest="minimum_filters",
        type=int,
        default=3,
        help="Minimum distinct filters (default: 3).",
    )
    parser.add_argument("--coverage-weight", type=float, default=0.65, help="Coverage score weight (default: 0.65).")
    parser.add_argument("--filter-weight", type=float, default=0.35, help="Filter-variety score weight (default: 0.35).")
    parser.add_argument(
        "--size-penalty-exponent",
        type=float,
        default=1.0,
        help="Exponent applied to product size in the score denominator (default: 1).",
    )
    parser.add_argument(
        "--grid-dimension",
        "--grid",
        dest="grid_dimension",
        type=int,
        default=48,
        help="Coverage grid width/height (default: 48).",
    )
    return parser.parse_args()


def main() -> int:
    """Run resolution → TAP fetch → selection → optional cache → JSON output."""

    args = parse_args()
    if args.download_selected:
        args.select_products = True
    configure_logging(args.log_level, args.log_file)
    started = time.monotonic()
    LOGGER.info(
        "MAST TAP workflow started target=%r missions=%s limit=%s balanced_missions=%s "
        "selection=%s download_selected=%s filter_location=%s tap_order=%s",
        args.target,
        args.missions,
        args.limit,
        args.balanced_missions,
        args.select_products,
        args.download_selected,
        args.eligibility_filter_location,
        args.tap_order,
    )

    if args.radius <= 0:
        raise ValueError("--radius must be greater than zero")
    if args.limit <= 0:
        raise ValueError("--limit must be greater than zero")
    if args.retries < 0:
        raise ValueError("--retries cannot be negative")
    if args.select_products:
        if args.schema:
            raise ValueError("--select-products cannot be combined with --schema")
        if args.columns:
            raise ValueError("--select-products requires the default application columns")
        if args.max_products <= 0:
            raise ValueError("--max-products must be greater than zero")
        if args.max_mb <= 0:
            raise ValueError("--max-mb must be greater than zero")
        if args.max_total_mb is not None and args.max_total_mb <= 0:
            raise ValueError("--max-total-mb must be greater than zero")
        if not 0 <= args.target_coverage <= 1:
            raise ValueError("--target-coverage must be in [0, 1]")
        if args.minimum_filters < 0:
            raise ValueError("--minimum-filters cannot be negative")
        if args.coverage_weight < 0 or args.filter_weight < 0:
            raise ValueError("selection weights cannot be negative")
        if args.size_penalty_exponent < 0:
            raise ValueError("--size-penalty-exponent cannot be negative")
        if args.grid_dimension <= 0:
            raise ValueError("--grid-dimension must be greater than zero")

    if args.schema:
        query = build_schema_query()
        resolved_position = None
        query_jobs = [("schema", query)]
    else:
        if (args.ra is None) != (args.dec is None):
            raise ValueError("provide both --ra and --dec")
        if args.ra is None:
            if not args.target:
                raise ValueError("provide --target or both --ra and --dec")
            ra, dec = resolve_target(args.target, timeout=args.timeout, retries=args.retries)
        else:
            ra, dec = args.ra, args.dec

        if not 0 <= ra < 360:
            raise ValueError("--ra must be in [0, 360)")
        if not -90 <= dec <= 90:
            raise ValueError("--dec must be in [-90, 90]")

        resolved_position = {"ra": ra, "dec": dec, "radius_degrees": args.radius}
        missions = parse_csv_values(args.missions)
        filters = parse_csv_values(args.filters) if args.filters.strip() else []
        product_types = parse_csv_values(args.product_types)
        try:
            calibration_levels = [
                int(value.strip())
                for value in args.calib_levels.split(",")
                if value.strip()
            ]
        except ValueError as error:
            raise ValueError("--calib-levels must contain comma-separated integers") from error
        if not calibration_levels:
            raise ValueError("--calib-levels requires at least one value")
        columns = parse_column_values(args.columns) if args.columns.strip() else None

        if args.balanced_missions and len(missions) > 1:
            base_limit, remainder = divmod(args.limit, len(missions))
            mission_limits = [
                base_limit + (1 if index < remainder else 0)
                for index in range(len(missions))
            ]
            query_jobs = [
                (
                    mission,
                    build_science_product_query(
                        ra=ra,
                        dec=dec,
                        radius=args.radius,
                        missions=[mission],
                        filters=filters,
                        calibration_levels=calibration_levels,
                        product_types=product_types,
                        limit=mission_limit,
                        columns=columns,
                        eligibility_filter_location=args.eligibility_filter_location,
                        max_product_bytes=int(args.max_mb * MIB),
                        tap_order=args.tap_order,
                    ),
                )
                for mission, mission_limit in zip(missions, mission_limits)
                if mission_limit > 0
            ]
        else:
            query_jobs = [
                (
                    "combined",
                    build_science_product_query(
                        ra=ra,
                        dec=dec,
                        radius=args.radius,
                        missions=missions,
                        filters=filters,
                        calibration_levels=calibration_levels,
                        product_types=product_types,
                        limit=args.limit,
                        columns=columns,
                        eligibility_filter_location=args.eligibility_filter_location,
                        max_product_bytes=int(args.max_mb * MIB),
                        tap_order=args.tap_order,
                    ),
                )
            ]

    if args.show_query:
        for label, adql in query_jobs:
            LOGGER.info("ADQL branch=%s\n%s", label, adql)

    completed_jobs, query_errors = execute_tap_queries(
        query_jobs,
        timeout=args.timeout,
        retries=args.retries,
        workers=args.workers,
        require_all=args.require_all_missions,
    )
    responses = [response for _, response, _ in completed_jobs]
    queries = [adql for _, _, adql in completed_jobs]
    response_rows = [named_rows(response) for response in responses]
    selection = None
    if args.select_products:
        assert resolved_position is not None
        selection_options = SelectionOptions(
            max_products=args.max_products,
            max_product_bytes=int(args.max_mb * MIB),
            max_total_bytes=int(args.max_total_mb * MIB) if args.max_total_mb is not None else None,
            target_coverage=args.target_coverage,
            minimum_filters=args.minimum_filters,
            coverage_weight=args.coverage_weight,
            filter_weight=args.filter_weight,
            size_penalty_exponent=args.size_penalty_exponent,
            grid_dimension=args.grid_dimension,
        )
        grid = make_coverage_grid(
            resolved_position["ra"],
            resolved_position["dec"],
            resolved_position["radius_degrees"],
            selection_options.grid_dimension,
        )
        # The named algorithm entry point performs branch preparation, grouping,
        # heap/index construction, and incremental greedy traversal.
        selection = greedy_select_products(response_rows, grid, selection_options)
        selection["target"] = args.target
        selection["position"] = resolved_position
        selection["target_area_square_degrees"] = grid.target_area_square_degrees
        if args.download_selected:
            cache_target_name = string_value(args.cache_target_name or args.target).strip()
            if not cache_target_name:
                cache_target_name = (
                    f"ra-{resolved_position['ra']:.6f}_dec-{resolved_position['dec']:.6f}"
                )
            selection["downloads"] = download_selected_products(
                selection["selected_products"],
                target_name=cache_target_name,
                cache_root=args.cache_root,
                timeout=args.timeout,
                retries=args.retries,
            )

    rows = [row for branch_rows in response_rows for row in branch_rows]
    response_columns = responses[0]["info"] if responses else []
    result = {
        "target": args.target,
        "position": resolved_position,
        "row_count": len(rows),
        "columns": [column.get("name") for column in response_columns],
        "column_availability": column_availability(rows),
        "missions": mission_summary(rows),
        "adql": queries[0] if len(queries) == 1 else queries,
        "query_errors": query_errors,
        "query_strategy": {
            "eligibility_filter_location": args.eligibility_filter_location,
            "tap_order": args.tap_order,
            "max_product_size_bytes": int(args.max_mb * MIB),
        },
        "rows": rows,
    }
    if selection is not None:
        result["selection"] = selection
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        LOGGER.info(
            "Report written path=%s rows=%s selected_products=%s",
            args.output,
            len(rows),
            len(selection["selected_products"]) if selection is not None else 0,
        )
    else:
        sys.stdout.write(rendered)

    LOGGER.info(
        "MAST TAP workflow finished rows=%s elapsed_seconds=%.3f",
        len(rows),
        time.monotonic() - started,
    )

    if selection is not None and args.download_selected:
        return 1 if selection["downloads"]["failed_product_count"] else 0
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
