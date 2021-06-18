#!/bin/bash
# set -x

# core
WEAVE="2.8.1"

HELP="Usage:
	$0 --type=(cplane|worker) --base-url=<base64-encoded-url>
Options:
	--type=       instance type (values: cplane, worker)
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
	echo -e "Missing mandatory argument --type=(cplane|worker)"
	exit 1
fi
if [ "x${COMPTYPE}" != "xcplane" ] && [ "x${COMPTYPE}" != "xworker" ]; then
	echo -e "Invalid argument value --type=${COMPTYPE}"
	exit 1
fi
if [ -z "${BASE_URL}" ]; then
	echo -e "Missing mandatory argument --base-url=<base64-encoded-url>"
	exit 1
fi

# scripts
if [ "x${COMPTYPE}" = "xcplane" ]; then
	SCRIPT_SET=( 'install-components' 'cplane-postconfig' 'helm-install' 'helm-components' 'check-install' )
else
	SCRIPT_SET=( 'helm-install' 'worker-integration' )
fi

BASE_URL="$(echo ${BASE_URL} | base64 --decode)"

echo "$(date): downloading initialization scripts";
for ADD_SCRIPT in "${SCRIPT_SET[@]}"; do
	wget -nv "${BASE_URL}/scripts/${ADD_SCRIPT}.sh" -O "/usr/local/sbin/${ADD_SCRIPT}.sh";
	chmod +x "/usr/local/sbin/${ADD_SCRIPT}.sh";
done

# bootstrap configuration complete
touch /tmp/jelastic-conf-mark

# common images
echo "$(date): pulling common docker images"
while read item; do
	crictl pull "$item";
done < <( kubeadm config images list --config /etc/custom-kubeadm.yaml | grep -E '(pause|kube-proxy)' )

# cplane images
[ "x${COMPTYPE}" = "xcplane" ] && {
	echo "$(date): pulling k8s cplane images";
	kubeadm config images pull --config /etc/custom-kubeadm.yaml;
}

# weave
[ -n "${WEAVE}" ] && {
	echo "$(date): pulling weave images";
	crictl pull public.ecr.aws/t6h9l3f8/weave-npc:${WEAVE};
	crictl pull public.ecr.aws/t6h9l3f8/weave-kube:${WEAVE};
}

exit 0
