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

# Maximum number of targets to actually process in one run
MAX_TARGETS = 2

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


def search_by_target_name(name: str, pagesize: int = 50) -> list[dict]:
    """
    Search MAST observations using a freeText target_name filter via
    Mast.Caom.Filtered. This avoids range/spatial queries that can hit
    server-side database contention issues.

    Returns a list of observation row dicts.
    """
    request = {
        "service": "Mast.Caom.Filtered",
        "format": "json",
        "pagesize": pagesize,
        "page": 1,
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

def process_target(name: str, counter: Counter) -> bool:
    """
    Search MAST by target name, download the first FITS hit, and update
    *counter* with the extracted header keywords.

    Returns True if the target was successfully processed.
    """
    print(f"  Searching MAST for '{name}'...")
    observations = search_by_target_name(name)
    if not observations:
        print(f"    No observations found for '{name}'.")
        return False

    fits_obs = filter_fits_observations(observations)
    if not fits_obs:
        # Fall back to first observation and try products
        fits_obs = observations[:1]

    print(f"    Found {len(fits_obs)} FITS observation(s). Attempting download...")
    local_path = download_fits_file(fits_obs[0])
    if local_path is None or not os.path.exists(local_path):
        print(f"    Download failed for '{name}'.")
        return False

    keywords = extract_header_keywords(local_path)
    counter.update(keywords)
    print(f"    Extracted {len(keywords)} keyword occurrences from '{os.path.basename(local_path)}'.")
    return True


def run(targets: list[str], max_targets: int = MAX_TARGETS) -> None:
    """
    Main entry point: iterate over *targets*, accumulate FITS header
    keyword counts, and write the sorted result to COUNTER_FILE.
    """
    counter = load_counter(COUNTER_FILE)
    processed = 0

    print(f"Starting FITS keyword scan for up to {max_targets} targets ...\n")

    for name in targets:
        if processed >= max_targets:
            break
        print(f"[{processed + 1}/{min(len(targets), max_targets)}] {name}")
        success = process_target(name, counter)
        if success:
            processed += 1
            # Save incrementally so progress is not lost on interruption
            save_counter(counter, COUNTER_FILE)

    save_counter(counter, COUNTER_FILE)

    print(f"\nDone — processed {processed} target(s).")
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
    run(TARGETS)
