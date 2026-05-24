#!/usr/bin/env python3
"""Query MAST for JWST products via Cone search and analyze obs_id grouping."""
import requests
import json
import re
from collections import defaultdict

def query_jwst_cone(ra, dec, radius, pagesize=500):
    payload = {
        'service': 'Mast.Caom.Cone',
        'params': {'ra': ra, 'dec': dec, 'radius': radius},
        'format': 'json',
        'pagesize': pagesize,
        'page': 1
    }
    resp = requests.post('https://mast.stsci.edu/api/v0/invoke',
                         data={'request': json.dumps(payload)})
    rows = resp.json().get('data', [])
    # Filter to JWST science images calib 3+
    return [r for r in rows
            if r.get('obs_collection') == 'JWST'
            and r.get('intentType') == 'science'
            and r.get('calib_level', 0) >= 3
            and r.get('dataproduct_type') == 'image']

def parse_filter_number(f):
    """Extract numeric wavelength from JWST filter name for sorting.
    F200W -> 200, F1000W -> 1000, F150W2 -> 150, F444W;F405N -> 444"""
    m = re.match(r'[Ff](\d+)', f.split(';')[0])
    return int(m.group(1)) if m else 99999

# NGC 628
targets = {
    'NGC 628': (24.174, 15.784, 0.2),
    'NGC 253': (11.888, -25.289, 0.3),
}

all_filters = set()

for target, (ra, dec, radius) in targets.items():
    print(f'\n{"="*60}')
    print(f'TARGET: {target} (ra={ra}, dec={dec}, radius={radius})')
    print(f'{"="*60}')

    rows = query_jwst_cone(ra, dec, radius)
    print(f'  Total JWST products: {len(rows)}')

    by_obsid = defaultdict(list)
    for r in rows:
        by_obsid[r['obs_id']].append(r)

    print(f'  Unique obs_ids: {len(by_obsid)}')
    print()

    for oid in sorted(by_obsid.keys()):
        items = by_obsid[oid]
        filters = sorted(set(r['filters'] for r in items), key=parse_filter_number)
        instruments = sorted(set(r['instrument_name'] for r in items))
        all_filters.update(r['filters'] for r in items)
        print(f'  {oid}')
        print(f'    instruments: {instruments}')
        print(f'    filters ({len(filters)}): {filters}')
        print(f'    t_min range: [{min(r["t_min"] for r in items):.4f}, {max(r["t_min"] for r in items):.4f}]')
        print()

print(f'\n{"="*60}')
print('ALL UNIQUE FILTERS (sorted by wavelength):')
for f in sorted(all_filters, key=parse_filter_number):
    print(f'  {f} -> sort key: {parse_filter_number(f)}')
