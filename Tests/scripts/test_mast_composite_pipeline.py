from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "Sources" / "scripts" / "mast_composite_pipeline.py"
SPEC = importlib.util.spec_from_file_location("mast_composite_pipeline", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def drawable(identity: str, group: str, rank: int) -> dict[str, object]:
    return {
        "identity": identity,
        "product": {"selection_rank": rank, "obs_id": identity},
        "mission": "HST",
        "group": group,
        "filters": ("F435W",),
        "shapes": (("CIRCLE", (10.0, 0.0, 0.1)),),
    }


class CompositePipelineRenderTests(unittest.TestCase):
    def test_distributed_colors_match_aosimage_examples(self) -> None:
        self.assertEqual(MODULE.distributed_color(0, 1), (120.0, "#00FF00"))
        self.assertEqual(MODULE.distributed_color(0, 2), (210.0, "#0080FF"))
        self.assertEqual(MODULE.distributed_color(1, 2), (30.0, "#FF8000"))

    def test_observation_group_palette_resets_for_each_stack_size(self) -> None:
        drawables = [
            drawable("single", "group-one", 1),
            drawable("pair-a", "group-two", 2),
            drawable("pair-b", "group-two", 3),
        ]

        assignments, entries = MODULE.render_color_plan(
            drawables,
            "observation-group",
            {},
        )

        self.assertEqual(assignments["single"], ("N1:P1",))
        self.assertEqual(entries["N1:P1"]["color"], "#00FF00")
        self.assertEqual(assignments["pair-a"], ("N2:P1",))
        self.assertEqual(assignments["pair-b"], ("N2:P2",))
        self.assertEqual(entries["N2:P1"]["color"], "#0080FF")
        self.assertEqual(entries["N2:P2"]["color"], "#FF8000")

    def test_render_command_defaults_to_filter_coloring(self) -> None:
        args = MODULE.build_parser().parse_args(
            ["render", "--input", "phase-2-download-manifest.json"]
        )

        self.assertEqual(args.color_by, "filter")
        self.assertEqual(args.label_by, "none")
        self.assertEqual(args.dpi, 180)
        self.assertIs(args.func, MODULE.run_render)


if __name__ == "__main__":
    unittest.main()
