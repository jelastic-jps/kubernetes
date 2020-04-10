#!/bin/bash
# set -x

if [ ! -d "/var/lib/worker" ]; then

	echo -e "Worker integration directory doesn't exist"
	exit 1
fi

echo "$(date): worker integration started";

# all scripts should be idempotent

{ ls -1qA /var/lib/worker 2>/dev/null | grep -q . ;} && \
	find /var/lib/worker -type f -executable -exec echo "$(date): execute {}" \; -exec {} \;

echo "$(date): worker integration finished";

exit 0
