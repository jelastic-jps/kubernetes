#!/bin/bash

if [ ! -f "/var/lib/worker/gitlab-integration.conf" ]; then

	echo "$(date): Gitlab integration configuration is missing"
	exit 2
fi

source /var/lib/worker/gitlab-integration.conf

rm -rf "/etc/docker/certs.d/${GITLAB_REGISTRY}" &>/dev/null

echo "$(date): Gitlab integration configuration removed"

exit 0
