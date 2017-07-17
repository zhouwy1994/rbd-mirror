#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

#set -e
#set -x

add_log
add_log "INFO" "`hostname`: delete rbd  mirror image..."
add_log "INFO" "$0 $*"

function usage()
{
        echo "Usage:$0 -p|--pool-name <pool name> -n|--image-name <image name>  | [-h|--help]"
        echo "-p, --pool-name <pool name>"
        echo -e "\t\tpool name."

        echo "-n, --image-name <image name>"
        echo -e "\t\timage name."

        echo "[-h, --help]"
        echo -e "\t\thelp info"
}

TEMP=`getopt -o p:n:h --long pool-name:,image-name:,help -n 'note' -- "$@"`
if [ $? != 0 ]; then
    echo "parse arguments failed."
    exit 1
fi

eval set -- "${TEMP}"
pool_name=""
image_name=""
res="" 
fail_msg="delete rbd  mirror image failed"
success_msg="delete rbd  mirror image successfully"
while true 
do
    case "$1" in
        -p|--pool-name) pool_name=$2; shift 2;;
        -n|--image-name) image_name=$2; shift 2;;
        -h|--help) usage; exit 1;;
        --) shift; break;;
        *) echo "Internal error!"; exit 1;;
    esac
done
function main() {
# get rbd mirror status
local rbd_mirror_image_status=` sudo rbd info $pool_name/$image_name |grep 'mirroring state' |sed 's/.*state: //g'`
if [ $? -eq 0 ] ;then
	add_log "INFO" "get rbd mirror image#$image_name status successfully"
else
 	add_log "ERROR" "local: get rbd mirror $image_name status false"
	my_exit 2 "local: get rbd mirror $image_name status false"
fi

if [ $rbd_mirror_image_status == "enabled" ]
then
# disable rbd mirror image in local cluster
sudo rbd mirror image disable $pool_name/$image_name
if [ $? -eq 0 ] ; then
	add_log "INFO" "delete rbd mirror image#$image_name successfully"
	exit 0
else
	echo "rbd_image is delete false"
	add_log "ERROR" "local: rbd_image#$image_name is delete false"
	my_exit 3 "local: rbd_image#$image_name is delete false"
fi
else
	add_log "INFO" "image#$image_name status is disable"
	exit 0
fi


}
err_parameter="error parameter, --pool-name, --image-name "
if [ -n "$pool_name" ] && [ -n "$image_name" ];then
  set -x
  main "${pool_name}" "${image_name}" 
  #check_pool_exist "${pool_name}"
  set +x
else
    add_log "ERROR" "${fail_msg}, ${err_parameter}" $print_log
    my_exit 1 "${fail_msg}" "${err_parameter}"
fi
