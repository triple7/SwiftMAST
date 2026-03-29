#!/usr/bin/env python3
"""Combine fits_header_keywords.json and keyword_relevance.json into a single CSV."""

import csv
import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KEYWORDS_FILE = os.path.join(SCRIPT_DIR, "keywords-research", "fits_header_keywords.json")
RELEVANCE_FILE = os.path.join(SCRIPT_DIR, "keywords-research", "keyword_relevance.json")
OUTPUT_FILE = os.path.join(SCRIPT_DIR, "keywords-research", "keywords_combined.csv")

FIELDNAMES = [
    "keyword",
    "description",
    "category",
    "datatype",
    "comment",
    "hdu",
    "missions",
    "mandatory",
    "content",
    "relevance_score",
    "relevance_comment",
    "user_comment",
]

def main():
    with open(KEYWORDS_FILE) as f:
        keywords = json.load(f)["keywords"]

    with open(RELEVANCE_FILE) as f:
        relevance = json.load(f)

    with open(OUTPUT_FILE, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=FIELDNAMES)
        writer.writeheader()

        for keyword, kw_data in keywords.items():
            rel_data = relevance.get(keyword, {})
            row = {
                "keyword": keyword,
                "description": kw_data.get("description", ""),
                "category": kw_data.get("category", ""),
                "datatype": kw_data.get("datatype", ""),
                "comment": kw_data.get("comment", ""),
                "hdu": "; ".join(kw_data.get("hdu", [])),
                "missions": "; ".join(kw_data.get("missions", [])),
                "mandatory": kw_data.get("mandatory", ""),
                "content": rel_data.get("content", ""),
                "relevance_score": rel_data.get("relevance_score", ""),
                "relevance_comment": rel_data.get("relevance_comment", ""),
                "user_comment": rel_data.get("user_comment", ""),
            }
            writer.writerow(row)

    print(f"Written {len(keywords)} rows to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
