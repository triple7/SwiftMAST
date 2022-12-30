import requests as R
from bs4 import BeautifulSoup
import re
import numpy as np

URL = "https://archive.stsci.edu/vo/mast_services.html#GET"
page = R.get(URL)
soup = BeautifulSoup(page.content, 'html.parser')
li = soup.find_all('li')
found=False
end = False
output = []
for i, l in enumerate(li):
    if found:
        if not end:
            if 'Swift UV/optical Telescope' not in l.text:
                output.append(l.text)
            end = True
            output.append(l.text)
    if 'HST tables' in l.text:
        found = True
        output.append(l.text)

output = [o.split('\n') for o in output]
output = np.array(output)
output = output.reshape(-1)
output = np.unique(output)
output = output[0]+output[1]

output = [o.split(' - ') for o in output if o != '']
output = [[o[0].strip(), o[1].strip()] for o in output if len(o) == 2]
final = []
for o in output:
    if o not in final:
        final.append(o)

header = "public enum MASTDataSet:String, CaseIterable, Identifiable {\n"
cases = '\n'.join([f'case {o[0]} /* {o[1]} */' for o in final])
caseDesc = '\n'.join([f'case .{o[0]}: return "{o[1]}"' for o in final])
desc = "public var description:String {\nswitch self {\n"
print(header, cases, '\n', '}\n\n', desc, caseDesc, '\n', '}\n')