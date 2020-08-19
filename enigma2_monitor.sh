#!/bin/sh -x
#
# Copyright (C) 2018
#
# This is free software, licensed under the GNU General Public License v2.
#
# initial Version
# TO DO:
# add support to display on TV only when STB is in active mode
# fan speed base on disk temperature
# report to domoticz: disk temp, disk state (active, idle), fan speed,


addressInternet="8.8.8.0" # address internet
addressServer="google.pl" # address server

periodSuccess=6 			#How often we should check if the host is ping-able in seconds when previous success 
					#Other acction will be served with the same period
AcceptableFailureTime=90		#How long server can be unavailable before take action in seconds


RecoveryAction() {
	InternatAvailable="$1"

	if [ "$InternatAvailable" -ge 1 ]; then
		date
	else
		date
	fi
}

Notification() {
  #notification_status 0 - all OK #1 - brak serwer, 2 - brak internetu,
  InternatAvailable="$1"
	PreviousNotification="$2"

	# jak sprawdzić, czy tuner pracuje, czy jest w standby?
  tuner0=$(cat /proc/stb/vmpeg/0/aspect)
  tuner1=$(cat /proc/stb/vmpeg/1/aspect)
  # echo "$a0"
  # echo "$a1"
  if [ $tuner0 -eq 1 ] || [ "$tuner1" -eq 1 ]; then
    	if [ "$PreviousNotification" -eq 0 ]; then
		    if [ "$InternatAvailable" -eq 1 ]; then
		      /usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Serwer%20jest%20niedostępny%0AInternet%20działa&type=1&timeout=5"
		      return 1
	      else
	        /usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Nie%20ma%20Internetu&type=1&timeout=5"
		      return 2
	      fi
	    elif [ "$PreviousNotification" -eq 1 ]; then
		    if [ "$InternatAvailable" -eq 1 ]; then
		      return 1
	      else
	        /usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Nie%20ma%20Internetu&type=1&timeout=5"
		      return 2
	      fi
	    elif [ "$PreviousNotification" -eq 2 ]; then
		    if [ "$InternatAvailable" -eq 1 ]; then
		      /usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Serwer%20jest%20niedostępny%0AInternet%20działa&type=1&timeout=5"
		      return 1
	      else
		      return 2
	      fi
	    else
		    /usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Serwer%20jest%20niedostępny%0AInternet%20działa&type=1&timeout=5"
	    fi
  else
    return $PreviousNotification
  fi
}

monitor() {
	local periodSuccess="$1"; local AcceptableFailureTime="$2"; local addressServer="$3"; local addressInternet="$4"

	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"
	time_lastcheck="$time_now"
	#time_lastcheck_withinternet="$time_now"
  notification_status=0 #1 - brak serwer, 2 - brak internetu,

	while true
	do
		# account for the time ping took to return. With a ping time of 5s, ping might take more than that, so it is important to avoid even more delay.
		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_diff="$((time_now-time_lastcheck))"

		[ "$time_diff" -lt "$periodSuccess" ] && {
			sleep_time="$((periodSuccess-time_diff))"
			sleep "$sleep_time"
		}

		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_lastcheck="$time_now"

		if ping -c 1 -W 1 "$addressServer" &> /dev/null
		then
			time_lastcheck_withhost="$time_now"
			if [ "$notification_status" -ne 0 ]; then
			  notification_status=0
			fi
		else
			time_diff="$((time_now-time_lastcheck_withhost))"
#			logger -p daemon.info -t "watchcat[$$]" "no internet connectivity for $time_diff seconds. Reseting when reaching $period"
		fi

		time_diff="$((time_now-time_lastcheck_withhost))"
		if [ "$time_diff" -ge "$AcceptableFailureTime" ]; then
			if ping -c 3 -W 1 "$addressInternet" &> /dev/null
			then
			  Notification "1" $notification_status
			  notification_status=$?
				RecoveryAction "1"
			else
			  Notification "0" $notification_status
			  notification_status=$?
				RecoveryAction "0"
			fi
		fi
	done
}

monitor "$periodSuccess" "$AcceptableFailureTime" "$addressServer" "$addressInternet"

