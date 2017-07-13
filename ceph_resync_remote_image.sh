#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

set -e
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
fail_msg="resync rbd mirror  failed"
success_msg="resync rbd mirror successfully"
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
#local remote_user=denali
local rbd_mirror_statu=`rbd info $pool_name/$image_name |grep 'mirroring state' |sed 's/.*state: //g'`
if [ $? -eq 0 ] ;then
                  add_log "INFO" "local: get rbd mirror image#$image_name status successfully"
else
                  add_log "ERROR" "local: get rbd mirror image#$image_name status false"
                  my_exit 2 "local: get rbd mirror image#$image_name status false"
fi


if [ $rbd_mirror_statu == "enabled" ]
then
	#sshpass -p "$remote_key" ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image resync $pool_name/$image_name"
	# resync remote image
	ssh -o StrictHostKeyChecking=no $remote_user@$remote_ipaddr "sudo rbd mirror image resync $pool_name/$image_name"
	if [ $? -eq 0 ] ; then
		add_log "INFO" "remote: rbd_mirror resync is successfully"
 		exit 0
	else
 		echo "rbd_mirror resync is false "
		add_log "ERROR" "remote: rbd mirror resync image#$image_name false"
 		my_exit 3 "remote: rbd mirror resync image#$image_name false"
	fi
else
	add_log "ERROR" "local: rbd image#$image_name is disable"
        my_exit 4 "local: rbd image#$image_name is disable"
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
