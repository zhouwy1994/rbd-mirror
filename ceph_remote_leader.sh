#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

add_log
add_log "INFO" "local: Get remote and local leader ip"
add_log "INFO" "$0 $*"

tmp_val_local=""
tmp_val_remote=""

for index_ip in $all_quorum_ip_local
do
	tmp_val_local+="'\"$index_ip\"',"
done

for index_ip in $all_quorum_ip_remote
do
	tmp_val_remote+="'\"$index_ip\"',"
done

echo $tmp_val_local

echo "var test = {
    leader: {
        local: {
            hostname: '"${local_leader_hostname}"',
            ip: '"${local_leader_ipaddr}"'
        },
        remote: {
            hostname: '"${remote_leader_hostname}"',
            ip: '"${remote_leader_ipaddr}"'
        }
    },
    local: [${tmp_val_local%,}],
    remote: [${tmp_val_remote%,}]
}"	
