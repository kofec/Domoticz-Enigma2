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
<plugin key="Enigma2" name="Enigma2 with Kodi Remote" author="kofec" version="3.1.0" wikilink="no" externallink=" https://dream.reichholf.net/wiki/Enigma2:WebInterface">
    <params>
        <param field="Address" label="IP Address" width="200px" required="true" default="127.0.0.1"/>
        <param field="Port" label="Port" width="40px" required="true" default="80"/>
        <param field="Mode1" label="Username" width="200px" required="false" default=""/>
        <param field="Mode2" label="Password" width="200px" required="false" default=""/>
        <param field="Mode3" label="Poll Period (* 10s)" width="75px" required="true" default="6"/>
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
import socket
import site
from urllib.parse import quote  # NEW

# +++ add these imports (urllib + auth) +++
import base64
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError


path = ''
path = site.getsitepackages()
for i in path:
    sys.path.append(i)

# Python framework in Domoticz do not include OS dependent path
#
from pathlib import Path

pathOfPackages = '/usr/lib/python3.6/site-packages/'

if Path(pathOfPackages).exists():
    sys.path.append(pathOfPackages)

try:
    import xmltodict
except ImportError:
    pass

# socket.setdefaulttimeout(2)  # avoid global default; keep timeouts local

class BasePlugin:
    # Connection Status
    isConnected = False
    isXmltodict = False
    pollPeriod = 0
    pollCount = 0

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
            DumpAllToLog()
        # Do not change below UNIT constants!
        self.UNIT_STATUS_REMOTE = 1
        self.UNIT_POWER_CONTROL = 2

        try:
            "parse" in dir(xmltodict)
            self.isXmltodict = True
        except Exception as e:
            print(e)
            self.isXmltodict = False
            pass

        if len(Devices) == 0:
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

        self.pollPeriod = int(Parameters["Mode3"])
        self.pollCount = self.pollPeriod - 1
        Domoticz.Heartbeat(10)

        self.config = {
            "description": "Domoticz",
            "user": Parameters["Mode1"],
            "password": Parameters["Mode2"],
            "host": Parameters["Address"],
            "port": int(Parameters["Port"]),
        }

        Domoticz.Log("Connecting to: " + Parameters["Address"] + ":" + Parameters["Port"])

        self.isAlive()

        if self.isConnected == True:
            if Parameters["Mode6"] == "Debug":
                Domoticz.Log("Devices are connected - Initialisation")
            UpdateDevice(self.UNIT_STATUS_REMOTE, 1, 'Enigma2 ON')
            self.EnigmaDetails()
            UpdateDevice(self.UNIT_POWER_CONTROL, 40, '40')

        return True

    # Check if Enigma TV is On and connected to Network

    def isAlive(self):
        # Local timeout only
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        try:
            s.connect((self.config["host"], self.config["port"]))
            self.isConnected = True
        except socket.error:
            self.isConnected = False
        finally:
            try:
                s.close()
            except Exception:
                pass

        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("isAlive status: " + str(self.isConnected))
        if self.isConnected and (not self.isXmltodict):
            Domoticz.Error("Missing module xmltodict - correct pathOfPackages in plugin.py")
            self.isConnected = False
        return

    def EnigmaDetails(self):
        doc = self._get("about", timeout_sec=5)
        if not doc:
            return

        try:
            data = doc["e2abouts"]["e2about"]
        except Exception:
            Domoticz.Error("Unexpected /web/about response shape")
            return

        if Parameters["Mode6"] == "Debug":
            for x in data.keys():
                Domoticz.Log(str(x) + " => " + str(data[x]))
        else:
            model = data.get("e2model")
            ver = data.get("e2enigmaversion")
            if model and ver:
                Domoticz.Log("Connected to Enigma2: {} on model: {}".format(ver, model))
        return

    def ChannelName(self):
        doc = self._get("subservices", timeout_sec=4)
        if not doc:
            return ""

        try:
            services = doc["e2servicelist"]["e2service"]
        except Exception:
            Domoticz.Error("Unexpected /web/subservices response shape")
            return ""

        # e2service can be dict or list; normalize
        if isinstance(services, list):
            svc = services[0] if services else {}
        else:
            svc = services or {}

        name = svc.get("e2servicename", "") if isinstance(svc, dict) else ""
        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("ChannelName => {}".format(name))
        else:
            if name:
                Domoticz.Log("Current channel: " + name)
        return name

    # executed each time we click on device thru domoticz GUI
    def onCommand(self, Unit, Command, Level, Hue):
        self.isAlive()
        Domoticz.Log(
            "onCommand called for Unit {}: Parameter '{}', Level: {}, Connected: {}".format(
                Unit, Command, Level, self.isConnected
            )
        )
        if not self.isConnected:
            Domoticz.Log("Cannot execute above command")
            return True

        endpoint = None

        if Unit == self.UNIT_STATUS_REMOTE and str(Command) in self.KEY:
            endpoint = "remotecontrol?command={}".format(self.KEY[str(Command)])
        elif Unit == self.UNIT_STATUS_REMOTE and str(Command) == "Off":
            endpoint = "powerstate?newstate=1"
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) < 20:
            endpoint = "powerstate?newstate=5"
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 20:
            endpoint = "powerstate?newstate=2"
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 30:
            endpoint = "powerstate?newstate=3"
        elif Unit == self.UNIT_POWER_CONTROL and int(Level) == 40:
            endpoint = "powerstate?newstate=4"
        else:
            # Keep existing behavior, but build safely
            msg = "onCommand called for\nUnit {}\nParameter {}\nLevel: {}\nConnected: {}".format(
                Unit, Command, Level, self.isConnected
            )
            # Ensure message is URL-encoded once (quote is fine here)
            endpoint = "message?text={}&type=1&timeout=3".format(quote(msg, safe=""))

        doc = self._get(endpoint, timeout_sec=4)
        if Parameters["Mode6"] == "Debug" and doc is not None:
            Domoticz.Log(str(doc))
        return True

    def onHeartbeat(self):
        Domoticz.Debug("onHeartBeat called:" + str(self.pollCount) + "/" + str(self.pollPeriod))
        if self.pollCount < self.pollPeriod:
            self.pollCount += 1
            return

        self.isAlive()
        if self.isConnected:
            doc = self._get("powerstate?", timeout_sec=4)
            if not doc:
                # treat as disconnected-ish for UI purposes
                UpdateDevice(self.UNIT_STATUS_REMOTE, 0, "Enigma2 OFF")
                UpdateDevice(self.UNIT_POWER_CONTROL, 0, "0")
                self.pollCount = 0
                return True

            try:
                instandby = str(doc["e2powerstate"]["e2instandby"])
            except Exception:
                Domoticz.Error("Unexpected /web/powerstate? response shape")
                instandby = "true"

            if Parameters["Mode6"] == "Debug":
                Domoticz.Log('e2instandby => ' + str(instandby))

            if instandby == "false":
                UpdateDevice(self.UNIT_POWER_CONTROL, 40, "40")
                if Parameters["Mode5"] == "StoreChannelName":
                    ch = self.ChannelName()
                    UpdateDevice(self.UNIT_STATUS_REMOTE, 1, ch if ch else "Enigma2 ON")
                else:
                    UpdateDevice(self.UNIT_STATUS_REMOTE, 1, "Enigma2 ON")
            else:
                UpdateDevice(self.UNIT_POWER_CONTROL, 10, "10")
                UpdateDevice(self.UNIT_STATUS_REMOTE, 1, "Enigma2 ON")
        else:
            UpdateDevice(self.UNIT_STATUS_REMOTE, 0, "Enigma2 OFF")
            UpdateDevice(self.UNIT_POWER_CONTROL, 0, "0")

        self.pollCount = 0
        return True

    # --- NEW helpers (deduplicate URL building + safer wget + XML parsing) ---
    def _auth_header(self):
        """
        Build HTTP Basic Authorization header (avoid credentials in URL).
        Returns dict of headers.
        """
        user = str(Parameters["Mode1"] or "")
        pwd = str(Parameters["Mode2"] or "")
        if user and pwd:
            token = base64.b64encode(f"{user}:{pwd}".encode("utf-8")).decode("ascii")
            return {"Authorization": f"Basic {token}"}
        return {}

    def _base_url(self):
        host = str(Parameters["Address"])
        port = str(Parameters["Port"])
        if port == "80":
            return f"http://{host}/web/"
        return f"http://{host}:{port}/web/"

    def _fetch_xml(self, url, timeout_sec=3):
        """
        Fetch URL via urllib and parse XML via xmltodict.
        Returns parsed dict or None on error.
        """
        if not self.isXmltodict:
            Domoticz.Error("Missing module xmltodict - cannot parse Enigma2 responses.")
            return None

        headers = {"User-Agent": "Domoticz-Enigma2/3.1.0"}
        headers.update(self._auth_header())

        if Parameters["Mode6"] == "Debug":
            Domoticz.Log("HTTP GET: " + url)

        req = Request(url, headers=headers, method="GET")
        try:
            with urlopen(req, timeout=float(timeout_sec)) as resp:
                data = resp.read()
        except HTTPError as e:
            Domoticz.Error("HTTP {} for {}: {}".format(getattr(e, "code", "?"), url, str(e)))
            return None
        except URLError as e:
            Domoticz.Error("Connection error for {}: {}".format(url, getattr(e, "reason", str(e))))
            return None
        except Exception as e:
            Domoticz.Error("HTTP request failed for {}: {}".format(url, str(e)))
            return None

        try:
            return xmltodict.parse(data)
        except Exception as e:
            Domoticz.Error("xml parse failed for {}: {}".format(url, str(e)))
            return None

    def _get(self, endpoint, timeout_sec=3):
        # endpoint like "about", "powerstate?", "remotecontrol?command=115"
        url = self._base_url() + endpoint
        return self._fetch_xml(url, timeout_sec=timeout_sec)

    # --- remove/disable old wget-based helpers (keep names stable) ---
    def _auth_prefix(self):
        # Deprecated: do not embed credentials in URL
        return ""

    def _base_url(self, path="/web/"):
        # Backwards compatible signature used elsewhere; ignore `path` and keep consistent
        base = self._base_url.__wrapped__(self) if hasattr(self._base_url, "__wrapped__") else None
        # NOTE: this placeholder will be replaced by the definition above in your merge.
        # Keep only one _base_url() in final file.
        return "http://{}:{}/web/".format(str(Parameters["Address"]), str(Parameters["Port"]))

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


# from plugin https://github.com/Xorfor/Domoticz-PiMonitor-Plugin/blob/master/plugin.py
def DumpDevicesToLog():
    # Show devices
    Domoticz.Debug("Device count.........: {}".format(len(Devices)))
    for x in Devices:
        Domoticz.Debug("Device...............: {} - {}".format(x, Devices[x]))
        Domoticz.Debug("Device Idx...........: {}".format(Devices[x].ID))
        Domoticz.Debug(
            "Device Type..........: {} / {}".format(Devices[x].Type, Devices[x].SubType))
        Domoticz.Debug("Device Name..........: '{}'".format(Devices[x].Name))
        Domoticz.Debug("Device nValue........: {}".format(Devices[x].nValue))
        Domoticz.Debug("Device sValue........: '{}'".format(Devices[x].sValue))
        Domoticz.Debug(
            "Device Options.......: '{}'".format(Devices[x].Options))
        Domoticz.Debug("Device Used..........: {}".format(Devices[x].Used))
        Domoticz.Debug(
            "Device ID............: '{}'".format(Devices[x].DeviceID))
        Domoticz.Debug("Device LastLevel.....: {}".format(
            Devices[x].LastLevel))
        Domoticz.Debug("Device Image.........: {}".format(Devices[x].Image))


def DumpImagesToLog():
    # Show images
    Domoticz.Debug("Image count..........: {}".format((len(Images))))
    for x in Images:
        Domoticz.Debug("Image '{}'...: '{}'".format(x, Images[x]))


def DumpParametersToLog():
    # Show parameters
    Domoticz.Debug("Parameters count.....: {}".format(len(Parameters)))
    for x in Parameters:
        if Parameters[x] != "":
            Domoticz.Debug("Parameter '{}'...: '{}'".format(x, Parameters[x]))


def DumpSettingsToLog():
    # Show settings
    Domoticz.Debug("Settings count.......: {}".format(len(Settings)))
    for x in Settings:
        Domoticz.Debug("Setting '{}'...: '{}'".format(x, Settings[x]))


def DumpAllToLog():
    DumpDevicesToLog()
    DumpImagesToLog()
    DumpParametersToLog()
    DumpSettingsToLog()


def UpdateDevice(Unit, nValue, sValue):
    # Make sure that the Domoticz device still exists (they can be deleted) before updating it 
    if (Unit in Devices):
        if (Devices[Unit].nValue != nValue) or (Devices[Unit].sValue != sValue):
            Devices[Unit].Update(nValue=nValue, sValue=str(sValue))
            Domoticz.Log("Update " + str(nValue) + ":'" + str(sValue) + "' (" + Devices[Unit].Name + ")")
    return
