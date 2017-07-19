#/bin/bash

SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

# function check_remote_leader()
# {
	# readonly all_quorum_ip_local=$(sudo ceph -s --cluster local 2>/dev/null\
	# | egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b")

	# readonly all_quorum_ip_remote=$(sudo ceph -s --cluster remote  2>/dev/null\
	# | egrep -o "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b")
	
	# readonly remote_leader_hostname=$(sudo ceph quorum_status --cluster remote 2>/dev/null\
	# | sed s/.*quorum_leader_name\":\"//g|sed s/\".*$//g)
	# readonly remote_leader_ipaddr=$(sudo ceph quorum_status  --cluster remote 2>/dev/null\
	# | sed s/^.*\"$remote_leader_hostname\",\"addr\":\"//g|sed s/:.*$//g)
# }

add_log
add_log "INFO" "local: remove ssh passwd..."
add_log "INFO" "$0 $*"

all_quorum_ip_remote=""

TEMP=`getopt -o i:h --long remote-ipaddr:,help -n 'note' -- "$@"`
if [ $? != 0 ]; then
    echo "parse arguments failed."
    exit 1
fi

eval set -- "${TEMP}"

function usage()
{
        echo "Usage:-i|--remote-ipaddr | [-h|--help]"
       
        echo "-i, --remote-ipaddr <cluster ipaddr>"
        echo -e "\t\cluster ipaddress."

        echo "[-h, --help]"
        echo -e "\t\thelp info"
}

function check_remote_cluster_ip()
{
	if ! res=$(echo "$1"| egrep "\b([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}\b" 2>&1);then
		add_log "ERROR" "remote ip address is invalid"
		my_exit 1 "$fail_msg" "remote ip address is invalid"
	fi
	
	# if [[ "$1" != "$remote_leader_ipaddr" ]];then
		# add_log "ERROR" "The remote cluster is unreachable"
		# my_exit 2 "$fail_msg" "The remote cluster is unreachable"
	# fi
	
	# timeout 3 ssh $user_name@$1 "pwd" &>/dev/null\
	# ||my_exit 2 "fail_msg" "The remote cluster is unreachable"
	
	# if [[ "$cluster_ip" != "$1" ]];then
		# add_log "ERROR" "Specifies that the cluster is not a backup cluster"
		# my_exit 2 "$fail_msg" "Specifies that the cluster is not a backup cluster"
	# fi
	
	if ! res=$(sudo timeout 5 ceph -s -m "$1":6789 2>/dev/null);then
		my_exit 2 "$fail_msg" "There is no cluster on the ip"
	fi
}

while true
do
    case "$1" in
        -i|--remote-ipaddr) check_remote_cluster_ip $2;
		all_quorum_ip_remote+=" $2"; shift 2;;
        -h|--help) usage; exit 1;;
        --) shift; break;;
        *) echo "Internal error!"; exit 1;;
    esac
done

function destroy_ssh_config_file()
{
	
	keystr=$(cat ~/.ssh/id_rsa.pub 2>/dev/null)
	str=$(python -c "import urllib;print urllib.quote_plus('${keystr}')")
	if [ $? -ne 0 ];then
		add_log "ERROR" "remove ssh passwd failed"
		my_exit 1 "remove ssh passwd failed"
	fi
	
	for ip_index_remote in $all_quorum_ip_remote 
	do
		curl -d "key=6ac240155855f944f9c77e15539a5680&path=/home/denali/.ssh/authorized_keys&secret=${str}" \
		"http://$ip_index_remote:8333/api/1.1/safe-command/removeSSHPasswordKey" &>/dev/null
		if [ $? -ne 0 ];then
			add_log "ERROR" "remove ssh passwd failed"
			my_exit 1 "remove ssh passwd failed"
		fi
	done
	
	add_log "INFO" "remove ssh passwd successfuuly"
	my_exit 0 "remove ssh passwd successfuuly"
}

echo $all_quorum_ip_remote
#check_remote_leader
destroy_ssh_config_file

