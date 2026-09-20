#!/bin/sh
#
# nbox_monitor.sh - czujka zatrzyman obrazu na dekoderze Enigma2 z oscamem
# (nBox ADB 5800SX, GraterliaOS, busybox 1.28, sh4, malo RAM-u).
#
# Po co: obraz "czasem staje", a kazda z mozliwych przyczyn zostawia slad
# gdzie indziej - w logu oscama, w sygnale z tunera, w logach routerow po
# drugiej stronie newcamd. Ten skrypt zbiera to, co widac Z BOXA, co POLL
# sekund, pod jednym zegarem. Biezace logi trzyma w RAM-ie, a na dysk
# zrzuca tylko pliki incydentow - z kontekstem sprzed i po zdarzeniu - zeby
# dalo sie je porownac z logami routerow i serwera kart.
#
# Wymaga: oscam z webifem (dvbapi) i OpenWebif; do sygnalu z tunera Python
# 2.7 i nbox_sygnal.py obok. Pisany i sprawdzany na ADB 5800SX z GraterliaOS.
#
# Wykrywane zdarzenia (typ w logu):
#   STOP       tuner pracuje, a nowy klucz CW nie przychodzi. Dwa sposoby,
#              bo w najgorszym przypadku pierwszy slepnie:
#                - w logu sa nowe "dropping ECM" od dvbapi (oscam dostaje ECM
#                  i je odrzuca; klient dvbapi znika wtedy ze statusu, a
#                  /tmp/ecm.info z dysku),
#                - dvbapi dekoduje program, a /tmp/ecm.info jest starszy niz
#                  ECM_STALL s.
#              STOP-KONIEC mowi, jak sie skonczylo (CW wrocily, takze po
#              restarcie oscama / zmiana kanalu / standby); znikniecie
#              klienta dvbapi przy zamykaniu oscama STOP-u nie konczy.
#   LOCK       tuner stracil synchronizacje z satelita (brak FE_HAS_LOCK) -
#              obraz staje od razu, niezaleznie od oscama. LOCK-OK po powrocie.
#   OBRAZ      tuner pracuje, a dekoder nie podaje obrazu (vmpeg xres = 0)
#              dluzej niz ECM_STALL s. DO SPRAWDZENIA: nie wiadomo jeszcze,
#              czy przy braku CW dekoder zeruje xres, czy trzyma ostatnia
#              ramke; na kanale radiowym xres = 0 zawsze.
#   OSCAM      linie logu oscama pasujace do OSCAM_BLEDY, oraz "ECM CYCLE"
#              dluzszy niz ECM_CYCLE_MAX (norma ~12 s).
#   OSCAM-START oscam uruchomiony ponownie.
#   CZYTNIK    czytnik sieciowy nie jest CONNECTED przez 2 kolejne probki.
#              UNKNOWN sie nie liczy, gdy tuner nie pracuje i nie ma ruchu
#              ECM - oscam laczy newcamd dopiero przy pierwszym ECM, wiec po
#              restarcie oscama bezczynny czytnik tak wlasnie wyglada.
#              CZYTNIK-OK po powrocie. Przy kilku czytnikach zdarzenie mowi,
#              ile innych jest polaczonych; naprawa sieci i przyczyna "brak
#              polaczenia z serwerem kart" dopiero, gdy nie ma zadnego -
#              klucze z innego czytnika znacza, ze siec dziala.
#   OSCAM-NIECZYTELNY  webif oscama odpowiedzial, ale bez starttime - stan
#              z poprzedniej probki zostaje, zadnych wnioskow (wczesniej
#              takie odpowiedzi dawaly falszywe incydenty CZYTNIK); pierwsza
#              trafia do $RAM_DIR/oscam_nieczytelna.txt.
#   SYGNAL     SNR ponizej SNR_ALERT; BER powyzej BER_ALERT, jesli ustawiony
#              (SYGNAL-OK po powrocie).
#   ZEGAR      oscam wystartowal przy zegarze sprzed 2020, zanim Enigma/NTP
#              ustawily czas. Konczy sie to czasem nauczonym cyklem ECM
#              rownym 26 latom ("New ECM arrived after 911151 ms instead of
#              842344662998 ms - dropping ECM") i brakiem CW az do zmiany
#              kanalu, a czasem cykl uczy sie mimo to poprawnie - wiec to
#              ryzyko, nie pewna awaria. Naprawa: jeden restart oscama po
#              ustawieniu zegara (linia do rc.local w README).
#   WEBIF      oscam nie odpowiada albo nie ma procesu enigma2.
#   ENIGMA     enigma2 ma nowy PID - padla i wstala albo restart z menu;
#              obraz stoi przez caly jej start.
#   SIEC       adres RELAY_ADDRESS albo trasa z TRASY zniknely (restart sieci,
#              odnowienie DHCP) i zostaly dodane z powrotem.
#   NAPRAWA    od NAPRAWA_PO s zaden czytnik nie jest polaczony: wynik
#              diagnozy (brama, internet, klient DHCP) i podjeta akcja -
#              patrz sekcja Siec.
#   REBOOT     siec (brama albo internet) nie wrocila przez REBOOT_PO s -
#              restart boxa.
#
# Zrodla - wszystko lokalne i tylko do odczytu, najtansze najpierw:
#   /proc/<enigma2>/fd       czy enigma2 trzyma /dev/dvb/adapter0/frontend*
#                            albo demux* = tuner pracuje. W standby nie trzyma
#                            zadnego /dev/dvb (sprawdzone na dwoch boxach).
#   /proc/stb/vmpeg/0/xres   szerokosc obrazu z dekodera (hex, 0 = brak,
#                            takze w standby)
#   /proc/stb/hdmi/output    off w standby
#   /tmp/ecm.info            dvbapi przepisuje go przy kazdym nowym CW
#   /tmp/nbox_sygnal         sygnal z drajwera tunera (ioctl FE_READ_*: status
#                            z LOCK, SNR, sila, BER) co POLL s - od pomocnika
#                            nbox_sygnal.py (obok), ktorego ten skrypt
#                            uruchamia. /proc ani /sys sygnalu na tym jadrze
#                            nie wystawiaja, a ioctl z shella sie nie da.
#   oscam :8888              oscamapi.html?part=status&appendlog=1 - klient
#                            dvbapi (SID, nazwa kanalu), czytniki, start i
#                            ostatnie ~256 linii logu zwyklym tekstem, jednym
#                            zapytaniem; dziala takze przy disablelog = 1.
#                            NIE logpoll.html: linie w base64, a dekodowanie w
#                            busyboxowym awk na sh4 to 12-14 s CPU / 256 linii.
#   OpenWebif /api/signal    tylko ZAPAS, gdy pomocnika nie ma albo jego odczyt
#                            jest nieswiezy: gdy tuner pracuje, najwyzej co
#                            SIGNAL_EVERY s i od razu przy STOP. OpenWebif
#                            dziala W PROCESIE enigma2 - pomiar: ~70 ms
#                            CPU enigmy na wywolanie; webif oscama ~0;
#                            odczyty /proc ~10 ms.
#
# Wyniki. Rootfs to NAND, a /hdd to talerzowy dysk, ktory przy kazdym
# zapisie sie budzi, halasuje i grzeje - dlatego biezace logi sa w RAM-ie
# (tmpfs), a dysk dostaje tylko incydenty:
#   $RAM_DIR/probki.csv          probka co POLL s        } rotacja: po
#   $RAM_DIR/zdarzenia.log       wszystkie zdarzenia     } przekroczeniu
#   $RAM_DIR/oscam_bledy.log     surowe linie bledow     } limitu plik -> .1
#                                oscama (osobno, bo       } (busybox nie ma
#                                "dropping ECM" leci      }  logrotate)
#                                po kilka na sekunde)
#   $LOG_DIR/zdarzenie_RRRRMMDD_GGMMSS_TYP.log
#                                przy zdarzeniu z INCYDENT_TYPY: stan w tej
#                                chwili, INCYDENT_PROBKI ostatnich probek,
#                                ostatnie zdarzenia, caly bufor logu oscama,
#                                koncowki logread i INCYDENT_DODATKI. Przy
#                                STOP-KONIEC / LOCK-OK dopisywana jest sekcja
#                                KONIEC z probkami z calego czasu trwania.
#                                Zapis w tle (budzenie dysku trwa kilka s),
#                                najwyzej jeden plik danego typu na
#                                INCYDENT_GAP s, na dysku najwyzej
#                                INCYDENT_MAX plikow - najstarsze znikaja.
#   logger(1), tag nbox_monitor  zdarzenia (linie OSCAM zbiorczo)
#   ekran telewizora             zdarzenia z TV_TYPY (domyslnie STOP i LOCK)
#                                jako komunikat OpenWebifu /web/message - tylko
#                                gdy tuner pracuje, najwyzej jeden na TV_GAP s.
#                                Tresc dla ogladajacego: co sie stalo i czy
#                                czekac, czy zmienic kanal.
#   Domoticz (opcjonalnie)       co REPORT s: min SNR i sily sygnalu, max BER,
#                                max czas ECM, liczba bledow oscama, zajetosc
#                                rootfs i /hdd, RAM i CPU; temperatura dysku
#                                co HDD_TEMP_CO s, tylko gdy sie kreci;
#                                ostatnie zdarzenie do urzadzenia tekstowego;
#                                STOP/LOCK/CZYTNIK/WEBIF/ENIGMA jako
#                                powiadomienie "NAZWA: co sie stalo".
#                                Powiadomienie, ktore nie przeszlo (siec padla
#                                razem z obrazem), raport() ponawia co REPORT s.
#                                ZEGAR bez powiadomienia: zdarza sie przy
#                                starcie, a naprawia go linia w rc.local.
#   wentylator (opcjonalnie)     przy FAN=1: gdy dysk sie kreci i grzeje,
#                                PWM rosnie rampa co FAN_KROK stopni, a po
#                                wystygnieciu albo zasnieciu dysku sterowanie
#                                wraca do firmware. Kazda zmiana idzie do
#                                zdarzenia.log jako WENTYLATOR.
#
# Uzycie:
#   nbox_monitor.sh                  praca ciagla (z /etc/rc.local, w tle: &)
#   nbox_monitor.sh --raz            jeden przebieg na ekran; NIC nie zapisuje
#                                    i nic nie wysyla. Da sie nim sprawdzic box
#                                    bez wgrywania czegokolwiek:
#                                      ssh root@box 'sh -s -- --raz' < nbox_monitor.sh
#   nbox_monitor.sh --raz --pokaz-incydent
#                                    j.w. i na koniec tresc, jaka mialby plik
#                                    incydentu w tej chwili (tez nic nie zapisuje)
#   nbox_monitor.sh --bez-domoticz   praca ciagla, tylko lokalne logi
#   nbox_monitor.sh --test-tv        wysyla na ekran przykladowy komunikat STOP
#                                    i konczy - czy OpenWebif go pokaze
#   nbox_monitor.sh --test-domoticz  wysyla testowe powiadomienie i zasoby
#                                    boxa do Domoticza z nbox_monitor.conf
#
# Konfiguracja: zmienne nizej albo /root/nbox_monitor.conf (sourcowany jako
# pierwszy, wiec wygrywa) - wzor z opisem: nbox_monitor.conf.example.
# Bez DOMOTICZ_HOST skrypt pracuje tylko lokalnie (na nBoxie Domoticza nie
# ma). NAZWA idzie w temat powiadomien ("nBox Salon: obraz stoi ..."),
# idx urzadzen (DZ_*) to liczby z tej samej konfiguracji - puste wylacza
# tylko ten jeden pomiar. /root/lib nie jest potrzebne: obsluga Domoticza
# jest w tym pliku. Na boxie wystarcza ten skrypt i nbox_sygnal.py.
#
# Siec - zastepuje prosty monitor pingujacy serwer kart i jako jedyna czesc
# cos na boxie zmienia. Bez problemu czytnika nic nie pinguje, pilnuje tylko
# adresu RELAY_ADDRESS i tras z TRASY. NAPRAWA=0 zostawia sama obserwacje.
#
# Pulapki busyboxowego awk na nBoxie (oba wywalaja CALY program awk):
#   - brak operatora "^" ("Math support is not compiled in"),
#   - "nazwa (" czytane jako wywolanie funkcji ("Call to undefined function"),
#     wiec zadnego "x = x (warunek ? a : b)".

# Uruchomiony z ssh nie ma /sbin w PATH (hdparm, ip, udhcpc, reboot)
PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# shellcheck source=/dev/null
[ -r /root/nbox_monitor.conf ] && . /root/nbox_monitor.conf

NAZWA="${NAZWA:-$(hostname 2>/dev/null || echo nBox)}"
E2_URL="${E2_URL:-http://127.0.0.1}"
OSCAM_URL="${OSCAM_URL:-http://127.0.0.1:8888}"
POLL="${POLL:-10}"                # s, co ile probka
SIGNAL_EVERY="${SIGNAL_EVERY:-60}" # s, co ile najwyzej pytac OpenWebif (zapas)
REPORT="${REPORT:-60}"            # s, co ile wartosci zbiorcze do Domoticza
ROTACJA="${ROTACJA:-300}"         # s, co ile sprawdzac rozmiar logow w RAM-ie
ECM_STALL="${ECM_STALL:-30}"      # s bez nowego CW = STOP (cykl ECM ~12 s)
SNR_ALERT="${SNR_ALERT:-50}"      # %, ponizej = zdarzenie SYGNAL
BER_ALERT="${BER_ALERT:-0}"       # surowy BER z drajwera, powyzej = SYGNAL;
                                  # 0 = bez alarmu (skala nieznana: zdrowy
                                  # sygnal dal 5, OpenWebif pokazal 0)
NOTIFY_GAP="${NOTIFY_GAP:-600}"   # s, min. odstep powiadomien jednego typu

TV_TYPY="${TV_TYPY-STOP LOCK}"    # zdarzenia na ekranie TV; "" = wcale
TV_GAP="${TV_GAP:-600}"           # s, min. odstep komunikatow na ekranie
TV_CZAS="${TV_CZAS:-20}"          # s, jak dlugo komunikat wisi na ekranie
TV_TYP="${TV_TYP:-1}"             # okno enigmy: 1 informacja, 2 ostrzezenie, 3 blad

RAM_DIR="${RAM_DIR:-/tmp/nbox_monitor}"
PROBKI_MAX="${PROBKI_MAX:-2160}"       # linii probek (2160 x 10 s = 6 h) + .1
ZDARZENIA_MAX="${ZDARZENIA_MAX:-1000}" # linii zdarzen / bledow oscama + .1

LOG_MOUNT="${LOG_MOUNT:-/hdd}"    # incydenty tylko gdy to punkt montowania -
                                  # inaczej pisalibysmy na NAND (kilka MB)
LOG_DIR="${LOG_DIR:-$LOG_MOUNT/nbox_monitor}"
INCYDENT_TYPY="${INCYDENT_TYPY:-STOP LOCK CZYTNIK}"
INCYDENT_PROBKI="${INCYDENT_PROBKI:-200}"
INCYDENT_GAP="${INCYDENT_GAP:-600}"    # s, min. odstep plikow tego samego typu
INCYDENT_MAX="${INCYDENT_MAX:-300}"    # plikow na dysku (w RAM-ie bez dysku: 20)
INCYDENT_DODATKI="${INCYDENT_DODATKI:-}" # dodatkowe logi do plikow incydentow

ECM_INFO="${ECM_INFO:-/tmp/ecm.info}"
SYGNAL_PY="${SYGNAL_PY:-/root/nbox_sygnal.py}"
SYGNAL_PLIK="${SYGNAL_PLIK:-/tmp/nbox_sygnal}"
OSCAM_BLEDY="${OSCAM_BLEDY:-dropping ECM|resetting ECM|timeout|not found|rejected|disconnect|connection closed|no matching reader|card removed|restarting}"
ECM_CYCLE_MAX="${ECM_CYCLE_MAX:-20000}" # ms; "ECM CYCLE" powyzej = blad (norma ~12000)

# Domoticz: idx urzadzen - liczby z nbox_monitor.conf, puste = bez pomiaru.
# Typy urzadzen opisuje nbox_monitor.conf.example.
DOMOTICZ_PORT="${DOMOTICZ_PORT:-8080}"
DOMOTICZ_TIMEOUT="${DOMOTICZ_TIMEOUT:-3}"  # s; jedna proba - petla co POLL s nie moze stac
DZ_ZDARZENIE="${DZ_ZDARZENIE:-}"  # tekst: ostatnie zdarzenie
DZ_SNR="${DZ_SNR:-}"              # % min SNR
DZ_SILA="${DZ_SILA:-}"            # % min sily sygnalu (tylko z nbox_sygnal.py)
DZ_BER="${DZ_BER:-}"              # max surowy BER
DZ_ECM="${DZ_ECM:-}"              # ms, max czas odpowiedzi na ECM
DZ_BLEDY="${DZ_BLEDY:-}"          # linie bledow oscama w oknie
DZ_ROOTFS="${DZ_ROOTFS:-}"        # % zajetosci / (NAND)
DZ_HDD="${DZ_HDD:-}"              # % zajetosci $LOG_MOUNT
DZ_RAM="${DZ_RAM:-}"              # % RAM-u bez buforow i cache
DZ_CPU="${DZ_CPU:-}"              # % CPU, srednia z REPORT s
DZ_HDD_TEMP="${DZ_HDD_TEMP:-}"    # st. C dysku, tylko gdy sie kreci

HDD_DEV="${HDD_DEV:-/dev/sda}"
SMARTCTL="${SMARTCTL:-/usr/sbin/smartctl}"
HDD_TEMP_CO="${HDD_TEMP_CO:-1800}" # s, co ile temperatura krecacego sie dysku

# Wentylator. Firmware ustawia PWM tylko przy zmianie stanu boxa (wartosci
# config.fans.0.pwm i pwm_standby z /etc/enigma2/settings), bez zwiazku
# z temperatura dysku - przy nagrywaniu w standby dysk pisze, a wentylator stoi
# na pwm_standby. FAN=1 podbija wtedy obroty rampa co FAN_KROK stopni, zeby
# rozkrecal sie jak najlagodniej i najciszej. Po wystygnieciu albo gdy dysk
# zasnie monitor oddaje sterowanie firmware, wpisujac zapamietana wartosc.
FAN="${FAN:-0}"                    # 1 = sterowanie wentylatorem
FAN_CTRL="${FAN_CTRL:-/proc/stb/fan/fan_ctrl}"
FAN_GORACO="${FAN_GORACO:-50}"     # st. C, od tego zaczyna sie rampa
FAN_ZIMNO="${FAN_ZIMNO:-48}"       # st. C, ponizej oddaj sterowanie (histereza)
FAN_KROK="${FAN_KROK:-2}"          # st. C na jeden stopien rampy
FAN_PWM_MIN="${FAN_PWM_MIN:-60}"   # 0-255, obroty na starcie rampy
FAN_PWM_KROK="${FAN_PWM_KROK:-40}" # o ile PWM na stopien rampy
FAN_PWM="${FAN_PWM:-180}"          # 0-255, sufit rampy (prog SMART to 55 st. C)
FAN_CO="${FAN_CO:-300}"            # s, co ile temperatura, gdy FAN=1

# Siec
NAPRAWA="${NAPRAWA:-1}"            # 1 = diagnoza i naprawa przy problemie czytnika
NAPRAWA_START="${NAPRAWA_START:-300}" # s od startu boxa bez naprawy (siec wstaje)
NAPRAWA_PO="${NAPRAWA_PO:-40}"     # s problemu czytnika do pierwszej diagnozy
NAPRAWA_CO="${NAPRAWA_CO:-120}"    # s miedzy kolejnymi diagnozami
REBOOT_PO="${REBOOT_PO:-3600}"     # s bez bramy albo internetu do restartu; 0 = nigdy
PING_INTERNET="${PING_INTERNET:-8.8.8.8 1.1.1.1}"
SIEC_DEV="${SIEC_DEV:-eth0}"
DHCP="${DHCP:-auto}"               # auto: tak, gdy przy starcie dziala udhcpc na SIEC_DEV
DHCP_PID="${DHCP_PID:-/var/run/udhcpc.${SIEC_DEV}.pid}"
RELAY_ADDRESS="${RELAY_ADDRESS:-}" # drugi, staly adres, np. 192.168.50.2/24
TRASY="${TRASY:-}"                 # "siec,brama ...", np. 10.8.0.0/24,192.168.1.3

TAG=nbox_monitor
PIDF=/tmp/nbox_monitor.pid
NAGLOWEK="czas;uptime;tuner;dvb_fd;xres;hdmi;kanal;dvbapi_sid;ecm_wiek_s;lock;snr;sila;ber;zrodlo_sygnalu;czytniki;bledy_oscam;dropping_ecm;ecm_max_ms"

TRYB=ciagly
DOMOTICZ=1
POKAZ_INCYDENT=0
for _a in "$@"; do
    case "$_a" in
        --raz)             TRYB=raz; DOMOTICZ=0 ;;
        --pokaz-incydent)  POKAZ_INCYDENT=1 ;;
        --bez-domoticz)    DOMOTICZ=0 ;;
        --test-tv)         TRYB=test_tv; DOMOTICZ=0 ;;
        --test-domoticz)   TRYB=test_dz ;;
        -h|--help)         sed -n '2,/^$/p' "$0"; exit 0 ;;
        *)                 echo "nieznana opcja: $_a" >&2; exit 2 ;;
    esac
done

[ "${DOMOTICZ_HOST:-127.0.0.1}" = 127.0.0.1 ] && DOMOTICZ=0

# --- Pomocnicze ------------------------------------------------------------

uptime_s() { cut -d. -f1 /proc/uptime; }
stempel()  { date '+%F %T'; }
pobierz()  { wget -q -T 5 -O - "$1" 2>/dev/null; }

# Liczba z jednowierszowego JSON-a OpenWebifu (/api/signal)
json_num() { printf '%s' "$2" | sed -n "s/.*\"$1\": *\([0-9][0-9]*\).*/\1/p" | head -n 1; }

# Przed arytmetyka: bledne wyrazenie konczy skrypt w ash.
liczba() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

# Dysk tylko gdy zamontowany - sprawdzenie punktu montowania go nie budzi.
katalog_ok() {
    if [ -n "$LOG_MOUNT" ] && ! mountpoint -q "$LOG_MOUNT" 2>/dev/null; then
        return 1
    fi
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null
    [ -w "$LOG_DIR" ]
}

# Rotacja logu w RAM-ie: po przekroczeniu $2 linii plik -> plik.1
rotuj() {
    [ -f "$1" ] || return 0
    [ "$(wc -l < "$1")" -gt "$2" ] && mv "$1" "$1.1"
    return 0
}

# Ostatnie $2 linii logu z RAM-u razem z poprzednia generacja (.1)
ostatnie() {
    cat "$1.1" "$1" 2>/dev/null | grep -v '^czas;' | tail -n "$2"
}

# Rodzaje urzadzen /dev/dvb/adapter0 otwartych przez enigma2, np.
# "audio demux frontend video". Pusto = standby (albo brak enigmy).
dvb_otwarte() {
    [ -n "$1" ] || return 0
    ls -l "/proc/$1/fd" 2>/dev/null \
        | sed -n 's#.*-> /dev/dvb/adapter0/\([a-z]*\).*#\1#p' \
        | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Status oscama (XML) -> cztery linie: starttime, srvid klienta dvbapi,
# czytniki, nazwa kanalu z dvbapi. Konczy na <log>, zeby tresc logu nie
# udawala znacznikow.
os_parse() {
    awk '
    /<log>/ { exit }
    /<oscam / && match($0, /starttime="[^"]*"/) { st = substr($0, RSTART + 11, RLENGTH - 12) }
    /<client / {
        typ = ""; nm = ""
        if (match($0, /type="[^"]*"/)) typ = substr($0, RSTART + 6, RLENGTH - 7)
        if (match($0, /name="[^"]*"/)) nm = substr($0, RSTART + 6, RLENGTH - 7)
    }
    /<request / && typ == "c" && nm == "dvbapi" {
        if (match($0, /srvid="[^"]*"/)) dsid = substr($0, RSTART + 7, RLENGTH - 8)
        kn = $0; sub(/^.*">/, "", kn); sub(/<.*$/, "", kn)
    }
    /<connection / && typ == "p" {
        s = $0; sub(/^.*">/, "", s); sub(/<.*$/, "", s)
        sep = ","; if (rd == "") sep = ""
        rd = rd sep nm "=" s
    }
    END { print st; print dsid; print rd; print kn }'
}

# Sam log oscama z odpowiedzi webifu (bez znacznikow CDATA)
oscam_log() {
    printf '%s\n' "$os" | awk '
    /<log>/   { wlog = 1; next }
    /<\/log>/ { wlog = 0 }
    wlog { sub(/^[ \t]+/, ""); if ($0 != "") print }'
}

# Koncowka logu z <log><![CDATA[ ... ]]></log>. Przetwarza tylko linie PO
# ostatniej widzianej ($1); gdy jej nie ma (pierwszy przebieg, restart
# oscama, bufor przewinal sie w calosci) - wszystkie. Wynik:
#   "E <linia>"  linie pasujace do OSCAM_BLEDY albo absurdalny ECM CYCLE
#   "L <linia>"  ostatnia linia bufora (do zapamietania)
#   "K <n>"      nowych linii, "N <n>" bledow, "D <n>" dropping ECM,
#   "M <ms>"     najdluzszy czas ECM (found/cache2; cache1 = 1 ms pomijamy)
#   "C <n>"      nowych linii "(ecm)" - czy w ogole jest ruch ECM
log_parse() {
    awk -v re="$OSCAM_BLEDY" -v ost="$1" -v cmax="$ECM_CYCLE_MAX" '
    /<log>/   { wlog = 1; next }
    /<\/log>/ { wlog = 0 }
    wlog {
        l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l)
        if (l == "") next
        ile++; L[ile] = l
        if (l == ost) od = ile
    }
    END {
        for (i = od + 1; i <= ile; i++) {
            l = L[i]
            blad = 0; if (l ~ re) blad = 1
            # "ECM CYCLE: 12013 ms" to zwykla nauka cyklu po zmianie kanalu.
            # Bledem jest dopiero cykl absurdalny: 60613 ms z cache innego
            # konta albo 842344662998 ms po skoku zegara.
            if (match(l, /ECM CYCLE: [0-9]+ ms/)) {
                c = substr(l, RSTART + 11, RLENGTH - 14) + 0
                if (c > cmax + 0) blad = 1
            }
            if (blad) { print "E " l; n++ }
            if (l ~ /dropping ECM/) d++
            if (l ~ /\(ecm\)/) e++
            if (match(l, /(found|cache2) +\([0-9]+ ms\)/)) {
                s = substr(l, RSTART, RLENGTH); s = substr(s, index(s, "(") + 1)
                gsub(/[^0-9]/, "", s); if (s + 0 > ms) ms = s + 0
            }
        }
        if (ile > 0) print "L " L[ile]
        print "K " ile - od; print "N " n + 0; print "D " d + 0; print "M " ms + 0
        print "C " e + 0
    }'
}

# --- Domoticz i kodowanie URL ------------------------------------------------
#
# Minimalny klient json.htm Domoticza - na boxie ma byc jeden plik. idx to
# liczby z nbox_monitor.conf, jedna proba z krotkim limitem (petla nie moze
# stac), kodowanie przez hexdump z awk w zapasie (busyboxowy od na nBoxie
# nie zna -A), a bledy ida do zdarzenia.log, bo logread na nBoxie nic nie
# zwraca.

# Kazdy bajt jako %XX - polskie znaki i nowe linie przechodza bez wyjatkow.
url_kod() {
    _h=$(printf '%s' "$1" | hexdump -v -e '/1 "%02X"' 2>/dev/null)
    if [ -n "$1" ] && [ -z "$_h" ]; then
        _h=$(awk 'BEGIN {
            for (i = 0; i < 256; i++) m[sprintf("%c", i)] = i
            t = ARGV[1]
            for (j = 1; j <= length(t); j++) printf "%02X", m[substr(t, j, 1)]
        }' "$1")
    fi
    printf '%s' "$_h" | sed 's/../%&/g'
}

dz_log() {
    if [ "$TRYB" = ciagly ]; then
        echo "$(stempel) up=$(uptime_s) DOMOTICZ $1" >> "$RAM_DIR/zdarzenia.log" 2>/dev/null
    else
        echo "Domoticz: $1" >&2
    fi
}

dz_request() {
    wget -q -T "$DOMOTICZ_TIMEOUT" -O /dev/null "http://${DOMOTICZ_HOST}:${DOMOTICZ_PORT}/json.htm?$1" 2>/dev/null && return 0
    dz_log "${DOMOTICZ_HOST}:${DOMOTICZ_PORT} nie odpowiada: $(printf '%s' "$1" | cut -c1-80)"
    return 1
}

dz_update() { dz_request "type=command&param=udevice&idx=$1&nvalue=0&svalue=$2"; }
dz_notify() { dz_request "type=command&param=sendnotification&subject=$(url_kod "$1")&body=$(url_kod "$2")"; }

# idx z konfiguracji ($1 wartosc, $2 nazwa zmiennej): liczba albo nic
dz_idx() {
    case "$1" in
        '') ;;
        *[!0-9]*) dz_log "$2=$1 to nie liczba - ten pomiar wylaczony" ;;
        *) echo "$1" ;;
    esac
}

idx_zdarzenie=""; idx_snr=""; idx_sila=""; idx_ber=""; idx_ecm=""; idx_bledy=""
idx_rootfs=""; idx_hdd=""; idx_ram=""; idx_cpu=""; idx_hdd_temp=""
dz_start() {
    idx_zdarzenie=$(dz_idx "$DZ_ZDARZENIE" DZ_ZDARZENIE)
    idx_snr=$(dz_idx "$DZ_SNR" DZ_SNR)
    idx_sila=$(dz_idx "$DZ_SILA" DZ_SILA)
    idx_ber=$(dz_idx "$DZ_BER" DZ_BER)
    idx_ecm=$(dz_idx "$DZ_ECM" DZ_ECM)
    idx_bledy=$(dz_idx "$DZ_BLEDY" DZ_BLEDY)
    idx_rootfs=$(dz_idx "$DZ_ROOTFS" DZ_ROOTFS)
    idx_hdd=$(dz_idx "$DZ_HDD" DZ_HDD)
    idx_ram=$(dz_idx "$DZ_RAM" DZ_RAM)
    idx_cpu=$(dz_idx "$DZ_CPU" DZ_CPU)
    idx_hdd_temp=$(dz_idx "$DZ_HDD_TEMP" DZ_HDD_TEMP)
}

# --- Pomocnik sygnalu (Python, ioctl na frontendzie) ------------------------

sygnal_pid=""; sygnal_start_ost=""
start_pomocnika() {
    [ -r "$SYGNAL_PY" ] || return 0
    command -v python >/dev/null 2>&1 || return 0
    # po padnieciu nie wiecej niz jedna proba na 10 minut
    _t=$(uptime_s)
    [ -n "$sygnal_start_ost" ] && [ $((_t - sygnal_start_ost)) -lt 600 ] && return 0
    sygnal_start_ost="$_t"
    python "$SYGNAL_PY" "$POLL" >/dev/null 2>&1 &
    sygnal_pid=$!
    logger -t "$TAG" "pomocnik sygnalu: pid $sygnal_pid ($SYGNAL_PY)"
}

# --- Zasoby boxa (do Domoticza) ---------------------------------------------
#
# Same odczyty /proc i statfs. rootfs to maly NAND (na ADB 5800SX 60 MB,
# zajety w ~90%) - z zasobow boxa najblizszy konca. df /hdd dysku nie
# budzi: hdparm -C daje "standby" przed i po.

# % zajetosci systemu plikow $1: kolumna Use% z ostatniej linii df, bo
# busybox przy dlugiej nazwie urzadzenia lamie wiersz na dwa.
proc_df() {
    df "$1" 2>/dev/null | tail -n 1 | awk '{ print $(NF-1) }' | tr -d '%'
}

# % RAM-u zajetego przez procesy (bez buforow i cache). Jadro 2.6.32 nie ma
# MemAvailable, wiec to przyblizenie - tmpfs (/tmp) liczy sie tu jako cache.
proc_ram() {
    awk '
    /^MemTotal:/ { t = $2 }
    /^MemFree:/  { f = $2 }
    /^Buffers:/  { b = $2 }
    /^Cached:/   { c = $2 }
    END { if (t > 0) printf "%d\n", (t - f - b - c) * 100 / t }' /proc/meminfo
}

# % CPU od poprzedniego wywolania, iowait liczy sie jako bezczynnosc. Wynik
# w cpu_w, nie na stdout: w $(...) poprzedni odczyt zginalby z podpowloka.
# Liczniki odejmuje awk - jiffies z roku pracy nie mieszcza sie w 32 bitach.
# Nie loadavg: na ADB 5800SX stal na 4.00 4.00 4.00 przy 14% CPU.
cpu_pop=""; cpu_w=""
cpu_zmierz() {
    _c=$(awk '/^cpu / { t = 0; for (k = 2; k <= NF; k++) t += $k; print t, $5 + $6; exit }' /proc/stat)
    cpu_w=""
    [ -n "$cpu_pop" ] && cpu_w=$(echo "$cpu_pop $_c" | awk '$3 > $1 { printf "%d\n", 100 - ($4 - $2) * 100 / ($3 - $1) }')
    cpu_pop="$_c"
}

z_rootfs=""; z_hdd=""; z_ram=""; z_cpu=""
zasoby() {
    z_rootfs=$(proc_df /)
    z_hdd=""
    mountpoint -q "$LOG_MOUNT" 2>/dev/null && z_hdd=$(proc_df "$LOG_MOUNT")
    z_ram=$(proc_ram)
    cpu_zmierz; z_cpu="$cpu_w"
}

# Temperatura dysku: smartctl -n standby nie budzi uspionego dysku (konczy
# "Device is in STANDBY mode, exit(2)", hdparm -C dalej standby). Uspiony -
# pytamy znow za REPORT s; odczytany - dopiero za HDD_TEMP_CO s, bo czeste
# odpytywanie krecacego sie dysku moze na niektorych modelach odsuwac jego
# usypianie. Wynik tylko w rundzie odczytu, inaczej z_hdd_temp jest puste;
# z_hdd_spi=1 mowi, ze dysk spi (i nie ma czego chlodzic).
hdd_temp_ost=""; z_hdd_temp=""; z_hdd_spi=""
hdd_temp() {
    z_hdd_temp=""; z_hdd_spi=""
    _ht=$(uptime_s)
    _ht_co="$HDD_TEMP_CO"
    [ "$FAN" -eq 1 ] && _ht_co="$FAN_CO"
    [ -n "$hdd_temp_ost" ] && [ $((_ht - hdd_temp_ost)) -lt "$_ht_co" ] && return 0
    _ht_out=$("$SMARTCTL" -n standby -A "$HDD_DEV" 2>/dev/null)
    case "$_ht_out" in *STANDBY*) z_hdd_spi=1 ;; esac
    z_hdd_temp=$(echo "$_ht_out" \
        | awk '/Temperature_Celsius|Airflow_Temperature/ { print $10; exit }')
    liczba "$z_hdd_temp" && hdd_temp_ost="$_ht"
    return 0
}

# Wentylator: rampa co FAN_KROK stopni od FAN_GORACO (FAN_PWM_MIN) do FAN_PWM.
# Nie czyta SMART-u sam z siebie - korzysta z tego, co ustawil hdd_temp, wiec
# spiacego dysku nie budzi. Wartosc sprzed pierwszego podbicia wraca przy
# FAN_ZIMNO albo gdy dysk zasnie; gdy firmware nadpisze PWM (zmiana stanu
# boxa), zapamietujemy jego nowa wartosc jako ta do oddania.
fan_moje=""; fan_firmware=""
fan_oddaj() {
    [ -n "$fan_moje" ] || return 0
    if liczba "$fan_firmware"; then
        echo "$fan_firmware" > "$FAN_CTRL" 2>/dev/null
        echo "$(stempel) up=$(uptime_s) WENTYLATOR oddany firmware ($fan_firmware)" \
            >> "$RAM_DIR/zdarzenia.log" 2>/dev/null
    fi
    fan_moje=""
    return 0
}
wentylator() {
    [ -w "$FAN_CTRL" ] || return 0
    _fan_now=$(cat "$FAN_CTRL" 2>/dev/null)
    liczba "$_fan_now" || return 0
    [ -n "$fan_moje" ] && [ "$_fan_now" != "$fan_moje" ] && fan_firmware="$_fan_now"
    if [ -n "$z_hdd_spi" ]; then fan_oddaj; return 0; fi
    liczba "$z_hdd_temp" || return 0
    if [ "$z_hdd_temp" -le "$FAN_ZIMNO" ]; then fan_oddaj; return 0; fi
    [ "$z_hdd_temp" -lt "$FAN_GORACO" ] && return 0
    _fan_st=$(( (z_hdd_temp - FAN_GORACO) / FAN_KROK ))
    _fan_pwm=$(( FAN_PWM_MIN + _fan_st * FAN_PWM_KROK ))
    [ "$_fan_pwm" -gt "$FAN_PWM" ] && _fan_pwm="$FAN_PWM"
    [ "$_fan_pwm" -le "$_fan_now" ] && [ -z "$fan_moje" ] && return 0
    [ -z "$fan_moje" ] && fan_firmware="$_fan_now"
    [ "$_fan_pwm" = "$_fan_now" ] && { fan_moje="$_fan_pwm"; return 0; }
    echo "$_fan_pwm" > "$FAN_CTRL" 2>/dev/null || return 0
    fan_moje="$_fan_pwm"
    echo "$(stempel) up=$(uptime_s) WENTYLATOR ${z_hdd_temp} C -> PWM $_fan_pwm (bylo $_fan_now)" \
        >> "$RAM_DIR/zdarzenia.log" 2>/dev/null
    return 0
}

# --- Zdarzenia -------------------------------------------------------------

zd_liczba=0; zd_ostatnie=""; zd_wazne=""; zd_wazny_txt=""
pow_stop=""; pow_czytnik=""; pow_inne=""
inc_nowy=""; inc_txt=""; inc_koniec=""; inc_plik=""; inc_od=0
inc_ost=""; inc_ost_typ=""
tv_nowy=""; tv_opis=""; tv_ost=""

zdarzenie() {
    _linia="$(stempel) up=$(uptime_s) $1 $2"
    case " $INCYDENT_TYPY " in
        *" $1 "*) [ -z "$inc_nowy" ] && { inc_nowy="$1"; inc_txt="$2"; } ;;
    esac
    case " $TV_TYPY " in
        *" $1 "*)
            # STOP i LOCK wygrywaja z reszta, a LOCK (sprawdzany pozniej)
            # ze STOP - brak sygnalu jest przyczyna braku kluczy
            case "$1" in STOP|LOCK) tv_nowy="" ;; esac
            [ -z "$tv_nowy" ] && { tv_nowy="$1"; tv_opis="$2"; } ;;
    esac
    case "$1" in
        STOP-KONIEC|LOCK-OK) [ -n "$inc_plik" ] && inc_koniec="$1 $2" ;;
    esac
    if [ "$TRYB" = raz ]; then
        echo "ZDARZENIE  $_linia"
        return 0
    fi
    logger -t "$TAG" "$1 $2" 2>/dev/null
    echo "$_linia" >> "$RAM_DIR/zdarzenia.log"
    zd_liczba=$((zd_liczba + 1))
    zd_ostatnie="$(date +%H:%M:%S) $1 $2"
    case "$1" in
        STOP|LOCK|CZYTNIK|WEBIF|ENIGMA) zd_wazne="$1"; zd_wazny_txt="$2" ;;
    esac
}

# --- Incydenty na dysk -----------------------------------------------------

# Tresc pliku incydentu na stdout ($1 typ, $2 opis). Korzysta ze zmiennych
# biezacego przebiegu, wiec wolana dopiero po nim.
incydent_tresc() {
    echo "=== $NAZWA: $1 - $2"
    echo "czas $(stempel), uptime $(uptime_s) s"
    echo
    echo "=== stan w chwili zdarzenia"
    echo "tuner=$tuner (enigma2 trzyma: ${dvb_fd:-nic}) xres=$xres hdmi=${hdmi:-?}"
    echo "kanal=${kanal:-?} dvbapi_sid=${dvb_sid:-?} ecm.info=${ecm_wiek:-brak}s"
    echo "sygnal: lock=${lock:--} snr=${snr:--}% sila=${sila:--}% ber=${ber:--} zrodlo=${zrodlo:--} ${_fe_st}"
    echo "oscam: start=${os_start:-?} czytniki=${czytniki:-?}"
    echo "load: $(cat /proc/loadavg)"
    free 2>/dev/null | sed -n '2,3p'
    if [ -f "$ECM_INFO" ]; then
        echo
        echo "=== $ECM_INFO (bez kluczy cw)"
        grep -v '^cw' "$ECM_INFO"
    fi
    echo
    echo "=== zdarzenia - ostatnie 50"
    ostatnie "$RAM_DIR/zdarzenia.log" 50
    echo
    echo "=== probki - ostatnie $INCYDENT_PROBKI"
    echo "$NAGLOWEK"
    ostatnie "$RAM_DIR/probki.csv" "$INCYDENT_PROBKI"
    echo
    echo "=== log oscama - caly bufor webifu"
    oscam_log
    echo
    echo "=== logread - ostatnie 50"
    logread 2>/dev/null | tail -n 50
    for _f in $INCYDENT_DODATKI; do
        [ -r "$_f" ] || continue
        echo
        echo "=== $_f - ostatnie 50"
        tail -n 50 "$_f"
    done
}

sprzataj_incydenty() {
    ls -1t "$LOG_DIR"/zdarzenie_*.log 2>/dev/null | tail -n +$((INCYDENT_MAX + 1)) | xargs rm -f 2>/dev/null
    ls -1t "$RAM_DIR"/zdarzenie_*.log 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null
    return 0
}

incydent_nowy() {
    _typ="$inc_nowy"; _txt="$inc_txt"; inc_nowy=""; inc_txt=""
    _t=$(uptime_s)
    # ten sam typ przed chwila - zostaje tylko wpis w zdarzenia.log
    if [ "$_typ" = "$inc_ost_typ" ] && [ -n "$inc_ost" ] && [ $((_t - inc_ost)) -lt "$INCYDENT_GAP" ]; then
        return 0
    fi
    inc_ost="$_t"; inc_ost_typ="$_typ"
    _n="zdarzenie_$(date +%Y%m%d_%H%M%S)_${_typ}.log"
    incydent_tresc "$_typ" "$_txt" > "$RAM_DIR/$_n"
    inc_plik="$LOG_DIR/$_n"; inc_od="$_t"
    # Kopia na dysk w tle: budzenie dysku trwa kilka sekund, a pomiary ida dalej.
    # Bez dysku plik zostaje w RAM-ie (najwyzej 20 sztuk).
    (
        if katalog_ok && cp "$RAM_DIR/$_n" "$LOG_DIR/$_n"; then
            rm -f "$RAM_DIR/$_n"
        else
            logger -t "$TAG" "brak dysku - incydent $_n zostaje w $RAM_DIR"
        fi
        sprzataj_incydenty
    ) &
}

incydent_koniec() {
    _k="$inc_koniec"; inc_koniec=""
    [ -n "$inc_plik" ] || return 0
    _ile=$(( ( $(uptime_s) - inc_od ) / POLL + 3 ))
    [ "$_ile" -gt 360 ] && _ile=360
    _cel="$inc_plik"
    [ -f "$_cel" ] || _cel="$RAM_DIR/${inc_plik##*/}"
    _tmp="$RAM_DIR/koniec.$$"
    {
        echo
        echo "=== KONIEC $(stempel), uptime $(uptime_s) s: $_k"
        echo
        echo "=== probki od poczatku zdarzenia ($_ile)"
        echo "$NAGLOWEK"
        ostatnie "$RAM_DIR/probki.csv" "$_ile"
        echo
        echo "=== log oscama - ostatnie 100 linii"
        oscam_log | tail -n 100
    } > "$_tmp"
    ( cat "$_tmp" >> "$_cel"; rm -f "$_tmp" ) &
    inc_plik=""
}

# --- Siec -------------------------------------------------------------------
#
# Poprzedni monitor pingowal serwer kart co 15 s, na okraglo. Tu diagnoza
# rusza dopiero, gdy zaden czytnik oscama nie jest CONNECTED - stan
# czytnikow mowi o polaczeniu z serwerami kart wiecej niz ping, a klucze
# z jednego znacza, ze siec dziala, nawet gdy drugi lezy (na jednym boxie
# newcamd ze starym adresem IP obok dzialajacego cccam). Wtedy ping do bramy
# (z trasy default) i do PING_INTERNET oraz stan klienta DHCP wybieraja akcje:
#   DHCP, a klient nie dziala albo brama nie odpowiada -> klient DHCP od nowa
#   bez DHCP, brama nie odpowiada                    -> restart sieci
#   brama tak, internet nie                          -> nic: problem za brama
#   brama i internet tak                             -> nic: serwer kart albo DNS
# Restart boxa dopiero po REBOOT_PO s, w ktorych diagnoza widzi brak bramy
# albo internetu - przy awarii samego serwera kart restart nic nie da.

brama() { ip route 2>/dev/null | awk '$1 == "default" { print $3; exit }'; }
ping1() { ping -c 1 -w 2 -W 2 "$1" >/dev/null 2>&1; }

dhcp_dziala() {
    [ -f "$DHCP_PID" ] && kill -0 "$(cat "$DHCP_PID" 2>/dev/null)" 2>/dev/null
}

# Jeden meldunek o tym samym bledzie, nie co POLL s
siec_ost=""
siec_meld() {
    [ "$1" = "$siec_ost" ] && return 0
    siec_ost="$1"
    zdarzenie SIEC "$1"
}

# Adres relay i trasy znikaja po restarcie sieci i po odnowieniu DHCP -
# sprawdzane co przebieg i dodawane z powrotem; w --raz tylko meldunek.
siec_pilnuj() {
    if [ -n "$RELAY_ADDRESS" ] \
        && ! ip addr show dev "$SIEC_DEV" 2>/dev/null | grep -q "inet ${RELAY_ADDRESS%/*}/"; then
        if [ "$TRYB" = raz ]; then
            echo "SIEC         brak adresu $RELAY_ADDRESS na $SIEC_DEV - praca ciagla by go dodala"
        elif ip address add "$RELAY_ADDRESS" dev "$SIEC_DEV" 2>/dev/null; then
            siec_ost=""; zdarzenie SIEC "dodany adres $RELAY_ADDRESS na $SIEC_DEV"
        else
            siec_meld "nie da sie dodac adresu $RELAY_ADDRESS na $SIEC_DEV"
        fi
    fi
    for _tr in $TRASY; do
        _net="${_tr%%,*}"; _gw="${_tr#*,}"
        ip route 2>/dev/null | grep -q "^${_net} " && continue
        if [ "$TRYB" = raz ]; then
            echo "SIEC         brak trasy $_net via $_gw - praca ciagla by ja dodala"
        elif ip route add "$_net" via "$_gw" 2>/dev/null; then
            siec_ost=""; zdarzenie SIEC "dodana trasa $_net via $_gw"
        else
            siec_meld "nie da sie dodac trasy $_net via $_gw"
        fi
    done
}

# Diagnoza - same odczyty i pingi. Wynik w d_*: d_akcja (dhcp/siec/pusto),
# d_txt (co widac) i d_opis (co z tego wynika).
diagnoza() {
    d_gw=$(brama); d_gw_ok=0; d_net_ok=0; d_dhcp=statyczny
    [ -n "$d_gw" ] && ping1 "$d_gw" && d_gw_ok=1
    for _h in $PING_INTERNET; do
        if ping1 "$_h"; then d_net_ok=1; break; fi
    done
    if [ "$DHCP" = 1 ]; then
        if dhcp_dziala; then d_dhcp=dziala; else d_dhcp=NIE; fi
    fi
    d_txt="brama ${d_gw:-BRAK}=$([ "$d_gw_ok" -eq 1 ] && echo ok || echo NIE) internet=$([ "$d_net_ok" -eq 1 ] && echo ok || echo NIE) dhcp=$d_dhcp"
    d_akcja=""
    if [ "$DHCP" = 1 ] && { [ "$d_dhcp" = NIE ] || [ "$d_gw_ok" -eq 0 ]; }; then
        d_akcja=dhcp; d_opis="klient DHCP od nowa"
    elif [ "$d_gw_ok" -eq 0 ]; then
        d_akcja=siec; d_opis="restart sieci"
    elif [ "$d_net_ok" -eq 0 ]; then
        d_opis="bez akcji - problem za brama"
    else
        d_opis="bez akcji - siec w porzadku, serwer kart albo DNS"
    fi
}

# Jak w poprzednim monitorze: zabic stary klient i uruchomic nowy; -n konczy
# go bez dzierzawy, po dzierzawie sam przechodzi w tlo.
dhcp_od_nowa() {
    kill "$(cat "$DHCP_PID" 2>/dev/null)" 2>/dev/null
    sleep 1
    killall udhcpc 2>/dev/null
    sleep 1
    udhcpc -R -n -p "$DHCP_PID" -i "$SIEC_DEV" >/dev/null 2>&1
}

restart_boxa() {
    zdarzenie REBOOT "$1 - restart boxa (REBOOT_PO=${REBOOT_PO}s)"
    _n="zdarzenie_$(date +%Y%m%d_%H%M%S)_REBOOT.log"
    incydent_tresc REBOOT "$1" > "$RAM_DIR/$_n"
    katalog_ok && cp "$RAM_DIR/$_n" "$LOG_DIR/$_n"
    [ "$DOMOTICZ" -eq 1 ] && dz_notify "$NAZWA: restart boxa" "$1"
    sync
    sleep 5
    reboot
    # reboot wraca od razu, a init dopiero zatrzymuje procesy - bez czekania
    # petla szla dalej i mogla jeszcze restartowac siec
    sleep 120
}

naprawa_ost=""; siec_zla_od=""
naprawa_krok() {
    if [ -z "$czyt_od" ] || [ "$czyt_zgloszony" -ne 1 ] || [ "$czyt_ok" -gt 0 ]; then
        naprawa_ost=""; siec_zla_od=""
        return 0
    fi
    [ "$up" -ge "$NAPRAWA_START" ] || return 0
    _dt=$((up - czyt_od))
    [ "$_dt" -ge "$NAPRAWA_PO" ] || return 0
    [ -n "$naprawa_ost" ] && [ $((up - naprawa_ost)) -lt "$NAPRAWA_CO" ] && return 0
    naprawa_ost="$up"

    diagnoza
    if [ "$d_gw_ok" -eq 1 ] && [ "$d_net_ok" -eq 1 ]; then
        siec_zla_od=""
    elif [ -z "$siec_zla_od" ]; then
        siec_zla_od="$up"
    fi
    if [ "$REBOOT_PO" -gt 0 ] && [ -n "$siec_zla_od" ] && [ $((up - siec_zla_od)) -ge "$REBOOT_PO" ]; then
        restart_boxa "czytnik bez polaczenia od ${_dt}s, $d_txt od $((up - siec_zla_od))s"
        return 0
    fi
    zdarzenie NAPRAWA "czytnik od ${_dt}s: $d_txt -> $d_opis"
    case "$d_akcja" in
        dhcp) dhcp_od_nowa ;;
        siec) /etc/init.d/network restart >/dev/null 2>&1 ;;
    esac
    [ -n "$d_akcja" ] && siec_pilnuj
    return 0
}

# --- Wyjscie ---------------------------------------------------------------

dz_tekst() {
    dz_request "type=command&param=udevice&idx=${idx_zdarzenie}&nvalue=0&svalue=$(url_kod "$(printf '%s' "$1" | cut -c1-200)")"
}

# Temat powiadomienia - co sie stalo, po ludzku ($1 typ, $2 opis zdarzenia)
opis_krotki() {
    case "$1" in
        STOP)    echo "obraz stoi - nie przychodza klucze" ;;
        LOCK)    echo "brak sygnalu z satelity" ;;
        CZYTNIK)
            if [ "$czyt_ok" -gt 0 ]; then echo "czytnik bez polaczenia, inne dzialaja"
            else echo "brak polaczenia z serwerem kart"
            fi ;;
        ENIGMA)  echo "enigma2 uruchomiona ponownie" ;;
        WEBIF)
            case "$2" in
                *BRAK*) echo "oscam albo enigma2 nie odpowiada" ;;
                *)      echo "oscam i enigma2 znow odpowiadaja" ;;
            esac ;;
        *)       echo "$1" ;;
    esac
}

zal_temat=""; zal_tresc=""
powiadom() {
    _t=$(uptime_s)
    case "$1" in
        STOP|LOCK) _ost="$pow_stop" ;;
        CZYTNIK)   _ost="$pow_czytnik" ;;
        *)         _ost="$pow_inne" ;;
    esac
    [ -n "$_ost" ] && [ $((_t - _ost)) -lt "$NOTIFY_GAP" ] && return 0
    case "$1" in
        STOP|LOCK) pow_stop="$_t" ;;
        CZYTNIK)   pow_czytnik="$_t" ;;
        *)         pow_inne="$_t" ;;
    esac
    _temat="$NAZWA: $(opis_krotki "$1" "$2")"
    _tresc="$(date +%H:%M:%S) dekoder $([ "$tuner" -eq 1 ] && echo wlaczony || echo w standby) - $1: $2"
    dz_notify "$_temat" "$_tresc" && return 0
    # Domoticz nie odpowiada - czesto z tego samego powodu, ktory zatrzymal
    # obraz (siec). Ostatnie takie powiadomienie ponawia raport().
    zal_temat="$_temat"; zal_tresc="$_tresc"
}

# --- Ekran telewizora --------------------------------------------------------

# Tekst dla ogladajacego ($1 typ, $2 opis zdarzenia); pusto = nic nie pokazujemy.
# Przyczyne STOP bierze ze zmiennych biezacego przebiegu.
tv_tresc() {
    case "$1" in
        STOP)
            _rada="Poczekaj - obraz powinien wrocic sam."
            if [ -z "$os" ]; then _p="program oscam w dekoderze nie odpowiada"
            elif [ -n "$czyt_problem" ] && [ "$czyt_ok" -eq 0 ]; then _p="brak polaczenia z serwerem kart"
            elif [ "${n_drop:-0}" -gt 0 ]; then
                # tak konczy sie skok zegara (ZEGAR): do zmiany kanalu
                _p="dekoder odrzuca klucze"; _rada="Zmien kanal i wroc."
            else _p="serwer kart nie przysyla kluczy"
            fi
            printf 'Obraz zatrzymany - kanal %s.\nPrzyczyna: %s.\n%s' "${kanal:-?}" "$_p" "$_rada" ;;
        LOCK)
            printf 'Brak sygnalu z satelity (SNR %s%%).\nMozliwe przyczyny: pogoda (snieg, ulewa), antena, kabel.\nObraz wroci razem z sygnalem.' "${snr:-?}" ;;
        SYGNAL)
            printf 'Slaby sygnal z satelity (SNR %s%%).\nObraz moze sie rozpadac na kwadraty.' "${snr:-?}" ;;
        CZYTNIK)
            printf 'Brak polaczenia z serwerem kart.\nKanaly kodowane moga nie dzialac.' ;;
        WEBIF)
            case "$2" in
                *oscam=BRAK*) printf 'Program oscam w dekoderze nie odpowiada.\nKanaly kodowane moga nie dzialac.' ;;
            esac ;;
        OBRAZ)
            printf 'Dekoder nie pokazuje obrazu - kanal %s.\nMoze to byc kanal spoza pakietu.' "${kanal:-?}" ;;
    esac
}

tv_wyslij() {
    pobierz "$E2_URL/web/message?text=$(url_kod "$1")&type=${TV_TYP}&timeout=${TV_CZAS}" >/dev/null && return 0
    logger -t "$TAG" "komunikat na ekran nie przeszedl ($E2_URL)" 2>/dev/null
    return 1
}

tv_pokaz() {
    _typ="$tv_nowy"; _opis="$tv_opis"; tv_nowy=""; tv_opis=""
    [ "$tuner" -eq 1 ] || return 0     # standby - nikt nie patrzy
    _txt=$(tv_tresc "$_typ" "$_opis")
    [ -n "$_txt" ] || return 0
    _t=$(uptime_s)
    [ -n "$tv_ost" ] && [ $((_t - tv_ost)) -lt "$TV_GAP" ] && return 0
    tv_ost="$_t"
    tv_wyslij "$_txt" && logger -t "$TAG" "ekran: $_typ" 2>/dev/null
    return 0
}

po_przebiegu() {
    [ -n "$inc_koniec" ] && incydent_koniec
    [ -n "$inc_nowy" ] && incydent_nowy
    # ekran przed Domoticzem: martwy Domoticz to kilka sekund czekania
    [ -n "$tv_nowy" ] && tv_pokaz
    [ "$zd_liczba" -gt 0 ] || return 0
    if [ "$DOMOTICZ" -eq 1 ]; then
        [ -n "$idx_zdarzenie" ] && dz_tekst "$zd_ostatnie"
        [ -n "$zd_wazne" ] && powiadom "$zd_wazne" "$zd_wazny_txt"
    fi
    zd_liczba=0; zd_wazne=""; zd_wazny_txt=""
}

# Jedno nieudane zapytanie konczy runde raportu: przy martwym Domoticzu kazde
# kolejne to znow DOMOTICZ_TIMEOUT s, a petla ma chodzic co POLL s.
dz_runda=0
dz_wyslij() {
    [ -n "$1" ] && liczba "$2" || return 0
    [ "$dz_runda" -eq 0 ] || return 1
    dz_update "$1" "$2" || { dz_runda=1; return 1; }
}

okno_snr=""; okno_sila=""; okno_ber=""; okno_ecm=0; okno_bledy=0
raport() {
    if [ "$DOMOTICZ" -eq 1 ]; then
        dz_runda=0
        dz_wyslij "$idx_snr" "$okno_snr"
        dz_wyslij "$idx_sila" "$okno_sila"
        dz_wyslij "$idx_ber" "$okno_ber"
        [ "$okno_ecm" -gt 0 ] && dz_wyslij "$idx_ecm" "$okno_ecm"
        dz_wyslij "$idx_bledy" "$okno_bledy"
        zasoby
        dz_wyslij "$idx_rootfs" "$z_rootfs"
        dz_wyslij "$idx_hdd" "$z_hdd"
        dz_wyslij "$idx_ram" "$z_ram"
        dz_wyslij "$idx_cpu" "$z_cpu"
        if [ -n "$idx_hdd_temp" ]; then hdd_temp; dz_wyslij "$idx_hdd_temp" "$z_hdd_temp"; fi
        if [ -n "$zal_temat" ] && [ "$dz_runda" -eq 0 ] \
            && dz_notify "$zal_temat" "$zal_tresc (wyslane z opoznieniem)"; then
            zal_temat=""
        fi
    fi
    if [ "$FAN" -eq 1 ]; then
        # bez Domoticza (albo bez DZ_HDD_TEMP) nikt jeszcze temperatury nie czytal
        if [ "$DOMOTICZ" -ne 1 ] || [ -z "$idx_hdd_temp" ]; then hdd_temp; fi
        wentylator
    fi
    okno_snr=""; okno_sila=""; okno_ber=""; okno_ecm=0; okno_bledy=0
}

# --- Jeden przebieg --------------------------------------------------------

ostatnia_linia=""; e2p_pop=""
os_start_pop=""; webif_pop=""; zegar_zgloszony=""
os_start=""; dvb_sid=""; czytniki=""; kanal=""; os_ok=0
czyt_zle=0; czyt_zgloszony=0; czyt_ostatnie_ok=""; czyt_problem=""; czyt_od=""; czyt_ok=0
tuner_pop=""; sid_pop=""; zmiana_od=0; stoi_od=""; sid_stop=""; os_start_stop=""
obraz_od=""; obraz_zly=0; snr_zly=0; ber_zly=0; lock_zly=0; sygnal_ost=0

przebieg() {
    up=$(uptime_s)

    # Stan dekodera z /proc - bez pytania enigmy o cokolwiek
    e2p=$(pidof enigma2 2>/dev/null | cut -d' ' -f1)
    dvb_fd=$(dvb_otwarte "$e2p")
    tuner=0
    case "$dvb_fd" in *frontend*|*demux*) tuner=1 ;; esac
    xres=$(cat /proc/stb/vmpeg/0/xres 2>/dev/null); xres=${xres:-0}
    hdmi=$(cat /proc/stb/hdmi/output 2>/dev/null)

    # ENIGMA - nowy PID enigmy: padla i wstala (albo restart z menu)
    if [ -n "$e2p" ] && [ -n "$e2p_pop" ] && [ "$e2p" != "$e2p_pop" ]; then
        zdarzenie ENIGMA "enigma2 ma nowy PID ($e2p_pop -> $e2p) - padla albo restart z menu"
    fi
    [ -n "$e2p" ] && e2p_pop="$e2p"

    # oscam: status i koncowka logu jednym zapytaniem (proces w C, ~0 CPU)
    os=$(pobierz "$OSCAM_URL/oscamapi.html?part=status&appendlog=1")
    os_ok=0
    if [ -n "$os" ]; then
        _w=$(printf '%s\n' "$os" | os_parse)
        _st=$(printf '%s\n' "$_w" | sed -n 1p)
        if [ -n "$_st" ]; then
            os_ok=1
            os_start="$_st"
            dvb_sid=$(printf '%s\n' "$_w" | sed -n 2p)
            czytniki=$(printf '%s\n' "$_w" | sed -n 3p)
            kanal=$(printf '%s\n' "$_w" | sed -n 4p | tr ';' ',')
            [ "$dvb_sid" = 0000 ] && dvb_sid=""
            case "$kanal" in ''|unknown) kanal="${dvb_sid:+SID $dvb_sid}" ;; esac
        else
            # Odpowiedz jest, ale bez starttime - nie wiemy, co w niej jest.
            # Kanal, SID, czytniki i start zostaja z poprzedniej probki;
            # pierwsza taka odpowiedz idzie do RAM-u do obejrzenia.
            if [ "$TRYB" != raz ] && [ ! -f "$RAM_DIR/oscam_nieczytelna.txt" ]; then
                { echo "$(stempel) up=$up - odpowiedz bez starttime, ${#os} B, pierwsze 60 linii:"
                  printf '%s\n' "$os" | head -n 60; } > "$RAM_DIR/oscam_nieczytelna.txt"
            fi
            zdarzenie OSCAM-NIECZYTELNY "status oscama bez starttime (${#os} B) - zostaje poprzedni stan"
        fi
    fi

    if [ "$os_ok" -eq 1 ] && [ -n "$os_start_pop" ] && [ "$os_start" != "$os_start_pop" ]; then
        zdarzenie OSCAM-START "oscam uruchomiony ponownie (start=$os_start)"
    fi
    [ "$os_ok" -eq 1 ] && os_start_pop="$os_start"

    _log=$(printf '%s\n' "$os" | log_parse "$ostatnia_linia")
    _l=$(printf '%s\n' "$_log" | sed -n 's/^L //p')
    [ -n "$_l" ] && ostatnia_linia="$_l"
    n_nowe=$(printf '%s\n' "$_log" | sed -n 's/^K //p');  n_nowe=${n_nowe:-0}
    n_err=$(printf '%s\n' "$_log" | sed -n 's/^N //p');   n_err=${n_err:-0}
    n_drop=$(printf '%s\n' "$_log" | sed -n 's/^D //p');  n_drop=${n_drop:-0}
    ecm_ms=$(printf '%s\n' "$_log" | sed -n 's/^M //p');  ecm_ms=${ecm_ms:-0}
    n_ecm=$(printf '%s\n' "$_log" | sed -n 's/^C //p');   n_ecm=${n_ecm:-0}
    if [ "$n_err" -gt 0 ]; then
        _pierwsza=$(printf '%s\n' "$_log" | sed -n 's/^E //p' | head -n 1)
        if [ "$TRYB" = raz ]; then
            echo "--- bledy w buforze logu oscama: $n_err, ostatnie 10 ---"
            printf '%s\n' "$_log" | sed -n 's/^E //p' | tail -n 10
        else
            # surowe linie osobno, do zdarzen tylko podsumowanie - inaczej
            # lawina "dropping ECM" zagluszylaby wszystko inne
            printf '%s\n' "$_log" | sed -n 's/^E //p' >> "$RAM_DIR/oscam_bledy.log"
            _t="$(stempel) up=$up OSCAM ${n_err}x: $_pierwsza"
            echo "$_t" >> "$RAM_DIR/zdarzenia.log"
            logger -t "$TAG" "OSCAM: $n_err linii bledow, np.: $_pierwsza" 2>/dev/null
            zd_liczba=$((zd_liczba + 1))
            zd_ostatnie="$(date +%H:%M:%S) OSCAM ${n_err}x: $_pierwsza"
        fi
    fi

    # WEBIF - pierwsze 5 minut po starcie boxa to normalny brak odpowiedzi
    _w="oscam=$([ -n "$os" ] && echo ok || echo BRAK) e2=$([ -n "$e2p" ] && echo ok || echo BRAK)"
    if [ "$up" -ge 300 ] || [ "$TRYB" = raz ]; then
        [ "$_w" != "${webif_pop:-oscam=ok e2=ok}" ] && zdarzenie WEBIF "$_w"
        webif_pop="$_w"
    fi

    # ZEGAR - oscam uruchomiony, zanim Enigma/NTP ustawily czas
    _rok=$(printf '%s' "$os_start" | cut -c1-4)
    case "$_rok" in [0-9][0-9][0-9][0-9]) ;; *) _rok="" ;; esac
    if [ "$os_ok" -eq 1 ] && [ -n "$_rok" ] && [ "$_rok" -lt 2020 ] && [ "$(date +%Y)" -ge 2020 ] \
        && [ "$os_start" != "$zegar_zgloszony" ]; then
        zdarzenie ZEGAR "oscam wystartowal przy nieustawionym zegarze (start=$os_start) - grozi dropping ECM az do zmiany kanalu"
        zegar_zgloszony="$os_start"
    fi

    # CZYTNIK - tylko z czytelnej odpowiedzi i dopiero po 2 probkach z rzedu.
    # UNKNOWN przy braku ruchu ECM to czytnik, ktory jeszcze sie nie laczyl.
    if [ "$os_ok" -eq 1 ]; then
        # ile czytnikow jest polaczonych - klucze z ktoregokolwiek = siec dziala
        czyt_ok=$(printf '%s' "$czytniki" | tr ',' '\n' | grep -c '=CONNECTED$')
        if [ -z "$czytniki" ]; then
            czyt_problem="brak czytnikow"
        else
            czyt_problem=$(printf '%s' "$czytniki" | tr ',' '\n' | grep -v '=CONNECTED$')
            if [ "$tuner" -eq 0 ] && [ "$n_ecm" -eq 0 ]; then
                czyt_problem=$(printf '%s\n' "$czyt_problem" | grep -v '=UNKNOWN$')
            fi
            czyt_problem=$(printf '%s' "$czyt_problem" | tr '\n' ',' | sed 's/,$//')
        fi
        if [ -n "$czyt_problem" ]; then
            czyt_zle=$((czyt_zle + 1))
            [ -n "$czyt_od" ] || czyt_od="$up"
            if [ "$czyt_zle" -ge 2 ] && [ "$czyt_zgloszony" -eq 0 ]; then
                czyt_zgloszony=1
                zdarzenie CZYTNIK "${czyt_ostatnie_ok:-?} -> $czyt_problem (od $czyt_zle probek, polaczonych: $czyt_ok)"
            fi
        else
            czyt_zle=0; czyt_od=""
            [ -n "$czytniki" ] && czyt_ostatnie_ok="$czytniki"
            if [ "$czyt_zgloszony" -eq 1 ]; then
                czyt_zgloszony=0
                zdarzenie CZYTNIK-OK "${czytniki:-?}"
            fi
        fi
    fi

    # Siec: adres relay i trasy co przebieg, naprawa tylko przy problemie
    # czytnika (w --raz diagnoza idzie osobno, na koniec)
    siec_pilnuj
    [ "$NAPRAWA" -eq 1 ] && [ "$TRYB" != raz ] && naprawa_krok

    # Po wybudzeniu i po zmianie programu dajemy ECM_STALL s spokoju:
    # ecm.info i obraz sa wtedy z definicji nieaktualne.
    if [ "$tuner" != "$tuner_pop" ] || [ "$dvb_sid" != "$sid_pop" ]; then
        [ -n "$tuner_pop" ] && zmiana_od="$up"
        tuner_pop="$tuner"; sid_pop="$dvb_sid"
    fi
    _spokoj=0; [ $((up - zmiana_od)) -ge "$ECM_STALL" ] && _spokoj=1

    # STOP - czy przychodza nowe CW
    ecm_wiek=""
    if [ -f "$ECM_INFO" ]; then
        _m=$(stat -c %Y "$ECM_INFO" 2>/dev/null)
        [ -n "$_m" ] && ecm_wiek=$(( $(date +%s) - _m ))
    fi
    _stoi=0; _dlaczego=""
    if [ "$tuner" -eq 1 ] && [ "$_spokoj" -eq 1 ]; then
        if [ "$n_drop" -gt 0 ]; then
            _stoi=1; _dlaczego="dvbapi odrzuca ECM (nowych dropping ECM: $n_drop)"
        elif [ -n "$dvb_sid" ] && [ -n "$ecm_wiek" ] && [ "$ecm_wiek" -gt "$ECM_STALL" ]; then
            _stoi=1; _dlaczego="brak nowego CW od ${ecm_wiek}s"
        fi
    fi
    # Trwajacy STOP konczy sie dopiero nowym CW albo innym kanalem. Klient
    # dvbapi znika tez, gdy oscam sie zamyka (restart trwal ~80 s; status
    # jest wtedy bez czytnikow), a po jego powrocie zmiana SID zeruje
    # _spokoj - bez tego oba momenty dawaly falszywe "CW znow przychodza".
    # Pusty SID przy czytnikach to kanal niekodowany - wtedy koniec STOP.
    if [ "$_stoi" -eq 0 ] && [ -n "$stoi_od" ] && [ "$tuner" -eq 1 ] \
        && { [ "$dvb_sid" = "$sid_stop" ] || { [ -z "$dvb_sid" ] && [ -z "$czytniki" ]; }; } \
        && { [ -z "$ecm_wiek" ] || [ "$ecm_wiek" -gt "$ECM_STALL" ]; }; then
        _stoi=1
    fi

    # Sygnal: najpierw od pomocnika (ioctl, patrz nbox_sygnal.py). Swiezy =
    # nie starszy niz 3 probki. OpenWebif tylko gdy pomocnika brak.
    snr=""; sila=""; ber=""; lock=""; _fe_st=""; zrodlo=""
    if [ -r "$SYGNAL_PLIK" ]; then
        read -r _s_up _s_fe _s_st _s_lock _s_snr _s_sila _s_ber < "$SYGNAL_PLIK"
        if liczba "$_s_up" && [ $((up - _s_up)) -le $((POLL * 3)) ]; then
            zrodlo=ioctl
            liczba "$_s_snr"  && snr="$_s_snr"
            liczba "$_s_sila" && sila="$_s_sila"
            liczba "$_s_ber"  && ber="$_s_ber"
            liczba "$_s_lock" && lock="$_s_lock"
            _fe_st="$_s_fe $_s_st"
        fi
    fi
    _mierz=0
    if [ -z "$zrodlo" ] && [ "$tuner" -eq 1 ]; then
        [ $((up - sygnal_ost)) -ge "$SIGNAL_EVERY" ] && _mierz=1
        [ "$_stoi" -eq 1 ] && [ -z "$stoi_od" ] && _mierz=1
        [ "$TRYB" = raz ] && _mierz=1
    fi
    if [ "$_mierz" -eq 1 ]; then
        sg=$(pobierz "$E2_URL/api/signal")
        snr=$(json_num snr "$sg"); sila=$(json_num agc "$sg"); ber=$(json_num ber "$sg")
        sygnal_ost="$up"; zrodlo=openwebif
    fi

    if [ "$_stoi" -eq 1 ] && [ -z "$stoi_od" ]; then
        stoi_od="$up"; sid_stop="$dvb_sid"; os_start_stop="$os_start"
        zdarzenie STOP "$_dlaczego - ${kanal:-?}, lock ${lock:-?} SNR ${snr:-?}% BER ${ber:-?}, xres $xres, czytniki: ${czytniki:-?}"
    elif [ "$_stoi" -eq 0 ] && [ -n "$stoi_od" ]; then
        if [ "$tuner" -eq 0 ]; then _jak="standby"
        elif [ "$dvb_sid" != "$sid_stop" ] && [ -n "$dvb_sid" ]; then _jak="zmiana kanalu"
        elif [ -z "$dvb_sid" ]; then _jak="zmiana na kanal bez dvbapi"
        elif [ "$os_start" != "$os_start_stop" ]; then _jak="CW znow przychodza po restarcie oscama"
        else _jak="CW znow przychodza"
        fi
        zdarzenie STOP-KONIEC "$_jak po ok. $((up - stoi_od))s od wykrycia - ${kanal:-?}"
        stoi_od=""
    fi

    # LOCK - tuner stracil synchronizacje (tylko z pomocnika; 10 s po zmianie
    # kanalu tuner jeszcze sie stroi)
    if [ "$tuner" -eq 1 ] && [ -n "$lock" ] && [ $((up - zmiana_od)) -ge 10 ]; then
        if [ "$lock" -eq 0 ] && [ "$lock_zly" -ne 1 ]; then
            lock_zly=1; zdarzenie LOCK "tuner bez synchronizacji ($_fe_st, SNR ${snr:-?}%, sila ${sila:-?}%) - ${kanal:-?}"
        elif [ "$lock" -eq 1 ] && [ "$lock_zly" -eq 1 ]; then
            lock_zly=0; zdarzenie LOCK-OK "synchronizacja wrocila (SNR ${snr:-?}%) - ${kanal:-?}"
        fi
    fi

    # OBRAZ - tuner pracuje, dekoder bez obrazu (do sprawdzenia, patrz naglowek)
    if [ "$tuner" -eq 1 ] && [ "$xres" = 0 ] && [ "$_spokoj" -eq 1 ]; then
        if [ "$obraz_zly" -ne 1 ]; then
            obraz_zly=1; obraz_od="$up"
            zdarzenie OBRAZ "tuner pracuje, dekoder bez obrazu (xres 0) - ${kanal:-?} (radio albo zamrozenie)"
        fi
    elif [ "$obraz_zly" -eq 1 ]; then
        obraz_zly=0
        zdarzenie OBRAZ-OK "po ok. $((up - obraz_od))s, xres $xres, tuner $tuner"
    fi

    # SYGNAL - tylko z pomiarow, 10 s po zmianie tuner jeszcze sie stroi
    if [ -n "$snr" ] && [ $((up - zmiana_od)) -ge 10 ]; then
        if [ "$snr" -lt "$SNR_ALERT" ] && [ "$snr_zly" -ne 1 ]; then
            snr_zly=1; zdarzenie SYGNAL "SNR ${snr}% < ${SNR_ALERT}% (sila ${sila:-?}%, BER ${ber:-?}) - ${kanal:-?}"
        elif [ "$snr" -ge $((SNR_ALERT + 5)) ] && [ "$snr_zly" -eq 1 ]; then
            snr_zly=0; zdarzenie SYGNAL-OK "SNR ${snr}% - ${kanal:-?}"
        fi
        if [ "$BER_ALERT" -gt 0 ] && [ -n "$ber" ]; then
            if [ "$ber" -gt "$BER_ALERT" ] && [ "$ber_zly" -ne 1 ]; then
                ber_zly=1; zdarzenie SYGNAL "BER $ber > $BER_ALERT (SNR ${snr}%) - ${kanal:-?}"
            elif [ "$ber" -le "$BER_ALERT" ] && [ "$ber_zly" -eq 1 ]; then
                ber_zly=0; zdarzenie SYGNAL-OK "BER $ber - ${kanal:-?}"
            fi
        fi
    fi

    # okno do Domoticza
    if [ -n "$snr" ]; then
        if [ -z "$okno_snr" ] || [ "$snr" -lt "$okno_snr" ]; then okno_snr="$snr"; fi
        if [ -n "$sila" ] && { [ -z "$okno_sila" ] || [ "$sila" -lt "$okno_sila" ]; }; then okno_sila="$sila"; fi
        if [ -z "$okno_ber" ] || [ "${ber:-0}" -gt "$okno_ber" ]; then okno_ber="${ber:-0}"; fi
    fi
    [ "$ecm_ms" -gt "$okno_ecm" ] && okno_ecm="$ecm_ms"
    okno_bledy=$((okno_bledy + n_err))

    if [ "$TRYB" = raz ]; then
        if [ -z "$tv_nowy" ]; then _tv_raz="nic (brak zdarzen z TV_TYPY: ${TV_TYPY:-wylaczone})"
        elif [ "$tuner" -ne 1 ]; then _tv_raz="nic - $tv_nowy, ale dekoder w standby"
        else _tv_raz="pokazalby komunikat $tv_nowy - tresc nizej"
        fi
        cat <<EOF
czas         $(stempel)  (uptime ${up}s)
dekoder      tuner: $([ "$tuner" -eq 1 ] && echo pracuje || echo standby)  (enigma2 trzyma: ${dvb_fd:-nic z /dev/dvb})  vmpeg xres=$xres  hdmi=${hdmi:-?}
sygnal       $([ -n "$zrodlo" ] && echo "lock=${lock:--}  SNR=${snr:--}%  sila=${sila:--}%  BER=${ber:--}  (zrodlo: $zrodlo)" || echo "brak odczytu - tuner nie pracuje, OpenWebif nie pytany")
oscam        $([ -z "$os" ] && echo "NIE ODPOWIADA" || { [ "$os_ok" -eq 1 ] && echo odpowiada || echo "odpowiada NIECZYTELNIE (bez starttime)"; })  start=${os_start:-?}
  dvbapi     SID=${dvb_sid:--}  kanal=${kanal:--}
  czytniki   ${czytniki:--}  -> $([ -n "$czyt_problem" ] && echo "problem: $czyt_problem (CZYTNIK dopiero po 2 probkach; polaczonych: $czyt_ok - $([ "$czyt_ok" -gt 0 ] && echo bez naprawy sieci || echo naprawa sieci po NAPRAWA_PO s))" || echo "ok (linii ecm: $n_ecm)")
ecm.info     $([ -n "$ecm_wiek" ] && echo "${ecm_wiek}s temu" || echo "brak pliku")
log          linii: $n_nowe, bledow: $n_err, w tym dropping ECM: $n_drop, max czas ECM: ${ecm_ms} ms
incydent     $([ -n "$inc_nowy" ] && echo "powstalby plik zdarzenie_..._${inc_nowy}.log" || echo "nie (brak zdarzenia z: $INCYDENT_TYPY)")
ekran TV     $_tv_raz
zasoby       rootfs ${z_rootfs:-?}%  $LOG_MOUNT ${z_hdd:--}%  RAM ${z_ram:-?}%  CPU ${z_cpu:-?}% (z 2 s)  load $(cut -d' ' -f1-3 /proc/loadavg)
dysk         $([ -n "$z_hdd_temp" ] && echo "${z_hdd_temp} C" || echo "bez temperatury - uspiony albo brak smartctl")  wentylator PWM $(cat "$FAN_CTRL" 2>/dev/null || echo ?) $([ "$FAN" -eq 1 ] && echo "(FAN=1: rampa od ${FAN_GORACO} C, co ${FAN_KROK} C, ${FAN_PWM_MIN}-${FAN_PWM})" || echo "(FAN=0: rzadzi firmware)")
EOF
    else
        [ -f "$RAM_DIR/probki.csv" ] || echo "$NAGLOWEK" > "$RAM_DIR/probki.csv"
        echo "$(stempel);$up;$tuner;$dvb_fd;$xres;$hdmi;$kanal;$dvb_sid;$ecm_wiek;$lock;$snr;$sila;$ber;$zrodlo;$czytniki;$n_err;$n_drop;$ecm_ms" >> "$RAM_DIR/probki.csv"
    fi
}

# --- Start -----------------------------------------------------------------

# DHCP=auto: tak, jesli klient DHCP dziala juz przy starcie monitora.
# Box z adresem stalym zostaje przy nim - udhcpc zamienilby go na dzierzawe.
if [ "$DHCP" = auto ]; then
    if dhcp_dziala; then DHCP=1; else DHCP=0; fi
fi

if [ "$TRYB" = raz ]; then
    echo "nbox_monitor --raz: jeden przebieg, nic nie jest zapisywane ani wysylane"
    cpu_zmierz; sleep 2; zasoby; hdd_temp
    przebieg
    if [ "$NAPRAWA" -eq 1 ]; then
        diagnoza
        echo "siec         $d_txt -> przy problemie czytnika: $d_opis (nic nie zrobiono)"
    else
        echo "siec         NAPRAWA=0 - bez diagnozy i naprawy"
    fi
    _typ="${tv_nowy:-STOP}"
    _txt=$(tv_tresc "$_typ" "$tv_opis")
    echo
    echo "################ ekran TV: komunikat $_typ (nic nie wyslano)"
    printf '%s\n' "${_txt:-(przy $_typ nic by sie nie pokazalo)}"
    echo "--- URL: $E2_URL/web/message?text=$(url_kod "$_txt")&type=$TV_TYP&timeout=$TV_CZAS"
    if [ "$POKAZ_INCYDENT" -eq 1 ]; then
        echo
        echo "################ tak wygladalby plik incydentu (nic nie zapisano)"
        incydent_tresc "${inc_nowy:-POKAZ}" "${inc_txt:-podglad na zadanie --pokaz-incydent}"
    fi
    exit 0
fi

if [ "$TRYB" = test_tv ]; then
    # przykladowy STOP z przyczyna sieciowa, niezaleznie od stanu tunera
    kanal="(kanal testowy)"; os=test; czyt_problem=test; n_drop=0
    _txt=$(printf 'TEST nbox_monitor - %s\n\n%s' "$NAZWA" "$(tv_tresc STOP)")
    printf '%s\n' "$_txt"
    if tv_wyslij "$_txt"; then echo "--- wyslane na $E2_URL"; exit 0; fi
    echo "--- NIE PRZESZLO: $E2_URL/web/message nie odpowiada" >&2
    exit 1
fi

if [ "$TRYB" = test_dz ]; then
    if [ "$DOMOTICZ" -ne 1 ]; then
        echo "Domoticz wylaczony: brak DOMOTICZ_HOST w /root/nbox_monitor.conf" >&2
        exit 1
    fi
    echo "Domoticz ${DOMOTICZ_HOST}:${DOMOTICZ_PORT}, NAZWA=$NAZWA"
    if dz_notify "$NAZWA: test nbox_monitor" "powiadomienie testowe, $(stempel)"; then
        echo "powiadomienie  wyslane"
    else
        echo "powiadomienie  BLAD - Domoticz nie odpowiada"
    fi
    test_wyslij() {   # $1 zmienna, $2 idx, $3 wartosc
        if [ -z "$2" ]; then echo "$1  pominiete - brak idx w konfiguracji"
        elif [ -z "$3" ]; then echo "$1  pominiete - brak odczytu"
        elif dz_update "$2" "$3"; then echo "$1  $3 -> idx $2"
        else echo "$1  BLAD przy idx $2"
        fi
    }
    dz_start
    cpu_zmierz; sleep 2; zasoby; hdd_temp
    test_wyslij DZ_ROOTFS "$idx_rootfs" "$z_rootfs"
    test_wyslij DZ_HDD "$idx_hdd" "$z_hdd"
    test_wyslij DZ_RAM "$idx_ram" "$z_ram"
    test_wyslij DZ_CPU "$idx_cpu" "$z_cpu"
    test_wyslij DZ_HDD_TEMP "$idx_hdd_temp" "$z_hdd_temp"
    exit 0
fi

if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
    echo "nbox_monitor juz dziala (pid $(cat "$PIDF"))" >&2
    exit 0
fi
mkdir -p "$RAM_DIR" || exit 1
[ "$DOMOTICZ" -eq 1 ] && dz_start
echo $$ > "$PIDF"
trap '[ -n "$sygnal_pid" ] && kill "$sygnal_pid" 2>/dev/null; rm -f "$PIDF"; exit 0' INT TERM

logger -t "$TAG" "start: POLL=${POLL}s ECM_STALL=${ECM_STALL}s incydenty=[$INCYDENT_TYPY] -> $LOG_DIR, RAM=$RAM_DIR, Domoticz=$DOMOTICZ"
start_pomocnika
# Start monitora = zwykle start boxa; w Domoticzu widac wtedy restarty, np.
# ten po REBOOT_PO s bez bramy albo internetu.
if [ "$DOMOTICZ" -eq 1 ] && [ -n "$idx_zdarzenie" ]; then
    dz_tekst "start monitora, uptime $(uptime_s) s"
fi

_t=$(uptime_s)
nast_raport=$((_t + REPORT))
nast_rotacja=$((_t + ROTACJA))
while :; do
    _t0=$(uptime_s)
    przebieg
    po_przebiegu
    if [ -n "$sygnal_pid" ] && ! kill -0 "$sygnal_pid" 2>/dev/null; then
        logger -t "$TAG" "pomocnik sygnalu (pid $sygnal_pid) nie dziala - restart"
        sygnal_pid=""
        start_pomocnika
    fi
    _t=$(uptime_s)
    if [ "$_t" -ge "$nast_raport" ]; then raport; nast_raport=$((_t + REPORT)); fi
    if [ "$_t" -ge "$nast_rotacja" ]; then
        rotuj "$RAM_DIR/probki.csv" "$PROBKI_MAX"
        rotuj "$RAM_DIR/zdarzenia.log" "$ZDARZENIA_MAX"
        rotuj "$RAM_DIR/oscam_bledy.log" "$ZDARZENIA_MAX"
        nast_rotacja=$((_t + ROTACJA))
    fi
    _t=$(uptime_s)
    [ $((_t - _t0)) -lt "$POLL" ] && sleep $((POLL - (_t - _t0)))
done
