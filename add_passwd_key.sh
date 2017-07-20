#!/bin/bash

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun


TEMP=`getopt -o i:h --long ip:,help  -n 'ceph_connect_cluster.sh' -- "$@"`

if [ $? != 0  ] 
 then 
	echo "parse arguments failed." ; exit 1
fi

eval set -- "${TEMP}"



function add_key ()
{
add_log 
add_log "INFO" "Add passwd key ..."
checkIP $1
if [ $? -ne 0 ]
then 
	echo "$1 is not a ip addr"
	exit 2
fi

if [ ! -f ~/.ssh/id_rsa.pub ]
then
	echo  | ssh-keygen -t rsa -P ''	&>/dev/null 
fi

if ! keystr=`cat ~/.ssh/id_rsa.pub`
then 
	echo "passwd key file error"
	exit 1
fi
if ! str=`python -c "import urllib;print urllib.quote_plus('${keystr}')"`
then 
	echo "python function error"
	exit 1
fi
curl -d "key=9aa0c25394c6a057d5fa5fcfb9a97ab4&path=/home/denali/.ssh/authorized_keys&secret=${str}" "http://$1:8333/api/1.1/safe-command/setSSHPasswordKey"

if [ $? -ne 0 ]
then 
	echo "add_passwd key error "
	add_log "INFO" "Add passwd key failed !"
	exit 1
fi

timeout 10 ssh -o StrictHostKeyChecking=no denali@$1 "pwd"
if [ $? -ne 0 ]
then 
	echo "add_passwd key error "
	add_log "INFO" "Add passwd key failed !"
	exit 3
fi
add_log "INFO" "Add passwd key ok!"
}


function usage ()
{
	echo "Usage $0 -i | --ip <ip addr> [-h | --help]"
	echo "-i,--ip <To add a passwd ip addr>"
	echo -e "\tinput add passwd ip like -i 0.0.0.0 -i 0.0.0.0\t "
	echo "-h,--help"
	echo -e "\t help info"
}


while true
do
	case "$1" in
	-i | --ip) add_key $2 ; shift 2;;
	-h | --help) usage ; exit 1;; 
	--) shift ; break;;
	*)echo "Internal error!"; usage ; exit 1;;
	esac
done


