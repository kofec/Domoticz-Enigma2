# Domoticz-Enigma2
A Python plugin for Domoticz to control Enigma2 tuner 

* Based on repository https://github.com/lrybak/domoticz-airly/
* and script for Samsung TV: https://www.domoticz.com/wiki/Plugins/SamsungTV.html

## Installation

* Make sure your Domoticz instance supports Domoticz Plugin System - see more https://www.domoticz.com/wiki/Using_Python_plugins

* Get plugin data into DOMOTICZ/plugins directory
```
cd YOUR_DOMOTICZ_PATH/plugins
git clone https://github.com/kofec/Domoticz-Enigma2
```
Restart Domoticz
* Go to Setup > Hardware and create new Hardware with type: Domoticz-Enigma2
* Enter name (it's up to you), user name and password if define. If not leave it blank

## Update
```
cd YOUR_DOMOTICZ_PATH/plugins/Domoticz-Enigma2
git pull
```
* Restart Domoticz

## Troubleshooting

In case of issues, mostly plugin not visible on plugin list, check logs if plugin system is working correctly. See Domoticz wiki for resolution of most typical installation issues http://www.domoticz.com/wiki/Linux#Problems_locating_Python
