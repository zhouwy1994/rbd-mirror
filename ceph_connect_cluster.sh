#!/bin/bash 

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun
remote_passwd=
file=~/.ssh/id_rsa.pub

sudo touch /var/log/ceph/ceph_rbd_mirror.log
sudo chmod 777 /var/log/ceph/ceph_rbd_mirror.log

TEMP=`getopt -o i:n:p:h --long ip:,name:,passwd:,help  -n 'ceph_connect_cluster.sh' -- "$@"`

if [ $? != 0  ] 
 then 
	echo "parse arguments failed." ; exit 1
fi

eval set -- "${TEMP}"

function usage () {
	echo "Usage:$0 -i| --ip <ip addr> -n | --name <user name>  -p | --passwd  <user passwd> [-h | --help]"
	echo "-i,--ip <remote ip>"
	echo -e "\tremote ip to connect cluster, --ip 0.0.0.0 "
	echo "-n,--name <remote user name>"
	echo -e "\tremote user name, --name root"
	echo "-p,--passwd <remote user passwd>"
	echo -e "\tremote user passwd,--passwd admin"
	echo "[-h| --help]"
	echo -e "\thelp info"
}

while true
do
	case "$1" in
	-i | --ip)  echo "remote_ipaddr=$2">> ./common_rbd_mirror_fun;shift 2;;
	-n | --name) echo "remote_user=$2" >> ./common_rbd_mirror_fun;shift 2;;
	-p | --passwd) remote_passwd=$2; shift 2;;
	-h | --help) usage ; exit 1;;
	--) shift; break;;
	*) echo "Internal error!"; exit 1;;
	esac
done
add_log 
add_log "INFO" "local cluster connect  remote cluster ..."
add_log "INFO" "$0 $remote_ipaddr $remote_user"




function test_passwd () {

if [ ! -f ${file} ]
then  
	echo  | ssh-keygen -t rsa -P ''	&>/dev/null  
fi
set -e
if ! sshpass -p ${remote_passwd} ssh -o StrictHostKeyChecking=no ${remote_user}@${remote_ipaddr} 'pwd' &>/dev/null
then 
	exit -1
fi
#if ! ssh ${remote_user}@${remote_ipaddr} "exit" ; 
#then
sshpass -p ${remote_passwd} scp -o StrictHostKeyChecking=no  ~/.ssh/id_rsa.pub ${remote_user}@${remote_ipaddr}:~  
sshpass -p ${remote_passwd} ssh -o StrictHostKeyChecking=no ${remote_user}@${remote_ipaddr} 'cat ~/id_rsa.pub >> ~/.ssh/authorized_keys'
sleep 5

#fi
}

function copy_to_remote () {


if ! sudo chmod 777  ${conf_dir}/ceph.client.admin.keyring
then 
	add_log "ERROR" "local : No such file or directory or permission denied" ;
	exit 1
fi
if ! sudo chmod 777  ${conf_dir}/ceph.conf
then 
	add_log "ERROR" "local : No such file or directory or permission denied" ;
	exit 1
fi
sudo cp ${conf_dir}/ceph.conf ${conf_dir}/local.conf
sudo cp ${conf_dir}/ceph.client.admin.keyring ${conf_dir}/local.client.admin.keyring

scp  ${conf_dir}/ceph.conf  ${remote_user}@${remote_ipaddr}:~/local.conf 
scp  ${conf_dir}/ceph.client.admin.keyring ${remote_user}@${remote_ipaddr}:~/local.client.admin.keyring 
ssh ${remote_user}@${remote_ipaddr} "sudo mv ~/local.c* ${conf_dir}/"
ssh ${remote_user}@${remote_ipaddr} "sudo chmod 600 ${conf_dir}/local.client.admin.keyring"
sudo chmod 600 ${conf_dir}/ceph.client.admin.keyring

}

function copy_for_remote () {


if ! ssh ${remote_user}@${remote_ipaddr} "sudo chmod 777 ${conf_dir}/ceph.client.admin.keyring"
then 
	add_log "ERROR" "remote : No such file or directory or permission denied" ;
	exit 1
fi
if ! ssh ${remote_user}@${remote_ipaddr} "sudo chmod 777 ${conf_dir}/ceph.conf"
then 
	add_log "ERROR" "remote : No such file or directory or permission denied" ;
	exit 1
fi
scp -p ${remote_user}@${remote_ipaddr}:${conf_dir}/ceph.conf ~/remote.conf 
scp -p ${remote_user}@${remote_ipaddr}:${conf_dir}/ceph.client.admin.keyring ~/remote.client.admin.keyring 
ssh ${remote_user}@${remote_ipaddr} "sudo chmod 600 ${conf_dir}/ceph.client.admin.keyring"
ssh ${remote_user}@${remote_ipaddr}  "sudo cp ${conf_dir}/ceph.conf ${conf_dir}/remote.conf"
ssh ${remote_user}@${remote_ipaddr}  "sudo cp ${conf_dir}/ceph.client.admin.keyring ${conf_dir}/remote.client.admin.keyring"
sudo mv ~/remote.c* ${conf_dir}/
sudo chmod 600 ${conf_dir}/remote.client.admin.keyring

}

function test_link () {

sudo ceph -s --cluster remote &>/dev/null

if [ $? -eq 0 ]
then
	ssh  ${remote_user}@${remote_ipaddr} 'sudo ceph -s --cluster local' &>/dev/null
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
test_passwd
copy_to_remote
copy_for_remote
test_link



