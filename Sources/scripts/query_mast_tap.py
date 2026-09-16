#!/usr/bin/env python3
"""Query public science-image products from the MAST CAOM TAP service.

The initial query is metadata-only: it does not download FITS headers or FITS
pixels. It returns the product URI, archive metadata, sky footprint, dimensions,
pixel scale, and estimated file size needed for preliminary selection/ranking.

Dependency:
    python3 -m pip install requests

Examples:
    python3 Sources/scripts/query_mast_tap.py --target "NGC 628" --limit 10

    python3 Sources/scripts/query_mast_tap.py \
        --ra 24.174 --dec 15.783 --radius 0.1 \
        --missions JWST,HST,HLA --balanced-missions --limit 100 \
        --output demo-mast-selected-columns-query.txt

    python3 Sources/scripts/query_mast_tap.py --schema
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


MAST_TAP_URL = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
MAST_API_URL = "https://mast.stsci.edu/api/v0/invoke"
DEFAULT_MISSIONS = ("JWST", "HST", "HLA")
TAP_TABLES = ("dbo.obspointing", "dbo.caomplane", "dbo.caomartifact")

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


def post_form_json(url: str, values: dict[str, str], timeout: float) -> dict[str, Any]:
    """POST form-encoded values and decode a JSON response."""

    retry = Retry(
        total=2,
        connect=2,
        read=2,
        status=2,
        backoff_factor=1,
        allowed_methods=frozenset({"POST"}),
        status_forcelist=(429, 500, 502, 503, 504),
    )
    session = requests.Session()
    session.mount("https://", HTTPAdapter(max_retries=retry))
    try:
        response = session.post(
            url,
            data=values,
            headers={
                "Accept": "application/json",
                "User-Agent": "SwiftMAST-TAP-query/1.0",
            },
            timeout=timeout,
        )
        response.raise_for_status()
    except requests.RequestException as error:
        raise RuntimeError(f"Could not query MAST: {error}") from error
    finally:
        session.close()

    try:
        decoded = response.json()
    except requests.exceptions.JSONDecodeError as error:
        raise RuntimeError(f"MAST did not return JSON: {response.text[:500]}") from error

    if not isinstance(decoded, dict):
        raise RuntimeError("MAST returned an unexpected JSON value")
    return decoded


def query_tap(adql: str, timeout: float = 120) -> dict[str, Any]:
    """Submit an ADQL query to the synchronous MAST CAOM TAP endpoint."""

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
    )

    # Successful MAST JSON responses contain `info` and `data`. TAP errors may
    # instead be returned as a different JSON object.
    if not isinstance(response.get("info"), list) or not isinstance(response.get("data"), list):
        raise RuntimeError(f"Unexpected TAP response: {json.dumps(response)[:500]}")
    return response


def resolve_target(target: str, timeout: float = 30) -> tuple[float, float]:
    """Resolve a target name through Mast.Name.Lookup."""

    mast_request = {
        "service": "Mast.Name.Lookup",
        "params": {"input": target, "format": "json"},
        "format": "json",
    }
    response = post_form_json(
        MAST_API_URL,
        {"request": json.dumps(mast_request, separators=(",", ":"))},
        timeout,
    )
    coordinates = response.get("resolvedCoordinate")
    if not isinstance(coordinates, list) or not coordinates:
        raise RuntimeError(f"MAST could not resolve target {target!r}")

    first = coordinates[0]
    try:
        return float(first["ra"]), float(first["decl"])
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError(f"Invalid target-resolution response: {first!r}") from error


def adql_strings(values: list[str] | tuple[str, ...]) -> str:
    """Return safely quoted ADQL string literals."""

    return ",".join("'" + value.replace("'", "''") + "'" for value in values)


def parse_csv_values(raw: str) -> list[str]:
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
    columns: list[str] | None = None,
) -> str:
    """Build the metadata-only ADQL used for candidate discovery."""

    predicates = [
        "CONTAINS("
        "POINT('ICRS', o.s_ra, o.s_dec), "
        f"CIRCLE('ICRS', {ra:.12g}, {dec:.12g}, {radius:.12g})"
        ") = 1",
        f"o.obs_collection IN ({adql_strings(missions)})",
        "o.datarights = 'PUBLIC'",
        "o.calib_level IN (3,4)",
        "LOWER(o.dataproduct_type) IN ('image','cube')",
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

    select_columns = ",\n        ".join(columns or APPLICATION_COLUMNS)

    return (
        f"SELECT TOP {limit}\n"
        f"    {select_columns}\n"
        "FROM dbo.obspointing AS o\n"
        "JOIN dbo.caomplane AS p ON p.planetid = o.objid\n"
        "JOIN dbo.caomartifact AS a ON a.planetid = p.planetid\n"
        "WHERE "
        + "\n  AND ".join(predicates)
        + "\nORDER BY o.obs_collection, o.instrument_name, o.obs_id, o.filters"
    )


def build_schema_query() -> str:
    """Return the schema query for all tables used by the product query."""

    return (
        "SELECT table_name,column_name,datatype,unit,description "
        "FROM TAP_SCHEMA.columns "
        f"WHERE table_name IN ({adql_strings(TAP_TABLES)})"
    )


def coerce_tap_value(value: Any, datatype: str) -> Any:
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query MAST CAOM TAP for public science FITS candidates."
    )
    parser.add_argument("--target", help="Target name to resolve, for example 'NGC 628'.")
    parser.add_argument("--ra", type=float, help="ICRS right ascension in degrees.")
    parser.add_argument("--dec", type=float, help="ICRS declination in degrees.")
    parser.add_argument("--radius", type=float, default=0.1, help="Search radius in degrees (default: 0.1).")
    parser.add_argument("--missions", default=",".join(DEFAULT_MISSIONS), help="Comma-separated MAST collections.")
    parser.add_argument("--filters", default="", help="Optional comma-separated filter-name fragments.")
    parser.add_argument("--limit", type=int, default=50, help="Maximum returned rows (default: 50).")
    parser.add_argument("--timeout", type=float, default=120, help="Network timeout in seconds.")
    parser.add_argument("--schema", action="store_true", help="Query the schema of the three joined CAOM tables.")
    parser.add_argument(
        "--balanced-missions",
        action="store_true",
        help=(
            "Split --limit approximately evenly across requested missions. "
            "Use this for representative availability samples."
        ),
    )
    parser.add_argument("--show-query", action="store_true", help="Print ADQL to stderr before submitting it.")
    parser.add_argument("--output", type=Path, help="Write formatted JSON to this path instead of stdout.")
    parser.add_argument(
        "--columns",
        default="",
        help="Diagnostic override using comma-separated TAP column references.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.radius <= 0:
        raise ValueError("--radius must be greater than zero")
    if args.limit <= 0:
        raise ValueError("--limit must be greater than zero")

    if args.schema:
        query = build_schema_query()
        resolved_position = None
    else:
        if (args.ra is None) != (args.dec is None):
            raise ValueError("provide both --ra and --dec")
        if args.ra is None:
            if not args.target:
                raise ValueError("provide --target or both --ra and --dec")
            ra, dec = resolve_target(args.target, timeout=args.timeout)
        else:
            ra, dec = args.ra, args.dec

        if not 0 <= ra < 360:
            raise ValueError("--ra must be in [0, 360)")
        if not -90 <= dec <= 90:
            raise ValueError("--dec must be in [-90, 90]")

        resolved_position = {"ra": ra, "dec": dec, "radius_degrees": args.radius}
        missions = parse_csv_values(args.missions)
        filters = parse_csv_values(args.filters) if args.filters.strip() else []
        columns = parse_column_values(args.columns) if args.columns.strip() else None

        if args.balanced_missions and len(missions) > 1:
            base_limit, remainder = divmod(args.limit, len(missions))
            mission_limits = [
                base_limit + (1 if index < remainder else 0)
                for index in range(len(missions))
            ]
            queries = [
                build_science_product_query(
                    ra=ra,
                    dec=dec,
                    radius=args.radius,
                    missions=[mission],
                    filters=filters,
                    limit=mission_limit,
                    columns=columns,
                )
                for mission, mission_limit in zip(missions, mission_limits)
                if mission_limit > 0
            ]
        else:
            queries = [
                build_science_product_query(
                    ra=ra,
                    dec=dec,
                    radius=args.radius,
                    missions=missions,
                    filters=filters,
                    limit=args.limit,
                    columns=columns,
                )
            ]

    if args.show_query:
        print("\n\n".join(queries if not args.schema else [query]), file=sys.stderr)

    if args.schema:
        queries = [query]

    responses = [query_tap(adql, timeout=args.timeout) for adql in queries]
    rows = [row for response in responses for row in named_rows(response)]
    response_columns = responses[0]["info"] if responses else []
    result = {
        "target": args.target,
        "position": resolved_position,
        "row_count": len(rows),
        "columns": [column.get("name") for column in response_columns],
        "column_availability": column_availability(rows),
        "missions": mission_summary(rows),
        "adql": queries[0] if len(queries) == 1 else queries,
        "rows": rows,
    }
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {len(rows)} row(s) to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(rendered)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
