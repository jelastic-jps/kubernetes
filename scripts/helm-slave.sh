#!/bin/bash
# set -x

( ( echo "$(date): Helm slave started ---";
	curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash;
	while true; do [ -f /usr/local/bin/helm ] && break; sleep 2; done;
	helm init --client-only;
	helm repo update;
	echo "$(date): Helm slave finished ---";
) &>>/var/log/kubernetes/k8s-helm-slave.log & )&

echo "$HOSTNAME Helm slave spawned"

exit 0
