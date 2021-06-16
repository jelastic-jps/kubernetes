#!/bin/bash

if [ ! -f "/var/lib/kubelet/kubeadm-flags.env" ]; then

	echo -e "Kubernetes worker configuration is invalid"
	exit 1
fi

if [ ! -f "/var/lib/worker/gitlab-integration.conf" ]; then

	echo "$(date): Gitlab integration configuration is missing"
	exit 2
fi

source /var/lib/worker/gitlab-integration.conf

if grep -q 'containerd' /var/lib/kubelet/kubeadm-flags.env; then

	rm -rf /etc/pki/ca-trust/source/anchors/gitlab-registry.crt &>/dev/null
	/bin/update-ca-trust
	service containerd restart

else
	rm -rf "/etc/docker/certs.d/${GITLAB_REGISTRY}" &>/dev/null
fi

echo "$(date): Gitlab integration configuration removed"

exit 0
