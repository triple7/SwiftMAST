from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = (
    Path(__file__).parents[2]
    / "Sources"
    / "scripts"
    / "download_mast_selection.py"
)
SPEC = importlib.util.spec_from_file_location("download_mast_selection", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def card(keyword: str, value: str) -> bytes:
    return f"{keyword:<8}= {value}".ljust(80).encode("ascii")


class AdaptiveDownloadTests(unittest.TestCase):
    def test_explicit_adaptive_subcommand(self) -> None:
        args = MODULE.build_parser().parse_args(
            ["adaptive", "--manifest", "phase-2-download-manifest.json"]
        )

        self.assertEqual(args.command, "adaptive")
        self.assertIs(args.func, MODULE.run_adaptive)
        self.assertEqual(args.min_preview_width, 1024)

    def test_legacy_arguments_route_to_fits_subcommand(self) -> None:
        normalized = MODULE.normalized_cli_args(
            ["--manifest", "phase-2-download-manifest.json", "--dry-run"]
        )
        args = MODULE.build_parser().parse_args(normalized)

        self.assertEqual(args.command, "fits")
        self.assertIs(args.func, MODULE.run_fits)

    def test_fits_header_parser_reads_dimensions_and_padding(self) -> None:
        data = b"".join(
            (
                card("SIMPLE", "T"),
                card("BITPIX", "-32"),
                card("NAXIS", "2"),
                card("NAXIS1", "2048"),
                card("NAXIS2", "1024"),
                b"END".ljust(80),
            )
        ).ljust(MODULE.BLOCK_SIZE, b" ")

        parsed = MODULE.parse_header_block(data)

        self.assertIsNotNone(parsed)
        header, header_size = parsed
        self.assertEqual(header["NAXIS1"], 2048)
        self.assertEqual(header["NAXIS2"], 1024)
        self.assertEqual(header_size, MODULE.BLOCK_SIZE)
        self.assertEqual(MODULE.fits_data_size(header), 2048 * 1024 * 4)

    def test_preview_is_selected_only_when_every_gate_passes(self) -> None:
        header = {"width": 2048, "height": 2048, "has_complete_wcs": True}
        preview = {"width": 1200, "height": 1200}

        choice, reasons = MODULE.preview_decision(
            header,
            None,
            preview,
            None,
            min_source_width=1024,
            min_source_height=1024,
            min_preview_width=1024,
            min_preview_height=1024,
            require_wcs=True,
        )

        self.assertEqual(choice, "preview")
        self.assertEqual(reasons, ["all_quality_gates_passed"])

    def test_missing_wcs_or_small_preview_falls_back_to_fits(self) -> None:
        header = {"width": 2048, "height": 2048, "has_complete_wcs": False}
        preview = {"width": 800, "height": 1200}

        choice, reasons = MODULE.preview_decision(
            header,
            None,
            preview,
            None,
            min_source_width=1024,
            min_source_height=1024,
            min_preview_width=1024,
            min_preview_height=1024,
            require_wcs=True,
        )

        self.assertEqual(choice, "fits")
        self.assertIn("fits_wcs_incomplete", reasons)
        self.assertIn("preview_width_below_threshold", reasons)

    def test_failed_header_probe_is_a_conservative_fits_fallback(self) -> None:
        choice, reasons = MODULE.preview_decision(
            None,
            "range unsupported",
            {"width": 2048, "height": 2048},
            None,
            min_source_width=1024,
            min_source_height=1024,
            min_preview_width=1024,
            min_preview_height=1024,
            require_wcs=False,
        )

        self.assertEqual(choice, "fits")
        self.assertIn("fits_header_probe_failed", reasons)


if __name__ == "__main__":
    unittest.main()
