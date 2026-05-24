#!/usr/bin/env python3
"""Analyze obs_id structure to determine grouping key."""

obs_ids = [
    'jw01783-o004_t008_nircam_clear-f115w',
    'jw01783-o004_t008_nircam_clear-f150w',
    'jw01783-o004_t008_nircam_f405n-f444w',
    'jw01783-o908_t016_miri_f560w',
    'jw01783-o908_t016_miri_f770w',
    'jw02107-c1019_t018_miri_f1000w',
    'jw02107-o039_t018_miri_f1000w',
    'jw02107-o040_t018_nircam_clear-f200w',
    'jw02666-o007_t004_miri_f1000w',
    'jw02666-o007_t004_miri_f2550w',
    'jw01701-o001_t024_miri_f1130w',
    'jw01701-o053_t021_nircam_clear-f140m',
    'jw01701-o054_t021_nircam_clear-f140m-sub640',
]

for oid in obs_ids:
    parts = oid.split('_')
    # Group key = first 3 parts: jw01783-o004_t008_nircam
    group = '_'.join(parts[:3])
    print(f'{oid}')
    print(f'  group key: {group}')
    print(f'  instrument: {parts[2]}')
    print()
