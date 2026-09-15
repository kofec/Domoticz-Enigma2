#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
nbox_sygnal.py - sygnal z tunera nBoxa prosto z drajwera, bez OpenWebifu.

Pomocnik dla nbox_monitor.sh, ktory go uruchamia i czyta jego wynik z pliku.
Na boxie musi dzialac w Pythonie 2.7 (GraterliaOS), a przy tym przechodzic
py_compile z Pythona 3 - stad __future__ i brak konstrukcji tylko z jednej
wersji.

Dlaczego ioctl: na nBoxie (GraterliaOS, jadro STi 2.6.32) ani /proc, ani /sys
nie wystawiaja SNR/BER - /sys/class/dvb/dvb0.frontend0 ma tylko dev i uevent.
OpenWebif (/api/signal) pyta enigme, a enigma robi dokladnie te ioctl na
swoim deskryptorze - wiec pytanie OpenWebifu to CPU zabrane enigmie
(pomiar: ~70 ms na wywolanie). Tu robimy te same ioctl sami, na
drugim deskryptorze otwartym TYLKO DO ODCZYTU:
  - dvb-core pozwala na wielu czytelnikow obok enigmy (pisarz jest jeden),
  - czytelnikowi zezwala wylacznie na ioctl typu READ - nie da sie nim
    przestroic ani wybudzic tunera,
  - usypianie tunera w standby zalezy tylko od pisarza (enigmy), a frontend
    i tak otwieramy na chwile i tylko wtedy, gdy trzyma go enigma.

Sprawdzone na ADB 5800SX, TVN HD, w tej samej chwili:
  FE_READ_STATUS            0x1b  SIGNAL|CARRIER|SYNC|LOCK (VITERBI ten
                                  drajwer nie ustawia, wiec go nie wymagamy)
  FE_READ_SNR               65535 -> *100/65536 = 99  (OpenWebif "snr": 99)
  FE_READ_SIGNAL_STRENGTH   52428 -> *100/65536 = 79  (OpenWebif "agc": 79)
  FE_READ_BER               5                         (OpenWebif "ber": 0 -
                                  skala nieznana, dlatego tylko zapisujemy)
  FE_READ_UNCORRECTED_BLOCKS  EOPNOTSUPP - drajwer tego nie ma
Koszt: start Pythona ~1.3 s CPU, potem ~3.3 MB RSS, pojedynczy odczyt - ms.
Dlatego jeden staly proces, a nie python przy kazdej probce.

Wyjscie: co OKRES sekund jedna linia w /tmp/nbox_sygnal (zapis przez rename,
wiec czytajacy nigdy nie trafi na pol linii):
  <uptime> <frontend> <status_hex> <lock 0/1> <snr %> <sila %> <ber>
  <uptime> - - - - - -      gdy enigma nie trzyma frontendu (standby)

Uzycie:
  python nbox_sygnal.py [OKRES]   praca ciagla (uruchamia nbox_monitor.sh)
  python nbox_sygnal.py --raz     jeden odczyt na ekran, nic nie zapisuje;
                                  bez wgrywania: python - --raz < nbox_sygnal.py
"""
from __future__ import print_function

import fcntl
import os
import struct
import sys
import time

FE_READ_STATUS = 0x80046f45           # _IOR('o', 69, fe_status_t)
FE_READ_BER = 0x80046f46              # _IOR('o', 70, __u32)
FE_READ_SIGNAL_STRENGTH = 0x80026f47  # _IOR('o', 71, __u16)
FE_READ_SNR = 0x80026f48              # _IOR('o', 72, __u16)
FE_HAS_LOCK = 0x10

WYJSCIE = "/tmp/nbox_sygnal"
NAGLOWEK = "uptime frontend status lock snr% sila% ber"

_pid_enigmy = None


def uptime():
    with open("/proc/uptime") as f:
        return int(float(f.read().split()[0]))


def nazwa_procesu(pid):
    """Nazwa z /proc/PID/stat - /proc/PID/comm pojawilo sie dopiero w 2.6.33."""
    try:
        with open("/proc/%s/stat" % pid) as f:
            return f.read(64).split(" ", 2)[1]
    except (IOError, OSError, IndexError):
        return None


def pid_enigmy():
    global _pid_enigmy
    if _pid_enigmy and nazwa_procesu(_pid_enigmy) == "(enigma2)":
        return _pid_enigmy
    _pid_enigmy = None
    for pid in os.listdir("/proc"):
        if pid.isdigit() and nazwa_procesu(pid) == "(enigma2)":
            _pid_enigmy = pid
            break
    return _pid_enigmy


def frontend_enigmy():
    """Pierwszy /dev/dvb/adapter0/frontend* otwarty przez enigme albo None."""
    pid = pid_enigmy()
    if not pid:
        return None
    katalog = "/proc/%s/fd" % pid
    try:
        deskryptory = sorted(os.listdir(katalog), key=int)
    except OSError:
        return None
    for fd in deskryptory:
        try:
            cel = os.readlink(os.path.join(katalog, fd))
        except OSError:
            continue
        if cel.startswith("/dev/dvb/adapter0/frontend"):
            return cel
    return None


def ioctl_liczba(fd, zadanie, fmt):
    try:
        return struct.unpack(fmt, fcntl.ioctl(fd, zadanie, struct.pack(fmt, 0)))[0]
    except IOError:
        return None


def odczyt():
    frontend = frontend_enigmy()
    if not frontend:
        return None
    try:
        fd = os.open(frontend, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        status = ioctl_liczba(fd, FE_READ_STATUS, "=I")
        snr = ioctl_liczba(fd, FE_READ_SNR, "=H")
        sila = ioctl_liczba(fd, FE_READ_SIGNAL_STRENGTH, "=H")
        ber = ioctl_liczba(fd, FE_READ_BER, "=I")
    finally:
        os.close(fd)
    return frontend, status, snr, sila, ber


def procent(wartosc):
    """Surowe 0..65535 -> % tak samo jak w OpenWebif (65535 -> 99, 52428 -> 79)."""
    return "-" if wartosc is None else str(wartosc * 100 // 65536)


def linia():
    wynik = odczyt()
    if wynik is None:
        return "%d - - - - - -" % uptime()
    frontend, status, snr, sila, ber = wynik
    if status is None:
        status_txt, lock = "-", "-"
    else:
        status_txt = "0x%x" % status
        lock = "1" if status & FE_HAS_LOCK else "0"
    return "%d %s %s %s %s %s %s" % (
        uptime(), os.path.basename(frontend), status_txt, lock,
        procent(snr), procent(sila), "-" if ber is None else ber)


def zapisz(tekst):
    tymczasowy = WYJSCIE + ".tmp"
    with open(tymczasowy, "w") as f:
        f.write(tekst + "\n")
    os.rename(tymczasowy, WYJSCIE)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--raz":
        print(NAGLOWEK)
        print(linia())
        return 0
    okres = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    while True:
        try:
            zapisz(linia())
        except (IOError, OSError) as blad:
            sys.stderr.write("nbox_sygnal: %s\n" % blad)
        time.sleep(okres)


if __name__ == "__main__":
    sys.exit(main())
