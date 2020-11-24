#! /usr/bin bash

FILE_SIZES_PATTERN=$1

echo "${FILE_SIZES_PATTERN}"

NFS_SERVER_DIR=/var/nfsroot/

cd ${NFS_SERVER_DIR}

while true
do
	ls -lh | grep -E ${FILE_SIZES_PATTERN} | rev | cut -d " " -f 1 | rev | xargs rm &> /dev/null
	sleep 2
done
