#!/bin/bash

#set -x
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

TEMP=`getopt -o i:h --long ip:,help  -n 'ceph_connect_cluster.sh' -- "$@"`

if [ $? != 0  ] 
 then 
	echo "parse arguments failed." ; exit 1
fi

eval set -- "${TEMP}"

function usage ()
{
	echo "Usage $0 -i | --ip <ip addr> [-h | --help]"
	echo "-i,--ip <To add a passwd ip addr>"
	echo -e "\tinput copy file to local ip like -i 0.0.0.0 -i 0.0.0.0\t "
	echo "-h,--help"
	echo -e "\t help info"
}



function copy ()
{
	add_log
	add_log "INFO" "Copy file to local..."

	if ! scp /etc/ceph/remote.c* ${remote_user}@$1:~
	then 
		echo "copy to remote failed! ip is $1"
		add_log "INFO" "Copy file to local failed ! ip is $1"
		exit 4
	fi
	ssh ${remote_user}@$1 "sudo mv remote.c* /etc/ceph/"
	if ! scp /etc/ceph/local.c* ${remote_user}@$1:~
	then 
		echo "copy to remote failed! ip is $1"
		add_log "INFO" "Copy file to local failed ! ip is $1"
		exit 4
	fi
	ssh ${remote_user}@$1 "sudo mv local.c* /etc/ceph/"
	echo "copy to $1 ok"
	add_log "INFO" "Copy file to local $1 ok!"
}


while true
do
	case $1 in 
	-i | --ip) copy $2; shift 2;;
	-h | --help) usage ; exit 1;;
	--) shift ; break ;;
	*) echo "Internal error!" ; exit 1;
	esac
done





