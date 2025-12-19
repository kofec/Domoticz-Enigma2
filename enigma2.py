#!/usr/bin/python3
import argparse
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

pathOfPackages = '/usr/local/lib/python3.5/dist-packages'

parser = argparse.ArgumentParser(description='Communicate with Enigma2.')
parser.add_argument('IPaddress', help='IP address of Enigma2')
parser.add_argument('--port', help='Port number')
parser.add_argument('--user', help='Username to login to')
parser.add_argument('--password', help='Password to login to')
parser.add_argument('--timeout', type=float, default=5.0, help='HTTP timeout in seconds (default: 5.0)')

args = parser.parse_args()

# Avoid dumping credentials to stdout by default
print(f"Target: {args.IPaddress}:{args.port or '80'} user={'set' if args.user else 'unset'}")

if Path(pathOfPackages).exists():
    sys.path.append(pathOfPackages)
    import xmltodict
else:
    print("It can be an issue with import package xmltodict")
    print("Find where is located package xmltodict and correct variable: pathOfPackages")
    print("pathOfPackages:", pathOfPackages)
    import xmltodict

addressIP = args.IPaddress
username = args.user
password = args.password
port = args.port
timeout = args.timeout

def _base_url() -> str:
    auth = ""
    if username and password:
        auth = f"{username}:{password}@"
    host = f"{addressIP}:{port}" if port else addressIP
    return f"http://{auth}{host}/web"

def _get_xml(endpoint: str, query: dict | None = None) -> dict:
    url = _base_url() + endpoint
    if query:
        url += "?" + urlencode(query, safe="%")
    req = Request(url, headers={"User-Agent": "Domoticz-Enigma2/1.0"})
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except HTTPError as e:
        raise RuntimeError(f"HTTP error {e.code} for {url}") from e
    except URLError as e:
        raise RuntimeError(f"Connection error for {url}: {e.reason}") from e

    try:
        return xmltodict.parse(raw)
    except Exception as e:
        # Keep raw out of logs by default; include size for debugging
        raise RuntimeError(f"Failed to parse XML from {url} (bytes={len(raw)})") from e

'''
Base on website: https://dream.reichholf.net/wiki/Enigma2:WebInterface
Miscellaneous
Requests:

    http://dreambox/web/updates.html
    http://dreambox/web/movielist
    http://dreambox/web/powerstate? to check Powerstate
    http://dreambox/web/powerstate?newstate={powerstate_number}
    0 = Toogle Standby
    1 = Deepstandby
    2 = Reboot
    3 = Restart Enigma2
    4 = Wakeup form Standby
    5 = Standby
'''
def main() -> int:
    print("Read data about tuner with Enigma2:")
    about = _get_xml("/about")
    data = about["e2abouts"]["e2about"]
    for k, v in data.items():
        print(f"{k} => {v}")

    print("Check power state:")
    pwr = _get_xml("/powerstate")
    print(pwr.get("e2powerstate", pwr))

    print("Wakeup from Standby:")
    _get_xml("/powerstate", {"newstate": 4})

    print("Wait 5 seconds")
    time.sleep(5)

    print("Send message:")
    _get_xml(
        "/message",
        {
            "text": "Domoticz plugin test\nYour Tuner will\nbe off in 5 seconds",
            "type": 1,
            "timeout": 5,
        },
    )

    print("Wait 5 seconds")
    time.sleep(5)

    print("Standby:")
    standby = _get_xml("/powerstate", {"newstate": 5})
    print(standby)
    time.sleep(5)
    print("Check power state:")
    pwr = _get_xml("/powerstate")
    print(pwr.get("e2powerstate", pwr))

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
