#!/bin/bash
# set -x

# components
K9S="0.24.2"
POPEYE="0.9.0"
STERN="1.11.0"
KUBECTX="0.8.0"

( ( echo "$(date): --- master postconfig started";

	# utilities
	echo "$(date): retrieving k8s utilities";
	[ -n "${K9S}" ] && { wget -O- "https://github.com/derailed/k9s/releases/download/v${K9S}/k9s_Linux_x86_64.tar.gz" | tar xz -C /usr/bin k9s; };
	[ -n "${POPEYE}" ] && { wget -O- "https://github.com/derailed/popeye/releases/download/v${POPEYE}/popeye_Linux_x86_64.tar.gz" | tar xz -C /usr/bin popeye; };
	[ -n "${STERN}" ] && {
		wget -nv "https://github.com/wercker/stern/releases/download/${STERN}/stern_linux_amd64" -O /usr/bin/stern;
		chmod +x /usr/bin/stern;
		/usr/bin/stern --completion=bash > /etc/bash_completion.d/stern.bash;
	};
	[ -n "${KUBECTX}" ] && {
		wget -O- "https://github.com/ahmetb/kubectx/archive/v${KUBECTX}.tar.gz" | tar xz --strip-components=1 -C /usr/bin kubectx-${KUBECTX}/kubectx kubectx-${KUBECTX}/kubens;
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
