import requests as R
from bs4 import BeautifulSoup
import re

url = "https://mast.stsci.edu/api/v0/pyex.html#MastCatalogsFilteredTicPy"
page = R.get(url)
soup = BeautifulSoup(page.content, 'html.parser')
h2 = soup.find_all('h2')
for i, h in enumerate(h2):
    print(i, 'what?',  h.text.replace('\n', ''))
