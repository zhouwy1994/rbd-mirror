#!/bin/bash

while true 
do
	str=`redis-cli get is-monitor`
	if [ $str == "true" ]
	then 
		pid=`pidof rbd-mirror`
		if [ x = x"${pid}" ]
		then 
			sudo rbd-mirror --setuser root --setgroup root --cluster remote -i admin
		fi
	fi
done
