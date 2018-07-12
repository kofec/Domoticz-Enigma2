#           Enigma2 Python Plugin for Domoticz
#
#           keys code :  https://dream.reichholf.net/wiki/Enigma2:WebInterface
#           Dev. Platform : Raspberry Pi 1 & Py 3.5.3 Arm
#
#           Author:     kofec, 2017
#           1.0.0:  initial release
#           2.0.0:  Added Remote control Kodi like (customizable)
#           2.0.1:  clean code and change to wget
#           3.0.0:  add support for channel name
#       
#           Base on website: https://dream.reichholf.net/wiki/Enigma2:WebInterface
#           Miscellaneous
#           Requests:
#           
#               http://dreambox/web/updates.html
#               http://dreambox/web/movielist
#               http://dreambox/web/powerstate? to check Powerstate
#               http://dreambox/web/powerstate?newstate={powerstate_number}
#               0 = Toogle Standby
#               1 = Deepstandby
#               2 = Reboot
#               3 = Restart Enigma2
#               4 = Wakeup form Standby
#               5 = Standby
#           
#               RemoteControl
#               Requests:
#               
#               http://dreambox/web/remotecontrol?command={command}
#               result:
#               
#               <e2remotecontrol>
#                      <e2result>True</e2result>
#                      <e2resulttext>command was was sent</e2resulttext>
#               </e2remotecontrol>
#               {Command} is (slight differences to the Enigma1 WebIF):
#               
#               116 Key "Power"	
#               2   Key "1"	 
#               3   Key "2"	
#               4   Key "3"	
#               5   Key "4"	
#               6   Key "5"	
#               7   Key "6"	
#               8   Key "7"	
#               9   Key "8"	
#               10  Key "1"	
#               11  Key "0"	
#               412 Key "previous"	
#               407 Key "next	
#               115 Key "volume up"	
#               113 Key "mute"	
#               402 Key "bouquet up"	
#               114 Key "volume down"	
#               174 Key "lame"	
#               403 Key "bouquet down"	
#               358 Key "info"	
#               103 Key "up"	
#               139 Key "menu"	
#               105 Key "left"	
#               352 Key "OK"	
#               106 Key "right"	
#               392 Key "audio"	
#               108 Key "down"	
#               393 Key "video"	
#               398 Key "red"	
#               399 Key "green"	
#               400 Key "yellow"	
#               401 Key "blue"	
#               377 Key "tv"	
#               385 Key "radio"	
#               388 Key "text"	
#               138 Key "help"	 


# Below is what will be displayed in Domoticz GUI under HW
#
"""
<plugin key="Enigma2" name="Enigma2 with Kodi Remote" author="kofec" version="3.0.0" wikilink="no" externallink=" https://dream.reichholf.net/wiki/Enigma2:WebInterface">
    <params>
        <param field="Address" label="IP Address" width="200px" required="true" default="127.0.0.1"/>
        <param field="Port" label="Port" width="40px" required="true" default="80"/>
        <param field="Mode1" label="Username" width="200px" required="false" default=""/>
        <param field="Mode2" label="Password" width="200px" required="false" default=""/>
        <param field="Mode5" label="Store Channel Name" width="75px">
            <options>
                <option label="Yes" value="StoreChannelName"/>
                <option label="No" value="NoStoreChannelName"  default="No" />
            </options>
        </param>
        <param field="Mode6" label="Debug" width="75px">
            <options>
                <option label="True" value="Debug"/>
                <option label="False" value="Normal"  default="True" />
            </options>
        </param>
    </params>
</plugin>
"""
#
# Main Import
import Domoticz
import sys
import os
import socket
import subprocess

# Python framework in Domoticz do not include OS dependent path
#
from pathlib import Path

pathOfPackages = '/usr/lib/python3.6/site-packages/'

if Path(pathOfPackages).exists():
    sys.path.append(pathOfPackages)
    import xmltodict
else:
    Domoticz.Log("It can be an issue with import package xmltodict")
    Domoticz.Log("Find where is located package xmltodict and correct variable: pathOfPackages")
    Domoticz.Log("pathOfPackages:", pathOfPackages)
    import xmltodict

socket.setdefaulttimeout(2)


class BasePlugin:
    # Connection Status
    isConnected = False
    KEY = {
        #             : 116,    # Key "Power"
        #             : 2,      # Key "1"
        #             : 3,      # Key "2"
        #             : 4,      # Key "3"
        #             : 5,      # Key "4"
        #             : 6,      # Key "5"
        #             : 7,      # Key "6"
        #             : 8,      # Key "7"
        #             : 9,      # Key "8"
        #             : 10,     # Key "1"
        #             : 11,     # Key "0"
        #             : 412,   # Key "previous#"
        #             : 407,   # Key "next
        "VolumeUp": 115,  # Key "volume up"
        "Mute": 113,  # Key "mute"
        "ChannelUp": 402,  # Key "bouquet up"
        "VolumeDown": 114,  # Key "volume down"
        #              : 174,   # Key "lame"
        "ChannelDown": 403,  # Key "bouquet down"
        "Info": 358,  # Key "info"
        "Up": 103,  # Key "up"
        "ContextMenu": 139,  # Key "menu"
        "Left": 105,  # Key "left"
        "Select": 352,  # Key "OK"
        "Right": 106,  # Key "right"
        #              : 392,   # Key "audio"
        "Down": 108,  # Key "down"
        #              : 393,   # Key "video"
        #              : 398,   # Key "red"
        #              : 399,   # Key "green"
        #              : 400,   # Key "yellow"
        #              : 401,   # Key "blue"
        #              : 377,   # Key "tv"
        #              : 385,   # Key "radio"
        #              : 388,   # Key "text"
        #              : 138,   # Key "help"
    }
    config = ''

    # Domoticz call back functions
    #

    # Executed once at HW creation/ update. Can create up to 255 devices.
    def onStart(self):
        if Parameters["Mode6"] == "Debug":
            Domoticz.Debugging(1)
            DumpConfigToLog()

        # Do not change below UNIT constants!
        self.UNIT_STATUS_REMOTE = 1
        self.UNIT_POWER_CONTROL = 2

        if (len(Devices) == 0):
            Domoticz.Device(Name="Status", Unit=self.UNIT_STATUS_REMOTE, Type=17, Image=2, Switchtype=17).Create()
            Options = {"LevelActions": "||||",
                       "LevelNames": "Off|Standby|Reboot|RestartE2|On",
                       "LevelOffHidden": "true",
                       "SelectorStyle": "0"
                       }
            Domoticz.Device(Name="Source", Unit=self.UNIT_POWER_CONTROL, TypeName="Selector Switch", Switchtype=18,
                            Image=12,
                            Options=Options).Create()
            Domoticz.Log("Devices created.")

        Domoticz.Heartbeat(60)

        self.config = {
            "description": "Domoticz",
            "user": Parameters["Mode1"],
            "password": Parameters["Mode2"],
            "host": Parameters["Address"],
            "port": int(Parameters["Port"]),
        }

        Domoticz.Log("Connecting to: " + Parameters["Address"] + ":" + Parameters["Port"])

        self.isAlive()

        if (self.isConnected == True):
            if Parameters["Mode6"] == "Debug":
                Domoticz.Log("Devices are connected - Initialisation")
            UpdateDevice(self.UNIT_STATUS_REMOTE, 1, 'Enigma2 ON')
            self.EnigmaDetails()
            UpdateDevice(self.UNIT_POWER_CONTROL, 40, '40')

        return True

    # Check if Samsung TV is On and connected to Network
    # Need to do in this way as TV accept connection and disconnect immediately
    def isAlive(self):
        socket.setdefaulttimeout(1)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.connect((self.config["host"], self.config["port"]))
            self.isConnected = True
        except socket.error as e:
            self.isConnected = False
        s.close()
        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("isAlive status: " + str(self.isConnected))

        return

    def EnigmaDetails(self):
        username = str(Parameters["Mode1"])
        password = str(Parameters["Mode2"])
        url = "http://"
        if username and password:
            url += username + ':' + password + '@'
        url += str(Parameters["Address"]) + '/web/about'
        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("Connect via wget to website: " + url)
        data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url], cwd=Parameters["HomeFolder"])
        data = xmltodict.parse(data)
        data = data["e2abouts"]["e2about"]
        if Parameters["Mode6"] == "Debug":
            for x in data.keys():
                Domoticz.Log(str(x) + " => " + str(data[x]))
        else:
            if data["e2model"] and data["e2enigmaversion"]:
                Domoticz.Log('Connected to Enigma2: ' + data["e2enigmaversion"] + ' on model: ' + data["e2model"])
        return

    def ChannelName(self):
        username = str(Parameters["Mode1"])
        password = str(Parameters["Mode2"])
        url = "http://"
        if username and password:
            url += username + ':' + password + '@'
        url += str(Parameters["Address"]) + '/web/subservices'
        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("Connect via wget to website: " + url)
        data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url], cwd=Parameters["HomeFolder"])
        data = xmltodict.parse(data)
        data = data["e2servicelist"]["e2service"]
        if Parameters["Mode6"] == "Debug":
            for x in data.keys():
                Domoticz.Log(str(x) + " => " + str(data[x]))
        else:
            if data["e2servicename"]:
                Domoticz.Log('Current channel: ' + data["e2servicename"])
        return data["e2servicename"]

    # executed each time we click on device thru domoticz GUI
    def onCommand(self, Unit, Command, Level, Hue):
        Domoticz.Log("onCommand called for Unit " + str(Unit) + ": Parameter '" + str(Command) + "', Level: " + str(
            Level) + ", Connected: " + str(self.isConnected))

        username = str(Parameters["Mode1"])
        password = str(Parameters["Mode2"])
        url = "http://"
        if username and password:
            url += username + ':' + password + '@'
        url += str(Parameters["Address"]) + '/web/'

        if Unit == self.UNIT_STATUS_REMOTE and str(Command) in self.KEY:
            url += 'remotecontrol?command=' + str(self.KEY[str(Command)])
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) < 20:
            url += 'powerstate?newstate=5'
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 20:
            url += 'powerstate?newstate=2'
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 30:
            url += 'powerstate?newstate=3'
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 40:
            url += 'powerstate?newstate=4'
        else:
            url += 'message?text=onCommand%20called%20for%0AUnit' + str(Unit) + '%0AParameter%20' + str(
                Command) + '%0ALevel:%20' + str(Level) + '%0AConnected:%20' + str(
                self.isConnected) + '&type=1&timeout=3'
            url = "\'" + url + "\'"

        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("Connect via wget to website: " + url)
        data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url], cwd=Parameters["HomeFolder"])
        data = xmltodict.parse(data)
        if Parameters["Mode6"] == "Debug":
            Domoticz.Log(str(data))
        return True

    def onHeartbeat(self):
        Domoticz.Log("onHeartbeat called")
        self.isAlive()
        if (self.isConnected == True):
            username = str(Parameters["Mode1"])
            password = str(Parameters["Mode2"])
            url = "http://"
            if username and password:
                url += username + ':' + password + '@'
            url += str(Parameters["Address"]) + '/web/powerstate?'
            if Parameters["Mode6"] == "Debug":
                Domoticz.Log("Connect via wget to website: " + url)
            data = subprocess.check_output(['bash', '-c', 'wget -q -O - ' + url], cwd=Parameters["HomeFolder"])
            data = xmltodict.parse(data)
            data = str(data["e2powerstate"]["e2instandby"])
            if Parameters["Mode6"] == "Debug":
                Domoticz.Log('data["e2powerstate"]["e2instandby"] => ' + str(data))
            if data == "false":
                UpdateDevice(self.UNIT_POWER_CONTROL, 40, '40')
                if Parameters["Mode5"] == "StoreChannelName":
                    UpdateDevice(self.UNIT_STATUS_REMOTE, 1, str(self.ChannelName()))
                else:
                    UpdateDevice(self.UNIT_STATUS_REMOTE, 1, 'Enigma2 ON')
            else:
                UpdateDevice(self.UNIT_POWER_CONTROL, 10, '10')
                UpdateDevice(self.UNIT_STATUS_REMOTE, 1, 'Enigma2 ON')
        else:
            UpdateDevice(self.UNIT_STATUS_REMOTE, 0, 'Enigma2 OFF')
            UpdateDevice(self.UNIT_POWER_CONTROL, 0, '0')
        return True

    def onConnect(self, Status, Description):
        Domoticz.Log("onConnect called")
        return

    def onMessage(self, Data, Status, Extra):
        Domoticz.Log("onMessage called")
        return

    def onNotification(self, Name, Subject, Text, Status, Priority, Sound, ImageFile):
        Domoticz.Log("Notification: " + Name + "," + Subject + "," + Text + "," + Status + "," + str(
            Priority) + "," + Sound + "," + ImageFile)
        return

    def onDisconnect(self, Connection):
        Domoticz.Log("Device has disconnected")
        return

    def onStop(self):
        Domoticz.Log("onStop called")
        return True


################ base on example ######################
global _plugin
_plugin = BasePlugin()


def onStart():
    global _plugin
    _plugin.onStart()


def onStop():
    global _plugin
    _plugin.onStop()


def onConnect(Connection, Status, Description):
    global _plugin
    _plugin.onConnect(Connection, Status, Description)


def onMessage(Connection, Data):
    global _plugin
    _plugin.onMessage(Connection, Data)


def onCommand(Unit, Command, Level, Hue):
    global _plugin
    _plugin.onCommand(Unit, Command, Level, Hue)


def onNotification(Name, Subject, Text, Status, Priority, Sound, ImageFile):
    global _plugin
    _plugin.onNotification(Name, Subject, Text, Status, Priority, Sound, ImageFile)


def onDisconnect(Connection):
    global _plugin
    _plugin.onDisconnect(Connection)


def onHeartbeat():
    global _plugin
    _plugin.onHeartbeat()


# Generic helper functions
def DumpConfigToLog():
    for x in Parameters:
        if Parameters[x] != "":
            Domoticz.Debug("'" + x + "':'" + str(Parameters[x]) + "'")
    Domoticz.Debug("Settings count: " + str(len(Settings)))
    for x in Settings:
        Domoticz.Debug("'" + x + "':'" + str(Settings[x]) + "'")
    Domoticz.Debug("Image count: " + str(len(Images)))
    for x in Images:
        Domoticz.Debug("'" + x + "':'" + str(Images[x]) + "'")
    Domoticz.Debug("Device count: " + str(len(Devices)))
    for x in Devices:
        Domoticz.Debug("Device:           " + str(x) + " - " + str(Devices[x]))
        Domoticz.Debug("Device ID:       '" + str(Devices[x].ID) + "'")
        Domoticz.Debug("Device Name:     '" + Devices[x].Name + "'")
        Domoticz.Debug("Device nValue:    " + str(Devices[x].nValue))
        Domoticz.Debug("Device sValue:   '" + Devices[x].sValue + "'")
        Domoticz.Debug("Device LastLevel: " + str(Devices[x].LastLevel))
        Domoticz.Debug("Device Image:     " + str(Devices[x].Image))
    return


def UpdateDevice(Unit, nValue, sValue):
    # Make sure that the Domoticz device still exists (they can be deleted) before updating it 
    if (Unit in Devices):
        if (Devices[Unit].nValue != nValue) or (Devices[Unit].sValue != sValue):
            Devices[Unit].Update(nValue=nValue, sValue=str(sValue))
            Domoticz.Log("Update " + str(nValue) + ":'" + str(sValue) + "' (" + Devices[Unit].Name + ")")
    return
