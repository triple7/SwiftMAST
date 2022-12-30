import requests as R
from bs4 import BeautifulSoup
import re
import sys

enumStub = "public enum MAST$:String, CaseIterable, Identifiable {\n"
idStub = """
public var id:String {
return self.rawValue
}
"""""

descStub = """
public var description:String {
switch self {
    $
}
}
"""

if __name__ == "__main__":
    # Service fields page
    name = sys.argv[1]
    url = sys.argv[2]
    page = R.get(url)
    soup = BeautifulSoup(page.content, 'html.parser')
    table = soup.find_all('table')
    rows = table[1].find_all('tr')
    rows = rows[1:]
    enumStub = enumStub.replace('$', name.capitalize())
    cases = ""
    for r in rows:
        c = [x.text.strip() for x in r.find_all('td')]
        cases += f'case {c[0]}\n'
    descs = ""
    for r in rows:
        c = [x.text.strip() for x in r.find_all('td')]
        descs += f'case .{c[0]}: return "{c[1]}"\n'
    print(enumStub, cases, idStub, descStub.replace('$', descs), '}\n')