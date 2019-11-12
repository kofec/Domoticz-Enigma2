# Domoticz-Enigma2
A Python plugin for Domoticz to control Enigma2 tuner 

* Based on repository https://github.com/lrybak/domoticz-airly/
* and script for Samsung TV: https://www.domoticz.com/wiki/Plugins/SamsungTV.html

## Installation
```
pip3 install -U xmltodict
```
* Make sure your Domoticz instance supports Domoticz Plugin System - see more https://www.domoticz.com/wiki/Using_Python_plugins

* Get plugin data into DOMOTICZ/plugins directory
```
cd YOUR_DOMOTICZ_PATH/plugins
git clone https://github.com/kofec/Domoticz-Enigma2
```
First use script "tinycontrol.py" to verify if you have needed python modules
e.g: 
```
 ./enigma2.py 192.168.1.1
 ./enigma2.py -h
usage: enigma2.py [-h] [--user USER] [--password PASSWORD] IPaddress

Comunicate with Enigma2.

positional arguments:
  IPaddress            IP address of Enigma2

optional arguments:
  -h, --help           show this help message and exit
  --user USER          Username to login to
  --password PASSWORD  Password to login to
```
* check where modules was installed and in file plugin.py find and correct below variable if needed
pathOfPackages = '/usr/local/lib/python3.5/dist-packages'

Restart Domoticz
* Go to Setup > Hardware and create new Hardware with type: Enigma2 with Kodi Remote
* Enter name (it's up to you), user name and password if define. If not leave it blank

## Update
```
cd YOUR_DOMOTICZ_PATH/plugins/Domoticz-Enigma2
git pull
```
* Restart Domoticz

## Troubleshooting

In case of issues, mostly plugin not visible on plugin list, check logs if plugin system is working correctly. See Domoticz wiki for resolution of most typical installation issues http://www.domoticz.com/wiki/Linux#Problems_locating_Python
