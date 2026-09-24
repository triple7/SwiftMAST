from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


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
    region: str = "CIRCLE ICRS 10.0 0.0 0.035",
    *,
    mission: str = "JWST",
    instrument: str = "NIRCAM/IMAGE",
) -> dict[str, object]:
    return {
        "obsid": 1,
        "obs_id": observation_id,
        "obs_collection": mission,
        "instrument_name": instrument,
        "target_name": "Test target",
        "filters": filter_name,
        "s_ra": 10.0,
        "s_dec": 0.0,
        "s_region": region,
        "datauri": f"mast:TEST/product/{observation_id}.fits",
        "previewuri": "",
        "productfilename": f"{observation_id}.fits",
        "contenttype": "application/fits",
        "contentlength": size_mib * MODULE.MIB if size_mib is not None else None,
    }


class HierarchicalGreedyTAPSelectionTests(unittest.TestCase):
    def test_terminal_logging_defaults_to_info(self) -> None:
        with patch.object(
            sys,
            "argv",
            ["greedy_mast_tap_selection.py", "--ra", "10", "--dec", "0"],
        ):
            args = MODULE.parse_args()

        self.assertEqual(args.log_level, "INFO")
        self.assertIsNone(args.log_file)
        self.assertEqual(args.retries, 5)
        self.assertEqual(args.workers, 1)
        self.assertEqual(args.eligibility_filter_location, "local")
        self.assertEqual(args.tap_order, "group")
        self.assertFalse(args.download_selected)
        self.assertEqual(args.cache_root, Path.home() / "Documents" / "MAST")

    def test_query_uses_configurable_calibration_levels_and_product_types(self) -> None:
        query = MODULE.build_science_product_query(
            ra=10,
            dec=0,
            radius=0.05,
            missions=["JWST"],
            filters=[],
            calibration_levels=[2, 4],
            product_types=["IMAGE", "CUBE"],
            limit=10,
        )

        self.assertIn("o.calib_level IN (2,4)", query)
        self.assertIn("LOWER(o.dataproduct_type) IN ('image','cube')", query)

    def test_query_can_push_static_eligibility_filters_and_size_order_to_tap(self) -> None:
        query = MODULE.build_science_product_query(
            ra=10,
            dec=0,
            radius=0.05,
            missions=["JWST"],
            filters=[],
            limit=10,
            eligibility_filter_location="tap",
            max_product_bytes=70 * MODULE.MIB,
            tap_order="min-size",
        )

        self.assertIn("o.s_region IS NOT NULL", query)
        self.assertIn("a.contentlength > 0", query)
        self.assertIn(f"a.contentlength <= {70 * MODULE.MIB}", query)
        self.assertIn("ORDER BY a.contentlength ASC", query)

    def test_tap_query_execution_retains_successful_branches(self) -> None:
        response = {"info": [], "data": []}

        def fake_query(adql: str, *, timeout: float, retries: int) -> dict[str, object]:
            del timeout, retries
            if adql == "bad query":
                raise RuntimeError("temporary MAST failure")
            return response

        with self.assertLogs(MODULE.LOGGER.name, level="WARNING"):
            with patch.object(MODULE, "query_tap", side_effect=fake_query):
                completed, failures = MODULE.execute_tap_queries(
                    [("JWST", "good query"), ("HST", "bad query")],
                    timeout=10,
                    retries=2,
                    workers=1,
                    require_all=False,
                )

        self.assertEqual([label for label, _, _ in completed], ["JWST"])
        self.assertEqual(set(failures), {"HST"})

    def test_region_parser_and_circle_containment(self) -> None:
        shapes = MODULE.parse_s_region("CIRCLE ICRS 10 0 0.05")
        self.assertIsNotNone(shapes)
        self.assertTrue(MODULE.region_contains((10.01, 0), shapes))
        self.assertFalse(MODULE.region_contains((11, 0), shapes))

    def test_prepares_mission_branches_before_global_selection(self) -> None:
        rows = [
            product("jw-one", "F200W", 5),
            product(
                "hst_10775_62_wfc3_f435w",
                "F435W",
                5,
                mission="HST",
                instrument="WFC3/UVIS",
            ),
        ]
        grid = MODULE.make_coverage_grid(10, 0, 0.05, 24)
        branches = MODULE.prepare_candidate_branches(
            [rows], grid, MODULE.SelectionOptions(max_products=2)
        )

        self.assertEqual([branch.mission for branch in branches], ["HST", "JWST"])
        self.assertEqual(sum(len(branch.candidates) for branch in branches), 2)
        self.assertEqual(sum(len(branch.observation_groups) for branch in branches), 2)

    def test_incremental_selector_chooses_size_then_new_coverage_and_filter(self) -> None:
        rows = [
            product("large-blue", "F435W", 20),
            product("small-blue", "F435W", 5),
            product(
                "red-offset",
                "F814W",
                10,
                "CIRCLE ICRS 10.03 0.0 0.035",
            ),
        ]
        options = MODULE.SelectionOptions(
            max_products=3,
            target_coverage=0.50,
            minimum_filters=2,
            grid_dimension=40,
        )
        grid = MODULE.make_coverage_grid(10, 0, 0.05, options.grid_dimension)
        result = MODULE.greedy_select_products([rows], grid, options)

        self.assertEqual(result["selected_products"][0]["obs_id"], "small-blue")
        self.assertEqual(
            {value["obs_id"] for value in result["selected_products"]},
            {"small-blue", "red-offset"},
        )
        self.assertEqual(result["selected_filters"], ["F435W", "F814W"])
        self.assertEqual(result["stop_reason"], "target_satisfied")
        self.assertEqual(result["summary"]["selected_product_count"], 2)
        self.assertEqual(result["summary"]["eligible_candidate_count"], 3)
        self.assertEqual(result["summary"]["selected_filter_count"], 2)
        self.assertEqual(result["summary"]["selected_size_bytes"], 15 * MODULE.MIB)
        self.assertEqual(result["summary"]["selected_size_mib"], 15.0)
        self.assertAlmostEqual(
            result["summary"]["coverage_percentage"],
            result["covered_fraction"] * 100,
            places=6,
        )
        self.assertEqual(result["complexity_metrics"]["full_candidate_rescans"], 0)
        self.assertGreater(result["complexity_metrics"]["candidate_score_updates"], 0)

    def test_rejects_incomplete_and_oversized_candidates(self) -> None:
        rows = [
            product("valid", "F200W", 10),
            product("missing-size", "F356W", None),
            product("missing-region", "F444W", 10, ""),
            product("pseudo-filter", "DETECTION", 10),
            product("too-large", "F090W", 80),
        ]
        options = MODULE.SelectionOptions()
        grid = MODULE.make_coverage_grid(10, 0, 0.05, options.grid_dimension)
        branches = MODULE.prepare_candidate_branches([rows], grid, options)
        result = MODULE.HierarchicalIncrementalGreedySelector(branches, grid, options).select()

        self.assertEqual(result["eligible_candidate_count"], 1)
        self.assertEqual(
            set(result["exclusion_reasons"]),
            {
                "missing_file_size",
                "missing_footprint",
                "missing_filter",
                "exceeds_product_size_limit",
            },
        )

    def test_reports_when_no_candidate_is_eligible(self) -> None:
        rows = [product("missing-size", "F356W", None)]
        options = MODULE.SelectionOptions()
        grid = MODULE.make_coverage_grid(10, 0, 0.05, options.grid_dimension)
        result = MODULE.HierarchicalIncrementalGreedySelector(
            MODULE.prepare_candidate_branches([rows], grid, options),
            grid,
            options,
        ).select()

        self.assertEqual(result["selected_products"], [])
        self.assertEqual(result["stop_reason"], "no_eligible_candidates")

    def test_selected_products_remain_grouped_by_observation(self) -> None:
        rows = [
            product(
                "hst_10775_62_wfc3_f435w",
                "F435W",
                5,
                mission="HST",
                instrument="WFC3/UVIS",
            ),
            product(
                "hst_10775_62_wfc3_f814w",
                "F814W",
                5,
                mission="HST",
                instrument="WFC3/UVIS",
            ),
        ]
        options = MODULE.SelectionOptions(max_products=2, minimum_filters=2)
        grid = MODULE.make_coverage_grid(10, 0, 0.05, options.grid_dimension)
        result = MODULE.HierarchicalIncrementalGreedySelector(
            MODULE.prepare_candidate_branches([rows], grid, options),
            grid,
            options,
        ).select()

        self.assertEqual(len(result["observation_groups"]), 1)
        self.assertEqual(
            result["observation_groups"][0]["observation_key"],
            "hst_10775_62_wfc3",
        )

    def test_filter_novelty_is_scoped_to_each_observation_group(self) -> None:
        rows = [
            product("jw00001-o001_t001_nircam_f435w_a", "F435W", 5),
            product("jw00001-o001_t001_nircam_f435w_b", "F435W", 6),
            product("jw00001-o002_t001_nircam_f435w", "F435W", 5),
        ]
        options = MODULE.SelectionOptions(
            max_products=2,
            target_coverage=1,
            minimum_filters=2,
            coverage_weight=0,
            filter_weight=1,
            size_penalty_exponent=0,
        )
        grid = MODULE.make_coverage_grid(10, 0, 0.05, options.grid_dimension)
        result = MODULE.greedy_select_products([rows], grid, options)

        self.assertEqual(result["filter_novelty_scope"], "observation_group")
        self.assertEqual(result["summary"]["selected_product_count"], 2)
        self.assertEqual(result["summary"]["selected_observation_group_count"], 2)
        self.assertEqual(result["summary"]["selected_group_filter_count"], 2)
        self.assertEqual(result["selected_filters"], ["F435W"])
        self.assertEqual([step["new_filter_count"] for step in result["steps"]], [1, 1])
        self.assertEqual(
            {product["observation_key"] for product in result["selected_products"]},
            {"jw00001-o001_t001_nircam", "jw00001-o002_t001_nircam"},
        )

    def test_swiftmast_cache_path_and_existing_fits_are_reused(self) -> None:
        selected = product(
            "hst_12345_01_wfc3_f606w",
            "F606W;CLEAR2L",
            1,
            mission="HLA",
            instrument="WFC3/UVIS",
        )
        payload = b"SIMPLE  " + b"0" * 8
        selected["contentlength"] = len(payload)

        class NoNetworkSession:
            def get(self, *args: object, **kwargs: object) -> object:
                raise AssertionError("cache hit must not perform a network request")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fits_path, sidecar_path = MODULE.swiftmast_cache_paths(
                root, "NGC 628", selected
            )
            fits_path.parent.mkdir(parents=True)
            fits_path.write_bytes(payload)

            report = MODULE.download_selected_product(
                NoNetworkSession(),
                selected,
                target_name="NGC 628",
                cache_root=root,
                timeout=10,
            )

            self.assertEqual(report["status"], "cached")
            self.assertIn("NGC_628/HST/hst_12345_01_wfc3_f606w", fits_path.as_posix())
            self.assertIn("F606W-CLEAR2L/fit", fits_path.as_posix())
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            self.assertEqual(sidecar["dataURL"], selected["datauri"])
            self.assertEqual(sidecar["obs_collection"], "HLA")
            self.assertEqual(sidecar["dataURLSizeBytes"], len(payload))

    def test_selected_fits_download_is_atomic_and_uses_mast_product_uri(self) -> None:
        selected = product("jw-product", "F200W", 1)
        payload = b"SIMPLE  " + b"1" * 8
        selected["contentlength"] = len(payload)

        class Response:
            status_code = 200

            def raise_for_status(self) -> None:
                return None

            def iter_content(self, chunk_size: int) -> list[bytes]:
                self.chunk_size = chunk_size
                return [payload[:9], payload[9:]]

            def close(self) -> None:
                return None

        class Session:
            def __init__(self) -> None:
                self.calls: list[tuple[object, object]] = []

            def get(self, url: str, **kwargs: object) -> Response:
                self.calls.append((url, kwargs.get("params")))
                return Response()

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            session = Session()
            report = MODULE.download_selected_product(
                session,
                selected,
                target_name="Test target",
                cache_root=root,
                timeout=10,
            )

            fits_path = Path(report["local_fits_path"])
            self.assertEqual(report["status"], "downloaded")
            self.assertEqual(fits_path.read_bytes(), payload)
            self.assertFalse(fits_path.with_suffix(".fits.part").exists())
            self.assertEqual(session.calls[0][0], MODULE.MAST_DOWNLOAD_URL)
            self.assertEqual(
                session.calls[0][1], {"uri": selected["datauri"]}
            )


if __name__ == "__main__":
    unittest.main()
