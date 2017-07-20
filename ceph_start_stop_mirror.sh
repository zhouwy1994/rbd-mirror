#!/bin/bash

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun




function usage () {
	echo "Usage $0 -on < -i  remote ip ... >[-off < -i  remote ip ... > ] [-h | --help] "
	echo -e "\t-on: start rbd-mirror.sh process"
	echo -e "\t-off: stop rbd-mirror.sh process"
	echo -e "\t -h | -help : help info"
}


function start_syncing () {

add_log
add_log "INFO" "Start syncing..."
shift 1 
while true
do
		if [ x = x"$2" ]
		then 
			break
		else
			checkIP $2
			if [ $? -ne 0 ]
			then 
				add_log "INFO" "Start syncing failed"
				exit checkIP $2
			else
				timeout 3 ssh ${remote_user}@$2 "${SHELL_DIR}/rbd-mirror.sh &"
				add_log "INFO" "Start syncing ok at $2"
			fi
		fi
	shift 2 
done


}

function stop_syncing () {


add_log
add_log "INFO" "Stop syncing..."

shift 1 
while true
do
	if [ x = x"$2" ]
	then 
		break
	else
		checkIP $2
		if [ $? -ne 0 ]
		then 
			add_log "INFO" "Start syncing failed"
			exit checkIP $2
		else
		ssh ${remote_user}@$2 "pgrep rbd-mirror.sh | xargs kill -9 "
			add_log "INFO" "Start syncing ok at $2"
		fi

	fi
	shift 2 
done

add_log "INFO" "Stop syncing ok"
}

while true
do
	case $1 in
		-on)
			start_syncing $@ ; 
			break
		;;
		-off)
			stop_syncing  $@ ;
			break
		;;
		-h)
			usage ; exit 1 
		;;
		--help)
			usage ; exit 1 
		;;
		*)
			echo "Internal error!" ; usage ; exit 1 
		;;
	esac
done

