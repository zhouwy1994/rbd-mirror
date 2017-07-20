#!/bin/bash 

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun
remote_ip=
if [ ! -f /var/log/ceph/ceph_rbd_mirror.log ]
then 
	sudo touch /var/log/ceph/ceph_rbd_mirror.log;
	sudo chmod 777 /var/log/ceph/ceph_rbd_mirror.log
fi

#set -x
TEMP=`getopt -o i:h --long ip:,help  -n 'ceph_connect_cluster.sh' -- "$@"`

if [ $? != 0  ] 
 then 
	echo "parse arguments failed." ; exit 1
fi

eval set -- "${TEMP}"

function usage () {
	echo "Usage:$0 -i| --ip <ip addr> -n | --name <user name>  -p | --passwd  <user passwd> [-h | --help]"
	echo "-i,--ip <remote ip>"
	echo "[-h| --help]"
	echo -e "\thelp info"
}

while true
do
	case "$1" in
	-i | --ip) remote_ip=$2;shift 2;;
	-h | --help) usage ; exit 1;;
	--) shift; break;;
	*) echo "Internal error!"; exit 1;;
	esac
done


checkIP ${remote_ip}
if [ $? -ne 0 ]
then 
	echo "Ip address is not legal"
	exit -1
fi

add_log 
add_log "INFO" "local cluster connect  remote cluster ..."
add_log "INFO" "$0 $*"




function add_passwd () {


echo  | ssh-keygen -t rsa -P ''	&>/dev/null 

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
curl -d "key=9aa0c25394c6a057d5fa5fcfb9a97ab4&path=/home/denali/.ssh/authorized_keys&secret=${str}" "http://${remote_ip}:8333/api/1.1/safe-command/setSSHPasswordKey"

if [ $? -ne 0 ]
then 
	echo "add_passwd key error "
	exit 1
fi

ssh -o StrictHostKeyChecking=no denali@${remote_ip} "pwd"
if [ $? -ne 0 ]
then 
	echo "add_passwd key error "
	exit 1
fi



}

function copy_to_remote () {


if ! sudo chmod 777  ${conf_dir}/ceph.client.admin.keyring
then 
	add_log "ERROR" "local : No such file or directory !" ;
	echo "local : No such file or directory !(ceph.client.admin.keyring)"
	exit 1
fi
if ! sudo chmod 777  ${conf_dir}/ceph.conf
then 
	add_log "ERROR" "local : No such file or directory or permission denied" ;
	echo "local : No such file or directory !(ceph.conf)"
	exit 1
fi

sudo cp ${conf_dir}/ceph.conf ${conf_dir}/local.conf 
sudo cp ${conf_dir}/ceph.client.admin.keyring ${conf_dir}/local.client.admin.keyring

if ! scp  ${conf_dir}/ceph.conf  ${remote_user}@${remote_ip}:~/local.conf 
then 
	echo "copy_for_remote error "
	exit 1
fi
if ! scp  ${conf_dir}/ceph.client.admin.keyring ${remote_user}@${remote_ip}:~/local.client.admin.keyring 
then 
	echo "copy_for_remote error "
	exit 1
fi

ssh ${remote_user}@${remote_ip} "sudo mv ~/local.c* ${conf_dir}/"
#ssh ${remote_user}@${remote_ip} "sudo chmod 600 ${conf_dir}/local.client.admin.keyring"
#sudo chmod 600 ${conf_dir}/ceph.client.admin.keyring

}

function copy_for_remote () {


if ! ssh ${remote_user}@${remote_ip} "sudo chmod 777 ${conf_dir}/ceph.client.admin.keyring"
then 
	add_log "ERROR" "remote : No such file or directory or permission denied" ;
	echo "remote  : No such file or directory !(ceph.client.admin.keyring)"
	exit 1
fi
if ! ssh ${remote_user}@${remote_ip} "sudo chmod 777 ${conf_dir}/ceph.conf"
then 
	add_log "ERROR" "remote : No such file or directory or permission denied" ;
	echo "remote  : No such file or directory !(ceph.conf)"
	exit 1
fi
scp -p ${remote_user}@${remote_ip}:${conf_dir}/ceph.conf ~/remote.conf 
scp -p ${remote_user}@${remote_ip}:${conf_dir}/ceph.client.admin.keyring ~/remote.client.admin.keyring 
#ssh ${remote_user}@${remote_ip} "sudo chmod 600 ${conf_dir}/ceph.client.admin.keyring"
ssh ${remote_user}@${remote_ip}  "sudo cp ${conf_dir}/ceph.conf ${conf_dir}/remote.conf"
ssh ${remote_user}@${remote_ip}  "sudo cp ${conf_dir}/ceph.client.admin.keyring ${conf_dir}/remote.client.admin.keyring"
sudo mv ~/remote.c* ${conf_dir}/
#sudo chmod 600 ${conf_dir}/remote.client.admin.keyring

}

function test_link () {

sudo ceph -s --cluster remote &>/dev/null

if [ $? -eq 0 ]
then
	ssh  ${remote_user}@${remote_ip} 'sudo ceph -s --cluster local' &>/dev/null
	if [ $? -eq 0 ] 
	then 
		add_log "INFO" "cluster connect  successful ..." ;
		exit 0
	else
		add_log "ERROR" "cluster connect failed" ;
		exit 1
	fi
else 
	add_log "ERROR" "cluster connect failed" ;
	exit 1
fi
}
add_passwd

copy_to_remote


copy_for_remote

test_link


