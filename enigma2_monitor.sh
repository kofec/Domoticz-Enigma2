#!/bin/sh
#
# Copyright (C) 2018
#
# This is free software, licensed under the GNU General Public License v2.
#
# initial Version

addressInternet=8.8.8.8 # address internet
addressServer=google.pl # address server

periodSuccess=60 			#How often we should check if the host is ping-able in seconds when previous success 
periodFailure=5 			#How often we should check if the host is ping-able in seconds when previous fail
AcceptableFailureTime=90	#How long server can be unavailable before take action 


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
	local periodSuccess="$1"; local periodFailure="$2"; local AcceptableFailureTime="$3"; local addressServer="$4"; local addressInternet="$5"

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

		[ "$time_diff" -lt "$pingperiod" ] && {
			sleep_time="$((pingperiod-time_diff))"
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
		if [ "$time_diff" -ge "$period" ]; then
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
		watchcat_ping_only "$periodSuccess" "$periodFailure" "$AcceptableFailureTime" "$addressServer" "$addressInternet"
	fi