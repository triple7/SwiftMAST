#!/usr/bin/env python3
"""Download an official Phase 2 MAST composite manifest.

``fits`` downloads every selected FITS product. ``adaptive`` range-walks the
remote FITS headers and downloads a smaller preview when both the FITS source
and preview pass the configured image-quality gates, otherwise it falls back
to FITS. Neither mode performs TAP queries or changes Phase 2 selection.

The former command form without a subcommand remains a FITS-only alias::

    download_mast_selection.py --manifest phase-2-download-manifest.json
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import logging
import math
import os
import re
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
BLOCK_SIZE = 2_880
CARD_SIZE = 80
MIB = 1_048_576
GREEDY_PATH = Path(__file__).with_name("greedy_mast_tap_selection.py")
LOGGER = logging.getLogger("swiftmast.selection_downloader")
REQUIRED_FIELDS = (
    "obs_collection",
    "obs_id",
    "filters",
    "datauri",
    "contentlength",
)
WCS_SCALAR_KEYS = (
    "CRPIX1",
    "CRPIX2",
    "CRVAL1",
    "CRVAL2",
)
WCS_REPORT_KEYS = (
    "WCSAXES",
    "EQUINOX",
    "CRPIX1",
    "CRPIX2",
    "CRVAL1",
    "CRVAL2",
    "CTYPE1",
    "CTYPE2",
    "CUNIT1",
    "CUNIT2",
    "CDELT1",
    "CDELT2",
    "PC1_1",
    "PC1_2",
    "PC2_1",
    "PC2_2",
    "CD1_1",
    "CD1_2",
    "CD2_1",
    "CD2_2",
)


def load_greedy():
    spec = importlib.util.spec_from_file_location("swiftmast_greedy_download", GREEDY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {GREEDY_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_pillow():
    """Load the adaptive mode's optional image dependency only when needed."""

    try:
        from PIL import Image, ImageFile, UnidentifiedImageError
    except ImportError as error:  # pragma: no cover - environment dependent
        raise RuntimeError(
            "adaptive mode requires Pillow: python -m pip install Pillow"
        ) from error
    return Image, ImageFile, UnidentifiedImageError


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported manifest schema {manifest.get('schema_version')!r}; "
            f"expected {SCHEMA_VERSION}"
        )
    if manifest.get("artifact") != "mast-composite-download-manifest":
        raise ValueError("input is not a MAST composite download manifest")
    products = manifest.get("selected_products")
    if not isinstance(products, list):
        raise ValueError("manifest selected_products must be an array")
    errors = []
    seen: set[str] = set()
    for index, product in enumerate(products, start=1):
        if not isinstance(product, dict):
            errors.append(f"product {index}: expected object")
            continue
        missing = [field for field in REQUIRED_FIELDS if product.get(field) in (None, "")]
        if missing:
            errors.append(f"product {index}: missing {', '.join(missing)}")
        uri = str(product.get("datauri") or "")
        if uri in seen:
            errors.append(f"product {index}: duplicate datauri {uri}")
        seen.add(uri)
        try:
            if int(float(product.get("contentlength"))) <= 0:
                errors.append(f"product {index}: contentlength must be positive")
        except (TypeError, ValueError, OverflowError):
            errors.append(f"product {index}: contentlength is not numeric")
    if errors:
        raise ValueError("manifest preflight failed:\n- " + "\n- ".join(errors))
    return manifest


def dry_run_report(
    greedy,
    products: list[dict[str, Any]],
    *,
    target_name: str,
    cache_root: Path,
) -> dict[str, Any]:
    entries = []
    for product in products:
        destination, sidecar = greedy.swiftmast_cache_paths(cache_root, target_name, product)
        expected = int(float(product["contentlength"]))
        cached = greedy.is_complete_fits(destination, expected)
        entries.append(
            {
                "selection_rank": product.get("selection_rank"),
                "observation_id": product.get("obs_id"),
                "product_uri": product.get("datauri"),
                "expected_size_bytes": expected,
                "status": "cached" if cached else "would_download",
                "local_fits_path": str(destination),
                "coam_sidecar_path": str(sidecar),
            }
        )
    return {
        "dry_run": True,
        "cache_root": str(cache_root),
        "requested_product_count": len(products),
        "cached_product_count": sum(entry["status"] == "cached" for entry in entries),
        "would_download_product_count": sum(
            entry["status"] == "would_download" for entry in entries
        ),
        "expected_total_bytes": sum(entry["expected_size_bytes"] for entry in entries),
        "expected_transfer_bytes": sum(
            entry["expected_size_bytes"]
            for entry in entries
            if entry["status"] == "would_download"
        ),
        "products": entries,
    }


def padded(value: int) -> int:
    """Round a byte offset up to the next FITS logical block."""

    return int(math.ceil(value / BLOCK_SIZE) * BLOCK_SIZE) if value else 0


def parse_header_value(raw: str) -> Any:
    """Parse the primitive value portion of one FITS card."""

    text = raw.strip()
    if text.startswith("'"):
        end = text.find("'", 1)
        return text[1:end].strip() if end > 0 else text.strip("'").strip()
    value = text.split("/", 1)[0].strip()
    if not value:
        return None
    if value == "T":
        return True
    if value == "F":
        return False
    try:
        if any(marker in value for marker in (".", "E", "e", "D", "d")):
            return float(value.replace("D", "E").replace("d", "e"))
        return int(value)
    except ValueError:
        return value


def parse_header_block(data: bytes) -> tuple[dict[str, Any], int] | None:
    """Parse a complete FITS header and return values plus padded byte size."""

    values: dict[str, Any] = {}
    for offset in range(0, len(data) - CARD_SIZE + 1, CARD_SIZE):
        card = data[offset : offset + CARD_SIZE].decode("ascii", errors="replace")
        keyword = card[:8].strip()
        if keyword == "END":
            return values, padded(offset + CARD_SIZE)
        if keyword and card[8:10] == "= ":
            values[keyword] = parse_header_value(card[10:])
    return None


def fits_data_size(header: dict[str, Any]) -> int:
    """Calculate an HDU payload size from FITS structural header fields."""

    naxis = int(header.get("NAXIS") or 0)
    bitpix = abs(int(header.get("BITPIX") or 0))
    if naxis <= 0 or bitpix <= 0:
        return 0
    elements = 1
    for axis in range(1, naxis + 1):
        length = int(header.get(f"NAXIS{axis}") or 0)
        if length < 0:
            raise ValueError(f"invalid NAXIS{axis}={length}")
        elements *= length
    pcount = int(header.get("PCOUNT") or 0)
    gcount = int(header.get("GCOUNT") or 1)
    return (bitpix // 8) * gcount * (elements + pcount)


def remote_size_from_headers(headers: dict[str, str]) -> int | None:
    """Read total object size from Content-Range or Content-Length."""

    content_range = headers.get("Content-Range", "")
    match = re.search(r"/(\d+)$", content_range)
    if match:
        return int(match.group(1))
    try:
        return int(headers["Content-Length"])
    except (KeyError, TypeError, ValueError):
        return None


def bounded_response_bytes(response, maximum: int) -> bytes:
    """Read at most ``maximum`` bytes before closing a streamed response."""

    output = bytearray()
    for chunk in response.iter_content(chunk_size=min(65_536, maximum)):
        if not chunk:
            continue
        remaining = maximum - len(output)
        output.extend(chunk[:remaining])
        if len(output) >= maximum:
            break
    return bytes(output)


def request_target(greedy, uri: str) -> tuple[str, dict[str, str] | None]:
    """Resolve an HTTP URL or ``mast:`` URI through the normal download route."""

    return greedy.product_download_request({"datauri": uri})


def read_range(
    session,
    greedy,
    uri: str,
    *,
    offset: int,
    byte_count: int,
    timeout: float,
) -> tuple[bytes, int | None, int]:
    """Read one bounded FITS byte range and reject servers that ignore seeks."""

    url, parameters = request_target(greedy, uri)
    headers = {
        "Accept": "application/fits, application/octet-stream",
        "Accept-Encoding": "identity",
        "Range": f"bytes={offset}-{offset + byte_count - 1}",
    }
    token = os.environ.get("MAST_API_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"token {token}"
    response = session.get(
        url,
        params=parameters,
        headers=headers,
        stream=True,
        timeout=timeout,
    )
    try:
        response.raise_for_status()
        if offset > 0 and response.status_code != 206:
            raise RuntimeError(
                f"server ignored FITS byte range at offset {offset} "
                f"(HTTP {response.status_code})"
            )
        remote_size = remote_size_from_headers(response.headers)
        data = bounded_response_bytes(response, byte_count)
        if not data:
            raise RuntimeError(f"empty FITS range at offset {offset}")
        return data, remote_size, response.status_code
    finally:
        response.close()


def read_header_at(
    session,
    greedy,
    uri: str,
    *,
    offset: int,
    chunk_bytes: int,
    max_header_bytes: int,
    timeout: float,
) -> tuple[dict[str, Any], int, int, int | None]:
    """Grow bounded range requests until the current HDU's END card is found."""

    data = bytearray()
    request_count = 0
    remote_size: int | None = None
    while len(data) < max_header_bytes:
        count = min(chunk_bytes, max_header_bytes - len(data))
        piece, detected_size, _status = read_range(
            session,
            greedy,
            uri,
            offset=offset + len(data),
            byte_count=count,
            timeout=timeout,
        )
        request_count += 1
        remote_size = remote_size or detected_size
        data.extend(piece)
        parsed = parse_header_block(bytes(data))
        if parsed is not None:
            header, header_size = parsed
            return header, header_size, len(data), remote_size
        if len(piece) < count:
            break
    raise RuntimeError(
        f"FITS END card not found at offset {offset} within {max_header_bytes} bytes"
    )


def has_complete_wcs(header: dict[str, Any]) -> bool:
    """Recognize the linear CD or PC+CDELT WCS forms SwiftMAST supports."""

    if any(header.get(key) is None for key in WCS_SCALAR_KEYS):
        return False
    has_cd = all(
        header.get(key) is not None
        for key in ("CD1_1", "CD1_2", "CD2_1", "CD2_2")
    )
    has_cdelt = all(header.get(key) is not None for key in ("CDELT1", "CDELT2"))
    return has_cd or has_cdelt


def hdu_role(header: dict[str, Any]) -> str:
    """Classify the common science/weight/error/data-quality extensions."""

    name = str(header.get("EXTNAME") or "").strip().upper()
    if name in {"SCI", "SCIENCE", "PRIMARY"}:
        return "science"
    if name in {"WHT", "WEIGHT", "IVM"}:
        return "weight"
    if name in {"ERR", "ERROR", "VAR", "VARIANCE"}:
        return "error"
    if name in {"DQ", "QUALITY", "DATAQUALITY"}:
        return "dataQuality"
    return "unknown"


def fetch_preferred_fits_header(
    session,
    greedy,
    product: dict[str, Any],
    *,
    chunk_bytes: int,
    max_header_bytes: int,
    max_hdus: int,
    timeout: float,
) -> dict[str, Any]:
    """Walk FITS HDUs by range and return the first renderable image header."""

    uri = str(product.get("datauri") or "").strip()
    if not uri:
        raise RuntimeError("product has no FITS datauri")
    started = time.monotonic()
    offset = 0
    total_bytes = 0
    request_count = 0
    primary: dict[str, Any] = {}
    remote_size: int | None = None
    for hdu_index in range(max_hdus):
        header, header_size, bytes_read, detected_size = read_header_at(
            session,
            greedy,
            uri,
            offset=offset,
            chunk_bytes=chunk_bytes,
            max_header_bytes=max_header_bytes,
            timeout=timeout,
        )
        total_bytes += bytes_read
        request_count += math.ceil(bytes_read / chunk_bytes)
        remote_size = remote_size or detected_size
        if hdu_index == 0:
            primary = header
        data_size = fits_data_size(header)
        naxis = int(header.get("NAXIS") or 0)
        width = int(header.get("NAXIS1") or 0)
        height = int(header.get("NAXIS2") or 0)
        if naxis >= 2 and width > 0 and height > 0 and data_size > 0:
            merged = {**primary, **header}
            wcs = {key.lower(): merged.get(key) for key in WCS_REPORT_KEYS}
            return {
                "status": "ok",
                "source_uri": uri,
                "bytes_fetched": total_bytes,
                "range_request_count": request_count,
                "remote_file_size_bytes": remote_size,
                "elapsed_seconds": round(time.monotonic() - started, 3),
                "hdu_index": hdu_index,
                "extname": str(header.get("EXTNAME") or ""),
                "role": hdu_role(header),
                "width": width,
                "height": height,
                "pixel_count": width * height,
                "axis_count": naxis,
                "axis_lengths": [
                    int(header.get(f"NAXIS{axis}") or 0)
                    for axis in range(1, naxis + 1)
                ],
                "bitpix": int(header.get("BITPIX") or 0),
                "data_size_bytes": data_size,
                "header_offset": offset,
                "data_offset": offset + header_size,
                "has_complete_wcs": has_complete_wcs(merged),
                "wcs": wcs,
            }
        offset = padded(offset + header_size + data_size)
        if remote_size is not None and offset >= remote_size:
            break
    raise RuntimeError(f"no image HDU found in the first {max_hdus} FITS HDUs")


def preview_probe(
    session,
    greedy,
    uri: str,
    *,
    maximum_bytes: int,
    timeout: float,
) -> dict[str, Any]:
    """Read enough of a preview to identify its actual format and dimensions."""

    _image, image_file, _unidentified_image_error = load_pillow()
    started = time.monotonic()
    url, parameters = request_target(greedy, uri)
    headers = {
        "Accept": "image/jpeg,image/png,image/*",
        "Accept-Encoding": "identity",
        "Range": f"bytes=0-{maximum_bytes - 1}",
    }
    token = os.environ.get("MAST_API_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"token {token}"
    response = session.get(
        url,
        params=parameters,
        headers=headers,
        stream=True,
        timeout=timeout,
    )
    try:
        response.raise_for_status()
        parser = image_file.Parser()
        bytes_read = 0
        width = height = 0
        image_format = ""
        for chunk in response.iter_content(chunk_size=16_384):
            if not chunk:
                continue
            remaining = maximum_bytes - bytes_read
            parser.feed(chunk[:remaining])
            bytes_read += min(len(chunk), remaining)
            if parser.image is not None:
                width, height = parser.image.size
                image_format = str(parser.image.format or "")
                break
            if bytes_read >= maximum_bytes:
                break
        if width <= 0 or height <= 0:
            raise RuntimeError(
                f"preview dimensions not found within {maximum_bytes} bytes"
            )
        return {
            "status": "ok",
            "source_uri": uri,
            "width": width,
            "height": height,
            "pixel_count": width * height,
            "format": image_format,
            "content_type": response.headers.get("Content-Type"),
            "remote_file_size_bytes": remote_size_from_headers(response.headers),
            "bytes_fetched": bytes_read,
            "elapsed_seconds": round(time.monotonic() - started, 3),
        }
    finally:
        response.close()


def preview_decision(
    header: dict[str, Any] | None,
    header_error: str | None,
    preview: dict[str, Any] | None,
    preview_error: str | None,
    *,
    min_source_width: int,
    min_source_height: int,
    min_preview_width: int,
    min_preview_height: int,
    require_wcs: bool,
) -> tuple[str, list[str]]:
    """Return ``preview`` only when every configured quality gate passes."""

    reasons = []
    if header_error or header is None:
        reasons.append("fits_header_probe_failed")
    else:
        if int(header["width"]) < min_source_width:
            reasons.append("fits_width_below_threshold")
        if int(header["height"]) < min_source_height:
            reasons.append("fits_height_below_threshold")
        if require_wcs and not header.get("has_complete_wcs"):
            reasons.append("fits_wcs_incomplete")
    if preview_error or preview is None:
        reasons.append("preview_probe_failed")
    else:
        if int(preview["width"]) < min_preview_width:
            reasons.append("preview_width_below_threshold")
        if int(preview["height"]) < min_preview_height:
            reasons.append("preview_height_below_threshold")
    return ("preview", ["all_quality_gates_passed"]) if not reasons else ("fits", reasons)


def adaptive_cache_paths(
    greedy,
    cache_root: Path,
    target_name: str,
    product: dict[str, Any],
) -> tuple[Path, Path, Path, Path]:
    """Return FITS, preview, COAM, and range-header cache paths."""

    fits_path, coam_path = greedy.swiftmast_cache_paths(
        cache_root, target_name, product
    )
    stem = fits_path.name.removesuffix(".fits")
    preview_path = fits_path.parent.parent / "preview" / f"{stem}.jpg"
    header_path = fits_path.parent / f"{stem}.range-header.json"
    return fits_path, preview_path, coam_path, header_path


def validated_image(path: Path) -> tuple[int, int, str] | None:
    """Return dimensions/format for a decodable local preview image."""

    image, _image_file, unidentified_image_error = load_pillow()
    try:
        with image.open(path) as opened_image:
            opened_image.verify()
        with image.open(path) as opened_image:
            width, height = opened_image.size
            return width, height, str(opened_image.format or "")
    except (OSError, unidentified_image_error):
        return None


def download_preview(
    session,
    greedy,
    product: dict[str, Any],
    destination: Path,
    *,
    timeout: float,
    max_bytes: int,
    min_width: int,
    min_height: int,
) -> dict[str, Any]:
    """Atomically download and validate one preview, with a strict size cap."""

    cached = validated_image(destination) if destination.exists() else None
    if cached is not None and cached[0] >= min_width and cached[1] >= min_height:
        return {
            "status": "cached_preview",
            "local_path": str(destination),
            "local_size_bytes": destination.stat().st_size,
            "width": cached[0],
            "height": cached[1],
            "format": cached[2],
            "transferred_bytes": 0,
        }
    uri = str(product.get("previewuri") or "").strip()
    if not uri:
        raise RuntimeError("product has no previewuri")
    url, parameters = request_target(greedy, uri)
    headers = {"Accept": "image/jpeg,image/png,image/*", "Accept-Encoding": "identity"}
    token = os.environ.get("MAST_API_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"token {token}"
    response = session.get(
        url,
        params=parameters,
        headers=headers,
        stream=True,
        timeout=timeout,
    )
    temporary = destination.with_suffix(destination.suffix + ".part")
    try:
        response.raise_for_status()
        announced = remote_size_from_headers(response.headers)
        if announced is not None and announced > max_bytes:
            raise RuntimeError(
                f"preview is {announced} bytes, above the {max_bytes}-byte cap"
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        transferred = 0
        with temporary.open("wb") as stream:
            for chunk in response.iter_content(chunk_size=MIB):
                if not chunk:
                    continue
                transferred += len(chunk)
                if transferred > max_bytes:
                    raise RuntimeError(
                        f"preview exceeded the {max_bytes}-byte cap while downloading"
                    )
                stream.write(chunk)
            stream.flush()
            os.fsync(stream.fileno())
        details = validated_image(temporary)
        if details is None:
            raise RuntimeError("downloaded preview is not a valid image")
        width, height, image_format = details
        if width < min_width or height < min_height:
            raise RuntimeError(
                f"downloaded preview {width}x{height} is below "
                f"{min_width}x{min_height}"
            )
        temporary.replace(destination)
        return {
            "status": "downloaded_preview",
            "local_path": str(destination),
            "local_size_bytes": destination.stat().st_size,
            "width": width,
            "height": height,
            "format": image_format,
            "transferred_bytes": transferred,
        }
    finally:
        response.close()
        if temporary.exists():
            temporary.unlink()


def write_preview_sidecar(
    greedy,
    product: dict[str, Any],
    *,
    preview_path: Path,
    coam_path: Path,
    preview_size: int,
) -> None:
    """Write a SwiftMAST-compatible COAM sidecar for a cached preview."""

    sidecar = greedy.swiftmast_coam_sidecar(product)
    sidecar["jpegURLSizeBytes"] = preview_size
    sidecar["localResources"] = {
        "fitsPath": None,
        "imagePath": None,
        "previewImagePath": str(preview_path),
        "rawMetadataPath": None,
        "structuredMetadataPath": None,
        "imageMetadataPath": None,
        "cachedAt": None,
    }
    greedy.write_json_atomically(coam_path, sidecar)


def download_fits_safely(
    session,
    greedy,
    product: dict[str, Any],
    *,
    target_name: str,
    cache_root: Path,
    timeout: float,
) -> dict[str, Any]:
    """Use the existing FITS downloader while isolating per-product failures."""

    try:
        return greedy.download_selected_product(
            session,
            product,
            target_name=target_name,
            cache_root=cache_root,
            timeout=timeout,
        )
    except Exception as error:  # report one failure and continue the manifest
        LOGGER.error(
            "FITS download failed rank=%s observation_id=%r error=%s",
            product.get("selection_rank"),
            product.get("obs_id"),
            error,
        )
        return {
            "status": "failed",
            "error": str(error),
            "transferred_bytes": 0,
        }


def product_plan(
    session,
    greedy,
    product: dict[str, Any],
    args: argparse.Namespace,
) -> dict[str, Any]:
    """Probe one product and return an auditable preview-or-FITS decision."""

    header = None
    header_error = None
    try:
        header = fetch_preferred_fits_header(
            session,
            greedy,
            product,
            chunk_bytes=args.header_chunk_bytes,
            max_header_bytes=args.max_header_bytes,
            max_hdus=args.max_hdus,
            timeout=args.timeout,
        )
    except Exception as error:  # keep one bad product from ending the run
        header_error = str(error)
        LOGGER.warning(
            "FITS header probe failed rank=%s error=%s",
            product.get("selection_rank"),
            error,
        )

    preview = None
    preview_error = None
    preview_uri = str(product.get("previewuri") or "").strip()
    if preview_uri:
        try:
            preview = preview_probe(
                session,
                greedy,
                preview_uri,
                maximum_bytes=args.preview_probe_bytes,
                timeout=args.timeout,
            )
        except Exception as error:  # conservative FITS fallback
            preview_error = str(error)
            LOGGER.warning(
                "Preview probe failed rank=%s error=%s",
                product.get("selection_rank"),
                error,
            )
    else:
        preview_error = "missing previewuri"

    choice, reasons = preview_decision(
        header,
        header_error,
        preview,
        preview_error,
        min_source_width=args.min_source_width,
        min_source_height=args.min_source_height,
        min_preview_width=args.min_preview_width,
        min_preview_height=args.min_preview_height,
        require_wcs=args.require_wcs,
    )
    return {
        "selection_rank": product.get("selection_rank"),
        "observation_id": product.get("obs_id"),
        "mission": product.get("obs_collection"),
        "filters": product.get("filters"),
        "fits_uri": product.get("datauri"),
        "preview_uri": product.get("previewuri"),
        "choice": choice,
        "decision_reasons": reasons,
        "fits_header": header,
        "fits_header_error": header_error,
        "preview_probe": preview,
        "preview_probe_error": preview_error,
    }


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return number




def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    """Add manifest, cache, network, logging, and dry-run options to a mode."""

    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--cache-root",
        type=Path,
        default=Path.home() / "Documents" / "MAST",
        help="SwiftMAST MAST cache root (default: ~/Documents/MAST).",
    )
    parser.add_argument("--target-name", help="Override the target cache folder name.")
    parser.add_argument("--output", type=Path, help="Download report path.")
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
    )


def target_name_from_manifest(args: argparse.Namespace, manifest: dict[str, Any]) -> str:
    """Return the explicit, manifest, or coordinate-derived cache target name."""

    target_name = str(args.target_name or manifest.get("target") or "").strip()
    if target_name:
        return target_name
    position = manifest.get("position") or {}
    return f"ra-{float(position['ra']):.6f}_dec-{float(position['dec']):.6f}"


def run_fits(args: argparse.Namespace) -> int:
    """Run the original FITS-only Phase 3 downloader."""

    manifest_path = args.manifest.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    products = manifest["selected_products"]
    target_name = target_name_from_manifest(args, manifest)
    cache_root = args.cache_root.expanduser().resolve()
    expected = sum(int(float(product["contentlength"])) for product in products)
    LOGGER.info(
        "Manifest ready products=%s expected_GiB=%.2f target=%r cache_root=%s",
        len(products),
        expected / (1024**3),
        target_name,
        cache_root,
    )
    greedy = load_greedy()
    if args.dry_run:
        report = dry_run_report(
            greedy,
            products,
            target_name=target_name,
            cache_root=cache_root,
        )
    else:
        report = greedy.download_selected_products(
            products,
            target_name=target_name,
            cache_root=cache_root,
            timeout=args.timeout,
            retries=args.retries,
        )
        report["dry_run"] = False
    report["schema_version"] = SCHEMA_VERSION
    report["artifact"] = "mast-composite-phase-3-download-report"
    report["manifest_path"] = str(manifest_path)
    report_path = (
        args.output.expanduser().resolve()
        if args.output
        else manifest_path.parent / "phase-3-download-report.json"
    )
    write_json(report_path, report)
    LOGGER.info("Phase 3 report written path=%s", report_path)
    return 1 if int(report.get("failed_product_count") or 0) else 0


def selected_products_for_adaptive_mode(
    parser: argparse.ArgumentParser,
    args: argparse.Namespace,
    manifest: dict[str, Any],
) -> list[dict[str, Any]]:
    """Apply optional rank and count restrictions to manifest products."""

    products = manifest["selected_products"]
    if args.selection_ranks:
        try:
            requested_ranks = {
                positive_int(value.strip())
                for value in args.selection_ranks.split(",")
                if value.strip()
            }
        except (ValueError, argparse.ArgumentTypeError) as error:
            parser.error(f"invalid --selection-ranks: {error}")
        if not requested_ranks:
            parser.error("--selection-ranks must contain at least one rank")
        products = [
            product
            for product in products
            if int(product.get("selection_rank") or 0) in requested_ranks
        ]
        found_ranks = {int(product.get("selection_rank") or 0) for product in products}
        missing_ranks = sorted(requested_ranks - found_ranks)
        if missing_ranks:
            parser.error(
                "selection ranks not found in manifest: "
                + ",".join(str(rank) for rank in missing_ranks)
            )
    if args.limit is not None:
        products = products[: args.limit]
    return products


def run_adaptive(args: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    """Choose and optionally download a validated preview or FITS per product."""

    greedy = load_greedy()
    manifest_path = args.manifest.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    products = selected_products_for_adaptive_mode(parser, args, manifest)
    target_name = target_name_from_manifest(args, manifest)
    cache_root = args.cache_root.expanduser().resolve()
    started = time.monotonic()
    reports = []
    with greedy.requests_session(args.retries) as session:
        for index, product in enumerate(products, start=1):
            LOGGER.info(
                "Adaptive probe started product=%s/%s rank=%s",
                index,
                len(products),
                product.get("selection_rank"),
            )
            report = product_plan(session, greedy, product, args)
            fits_path, preview_path, coam_path, header_path = adaptive_cache_paths(
                greedy, cache_root, target_name, product
            )
            report.update(
                {
                    "planned_fits_path": str(fits_path),
                    "planned_preview_path": str(preview_path),
                    "coam_sidecar_path": str(coam_path),
                    "range_header_path": str(header_path),
                }
            )
            if args.dry_run:
                report["status"] = f"would_download_{report['choice']}"
                report["transferred_bytes"] = 0
            elif report["choice"] == "preview":
                try:
                    result = download_preview(
                        session,
                        greedy,
                        product,
                        preview_path,
                        timeout=args.timeout,
                        max_bytes=args.max_preview_mib * MIB,
                        min_width=args.min_preview_width,
                        min_height=args.min_preview_height,
                    )
                    write_preview_sidecar(
                        greedy,
                        product,
                        preview_path=preview_path,
                        coam_path=coam_path,
                        preview_size=int(result["local_size_bytes"]),
                    )
                    report.update(result)
                except Exception as error:
                    LOGGER.warning(
                        "Preview download failed; falling back to FITS rank=%s error=%s",
                        product.get("selection_rank"),
                        error,
                    )
                    report["choice"] = "fits"
                    report["decision_reasons"].append(
                        "preview_download_validation_failed"
                    )
                    report["preview_download_error"] = str(error)
                    report.update(
                        download_fits_safely(
                            session,
                            greedy,
                            product,
                            target_name=target_name,
                            cache_root=cache_root,
                            timeout=args.timeout,
                        )
                    )
            else:
                report.update(
                    download_fits_safely(
                        session,
                        greedy,
                        product,
                        target_name=target_name,
                        cache_root=cache_root,
                        timeout=args.timeout,
                    )
                )
            if not args.dry_run and report.get("fits_header") is not None:
                greedy.write_json_atomically(header_path, report["fits_header"])
            reports.append(report)
            LOGGER.info(
                "Adaptive decision finished rank=%s choice=%s status=%s reasons=%s",
                product.get("selection_rank"),
                report.get("choice"),
                report.get("status"),
                ",".join(report.get("decision_reasons") or []),
            )

    choices = Counter(report["choice"] for report in reports)
    statuses = Counter(str(report.get("status") or "unknown") for report in reports)
    total_fits_bytes = sum(int(float(product["contentlength"])) for product in products)
    planned_preview_bytes = sum(
        int((report.get("preview_probe") or {}).get("remote_file_size_bytes") or 0)
        for report in reports
        if report["choice"] == "preview"
    )
    planned_fits_bytes = sum(
        int(float(product["contentlength"]))
        for product, report in zip(products, reports)
        if report["choice"] == "fits"
    )
    payload = {
        "schema_version": SCHEMA_VERSION,
        "artifact": "mast-composite-phase-3-adaptive-download-report",
        "manifest_path": str(manifest_path),
        "dry_run": args.dry_run,
        "target": target_name,
        "policy": {
            "min_source_width": args.min_source_width,
            "min_source_height": args.min_source_height,
            "min_preview_width": args.min_preview_width,
            "min_preview_height": args.min_preview_height,
            "require_wcs": args.require_wcs,
            "fallback": "fits",
        },
        "summary": {
            "product_count": len(reports),
            "preview_choice_count": choices["preview"],
            "fits_choice_count": choices["fits"],
            "failed_product_count": statuses["failed"],
            "status_counts": dict(sorted(statuses.items())),
            "fits_only_manifest_bytes": total_fits_bytes,
            "planned_payload_bytes": planned_fits_bytes + planned_preview_bytes,
            "estimated_bytes_avoided": max(
                total_fits_bytes - planned_fits_bytes - planned_preview_bytes, 0
            ),
            "metadata_probe_bytes": sum(
                int((report.get("fits_header") or {}).get("bytes_fetched") or 0)
                + int((report.get("preview_probe") or {}).get("bytes_fetched") or 0)
                for report in reports
            ),
            "transferred_bytes": sum(
                int(report.get("transferred_bytes") or 0) for report in reports
            ),
            "elapsed_seconds": round(time.monotonic() - started, 3),
        },
        "products": reports,
    }
    report_path = (
        args.output.expanduser().resolve()
        if args.output
        else manifest_path.parent / "phase-3-adaptive-download-report.json"
    )
    write_json(report_path, payload)
    LOGGER.info(
        "Adaptive Phase 3 complete previews=%s fits=%s probe_mib=%.2f report=%s",
        choices["preview"],
        choices["fits"],
        payload["summary"]["metadata_probe_bytes"] / MIB,
        report_path,
    )
    return 1 if statuses["failed"] else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    fits = subparsers.add_parser(
        "fits",
        help="Download every selected product as FITS (original Phase 3 behavior).",
    )
    add_common_arguments(fits)
    fits.set_defaults(func=run_fits)

    adaptive = subparsers.add_parser(
        "adaptive",
        help="Choose a validated preview or FITS file for each selected product.",
    )
    add_common_arguments(adaptive)
    adaptive.add_argument("--limit", type=positive_int, help="Use the first N products.")
    adaptive.add_argument(
        "--selection-ranks",
        help="Comma-separated Phase 2 selection ranks to probe/download.",
    )
    adaptive.add_argument("--min-source-width", type=positive_int, default=1024)
    adaptive.add_argument("--min-source-height", type=positive_int, default=1024)
    adaptive.add_argument("--min-preview-width", type=positive_int, default=1024)
    adaptive.add_argument("--min-preview-height", type=positive_int, default=1024)
    adaptive.add_argument(
        "--require-wcs",
        action="store_true",
        help="Use previews only when the FITS header has a complete linear WCS.",
    )
    adaptive.add_argument("--header-chunk-bytes", type=positive_int, default=65_536)
    adaptive.add_argument("--max-header-bytes", type=positive_int, default=262_144)
    adaptive.add_argument("--max-hdus", type=positive_int, default=16)
    adaptive.add_argument("--preview-probe-bytes", type=positive_int, default=262_144)
    adaptive.add_argument("--max-preview-mib", type=positive_int, default=50)
    adaptive.set_defaults(func=run_adaptive)
    return parser


def normalized_cli_args(argv: list[str]) -> list[str]:
    """Route the former no-subcommand syntax to the FITS-only mode."""

    if argv and argv[0] not in {"fits", "adaptive", "-h", "--help"}:
        return ["fits", *argv]
    return argv


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    raw_arguments = list(sys.argv[1:] if argv is None else argv)
    args = parser.parse_args(normalized_cli_args(raw_arguments))
    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if args.retries < 0:
        parser.error("--retries cannot be negative")
    if args.command == "adaptive" and args.max_header_bytes < args.header_chunk_bytes:
        parser.error("--max-header-bytes must be at least --header-chunk-bytes")
    if args.command == "adaptive":
        return args.func(args, parser)
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        LOGGER.exception("Selection download failed")
        raise
