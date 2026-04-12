#!/usr/bin/env python3
"""Query MAST for JWST products and analyze obs_id grouping patterns."""
import requests
import json
import re
from collections import defaultdict

def resolve_target(name):
    payload = {
        'service': 'Mast.Name.Lookup',
        'params': {'input': name, 'format': 'json'},
        'format': 'json',
        'removenullcolumns': True
    }
    resp = requests.post('https://mast.stsci.edu/api/v0/invoke',
                         data={'request': json.dumps(payload)})
    data = resp.json()
    c = data['resolvedCoordinate'][0]
    return c['ra'], c['decl'], c['radius']

def query_jwst(ra, dec, radius, pagesize=400):
    payload = {
        'service': 'Mast.Caom.Filtered.Position',
        'params': {'columns': '*', 'position': f'{ra}, {dec}, {radius}'},
        'format': 'json',
        'removenullcolumns': True,
        'pagesize': pagesize,
        'page': 1,
        'filters': [
            {'paramName': 'dataRights', 'values': [{'value': 'PUBLIC'}]},
            {'paramName': 'calib_level', 'values': [{'value': '3'}, {'value': '4'}]},
            {'paramName': 'dataproduct_type', 'values': [{'value': 'IMAGE'}]},
            {'paramName': 'intentType', 'values': [{'value': 'science'}]},
            {'paramName': 'obs_collection', 'values': [{'value': 'JWST'}]}
        ]
    }
    resp = requests.post('https://mast.stsci.edu/api/v0/invoke',
                         data={'request': json.dumps(payload)})
    return resp.json().get('data', [])

def parse_filter_number(f):
    """Extract numeric wavelength from JWST filter name for sorting.
    F200W -> 200, F1000W -> 1000, F150W2 -> 150, F444W;F405N -> 444"""
    m = re.match(r'[Ff](\d+)', f.split(';')[0])
    return int(m.group(1)) if m else 99999

for target in ['NGC 628', 'NGC 253']:
    print(f'\n{"="*60}')
    print(f'TARGET: {target}')
    print(f'{"="*60}')
    ra, dec, radius = resolve_target(target)
    print(f'  RA={ra}, Dec={dec}, Radius={radius}')
    
    rows = query_jwst(ra, dec, radius)
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
        print(f'  {oid}')
        print(f'    instruments: {instruments}')
        print(f'    filters ({len(filters)}): {filters}')
        print(f'    t_min range: [{min(r["t_min"] for r in items)}, {max(r["t_min"] for r in items)}]')
        print()

# Also show all unique filter names across all data
print(f'\n{"="*60}')
print('ALL UNIQUE FILTERS (sorted by wavelength):')
all_filters = set()
for target in ['NGC 628', 'NGC 253']:
    ra, dec, radius = resolve_target(target)
    rows = query_jwst(ra, dec, radius)
    for r in rows:
        all_filters.add(r['filters'])

for f in sorted(all_filters, key=parse_filter_number):
    print(f'  {f} (sort key: {parse_filter_number(f)})')
