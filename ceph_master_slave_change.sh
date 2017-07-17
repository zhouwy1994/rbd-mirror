#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

set -e

add_log
add_log "INFO" "remote: Start Master Savle Change..."
add_log "INFO" "$0 $*"

fail_msg="master salve change failed"
success_msg="master salve change successfully"

# function destroy_config_file()
# {
	# local res=$(cd "$config_file_dir_remote" && sudo rm $config_file_remote \
	# $keyring_file_remote $config_file_local $keyring_file_local 2>&1)
	
	# add_log "INFO" "remote:Delete config file successfully"
# }

# function check_rbd_mirror()
# {
	# if ! pidof rbd-mirror &>/dev/null;then
		# sudo rbd-mirror --setuser root --setgroup root -i admin
	# fi
# }

function upgrade_image()
{
	local pool_total=$(sudo ceph osd pool ls 2>/dev/null)
	for pool_index in $pool_total
	do
		image_total=$(sudo rbd ls -p $pool_index 2>/dev/null)
		for image_index in $image_total
		do
			local primary_status=$(sudo rbd info $pool_index/$image_index | grep -E "mirroring primary: "|cut -d' ' -f3 2>/dev/null)
				if [[ "$primary_status" = "false" ]];then
					if ! sudo rbd mirror image promote $pool_index/$image_index --force --cluster remote &>/dev/null
						add_log "ERROR" "promote $1/$2 Failed"
						my_exit 1 "$fail_msg" "promote $1/$2 Failed"
				fi
				
				# sudo rbd mirror image disable $pool_index/$image_index &>/dev/null
		done
		
		# rbd mirror pool disable $pool_index image &>/dev/null
	done
}

function kill_rbd_mirror_remote()
{
	pidof rbd-mirror | xargs sudo kill -9 &>/dev/null
	local res=$(pidof rbd-mirror)
	
	if [ -z "$res" ];then
		add_log "INFO" "rbd-mirror has been stop"
	else
		my_exit 2 "$fail_msg" "remote rbd-mirror stop failed"
	fi
}

upgrade_image
kill_rbd_mirror_remote
# destroy_config_file



