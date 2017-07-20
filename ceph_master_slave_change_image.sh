#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

#set -e
#set -x

add_log
add_log "INFO" "local: upgrade remote image..."
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
user_name="denali"
remote_ipaddr=""
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

function check_remote_leader()
{
	readonly remote_leader_hostname=$(sudo ceph quorum_status --cluster remote 2>/dev/null\
	| sed s/.*quorum_leader_name\":\"//g|sed s/\".*$//g)
	readonly remote_leader_ipaddr=$(sudo ceph quorum_status  --cluster remote 2>/dev/null\
	| sed s/^.*\"$remote_leader_hostname\",\"addr\":\"//g|sed s/:.*$//g)
}

function check_remote_cluster_ip()
{
	if ! res=$(echo "$1"| egrep "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b" 2>&1);then
		add_log "ERROR" "remote ip address is invalid"
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	if [[ "$1" != "$remote_leader_ipaddr" ]];then
		add_log "ERROR" "The remote cluster is unreachable"
		my_exit 2 "$fail_msg" "The remote cluster is unreachable"
	fi
	
	# timeout 3 ssh $user_name@$1 "pwd" &>/dev/null\
	# ||my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	# if [[ "$cluster_ip" != "$1" ]];then
		# add_log "ERROR" "Specifies that the cluster is not a backup cluster"
		# my_exit 2 "$fail_msg" "Specifies that the cluster is not a backup cluster"
	# fi
	
	if ! res=$(sudo timeout 3 ceph -s -m "$1":6789 2>&1);then
		my_exit 3 "$fail_msg" "There is no cluster on the ip"
	fi
}

function check_ec_pool()
{
	if sudo ceph osd pool get $1 erasure_code_profile &>/dev/null;then
		pool_type="erasure"
	fi
}

function check_pool_image_exist_local()
{
	if ! sudo ceph osd pool stats $1  --cluster local &>/dev/null;then
		add_log "ERROR" "Local Pools $1 is not exist"
		my_exit 1 "$fail_msg" "Local Pools $1 is not exist"
	fi
	
	if [ "$pool_type" == "erasure" ];then
		if ! sudo rbd info rbd/$2 --cluster local &>/dev/null;then
			add_log "ERROR" "Local images rbd/$2 is not exist"
			my_exit 1 "$fail_msg" "Local rbd/$2 is not exist"
		fi
	else
		if ! sudo rbd info $1/$2 --cluster local &>/dev/null;then
			add_log "ERROR" "Local images $2 is not exist"
			my_exit 1 "$fail_msg" "Local $1/$2 is not exist"
		fi
	fi
}

function check_pool_exist_remote()
{
	if [ "$pool_type" == "erasure" ];then
		if ! sudo ceph osd pool ls --cluster remote | grep -w "$1" &>/dev/null;then
			add_log "ERROR" "remote:Remote the pool $1 not exist"
			my_exit 4 "$fail_msg" "Remote the pool $1 not exist"
		else
			if ! sudo rbd info rbd/$2 --cluster remote &>/dev/null;then
				add_log "ERROR" "remote images rbd/$2 not exist"
				my_exit 4 "$fail_msg" "Remote images rbd/$2 not exist"
			fi
		fi
	else
		if ! sudo ceph osd pool ls --cluster remote | grep -w $1 &>/dev/null;then
			add_log "ERROR" "remote:Remote the pool $1 not exist"
			my_exit 4 "$fail_msg" "Remote the pool $1 not exist"
		else
			if ! sudo rbd info $1/$2 --cluster remote &>/dev/null;then
				add_log "ERROR" "Remote image $1/$2 not exist"
				my_exit 4 "$fail_msg" "Remote image $1/$2 not exist"
			fi
		fi
	fi	
}


function upgrade_remote_image()
{
	local tmp_pool_name
	local mirror_pri_stats_local=""
	local mirror_pri_stats_remote=""
	
	if [ "$pool_type" == "erasure" ];then
		tmp_pool_name="rbd"
	else
		tmp_pool_name=$1
	fi
	
	mirror_pri_stats_local=$(sudo rbd info -p $tmp_pool_name $2 --cluster local \
	| grep -E "mirroring primary" | cut -d' ' -f3 2>&1)
	mirror_pri_stats_remote=$(sudo rbd info -p $tmp_pool_name $2 --cluster remote \
	| grep -E "mirroring primary" | cut -d' ' -f3 2>&1)
	
	if [ -z "mirror_pri_stats_local" ];then
		add_log "ERROR" "Local:Local image is not enable mirror"
		my_exit 1 "$fail_msg" "Local image is not enable mirror"
	elif [ -z "mirror_pri_stats_remote" ];then
		add_log "ERROR" "Remote:Remote image is not enable mirror"
		my_exit 1 "$fail_msg" "Remote image is not enable mirror"
	fi
	
	if [[ "$mirror_pri_stats_local" = "true" ]];then
		if [[ "$mirror_pri_stats_remote" = "false" ]];then
			sudo rbd mirror image demote $tmp_pool_name/$2 --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:demote $tmp_pool_name/$2 successfully";;
				30) add_log "ERROR" "local:demote $tmp_pool_name/$2 failed";my_exit 5 "demote \
				$tmp_pool_name/$2 failed" "$tmp_pool_name/$2 exists IO read and write";;
				*)add_log "ERROR" "local:demote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "demote local \
				$tmp_pool_name/$2 failed";;
			esac
			
			sudo rbd mirror image promote $tmp_pool_name/$2 --force --cluster remote &>/dev/null
				case $? in
				0) add_log "INFO" "remote:promote $tmp_pool_name/$2 successfully";;
				*)add_log "ERROR" "remote:promote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "promote remote \
				$tmp_pool_name/$2 failed";;
			esac
			
			if ! pidof rbd-mirror &>/dev/null;then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster local &>/dev/null
			fi
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" "primary:remote non-primary:local"
			# rbd mirror image resync $tmp_pool_name/$2 --cluster local
			# case $? in
				# 0) add_log "INFO" "local:resync $tmp_pool_name/$2 Resynchronizing";\
				# my_exit 0 "local:Master and slave switch success";;
				# *)add_log "ERROR" "local:resync $tmp_pool_name/$2 failed";my_exit 1 \
				# "resync $tmp_pool_name/$2 failed" "unknown error";;
			# esac
			
		elif [[ "$mirror_pri_stats_remote" = "true" ]];then
			sudo rbd mirror image demote $tmp_pool_name/$2 --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "remote:demote $tmp_pool_name/$2 successfully";;
				30) add_log "ERROR" "remote:demote $tmp_pool_name/$2 failed";my_exit 5 \
				"demote $tmp_pool_name/$2 failed" "$tmp_pool_name/$2 exists IO read and write";;
				*)add_log "ERROR" "remote:demote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "demote local $tmp_pool_name/\
				$2 failed";;
			esac
			
			if ! pidof rbd-mirror &>/dev/null;then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster local &>/dev/null
			fi
			
			sudo rbd mirror image resync $tmp_pool_name/$2 --cluster local &>/dev/null
				case $? in
				0) add_log "INFO" "local:resync $tmp_pool_name/$2 Resynchronizing";my_exit 0 \
				"local:Master and slave switch success";;
				*)add_log "ERROR" "local:resync $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "resync local \
				$tmp_pool_name/$2 failed";;
			esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" "primary:remote non-primary:local"
		fi

	elif [[ "$mirror_pri_stats_local" = "false" ]];then
		if [[ "$mirror_pri_stats_remote" = "true" ]];then
			sudo rbd mirror image demote $tmp_pool_name/$2 --cluster remote &>/dev/null
			case $? in
				0) add_log "INFO" "remote:demote $tmp_pool_name/$2 successfully";;
				30) add_log "ERROR" "remote:demote $tmp_pool_name/$2 failed";my_exit 5 "demote \
				$tmp_pool_name/$2 failed" "$tmp_pool_name/$2 exists IO read and write";;
				*)add_log "ERROR" "remote:demote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "demote remote \
				$tmp_pool_name/$2 failed";;
			esac
			
			sudo rbd mirror image promote $tmp_pool_name/$2 --force --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:promote $tmp_pool_name/$2 successfully";;
				*)add_log "ERROR" "local:promote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "promote local \
				$tmp_pool_name/$2 failed";;
			esac
			
			if ! ssh $user_name@$3 'pidof rbd-mirror &>/dev/null';then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster remote &>/dev/null
			fi
			
			# rbd mirror image resync $tmp_pool_name/$2 --cluster remote
			# case $? in
				# 0) add_log "INFO" "remote:resync $tmp_pool_name/$2 Resynchronizing";my_exit 0 "local\
				#:Master and slave switch success";;
				# *)add_log "ERROR" "remote:resync $tmp_pool_name/$2 failed";my_exit 1 "resync \
				#$tmp_pool_name/$2 failed" "unknown error";;
			# esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" "primary:local non-primary:remote"
			
		elif [[ "$mirror_pri_stats_remote" = "false" ]];then
			sudo rbd mirror image promote $tmp_pool_name/$2 --force --cluster local &>/dev/null
			case $? in
				0) add_log "INFO" "local:promote $tmp_pool_name/$2 successfully";;
				*)add_log "ERROR" "local:promote $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" "promote local \
				$tmp_pool_name/$2 failed";;
			esac
			
			if ! ssh $user_name@$3 'pidof rbd-mirror &>/dev/null';then
				sudo rbd-mirror --setuser root --setgroup root -i admin --cluster remote &>/dev/null
			fi
			
			sudo rbd mirror image resync $tmp_pool_name/$2 --cluster remote &>/dev/null
			case $? in
				0) add_log "INFO" "remote:resync $tmp_pool_name/$2 Resynchronizing";\
				my_exit 0 "local:Master and slave switch success";;
				*)add_log "ERROR" "remote:resync $tmp_pool_name/$2 failed";my_exit 1 "$fail_msg" \
				"resync remote $tmp_pool_name/$2 failed";;
			esac
			
			add_log "INFO" "$success_msg"
			my_exit 0 "$success_msg" "primary:local non-primary:remote"
		fi
	fi
}

err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ipaddr}" ];then
	  check_remote_leader
	  check_remote_cluster_ip "$remote_ipaddr"
	  check_ec_pool "$pool_name"
	  check_pool_image_exist_local "$pool_name" "$image_name"
	  check_pool_exist_remote "$pool_name" "$image_name"
	  upgrade_remote_image "$pool_name" "$image_name" "$remote_ipaddr"
else
    add_log "ERROR" "${fail_msg}" "${err_parameter}"
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
