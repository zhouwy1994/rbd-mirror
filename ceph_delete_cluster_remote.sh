#!/bin/bash

set -e

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

add_log
add_log "INFO" "$(hostname)(local): Delete remote cluster...."
add_log "INFO" "$0 $*"

remote_ipaddr=""
user_name="$remote_user"

fail_msg="Delete remote cluster failed"
success_msg="Delete remote cluster successfully."

TEMP=`getopt -o i:h --long remote-ipaddr:,user-name:,help -n 'note' -- "$@"`
if [ $? != 0 ]; then
    echo "parse arguments failed."
    exit 1
fi

eval set -- "${TEMP}"

function usage()
{
	echo "Usage:$0 -i|--remote-ipaddr <remote ipaddress> [-h|--help]"

	echo "-i, --remote-ipaddr<cluster ipaddress>"
	echo -e "\t\t remote cluster ipaddr."
	
	echo "[-h, --help]"
	echo -e "\t\t get this help info."
}

while true
do
    case "$1" in
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
	
	if ! res=$(echo "$1" | egrep "([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}" 2>&1);then
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi

	if ! res=$(sudo timeout 5 ceph -s -m "$1":6789);then
		my_exit 3 "$fail_msg" "There is no cluster on the ip"
	fi
}

function kill_rbd_mirror_remote()
{
	local res=$(ssh "$user_name"@"$1" 'pidof rbd-mirror | xargs sudo kill -9' 2>&1)
	local res=$(ssh "$user_name"@"$1" 'pidof rbd-mirror')
	
	if [ -z "$res" ];then
		add_log "INFO" "$(get_hostname $remote_ipaddr)(remote):rbd-mirror has been stop"
	else
		my_exit 4 "$fail_msg" "remote rbd-mirror stop failed"
	fi
}

function remove_pool_peer()
{
	local pool_total=$(sudo ceph osd pool ls --cluster local 2>/dev/null)
	
	for pool_index in $pool_total
		do
			local peer_uuid=$(sudo rbd mirror pool info -p "$pool_index" --cluster local  2>&1 | grep \
			-E -o "[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}" 2>/dev/null)
			if [ -n "$peer_uuid" ];then
				for peer_index in $peer_uuid
				do
					local res=$(sudo rbd mirror pool peer remove "$pool_index" "$peer_index" --cluster local 2>&1)
				done
			fi
			
			local peer_uuid=$(sudo rbd mirror pool info -p "$pool_index" --cluster remote 2>/dev/null| grep \
			-E -o "[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}")
			if [ -n "$peer_uuid" ];then
				for peer_index in $peer_uuid
				do
					local res=$(sudo rbd mirror pool peer remove "$pool_index" "$peer_index" --cluster remote 2>&1)
				done
			fi
		done
}

function destroy_config_file()
{
	local res=$(ssh -o StrictHostKeyChecking=no "$user_name"@"$remote_ipaddr" "cd "$config_file_dir_remote" && sudo rm $config_file_remote $keyring_file_remote $config_file_local $keyring_file_local 2>&1")

	local res=$(cd "$config_file_dir_remote" && sudo rm $config_file_remote $keyring_file_remote $config_file_local $keyring_file_local 2>&1)
	
	if ! res=$(sudo ceph -s --cluster remote 2>&1);then
		add_log "INFO" "$(hostname)(local):Delete remote config file successfully"
	else
		add_log "ERROR" "local:Delete remote config file failed"
		my_exit 5 "$fail_msg" "Delete remote config file failed"
	fi

	if ! res=$(ssh "$user_name"@"$remote_ipaddr" 'sudo ceph -s --cluster local 2>&1');then
		add_log "INFO" "remote:delete local config file successfully"
	else
		add_log "ERROR" "remote:Delete local config file failed" 
		my_exit 5 "$fail_msg" "Delete local config file failed"
	fi
	
	add_log "INFO" "local:Delete remote successfully"
	my_exit 0 "$success_msg" "The remote cluster has been removed"

}

err_parameter="error parameter, --remote-ipaddr, --help"
#set -x
if [ -n "$remote_ipaddr" ];then
	check_remote_cluster_ip "$remote_ipaddr"
	#remove_pool_peer
	kill_rbd_mirror_remote "$remote_ipaddr"
	destroy_config_file
else
	add_log "ERROR" "${fail_msg}, ${err_parameter}"
	my_exit 1 "$fail_msg" "$err_parameter"
fi
#set +x
