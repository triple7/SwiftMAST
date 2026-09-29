import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
import re
from collections import defaultdict, Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

TARGET_RA = 24.174
TARGET_DEC = 15.783

def parse_polygon(footprint_str):
    """
    Parses an STC-S POLYGON string and extracts its bounding box.
    """
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
        'max_dec': max(decs)
    }

def bboxes_overlap(c1, c2):
    """
    Checks if two spatial bounding boxes intersect/overlap.
    """
    return not (c1['max_ra'] < c2['min_ra'] or c1['min_ra'] > c2['max_ra'] or 
                c1['max_dec'] < c2['min_dec'] or c1['min_dec'] > c2['max_dec'])

def fetch_collection(collection):
    """
    Executes a TAP query for a specific observatory collection.
    """
    query = f"""
    SELECT TOP 1000
        o.obs_id, 
        o.filters,
        p.posboundsstcs,
        o.instrument_name
    FROM dbo.obspointing AS o 
    JOIN dbo.caomplane AS p ON p.planetid = o.objid 
    JOIN dbo.caomartifact AS a ON a.planetid = p.planetid 
    WHERE 
        CONTAINS( 
            POINT('ICRS', o.s_ra, o.s_dec), 
            CIRCLE('ICRS', {TARGET_RA}, {TARGET_DEC}, 0.0.05) 
        ) = 1 
        AND o.obs_collection = '{collection}' 
        AND o.datarights = 'PUBLIC' 
        AND o.calib_level IN (3, 4)
        AND o.dataproduct_type = 'image'
    """

    url = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
    data = urllib.parse.urlencode({
        "REQUEST": "doQuery",
        "LANG": "ADQL",
        "FORMAT": "csv",
        "QUERY": query
    }).encode('utf-8')

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
                
                obs_idx, filter_idx, foot_idx, inst_idx = -1, -1, -1, -1
                for i, field in enumerate(fields):
                    name = field.attrib.get('name', '').lower()
                    if name == 'obs_id': obs_idx = i
                    elif name == 'filters': filter_idx = i
                    elif name == 'posboundsstcs': foot_idx = i
                    elif name == 'instrument_name': inst_idx = i
                        
                if -1 not in (obs_idx, filter_idx, foot_idx, inst_idx):
                    for tr in root.findall('.//TR'):
                        tds = tr.findall('TD')
                        if len(tds) > max(obs_idx, filter_idx, foot_idx, inst_idx):
                            obs_id = tds[obs_idx].text.strip() if tds[obs_idx].text else "UNKNOWN"
                            filt = tds[filter_idx].text.strip() if tds[filter_idx].text else "UNKNOWN"
                            foot = tds[foot_idx].text.strip() if len(tds) > foot_idx and tds[foot_idx].text else "UNKNOWN"
                            inst = tds[inst_idx].text.strip() if tds[inst_idx].text else "UNKNOWN"
                            observations.add((obs_id, filt, foot, inst, collection))
            else:
                import csv, io
                reader = csv.reader(io.StringIO(res))
                header = next(reader, None)
                if header:
                    o_idx = header.index('obs_id')
                    f_idx = header.index('filters')
                    ft_idx = header.index('posboundsstcs')
                    i_idx = header.index('instrument_name')
                    for row in reader:
                        observations.add((row[o_idx].strip(), row[f_idx].strip(), row[ft_idx].strip(), row[i_idx].strip(), collection))
                        
    except Exception as e:
        return collection, set(), str(e), time.time() - start_time

    return collection, observations, None, elapsed


print("--- PHASE 1: EXECUTING PARALLEL TAP QUERIES ---")
collections = ['JWST', 'HST', 'HLA']
all_raw_observations = set()
overall_start = time.time()

with ThreadPoolExecutor(max_workers=3) as executor:
    future_to_col = {executor.submit(fetch_collection, col): col for col in collections}
    for future in as_completed(future_to_col):
        col, obs_set, error, elapsed = future.result()
        if error:
            print(f"❌ {col.ljust(5)} : FAILED in {elapsed:.2f}s (Error: {error})")
        else:
            print(f"✅ {col.ljust(5)} : Completed in {elapsed:.2f}s ({len(obs_set)} unique artifacts)")
            all_raw_observations.update(obs_set)

print(f"Total Query Phase Time: {time.time() - overall_start:.2f} seconds\n")

if all_raw_observations:
    print("--- PHASE 2: SPATIAL INTERACTION ANALYSIS ---")
    
    TOLERANCE = 0.001 
    all_base_clusters = []
    
    # 1. Deduplicate identical footprints per instrument to find base geometric clusters
    for obs_id, filt, raw_foot, inst, coll in all_raw_observations:
        geom = parse_polygon(raw_foot)
        if not geom: continue
            
        matched_cluster = None
        for cluster in all_base_clusters:
            # Must be same collection/instrument to be grouped as a single "base footprint"
            if cluster['collection'] == coll and cluster['instrument'] == inst:
                if (abs(cluster['min_ra'] - geom['min_ra']) <= TOLERANCE and 
                    abs(cluster['max_ra'] - geom['max_ra']) <= TOLERANCE and 
                    abs(cluster['min_dec'] - geom['min_dec']) <= TOLERANCE and 
                    abs(cluster['max_dec'] - geom['max_dec']) <= TOLERANCE):
                    matched_cluster = cluster
                    break
                
        if matched_cluster:
            matched_cluster['observations'].append((obs_id, filt))
        else:
            geom['collection'] = coll
            geom['instrument'] = inst
            geom['observations'] = [(obs_id, filt)]
            all_base_clusters.append(geom)

    # 2. Map clusters to Interaction Zones
    core_zone = []
    adjacent_zone = []
    peripheral_zone = []

    for cluster in all_base_clusters:
        # Check if the bounding box directly encompasses the exact target coordinates
        if cluster['min_ra'] <= TARGET_RA <= cluster['max_ra'] and cluster['min_dec'] <= TARGET_DEC <= cluster['max_dec']:
            core_zone.append(cluster)

    for cluster in all_base_clusters:
        if cluster in core_zone:
            continue
        
        # Check if it intersects/overlaps with ANY of the Core coverage clusters
        overlaps_core = any(bboxes_overlap(cluster, core) for core in core_zone)
        if overlaps_core:
            adjacent_zone.append(cluster)
        else:
            peripheral_zone.append(cluster)

    # --- PRINT HIGH-LEVEL SUMMARY ---
    def print_zone_summary(zone_name, description, clusters):
        print("=" * 70)
        print(f"ZONE: {zone_name}")
        print(f"↳ {description}")
        print("=" * 70)
        
        if not clusters:
            print("  (No spatial coverage falls into this interaction zone)\n")
            return
            
        # Group by Collection -> Instrument for the summary view
        hierarchy = defaultdict(lambda: defaultdict(list))
        for c in clusters:
            coll = c['collection']
            inst = c['instrument']
            for obs_id, filt in c['observations']:
                hierarchy[coll][inst].append(filt)
                
        print(f"Composed of {len(clusters)} distinct spatial footprints:\n")
        
        for coll in sorted(hierarchy.keys()):
            print(f"■ {coll} OBSERVATORY")
            for inst in sorted(hierarchy[coll].keys()):
                filters_present = hierarchy[coll][inst]
                f_counts = Counter(filters_present)
                
                # Format a nice string for the filters
                f_summary = " | ".join([f"{f}({count})" for f, count in f_counts.most_common()])
                print(f"    - {inst.ljust(8)} : {len(filters_present)} total obs -> {f_summary}")
        print("\n")

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
