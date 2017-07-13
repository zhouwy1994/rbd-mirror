#!/bin/bash

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun




function usage () {
	echo "Usage $0 -on [-off] [-h | --help] "
	echo -e "\t-on: start rbd-mirror process"
	echo -e "\t-off: stop rbd-mirror process"
	echo -e "\t -h | -help : help info"
}


function start_syncing () {

add_log
add_log "INFO" "Start syncing..."

rbd_pid=`ssh ${remote_user}@${remote_ipaddr} "pidof rbd-mirror"`

if [ x"${rbd_pid}" = x ] 
then
	ssh ${remote_user}@${remote_ipaddr} "sudo rbd-mirror  --setuser root --setgroup root --cluster remote -i admin"	
else
	add_log "WARNING" "the process is running"
	add_log "INFO" "start syncing successful"
	exit 0
fi

pid=`ssh  ${remote_user}@${remote_ipaddr} "pidof rbd-mirror"`

if [ x"${pid}" = x ] 
then
	add_log "ERROR" "start process failed" ;
	exit 1
else
	add_log "INFO" "start syncing successful" ;
	exit 0
fi

}

function stop_syncing () {


add_log
add_log "INFO" "Stop syncing..."

rbd_pid=`ssh ${remote_user}@${remote_ipaddr} "pidof rbd-mirror"`

if [ x"${rbd_pid}" = x ] 
then
	add_log "WARNING" "Not have rbd-mirror pid "
	add_log "INFO" "stop syncing successful"
	exit 0
fi

ssh ${remote_user}@${remote_ipaddr} "sudo kill -9 ${rbd_pid}"
pid=`ssh  ${remote_user}@${remote_ipaddr} "pidof rbd-mirror"`

if [ x"${pid}" = x ] 
then
	add_log "INFO" "stop syncing successful" ;
	exit 0
else
	add_log "ERROR" "kill process failed" ;
	exit 1
fi

}

while true
do
	case $1 in
		on)
			start_syncing 
		;;
		off)
			stop_syncing 
		;;
		-h)
			usage ; exit 1 
		;;
		--help)
			usage ; exit 1 
		;;
		*)
			echo "Internal error!" ; exit 1 
		;;
	esac
done

