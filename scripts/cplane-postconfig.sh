#!/bin/bash
# set -x

# components
K9S="0.26.7"
STERN="1.26.0"
KUBECTX="0.9.5"

( ( echo "$(date): --- cplane postconfig started";

	# utilities
	echo "$(date): retrieving k8s utilities";
	[ -n "${K9S}" ] && { wget -nv -O- "https://github.com/derailed/k9s/releases/download/v${K9S}/k9s_Linux_x86_64.tar.gz" | tar xz -C /usr/bin k9s; };
	[ -n "${STERN}" ] && {
		wget -nv -O- https://github.com/stern/stern/releases/download/v${STERN}/stern_${STERN}_linux_amd64.tar.gz | tar xz -C /usr/bin stern;
		/usr/bin/stern --completion=bash > /etc/bash_completion.d/stern.bash;
	};
	[ -n "${KUBECTX}" ] && {
		for KUBECTX_COMP in "kubens" "kubectx"; do
			wget -nv -O- "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/${KUBECTX_COMP}_v${KUBECTX}_linux_x86_64.tar.gz" | tar xz -C /usr/bin ${KUBECTX_COMP};
		done;

		wget -nv -O- "https://github.com/ahmetb/kubectx/archive/v${KUBECTX}.tar.gz" | tar xz --strip-components=2 -C /etc/bash_completion.d kubectx-${KUBECTX}/completion/kubens.bash kubectx-${KUBECTX}/completion/kubectx.bash;
	};

	# validate cplane configuration
	/usr/local/sbin/k8sm-config -f

	# cleanup
	rm -f /tmp/jelastic-{init,conf}-mark;

	echo "$(date): --- cplane postconfig finished";
) &>>/var/log/kubernetes/k8s-cplane-postconfig.log & )&

echo "${HOSTNAME} cplane postconfig spawned"

exit 0
