import requests as R
from bs4 import BeautifulSoup
import re

URL = "https://archive.stsci.edu/vo/general_params.html"
page = R.get(URL)
soup = BeautifulSoup(page.content, 'html.parser')
T = soup.find_all('table')[-3]
rows = T.find_all('tr')[1:]
output = []
for r in rows:
    columns = [c.text for c in r.find_all('td')]
    output.append(columns)

output = output[1:]
header = "public enum MASTGeneralParameter:String, CaseIterable, Identifiable {\n"
cases = '\n'.join([f'case {r[0]} /*{r[1]}: {r[2]}*/' for r in output])
print(header, cases, '\n', '}')