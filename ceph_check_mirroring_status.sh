#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

#set -e
#set -x

add_log
add_log "INFO" "`hostname`: check mirror status ..."
add_log "INFO" "$0 $*"

function usage()
{
        echo "Usage:$0 -p|--pool-name <pool name> -n|--image-name <image name> -i|--remote-ipaddr | [-h|--help]"
        echo "-p, --pool-name <pool name>"
        echo -e "\t\tpool name."

        echo "-n, --image-name <image name>"
        echo -e "\t\timage name."

        echo "-i, --remote-ipaddr <remote ipaddr>"
        echo -e "\t\tremote ipaddress."

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
res="" 
fail_msg="check mirror state failed"
success_msg="check mirror state successfully"
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
function main() {

#local remote_key="admin"
#local remote_user="denali"
local local_image_status=`rbd info $pool_name/$image_name |grep 'mirroring state' |sed 's/.*state: //g'`

if [ $? -eq 0 ] ;then
	add_log "INFO" "local: get rbd mirror image#$image_name status successfully"
else
 	add_log "ERROR" "local: get rbd mirror image#$image_name status false"
        my_exit 2 "local: get rbd mirror image#$image_name status false"
fi

if [ "$local_image_status" == "enabled" ]
then
#local rbd_mirror_state=`sudo sshpass -p "$remote_key" ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image status $pool_name/$image_name |grep  "state:" |cut -d':' -f 2 | tr -d ' ' | sed 's/\+.*$//g'"`
local rbd_mirror_state=`sudo rbd mirror image status rbd/image111 --cluster remote|grep "state:" |cut -d':' -f 2 | tr -d ' ' | sed 's/\+.*$//g'`
if [ $? -eq 0 ] ;then
	add_log "INFO" "local: get rbd mirror status successfully"
else
 	add_log "ERROR" "local: get rbd mirror  status false"
fi
#local remote_image_state=`sudo sshpass -p "$remote_key" ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image status $pool_name/$image_name |grep  "state:" |cut -d':' -f 2 | tr -d ' ' |sed 's/^.*+//g'"`
local remote_image_state=`sudo rbd mirror image status rbd/image111 --cluster remote |grep  "state:" |cut -d':' -f 2 | tr -d ' ' |sed 's/^.*+//g'`
if [ $? -eq 0 ] 
then
	add_log "INFO" "get mirror image state successfully"
else
	add_log "ERROR" "get mirror image state false"
	my_exit 3 "local: get mirror image  status false"
fi
#entries_behind_master=`sudo sshpass -p "$remote_key" ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image status $pool_name/$image_name |grep -E -o "entries_behind_master=[[:digit:]]+" |grep -E -o "[[:digit:]]+""`
entries_behind_master=`sudo rbd mirror image status rbd/image111 --cluster remote |grep -E -o "entries_behind_master=[[:digit:]]+" |grep -E -o "[[:digit:]]+"`
if [ $? -eq 0 ] ;then
	add_log "INFO" "get entries_behind_master successfully"
else
 	add_log "ERROR" "get entries_behind_master false"
	my_exit 4 "local: get entries_behind_master false"	
fi
  echo "==================rbd_mirror_state:$rbd_mirror_state"
  echo "==================remote_image_state:$remote_image_state"
  echo "=================$entries_behind_master"
  if [ "$rbd_mirror_state" = "down" ]
  then
	 echo "rbd-mirror process is down"
  fi
  if [[ "$remote_image_state" = "replaying" && $entries_behind_master -eq 0 ]]
  then
    echo "replay complete"
    exit 5
  elif [[ "$remote_image_state" = "replaying" && $entries_behind_master -ne 0 ]]
  then
    echo "replaying"
    exit 6
  else
    echo "error"
    exit 7
  fi
else 
	add_log "ERROR" "the $image_name is disable"
	exit 7

fi
}
err_parameter="error parameter, --pool-name, --image-name or --remote-ipaddr"
if [ -n "$pool_name" ] && [ -n "$image_name" ] && [ -n "${remote_ipaddr}" ];then
   set -x
  run "${pool_name}" "${image_name}" "${remote_ipaddr}" 
  #check_pool_exist "${pool_name}"
 set +x
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}" $print_log
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
