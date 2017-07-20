#!/bin/bash


filedir=/etc/ceph/

lfilename=local.conf
rfilename=remote.conf


function test_local_or_remote () {

uuidlocal=`sudo ceph -s | grep cluster | awk '{print $2}'`	
if [ $? -ne 0 ]
then 
	exit 1
fi
uuidremote=`sudo ceph -s --cluster remote | grep cluster | awk '{print $2}'`
if [ $? -ne 0 ]
then 
	exit 1
fi

if [ ${uuidlocal} == ${uuidremote} ]
then 
	echo "3"
else
	echo "2"
fi
}



if [  -f  ${filedir}${lfilename} ] && [ -f  ${filedir}${rfilename} ]
then 
	test_local_or_remote
else 
	echo "1"
fi




