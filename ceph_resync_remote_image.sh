#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

set -e
#set -x

add_log
add_log "INFO" "`hostname`: resync remote image ..."
add_log "INFO" "$0 $*"

function usage()
{
        echo "Usage:$0 -p|--pool-name <pool name> -n|--image-name <image name> -i|--remote-ipaddr | [-h|--help]"
        echo "-p, --pool-name <pool name>"
        echo -e "\t\tpool name."

        echo "-n, --image-name <image name>"
        echo -e "\t\timage name."

        echo "-i, --remote-ipaddr <remote ipaddr>"
        echo -e "\t\tremote ipaddress."

        echo "[-h, --help]"
        echo -e "\t\thelp info"
}

TEMP=`getopt -o p:n:i:h --long pool-name:,image-name:,remote-ipaddr:,help -n 'note' -- "$@"`
if [ $? != 0 ]; then
    echo "parse arguments failed."
    exit 1
fi

eval set -- "${TEMP}"
pool_name=""
image_name=""
remote_ipaddr=""
res="" 
fail_msg="resync rbd mirror  failed"
success_msg="resync rbd mirror successfully"
while true 
do
    case "$1" in
        -p|--pool-name) pool_name=$2; shift 2;;
        -n|--image-name) image_name=$2; shift 2;;
        -i|--remote-ipaddr) remote_ipaddr=$2; shift 2;;
        -h|--help) usage; exit 1;;
        --) shift; break;;
        *) echo "Internal error!"; exit 1;;
    esac
done

function check_remote_leader()
{
	readonly all_quorum_ip_local=$(sudo ceph -s --cluster local 2>/dev/null\
	| egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b")

	readonly all_quorum_ip_remote=$(sudo ceph -s --cluster remote  2>/dev/null\
	| egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b")
	
	readonly remote_leader_hostname=$(sudo ceph quorum_status --cluster remote 2>/dev/null\
	| sed s/.*quorum_leader_name\":\"//g|sed s/\".*$//g)
	readonly remote_leader_ipaddr=$(sudo ceph quorum_status  --cluster remote 2>/dev/null\
	| sed s/^.*\"$remote_leader_hostname\",\"addr\":\"//g|sed s/:.*$//g)
}

function check_pool() {
	sudo rados df |grep -w $pool_name &>/dev/null
	if [ $? -eq 0 ] ;then 
	add_log "INFO" "local: local_pool#$pool_name is exist"
	else
		add_log "ERROR" "arguments: -p local_pool#$pool_name is not exist"
		my_exit 1 "$fail_msg" "arguments: -p local_pool#$pool_name is not exist"
	fi
	ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rados df |grep -w $pool_name &>/dev/null"
	if [ $? -eq 0 ] ;then
	add_log "INFO" "remote: remote_pool#$pool_name is exist"
	else
	add_log "ERROR" "arguments: -p remote_pool#$pool_name is not exist"
	my_exit 1 "$fail_msg" "arguments: -p remote_pool#$pool_name is not exist"
	fi
}
function check_image() {
	sudo rbd info $pool_name/$image_name &>/dev/null
	if [ $? -eq 0 ] ;then
	add_log "INFO" "local: local_image#$pool_name/$image_name is exist"
	else
		add_log "ERROR" "arguments: -n local_image#$pool_name#$image_name is not exist"
		my_exit 1 "$fail_msg" "arguments: -n local_image#$image_name#$image_name is not exist"
	fi
	ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd info $pool_name/$image_name &>/dev/null"
	if [ $? -eq 0 ] ;then
	add_log "INFO" "remote: remote_image#$pool_name/$image_name is exist"
	else
		add_log "ERROR" "arguments: -n remote_image#$pool_name#$image_name is not exist"
		my_exit 1 "$fail_msg" "arguments: -n remote_image#$image_name#$image_name is not exist"
	fi
	
}
function check_ip() {
	local res
	
	# $(timeout 5 ssh -o StrictHostKeyChecking=no "$user_name"@"$1" 'exit' &>/dev/null) || \
	#my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	if ! res=$(echo "$1" | egrep "([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}" 2>&1);then
		add_log "ERROR" "remote ip address is invalid"
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	if ! res=$(sudo timeout 5 ceph -s -m "$1":6789);then
		add_log "ERROR" "There is no cluster on the ip"
		my_exit 1 "$fail_msg" "There is no cluster on the ip"
	fi
	
	if [[ "$1" != "$remote_leader_ipaddr" ]];then
    add_log "ERROR" "The remote cluster is unreachable"
    my_exit 1 "$fail_msg" "The remote cluster is unreachable"
    fi

}

function main() {
#local remote_key="admin"
#local remote_user=denali
local rbd_mirror_statu=`sudo rbd info $pool_name/$image_name |grep 'mirroring state' |sed 's/.*state: //g'`
if [ $? -eq 0 ] ;then
                  add_log "INFO" "local: get rbd mirror image#$image_name status successfully"
else
                  add_log "ERROR" "local: get rbd mirror image#$image_name status false"
                  my_exit 2 "$fail_msg" "local: get rbd mirror image#$image_name status false"
fi


if [ $rbd_mirror_statu == "enabled" ]
then
	
	#sshpass -p $remote_key ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr " ps -ef |grep -w 'rbd-mirror'| grep -v 'grep' &>/dev/null"
	ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr " ps -ef |grep -w 'rbd-mirror'| grep -v 'grep' &>/dev/null"
	if [ $? -eq 0 ] ;then
	#sshpass -p "$remote_key" ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image resync $pool_name/$image_name"
	# resync remote image
	ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image resync $pool_name/$image_name"
	if [ $? -eq 0 ] ; then
		add_log "INFO" "remote: rbd_mirror resync is successfully"
 		exit 0
	else
 		echo "rbd_mirror resync is false "
		add_log "ERROR" "remote: rbd mirror resync image#$image_name false"
 		my_exit 3 "$fail_msg" "remote: rbd mirror resync image#$image_name false"
	fi
	else
		add_log "ERROR" "remote: rbd mirror process is not exist"
		my_exit 5 "$fail_msg" "remote: rbd mirror process is not exist"
	fi
else
	add_log "ERROR" "local: rbd image#$image_name is disable"
    my_exit 4 "$fail_msg" "local: rbd image#$image_name is disable"
fi
	
}
err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ipaddr}" ];then
  #set -x
  check_remote_leader
  check_ip "${remote_ipaddr}" 
  check_pool "${pool_name}"
  check_image "${image_name}"
  main "${pool_name}" "${image_name}" "${remote_ipaddr}" 
   #set +x
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}" $print_log
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
