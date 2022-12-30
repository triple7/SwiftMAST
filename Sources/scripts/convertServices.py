import requests as R
from bs4 import BeautifulSoup
import re

URL = "https://mast.stsci.edu/api/v0/_services.html"
page = R.get(URL)
soup = BeautifulSoup(page.content, 'html.parser')
headers = soup.find_all('h1')
headers = [h.text.replace('\n', '').replace('\r', '') for h in headers]
for i,h in enumerate(headers):
    h = h.replace('.', '_')
    print(f'case .{h}: return """{a[i]}"""')

uls = soup.find_all('ul')
uls = uls[109:]
uls = [l for i, l in enumerate(uls) if (i%2) == 0]


# Tic fields page
url2 = "https://mast.stsci.edu/api/v0/_t_i_cfields.html"
page = R.get(url2)
soup = BeautifulSoup(page.content, 'html.parser')
table = soup.find_all('table')
rows = table[1].find_all('tr')[1:]
output = []
for r in rows:
    c = [x.text for x in r.find_all('td')]
    print(f'case {c[0]}')
