#!/bin/bash
# set -x

# core
K8S="1.16.7"
PAUSE="3.1"
ETCD="3.3.15-0"
COREDNS="1.6.2"
WEAVE="2.5.2"

# components
K9S="0.17.4"
POPEYE="0.7.1"
STERN="1.11.0"
KUBECTX="0.8.0"

HELP="Usage:
	$0 --type=(master|worker) --repo=<dockerhub-repo>
Options:
	--type=       instance type (values: master, worker)
	--repo=       repository used (arbitrary)
	-h, --help    show this help
"
if [[ $# -eq 0 ]] ; then
	echo -e "${HELP}"
	exit 2
fi

for key in "$@"; do
	case $key in
	--type=*)
		COMPTYPE="${key#*=}"
		shift
		;;
	--repo=*)
		REPOSITORY="${key#*=}"
		shift
		;;
	-h | --help)
		echo -e "${HELP}"
		exit 1
		;;
	*)
		echo "Unknown argument passed: '$key'"
		echo -e "${HELP}"
		exit 1
		;;
	esac
done

if [ -z "${COMPTYPE}" ]; then
	echo -e "Missing mandatory argument --type=(master|worker)"
	exit 1
fi
if [ "x${COMPTYPE}" != "xmaster" ] && [ "x${COMPTYPE}" != "xworker" ]; then
	echo -e "Invalid argument value --type=${COMPTYPE}"
	exit 1
fi
if [ -z "${REPOSITORY}" ]; then
	echo -e "Missing mandatory argument --repo=<dockerhub-repo>"
	exit 1
fi

# common
echo "$(date): pulling common docker images"
docker pull ${REPOSITORY}/kube-proxy:v${K8S}
[ -n "${PAUSE}" ] && docker pull ${REPOSITORY}/pause:${PAUSE}

# kubernetes
[ "x${COMPTYPE}" = "xmaster" ] && {
	echo "$(date): pulling k8s master docker images";
	docker pull ${REPOSITORY}/kube-apiserver:v${K8S};
	docker pull ${REPOSITORY}/kube-controller-manager:v${K8S};
	docker pull ${REPOSITORY}/kube-scheduler:v${K8S};
	[ -n "${ETCD}" ] && docker pull ${REPOSITORY}/etcd:${ETCD};
	[ -n "${COREDNS}" ] && docker pull ${REPOSITORY}/coredns:${COREDNS};
}

# weave
[ -n "${WEAVE}" ] && {
	echo "$(date): pulling weave docker images";
	docker pull jelastic/weave-npc:${WEAVE};
	docker pull jelastic/weave-kube:${WEAVE};
}

# additional
[ "x${COMPTYPE}" = "xmaster" ] && {
	[ -n "${WEAVE}" ] && {
		echo "$(date): retrieving weaveexec components";
		docker pull weaveworks/weaveexec:${WEAVE};
		wget -nv "https://github.com/weaveworks/weave/releases/download/v${WEAVE}/weave" -O /usr/bin/weave;
		chmod +x /usr/bin/weave;
	};

	# scripts
	BASE_URL="https://raw.githubusercontent.com/jelastic-jps/kubernetes/v${K8S}";

	echo "$(date): downloading initialization scripts";
	for ADD_SCRIPT in "install-components" "helm-slave" "helm-components" "check-install"; do
		wget -nv "${BASE_URL}/scripts/${ADD_SCRIPT}.sh" -O "/usr/local/sbin/${ADD_SCRIPT}.sh";
		chmod +x "/usr/local/sbin/${ADD_SCRIPT}.sh";
	done

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
}

exit 0
