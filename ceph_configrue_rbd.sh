#!/bin/bash

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun
#set -x

echo $SHELL_DIR


function config_remote () {
	add_log
	add_log "INFO" "Configrue remote ..."
	shift 1
	${SHELL_DIR}/copy_to_remote.sh  $@
	num=$?
	if [ $num -ne 0 ]
	then
		add_log "INFO" "Configrue remote failed !"
		exit $num 
	fi
	add_log "INFO" "Configrue remote ok !"
}

function config_local () {
	add_log
	add_log "INFO" "Configrue local ..."
	ip=$2
	shift 2
	ssh ${remote_user}@${ip} "${SHELL_DIR}/add_passwd_key.sh $@"
	num=`ssh ${remote_user}@${ip} "echo $?"`
	if [ $num -ne 0 ]
	then
		add_log "INFO" "Configrue local failed !"
		exit $num 
	fi
	ssh ${remote_user}@${ip} "${SHELL_DIR}/copy_to_local.sh $@"
	num=`ssh ${remote_user}@${ip} "echo $?"`
	if [ $num -ne 0 ]
	then
		add_log "INFO" "Configrue local failed !"
		exit $num 
	fi
	add_log "INFO" "Configrue remote ok !"
}

while true
do
	case $1 in
	-l | --local)
		config_remote $@ ; break ;;
	-r | --remote)
		config_local $@ ; break ;;
	*) echo "Internal error!"; exit 1;;
	esac
done

