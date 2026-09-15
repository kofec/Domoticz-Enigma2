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
* IP Address: `192.168.1.41`, or `192.168.1.41:8080` when the web interface is not on port 80

## nBox monitor devices (optional)
With **nBox monitor devices: Yes** the plugin additionally creates devices for
[nbox_monitor.sh](#nbox-monitor-script-running-on-the-box), a monitoring script
running on the box itself (signal, OSCam, disk, RAM, CPU):

| Unit | Device | Type |
|---|---|---|
| 3 | Last event | Text |
| 4 | SNR | Percentage |
| 5 | Signal | Percentage |
| 6 | BER | Custom |
| 7 | ECM time | Custom (ms) |
| 8 | OSCam errors | Custom |
| 9 | Root FS | Percentage |
| 10 | HDD usage | Percentage |
| 11 | RAM | Percentage |
| 12 | CPU | Percentage |
| 13 | HDD temperature | Temperature |

The plugin only creates them; the script on the box pushes the values with
`json.htm?type=command&param=udevice&idx=...`. After the start the Domoticz log
shows a ready line with the idx of each device, e.g.
`nbox_monitor.conf: DZ_ZDARZENIE=301 DZ_SNR=302 ...`.
Switching the option back to **No** keeps the devices and their history;
delete them in Setup > Devices if not needed.

## nBox monitor (script running on the box)
[nbox/](nbox/) holds a watchdog for Enigma2 receivers with OSCam, written and
tested on nBox ADB 5800SX with GraterliaOS (busybox 1.28, sh4, Python 2.7).
It runs **on the box**, not in Domoticz, samples every 10 s and answers the
question "why did the picture freeze?". Comments and TV messages are in
Polish. It replaces the old `enigma2_monitor.sh`.

| File | Purpose |
|---|---|
| [nbox_monitor.sh](nbox/nbox_monitor.sh) | the monitor (POSIX sh, busybox ash) |
| [nbox_sygnal.py](nbox/nbox_sygnal.py) | helper reading lock, SNR, signal and BER straight from the tuner driver (ioctl); started by the monitor |
| [nbox_monitor.conf.example](nbox/nbox_monitor.conf.example) | configuration template for `/root/nbox_monitor.conf`, every option described |

### What it watches
| Event | Meaning |
|---|---|
| `STOP` | the tuner works but no new control word arrives (OSCam drops ECMs, or `/tmp/ecm.info` older than 30 s) - the picture freezes |
| `LOCK` | the tuner lost the satellite (no `FE_HAS_LOCK`) |
| `SYGNAL` | SNR below 50 % |
| `CZYTNIK` | the OSCam network reader is not `CONNECTED` for two samples |
| `OSCAM`, `OSCAM-START` | errors in the OSCam log, an absurd ECM cycle, OSCam restarted |
| `ZEGAR` | OSCam started with a clock before 2020 - it can drop ECMs until the channel changes |
| `WEBIF` | the OSCam web interface or enigma2 does not respond |
| `ENIGMA` | enigma2 restarted (new PID) |
| `OBRAZ` | the tuner works, the decoder shows no picture |
| `SIEC`, `NAPRAWA`, `REBOOT` | network repair, see below |

Sources are local and cheap: `/proc`, `/tmp/ecm.info`, the OSCam web interface
(`oscamapi.html?part=status&appendlog=1`, port 8888) and the helper. OpenWebif
is only a fallback, because it runs inside the enigma2 process.

### What it does
- **TV message** (OpenWebif `/web/message`) for `STOP` and `LOCK` while the
  tuner is on, at most one per 10 minutes: the channel, the cause (card server,
  OSCam, decoder rejects keys) and whether to wait or to zap.
- **Domoticz** (optional): a notification "NAZWA: what happened" for `STOP`,
  `LOCK`, `CZYTNIK`, `WEBIF` and `ENIGMA` (retried when the network was down
  too), and every 60 s the values for the devices described above.
- **Logs**: samples and events in RAM (`/tmp/nbox_monitor/`), incident files
  with the context before and after on `/hdd/nbox_monitor/` - only for `STOP`,
  `LOCK` and `CZYTNIK`, so the disk is not woken up otherwise.
- **Network repair** - no pinging while everything works. When no OSCam
  reader has been connected for 40 s (control words from any reader mean the
  network works, even if another reader is down), the script pings the
  default gateway and an internet address (`8.8.8.8`, `1.1.1.1`) and checks
  the DHCP client:

  | Diagnosis | Action |
  |---|---|
  | DHCP, gateway or DHCP client dead | start `udhcpc` again |
  | static address, gateway dead | `/etc/init.d/network restart` |
  | gateway ok, internet down | none - the problem is beyond the gateway |
  | gateway and internet ok | none - card server or DNS |

  After an hour without gateway or internet (`REBOOT_PO`) the box reboots.
  `RELAY_ADDRESS` (a second static address, e.g. for a box behind relayd) and
  `TRASY` (static routes) are added back whenever they disappear.
  `NAPRAWA=0` turns every change off and leaves pure monitoring.

### Installation
1. Copy both scripts to `/root/` with Unix line endings (`scp -O`, or
   `cat nbox_monitor.sh | ssh root@box 'cat > /root/nbox_monitor.sh'`) and
   `chmod 755 /root/nbox_monitor.sh`.
2. Optionally create `/root/nbox_monitor.conf` from the template: at least
   `NAZWA`, plus `DOMOTICZ_HOST` and the `DZ_*` idx for Domoticz, and
   `RELAY_ADDRESS` / `TRASY` if the box needs them.
3. Check the box without changing anything: `sh /root/nbox_monitor.sh --raz`
   (network diagnosis included).
4. Test the TV message and Domoticz: `--test-tv`, `--test-domoticz`.
5. Start it at boot - at the end of `/etc/rc.local`:
   ```sh
   nohup /root/nbox_monitor.sh >/dev/null 2>&1 &
   ```
   Recommended next to it against the `ZEGAR` problem - one OSCam restart
   once the clock is set:
   ```sh
   ( while [ $(date +%Y) -lt 2020 ]; do sleep 5; done; sleep 30; /etc/init.d/softcam restart ) &
   ```

Other options: `--raz --pokaz-incydent` (what an incident file would contain
right now), `--bez-domoticz`, `-h`.

## Update
```
cd YOUR_DOMOTICZ_PATH/plugins/Domoticz-Enigma2
git pull
```
* Restart Domoticz

### From 3.1 to 3.2
The separate **Port** field became **nBox monitor devices**. An existing
hardware keeps working on its old port until it is saved again - before saving,
put a non-80 port into the address field (`host:port`).

## Troubleshooting

In case of issues, mostly plugin not visible on plugin list, check logs if plugin system is working correctly. See Domoticz wiki for resolution of most typical installation issues http://www.domoticz.com/wiki/Linux#Problems_locating_Python
