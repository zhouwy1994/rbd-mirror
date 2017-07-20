#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

add_log
add_log "INFO" "local: Get remote and local leader ip"
add_log "INFO" "$0 $*"

all_quorum_ip_local=$(sudo ceph -s --cluster local| egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b" 2>&1)
all_quorum_ip_remote=$(sudo ceph -s --cluster remote| egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b" 2>&1)

local_leader_hostname=$(sudo ceph quorum_status --cluster local | sed s/.*quorum_leader_name\":\"//g|sed s/\".*$//g 2>&1)
remote_leader_hostname=$(sudo ceph quorum_status --cluster remote | sed s/.*quorum_leader_name\":\"//g|sed s/\".*$//g 2>&1)

local_leader_uuid=$(sudo ceph -s --cluster local|grep cluster|egrep -o "[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}" 2>&1)
remote_leader_uuid=$(sudo ceph -s --cluster remote|grep cluster|egrep -o "[[:alnum:]]{8}-([[:alnum:]]{4}-){3}[[:alnum:]]{12}" 2>&1)

local_leader_ipaddr=$(sudo ceph quorum_status  --cluster local | sed s/^.*\"$local_leader_hostname\",\"addr\":\"//g|sed s/:.*$//g 2>&1)
remote_leader_ipaddr=$(sudo ceph quorum_status  --cluster remote | sed s/^.*\"$remote_leader_hostname\",\"addr\":\"//g|sed s/:.*$//g 2>&1)


tmp_val_local=""
tmp_val_remote=""

for index_ip in $all_quorum_ip_local
do
	tmp_val_local+="\"$index_ip\","
done

for index_ip in $all_quorum_ip_remote
do
	tmp_val_remote+="\"$index_ip\","
done

#echo $tmp_val_local

echo "{\"leader\":{\"local\":{\"hostname\":"\"${local_leader_uuid}\"",\"ip\": "\"${local_leader_ipaddr}\""},\"remote\":{\"hostname\":"\"${remote_leader_uuid}\"",\"ip\":"\"${remote_leader_ipaddr}\""}},\"local\":[${tmp_val_local%,}],\"remote\":[${tmp_val_remote%,}]}"	
