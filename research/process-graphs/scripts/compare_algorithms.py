#!/usr/bin/env python3
"""Run every Phase 2 comparison algorithm and build a visual gallery.

Example::

    .venv/bin/python research/process-graphs/scripts/compare_algorithms.py \
      --input research/pipeline-runs/ngc628/phase-1-qualified.json \
      --output-dir research/process-graphs/comparison-outputs/ngc628

Use ``--reuse-existing`` to rebuild the summary and gallery without rerunning
the selectors.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import phase2


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
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--max-file-mib", type=positive_float, default=300)
    parser.add_argument("--max-total-mib", type=positive_float, default=2000)
    parser.add_argument("--max-products", type=positive_int, default=40)
    parser.add_argument("--grid-dimension", type=positive_int, default=48)
    parser.add_argument("--texture-density", type=positive_int, default=10)
    parser.add_argument("--dpi", type=positive_int, default=120)
    parser.add_argument("--reuse-existing", action="store_true")
    parser.add_argument(
        "--log-level", choices=("DEBUG", "INFO", "WARNING", "ERROR"), default="WARNING"
    )
    return parser


def expected_paths(root: Path, algorithm: str) -> tuple[Path, Path]:
    directory = root / algorithm
    return (
        directory / f"phase-2-{algorithm}-selection.json",
        directory / f"phase-2-{algorithm}-footprints.png",
    )


def run_algorithms(args: argparse.Namespace, output_dir: Path) -> None:
    for algorithm in phase2.ALGORITHMS:
        selection_path, image_path = expected_paths(output_dir, algorithm)
        if args.reuse_existing and selection_path.is_file() and image_path.is_file():
            continue
        result = phase2.main(
            [
                "--input",
                str(args.input),
                "--algorithm",
                algorithm,
                "--max-file-mib",
                str(args.max_file_mib),
                "--max-total-mib",
                str(args.max_total_mib),
                "--max-products",
                str(args.max_products),
                "--grid-dimension",
                str(args.grid_dimension),
                "--texture-density",
                str(args.texture_density),
                "--dpi",
                str(args.dpi),
                "--output-dir",
                str(output_dir / algorithm),
                "--log-level",
                args.log_level,
            ]
        )
        if result != 0:
            raise RuntimeError(f"{algorithm} failed with status {result}")


def collect_results(output_dir: Path) -> list[dict[str, Any]]:
    results = []
    for algorithm, description in phase2.ALGORITHMS.items():
        selection_path, image_path = expected_paths(output_dir, algorithm)
        if not selection_path.is_file() or not image_path.is_file():
            raise FileNotFoundError(f"missing output for {algorithm}")
        selection = json.loads(selection_path.read_text(encoding="utf-8"))
        results.append(
            {
                "algorithm": algorithm,
                "description": description,
                "implementation_note": selection.get("implementation_note"),
                "selection": str(selection_path),
                "image": str(image_path),
                "summary": selection["summary"],
            }
        )
    return results


def write_gallery(path: Path, target: str, results: list[dict[str, Any]], dpi: int) -> None:
    figure, axes = phase2.plt.subplots(5, 2, figsize=(18, 28), facecolor="#080A0F")
    for axis, result in zip(axes.flat, results):
        summary = result["summary"]
        axis.imshow(phase2.plt.imread(result["image"]))
        axis.set_title(
            f"{result['algorithm']}\n"
            f"products={summary['selected_product_count']}  "
            f"groups={summary['selected_group_count']}  "
            f"filters={summary['selected_filter_count']}\n"
            f"coverage={summary['coverage_percentage']:.2f}%  "
            f"size={summary['selected_size_mib']:.1f} MiB",
            color="white",
            fontsize=12,
        )
        axis.axis("off")
    figure.suptitle(
        f"{target} — Phase 2 algorithm comparison",
        color="white",
        fontsize=22,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(path, dpi=max(80, min(dpi, 130)), bbox_inches="tight", facecolor=figure.get_facecolor())
    phase2.plt.close(figure)


def write_readme(
    path: Path,
    target: str,
    args: argparse.Namespace,
    results: list[dict[str, Any]],
) -> None:
    lines = [
        f"# {target} Phase 2 comparison",
        "",
        "Every algorithm used the same qualified Phase 1 products and limits:",
        "",
        f"- Maximum file: {args.max_file_mib:g} MiB",
        f"- Total budget: {args.max_total_mib:g} MiB",
        f"- Maximum products: {args.max_products}",
        f"- Coverage grid: {args.grid_dimension} × {args.grid_dimension}",
        "",
        "[Open the ten-algorithm gallery](algorithm-comparison-gallery.png)",
        "",
        "| Algorithm | Products | Groups | Filters | Size MiB | Coverage | Image |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for result in results:
        summary = result["summary"]
        relative_image = Path(result["image"]).relative_to(path.parent)
        lines.append(
            f"| `{result['algorithm']}` | {summary['selected_product_count']} | "
            f"{summary['selected_group_count']} | {summary['selected_filter_count']} | "
            f"{summary['selected_size_mib']:.2f} | {summary['coverage_percentage']:.2f}% | "
            f"[PNG]({relative_image.as_posix()}) |"
        )
    lines.extend(("", "## Comparison-policy notes", ""))
    for result in results:
        if result["implementation_note"]:
            lines.append(f"- **{result['algorithm']}:** {result['implementation_note']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    input_path = args.input.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    args.input = input_path
    run_algorithms(args, output_dir)
    results = collect_results(output_dir)
    source = json.loads(input_path.read_text(encoding="utf-8"))
    target = str(source.get("configuration", {}).get("target") or "MAST target")
    gallery_path = output_dir / "algorithm-comparison-gallery.png"
    write_gallery(gallery_path, target, results, args.dpi)
    manifest = {
        "artifact": "process-graphs-phase-2-algorithm-comparison",
        "target": target,
        "source": str(input_path),
        "options": {
            "max_file_mib": args.max_file_mib,
            "max_total_mib": args.max_total_mib,
            "max_products": args.max_products,
            "grid_dimension": args.grid_dimension,
            "texture_density": args.texture_density,
            "dpi": args.dpi,
        },
        "gallery": str(gallery_path),
        "algorithms": results,
    }
    phase2.write_json(output_dir / "comparison-summary.json", manifest)
    write_readme(output_dir / "README.md", target, args, results)
    print(
        json.dumps(
            {
                "output_directory": str(output_dir),
                "gallery": str(gallery_path),
                "summary": str(output_dir / "comparison-summary.json"),
                "readme": str(output_dir / "README.md"),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
