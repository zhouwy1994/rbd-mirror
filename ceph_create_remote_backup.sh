#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_log

#set -e
#set -x

add_log
add_log "INFO" "`hostname`: create remote backup..."
add_log "INFO" "$0 $*"

function usage()
{
        echo "Usage:$0 -p|--pool-name <pool name> -n|--image-name <image name> -i|--remote-ipaddr | [-h|--help]"
        echo "-p, --pool-name <pool name>"
        echo -e "\t\tpool name."

        echo "-n, --image-name <image name>"
        echo -e "\t\timage name."

        echo "-i, --remote-ipaddr <cluster ipaddr>"
        echo -e "\t\cluster ipaddress."

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
user_name="$remote_user"
fail_msg="create remote backup failed"
success_msg="create remote backup successfully"

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

function check_remote_cluster_ip()
{
	local res
	
	$(timeout 5 ssh -o StrictHostKeyChecking=no "$user_name"@"$1" 'exit' &>/dev/null) || \
	my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	if ! local res=$(echo "$1"	| egrep "([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}" 2>&1);then
		add_log 
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	if ! res=$(sudo timeout 5 ceph -s -m "$1":6789);then
		my_exit 3 "$fail_msg" "There is no cluster on the ip"
	fi
}

function check_pool_exist()
{
	local res
	if ! sudo ceph osd pool ls --cluster remote | grep -w $1 &>/dev/null;then
		ssh $user_name@$remote_ipaddr \
		"sudo bash $(dirname ${SHELL_DIR})/ceph_create_pool.sh -t replicated -p "$1" -d 5.47397449 -s 2 &>/dev/null"
		if [ $? -ne 0 ];then
			add_log "ERROR" "remote:Create remote pool $1 Failed"
			my_exit 4 "Create remote pool $1 Failed"
		else
			add_log "INFO" "remote:Create remote pool $1 Successfully!!"
		fi
	else
		if  res=$(sudo rbd info $1/$2 --cluster remote 2>&1);then
			add_log "ERROR" "remote images already exist"
			my_exit 5 "$fail_msg" "Remote images already exist"
		fi
		
		add_log "INFO" "remote:remote pools $1 exist!!"
	fi
}

function check_pool_image_exist()
{
	local res 
	
	if ! sudo ceph osd pool stats $1 &>/dev/null;then
		add_log "ERROR" "Local Pools $1 is not exist"
		my_exit 1 "$fail_msg" "Pools $1 is not exist"
	fi
	
	if ! res=$(sudo rbd info $1/$2 --cluster local 2>&1);then
			add_log "ERROR" "Local images $2 is not exist"
			my_exit 1 "$fail_msg" "Local images $2 is not exis"
	fi
}

function create_backup()
{
	sudo rbd mirror pool enable $1 image --cluster local &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "local:Enable local pool $1 successfully mode:image!!"
	else
		add_log "ERROR" "local:Enable local pool $1 failed mode:image!!"
		my_exit 6 "Create remote backup Failed" "Enable local pool $1 failed mode:image"
	fi
	
	sudo rbd mirror pool enable $1 image --cluster remote &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "remote:Enable remote pool $1 successfully mode:image!!"
	else
		add_log "ERROR" "remote:Enable remote pool $1 failed mode:image!!"
		my_exit 6 "Create remote backup Failed" "Enable remote pool $1 failed mode:image"
	fi
	
	sudo rbd mirror pool peer add $1 client.admin@local --cluster remote &>/dev/null
	if [ $? -eq 0 -o $? -eq 17 ];then
		add_log "INFO" "remote:Add to remote pool peer successfully"
	else
		add_log "ERROR" "remote:Add to remote pool peer failed"
		my_exit 7 "Create remote backup Failed" "Add to remote pool peer failed"
	fi
	
	sudo rbd mirror pool peer add $1 client.admin@remote --cluster local &>/dev/null
	if [ $? -eq 0 -o $? -eq 17 ];then
		add_log "INFO" "local:Add to local pool peer successfully"
	else
		add_log "ERROR" "local:Add to local pool peer failed"
		my_exit 7 "Create remote backup Failed" "Add to local pool peer failed"
	fi
	
	if ! sudo rbd info -p $1 $2 --cluster local | grep  features | grep -w exclusive-lock &>/dev/null;then
		rbd feature enable $1/$2 exclusive-lock --cluster local
	fi
	
	if ! sudo rbd info -p $1 $2 --cluster local | grep  features | grep -w journaling &>/dev/null;then
		sudo rbd feature enable $1/$2 journaling --cluster local
	fi
	
	sudo rbd mirror image enable $1/$2 --cluster local &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "local:Enable local $1/$2 mirror successfully"
	else
		add_log "ERROR" "local:Enable local image $1/$2 mirror failed"
		my_exit 8 "Create remote backup Failed" "Enable local image $1/$2 mirror failed"
	fi
	
	if ! $user_name@$remote_ipaddr 'pidof rbd-mirror &>/dev/null';then
		ssh $user_name@$remote_ipaddr \
		'sudo rbd-mirror --setuser root --setgroup root -i admin --cluster remote & &>/dev/null'
		if [ $? -eq 0 ];then
		add_log "INFO" "remote:Start rbd-mirror process successfully"
		else
		add_log "ERROR" "remote:Start rbd-mirror process failed"
		my_exit 8 "Create remote backup Failed" "Start rbd-mirror process failed"
		fi
		
	fi
	
	add_log "INFO" "remote:Create backup successfully"
	my_exit 0 "Create remote backup successfully"
}
err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ipaddr}" ];then
    check_remote_cluster_ip "$remote_ipaddr"
	check_pool_image_exist "$pool_name" "$image_name"
	check_pool_exist "${pool_name}" "$image_name"
	create_backup "${pool_name}" "${image_name}"
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}"
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
