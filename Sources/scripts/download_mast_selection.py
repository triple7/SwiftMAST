#!/usr/bin/env python3
"""Download an official Phase 2 MAST composite manifest.

This script never performs TAP queries or selection. Use ``--dry-run`` to
inspect the SwiftMAST cache destinations and expected transfer size.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import logging
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
MIB = 1_048_576
GREEDY_PATH = Path(__file__).with_name("greedy_mast_tap_selection.py")
LOGGER = logging.getLogger("swiftmast.selection_downloader")
REQUIRED_FIELDS = (
    "obs_collection",
    "obs_id",
    "filters",
    "datauri",
    "contentlength",
)


def load_greedy():
    spec = importlib.util.spec_from_file_location("swiftmast_greedy_download", GREEDY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {GREEDY_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported manifest schema {manifest.get('schema_version')!r}; "
            f"expected {SCHEMA_VERSION}"
        )
    if manifest.get("artifact") != "mast-composite-download-manifest":
        raise ValueError("input is not a MAST composite download manifest")
    products = manifest.get("selected_products")
    if not isinstance(products, list):
        raise ValueError("manifest selected_products must be an array")
    errors = []
    seen: set[str] = set()
    for index, product in enumerate(products, start=1):
        if not isinstance(product, dict):
            errors.append(f"product {index}: expected object")
            continue
        missing = [field for field in REQUIRED_FIELDS if product.get(field) in (None, "")]
        if missing:
            errors.append(f"product {index}: missing {', '.join(missing)}")
        uri = str(product.get("datauri") or "")
        if uri in seen:
            errors.append(f"product {index}: duplicate datauri {uri}")
        seen.add(uri)
        try:
            if int(float(product.get("contentlength"))) <= 0:
                errors.append(f"product {index}: contentlength must be positive")
        except (TypeError, ValueError, OverflowError):
            errors.append(f"product {index}: contentlength is not numeric")
    if errors:
        raise ValueError("manifest preflight failed:\n- " + "\n- ".join(errors))
    return manifest


def dry_run_report(
    greedy,
    products: list[dict[str, Any]],
    *,
    target_name: str,
    cache_root: Path,
) -> dict[str, Any]:
    entries = []
    for product in products:
        destination, sidecar = greedy.swiftmast_cache_paths(cache_root, target_name, product)
        expected = int(float(product["contentlength"]))
        cached = greedy.is_complete_fits(destination, expected)
        entries.append(
            {
                "selection_rank": product.get("selection_rank"),
                "observation_id": product.get("obs_id"),
                "product_uri": product.get("datauri"),
                "expected_size_bytes": expected,
                "status": "cached" if cached else "would_download",
                "local_fits_path": str(destination),
                "coam_sidecar_path": str(sidecar),
            }
        )
    return {
        "dry_run": True,
        "cache_root": str(cache_root),
        "requested_product_count": len(products),
        "cached_product_count": sum(entry["status"] == "cached" for entry in entries),
        "would_download_product_count": sum(
            entry["status"] == "would_download" for entry in entries
        ),
        "expected_total_bytes": sum(entry["expected_size_bytes"] for entry in entries),
        "expected_transfer_bytes": sum(
            entry["expected_size_bytes"]
            for entry in entries
            if entry["status"] == "would_download"
        ),
        "products": entries,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--cache-root",
        type=Path,
        default=Path.home() / "Documents" / "MAST",
        help="SwiftMAST MAST cache root (default: ~/Documents/MAST)",
    )
    parser.add_argument("--target-name", help="Override the target cache folder name")
    parser.add_argument("--output", type=Path, help="Download report path")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if args.retries < 0:
        parser.error("--retries cannot be negative")

    manifest_path = args.manifest.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    products = manifest["selected_products"]
    target_name = str(args.target_name or manifest.get("target") or "").strip()
    if not target_name:
        position = manifest.get("position") or {}
        target_name = (
            f"ra-{float(position['ra']):.6f}_dec-{float(position['dec']):.6f}"
        )
    cache_root = args.cache_root.expanduser().resolve()
    expected = sum(int(float(product["contentlength"])) for product in products)
    LOGGER.info(
        "Manifest ready products=%s expected_GiB=%.2f target=%r cache_root=%s",
        len(products),
        expected / (1024**3),
        target_name,
        cache_root,
    )
    greedy = load_greedy()
    if args.dry_run:
        report = dry_run_report(
            greedy,
            products,
            target_name=target_name,
            cache_root=cache_root,
        )
    else:
        report = greedy.download_selected_products(
            products,
            target_name=target_name,
            cache_root=cache_root,
            timeout=args.timeout,
            retries=args.retries,
        )
        report["dry_run"] = False
    report["schema_version"] = SCHEMA_VERSION
    report["artifact"] = "mast-composite-phase-3-download-report"
    report["manifest_path"] = str(manifest_path)
    report_path = (
        args.output.expanduser().resolve()
        if args.output
        else manifest_path.parent / "phase-3-download-report.json"
    )
    write_json(report_path, report)
    LOGGER.info("Phase 3 report written path=%s", report_path)
    return 1 if int(report.get("failed_product_count") or 0) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        LOGGER.exception("Selection download failed")
        raise
