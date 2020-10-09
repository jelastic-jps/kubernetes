#!/bin/bash

if [ ! -f "/var/lib/worker/gitlab-cacert.crt" ]; then

	echo -e "Gitlab integration certificate doesn't exist"
	exit 1
fi
if [ ! -f "/var/lib/worker/gitlab-integration.conf" ]; then

	echo -e "Gitlab integration configuration is missing"
	exit 2
fi

source /var/lib/worker/gitlab-integration.conf

mkdir -p "/etc/docker/certs.d/${GITLAB_REGISTRY}" &>/dev/null

/usr/bin/cp -f /var/lib/worker/gitlab-cacert.crt "/etc/docker/certs.d/${GITLAB_REGISTRY}/ca.crt"

echo -e "Gitlab integration configuration complete"

exit 0
