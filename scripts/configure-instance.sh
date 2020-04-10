#!/bin/bash
# set -x

# core
WEAVE="2.6.2"

HELP="Usage:
	$0 --type=(master|worker) --base-url=<base64-encoded-url>
Options:
	--type=       instance type (values: master, worker)
	--base-url=   manifest baseUrl
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
	--base-url=*)
		BASE_URL="${key#*=}"
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
if [ -z "${BASE_URL}" ]; then
	echo -e "Missing mandatory argument --base-url=<base64-encoded-url>"
	exit 1
fi

# scripts
if [ "x${COMPTYPE}" = "xmaster" ]; then
	SCRIPT_SET=( 'install-components' 'master-postconfig' 'helm-install' 'helm-components' 'check-install' )
else
	SCRIPT_SET=( 'worker-integration' )
fi

BASE_URL="$(echo ${BASE_URL} | base64 --decode)"

echo "$(date): downloading initialization scripts";
for ADD_SCRIPT in "${SCRIPT_SET[@]}"; do
	wget -nv "${BASE_URL}/scripts/${ADD_SCRIPT}.sh" -O "/usr/local/sbin/${ADD_SCRIPT}.sh";
	chmod +x "/usr/local/sbin/${ADD_SCRIPT}.sh";
done

# bootstrap configuration complete
touch /tmp/jelastic-conf-mark

# common dockers
echo "$(date): pulling common docker images"
while read item; do
	docker pull "$item";
done < <( kubeadm config images list --config /etc/kubernetes/custom-kubeadm.yaml | grep -E '(pause|kube-proxy)' )

# master dockers
[ "x${COMPTYPE}" = "xmaster" ] && {
	echo "$(date): pulling k8s master docker images";
	kubeadm config images pull --config /etc/kubernetes/custom-kubeadm.yaml;
}

# weave
[ -n "${WEAVE}" ] && {
	echo "$(date): pulling weave docker images";
	docker pull devbeta/weave-npc:${WEAVE};
	docker pull devbeta/weave-kube:${WEAVE};
}

# additional
[ "x${COMPTYPE}" = "xmaster" ] && {
	[ -n "${WEAVE}" ] && {
		echo "$(date): retrieving weaveexec components";
		docker pull weaveworks/weaveexec:${WEAVE};
		wget -nv "https://github.com/weaveworks/weave/releases/download/v${WEAVE}/weave" -O /usr/bin/weave;
		chmod +x /usr/bin/weave;
	};
}

exit 0
