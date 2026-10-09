from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PHASE2_PATH = ROOT / "research" / "process-graphs" / "scripts" / "phase2.py"


def load_phase2():
    spec = importlib.util.spec_from_file_location("process_graph_phase2_tests", PHASE2_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {PHASE2_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


PHASE2 = load_phase2()


def product(filter_name: str, suffix: int) -> dict[str, object]:
    offset = suffix * 0.002
    return {
        "obs_id": f"example_{filter_name.lower()}",
        "datauri": f"mast:example/{filter_name.lower()}",
        "obs_collection": "HST",
        "instrument_name": "ACS/WFC",
        "filters": filter_name,
        "contentlength": 1_048_576,
        "contentlength_bytes": 1_048_576,
        "em_min": float(filter_name[1:4]) - 5,
        "em_max": float(filter_name[1:4]) + 5,
        "observation_group_id": "HST:ACS/WFC:example",
        "observation_group": "example",
        "s_region": (
            "POLYGON ICRS "
            f"{9.99 + offset} {19.99 + offset} "
            f"{10.01 + offset} {19.99 + offset} "
            f"{10.01 + offset} {20.01 + offset} "
            f"{9.99 + offset} {20.01 + offset}"
        ),
    }


class ProcessGraphPipelineTests(unittest.TestCase):
    def test_balanced_additive_primaries_reach_white(self) -> None:
        self.assertEqual(
            PHASE2.additive_mix(["#FF0000", "#00FF00", "#0000FF"]),
            (1.0, 1.0, 1.0),
        )
        self.assertEqual(
            PHASE2.additive_mix(["#00FF00"]),
            (0.0, 1.0, 0.0),
        )

    def test_texture_base_is_observation_stable_and_filter_variation_is_unique(self) -> None:
        common = {
            "obs_id": "shared-observation",
            "observation_group_id": "shared-stack",
        }
        first = PHASE2.PreparedProduct(
            identity="first",
            group_id="shared-stack",
            group_name="shared-stack",
            filters=frozenset({"F435W"}),
            bytes=1,
            shapes=(),
            cells=frozenset(),
            row={**common, "filters": "F435W"},
        )
        second = PHASE2.PreparedProduct(
            identity="second",
            group_id="shared-stack",
            group_name="shared-stack",
            filters=frozenset({"F814W"}),
            bytes=1,
            shapes=(),
            cells=frozenset(),
            row={**common, "filters": "F814W"},
        )

        first_observation, first_filter = PHASE2.texture_keys(first)
        second_observation, second_filter = PHASE2.texture_keys(second)
        self.assertEqual(first_observation, second_observation)
        self.assertNotEqual(first_filter, second_filter)
        self.assertEqual(PHASE2.texture_keys(first), PHASE2.texture_keys(first))

    def test_group_rank_selects_and_renders_without_pixels(self) -> None:
        phase1 = {
            "schema_version": 1,
            "artifact": "mast-composite-phase-1-qualified",
            "configuration": {
                "target": "Synthetic target",
                "ra": 10.0,
                "dec": 20.0,
                "radius_degrees": 0.05,
                "missions": ["HST"],
            },
            "qualified_rows": [
                product("F435W", 0),
                product("F555W", 1),
                product("F814W", 2),
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "phase-1-qualified.json"
            output_dir = root / "output"
            input_path.write_text(json.dumps(phase1), encoding="utf-8")

            result = PHASE2.main(
                [
                    "--input",
                    str(input_path),
                    "--algorithm",
                    "02-greedy-group-rank",
                    "--max-total-mib",
                    "10",
                    "--max-products",
                    "10",
                    "--grid-dimension",
                    "12",
                    "--texture-density",
                    "2",
                    "--dpi",
                    "50",
                    "--output-dir",
                    str(output_dir),
                    "--log-level",
                    "WARNING",
                ]
            )

            self.assertEqual(result, 0)
            selection_path = output_dir / "phase-2-02-greedy-group-rank-selection.json"
            image_path = output_dir / "phase-2-02-greedy-group-rank-footprints.png"
            report = json.loads(selection_path.read_text(encoding="utf-8"))
            self.assertEqual(report["summary"]["selected_product_count"], 3)
            self.assertEqual(report["summary"]["selected_filter_count"], 3)
            self.assertEqual(report["summary"]["selected_size_bytes"], 3_145_728)
            self.assertGreater(report["summary"]["coverage_percentage"], 0)
            self.assertTrue(image_path.is_file())
            self.assertGreater(image_path.stat().st_size, 0)

    def test_all_documented_phase2_algorithms_are_runnable(self) -> None:
        expected = {f"{index:02d}" for index in range(1, 11)}
        actual = {name.split("-", 1)[0] for name in PHASE2.SELECTORS}
        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
