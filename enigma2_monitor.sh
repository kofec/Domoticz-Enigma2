#!/bin/sh
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


addressInternet=8.8.8.8 # address internet
addressServer=google.pl # address server

periodSuccess=60 			#How often we should check if the host is ping-able in seconds when previous success 
					#Other acction will be served with the same period
AcceptableFailureTime=90		#How long server can be unavailable before take action in seconds


RecoveryAction() {
	local InternatAvailable="$1"

	if [ "$InternatAvailable" -ge 1 ]; then
		/usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Nie%20ma%20Internetu&type=1&timeout=5"
	else
		/usr/bin/wget -q -O /dev/null "http://127.0.0.1/web/message?text=Serwer%20jest%20niedostępny%0AInternet%20działa&type=1&timeout=5"
	fi
}

watchcat_always() {
	local period="$1"; local forcedelay="$2"

	sleep "$period" && shutdown_now "$forcedelay"
}

watchcat_ping_only() {
	local periodSuccess="$1"; local AcceptableFailureTime="$2"; local addressServer="$3"; local addressInternet="$4"

	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"
	time_lastcheck="$time_now"
	time_lastcheck_withinternet="$time_now"

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


		if ping -c 1 "$addressServer" &> /dev/null
		then
			time_lastcheck_withhost="$time_now"
		else
			time_diff="$((time_now-time_lastcheck_withhost))"
#			logger -p daemon.info -t "watchcat[$$]" "no internet connectivity for $time_diff seconds. Reseting when reaching $period"
		fi

		time_diff="$((time_now-time_lastcheck_withhost))"
		if [ "$time_diff" -ge "$AcceptableFailureTime" ]; then
			if ping -c 4 "$addressInternet" &> /dev/null
				RecoveryAction "1"
			else
				RecoveryAction "0"
			fi
		fi
	done
}

	if [ "$mode" = "always" ]
	then
		watchcat_always "$2" "$3"
	else
		watchcat_ping_only "$periodSuccess" "$AcceptableFailureTime" "$addressServer" "$addressInternet"
	fi
