function check_mirror_stats()
{
	local mirror_state=""
	local entries_behind_master=""
	
	mirror_state=$( rbd mirror image status pool1/images | grep  "state:" | awk '{print $2}')
	entries_behind_master=$(rbd mirror image status pool1/images | grep -E -o "entries_behind_master=[[:digit:]]+" | /
	grep -E -o "[[:digit:]]+")
	
	if [[ "$mirror_state" = "up+replaying" -a $entries_behind_master -eq 0 ]]
		echo "replay complete"
		exit 0
	else
		echo "replaying"
		exit 1
	fi
	
	if [[ "$mirror_state" = "up+error" ]]
		echo "up+error"
		exit 2
	fi
	
	if [[ "$mirror_state" = "up+syncing" ]]
		echo "up+syncing"
		exit 2
	fi
}