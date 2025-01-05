import requests
from bs4 import BeautifulSoup

def parse(url):
    try:
        # Send a GET request to the specified URL
        response = requests.get(url)
        response.raise_for_status()  
        # Parse the HTML content using BeautifulSoup
        soup = BeautifulSoup(response.content, 'html.parser')
        return soup
    except requests.exceptions.RequestException as e:
        print(f"An error occurred: {e}")
        return None


def run():
    soup = parse("https://hla.stsci.edu/fitscutcgi_interface.html")
    table = soup.find_all('table')[0]
    rows = table.find_all('tr')
    rows = rows[1:]
    output = {}
    for r in rows:
        cols = r.find_all('td')
        parameter = f"let {cols[0].text}:"
        desc = cols[1].text
        output[parameter] = desc

    print("public struct HLAParam:Codable {")
    for o in output:
        print(o)

    print("\n")
    print("var description:String {")
    print("switch self {")
    for o in output:
        print(f"case .{o}: return {output[o]}")
    print("}\n}")


if __name__ == "__main__":
    run()