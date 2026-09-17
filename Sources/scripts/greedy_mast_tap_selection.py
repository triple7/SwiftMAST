#!/usr/bin/env python3
"""Select science FITS products and observation groups with a greedy TAP search.

This is a requests-only research implementation of SwiftMAST's greedy selector.
It resolves a target, queries CAOM TAP metadata, rejects incomplete or oversized
products, and selects products that add sky coverage and filter variety for the
least download cost. It does not download FITS files or read FITS headers.

Dependency:
    python3 -m pip install requests

Example matching the TAP-column research command:
    .venv/bin/python Sources/scripts/greedy_mast_tap_selection.py \
      --target "NGC 628" \
      --missions JWST,HST,HLA \
      --balanced-missions \
      --limit 100 \
      --max-products 5 \
      --max-mb 70 \
      --output greedy-science-product-report.json
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import re
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


MAST_TAP_URL = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
MAST_API_URL = "https://mast.stsci.edu/api/v0/invoke"
DEFAULT_MISSIONS = ("JWST", "HST", "HLA")
MIB = 1_048_576
LOGGER = logging.getLogger("swiftmast.greedy_tap")

# These are the metadata fields used by the selector. No FITS header request is
# made. s_region_area is intentionally absent because it is computed locally.
APPLICATION_COLUMNS = (
    "o.obsid AS obsid",
    "o.obs_id AS obs_id",
    "o.obs_collection AS obs_collection",
    "o.instrument_name AS instrument_name",
    "o.target_name AS target_name",
    "o.filters AS filters",
    "o.calib_level AS calib_level",
    "o.dataproduct_type AS dataproduct_type",
    "o.intenttype AS intenttype",
    "o.datarights AS datarights",
    "o.s_ra AS s_ra",
    "o.s_dec AS s_dec",
    "o.s_region AS s_region",
    "o.t_exptime AS t_exptime",
    "o.t_min AS t_min",
    "o.t_max AS t_max",
    "o.em_min AS em_min",
    "o.em_max AS em_max",
    "o.wavelength_region AS wavelength_region",
    "o.proposal_id AS proposal_id",
    "o.project AS project",
    "o.provenance_name AS provenance_name",
    "p.posdimension1 AS posdimension1",
    "p.posdimension2 AS posdimension2",
    "p.possamplesize AS possamplesize",
    "COALESCE(a.datauri, o.dataurl) AS datauri",
    "COALESCE(p.previewuri, o.jpegurl) AS previewuri",
    "a.productfilename AS productfilename",
    "a.contenttype AS contenttype",
    "a.contentlength AS contentlength",
)

IGNORED_FILTERS = {"", "CLEAR", "DETECTION", "N/A", "NA", "NONE", "UNKNOWN", "WHITE"}
FILTER_TOKEN = re.compile(r"^(?:FQ?|G)\d{2,4}[A-Z0-9]*$")


@dataclass(frozen=True)
class SelectionOptions:
    max_products: int = 5
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
    points: tuple[tuple[float, float], ...]
    target_area_square_degrees: float

    def fraction(self, cells: set[int]) -> float:
        return min(len(cells) / len(self.points), 1.0) if self.points else 0.0


@dataclass(frozen=True)
class Candidate:
    product: dict[str, Any]
    identity: str
    instrument_branch: str
    observation_key: str
    filters: frozenset[str]
    file_size_bytes: int
    covered_cells: frozenset[int]


def configure_logging(level: str, log_file: Path | None) -> None:
    """Configure timestamped stderr logging and an optional duplicate log file."""

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
    retry = Retry(
        total=retries,
        connect=retries,
        read=retries,
        status=retries,
        backoff_factor=2,
        allowed_methods=frozenset({"POST"}),
        status_forcelist=(429, 500, 502, 503, 504),
        respect_retry_after_header=True,
        raise_on_status=False,
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    session.headers.update(
        {
            "Accept": "application/json",
            "User-Agent": "SwiftMAST-greedy-TAP-research/1.0",
        }
    )
    return session


def post_form_json(
    url: str,
    values: dict[str, str],
    timeout: float,
    retries: int,
) -> dict[str, Any]:
    LOGGER.debug("HTTP POST started url=%s timeout_seconds=%s retries=%s", url, timeout, retries)
    started = time.monotonic()
    with requests_session(retries) as session:
        try:
            response = session.post(url, data=values, timeout=timeout)
        except requests.RequestException as error:
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
    LOGGER.debug(
        "HTTP POST finished url=%s status=%s elapsed_seconds=%.3f response_bytes=%s",
        url,
        response.status_code,
        time.monotonic() - started,
        len(response.content),
    )

    try:
        decoded = response.json()
    except requests.exceptions.JSONDecodeError as error:
        raise RuntimeError(f"MAST did not return JSON: {response.text[:500]}") from error
    if not isinstance(decoded, dict):
        raise RuntimeError("MAST returned an unexpected JSON value")
    return decoded


def resolve_target(target: str, timeout: float, retries: int) -> tuple[float, float]:
    LOGGER.info("Target resolution started target=%r", target)
    started = time.monotonic()
    request = {
        "service": "Mast.Name.Lookup",
        "params": {"input": target, "format": "json"},
        "format": "json",
    }
    response = post_form_json(
        MAST_API_URL,
        {"request": json.dumps(request, separators=(",", ":"))},
        timeout,
        retries,
    )
    coordinates = response.get("resolvedCoordinate")
    if not isinstance(coordinates, list) or not coordinates:
        raise RuntimeError(f"MAST could not resolve target {target!r}")
    try:
        position = float(coordinates[0]["ra"]), float(coordinates[0]["decl"])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"Invalid target-resolution response: {coordinates[0]!r}") from error
    LOGGER.info(
        "Target resolution finished target=%r ra=%.8f dec=%.8f elapsed_seconds=%.3f",
        target,
        position[0],
        position[1],
        time.monotonic() - started,
    )
    return position


def adql_strings(values: Iterable[str]) -> str:
    return ",".join("'" + value.replace("'", "''") + "'" for value in values)


def build_science_product_query(
    *,
    ra: float,
    dec: float,
    radius: float,
    mission: str,
    filters: list[str],
    calibration_levels: list[int],
    product_types: list[str],
    limit: int,
) -> str:
    predicates = [
        "CONTAINS("
        "POINT('ICRS', o.s_ra, o.s_dec), "
        f"CIRCLE('ICRS', {ra:.12g}, {dec:.12g}, {radius:.12g})"
        ") = 1",
        f"o.obs_collection = '{mission.replace(chr(39), chr(39) * 2)}'",
        "o.datarights = 'PUBLIC'",
        f"o.calib_level IN ({','.join(str(value) for value in calibration_levels)})",
        f"LOWER(o.dataproduct_type) IN ({adql_strings(value.lower() for value in product_types)})",
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
        fragments = [value.replace("'", "''").upper() for value in filters]
        predicates.append(
            "(" + " OR ".join(f"UPPER(o.filters) LIKE '%{value}%'" for value in fragments) + ")"
        )

    return (
        f"SELECT TOP {limit}\n"
        f"    {',\n    '.join(APPLICATION_COLUMNS)}\n"
        "FROM dbo.obspointing AS o\n"
        "JOIN dbo.caomplane AS p ON p.planetid = o.objid\n"
        "JOIN dbo.caomartifact AS a ON a.planetid = p.planetid\n"
        "WHERE "
        + "\n  AND ".join(predicates)
        + "\nORDER BY o.instrument_name, o.obs_id, o.filters, o.t_min"
    )


def query_tap(adql: str, timeout: float, retries: int) -> dict[str, Any]:
    response = post_form_json(
        MAST_TAP_URL,
        {
            "REQUEST": "doQuery",
            "LANG": "ADQL",
            "QUERY": adql,
            "responseformat": "json",
        },
        timeout,
        retries,
    )
    if not isinstance(response.get("info"), list) or not isinstance(response.get("data"), list):
        raise RuntimeError(f"Unexpected TAP response: {json.dumps(response)[:500]}")
    return response


def coerce_tap_value(value: Any, datatype: str) -> Any:
    if value in (None, ""):
        return None
    try:
        if datatype in {"int", "integer", "long", "short"}:
            return int(value)
        if datatype in {"float", "double", "real"}:
            number = float(value)
            return number if math.isfinite(number) else None
        if datatype == "boolean":
            normalized = str(value).strip().lower()
            if normalized in {"1", "true", "t"}:
                return True
            if normalized in {"0", "false", "f"}:
                return False
    except (TypeError, ValueError):
        pass
    return value


def named_rows(response: dict[str, Any]) -> list[dict[str, Any]]:
    info = response["info"]
    names = [str(column.get("name", f"column_{index}")).lower() for index, column in enumerate(info)]
    types = [str(column.get("datatype", column.get("type", ""))).lower() for column in info]
    rows: list[dict[str, Any]] = []
    for raw in response["data"]:
        if not isinstance(raw, list):
            continue
        rows.append(
            {
                name: coerce_tap_value(raw[index], types[index]) if index < len(raw) else None
                for index, name in enumerate(names)
            }
        )
    return rows


def parse_csv(raw: str, *, uppercase: bool = True) -> list[str]:
    values = [value.strip() for value in raw.split(",") if value.strip()]
    return [value.upper() for value in values] if uppercase else values


def wrapped_degrees(value: float) -> float:
    value %= 360.0
    if value > 180.0:
        value -= 360.0
    return value


def angular_distance_degrees(lhs: tuple[float, float], rhs: tuple[float, float]) -> float:
    ra1, dec1 = (math.radians(value) for value in lhs)
    ra2, dec2 = (math.radians(value) for value in rhs)
    cosine = math.sin(dec1) * math.sin(dec2) + math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2)
    return math.degrees(math.acos(min(1.0, max(-1.0, cosine))))


def parse_s_region(value: str) -> tuple[tuple[str, tuple[float, ...]], ...] | None:
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
            edge_x = x_current + (x_previous - x_current) * (-y_current) / (y_previous - y_current)
            if edge_x >= 0:
                inside = not inside
        previous = current
    return inside


def region_contains(
    point: tuple[float, float],
    shapes: tuple[tuple[str, tuple[float, ...]], ...],
) -> bool:
    for shape, numbers in shapes:
        if shape == "CIRCLE":
            if angular_distance_degrees(point, (numbers[0], numbers[1])) <= numbers[2]:
                return True
        elif polygon_contains(point, numbers):
            return True
    return False


def make_coverage_grid(ra: float, dec: float, radius: float, dimension: int) -> CoverageGrid:
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
    if not isinstance(value, str):
        return frozenset()
    return frozenset(
        token
        for token in (part.strip().upper() for part in re.split(r"[;,|\s]+", value))
        if token not in IGNORED_FILTERS
    )


def observation_group_key(product: dict[str, Any]) -> str:
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


def exclusion(product: dict[str, Any], reason: str) -> dict[str, Any]:
    return {
        "observation_id": product.get("obs_id"),
        "product_uri": product.get("datauri"),
        "reason": reason,
    }


def prepare_candidates(
    products: list[dict[str, Any]],
    grid: CoverageGrid,
    options: SelectionOptions,
) -> tuple[list[Candidate], list[dict[str, Any]]]:
    candidates: list[Candidate] = []
    exclusions: list[dict[str, Any]] = []
    seen: set[str] = set()
    for product in products:
        data_uri = str(product.get("datauri") or "").strip()
        identity = data_uri or "\x1f".join(
            str(product.get(key) or "")
            for key in ("obs_collection", "obs_id", "instrument_name", "filters")
        )
        if identity in seen:
            exclusions.append(exclusion(product, "duplicate_product"))
            continue
        seen.add(identity)
        if not data_uri:
            exclusions.append(exclusion(product, "missing_download_url"))
            continue
        try:
            size = int(product.get("contentlength"))
        except (TypeError, ValueError):
            exclusions.append(exclusion(product, "missing_file_size"))
            continue
        if size <= 0:
            exclusions.append(exclusion(product, "missing_file_size"))
            continue
        if size > options.max_product_bytes:
            exclusions.append(exclusion(product, "exceeds_product_size_limit"))
            continue
        region_text = str(product.get("s_region") or "").strip()
        if not region_text:
            exclusions.append(exclusion(product, "missing_footprint"))
            continue
        shapes = parse_s_region(region_text)
        if shapes is None:
            exclusions.append(exclusion(product, "invalid_footprint"))
            continue
        filters = filter_keys(product.get("filters"))
        if not filters:
            exclusions.append(exclusion(product, "missing_filter"))
            continue
        instrument = str(product.get("instrument_name") or "").strip().upper()
        if not instrument:
            exclusions.append(exclusion(product, "missing_instrument"))
            continue
        cells = frozenset(
            index for index, point in enumerate(grid.points) if region_contains(point, shapes)
        )
        candidates.append(
            Candidate(
                product=product,
                identity=identity,
                instrument_branch=instrument,
                observation_key=observation_group_key(product),
                filters=filters,
                file_size_bytes=size,
                covered_cells=cells,
            )
        )
    LOGGER.info(
        "Candidate validation finished fetched=%s eligible=%s excluded=%s exclusion_reasons=%s",
        len(products),
        len(candidates),
        len(exclusions),
        dict(sorted(Counter(value["reason"] for value in exclusions).items())),
    )
    return candidates, exclusions


def greedy_select(
    products: list[dict[str, Any]],
    *,
    target_name: str,
    ra: float,
    dec: float,
    radius: float,
    options: SelectionOptions,
) -> dict[str, Any]:
    LOGGER.info(
        "Greedy selection started target=%r candidates=%s max_products=%s max_product_mib=%.2f",
        target_name,
        len(products),
        options.max_products,
        options.max_product_bytes / MIB,
    )
    started = time.monotonic()
    grid = make_coverage_grid(ra, dec, radius, options.grid_dimension)
    candidates, exclusions = prepare_candidates(products, grid, options)
    branch_counts: dict[str, int] = {}
    for candidate in candidates:
        branch_counts[candidate.instrument_branch] = branch_counts.get(candidate.instrument_branch, 0) + 1

    remaining = list(candidates)
    selected: list[Candidate] = []
    selected_cells: set[int] = set()
    selected_filters: set[str] = set()
    total_size = 0
    steps: list[dict[str, Any]] = []
    stop_reason = "no_eligible_candidates" if not candidates else "no_additional_benefit"
    target_coverage = min(max(options.target_coverage, 0.0), 1.0)

    while remaining and len(selected) < options.max_products:
        covered_fraction = grid.fraction(selected_cells)
        if covered_fraction >= target_coverage and len(selected_filters) >= options.minimum_filters:
            stop_reason = "target_satisfied"
            break

        scored: list[tuple[tuple[Any, ...], Candidate, set[int], set[str], float, float]] = []
        for candidate in remaining:
            if options.max_total_bytes is not None and total_size + candidate.file_size_bytes > options.max_total_bytes:
                continue
            new_cells = set(candidate.covered_cells) - selected_cells
            new_filters = set(candidate.filters) - selected_filters
            new_coverage = grid.fraction(new_cells)
            benefit = options.coverage_weight * new_coverage + options.filter_weight * len(new_filters)
            if benefit <= 0:
                continue
            size_mib = max(candidate.file_size_bytes / MIB, 0.001)
            size_cost = max(size_mib**options.size_penalty_exponent, 0.000001)
            score = benefit / size_cost
            # min() with this key gives the same deterministic preference as
            # descending score/coverage/filter gain and ascending size/identity.
            rank = (
                -score,
                -new_coverage,
                -len(new_filters),
                candidate.file_size_bytes,
                candidate.identity,
            )
            scored.append((rank, candidate, new_cells, new_filters, new_coverage, score))

        if not scored:
            stop_reason = "no_additional_benefit"
            break

        _, candidate, new_cells, new_filters, new_coverage, score = min(scored, key=lambda value: value[0])
        selected.append(candidate)
        selected_cells.update(candidate.covered_cells)
        selected_filters.update(candidate.filters)
        total_size += candidate.file_size_bytes
        remaining = [value for value in remaining if value.identity != candidate.identity]
        steps.append(
            {
                "iteration": len(steps) + 1,
                "instrument_branch": candidate.instrument_branch,
                "observation_key": candidate.observation_key,
                "observation_id": candidate.product.get("obs_id"),
                "filters": sorted(candidate.filters),
                "file_size_bytes": candidate.file_size_bytes,
                "new_coverage_fraction": new_coverage,
                "new_area_square_degrees": new_coverage * grid.target_area_square_degrees,
                "new_filter_count": len(new_filters),
                "score": score,
                "cumulative_coverage_fraction": grid.fraction(selected_cells),
                "cumulative_filters": sorted(selected_filters),
                "cumulative_size_bytes": total_size,
            }
        )
        LOGGER.info(
            "Greedy selection step iteration=%s mission=%s instrument=%r observation_id=%r "
            "filters=%s score=%.8f new_coverage=%.6f cumulative_coverage=%.6f "
            "file_mib=%.2f cumulative_mib=%.2f",
            len(steps),
            candidate.product.get("obs_collection"),
            candidate.instrument_branch,
            candidate.product.get("obs_id"),
            ",".join(sorted(candidate.filters)),
            score,
            new_coverage,
            grid.fraction(selected_cells),
            candidate.file_size_bytes / MIB,
            total_size / MIB,
        )

    if len(selected) >= options.max_products:
        stop_reason = (
            "target_satisfied"
            if grid.fraction(selected_cells) >= target_coverage
            and len(selected_filters) >= options.minimum_filters
            else "maximum_products_reached"
        )

    selected_products: list[dict[str, Any]] = []
    for index, candidate in enumerate(selected):
        product = dict(candidate.product)
        product["selection_rank"] = index + 1
        product["observation_key"] = candidate.observation_key
        selected_products.append(product)

    observation_groups = group_selected_products(selected_products)
    selection_result = {
        "target": target_name,
        "position": {"ra": ra, "dec": dec, "radius_degrees": radius},
        "candidate_count": len(products),
        "eligible_candidate_count": len(candidates),
        "branch_candidate_counts": dict(sorted(branch_counts.items())),
        "excluded_candidates": exclusions,
        "steps": steps,
        "selected_products": selected_products,
        "observation_groups": observation_groups,
        "covered_fraction": grid.fraction(selected_cells),
        "selected_filters": sorted(selected_filters),
        "total_selected_size_bytes": total_size,
        "stop_reason": stop_reason,
    }
    LOGGER.info(
        "Greedy selection finished selected_products=%s observation_groups=%s filters=%s "
        "covered_fraction=%.6f total_mib=%.2f stop_reason=%s elapsed_seconds=%.3f",
        len(selected_products),
        len(observation_groups),
        len(selected_filters),
        selection_result["covered_fraction"],
        total_size / MIB,
        stop_reason,
        time.monotonic() - started,
    )
    return selection_result


def group_selected_products(products: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for product in products:
        identity = (
            str(product.get("obs_collection") or "").upper(),
            str(product.get("observation_key") or observation_group_key(product)),
            str(product.get("instrument_name") or ""),
        )
        groups.setdefault(identity, []).append(product)

    output = []
    for (mission, key, instrument), group_products in sorted(groups.items()):
        output.append(
            {
                "mission": mission,
                "observation_key": key,
                "instrument": instrument,
                "product_count": len(group_products),
                "filters": sorted({value for product in group_products for value in filter_keys(product.get("filters"))}),
                "total_size_bytes": sum(int(product.get("contentlength") or 0) for product in group_products),
                "products": group_products,
            }
        )
    return output


def mission_limits(missions: list[str], limit: int, balanced: bool) -> list[tuple[str, int]]:
    if not balanced:
        return [(mission, limit) for mission in missions]
    base, remainder = divmod(limit, len(missions))
    return [
        (mission, base + (1 if index < remainder else 0))
        for index, mission in enumerate(missions)
        if base + (1 if index < remainder else 0) > 0
    ]


def fetch_candidates(
    *,
    ra: float,
    dec: float,
    radius: float,
    missions: list[str],
    filters: list[str],
    calibration_levels: list[int],
    product_types: list[str],
    limit: int,
    balanced_missions: bool,
    timeout: float,
    retries: int,
    workers: int,
    require_all_missions: bool,
    show_query: bool,
) -> tuple[list[dict[str, Any]], dict[str, str], dict[str, str]]:
    limits = mission_limits(missions, limit, balanced_missions)
    queries = {
        mission: build_science_product_query(
            ra=ra,
            dec=dec,
            radius=radius,
            mission=mission,
            filters=filters,
            calibration_levels=calibration_levels,
            product_types=product_types,
            limit=mission_limit,
        )
        for mission, mission_limit in limits
    }
    if show_query:
        for mission, query in queries.items():
            LOGGER.info("ADQL mission=%s\n%s", mission, query)

    LOGGER.info(
        "TAP candidate fetch started missions=%s mission_limits=%s workers=%s retries=%s timeout_seconds=%s",
        ",".join(missions),
        dict(limits),
        workers,
        retries,
        timeout,
    )

    def query_mission(mission: str, query: str) -> dict[str, Any]:
        LOGGER.info("TAP mission query started mission=%s", mission)
        started = time.monotonic()
        response = query_tap(query, timeout, retries)
        LOGGER.info(
            "TAP mission query finished mission=%s rows=%s elapsed_seconds=%.3f",
            mission,
            len(response.get("data", [])),
            time.monotonic() - started,
        )
        return response

    rows_by_mission: dict[str, list[dict[str, Any]]] = {}
    failures: dict[str, str] = {}
    worker_count = min(max(workers, 1), max(len(queries), 1), 4)
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = {
            executor.submit(query_mission, mission, query): mission
            for mission, query in queries.items()
        }
        for future in as_completed(futures):
            mission = futures[future]
            try:
                rows_by_mission[mission] = named_rows(future.result())
            except RuntimeError as error:
                failures[mission] = str(error)
                LOGGER.warning("TAP mission query failed mission=%s error=%s", mission, error)

    if failures and require_all_missions:
        details = "; ".join(f"{mission}: {message}" for mission, message in sorted(failures.items()))
        raise RuntimeError(f"One or more required mission queries failed: {details}")
    if not rows_by_mission:
        details = "; ".join(f"{mission}: {message}" for mission, message in sorted(failures.items()))
        raise RuntimeError(f"All mission queries failed: {details}")

    rows = [row for mission, _ in limits for row in rows_by_mission.get(mission, [])]
    LOGGER.info(
        "TAP candidate fetch finished rows=%s successful_missions=%s failed_missions=%s",
        len(rows),
        ",".join(mission for mission, _ in limits if mission in rows_by_mission),
        ",".join(sorted(failures)),
    )
    return rows, queries, failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query MAST TAP and greedily select science products and observation groups."
    )
    parser.add_argument("--target", help="Target name to resolve, for example 'NGC 628'.")
    parser.add_argument("--ra", type=float, help="ICRS right ascension in degrees.")
    parser.add_argument("--dec", type=float, help="ICRS declination in degrees.")
    parser.add_argument("--radius", type=float, default=0.1, help="Search radius in degrees (default: 0.1).")
    parser.add_argument("--missions", default=",".join(DEFAULT_MISSIONS), help="Comma-separated collections.")
    parser.add_argument("--filters", default="", help="Optional comma-separated filter fragments.")
    parser.add_argument("--calib-levels", default="3,4", help="Comma-separated calibration levels.")
    parser.add_argument("--product-types", default="IMAGE,CUBE", help="Comma-separated CAOM product types.")
    parser.add_argument("--limit", type=int, default=100, help="Candidate TAP rows (default: 100).")
    parser.add_argument(
        "--balanced-missions",
        action="store_true",
        help="Divide --limit across mission queries; otherwise --limit applies to each mission.",
    )
    parser.add_argument("--max-products", type=int, default=5, help="Maximum selected products.")
    parser.add_argument("--max-mb", type=float, default=70, help="Maximum MiB per product.")
    parser.add_argument("--max-total-mb", type=float, help="Optional total selected MiB budget.")
    parser.add_argument("--target-coverage", type=float, default=0.80, help="Desired coverage fraction.")
    parser.add_argument("--min-filters", type=int, default=3, help="Desired distinct-filter count.")
    parser.add_argument("--coverage-weight", type=float, default=0.65)
    parser.add_argument("--filter-weight", type=float, default=0.35)
    parser.add_argument("--size-penalty-exponent", type=float, default=1.0)
    parser.add_argument("--grid", type=int, default=48, help="Coverage grid dimension.")
    parser.add_argument("--timeout", type=float, default=120, help="Network timeout per request.")
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
        help="Concurrent mission queries. One is gentlest on MAST and is the default.",
    )
    parser.add_argument(
        "--require-all-missions",
        action="store_true",
        help="Fail the run if any mission query fails; default behavior keeps successful missions.",
    )
    parser.add_argument("--show-query", action="store_true", help="Print ADQL to stderr.")
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
        help="Logging verbosity written to stderr (default: INFO).",
    )
    parser.add_argument("--log-file", type=Path, help="Also append logs to this file.")
    parser.add_argument("--output", type=Path, help="Write JSON here instead of stdout.")
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.radius <= 0:
        raise ValueError("--radius must be greater than zero")
    if args.limit <= 0 or args.max_products <= 0 or args.max_mb <= 0:
        raise ValueError("--limit, --max-products, and --max-mb must be greater than zero")
    if args.grid <= 0 or args.coverage_weight < 0 or args.filter_weight < 0:
        raise ValueError("--grid and scoring weights must be non-negative")
    if args.retries < 0:
        raise ValueError("--retries must be non-negative")
    if args.size_penalty_exponent < 0:
        raise ValueError("--size-penalty-exponent must be non-negative")
    if (args.ra is None) != (args.dec is None):
        raise ValueError("provide both --ra and --dec")
    if args.ra is None and not args.target:
        raise ValueError("provide --target or both --ra and --dec")


def main() -> int:
    args = parse_args()
    configure_logging(args.log_level, args.log_file)
    workflow_started = time.monotonic()
    LOGGER.info("Workflow started target=%r", args.target or "Coordinate target")
    validate_args(args)
    missions = parse_csv(args.missions)
    filters = parse_csv(args.filters) if args.filters.strip() else []
    product_types = parse_csv(args.product_types)
    try:
        calibration_levels = [int(value) for value in parse_csv(args.calib_levels, uppercase=False)]
    except ValueError as error:
        raise ValueError("--calib-levels must contain integers") from error
    if not missions or not product_types or not calibration_levels:
        raise ValueError("missions, product types, and calibration levels cannot be empty")

    if args.ra is None:
        ra, dec = resolve_target(args.target, args.timeout, args.retries)
    else:
        ra, dec = args.ra, args.dec
    if not 0 <= ra < 360 or not -90 <= dec <= 90:
        raise ValueError("coordinates must satisfy 0 <= RA < 360 and -90 <= Dec <= 90")

    products, queries, query_errors = fetch_candidates(
        ra=ra,
        dec=dec,
        radius=args.radius,
        missions=missions,
        filters=filters,
        calibration_levels=calibration_levels,
        product_types=product_types,
        limit=args.limit,
        balanced_missions=args.balanced_missions,
        timeout=args.timeout,
        retries=args.retries,
        workers=args.workers,
        require_all_missions=args.require_all_missions,
        show_query=args.show_query,
    )
    options = SelectionOptions(
        max_products=args.max_products,
        max_product_bytes=int(args.max_mb * MIB),
        max_total_bytes=int(args.max_total_mb * MIB) if args.max_total_mb is not None else None,
        target_coverage=args.target_coverage,
        minimum_filters=max(args.min_filters, 0),
        coverage_weight=args.coverage_weight,
        filter_weight=args.filter_weight,
        size_penalty_exponent=args.size_penalty_exponent,
        grid_dimension=args.grid,
    )
    result = greedy_select(
        products,
        target_name=args.target or "Coordinate target",
        ra=ra,
        dec=dec,
        radius=args.radius,
        options=options,
    )
    result["options"] = asdict(options)
    result["missions"] = missions
    result["adql_by_mission"] = queries
    result["mission_query_errors"] = query_errors
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        LOGGER.info(
            "Report written path=%s selected_products=%s observation_groups=%s",
            args.output,
            len(result["selected_products"]),
            len(result["observation_groups"]),
        )
    else:
        sys.stdout.write(rendered)
    LOGGER.info("Workflow finished elapsed_seconds=%.3f", time.monotonic() - workflow_started)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
