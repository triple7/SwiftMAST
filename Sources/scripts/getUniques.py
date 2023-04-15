import json as J
import numpy as np

json = None
with open('./coneSearch.json', 'r') as file:
    json = J.load(file)

input = json['json']
K = []
for i in input:
    for j in i:
        if j not in K:
            K.append(j)

uniques = {}
for k in K:
    u = []
    for i in input:
        if i[k] not in u:
            u.append(i[k])
    uniques[k] = u

header = "public enum SearchResultField:String, Identifiable, CaseIterable {\n"
cases = '\n'.join(f'case {k}' for k in K)
print(header, cases, '\n', '}')