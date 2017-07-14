#!/bin/bash
set -e
set -x
pool_total=$(sudo rados lspools)

for pool_index in $pool_total
do
	image_total=$(sudo rbd ls  $pool_index)
	for image_index in $image_total
	do
		sudo rbd rm $pool_index/$image_index
	done
done

	
