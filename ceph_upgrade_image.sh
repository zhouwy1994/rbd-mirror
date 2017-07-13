#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

#set -e
#set -x

add_log
add_log "INFO" "`hostname`: upgrade remote image..."
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
user_name="$remote_usrname"
res="" 
fail_msg="upgrade remote image failed"
success_msg="upgrade remote image successfully"

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
	
	$(timeout 5 ssh -o StrictHostKeyChecking=no "$user_name"@"$1" 'exit' &>/dev/null) || my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	if ! local res=$(echo "$1"	| egrep "([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}" 2>&1);then
		add_log 
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	if ! res=$(sudo timeout 5 ceph -s -m "$1":6789);then
		my_exit 3 "$fail_msg" "There is no cluster on the ip"
	fi
}

function check_pool_image_exist()
{
	local res 
	
	if ! sudo ceph osd pool stats $1 &>/dev/null;then
		add_log "ERROR" "Local Pools $1 is not exist"
		my_exit 1 "$fail_msg" "Pools $1 is not exist"
	fi
	
	if ! res=$(sudo rbd info $1/$2 --cluster remote 2>&1);then
			add_log "ERROR" "Local images $2 is not exist"
			my_exit 1 "$fail_msg" "Local images $2 is not exis"
	fi
}

function upgrade_remote_image()
{
	local mirror_pri_stats_local=""
	local mirror_pri_stats_remote=""
	
	mirror_pri_stats_local=$(sudo rbd info -p $1 $2 --cluster local | grep -E "mirroring primary" | cut -d' ' -f3)
	mirror_pri_stats_remote=$(sudo rbd info -p $1 $2 --cluster remote | grep -E "mirroring primary" | cut -d' ' -f3)
	
	if [[ "$mirror_pri_stats_local" = "true" ]];then
		if [[ "$mirror_pri_stats_remote" = "false" ]];then
			sudo rbd mirror image demote $1/$2 --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:demote $1/$2 successfully";;
				30) add_log "ERROR" "local:demote $1/$2 failed";my_exit 4 "demote $1/$2 failed" "$1/$2 exists IO read and write";;
				*)add_log "ERROR" "local:demote $1/$2 failed";my_exit 1 "demote $1/$2 failed" "unknown error";;
			esac
			
			sudo rbd mirror image promote $1/$2 --force --cluster remote &>/dev/null
				case $? in
				0) add_log "INFO" "remote:promote $1/$2 successfully";;
				*)add_log "ERROR" "remote:promote $1/$2 failed";my_exit 1 "promote $1/$2 failed" "unknown error";;
			esac
			
			if ! pidof rbd-mirror &>/dev/null;then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster local &>/dev/null
			fi
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" ""
			# rbd mirror image resync $1/$2 --cluster local
			# case $? in
				# 0) add_log "INFO" "local:resync $1/$2 Resynchronizing";my_exit 0 "local:Master and slave switch success";;
				# *)add_log "ERROR" "local:resync $1/$2 failed";my_exit 1 "resync $1/$2 failed" "unknown error";;
			# esac
			
		elif [[ "$mirror_pri_stats_remote" = "true" ]];then
			sudo rbd mirror image demote $1/$2 --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "remote:demote $1/$2 successfully";;
				30) add_log "ERROR" "remote:demote $1/$2 failed";my_exit 4 "demote $1/$2 failed" "$1/$2 exists IO read and write";;
				*)add_log "ERROR" "remote:demote $1/$2 failed";my_exit 1 "demote $1/$2 failed" "unknown error";;
			esac
			
			if ! pidof rbd-mirror &>/dev/null;then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster local &>/dev/null
			fi
			
			sudo rbd mirror image resync $1/$2 --cluster local &>/dev/null
				case $? in
				0) add_log "INFO" "local:resync $1/$2 Resynchronizing";my_exit 0 "local:Master and slave switch success";;
				*)add_log "ERROR" "local:resync $1/$2 failed";my_exit 1 "resync $1/$2 failed" "unknown error";;
			esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" ""
		fi

	elif [[ "$mirror_pri_stats_local" = "false" ]];then
		if [[ "$mirror_pri_stats_remote" = "true" ]];then
			sudo rbd mirror image demote $1/$2 --cluster remote &>/dev/null
			case $? in
				0) add_log "INFO" "remote:demote $1/$2 successfully";;
				30) add_log "ERROR" "remote:demote $1/$2 failed";my_exit 4 "demote $1/$2 failed" "$1/$2 exists IO read and write";;
				*)add_log "ERROR" "remote:demote $1/$2 failed";my_exit 1 "demote $1/$2 failed" "unknown error";;
			esac
			
			sudo rbd mirror image promote $1/$2 --force --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:promote $1/$2 successfully";;
				*)add_log "ERROR" "local:promote $1/$2 failed";my_exit 1 "promote $1/$2 failed" "unknown error";;
			esac
			
			if ! ssh $user_name@$3 'pidof rbd-mirror &>/dev/null';then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster remote &>/dev/null
			fi
			
			# rbd mirror image resync $1/$2 --cluster remote
			# case $? in
				# 0) add_log "INFO" "remote:resync $1/$2 Resynchronizing";my_exit 0 "local:Master and slave switch success";;
				# *)add_log "ERROR" "remote:resync $1/$2 failed";my_exit 1 "resync $1/$2 failed" "unknown error";;
			# esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" ""
			
		elif [[ "$mirror_pri_stats_remote" = "false" ]];then
			sudo rbd mirror image promote $1/$2 --force --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:promote $1/$2 successfully";;
				*)add_log "ERROR" "local:promote $1/$2 failed";my_exit 1 "promote $1/$2 failed" "unknown error";;
			esac
			
			if ! ssh $user_name@$3 'pidof rbd-mirror &>/dev/null';then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster remote &>/dev/null
			fi
			
			sudo rbd mirror image resync $1/$2 --cluster remote &>/dev/null
			case $? in
				0) add_log "INFO" "remote:resync $1/$2 Resynchronizing";my_exit 0 "local:Master and slave switch success";;
				*)add_log "ERROR" "remote:resync $1/$2 failed";my_exit 1 "resync $1/$2 failed" "unknown error";;
			esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" ""
		fi
	fi
}

err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ipaddr}" ];then
#set -x
	check_remote_cluster_ip "$remote_ipaddr"
	check_pool_image_exist "$pool_name" "$image_name"
	upgrade_remote_image "$pool_name" "$image_name" "$remote_ipaddr"
#set +x
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}" $print_log
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
