#!/bin/bash

if [ ! -f "/var/lib/kubelet/kubeadm-flags.env" ]; then

	echo -e "Kubernetes worker configuration is invalid"
	exit 1
fi

if [ ! -f "/var/lib/worker/gitlab-cacert.crt" ]; then

	echo -e "Gitlab integration certificate doesn't exist"
	exit 2
fi

if [ ! -f "/var/lib/worker/gitlab-integration.conf" ]; then

	echo -e "Gitlab integration configuration is missing"
	exit 3
fi

source /var/lib/worker/gitlab-integration.conf

if grep -q 'containerd' /var/lib/kubelet/kubeadm-flags.env; then

	/usr/bin/cp -f /var/lib/worker/gitlab-cacert.crt /etc/pki/ca-trust/source/anchors/gitlab-registry.crt
	/bin/update-ca-trust
	service containerd restart

else
	mkdir -p "/etc/docker/certs.d/${GITLAB_REGISTRY}" &>/dev/null
	/usr/bin/cp -f /var/lib/worker/gitlab-cacert.crt "/etc/docker/certs.d/${GITLAB_REGISTRY}/ca.crt"
fi

echo -e "Gitlab integration configuration complete"

exit 0
