#!/bin/bash
# set -x

# components
NPD_TAG="v0.8.14"

HELP="Usage:
	$0 --base-url=<base64-encoded-url> --nfs-provisioner=(true|false) --nfs-server=<ip-address> --problem-detector=(true|false)
Options:
	--base-url=           manifest baseUrl
	--nfs-provisioner=    install nfs-client-provisioner
	--nfs-server=         nfs-client-provisioner NFS server address
	--problem-detector=   install node-problem-detector
	-h, --help    show this help
"
if [[ $# -eq 0 ]] ; then
	echo -e "${HELP}"
	exit 2
fi

for key in "$@"; do
	case $key in
	--base-url=*)
		BASE_URL="${key#*=}"
		shift
		;;
	--nfs-provisioner=*)
		NFS_INSTALL="${key#*=}"
		shift
		;;
	--nfs-server=*)
		NFS_SERVER="${key#*=}"
		shift
		;;
	--problem-detector=*)
		PROBLEM_DETECT="${key#*=}"
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

if [ -z "${BASE_URL}" ]; then
	echo -e "Missing mandatory argument --base-url=<base64-encoded-url>"
	exit 1
fi

( ( echo "$(date): --- Helm components started";

	BASE_URL="$(echo ${BASE_URL} | base64 --decode)"

	if [ "x${NFS_INSTALL}" = "xtrue" ] && [ -n "${NFS_SERVER}" ]; then
		echo "$(date): installing nfs-subdir-external-provisioner"
		helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/;
		helm repo update;
		helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=${NFS_SERVER} --set nfs.path=/data --set nfs.mountOptions='{soft,proto=tcp}' --set replicaCount=3 --set storageClass.defaultClass=true --set storageClass.allowVolumeExpansion=true --set storageClass.name=jelastic-dynamic-volume ;
	else
		echo "$(date): nfs-subdir-external-provisioner installation skipped"
	fi

	if [ "x${PROBLEM_DETECT}" = "xtrue" ]; then
		echo "$(date): installing node-problem-detector"
		helm repo add deliveryhero https://charts.deliveryhero.io/;
		helm repo update;
		helm install node-problem-detector deliveryhero/node-problem-detector --set image.tag=${NPD_TAG};
	else
		echo "$(date): node-problem-detector installation skipped"
	fi

	echo "$(date): --- Helm components finished";
) &>>/var/log/kubernetes/k8s-helm-components.log & )&

echo "${HOSTNAME} Helm components spawned"

exit 0
