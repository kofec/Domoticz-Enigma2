#!/usr/bin/python3
import urllib.request
import sys
from pathlib import Path

pathOfPackages='/usr/local/lib/python3.5/dist-packages'

if Path(pathOfPackages).exists():
    sys.path.append('/usr/local/lib/python3.5/dist-packages')
    import xmltodict
else:
    Print("It can be an issue with import package xmltodict")
    Print("Find where is located package xmltodict and correct variable:")
    Print("pathOfPackages:", pathOfPackages)
    import xmltodict

addressIP = "127.0.0.1"
username = ""
password = ""

#print(len(sys.argv))
if len(sys.argv) == 2:
    print("Usage: python " + sys.argv[0] + " IPaddress user password")
    print('Number of arguments:', len(sys.argv), 'arguments.')
    print('Argument List:', str(sys.argv))
    print('Ony IP arguments provide so admin and password are empty')
    addressIP = str(sys.argv[1])
    print("address IP:", addressIP)
    print("username:", username)
    print("password:", password)
elif len(sys.argv) != 4:
    print("Usage: python " + sys.argv[0] + " IPaddress user password")
    print('Number of arguments:', len(sys.argv), 'arguments.')
    print('Argument List:', str(sys.argv))
    print('No all arguments provide so take these from script')
    print("address IP:", addressIP)
    print("username:", username)
    print("password:", password)
else:
     addressIP = str(sys.argv[1])
     username = str(sys.argv[2])
     password = str(sys.argv[3])
     print("address IP:", addressIP)
     print("username:", username)
     print("password:", password)

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
urll = 'http://' + addressIP + '/web/about'
# create a password manager
passman = urllib.request.HTTPPasswordMgrWithDefaultRealm()
# Add the username and password.
# If we knew the realm, we could use it instead of None.
passman.add_password(None, urll, username, password)

authhandler = urllib.request.HTTPBasicAuthHandler(passman)
# create "opener" (OpenerDirector instance)
opener = urllib.request.build_opener(authhandler)
# use the opener to fetch a URL
pagehandle = opener.open(urll)

data = pagehandle.read()
pagehandle.close()
print (data)

data = xmltodict.parse(data)
data = data["e2abouts"]["e2about"]
for x in data.keys():
    print(str(x) +" => " + str(data[x]))
print(data)

urll = 'http://' + addressIP + '/web/powerstate?'
# create a password manager
passman = urllib.request.HTTPPasswordMgrWithDefaultRealm()
# Add the username and password.
# If we knew the realm, we could use it instead of None.
passman.add_password(None, urll, username, password)

authhandler = urllib.request.HTTPBasicAuthHandler(passman)
# create "opener" (OpenerDirector instance)
opener = urllib.request.build_opener(authhandler)
# use the opener to fetch a URL
pagehandle = opener.open(urll)

data = pagehandle.read()
pagehandle.close()
print(data)

data = xmltodict.parse(data)
data = data["e2powerstate"]
print(data)

#urll = 'http://' + addressIP + '/web/powerstate?newstate=5'
passman.add_password(None, urll, username, password)

authhandler = urllib.request.HTTPBasicAuthHandler(passman)
# create "opener" (OpenerDirector instance)
opener = urllib.request.build_opener(authhandler)
# use the opener to fetch a URL
pagehandle = opener.open(urll)

data = pagehandle.read()
pagehandle.close()
print (data)

urll = 'http://192.168.1.41/web/powerstate?'
# create a password manager
passman = urllib.request.HTTPPasswordMgrWithDefaultRealm()
# Add the username and password.
# If we knew the realm, we could use it instead of None.
passman.add_password(None, urll, username, password)

authhandler = urllib.request.HTTPBasicAuthHandler(passman)
# create "opener" (OpenerDirector instance)
opener = urllib.request.build_opener(authhandler)
# use the opener to fetch a URL
pagehandle = opener.open(urll)

data = pagehandle.read()
pagehandle.close()
print (data)

data = xmltodict.parse(data)
print(data)

#urll = 'http://' + addressIP + '/web/powerstate?newstate=4'
passman.add_password(None, urll, username, password)

authhandler = urllib.request.HTTPBasicAuthHandler(passman)
# create "opener" (OpenerDirector instance)
opener = urllib.request.build_opener(authhandler)
# use the opener to fetch a URL
pagehandle = opener.open(urll)

data = pagehandle.read()
pagehandle.close()
print (data)

