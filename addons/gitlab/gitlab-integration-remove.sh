#!/bin/bash

if [ ! -f "/var/lib/worker/gitlab-integration.conf" ]; then

	echo -e "Integration configuration is missing"
	exit 2
fi

source /var/lib/worker/gitlab-integration.conf

rm -rf "/etc/docker/certs.d/${GITLAB_REGISTRY}" &>/dev/null

exit 0
