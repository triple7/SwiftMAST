from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).parents[2]
COMMON_SCRIPT = ROOT / "Sources" / "scripts" / "greedy_mast_tap_selection.py"
GRAPH_SCRIPT = ROOT / "Sources" / "scripts" / "graph_greedy_mast_tap_selection.py"


def load_module(name: str, path: Path):
    existing = sys.modules.get(name)
    if existing is not None:
        return existing
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


COMMON = load_module("greedy_mast_tap_selection", COMMON_SCRIPT)
GRAPH = load_module("graph_greedy_mast_tap_selection", GRAPH_SCRIPT)


def product(
    observation_id: str,
    filter_name: str,
    size_mib: int,
    region: str = "CIRCLE ICRS 10.0 0.0 0.035",
    *,
    mission: str = "JWST",
    instrument: str = "NIRCAM/IMAGE",
) -> dict[str, object]:
    return {
        "obsid": observation_id,
        "obs_id": observation_id,
        "obs_collection": mission,
        "instrument_name": instrument,
        "target_name": "Test target",
        "filters": filter_name,
        "calib_level": 3,
        "dataproduct_type": "IMAGE",
        "datarights": "PUBLIC",
        "s_ra": 10.0,
        "s_dec": 0.0,
        "s_region": region,
        "datauri": f"mast:TEST/product/{observation_id}.fits",
        "previewuri": "",
        "productfilename": f"{observation_id}.fits",
        "contenttype": "application/fits",
        "contentlength": size_mib * COMMON.MIB,
    }


class FilterCoverageGraphTests(unittest.TestCase):
    def setUp(self) -> None:
        self.grid = COMMON.make_coverage_grid(10, 0, 0.05, 40)

    def key(self, filter_name: str) -> object:
        return GRAPH.FilterNodeKey("JWST", "NIRCAM/IMAGE", filter_name)

    def test_mission_query_fetches_filters_together_without_instrument_query(self) -> None:
        query = GRAPH.build_mission_query(
            mission="JWST",
            ra=10,
            dec=0,
            radius=0.05,
            requested_filters=["F200W", "F300M"],
            calibration_levels=[3, 4],
            product_types=["IMAGE"],
            limit=50,
            eligibility_filter_location="tap",
            max_product_bytes=70 * COMMON.MIB,
            tap_order="group",
        )

        self.assertIn("o.obs_collection IN ('JWST')", query)
        self.assertIn("UPPER(o.filters) LIKE '%F200W%'", query)
        self.assertIn("UPPER(o.filters) LIKE '%F300M%'", query)
        self.assertNotIn("UPPER(o.instrument_name) IN", query)

    def test_mission_rows_are_divided_into_filter_nodes_locally(self) -> None:
        rows = [
            product("blue", "F200W", 5),
            product("red", "F300M", 5),
            product("shared", "F200W;F300M", 5),
        ]

        node_rows = GRAPH.split_rows_by_filter_node(rows)

        self.assertEqual(set(node_rows), {self.key("F200W"), self.key("F300M")})
        self.assertEqual(len(node_rows[self.key("F200W")]), 2)
        self.assertEqual(len(node_rows[self.key("F300M")]), 2)

    def test_same_sky_in_different_filters_is_selected_and_counted_as_overlap(self) -> None:
        rows = {
            self.key("F200W"): [product("blue", "F200W", 5)],
            self.key("F300M"): [product("red", "F300M", 5)],
        }
        options = COMMON.SelectionOptions(
            max_products=4,
            target_coverage=0.30,
            minimum_filters=2,
            grid_dimension=40,
        )
        result = GRAPH.graph_select_products(rows, self.grid, options)

        self.assertEqual(
            {value["obs_id"] for value in result["selected_products"]},
            {"blue", "red"},
        )
        self.assertEqual(result["stop_reason"], "target_satisfied")
        self.assertTrue(all(node["complete"] for node in result["filter_results"]))
        self.assertAlmostEqual(
            result["multi_filter_coverage"]["union_coverage_fraction"],
            result["multi_filter_coverage"]["at_least_two_filters_fraction"],
        )
        overlap_edges = result["graph"]["edges"]["filter_overlap"]
        self.assertEqual(len(overlap_edges), 1)
        self.assertTrue(overlap_edges[0]["target_met"])

    def test_one_multifilter_product_updates_two_nodes_but_is_paid_for_once(self) -> None:
        shared = product("shared", "F200W;F300M", 7)
        rows = {
            self.key("F200W"): [shared],
            self.key("F300M"): [shared],
        }
        options = COMMON.SelectionOptions(
            max_products=4,
            target_coverage=0.30,
            minimum_filters=2,
            grid_dimension=40,
        )
        result = GRAPH.graph_select_products(rows, self.grid, options)

        self.assertEqual(result["summary"]["selected_product_count"], 1)
        self.assertEqual(result["summary"]["selected_size_bytes"], 7 * COMMON.MIB)
        self.assertEqual(
            [node["selected_product_count"] for node in result["filter_results"]],
            [1, 1],
        )

    def test_budget_blocked_filter_is_reported_without_losing_its_candidate(self) -> None:
        rows = {
            self.key("F200W"): [product("blue", "F200W", 8)],
            self.key("F300M"): [product("red", "F300M", 8)],
        }
        options = COMMON.SelectionOptions(
            max_products=4,
            max_total_bytes=8 * COMMON.MIB,
            target_coverage=0.30,
            minimum_filters=2,
            grid_dimension=40,
        )
        result = GRAPH.graph_select_products(rows, self.grid, options)

        self.assertEqual(result["summary"]["selected_product_count"], 1)
        self.assertEqual(result["budget_skipped_candidates"], 1)
        self.assertIn(
            "budget_blocked",
            {node["status"] for node in result["filter_results"]},
        )
        self.assertEqual(result["eligible_candidate_count"], 2)

    def test_redundant_product_is_deprioritized_inside_one_filter_node(self) -> None:
        rows = {
            self.key("F200W"): [
                product("large", "F200W", 20),
                product("small", "F200W", 5),
            ]
        }
        options = COMMON.SelectionOptions(
            max_products=2,
            target_coverage=0.30,
            grid_dimension=40,
        )
        result = GRAPH.graph_select_products(rows, self.grid, options)

        self.assertEqual(
            [value["obs_id"] for value in result["selected_products"]],
            ["small"],
        )

    def test_truncated_mission_can_expand_its_shared_tap_limit(self) -> None:
        first = product(
            "one", "F200W", 1, "CIRCLE ICRS 9.98 0.0 0.008"
        )
        second = product(
            "two", "F200W", 1, "CIRCLE ICRS 10.02 0.0 0.008"
        )
        responses = [
            {"rows": [first], "info": []},
            {"rows": [first, second], "info": []},
        ]
        options = COMMON.SelectionOptions(
            target_coverage=0.80,
            max_product_bytes=70 * COMMON.MIB,
            grid_dimension=40,
        )

        with patch.object(GRAPH.common, "query_tap", side_effect=responses):
            with patch.object(
                GRAPH.common, "named_rows", side_effect=lambda response: response["rows"]
            ):
                result = GRAPH.query_one_mission(
                    "JWST",
                    ra=10,
                    dec=0,
                    radius=0.05,
                    calibration_levels=[3, 4],
                    product_types=["IMAGE"],
                    requested_filters=[],
                    initial_limit=1,
                    maximum_limit=2,
                    growth_factor=2,
                    eligibility_filter_location="tap",
                    max_product_bytes=70 * COMMON.MIB,
                    tap_order="group",
                    grid=self.grid,
                    options=options,
                    timeout=10,
                    retries=0,
                    show_query=False,
                )

        self.assertEqual([attempt["limit"] for attempt in result.attempts], [1, 2])
        self.assertEqual(len(result.rows), 2)
        self.assertIn("SELECT TOP 2", result.adql[-1])

    def test_query_orchestration_calls_tap_once_per_mission(self) -> None:
        def fake_query(mission: str, **_: object) -> object:
            return GRAPH.MissionQueryResult(
                mission=mission,
                rows=[],
                info=[],
                attempts=[{"limit": 10, "returned_row_count": 0}],
                adql=[f"query for {mission}"],
            )

        with patch.object(GRAPH, "query_one_mission", side_effect=fake_query) as query:
            results = GRAPH.query_missions(
                ["JWST", "HLA"],
                workers=2,
                require_all=True,
                query_arguments={},
            )

        self.assertEqual(query.call_count, 2)
        self.assertEqual([result.mission for result in results], ["JWST", "HLA"])

    def test_report_keeps_existing_selection_contract(self) -> None:
        result = GRAPH.graph_select_products(
            {self.key("F200W"): [product("one", "F200W", 5)]},
            self.grid,
            COMMON.SelectionOptions(target_coverage=0.30, grid_dimension=40),
        )

        for key in (
            "summary",
            "steps",
            "selected_products",
            "observation_groups",
            "selected_filters",
            "covered_fraction",
            "total_selected_size_bytes",
        ):
            self.assertIn(key, result)
        self.assertEqual(result["algorithm"], "filter_graph_max_min_greedy")
        self.assertEqual(result["filter_novelty_scope"], "independent_filter_node")
        self.assertEqual(len(result["graph"]["mission_nodes"]), 1)
        self.assertEqual(
            result["graph"]["edges"]["target_mission"][0]["target"],
            "mission:JWST",
        )


if __name__ == "__main__":
    unittest.main()
