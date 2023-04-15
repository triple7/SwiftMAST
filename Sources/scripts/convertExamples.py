import requests as R
from bs4 import BeautifulSoup
import re

url = "https://mast.stsci.edu/api/v0/pyex.html#MastCatalogsFilteredTicPy"
page = R.get(url)
soup = BeautifulSoup(page.content, 'html.parser')


def s(text):
    return text.replace('\n', '').strip()

h2 = soup.find_all('h2')
for i, h in enumerate(h2):
    print(i, h.text.replace('\n', ''))
    n = s(h.next)
