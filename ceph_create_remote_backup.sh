#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun


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
# cluster_ip="$remote_ipaddr"
remote_ip="" 
user_name="$remote_user"
fail_msg="Create remote backup failed"
success_msg="Create remote backup successfully"

while true
do
    case "$1" in
        -p|--pool-name) pool_name=$2; shift 2;;
        -n|--image-name) image_name=$2; shift 2;;
        -i|--remote-ipaddr) remote_ip=$2; shift 2;;
        -h|--help) usage; exit 1;;
        --) shift; break;;
        *) echo "Internal error!"; exit 1;;
    esac
done

function check_remote_cluster_ip()
{
	local res
	
	# $(timeout 5 ssh -o StrictHostKeyChecking=no "$user_name"@"$1" 'exit' &>/dev/null) || my_exit 2 "fail_msg" "The remote cluster is unreachable"
	if ! echo "$1" | egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b" &>/dev/null;then
		add_log "ERROR" "remote ip address is invalid"
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	timeout 3 ssh $user_name@$1 "pwd" &>/dev/null\
	||my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	# if [[ "$cluster_ip" != "$1" ]];then
		# add_log "ERROR" "Specifies that the cluster is not a backup cluster"
		# my_exit 2 "$fail_msg" "Specifies that the cluster is not a backup cluster"
	# fi
	
	if ! sudo timeout 5 ceph -s -m "$1":6789 &>/dev/null;then
		add_log "ERROR" "There is no cluster on the ip"
		my_exit 3 "$fail_msg" "There is no cluster on the ip"
	fi
}

function check_pool_exist_remote()
{
	local ecpool=$(sudo rbd info $1/$2 | grep "data_pool:"|cut -d':' -f2|tr -d ' ')
	if [ -n "$ecpool" ];then
		if ! sudo ceph osd pool ls --cluster remote | grep -w "$ecpool" &>/dev/null;then
			sudo ceph osd erasure-code-profile set ec51 k=3 m=1 plugin=isa \
			technique=reed_sol_van ruleset-failure-domain=osd --cluster remote &>/dev/null
			if ! sudo ceph osd pool create $ecpool 512 erasure ec51 --cluster remote &>/dev/null;then
				add_log "ERROR" "remote:Create erasure pool $ecpool failed"
				my_exit 4 "$fail_msg" "Create erasure pool $ecpool failed"
			fi
			
			sudo ceph osd pool set $ecpool min_size 3 --cluster remote &>/dev/null	
 			sudo ceph osd pool set $ecpool allow_ec_overwrites true --cluster remote &>/dev/null
		fi
	fi
	
	if ! sudo ceph osd pool ls --cluster remote | grep -w $1 &>/dev/null;then
		sudo ceph osd pool create $1 128 128 --cluster remote &>/dev/null
		if [ $? -ne 0 ];then
			add_log "ERROR" "remote:Create remote pool $1 Failed"
			my_exit 4 "$fail_msg" "Create remote pool $1 Failed"
		else
			add_log "INFO" "remote:Create remote pool $1 Successfully!!"
		fi
	else
		if sudo rbd info $1/$2 --cluster remote &>/dev/null;then
			add_log "ERROR" "remote images already exist"
			my_exit 5 "$fail_msg" "Remote images already exist"
		fi
	fi	
}

function check_pool_image_exist_local()
{
	if ! sudo ceph osd pool stats $1 &>/dev/null;then
		add_log "ERROR" "Local Pools $1 is not exist"
		my_exit 1 "$fail_msg" "Local pools $1 is not exist"
	fi
	
	if ! sudo rbd info $1/$2 --cluster local &>/dev/null;then
			add_log "ERROR" "Local images $2 is not exist"
			my_exit 1 "$fail_msg" "Local $1/$2 is not exist"
	fi
}

function create_backup()
{
	#1.Enable Local pool mode:image
	sudo rbd mirror pool enable $1 image --cluster local &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "local:Enable local pool $1 successfully mode:image!!"
	else
		add_log "ERROR" "local:Enable local pool $1 failed mode:image!!"
		my_exit 6 "Create remote backup Failed" "Enable local pool $1 failed mode:image"
	fi
	
	#2.Enable Remote pool mode:image
	sudo rbd mirror pool enable $1 image --cluster remote &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "remote:Enable remote pool $1 successfully mode:image!!"
	else
		add_log "ERROR" "remote:Enable remote pool $1 failed mode:image!!"
		my_exit 6 "Create remote backup Failed" "Enable remote pool $1 failed mode:image"
	fi
	
	#3.Add Local pool to peer
	sudo rbd mirror pool peer add $1 client.admin@local --cluster remote &>/dev/null
	if [ $? -eq 0 -o $? -eq 17 ];then
		add_log "INFO" "remote:Add to remote pool peer successfully"
	else
		add_log "ERROR" "remote:Add to remote pool peer failed"
		my_exit 6 "Create remote backup Failed" "Add to remote pool peer failed"
	fi
	
	#4.Add Remote pool to peer
	sudo rbd mirror pool peer add $1 client.admin@remote --cluster local &>/dev/null
	if [ $? -eq 0 -o $? -eq 17 ];then
		add_log "INFO" "local:Add to local pool peer successfully"
	else
		add_log "ERROR" "local:Add to local pool peer failed"
		my_exit 6 "Create remote backup Failed" "Add to local pool peer failed"
	fi
	
	# #5.Enable features exclusive-lock of Local image 
	# if ! sudo rbd info -p $1 $2 --cluster local | grep  features | grep -w exclusive-lock &>/dev/null;then
		# sudo rbd feature enable $1/$2 exclusive-lock --cluster local
	# fi
	
	#6.Enable features journaling of Local image
	if ! sudo rbd info -p $1 $2 --cluster local | grep  features | grep -w journaling &>/dev/null;then
		sudo rbd feature enable $1/$2 journaling --cluster local
	fi
	
	#7.Enable iamge Mirror mode
	sudo rbd mirror image enable $1/$2 --cluster local &>/dev/null
	if [ $? -eq 0 ];then
		add_log "INFO" "local:Enable local $1/$2 mirror successfully"
	else
		add_log "ERROR" "local:Enable local image $1/$2 mirror failed"
		my_exit 6 "Create remote backup Failed" "Enable local image $1/$2 mirror failed"
	fi
	
	#8.Start cluster rbd-mirror process
	if ! ssh $user_name@$remote_ip 'pidof rbd-mirror &>/dev/null';then
		sudo rbd-mirror  --setuser root --setgroup root -i admin --cluster remote & &>/dev/null
		if [ $? -eq 0 ];then
		add_log "INFO" "remote:Start rbd-mirror process successfully"
		else
		add_log "ERROR" "remote:Start rbd-mirror process failed"
		my_exit 7 "Create remote backup Failed" "Start rbd-mirror process failed"
		fi
		
	fi
	
	add_log "INFO" "remote:Create backup successfully"
	my_exit 0 "$success_msg"
}

err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ip}" ];then
    check_remote_cluster_ip "$remote_ip"
	#set -x
	check_pool_image_exist_local "$pool_name" "$image_name"
	check_pool_exist_remote "${pool_name}" "$image_name"
	#set +x
	create_backup "${pool_name}" "${image_name}"
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}"
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi