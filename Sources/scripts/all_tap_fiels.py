import urllib.request
import xml.etree.ElementTree as ET
import csv
import re

url = "https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync"
data = "REQUEST=doQuery&LANG=ADQL&FORMAT=csv&QUERY=SELECT table_name, column_name, description, datatype, unit FROM TAP_SCHEMA.columns ORDER BY table_name, column_name".encode('utf-8')

print("Fetching data from MAST...")
req = urllib.request.Request(url, data=data)
with urllib.request.urlopen(req) as response:
    xml_str = response.read().decode('utf-8')

# Strip XML namespaces for easier standard parsing
xml_str = re.sub(r'\sxmlns="[^"]+"', '', xml_str, count=1)
root = ET.fromstring(xml_str)

print("Converting to CSV...")
with open('mast_caom_columns.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['table_name', 'column_name', 'description', 'datatype', 'unit'])
    
    for tr in root.findall('.//TR'):
        row = [td.text if td.text else "" for td in tr.findall('TD')]
        if row:
            writer.writerow(row)

print("Saved successfully to mast_caom_columns.csv")