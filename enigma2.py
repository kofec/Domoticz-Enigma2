#!/usr/bin/python3
import argparse
import subprocess
import sys
import os
import time
from pathlib import Path

pathOfPackages = '/usr/local/lib/python3.5/dist-packages'

parser = argparse.ArgumentParser(description='Comunicate with Enigma2.')
parser.add_argument('IPaddress', help='IP address of Enigma2')
parser.add_argument('--port', help='Port number')
parser.add_argument('--user', help='Username to login to')
parser.add_argument('--password', help='Password to login to')

args = parser.parse_args()
print(args)
print("Current paths where search for modules: " + str(sys.path))

if Path(pathOfPackages).exists():
    print("Adding path: " + pathOfPackages)
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

try:
    subprocess.call(["bash", "--version"])
except OSError as e:
    if e.errno == os.errno.ENOENT:
        print("Cannot find wget command")
        exit()
    else:
        print("Error when checking if wget exist")
        raise

try:
    subprocess.call(["wget", "--version"])
except OSError as e:
    if e.errno == os.errno.ENOENT:
        print("Cannot find wget command")
        exit()
    else:
        print("Error when checking if wget exist")
        raise

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
print("Read data about tuner with Enigma2: ")
url = "http://"
if username and password:
    url += username + ':' + password + '@'
if port:
    url += addressIP + ":" + port + '/web/about'
else:
    url += addressIP + '/web/about'
print("Connect via wget to website: wget -q -O - " + url)
data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url])
print(data)
data = xmltodict.parse(data)
data = data["e2abouts"]["e2about"]
for x in data.keys():
    print(str(x) + " => " + str(data[x]))
print(data)
print("check power state: ")
url = "http://"
if username and password:
    url += username + ':' + password + '@'
if port:
    url += addressIP + ":" + port + '/web/powerstate?'
else:
    url += addressIP + '/web/powerstate?'
print("Connect via wget to website: wget -q -O - " + url)
data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url])
print(data)

data = xmltodict.parse(data)
data = data["e2powerstate"]
print(data)

url = "http://"
if username and password:
    url += username + ':' + password + '@'
if port:
    url += addressIP + ":" + port + '/web/powerstate?newstate=4'
else:
    url += addressIP + '/web/powerstate?newstate=4'
print("Wakeup form Standby: ")
print("Connect via wget to website: wget -q -O - " + url)
data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url])
print(data)
print("Wait 5 seconds")
time.sleep(5)
url = "http://"
if username and password:
    url += username + ':' + password + '@'
if port:
    url += addressIP + ":" + port + '/web/'
else:
    url += addressIP + '/web/'
url += 'message?text=Domoticz%20plugin%20test%0AYour%20Tuner%20will%0Abe%20off%20in%205%20seconds&type=1&timeout=5'
url = "\'" + url + "\'"
print("Connect via wget to website: wget -q -O - " + url)
data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url])
print(data)
print("Wait 5 seconds")
time.sleep(5)
url = "http://"
if username and password:
    url += username + ':' + password + '@'
if port:
    url += addressIP + ":" + port + '/web/powerstate?newstate=5'
else:
    url += addressIP + '/web/powerstate?newstate=5'
print("Standby: ")
print("Connect via wget to website: wget -q -O - " + url)
data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url])
print(data)
data = xmltodict.parse(data)
print(data)

