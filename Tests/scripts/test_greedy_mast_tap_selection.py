from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "Sources" / "scripts" / "greedy_mast_tap_selection.py"
SPEC = importlib.util.spec_from_file_location("greedy_mast_tap_selection", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def product(
    observation_id: str,
    filter_name: str,
    size_mib: int | None,
    region: str = "CIRCLE ICRS 10.0 0.0 0.04",
    instrument: str = "NIRCAM/IMAGE",
) -> dict[str, object]:
    return {
        "obsid": 1,
        "obs_id": observation_id,
        "obs_collection": "JWST",
        "instrument_name": instrument,
        "target_name": "Test target",
        "filters": filter_name,
        "s_ra": 10.0,
        "s_dec": 0.0,
        "s_region": region,
        "datauri": f"mast:TEST/product/{observation_id}_i2d.fits",
        "previewuri": "",
        "productfilename": f"{observation_id}_i2d.fits",
        "contenttype": "application/fits",
        "contentlength": size_mib * MODULE.MIB if size_mib is not None else None,
    }


class GreedyMASTTAPSelectionTests(unittest.TestCase):
    def test_balanced_mission_limit_matches_research_command(self) -> None:
        self.assertEqual(
            MODULE.mission_limits(["JWST", "HST", "HLA"], 100, True),
            [("JWST", 34), ("HST", 33), ("HLA", 33)],
        )

    def test_region_parser_and_circle_containment(self) -> None:
        shapes = MODULE.parse_s_region("CIRCLE ICRS 10 0 0.05")
        self.assertIsNotNone(shapes)
        self.assertTrue(MODULE.region_contains((10.01, 0), shapes))
        self.assertFalse(MODULE.region_contains((11, 0), shapes))

    def test_selects_smaller_representative_then_new_coverage_and_filter(self) -> None:
        products = [
            product("large-blue", "F435W", 20, "CIRCLE ICRS 10.0 0.0 0.035"),
            product("small-blue", "F435W", 5, "CIRCLE ICRS 10.0 0.0 0.035"),
            product("red-offset", "F814W", 10, "CIRCLE ICRS 10.03 0.0 0.035"),
        ]
        options = MODULE.SelectionOptions(
            max_products=3,
            target_coverage=0.50,
            minimum_filters=2,
            grid_dimension=40,
        )

        with self.assertLogs(MODULE.LOGGER.name, level="INFO") as captured_logs:
            result = MODULE.greedy_select(
                products,
                target_name="Test target",
                ra=10,
                dec=0,
                radius=0.05,
                options=options,
            )

        self.assertEqual(result["selected_products"][0]["obs_id"], "small-blue")
        self.assertEqual(
            {value["obs_id"] for value in result["selected_products"]},
            {"small-blue", "red-offset"},
        )
        self.assertEqual(result["selected_filters"], ["F435W", "F814W"])
        self.assertEqual(result["stop_reason"], "target_satisfied")
        self.assertTrue(
            any("Greedy selection finished" in message for message in captured_logs.output)
        )

    def test_rejects_missing_fields_pseudo_filters_and_oversized_files(self) -> None:
        products = [
            product("valid", "F200W", 10),
            product("missing-size", "F356W", None),
            product("missing-region", "F444W", 10, ""),
            product("pseudo-filter", "DETECTION", 10),
            product("too-large", "F090W", 80),
        ]
        result = MODULE.greedy_select(
            products,
            target_name="Test target",
            ra=10,
            dec=0,
            radius=0.05,
            options=MODULE.SelectionOptions(),
        )

        self.assertEqual(result["eligible_candidate_count"], 1)
        self.assertEqual(result["selected_products"][0]["obs_id"], "valid")
        self.assertEqual(
            {value["reason"] for value in result["excluded_candidates"]},
            {
                "missing_file_size",
                "missing_footprint",
                "missing_filter",
                "exceeds_product_size_limit",
            },
        )

    def test_groups_selected_hst_products_by_observation(self) -> None:
        products = [
            product("hst_10775_62_wfc3_f435w", "F435W", 5, instrument="WFC3/UVIS"),
            product("hst_10775_62_wfc3_f814w", "F814W", 5, instrument="WFC3/UVIS"),
        ]
        for value in products:
            value["obs_collection"] = "HST"
            value["observation_key"] = MODULE.observation_group_key(value)

        groups = MODULE.group_selected_products(products)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["observation_key"], "hst_10775_62_wfc3")
        self.assertEqual(groups[0]["filters"], ["F435W", "F814W"])


if __name__ == "__main__":
    unittest.main()
