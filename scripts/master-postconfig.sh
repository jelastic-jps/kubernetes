#!/bin/bash
# set -x

# components
K9S="0.24.4"
STERN="1.11.0"
KUBECTX="0.9.3"

( ( echo "$(date): --- master postconfig started";

	# utilities
	echo "$(date): retrieving k8s utilities";
	[ -n "${K9S}" ] && { wget -O- "https://github.com/derailed/k9s/releases/download/v${K9S}/k9s_Linux_x86_64.tar.gz" | tar xz -C /usr/bin k9s; };
	[ -n "${STERN}" ] && {
		wget -nv "https://github.com/wercker/stern/releases/download/${STERN}/stern_linux_amd64" -O /usr/bin/stern;
		chmod +x /usr/bin/stern;
		/usr/bin/stern --completion=bash > /etc/bash_completion.d/stern.bash;
	};
	[ -n "${KUBECTX}" ] && {
		for KUBECTX_COMP in "kubens" "kubectx"; do
			wget -O- "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/${KUBECTX_COMP}_v${KUBECTX}_linux_x86_64.tar.gz" | tar xz -C /usr/bin ${KUBECTX_COMP};
		done;

		wget -O- "https://github.com/ahmetb/kubectx/archive/v${KUBECTX}.tar.gz" | tar xz --strip-components=2 -C /etc/bash_completion.d kubectx-${KUBECTX}/completion/kubens.bash kubectx-${KUBECTX}/completion/kubectx.bash;
	};

	# validate master configuration
	/usr/local/sbin/k8sm-config -f

	# cleanup
	rm -f /tmp/jelastic-{init,conf}-mark;

	echo "$(date): --- master postconfig finished";
) &>>/var/log/kubernetes/k8s-master-postconfig.log & )&

echo "${HOSTNAME} master postconfig spawned"

exit 0
