#!/usr/bin/env python3
"""Select MAST science products with an explicit multi-filter coverage graph.

Unlike the original global-coverage greedy selector, this implementation gives
every ``(mission, instrument, filter)`` node its own coverage state.  Covering a
sky cell in one filter therefore does not reduce the value of covering the same
cell in another filter.  Filter-to-filter edges report the resulting
multi-frequency overlap.

Graph responsibilities:

* the root node owns the final image, product-count, and byte-budget objectives;
* mission subgraphs divide the fetched JWST, HST, HLA, or other collections;
* filter nodes independently pursue their maximum target coverage;
* observation nodes preserve the grouping needed to build AOSImageStack values;
* product nodes hold downloadable science-product metadata;
* target/mission and mission/filter edges carry hierarchy and completion state;
* filter/filter edges carry selected-footprint overlap.

The script runs one TAP branch per requested mission/collection, divides each
returned branch into instrument-scoped filter nodes locally, and then performs
a max-min traversal.  The least-complete filter node is visited first; within
that node, the product adding the most uncovered area per byte is selected.
Products shared by multiple filter nodes are paid for once and update every
connected node.

The emitted report preserves ``selection.selected_products``,
``selection.observation_groups``, ``selection.steps``, and the existing summary
fields so the footprint renderer and other current consumers can read either
selector's output.
"""

from __future__ import annotations

import argparse
import heapq
import json
import logging
import math
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
if str(SCRIPT_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIRECTORY))

import greedy_mast_tap_selection as common


LOGGER = logging.getLogger("swiftmast.graph_greedy_mast_tap")


@dataclass(frozen=True, order=True)
class FilterNodeKey:
    """Stable identity for one independent spectral-coverage objective."""

    mission: str
    instrument: str
    filter_name: str

    @property
    def node_id(self) -> str:
        return f"{self.mission}|{self.instrument}|{self.filter_name}"

    def as_dict(self) -> dict[str, str]:
        return {
            "id": self.node_id,
            "mission": self.mission,
            "instrument": self.instrument,
            "filter": self.filter_name,
        }


@dataclass
class GraphProduct:
    """One unique science product connected to one or more filter nodes."""

    identity: str
    product: dict[str, Any]
    mission: str
    instrument: str
    observation_key: str
    filters: frozenset[str]
    covered_cells: frozenset[int]
    file_size_bytes: int
    node_ids: set[str] = field(default_factory=set)

    @property
    def group_id(self) -> tuple[str, str, str]:
        return self.mission, self.instrument, self.observation_key


@dataclass
class FilterCoverageNode:
    """Mutable traversal state belonging to exactly one filter objective."""

    key: FilterNodeKey
    candidate_ids: set[str] = field(default_factory=set)
    selected_product_ids: list[str] = field(default_factory=list)
    covered_cells: set[int] = field(default_factory=set)
    maximum_cells: set[int] = field(default_factory=set)
    candidates_by_cell: dict[int, set[str]] = field(
        default_factory=lambda: defaultdict(set)
    )
    marginal_cell_counts: dict[str, int] = field(default_factory=dict)
    candidate_versions: dict[str, int] = field(default_factory=dict)
    candidate_heap: list[tuple[Any, ...]] = field(default_factory=list)
    version: int = 0
    query: dict[str, Any] = field(default_factory=dict)


@dataclass
class MissionQueryResult:
    """Rows and diagnostics returned by one adaptive mission query."""

    mission: str
    rows: list[dict[str, Any]]
    info: list[dict[str, Any]]
    attempts: list[dict[str, Any]]
    adql: list[str]
    error: str | None = None


def product_identity(product: dict[str, Any]) -> str:
    """Return the same stable identity used by the existing selector."""

    data_uri = str(product.get("datauri") or "").strip()
    return data_uri or "\x1f".join(
        str(product.get(key) or "")
        for key in ("obs_collection", "obs_id", "instrument_name", "filters")
    )


def build_mission_query(
    *,
    mission: str,
    ra: float,
    dec: float,
    radius: float,
    requested_filters: list[str],
    calibration_levels: list[int],
    product_types: list[str],
    limit: int,
    eligibility_filter_location: str,
    max_product_bytes: int,
    tap_order: str,
) -> str:
    """Build one complete science-product query for a mission subgraph."""

    return common.build_science_product_query(
        ra=ra,
        dec=dec,
        radius=radius,
        missions=[mission],
        filters=requested_filters,
        limit=limit,
        calibration_levels=calibration_levels,
        product_types=product_types,
        eligibility_filter_location=eligibility_filter_location,
        max_product_bytes=max_product_bytes,
        tap_order=tap_order,
    )


def split_rows_by_filter_node(
    rows: list[dict[str, Any]],
    requested_filters: list[str] | None = None,
) -> dict[FilterNodeKey, list[dict[str, Any]]]:
    """Divide mission rows into local instrument/filter graph nodes.

    One product may be connected to multiple nodes when its CAOM filter field
    contains multiple real filters.  This does not duplicate the download: the
    graph de-duplicates products by URI and charges their size once.
    """

    requested = {value.upper() for value in (requested_filters or [])}
    node_rows: dict[FilterNodeKey, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        mission = str(row.get("obs_collection") or "").strip().upper()
        instrument = str(row.get("instrument_name") or "").strip().upper()
        if not mission or not instrument:
            continue
        for filter_name in common.filter_keys(row.get("filters")):
            if requested and not any(
                value == filter_name or value in filter_name
                for value in requested
            ):
                continue
            node_rows[FilterNodeKey(mission, instrument, filter_name)].append(row)
    return dict(sorted(node_rows.items()))


def mission_filter_coverage(
    rows: list[dict[str, Any]],
    grid: common.CoverageGrid,
    options: common.SelectionOptions,
) -> dict[str, float]:
    """Estimate maximum coverage of locally constructed filter nodes."""

    coverage: dict[str, float] = {}
    for key, filter_rows in split_rows_by_filter_node(rows).items():
        branch = common.prepare_mission_branch(
            key.mission, filter_rows, grid, options
        )
        cells: set[int] = set()
        for candidate in branch.candidates:
            cells.update(candidate.covered_cells)
        coverage[key.node_id] = grid.fraction_for_count(len(cells))
    return coverage


def query_one_mission(
    mission: str,
    *,
    ra: float,
    dec: float,
    radius: float,
    calibration_levels: list[int],
    product_types: list[str],
    requested_filters: list[str],
    initial_limit: int,
    maximum_limit: int,
    growth_factor: float,
    eligibility_filter_location: str,
    max_product_bytes: int,
    tap_order: str,
    grid: common.CoverageGrid,
    options: common.SelectionOptions,
    timeout: float,
    retries: int,
    show_query: bool,
) -> MissionQueryResult:
    """Run one mission query and optionally expand its shared candidate pool."""

    current_limit = initial_limit
    attempts: list[dict[str, Any]] = []
    queries: list[str] = []
    latest_rows: list[dict[str, Any]] = []
    latest_info: list[dict[str, Any]] = []
    while True:
        query = build_mission_query(
            mission=mission,
            ra=ra,
            dec=dec,
            radius=radius,
            calibration_levels=calibration_levels,
            product_types=product_types,
            requested_filters=requested_filters,
            limit=current_limit,
            eligibility_filter_location=eligibility_filter_location,
            max_product_bytes=max_product_bytes,
            tap_order=tap_order,
        )
        queries.append(query)
        if show_query:
            LOGGER.info("Mission ADQL mission=%s limit=%s\n%s", mission, current_limit, query)
        started = time.monotonic()
        response = common.query_tap(query, timeout=timeout, retries=retries)
        elapsed = time.monotonic() - started
        latest_rows = common.named_rows(response)
        latest_info = list(response.get("info") or [])
        filter_coverage = mission_filter_coverage(latest_rows, grid, options)
        hit_limit = len(latest_rows) >= current_limit
        attempts.append(
            {
                "limit": current_limit,
                "returned_row_count": len(latest_rows),
                "filter_node_count": len(filter_coverage),
                "filter_maximum_coverage": filter_coverage,
                "hit_limit": hit_limit,
                "elapsed_seconds": round(elapsed, 6),
            }
        )
        LOGGER.info(
            "Mission query finished mission=%s rows=%s filter_nodes=%s "
            "limit=%s hit_limit=%s elapsed_seconds=%.3f",
            mission,
            len(latest_rows),
            len(filter_coverage),
            current_limit,
            hit_limit,
            elapsed,
        )
        if (
            not hit_limit
            or current_limit >= maximum_limit
        ):
            break
        next_limit = min(
            maximum_limit,
            max(current_limit + 1, int(math.ceil(current_limit * growth_factor))),
        )
        if next_limit == current_limit:
            break
        current_limit = next_limit
        LOGGER.info(
            "Mission result reached TOP; expanding shared query mission=%s next_limit=%s",
            mission,
            current_limit,
        )
    return MissionQueryResult(
        mission=mission,
        rows=latest_rows,
        info=latest_info,
        attempts=attempts,
        adql=queries,
    )


def query_missions(
    missions: list[str],
    *,
    workers: int,
    require_all: bool,
    query_arguments: dict[str, Any],
) -> list[MissionQueryResult]:
    """Execute one independent TAP branch per mission with bounded parallelism."""

    if not missions:
        return []
    results: dict[str, MissionQueryResult] = {}
    with ThreadPoolExecutor(max_workers=min(workers, len(missions))) as executor:
        future_missions = {
            executor.submit(query_one_mission, mission, **query_arguments): mission
            for mission in missions
        }
        for future in as_completed(future_missions):
            mission = future_missions[future]
            try:
                result = future.result()
            except Exception as error:  # keep other independent graph branches
                if require_all:
                    raise RuntimeError(
                        f"mission query failed for {mission}: {error}"
                    ) from error
                LOGGER.error("Mission query failed mission=%s error=%s", mission, error)
                result = MissionQueryResult(
                    mission=mission,
                    rows=[],
                    info=[],
                    attempts=[],
                    adql=[],
                    error=str(error),
                )
            results[mission] = result
    return [results[mission] for mission in missions]


class FilterCoverageGraph:
    """Explicit filter/observation/product graph with max-min traversal."""

    def __init__(
        self,
        node_rows: dict[FilterNodeKey, list[dict[str, Any]]],
        grid: common.CoverageGrid,
        options: common.SelectionOptions,
        query_information: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        self.grid = grid
        self.options = options
        self.nodes: dict[str, FilterCoverageNode] = {}
        self.products: dict[str, GraphProduct] = {}
        self.observation_products: dict[tuple[str, str, str], set[str]] = defaultdict(set)
        self.selected_product_ids: list[str] = []
        self.selected_product_set: set[str] = set()
        self.blocked_product_ids: set[str] = set()
        self.exclusions: list[dict[str, Any]] = []
        self.root_heap: list[tuple[Any, ...]] = []
        # Rows are copied onto every matching filter node, so count unique
        # source products rather than graph memberships.
        self.fetched_count = len(
            {
                product_identity(row)
                for rows in node_rows.values()
                for row in rows
            }
        )
        self.metrics = {
            "filter_node_visits": 0,
            "root_heap_pops": 0,
            "candidate_heap_pops": 0,
            "coverage_edge_visits": 0,
            "candidate_score_updates": 0,
            "full_candidate_rescans": 0,
        }

        query_information = query_information or {}
        for key, rows in sorted(node_rows.items()):
            node = FilterCoverageNode(
                key=key,
                query=dict(query_information.get(key.node_id) or {}),
            )
            self.nodes[key.node_id] = node
            branch = common.prepare_mission_branch(key.mission, rows, grid, options)
            for exclusion in branch.exclusions:
                tagged = dict(exclusion)
                tagged["filter_node_id"] = key.node_id
                self.exclusions.append(tagged)
            for candidate in branch.candidates:
                if (
                    candidate.instrument != key.instrument
                    or key.filter_name not in candidate.filters
                ):
                    continue
                graph_product = self.products.get(candidate.identity)
                if graph_product is None:
                    graph_product = GraphProduct(
                        identity=candidate.identity,
                        product=dict(candidate.product),
                        mission=candidate.mission,
                        instrument=candidate.instrument,
                        observation_key=candidate.observation_key,
                        filters=candidate.filters,
                        covered_cells=candidate.covered_cells,
                        file_size_bytes=candidate.file_size_bytes,
                    )
                    self.products[candidate.identity] = graph_product
                    self.observation_products[graph_product.group_id].add(
                        candidate.identity
                    )
                graph_product.node_ids.add(key.node_id)
                node.candidate_ids.add(candidate.identity)

        for node in self.nodes.values():
            self._initialise_node(node)
        LOGGER.info(
            "Filter graph initialized filter_nodes=%s products=%s observations=%s edges=%s",
            len(self.nodes),
            len(self.products),
            len(self.observation_products),
            sum(len(product.node_ids) for product in self.products.values()),
        )

    def _candidate_score(self, cell_gain: int, size_bytes: int) -> float:
        if cell_gain <= 0:
            return 0.0
        gain_fraction = self.grid.fraction_for_count(cell_gain)
        size_mib = max(size_bytes / common.MIB, 0.001)
        size_cost = max(
            size_mib**self.options.size_penalty_exponent, 0.000001
        )
        return self.options.coverage_weight * gain_fraction / size_cost

    def _candidate_entry(
        self, node: FilterCoverageNode, identity: str
    ) -> tuple[Any, ...]:
        product = self.products[identity]
        gain = node.marginal_cell_counts[identity]
        return (
            -self._candidate_score(gain, product.file_size_bytes),
            -gain,
            product.file_size_bytes,
            identity,
            node.candidate_versions[identity],
        )

    def _initialise_node(self, node: FilterCoverageNode) -> None:
        for identity in sorted(node.candidate_ids):
            product = self.products[identity]
            node.maximum_cells.update(product.covered_cells)
            node.marginal_cell_counts[identity] = len(product.covered_cells)
            node.candidate_versions[identity] = 0
            for cell in product.covered_cells:
                node.candidates_by_cell[cell].add(identity)
            heapq.heappush(node.candidate_heap, self._candidate_entry(node, identity))

    def _best_candidate(
        self, node: FilterCoverageNode
    ) -> tuple[GraphProduct, float] | None:
        while node.candidate_heap:
            entry = node.candidate_heap[0]
            identity = entry[3]
            version = entry[4]
            if (
                identity in self.selected_product_set
                or identity in self.blocked_product_ids
                or node.candidate_versions.get(identity) != version
            ):
                heapq.heappop(node.candidate_heap)
                self.metrics["candidate_heap_pops"] += 1
                continue
            product = self.products[identity]
            score = self._candidate_score(
                node.marginal_cell_counts.get(identity, 0),
                product.file_size_bytes,
            )
            if score <= 0:
                heapq.heappop(node.candidate_heap)
                self.metrics["candidate_heap_pops"] += 1
                continue
            if entry[:3] != (-score, -node.marginal_cell_counts[identity], product.file_size_bytes):
                heapq.heappop(node.candidate_heap)
                self.metrics["candidate_heap_pops"] += 1
                heapq.heappush(node.candidate_heap, self._candidate_entry(node, identity))
                continue
            return product, score
        return None

    def _coverage_fraction(self, node: FilterCoverageNode) -> float:
        return self.grid.fraction_for_count(len(node.covered_cells))

    def _maximum_fraction(self, node: FilterCoverageNode) -> float:
        return self.grid.fraction_for_count(len(node.maximum_cells))

    def _completion_ratio(self, node: FilterCoverageNode) -> float:
        reachable_objective = min(
            self.options.target_coverage, self._maximum_fraction(node)
        )
        if reachable_objective <= 0:
            return 1.0
        return min(self._coverage_fraction(node) / reachable_objective, 1.0)

    def _publish_node(self, node: FilterCoverageNode) -> None:
        node.version += 1
        if self._coverage_fraction(node) >= self.options.target_coverage:
            return
        best = self._best_candidate(node)
        if best is None:
            return
        product, score = best
        heapq.heappush(
            self.root_heap,
            (
                self._completion_ratio(node),
                -score,
                node.key.node_id,
                product.identity,
                node.version,
            ),
        )

    def _pop_traversal_candidate(
        self,
    ) -> tuple[FilterCoverageNode, GraphProduct, float] | None:
        while self.root_heap:
            entry = heapq.heappop(self.root_heap)
            self.metrics["root_heap_pops"] += 1
            node = self.nodes[entry[2]]
            if node.version != entry[4]:
                continue
            best = self._best_candidate(node)
            if best is None:
                continue
            product, score = best
            if product.identity != entry[3] or not math.isclose(score, -entry[1]):
                self._publish_node(node)
                continue
            self.metrics["filter_node_visits"] += 1
            return node, product, score
        return None

    def _update_node_coverage(
        self, node: FilterCoverageNode, product: GraphProduct
    ) -> set[int]:
        new_cells = set(product.covered_cells) - node.covered_cells
        if product.identity not in node.selected_product_ids:
            node.selected_product_ids.append(product.identity)
        node.covered_cells.update(new_cells)
        affected: set[str] = set()
        for cell in new_cells:
            identities = node.candidates_by_cell.get(cell, set())
            self.metrics["coverage_edge_visits"] += len(identities)
            for identity in identities:
                if identity in self.selected_product_set or identity in self.blocked_product_ids:
                    continue
                node.marginal_cell_counts[identity] = max(
                    node.marginal_cell_counts[identity] - 1, 0
                )
                affected.add(identity)
        for identity in affected:
            node.candidate_versions[identity] += 1
            self.metrics["candidate_score_updates"] += 1
            heapq.heappush(node.candidate_heap, self._candidate_entry(node, identity))
        return new_cells

    def _coverage_depth(self) -> Counter[int]:
        depth: Counter[int] = Counter()
        for node in self.nodes.values():
            for cell in node.covered_cells:
                depth[cell] += 1
        return depth

    def _multi_filter_coverage(self) -> dict[str, Any]:
        depth = self._coverage_depth()
        node_count = len(self.nodes)
        quorum = min(self.options.minimum_filters, node_count) if node_count else 0

        def fraction_at_least(value: int) -> float:
            if value <= 0:
                return 0.0
            return self.grid.fraction_for_count(
                sum(1 for cell_depth in depth.values() if cell_depth >= value)
            )

        histogram = Counter(depth.values())
        return {
            "filter_node_count": node_count,
            "union_coverage_fraction": fraction_at_least(1),
            "union_coverage_percentage": round(fraction_at_least(1) * 100, 6),
            "at_least_two_filters_fraction": fraction_at_least(2),
            "at_least_two_filters_percentage": round(fraction_at_least(2) * 100, 6),
            "minimum_filter_quorum": quorum,
            "minimum_filter_quorum_fraction": fraction_at_least(quorum),
            "minimum_filter_quorum_percentage": round(
                fraction_at_least(quorum) * 100, 6
            ),
            "all_filter_coverage_fraction": fraction_at_least(node_count),
            "all_filter_coverage_percentage": round(
                fraction_at_least(node_count) * 100, 6
            ),
            "coverage_depth_cell_counts": {
                str(depth_value): count
                for depth_value, count in sorted(histogram.items())
            },
        }

    def _node_status(self, node: FilterCoverageNode, stop_reason: str) -> str:
        coverage = self._coverage_fraction(node)
        if node.query.get("error"):
            return "query_failed"
        if not node.candidate_ids:
            return "unavailable"
        if coverage >= self.options.target_coverage:
            return "complete"
        if any(identity in self.blocked_product_ids for identity in node.candidate_ids):
            return "budget_blocked"
        if stop_reason == "maximum_products_reached" and self._best_candidate(node):
            return "selection_limit_reached"
        if node.query.get("hit_limit"):
            return "needs_larger_query"
        return "partial_exhausted"

    def _filter_results(self, stop_reason: str) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for node in self.nodes.values():
            coverage = self._coverage_fraction(node)
            maximum = self._maximum_fraction(node)
            status = self._node_status(node, stop_reason)
            results.append(
                {
                    **node.key.as_dict(),
                    "status": status,
                    "complete": status == "complete",
                    "target_coverage_fraction": self.options.target_coverage,
                    "coverage_fraction": coverage,
                    "coverage_percentage": round(coverage * 100, 6),
                    "maximum_available_coverage_fraction": maximum,
                    "maximum_available_coverage_percentage": round(maximum * 100, 6),
                    "completion_ratio": self._completion_ratio(node),
                    "candidate_count": len(node.candidate_ids),
                    "selected_product_count": len(node.selected_product_ids),
                    "selected_product_ids": list(node.selected_product_ids),
                    "query": node.query,
                }
            )
        return results

    def _filter_overlap_edges(self) -> list[dict[str, Any]]:
        node_values = list(self.nodes.values())
        edges: list[dict[str, Any]] = []
        for left_index, left in enumerate(node_values):
            for right in node_values[left_index + 1 :]:
                intersection = left.covered_cells & right.covered_cells
                union = left.covered_cells | right.covered_cells
                overlap = self.grid.fraction_for_count(len(intersection))
                edges.append(
                    {
                        "source": left.key.node_id,
                        "target": right.key.node_id,
                        "type": "multi_filter_overlap",
                        "overlap_cell_count": len(intersection),
                        "overlap_fraction_of_target": overlap,
                        "overlap_percentage_of_target": round(overlap * 100, 6),
                        "jaccard": len(intersection) / len(union) if union else 0.0,
                        "target_met": overlap >= self.options.target_coverage,
                    }
                )
        return edges

    def _graph_report(
        self, filter_results: list[dict[str, Any]], total_size: int
    ) -> dict[str, Any]:
        filter_results_by_mission: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for result in filter_results:
            filter_results_by_mission[result["mission"]].append(result)
        mission_nodes = []
        target_mission_edges = []
        mission_filter_edges = []
        for mission, mission_filters in sorted(filter_results_by_mission.items()):
            mission_id = f"mission:{mission}"
            mission_products = [
                product
                for product in self.products.values()
                if product.mission == mission
            ]
            mission_nodes.append(
                {
                    "id": mission_id,
                    "mission": mission,
                    "type": "mission_subgraph",
                    "filter_node_count": len(mission_filters),
                    "candidate_product_count": len(mission_products),
                    "selected_product_count": sum(
                        product.identity in self.selected_product_set
                        for product in mission_products
                    ),
                    "complete_filter_node_count": sum(
                        result["complete"] for result in mission_filters
                    ),
                }
            )
            target_mission_edges.append(
                {
                    "source": "target",
                    "target": mission_id,
                    "type": "contains_mission_graph",
                }
            )
            for result in mission_filters:
                mission_filter_edges.append(
                    {
                        "source": mission_id,
                        "target": result["id"],
                        "type": "contains_filter_objective",
                        "target_coverage_fraction": result[
                            "target_coverage_fraction"
                        ],
                        "achieved_coverage_fraction": result["coverage_fraction"],
                        "status": result["status"],
                    }
                )
        target_filter_edges = [
            {
                "source": "target",
                "target": result["id"],
                "type": "requires_filter_coverage",
                "target_coverage_fraction": result["target_coverage_fraction"],
                "achieved_coverage_fraction": result["coverage_fraction"],
                "maximum_available_coverage_fraction": result[
                    "maximum_available_coverage_fraction"
                ],
                "status": result["status"],
            }
            for result in filter_results
        ]
        observation_nodes = []
        filter_observation_edges = []
        observation_product_edges = []
        for group_id, identities in sorted(self.observation_products.items()):
            mission, instrument, observation_key = group_id
            observation_id = f"{mission}|{instrument}|{observation_key}"
            selected_count = sum(
                identity in self.selected_product_set for identity in identities
            )
            observation_nodes.append(
                {
                    "id": observation_id,
                    "mission": mission,
                    "instrument": instrument,
                    "observation_key": observation_key,
                    "candidate_product_count": len(identities),
                    "selected_product_count": selected_count,
                }
            )
            linked_node_ids: set[str] = set()
            for identity in sorted(identities):
                product = self.products[identity]
                linked_node_ids.update(product.node_ids)
                observation_product_edges.append(
                    {
                        "source": observation_id,
                        "target": identity,
                        "type": "contains_product",
                        "selected": identity in self.selected_product_set,
                    }
                )
            for node_id in sorted(linked_node_ids):
                filter_observation_edges.append(
                    {
                        "source": node_id,
                        "target": observation_id,
                        "type": "has_observation_candidate",
                    }
                )
        product_nodes = [
            {
                "id": product.identity,
                "mission": product.mission,
                "instrument": product.instrument,
                "observation_key": product.observation_key,
                "filters": sorted(product.filters),
                "file_size_bytes": product.file_size_bytes,
                "covered_cell_count": len(product.covered_cells),
                "selected": product.identity in self.selected_product_set,
                "filter_node_ids": sorted(product.node_ids),
            }
            for product in self.products.values()
        ]
        return {
            "root": {
                "id": "target",
                "type": "final_multi_filter_image",
                "target_coverage_fraction": self.options.target_coverage,
                "max_products": self.options.max_products,
                "max_total_size_bytes": self.options.max_total_bytes,
                "selected_product_count": len(self.selected_product_ids),
                "selected_size_bytes": total_size,
            },
            "mission_nodes": mission_nodes,
            "filter_nodes": filter_results,
            "observation_nodes": observation_nodes,
            "product_nodes": product_nodes,
            "edges": {
                "target_mission": target_mission_edges,
                "mission_filter": mission_filter_edges,
                "target_filter": target_filter_edges,
                "filter_overlap": self._filter_overlap_edges(),
                "filter_observation": filter_observation_edges,
                "observation_product": observation_product_edges,
            },
            "edge_responsibilities": {
                "target_mission": "Divides the target into independently fetched mission subgraphs.",
                "mission_filter": "Connects locally constructed filter objectives to their mission query.",
                "target_filter": "Backward-compatible shortcut to each filter completion state.",
                "filter_overlap": "Measures co-spatial multi-frequency coverage between filters.",
                "filter_observation": "Connects a filter objective to candidate observation groups.",
                "observation_product": "Connects an AOSImageStack observation group to its science products.",
            },
        }

    def select(self) -> dict[str, Any]:
        """Traverse least-complete filter nodes and select coverage per byte."""

        started = time.monotonic()
        for node in self.nodes.values():
            self._publish_node(node)
        total_size = 0
        budget_skipped = 0
        steps: list[dict[str, Any]] = []
        selected_filter_names: set[str] = set()
        stop_reason = "no_eligible_candidates" if not self.products else "no_additional_benefit"

        while len(self.selected_product_ids) < self.options.max_products:
            if self.nodes and all(
                self._coverage_fraction(node) >= self.options.target_coverage
                for node in self.nodes.values()
            ):
                stop_reason = "target_satisfied"
                break
            traversal = self._pop_traversal_candidate()
            if traversal is None:
                stop_reason = (
                    "budget_exhausted"
                    if budget_skipped
                    else "no_additional_benefit"
                )
                break
            selected_from_node, product, score = traversal
            if (
                self.options.max_total_bytes is not None
                and total_size + product.file_size_bytes > self.options.max_total_bytes
            ):
                self.blocked_product_ids.add(product.identity)
                budget_skipped += 1
                for node_id in product.node_ids:
                    self._publish_node(self.nodes[node_id])
                continue

            before_depth = self._coverage_depth()
            self.selected_product_ids.append(product.identity)
            self.selected_product_set.add(product.identity)
            total_size += product.file_size_bytes
            per_node_gain: dict[str, float] = {}
            affected_nodes: set[str] = set(product.node_ids)
            for node_id in product.node_ids:
                node = self.nodes[node_id]
                new_cells = self._update_node_coverage(node, product)
                per_node_gain[node_id] = self.grid.fraction_for_count(len(new_cells))
            for node_id in affected_nodes:
                self._publish_node(self.nodes[node_id])
            after_depth = self._coverage_depth()
            new_multifilter_cells = sum(
                1
                for cell, depth in after_depth.items()
                if depth >= 2 and before_depth.get(cell, 0) < 2
            )
            new_filter_names = set(product.filters) - selected_filter_names
            selected_filter_names.update(product.filters)
            union_cells = sum(1 for depth in after_depth.values() if depth >= 1)
            steps.append(
                {
                    "iteration": len(steps) + 1,
                    "selected_from_filter_node": selected_from_node.key.node_id,
                    "mission": product.mission,
                    "instrument": product.instrument,
                    "observation_key": product.observation_key,
                    "observation_id": product.product.get("obs_id"),
                    "filters": sorted(product.filters),
                    "file_size_bytes": product.file_size_bytes,
                    "new_coverage_fraction": per_node_gain.get(
                        selected_from_node.key.node_id, 0.0
                    ),
                    "per_filter_new_coverage_fraction": per_node_gain,
                    "new_multi_filter_coverage_fraction": self.grid.fraction_for_count(
                        new_multifilter_cells
                    ),
                    "new_filter_count": len(new_filter_names),
                    "score": score,
                    "cumulative_coverage_fraction": self.grid.fraction_for_count(
                        union_cells
                    ),
                    "cumulative_filters": sorted(selected_filter_names),
                    "cumulative_size_bytes": total_size,
                }
            )
            LOGGER.info(
                "Graph selection step iteration=%s node=%s observation_id=%r "
                "node_gain=%.6f multi_filter_gain=%.6f file_mib=%.2f cumulative_mib=%.2f",
                len(steps),
                selected_from_node.key.node_id,
                product.product.get("obs_id"),
                per_node_gain.get(selected_from_node.key.node_id, 0.0),
                self.grid.fraction_for_count(new_multifilter_cells),
                product.file_size_bytes / common.MIB,
                total_size / common.MIB,
            )

        if len(self.selected_product_ids) >= self.options.max_products:
            stop_reason = (
                "target_satisfied"
                if self.nodes
                and all(
                    self._coverage_fraction(node) >= self.options.target_coverage
                    for node in self.nodes.values()
                )
                else "maximum_products_reached"
            )

        selected_products: list[dict[str, Any]] = []
        for rank, identity in enumerate(self.selected_product_ids, start=1):
            product = self.products[identity]
            value = dict(product.product)
            value["selection_rank"] = rank
            value["observation_key"] = product.observation_key
            selected_products.append(value)
        observation_groups = common.group_selected_products(selected_products)
        multi_filter = self._multi_filter_coverage()
        filter_results = self._filter_results(stop_reason)
        union_coverage = multi_filter["union_coverage_fraction"]
        group_filter_count = sum(
            len(group.get("filters") or []) for group in observation_groups
        )
        summary = {
            "coverage_fraction": union_coverage,
            "coverage_percentage": round(union_coverage * 100, 6),
            "selected_size_bytes": total_size,
            "selected_size_mib": round(total_size / common.MIB, 6),
            "selected_filter_count": len(selected_filter_names),
            "selected_filter_node_count": sum(
                bool(node.selected_product_ids) for node in self.nodes.values()
            ),
            "selected_group_filter_count": group_filter_count,
            "selected_product_count": len(selected_products),
            "eligible_candidate_count": len(self.products),
            "observation_group_count": len(self.observation_products),
            "selected_observation_group_count": len(observation_groups),
            "multi_filter_coverage_percentage": multi_filter[
                "at_least_two_filters_percentage"
            ],
            "all_filter_coverage_percentage": multi_filter[
                "all_filter_coverage_percentage"
            ],
        }
        branch_counts = Counter(product.mission for product in self.products.values())
        result = {
            "algorithm": "filter_graph_max_min_greedy",
            "filter_novelty_scope": "independent_filter_node",
            "summary": summary,
            "candidate_count": self.fetched_count,
            "eligible_candidate_count": len(self.products),
            "observation_group_count": len(self.observation_products),
            "branch_candidate_counts": dict(sorted(branch_counts.items())),
            "excluded_candidates": self.exclusions,
            "exclusion_reasons": dict(
                sorted(Counter(value["reason"] for value in self.exclusions).items())
            ),
            "steps": steps,
            "selected_products": selected_products,
            "observation_groups": observation_groups,
            "covered_fraction": union_coverage,
            "selected_filters": sorted(selected_filter_names),
            "total_selected_size_bytes": total_size,
            "budget_skipped_candidates": budget_skipped,
            "stop_reason": stop_reason,
            "complexity_metrics": self.metrics,
            "multi_filter_coverage": multi_filter,
            "filter_results": filter_results,
            "graph": self._graph_report(filter_results, total_size),
        }
        LOGGER.info(
            "Graph selection finished products=%s filter_nodes=%s observations=%s "
            "union_coverage=%.6f multi_filter_coverage=%.6f total_mib=%.2f "
            "stop_reason=%s elapsed_seconds=%.3f",
            len(selected_products),
            len(self.nodes),
            len(observation_groups),
            union_coverage,
            multi_filter["at_least_two_filters_fraction"],
            total_size / common.MIB,
            stop_reason,
            time.monotonic() - started,
        )
        return result


def graph_select_products(
    node_rows: dict[FilterNodeKey, list[dict[str, Any]]],
    grid: common.CoverageGrid,
    options: common.SelectionOptions,
    query_information: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Named review entry point for graph construction and traversal."""

    return FilterCoverageGraph(
        node_rows, grid, options, query_information
    ).select()


def build_argument_parser() -> argparse.ArgumentParser:
    """Extend the original CLI with mission-branch query controls."""

    parser = common.build_argument_parser()
    parser.description = (
        "Query MAST once per mission, construct filter nodes locally, and "
        "select multi-frequency science products with an explicit graph."
    )
    parser.set_defaults(select_products=True)
    for action in parser._actions:
        if action.dest == "balanced_missions":
            action.help = (
                "No effect in this script: every mission is already an independent branch."
            )
        elif action.dest == "select_products":
            action.help = "Selection is always enabled in this graph-specific script."
        elif action.dest == "filter_weight":
            action.help = (
                "Retained for CLI compatibility; filter separation is represented by nodes."
            )
    parser.add_argument(
        "--mission-limit",
        type=int,
        help="Initial TOP value for each mission query (default: --limit).",
    )
    parser.add_argument(
        "--max-mission-limit",
        type=int,
        help=(
            "Maximum adaptive TOP value when a mission result reaches its limit. "
            "Defaults to --mission-limit, which disables automatic expansion."
        ),
    )
    parser.add_argument(
        "--mission-limit-growth",
        type=float,
        default=2.0,
        help="Multiplier used when expanding a truncated mission query (default: 2).",
    )
    return parser


def parse_args() -> argparse.Namespace:
    return build_argument_parser().parse_args()


def validate_args(args: argparse.Namespace) -> None:
    """Validate graph and inherited selection arguments before network calls."""

    if args.radius is not None and args.radius <= 0:
        raise ValueError("--radius must be greater than zero")
    if args.limit <= 0 or (args.mission_limit is not None and args.mission_limit <= 0):
        raise ValueError("query limits must be greater than zero")
    if args.max_mission_limit is not None and args.max_mission_limit <= 0:
        raise ValueError("--max-mission-limit must be greater than zero")
    if args.mission_limit_growth <= 1:
        raise ValueError("--mission-limit-growth must be greater than one")
    if args.workers <= 0:
        raise ValueError("--workers must be greater than zero")
    if args.max_products <= 0 or args.max_mb <= 0:
        raise ValueError("selection product limits must be greater than zero")
    if args.max_total_mb is not None and args.max_total_mb <= 0:
        raise ValueError("--max-total-mb must be greater than zero")
    if not 0 <= args.target_coverage <= 1:
        raise ValueError("--target-coverage must be in [0, 1]")
    if args.minimum_filters < 0:
        raise ValueError("--minimum-filters cannot be negative")
    if args.coverage_weight <= 0:
        raise ValueError("--coverage-weight must be greater than zero")
    if args.size_penalty_exponent < 0:
        raise ValueError("--size-penalty-exponent cannot be negative")
    if args.grid_dimension <= 0:
        raise ValueError("--grid-dimension must be greater than zero")
    if args.columns:
        raise ValueError("graph selection requires the default application columns")


def parse_calibration_levels(raw: str) -> list[int]:
    try:
        values = [int(value.strip()) for value in raw.split(",") if value.strip()]
    except ValueError as error:
        raise ValueError("--calib-levels must contain comma-separated integers") from error
    if not values:
        raise ValueError("--calib-levels requires at least one value")
    return values


def deduplicated_rows(results: list[MissionQueryResult]) -> list[dict[str, Any]]:
    """Combine mission-query rows without repeating shared products."""

    rows: dict[str, dict[str, Any]] = {}
    for result in results:
        for row in result.rows:
            rows.setdefault(product_identity(row), row)
    return list(rows.values())


def write_result(args: argparse.Namespace, result: dict[str, Any]) -> None:
    rendered = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        LOGGER.info("Graph report written path=%s rows=%s", args.output, result["row_count"])
    else:
        sys.stdout.write(rendered)


def main() -> int:
    """Resolve target, instantiate/query filter nodes, traverse, and report."""

    args = parse_args()
    validate_args(args)
    common.configure_logging(args.log_level, args.log_file)
    started = time.monotonic()
    LOGGER.info(
        "Graph MAST workflow started target=%r missions=%s mission_limit=%s "
        "max_mission_limit=%s workers=%s download_selected=%s",
        args.target,
        args.missions,
        args.mission_limit or args.limit,
        args.max_mission_limit or args.mission_limit or args.limit,
        args.workers,
        args.download_selected,
    )

    if args.schema:
        query = common.build_schema_query()
        if args.show_query:
            LOGGER.info("Schema ADQL\n%s", query)
        response = common.query_tap(query, timeout=args.timeout, retries=args.retries)
        rows = common.named_rows(response)
        result = {
            "target": None,
            "position": None,
            "row_count": len(rows),
            "columns": [column.get("name") for column in response.get("info") or []],
            "column_availability": common.column_availability(rows),
            "missions": [],
            "adql": query,
            "query_errors": {},
            "query_strategy": {"algorithm": "schema"},
            "rows": rows,
        }
        write_result(args, result)
        return 0

    if (args.ra is None) != (args.dec is None):
        raise ValueError("provide both --ra and --dec")
    if args.ra is None:
        if not args.target:
            raise ValueError("provide --target or both --ra and --dec")
        ra, dec, resolved_radius = common.resolve_target(
            args.target, timeout=args.timeout, retries=args.retries
        )
    else:
        ra, dec = args.ra, args.dec
        resolved_radius = None
        if args.radius is None:
            if not args.target:
                raise ValueError(
                    "provide --radius with coordinates, or also provide --target "
                    "so its radius can be resolved"
                )
            _, _, resolved_radius = common.resolve_target(
                args.target, timeout=args.timeout, retries=args.retries
            )
    if not 0 <= ra < 360 or not -90 <= dec <= 90:
        raise ValueError("coordinates are outside the ICRS degree ranges")
    effective_radius = args.radius if args.radius is not None else resolved_radius
    if effective_radius is None or effective_radius <= 0:
        raise ValueError("a positive search radius is required")

    missions = common.parse_csv_values(args.missions)
    requested_filters = (
        common.parse_csv_values(args.filters) if args.filters.strip() else []
    )
    calibration_levels = parse_calibration_levels(args.calib_levels)
    product_types = common.parse_csv_values(args.product_types)
    initial_mission_limit = args.mission_limit or args.limit
    maximum_mission_limit = args.max_mission_limit or initial_mission_limit
    if maximum_mission_limit < initial_mission_limit:
        raise ValueError(
            "--max-mission-limit cannot be smaller than --mission-limit"
        )

    options = common.SelectionOptions(
        max_products=args.max_products,
        max_product_bytes=int(args.max_mb * common.MIB),
        max_total_bytes=(
            int(args.max_total_mb * common.MIB)
            if args.max_total_mb is not None
            else None
        ),
        target_coverage=args.target_coverage,
        minimum_filters=args.minimum_filters,
        coverage_weight=args.coverage_weight,
        filter_weight=args.filter_weight,
        size_penalty_exponent=args.size_penalty_exponent,
        grid_dimension=args.grid_dimension,
    )
    position = {"ra": ra, "dec": dec, "radius_degrees": effective_radius}
    grid = common.make_coverage_grid(ra, dec, effective_radius, args.grid_dimension)

    query_results = query_missions(
        missions,
        workers=args.workers,
        require_all=args.require_all_missions,
        query_arguments={
            "ra": ra,
            "dec": dec,
            "radius": effective_radius,
            "calibration_levels": calibration_levels,
            "product_types": product_types,
            "requested_filters": requested_filters,
            "initial_limit": initial_mission_limit,
            "maximum_limit": maximum_mission_limit,
            "growth_factor": args.mission_limit_growth,
            "eligibility_filter_location": args.eligibility_filter_location,
            "max_product_bytes": options.max_product_bytes,
            "tap_order": args.tap_order,
            "grid": grid,
            "options": options,
            "timeout": args.timeout,
            "retries": args.retries,
            "show_query": args.show_query,
        },
    )
    node_rows: dict[FilterNodeKey, list[dict[str, Any]]] = defaultdict(list)
    query_information: dict[str, dict[str, Any]] = {}
    for result in query_results:
        mission_nodes = split_rows_by_filter_node(
            result.rows, requested_filters=requested_filters
        )
        last_attempt = result.attempts[-1] if result.attempts else {}
        for key, filter_rows in mission_nodes.items():
            node_rows[key].extend(filter_rows)
            query_information[key.node_id] = {
                "source_mission": result.mission,
                "shared_mission_query": True,
                "attempts": result.attempts,
                "attempt_count": len(result.attempts),
                "final_limit": last_attempt.get("limit"),
                "mission_returned_row_count": last_attempt.get(
                    "returned_row_count", 0
                ),
                "hit_limit": last_attempt.get("hit_limit", False),
                "error": result.error,
            }
    node_rows = dict(sorted(node_rows.items()))
    filter_keys = list(node_rows)
    LOGGER.info(
        "Mission results divided into graph nodes missions=%s filter_nodes=%s products=%s",
        len(query_results),
        len(filter_keys),
        len(deduplicated_rows(query_results)),
    )

    selection = graph_select_products(
        node_rows, grid, options, query_information=query_information
    )
    selection["target"] = args.target
    selection["position"] = position
    selection["target_area_square_degrees"] = grid.target_area_square_degrees
    selection["mission_query_results"] = [
        {
            "mission": result.mission,
            "attempts": result.attempts,
            "attempt_count": len(result.attempts),
            "error": result.error,
        }
        for result in query_results
    ]
    if args.download_selected:
        cache_target = common.string_value(args.cache_target_name or args.target).strip()
        if not cache_target:
            cache_target = f"ra-{ra:.6f}_dec-{dec:.6f}"
        selection["downloads"] = common.download_selected_products(
            selection["selected_products"],
            target_name=cache_target,
            cache_root=args.cache_root,
            timeout=args.timeout,
            retries=args.retries,
        )

    rows = deduplicated_rows(query_results)
    first_info = next((result.info for result in query_results if result.info), [])
    all_queries: list[str] = []
    for result in query_results:
        all_queries.extend(result.adql)
    query_errors = {
        result.mission: result.error
        for result in query_results
        if result.error is not None
    }
    result = {
        "target": args.target,
        "position": position,
        "row_count": len(rows),
        "columns": [column.get("name") for column in first_info],
        "column_availability": common.column_availability(rows),
        "missions": common.mission_summary(rows),
        "adql": all_queries,
        "query_errors": query_errors,
        "query_strategy": {
            "algorithm": "filter_graph_max_min_greedy",
            "tap_query_scope": "mission",
            "mission_query_count": sum(
                len(result.attempts) for result in query_results
            ),
            "mission_branches": [
                {
                    "mission": result.mission,
                    "attempt_count": len(result.attempts),
                    "returned_row_count": len(result.rows),
                    "error": result.error,
                }
                for result in query_results
            ],
            "filter_node_count": len(filter_keys),
            "filter_nodes": [key.as_dict() for key in filter_keys],
            "eligibility_filter_location": args.eligibility_filter_location,
            "tap_order": args.tap_order,
            "initial_mission_limit": initial_mission_limit,
            "maximum_mission_limit": maximum_mission_limit,
            "mission_limit_growth": args.mission_limit_growth,
            "max_product_size_bytes": options.max_product_bytes,
        },
        "rows": rows,
        "selection": selection,
    }
    write_result(args, result)
    LOGGER.info(
        "Graph MAST workflow finished rows=%s selected_products=%s elapsed_seconds=%.3f",
        len(rows),
        len(selection["selected_products"]),
        time.monotonic() - started,
    )
    if args.download_selected:
        return 1 if selection["downloads"]["failed_product_count"] else 0
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
