#!/usr/bin/env python3
"""
FITS Header Keyword Relevance Scorer

Uses Google Gemini to evaluate the relevance of FITS header keywords
for end-user facing astronomy applications. Processes keywords in
batches of 10 to minimize token cost, and supports resuming from a
specific keyword.

Usage:
    python keyword_relevance.py                         # process all keywords
    python keyword_relevance.py --start-key EXPTIME     # resume from EXPTIME
    python keyword_relevance.py --start-key FILTER --batch-size 5
"""

import argparse
import json
import os
import sys
import time
from google import genai
from google.genai import types


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_FILE = os.path.join(SCRIPT_DIR, "keywords-research", "fits_header_keywords.json")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "keywords-research", "keyword_relevance.json")
API_KEY_FILE = os.path.join(SCRIPT_DIR, "gemini-api.key")

SYSTEM_PROMPT = """You are an expert astronomer and software engineer evaluating FITS header keywords for an astronomy app aimed at researchers and enthusiasts.

For each keyword, provide:
1. "content": A 1-4 sentence plain-language explanation of what this keyword means and why it matters for astronomical data.
2. "relevance_score": An integer from 0-100 indicating how relevant/useful this keyword is to a typical end-user of an astronomy app (100 = essential for any user, 0 = purely internal/engineering with no user value).
3. "relevance_comment": A single sentence explaining the relevance score.

Scoring guidelines:
- 90-100: Essential metadata users always want (target name, coordinates, filter, exposure time, date)
- 70-89: Commonly useful for analysis or display (WCS, photometry, instrument details)
- 40-69: Useful for advanced users or specific workflows (calibration, subarray, dither)
- 20-39: Rarely needed by end users, mostly pipeline/engineering (reference files, versioning)
- 0-19: Purely internal/structural with no direct user relevance (PCOUNT, GCOUNT, checksums)

You MUST respond with valid JSON only — no markdown fences, no extra text.
Return a JSON object where each key is the FITS keyword name and the value is an object with "content", "relevance_score", and "relevance_comment"."""


def load_api_key():
    try:
        with open(API_KEY_FILE, "r") as f:
            key = f.read().strip()
        if not key:
            print(f"Error: {API_KEY_FILE} is empty.")
            sys.exit(1)
        return key
    except FileNotFoundError:
        print(f"Error: API key file not found at {API_KEY_FILE}")
        sys.exit(1)


def load_input_keywords():
    with open(INPUT_FILE, "r") as f:
        data = json.load(f)
    return data.get("keywords", {})


def load_existing_output():
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, "r") as f:
            return json.load(f)
    return {}


def save_output(results):
    with open(OUTPUT_FILE, "w") as f:
        json.dump(results, f, indent=2)


def build_batch_prompt(batch: dict) -> str:
    lines = ["Evaluate the following FITS header keywords:\n"]
    for key, info in batch.items():
        lines.append(f"- **{key}**: {info.get('description', 'N/A')} "
                     f"(category: {info.get('category', 'N/A')}, "
                     f"datatype: {info.get('datatype', 'N/A')}, "
                     f"HDU: {', '.join(info.get('hdu', []))}, "
                     f"missions: {', '.join(info.get('missions', []))})")
    lines.append("\nReturn a JSON object with results for all keywords above.")
    return "\n".join(lines)


def query_gemini(client, prompt: str, max_retries: int = 3) -> dict:
    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                ),
            )
            text = response.text.strip()
            # Strip markdown code fences if present
            if text.startswith("```"):
                text = text.split("\n", 1)[1]
                if text.endswith("```"):
                    text = text[: text.rfind("```")]
                text = text.strip()
            return json.loads(text)
        except json.JSONDecodeError as e:
            print(f"  JSON parse error (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
        except Exception as e:
            print(f"  API error (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
    return {}


def main():
    parser = argparse.ArgumentParser(description="Score FITS keyword relevance using Gemini")
    parser.add_argument("--start-key", type=str, default=None,
                        help="Keyword to start/resume from (case-sensitive, e.g. EXPTIME)")
    parser.add_argument("--batch-size", type=int, default=10,
                        help="Number of keywords per Gemini request (default: 10)")
    args = parser.parse_args()

    # Setup
    api_key = load_api_key()
    client = genai.Client(api_key=api_key)

    keywords = load_input_keywords()
    results = load_existing_output()
    all_keys = list(keywords.keys())

    # Determine starting index
    start_idx = 0
    if args.start_key:
        if args.start_key not in keywords:
            print(f"Error: keyword '{args.start_key}' not found in input file.")
            print(f"Available keywords start with: {', '.join(all_keys[:10])} ...")
            sys.exit(1)
        start_idx = all_keys.index(args.start_key)
        print(f"Resuming from keyword '{args.start_key}' (index {start_idx}/{len(all_keys)})")

    keys_to_process = all_keys[start_idx:]
    total = len(keys_to_process)
    batch_size = args.batch_size

    print(f"Total keywords: {len(all_keys)}")
    print(f"Keywords to process: {total} (starting at index {start_idx})")
    print(f"Batch size: {batch_size}")
    print(f"Output file: {OUTPUT_FILE}")
    print()

    processed = 0
    for i in range(0, total, batch_size):
        batch_keys = keys_to_process[i : i + batch_size]
        batch = {k: keywords[k] for k in batch_keys}

        batch_num = (i // batch_size) + 1
        total_batches = (total + batch_size - 1) // batch_size
        print(f"[Batch {batch_num}/{total_batches}] Processing: {', '.join(batch_keys)}")

        prompt = build_batch_prompt(batch)
        batch_results = query_gemini(client, prompt)

        if batch_results:
            for key in batch_keys:
                if key in batch_results:
                    entry = batch_results[key]
                    results[key] = {
                        "content": entry.get("content", ""),
                        "relevance_score": entry.get("relevance_score", 0),
                        "relevance_comment": entry.get("relevance_comment", ""),
                        "user_comment": ""
                    }
                    processed += 1
                else:
                    print(f"  Warning: no result for '{key}' in Gemini response")

            # Save immediately after each batch
            save_output(results)
            print(f"  Saved. Total scored: {len(results)}/{len(all_keys)}")
        else:
            print(f"  Failed to get results for batch. Stopping.")
            print(f"  Resume with: python keyword_relevance.py --start-key {batch_keys[0]}")
            sys.exit(1)

        # Rate-limit to avoid quota issues
        if i + batch_size < total:
            time.sleep(1)

    print(f"\nDone. Processed {processed} keywords this run.")
    print(f"Total scored keywords: {len(results)}/{len(all_keys)}")
    print(f"Results saved to: {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
