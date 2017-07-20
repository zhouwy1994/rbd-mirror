#!/bin/bash
SHELL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $SHELL_DIR/common_rbd_mirror_fun

size=""
image_info=""
image_size=""

add_log
add_log "INFO" "`hostname`: select pool and image info ..."
add_log "INFO" "$0 $*"

fail_msg="select pool and image info failed"
success_msg="select pool and image info successfully"

function get_image_info() {
sudo ceph osd pool get $var erasure_code_profile &>/dev/null
if [ $? -eq 0 ] ;then
	ec_image_name=`sudo rbd -p rbd ls`
	echo "	images["
	for var1 in $ec_image_name
	{
		local ec_pool=`sudo rbd info rbd/$var1 |egrep -A 4 'rbd image'|grep -v 'rbd image'|grep 'data_pool'|sed 's/.*data_pool: //g'`
		if [ $? -eq 0 ] ;then
		add_log "INFO" "get ec_pool_name Successfully"
		else
		add_log "ERROR" "get ec_pool_name False"
		my_exit 1 "${fail_msg}" "get ec_pool_name False"
		fi
		if [[ "$ec_pool" = $var ]] ;then
		local name=$var1
		var2=rbd/$var1	
		get_image_size $var2
		echo "		{
				name:$name
				size:$image_size
				}"
	fi
	}
	echo "	  ]"	
else
	rbd_image_name=`sudo rbd -p $var  ls`
	echo "	images["
	for var1 in $rbd_image_name
	{
		local name=$var1
		var2=$var/$var1
		get_image_size $var2
		echo "		{
			name:$name
			size:$image_size
			}"

	}
	echo "	  ]"
fi
}

function get_image_size() {

image_size=`sudo rbd info $var2 |egrep -A 1 'rbd image'|grep -v 'rbd image'|sed 's/.*size //g'|sed 's/in.*$//g'`
if [ $? -eq 0 ] ;then
		add_log "INFO" "get image_Size info successfully"
else
		add_log "ERROR" "get image_Size info failed"
		my_exit 2 "${fail_msg}" "get image_Size info failed"
fi
echo "$image_size" &>/dev/null
expr $imahe_size + 0 &>/dev/null
if [ $? -eq 0 ] ;then
	echo "data is num" &>/dev/null
else
	final=`echo ${image_size:$((-3))}`
	echo "========$final" &>/dev/null
if [[ $final == 'kB' ]]  ; then
	image_size=`echo $image_size|sed 's/ kB//'`;
	image_size=$(($image_size * 1024))
fi
if [[ $final == 'MB' ]] ;then
	image_size=`echo $image_size|sed 's/ MB//'`;
	image_size=$(($image_size * 1024 * 1024))
fi
if [[ $final == 'GB' ]] ;then
	image_size=`echo $image_size|sed 's/ GB//'`;
	image_size=$(($image_size * 1024 * 1024 * 1024))
fi

if [[ $final == 'TB' ]] ;then
	image_size=`echo $image_size|sed 's/ TB//'`;
	image_size=$(($image_size * 1024 * 1024 * 1024))
fi
	echo "$image_size" &>/dev/null
fi

}
function get_usedSize() {
size=`sudo rados df |grep -w "$var"|awk '{ print $2 }'`
if [ $? -eq 0 ] ;then
	add_log "INFO" "get pool_used_Size info successfully"
else
	add_log "ERROR" "get pool_used_Size info failed"
	my_exit 3 "${fail_msg}" "get pool_used_Size info failed"
fi
echo "$size" &>/dev/null
expr $size + 0 &>/dev/null
if [ $? -eq 0 ] ;then
	echo "data is num" &>/dev/null
else
	final=`echo ${size:$((-1))}`
	size=`echo $size|sed 's/.$//'`;
if [[ $final == 'k' ]]  ; then 
	size=$(($size * 1024))
fi
if [[ $final == 'M' ]] ;then 
	size=$(($size * 1024 * 1024))
fi
if [[ $final == 'G' ]] ;then
	size=$(($size * 1024 * 1024 * 1024))
fi
if [[ $final == 'T' ]] ;then
	size=$(($size * 1024 * 1024 * 1024))
fi
echo "$size" &>/dev/null
fi

}

function get_pool_info() {
local pool_name=`sudo rados df |head -n $(($(sudo rados df |wc -l) - 5))| cut -d' '  -f1|grep -w -v 'rbd'|awk 'NR!=1{print}'`
if [ $? -eq 0 ] ;then
	add_log "INFO" "get pool_name successfully"
else
	add_log "ERROR" "get pool_name failed"
	my_exit 4 "${fail_msg}" "get pool_name info failed"
fi

for var in $pool_name
{
	sudo ceph osd pool get $var erasure_code_profile &>/dev/null
	if [ $? -eq 0 ] ;then
		name=$var
		pool_type="erasure"
		profile=`sudo ceph osd pool get $var erasure_code_profile |sed 's/.*: //g'`
		echo "$profile" &>/dev/null
		k_key=`sudo ceph osd erasure-code-profile get $profile |grep 'k='|sed 's/.*=//g'`
		m_key=`sudo ceph osd erasure-code-profile get $profile |grep 'm='|sed 's/.*=//g'`
		rule_key=`sudo ceph osd erasure-code-profile get $profile |grep 'ruleset-f'|sed 's/.*=//g'`
		pg_num=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f13`
		pgp_num=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f15`
		get_usedSize $var
	
		echo "{			name:$name
			type:$pool_type	
			used_size:$size"
		echo "	pool_info{
			k:$k_key
			m:$m_key
			pg_num:$pg_num
			pgp_num:$pgp_num
			reluset:$rule_key"
		get_image_info $var
		echo "	}"
		echo "}"
	
	else
		#name=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f2`
		name=$var
		pool_type="replicated"
		replica_Size=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f5`
		pg_num=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f13`
		pgp_num=`sudo ceph osd dump|grep -w 'pool'|cut -d" " -f1  --complement|grep -w $var |cut -d" " -f15`
		get_usedSize $var
		echo "{			name:$name
			type:$pool_type	
			used_size:$size"
		echo "	pool_info{
			replicaSize:$replica_Size
			pg_num:$pg_num
			pgp_num:$pgp_num"
		get_image_info $var
		echo "	}"
		echo "}"


	fi 
	
}


}
get_pool_info 
exit 0
