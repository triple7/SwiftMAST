#!/usr/bin/env python3
"""Fetch and prepare real MAST products for the process-graph experiments.

This script delegates TAP qualification to the repository's maintained
``mast_composite_pipeline.py`` implementation, then writes a second artifact
that makes the relationships from ``00-shared-preparation.mmd`` explicit.
It downloads metadata only; it never downloads a FITS or preview image.

Example::

    .venv/bin/python research/process-graphs/scripts/phase1.py \
      --target "NGC 628" \
      --missions JWST,HST,HLA \
      --radius 0.05 \
      --run-dir research/process-graphs/runs/ngc628

Principal outputs::

    phase-1-qualified.json
    phase-1-observation-groups.csv
    phase-1-process-graph-input.json
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import logging
import os
import sys
import tempfile
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
PIPELINE_PATH = ROOT / "Sources" / "scripts" / "mast_composite_pipeline.py"
SCHEMA_VERSION = 1
LOGGER = logging.getLogger("swiftmast.process_graphs.phase1")

# Loading the maintained pipeline also loads Matplotlib for its audit charts.
# Give it a stable writable cache when the user's home cache is read-only.
_MPL_CACHE = Path(tempfile.gettempdir()) / "swiftmast-process-graphs-matplotlib"
_MPL_CACHE.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("MPLCONFIGDIR", str(_MPL_CACHE))


def load_pipeline():
    """Load the maintained TAP pipeline without invoking its command line."""

    spec = importlib.util.spec_from_file_location(
        "swiftmast_process_graph_pipeline", PIPELINE_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {PIPELINE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1_048_576), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def product_identity(row: dict[str, Any]) -> str:
    return str(row.get("datauri") or row.get("obs_id") or "").strip()


def build_shared_preparation(phase1: dict[str, Any], tap) -> dict[str, Any]:
    """Materialize the entities described by 00-shared-preparation.mmd.

    Exact products remain intact. ``representative_products`` is a separate
    view and therefore does not discard the original product records.
    """

    rows = list(phase1.get("qualified_rows", []))
    products_by_group: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        group_id = str(row.get("observation_group_id") or "").strip()
        if group_id:
            products_by_group[group_id].append(row)

    prepared_groups: list[dict[str, Any]] = []
    filter_group_count: Counter[str] = Counter()
    adjacency: dict[str, set[str]] = defaultdict(set)
    all_filters: set[str] = set()

    for group_id in sorted(products_by_group):
        products = sorted(
            products_by_group[group_id],
            key=lambda row: (
                str(row.get("obs_id") or ""),
                product_identity(row),
            ),
        )
        filters_by_product = {
            product_identity(row): sorted(tap.filter_keys(row.get("filters")))
            for row in products
        }
        filters = sorted(
            {name for names in filters_by_product.values() for name in names}
        )
        all_filters.update(filters)
        filter_group_count.update(filters)
        for left, right in combinations(filters, 2):
            adjacency[left].add(right)
            adjacency[right].add(left)

        by_signature: dict[tuple[str, ...], list[dict[str, Any]]] = defaultdict(list)
        for row in products:
            identity = product_identity(row)
            by_signature[tuple(filters_by_product[identity])].append(row)
        representative_products = []
        for signature in sorted(by_signature):
            winner = min(
                by_signature[signature],
                key=lambda row: (
                    str(row.get("obs_id") or ""),
                    product_identity(row),
                ),
            )
            representative_products.append(product_identity(winner))

        sizes = [int(row.get("contentlength_bytes") or row.get("contentlength") or 0) for row in products]
        total_bytes = sum(sizes)
        prepared_groups.append(
            {
                "group_id": group_id,
                "observation_group": str(
                    products[0].get("observation_group") or group_id
                ),
                "observation_ids": [str(row.get("obs_id") or "") for row in products],
                "product_identities": [product_identity(row) for row in products],
                "representative_products": representative_products,
                "filters": filters,
                "filter_count": len(filters),
                "product_count": len(products),
                "total_bytes": total_bytes,
                "average_file_bytes": total_bytes / len(products) if products else 0,
                "max_bytes": max(sizes, default=0),
            }
        )

    pairs = [
        [left, right]
        for left in sorted(adjacency)
        for right in sorted(adjacency[left])
        if left < right
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "artifact": "process-graphs-phase-1-prepared",
        "source": {
            "artifact": phase1.get("artifact"),
            "created_at": phase1.get("created_at"),
        },
        "configuration": phase1.get("configuration", {}),
        "summary": {
            "qualified_product_count": len(rows),
            "qualified_group_count": len(prepared_groups),
            "filter_count": len(all_filters),
            "adjacent_pair_count": len(pairs),
            "max_filters_in_any_group": max(
                (group["filter_count"] for group in prepared_groups), default=0
            ),
        },
        "groups": prepared_groups,
        "filter_graph": {
            "filters": sorted(all_filters),
            "group_count": dict(sorted(filter_group_count.items())),
            "adjacent_pairs": pairs,
            "degree": {
                name: len(adjacency[name]) for name in sorted(all_filters)
            },
        },
        "products": rows,
    }


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
    parser.add_argument("--target")
    parser.add_argument("--ra", type=float)
    parser.add_argument("--dec", type=float)
    parser.add_argument("--radius", type=positive_float, default=0.05)
    parser.add_argument("--missions", default="JWST,HST,HLA")
    parser.add_argument("--per-filter-limit", type=positive_int, default=1000)
    parser.add_argument("--max-file-mib", type=positive_float, default=2048)
    parser.add_argument("--min-group-observation-ids", type=positive_int, default=3)
    parser.add_argument("--timeout", type=positive_float, default=180)
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    if args.retries < 0:
        raise ValueError("--retries must be zero or greater")

    pipeline = load_pipeline()
    qualify_args = argparse.Namespace(
        target=args.target,
        ra=args.ra,
        dec=args.dec,
        radius=args.radius,
        missions=args.missions,
        per_filter_limit=args.per_filter_limit,
        max_file_mib=args.max_file_mib,
        min_group_observation_ids=args.min_group_observation_ids,
        timeout=args.timeout,
        retries=args.retries,
        run_dir=args.run_dir,
    )
    pipeline.run_qualify(qualify_args)

    run_dir = args.run_dir.expanduser().resolve()
    qualified_path = run_dir / "phase-1-qualified.json"
    phase1 = json.loads(qualified_path.read_text(encoding="utf-8"))
    prepared = build_shared_preparation(phase1, pipeline.load_greedy())
    prepared["source"]["path"] = str(qualified_path)
    prepared["source"]["sha256"] = file_sha256(qualified_path)
    prepared_path = run_dir / "phase-1-process-graph-input.json"
    write_json(prepared_path, prepared)
    LOGGER.info(
        "Prepared process graph groups=%s products=%s filters=%s path=%s",
        prepared["summary"]["qualified_group_count"],
        prepared["summary"]["qualified_product_count"],
        prepared["summary"]["filter_count"],
        prepared_path,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
