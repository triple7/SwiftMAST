import time
import urllib.request
import urllib.error
import urllib.parse
import xml.etree.ElementTree as ET
import re
import random
import math
from collections import defaultdict, Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

TARGET_RA = 24.174
TARGET_DEC = 15.783
SEARCH_RADIUS = 0.1

def parse_polygon(footprint_str):
    if not footprint_str or footprint_str.upper() == "UNKNOWN" or "POLYGON" not in footprint_str.upper():
        return None
        
    coords = [float(x) for x in re.findall(r'[-+]?\d*\.\d+|\d+', footprint_str)]
    if len(coords) < 6: 
        return None
        
    ras = coords[0::2]
    decs = coords[1::2]
    
    return {
        'min_ra': min(ras),
        'max_ra': max(ras),
        'min_dec': min(decs),
        'max_dec': max(decs),
        'area': (max(ras) - min(ras)) * (max(decs) - min(decs)) # Simple bounding box area
    }

def bboxes_overlap(c1, c2):
    return not (c1['max_ra'] < c2['min_ra'] or c1['min_ra'] > c2['max_ra'] or 
                c1['max_dec'] < c2['min_dec'] or c1['min_dec'] > c2['max_dec'])

def calculate_circle_overlap_percentage(bbox):
    """
    Calculates the approximate percentage of the search circle covered by the bounding box.
    Uses a simple geometric intersection approximation.
    """
    # 1. Circle bounding box
    circle_min_ra = TARGET_RA - SEARCH_RADIUS
    circle_max_ra = TARGET_RA + SEARCH_RADIUS
    circle_min_dec = TARGET_DEC - SEARCH_RADIUS
    circle_max_dec = TARGET_DEC + SEARCH_RADIUS
    circle_area = math.pi * (SEARCH_RADIUS ** 2)

    # 2. Find intersection of the two bounding boxes
    inter_min_ra = max(circle_min_ra, bbox['min_ra'])
    inter_max_ra = min(circle_max_ra, bbox['max_ra'])
    inter_min_dec = max(circle_min_dec, bbox['min_dec'])
    inter_max_dec = min(circle_max_dec, bbox['max_dec'])

    # If they don't intersect, overlap is 0%
    if inter_min_ra >= inter_max_ra or inter_min_dec >= inter_max_dec:
        return 0.0

    # 3. Calculate intersection area
    inter_area = (inter_max_ra - inter_min_ra) * (inter_max_dec - inter_min_dec)
    
    # 4. Calculate percentage of the circle
    percentage = (inter_area / circle_area) * 100
    return min(100.0, percentage) # Cap at 100% just in case of bounding box weirdness


def format_res(val):
    try:
        return f"{float(val):.4f}"
    except (ValueError, TypeError):
        return "N/A"

def fetch_collection(collection, delay=0):
    time.sleep(delay)
    
    # ADDED: AND a.contenttype LIKE '%fits%' to filter out JPG previews and XML logs
    query = f"""
    SELECT TOP 1000
        o.obs_id, 
        o.filters,
        p.posboundsstcs,
        o.instrument_name,
        p.posresolution,
        a.contentlength
    FROM dbo.obspointing AS o 
    JOIN dbo.caomplane AS p ON p.planetid = o.objid 
    JOIN dbo.caomartifact AS a ON a.planetid = p.planetid 
    WHERE 
        CONTAINS( 
            POINT('ICRS', o.s_ra, o.s_dec), 
            CIRCLE('ICRS', {TARGET_RA}, {TARGET_DEC}, {SEARCH_RADIUS}) 
        ) = 1 
        AND o.obs_collection = '{collection}' 
        AND o.datarights = 'PUBLIC' 
        AND o.calib_level IN (3, 4)
        AND o.dataproduct_type = 'image'
        AND a.contenttype LIKE '%fits%'
    """

    url = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
    data = urllib.parse.urlencode({
        "REQUEST": "doQuery",
        "LANG": "ADQL",
        "FORMAT": "csv",
        "QUERY": query
    }).encode('utf-8')

    max_retries = 3
    for attempt in range(max_retries):
        start_time = time.time()
        observations = set()
        
        try:
            req = urllib.request.Request(url, data=data)
            with urllib.request.urlopen(req, timeout=120) as response:
                res = response.read().decode('utf-8')
                elapsed = time.time() - start_time
                
                if res.strip().startswith('<'):
                    xml_str = re.sub(r'\sxmlns="[^"]+"', '', res, count=1)
                    root = ET.fromstring(xml_str)
                    fields = root.findall('.//FIELD')
                    
                    obs_idx, filter_idx, foot_idx, inst_idx, res_idx, len_idx = -1, -1, -1, -1, -1, -1
                    for i, field in enumerate(fields):
                        name = field.attrib.get('name', '').lower()
                        if name == 'obs_id': obs_idx = i
                        elif name == 'filters': filter_idx = i
                        elif name == 'posboundsstcs': foot_idx = i
                        elif name == 'instrument_name': inst_idx = i
                        elif name == 'posresolution': res_idx = i
                        elif name == 'contentlength': len_idx = i
                            
                    if -1 not in (obs_idx, filter_idx, foot_idx, inst_idx):
                        for tr in root.findall('.//TR'):
                            tds = tr.findall('TD')
                            if len(tds) > max(obs_idx, filter_idx, foot_idx, inst_idx):
                                obs_id = tds[obs_idx].text.strip() if tds[obs_idx].text else "UNKNOWN"
                                filt = tds[filter_idx].text.strip() if tds[filter_idx].text else "UNKNOWN"
                                foot = tds[foot_idx].text.strip() if len(tds) > foot_idx and tds[foot_idx].text else "UNKNOWN"
                                inst = tds[inst_idx].text.strip() if tds[inst_idx].text else "UNKNOWN"
                                
                                s_res = tds[res_idx].text.strip() if res_idx != -1 and len(tds) > res_idx and tds[res_idx].text else "N/A"
                                c_len = tds[len_idx].text.strip() if len_idx != -1 and len(tds) > len_idx and tds[len_idx].text else "N/A"
                                
                                observations.add((obs_id, filt, foot, inst, collection, format_res(s_res), c_len))
                else:
                    import csv, io
                    reader = csv.reader(io.StringIO(res))
                    header = next(reader, None)
                    if header:
                        o_idx = header.index('obs_id')
                        f_idx = header.index('filters')
                        ft_idx = header.index('posboundsstcs')
                        i_idx = header.index('instrument_name')
                        r_idx = header.index('posresolution') if 'posresolution' in header else -1
                        l_idx = header.index('contentlength') if 'contentlength' in header else -1
                        
                        for row in reader:
                            s_res = row[r_idx].strip() if r_idx != -1 else "N/A"
                            c_len = row[l_idx].strip() if l_idx != -1 else "N/A"
                            observations.add((
                                row[o_idx].strip(), 
                                row[f_idx].strip(), 
                                row[ft_idx].strip(), 
                                row[i_idx].strip(), 
                                collection, 
                                format_res(s_res), 
                                c_len
                            ))
                
                return collection, observations, None, elapsed

        except urllib.error.HTTPError as e:
            if attempt < max_retries - 1:
                sleep_time = (2 ** attempt) + random.uniform(1, 3)
                print(f"⚠️ {collection} retrying in {sleep_time:.1f}s...")
                time.sleep(sleep_time)
            else:
                return collection, set(), f"HTTP {e.code}: {e.reason}", time.time() - start_time
                
        except Exception as e:
            if attempt < max_retries - 1:
                sleep_time = (2 ** attempt) + random.uniform(1, 3)
                print(f"⚠️ {collection} hit exception: {e}. Retrying in {sleep_time:.1f}s...")
                time.sleep(sleep_time)
            else:
                return collection, set(), str(e), time.time() - start_time


print("--- PHASE 1: EXECUTING PARALLEL TAP QUERIES ---")
collections = ['JWST', 'HLA']
all_raw_observations = set()
overall_start = time.time()

with ThreadPoolExecutor(max_workers=2) as executor:
    future_to_col = {
        executor.submit(fetch_collection, col, delay=i*1.5): col 
        for i, col in enumerate(collections)
    }
    
    for future in as_completed(future_to_col):
        col, obs_set, error, elapsed = future.result()
        if error:
            print(f"❌ {col.ljust(5)} : FAILED in {elapsed:.2f}s (Error: {error})")
        else:
            print(f"✅ {col.ljust(5)} : Completed in {elapsed:.2f}s ({len(obs_set)} unique artifacts)")
            all_raw_observations.update(obs_set)

print(f"\nTotal Query Phase Time: {time.time() - overall_start:.2f} seconds\n")

if all_raw_observations:
    print("--- PHASE 2: SPATIAL INTERACTION ANALYSIS ---")
    
    TOLERANCE = 0.001 
    all_base_clusters = []
    
    # Track overall bounding box per instrument to calculate total coverage
    instrument_coverage = defaultdict(lambda: {'min_ra': float('inf'), 'max_ra': float('-inf'), 'min_dec': float('inf'), 'max_dec': float('-inf')})

    for obs_id, filt, raw_foot, inst, coll, s_res, c_len in all_raw_observations:
        geom = parse_polygon(raw_foot)
        if not geom: continue
        
        # Expand the unified bounding box for this instrument
        ic = instrument_coverage[inst]
        ic['min_ra'] = min(ic['min_ra'], geom['min_ra'])
        ic['max_ra'] = max(ic['max_ra'], geom['max_ra'])
        ic['min_dec'] = min(ic['min_dec'], geom['min_dec'])
        ic['max_dec'] = max(ic['max_dec'], geom['max_dec'])

        matched_cluster = None
        for cluster in all_base_clusters:
            if cluster['collection'] == coll and cluster['instrument'] == inst:
                if (abs(cluster['min_ra'] - geom['min_ra']) <= TOLERANCE and 
                    abs(cluster['max_ra'] - geom['max_ra']) <= TOLERANCE and 
                    abs(cluster['min_dec'] - geom['min_dec']) <= TOLERANCE and 
                    abs(cluster['max_dec'] - geom['max_dec']) <= TOLERANCE):
                    matched_cluster = cluster
                    break
                
        if matched_cluster:
            matched_cluster['observations'].append((obs_id, filt, s_res, c_len))
        else:
            geom['collection'] = coll
            geom['instrument'] = inst
            geom['observations'] = [(obs_id, filt, s_res, c_len)]
            all_base_clusters.append(geom)

    # Calculate overall coverage percentage per instrument
    for inst, ic in instrument_coverage.items():
        ic['coverage_percent'] = calculate_circle_overlap_percentage(ic)

    core_zone = []
    adjacent_zone = []
    peripheral_zone = []

    for cluster in all_base_clusters:
        if cluster['min_ra'] <= TARGET_RA <= cluster['max_ra'] and cluster['min_dec'] <= TARGET_DEC <= cluster['max_dec']:
            core_zone.append(cluster)

    for cluster in all_base_clusters:
        if cluster in core_zone:
            continue
        overlaps_core = any(bboxes_overlap(cluster, core) for core in core_zone)
        if overlaps_core:
            adjacent_zone.append(cluster)
        else:
            peripheral_zone.append(cluster)

    def print_zone_summary(zone_name, description, clusters):
        print("=" * 80)
        print(f"ZONE: {zone_name}")
        print(f"↳ {description}")
        print("=" * 80)
        
        if not clusters:
            print("  (No spatial coverage falls into this interaction zone)\n")
            return
            
        hierarchy = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
        for c in clusters:
            coll = c['collection']
            inst = c['instrument']
            for obs_id, filt, s_res, c_len in c['observations']:
                
                if c_len.isdigit():
                    size_mb = int(c_len) / (1024 * 1024)
                    size_str = f"{size_mb:.1f} MB"
                else:
                    size_str = "N/A"
                    
                res_tier = f"Res: {s_res} arcsec | Size: {size_str}"
                hierarchy[coll][inst][res_tier].append(filt)
                
        print(f"Composed of {len(clusters)} distinct spatial footprint(s):\n")
        
        for coll in sorted(hierarchy.keys()):
            print(f"■ {coll} OBSERVATORY")
            for inst in sorted(hierarchy[coll].keys()):
                
                # Retrieve the overall coverage for this instrument
                coverage = instrument_coverage[inst]['coverage_percent']
                
                print(f"    - {inst.ljust(8)} | Overall Area Coverage: {coverage:.1f}%")
                
                for res_tier in sorted(hierarchy[coll][inst].keys()):
                    filters_present = hierarchy[coll][inst][res_tier]
                    f_counts = Counter(filters_present)
                    
                    f_summary = " | ".join([f"{f}({count})" for f, count in f_counts.most_common()])
                    print(f"        ↳ [{res_tier}] : {len(filters_present):>2} obs -> {f_summary}")
            print()

    print_zone_summary(
        "CORE TARGET COVERAGE", 
        f"Clusters superimposed directly over the target center ({TARGET_RA}, {TARGET_DEC})", 
        core_zone
    )
    
    print_zone_summary(
        "ADJACENT / OVERLAPPING MOSAICS", 
        "Clusters that surround the target and physically overlap with the Core clusters", 
        adjacent_zone
    )
    
    print_zone_summary(
        "PERIPHERAL COVERAGE", 
        "Isolated clusters catching the edge of the search radius (No overlap with Core)", 
        peripheral_zone
    )