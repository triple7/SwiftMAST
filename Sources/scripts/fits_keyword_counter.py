#!/usr/bin/env python3
"""
FITS Header Keyword Counter
============================
Queries the MAST (Mikulski Archive for Space Telescopes) API,
downloads FITS files for a list of astronomical targets, extracts
all header keywords from every HDU, and accumulates their counts
in a JSON file (headers_counter.json).

The final output is sorted by descending frequency so the most
common keywords appear first.

Usage:
    python3 fits_keyword_counter.py
"""

import sys
import os
import json
import time
from collections import Counter
from dataclasses import dataclass, field
from urllib.parse import quote as urlencode

import requests
from astropy.io import fits


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MAST_API_URL = "https://mast.stsci.edu/api/v0/invoke"
MAST_DOWNLOAD_URL = "https://mast.stsci.edu/api/v0.1/Download/file?"

# Paths are relative to the repo root; the script resolves them from its own location
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(os.path.dirname(_SCRIPT_DIR))

COUNTER_FILE = os.path.join(_REPO_ROOT, "Resources", "results", "headers_counter.json")
DOWNLOAD_DIR = os.path.join(_REPO_ROOT, "Resources", "fits")

# Maximum total FITS files to analyse across all targets in one run.
# The traversal is round-robin: one file per target per round, so every
# target is sampled before any target gets a second file.
MAX_FILES = 4

# Number of observation rows to request per MAST page
PAGESIZE = 50

# File extensions considered valid FITS files (including gzipped)
FITS_EXTENSIONS = (".fits", ".fits.gz")

# Number of retries when the MAST server returns a transient DB error
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 5

# Targets to query – add or remove entries as needed
TARGETS = [
    # Well-known stars / objects
    "Polaris",
    "Sirius",
    "Vega",
    "Betelgeuse",
    "M31",
    "M101",
    "Aldebaran",
    "Rigel",
    "Proxima Centauri",
    "Barnard's Star",
]


# ---------------------------------------------------------------------------
# MAST API helpers
# ---------------------------------------------------------------------------

def mast_query(request: dict) -> tuple[dict, str]:
    """
    POST a JSON request to the MAST API and return (response_headers, body_text).

    Retries up to MAX_RETRIES times on transient server errors.
    """
    version = ".".join(map(str, sys.version_info[:3]))
    http_headers = {
        "Content-type": "application/x-www-form-urlencoded",
        "Accept": "text/plain",
        "User-agent": f"python-requests/{version}",
    }
    req_string = urlencode(json.dumps(request))

    for attempt in range(1, MAX_RETRIES + 1):
        resp = requests.post(MAST_API_URL, data="request=" + req_string, headers=http_headers)
        resp.raise_for_status()
        body = resp.content.decode("utf-8")
        result = json.loads(body)
        if result.get("status") == "ERROR":
            msg = result.get("msg", "")
            if attempt < MAX_RETRIES:
                print(f"    [retry {attempt}/{MAX_RETRIES}] Server error: {msg[:80]}")
                time.sleep(RETRY_DELAY_SECONDS * attempt)
                continue
        return resp.headers, body

    return resp.headers, body  # return last attempt regardless


def resolve_target(object_name: str) -> dict | None:
    """
    Use Mast.Name.Lookup to resolve *object_name* to sky coordinates.

    Returns dict with 'ra' and 'dec' on success, None if unresolvable.
    """
    request = {
        "service": "Mast.Name.Lookup",
        "params": {"input": object_name, "format": "json"},
    }
    _, body = mast_query(request)
    data = json.loads(body)

    coords_list = data.get("resolvedCoordinate")
    if not coords_list:
        return None

    coord = coords_list[0]
    return {"ra": coord["ra"], "dec": coord["decl"]}


def search_by_target_name(name: str, page: int = 1, pagesize: int = PAGESIZE) -> list[dict]:
    """
    Search MAST observations using a freeText target_name filter via
    Mast.Caom.Filtered. This avoids range/spatial queries that can hit
    server-side database contention issues.

    Parameters
    ----------
    name     : target name to search for (wrapped in SQL wildcards).
    page     : 1-based page number for paginated results.
    pagesize : number of rows per page.

    Returns a list of observation row dicts, or [] when the page is empty or
    on error.
    """
    request = {
        "service": "Mast.Caom.Filtered",
        "format": "json",
        "pagesize": pagesize,
        "page": page,
        "params": {
            "columns": "*",
            "filters": [
                {
                    "paramName": "target_name",
                    "values": [],
                    "freeText": f"%{name}%",
                }
            ],
        },
    }
    _, body = mast_query(request)
    result = json.loads(body)

    if result.get("status") != "COMPLETE":
        return []
    return result.get("data", [])


def filter_fits_observations(observations: list[dict]) -> list[dict]:
    """
    Keep only observations whose dataURL ends with a known FITS extension.
    """
    return [
        obs for obs in observations
        if str(obs.get("dataURL") or "").lower().endswith(FITS_EXTENSIONS)
    ]


def get_science_products(obsid: int | str) -> list[dict]:
    """
    Fetch science FITS products for a given MAST obsid via Mast.Caom.Products.

    Returns a list of product dicts that have a FITS dataURI.
    """
    request = {
        "service": "Mast.Caom.Products",
        "params": {"obsid": obsid},
        "format": "json",
        "pagesize": 50,
        "page": 1,
    }
    _, body = mast_query(request)
    result = json.loads(body)

    if result.get("status") != "COMPLETE":
        return []

    return [
        p for p in result.get("data", [])
        if p.get("productType") == "SCIENCE"
        and str(p.get("dataURI", "")).lower().endswith(FITS_EXTENSIONS)
    ]


def _is_mast_uri(uri: str) -> bool:
    """Return True if *uri* is a MAST-internal URI (starts with 'mast:')."""
    return uri.lower().startswith("mast:")


def download_file(url_or_uri: str, out_path: str) -> bool:
    """
    Download a file given either:
      - An external HTTP URL (GALEX/Spitzer/etc.) – downloaded directly.
      - A MAST-internal URI (mast:...) – routed through the MAST download endpoint.

    Returns True on success.
    """
    if _is_mast_uri(url_or_uri):
        resp = requests.get(MAST_DOWNLOAD_URL, params={"uri": url_or_uri}, timeout=120)
    else:
        resp = requests.get(url_or_uri, timeout=120)
    resp.raise_for_status()

    with open(out_path, "wb") as fh:
        fh.write(resp.content)
    return True


def download_fits_file(observation: dict) -> str | None:
    """
    Download the FITS file associated with *observation*.

    Strategy:
      1. Use observation['dataURL'] if it ends with a FITS extension.
      2. Otherwise, call get_science_products() and use the first result's dataURI.

    Returns the local file path on success, None on failure.
    """
    out_dir = os.path.join(
        DOWNLOAD_DIR,
        str(observation.get("obs_collection", "unknown")),
        str(observation.get("obs_id", "unknown")),
    )
    os.makedirs(out_dir, exist_ok=True)

    # --- Strategy 1: direct dataURL ---
    direct_url = observation.get("dataURL") or ""
    if direct_url.lower().endswith(FITS_EXTENSIONS):
        filename = os.path.basename(direct_url.split("?")[0]) or "data.fits"
        out_path = os.path.join(out_dir, filename)
        if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
            return out_path
        try:
            download_file(direct_url, out_path)
            return out_path
        except Exception as e:
            print(f"    Direct download failed ({e}), trying products...")

    # --- Strategy 2: Mast.Caom.Products ---
    obsid = observation.get("obsid")
    if obsid:
        products = get_science_products(obsid)
        if products:
            prod = products[0]
            uri = prod.get("dataURI", "")
            filename = prod.get("productFilename") or os.path.basename(uri) or "data.fits"
            out_path = os.path.join(out_dir, os.path.basename(filename))
            if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
                return out_path
            try:
                download_file(uri, out_path)
                return out_path
            except Exception as e:
                print(f"    Products download failed: {e}")

    return None


# ---------------------------------------------------------------------------
# Per-target traversal state
# ---------------------------------------------------------------------------

@dataclass
class TargetState:
    """Tracks pagination and record position for one target across rounds."""
    name: str
    # Next MAST page to fetch (1-based). Incremented after each successful fetch.
    next_page: int = 1
    # FITS-filtered records from the most-recently fetched page.
    page_records: list = field(default_factory=list)
    # Index of the next record to try inside page_records.
    record_index: int = 0
    # Set to True when MAST returns an empty page – no more data for this target.
    exhausted: bool = False
    # Total FITS files successfully analysed for this target.
    files_processed: int = 0


def advance_target(state: TargetState) -> str | None:
    """
    Return the local path of the next analysable FITS file for *state*,
    advancing page_records / fetching the next MAST page as needed.

    - Skips records where the download fails.
    - Fetches successive pages when the current page's records are exhausted.
    - Sets state.exhausted = True and returns None when no more pages remain.
    """
    while not state.exhausted:
        # Try remaining records on the current page.
        while state.record_index < len(state.page_records):
            record = state.page_records[state.record_index]
            state.record_index += 1
            local_path = download_fits_file(record)
            if local_path and os.path.exists(local_path):
                return local_path
            # Download failed; try next record on same page.

        # All records on the current page tried – fetch the next page.
        print(f"    [{state.name}] Fetching MAST page {state.next_page}...")
        raw_records = search_by_target_name(state.name, page=state.next_page)
        state.next_page += 1

        if not raw_records:
            print(f"    [{state.name}] No more pages – target exhausted.")
            state.exhausted = True
            return None

        # Prefer records with a direct FITS URL; fall back to all records so
        # the products-based download strategy can be attempted.
        fits_records = filter_fits_observations(raw_records)
        state.page_records = fits_records if fits_records else raw_records
        state.record_index = 0
        # Loop back to try the newly loaded records.

    return None


# ---------------------------------------------------------------------------
# FITS header extraction
# ---------------------------------------------------------------------------

# FITS structural/annotation card names that carry no keyword semantics.
# Blank cards (empty string) are padding; HISTORY/COMMENT are free-text
# annotations; END marks the header boundary. None of these reflect
# instrument or calibration keywords and would dominate the frequency counts.
_SKIP_KEYWORDS = {"", "HISTORY", "COMMENT", "END"}


def extract_header_keywords(fits_path: str) -> list[str]:
    """
    Open a FITS file at *fits_path* and return all meaningful header keywords
    from every HDU (duplicates included for counting purposes).

    Structural/annotation cards (blank, HISTORY, COMMENT, END) are excluded
    because they are not semantic data keywords.
    """
    keywords: list[str] = []
    with fits.open(fits_path) as hdul:
        for hdu in hdul:
            keywords.extend(
                k for k in hdu.header.keys() if k not in _SKIP_KEYWORDS
            )
    return keywords


# ---------------------------------------------------------------------------
# Counter persistence
# ---------------------------------------------------------------------------

def load_counter(path: str) -> Counter:
    """Load an existing keyword counter from a JSON file, or return empty."""
    if os.path.exists(path):
        with open(path, "r") as fh:
            return Counter(json.load(fh))
    return Counter()


def save_counter(counter: Counter, path: str) -> None:
    """
    Save *counter* to a JSON file sorted by descending count,
    so the most popular keyword is at the top.
    """
    sorted_items = counter.most_common()
    ordered = {k: v for k, v in sorted_items}
    with open(path, "w") as fh:
        json.dump(ordered, fh, indent=4)


# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

def run(targets: list[str], max_files: int = MAX_FILES) -> None:
    """
    Main entry point.

    Analyses up to *max_files* FITS files in round-robin order across all
    *targets*:

      Round 1 : one file from target[0], one from target[1], …
      Round 2 : next untouched file from target[0], next from target[1], …
      …

    Within each target, records are drawn from successive MAST pages so
    pagination is handled transparently.  The keyword counter is saved after
    every successful file so progress survives interruption.
    """
    counter = load_counter(COUNTER_FILE)
    total_processed = 0

    states = [TargetState(name=t) for t in targets]

    print(f"Starting FITS keyword scan — goal: {max_files} file(s) across "
          f"{len(targets)} target(s), round-robin.\n")

    round_num = 1
    while total_processed < max_files:
        active = [s for s in states if not s.exhausted]
        if not active:
            print("All targets exhausted.")
            break

        print(f"--- Round {round_num} ({len(active)} active target(s)) ---")
        progress_this_round = False

        for state in active:
            if total_processed >= max_files:
                break

            print(f"  [{state.name}] Seeking next FITS file "
                  f"(target total so far: {state.files_processed})...")
            local_path = advance_target(state)

            if local_path is None:
                continue  # target exhausted mid-round

            keywords = extract_header_keywords(local_path)
            counter.update(keywords)
            total_processed += 1
            state.files_processed += 1
            save_counter(counter, COUNTER_FILE)
            progress_this_round = True

            print(f"    Extracted {len(keywords)} keyword(s) from "
                  f"'{os.path.basename(local_path)}' "
                  f"[{total_processed}/{max_files} total].")

        if not progress_this_round:
            print("No progress this round – all remaining targets exhausted.")
            break

        round_num += 1

    save_counter(counter, COUNTER_FILE)
    print(f"\nDone — {total_processed} file(s) analysed across "
          f"{sum(1 for s in states if s.files_processed > 0)} target(s).")
    print(f"Counter saved to '{COUNTER_FILE}' ({len(counter)} unique keywords).\n")
    print_top_keywords(counter)


def print_top_keywords(counter: Counter, n: int = 30) -> None:
    """Print the top *n* keywords by frequency."""
    print(f"Top {n} FITS header keywords:")
    print("-" * 40)
    for keyword, count in counter.most_common(n):
        print(f"  {keyword:20s}  {count}")


# ---------------------------------------------------------------------------

if __name__ == "__main__":
    run(TARGETS, 20)
