from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).parents[2] / "Sources" / "scripts"
sys.path.insert(0, str(SCRIPTS))
SCRIPT = SCRIPTS / "plot_mast_science_product_footprints.py"
SPEC = importlib.util.spec_from_file_location("plot_mast_science_product_footprints", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def drawable(
    identity: str,
    filter_names: tuple[str, ...],
    *,
    group: str,
    selected: bool,
) -> object:
    return MODULE.DrawableProduct(
        product={},
        identity=identity,
        mission="HST",
        group_id=("HST", "ACS/WFC", group),
        filters=filter_names,
        shapes=(("CIRCLE", (10.0, 0.0, 0.1)),),
        selected=selected,
    )


class FootprintColorTests(unittest.TestCase):
    def test_distributed_hues_match_aosimage_examples(self) -> None:
        self.assertEqual(MODULE.distributed_hue_degrees(0, 1), 120.0)
        self.assertEqual(
            [MODULE.distributed_hue_degrees(index, 2) for index in range(2)],
            [210.0, 30.0],
        )
        self.assertEqual(
            [MODULE.distributed_hue_degrees(index, 3) for index in range(3)],
            [240.0, 0.0, 120.0],
        )
        self.assertEqual(
            [MODULE.distributed_hue_degrees(index, 6) for index in range(6)],
            [270.0, 330.0, 30.0, 90.0, 150.0, 210.0],
        )

    def test_filter_key_counts_products_and_honors_preferred_hex(self) -> None:
        drawables = [
            drawable("one", ("F435W",), group="a", selected=True),
            drawable("two", ("F435W", "F814W"), group="b", selected=False),
        ]

        entries, lookup = MODULE.build_color_key(
            drawables,
            "filter",
            {"F814W": "#3366CC"},
        )

        self.assertEqual([entry.key for entry in entries], ["F435W", "F814W"])
        self.assertEqual(lookup["F435W"].eligible_product_count, 2)
        self.assertEqual(lookup["F435W"].selected_product_count, 1)
        self.assertEqual(lookup["F814W"].color, "#3366CC")
        self.assertEqual(lookup["F814W"].source, "preferred_hex")

    def test_observation_group_mode_resets_palette_inside_each_group(self) -> None:
        drawables = [
            drawable("one", ("F435W",), group="single", selected=True),
            drawable("two-a", ("F435W",), group="pair", selected=True),
            drawable("two-b", ("F814W",), group="pair", selected=True),
        ]

        plan = MODULE.build_color_plan(drawables, "observation-group", {})

        self.assertEqual(plan.lookup["N1:P1"].hue_degrees, 120.0)
        self.assertEqual(plan.lookup["N1:P1"].color, "#00FF00")
        self.assertEqual(plan.lookup["N2:P1"].hue_degrees, 210.0)
        self.assertEqual(plan.lookup["N2:P2"].hue_degrees, 30.0)
        self.assertEqual(plan.eligible_assignments["one"], ("N1:P1",))
        self.assertEqual(plan.eligible_assignments["two-a"], ("N2:P1",))
        self.assertEqual(plan.eligible_assignments["two-b"], ("N2:P2",))

    def test_selected_panel_recomputes_palette_from_selected_group_members(self) -> None:
        drawables = [
            drawable("selected", ("F435W",), group="pair", selected=True),
            drawable("not-selected", ("F814W",), group="pair", selected=False),
        ]

        plan = MODULE.build_color_plan(drawables, "observation-group", {})

        self.assertEqual(plan.eligible_assignments["selected"], ("N2:P1",))
        self.assertEqual(plan.eligible_assignments["not-selected"], ("N2:P2",))
        self.assertEqual(plan.selected_assignments["selected"], ("N1:P1",))

    def test_filter_is_the_default_color_mode(self) -> None:
        with patch.object(
            sys,
            "argv",
            ["plot_mast_science_product_footprints.py", "report.json"],
        ):
            args = MODULE.parse_args()

        self.assertEqual(args.color_by, "filter")


if __name__ == "__main__":
    unittest.main()
