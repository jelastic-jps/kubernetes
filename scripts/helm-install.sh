#!/bin/bash
# set -x

# core
HELM_VERSION="v2.16.3"

HELP="Usage:
	$0 --master=(true|false)
Options:
	--master=     perform Helm master installation
	-h, --help    show this help
"
if [[ $# -eq 0 ]] ; then
	echo -e "${HELP}"
	exit 2
fi

for key in "$@"; do
	case $key in
	--master=*)
		MASTER="${key#*=}"
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

if [ -z "${MASTER}" ]; then
	echo -e "Missing mandatory argument --master=(true|false)"
	exit 1
fi

export DESIRED_VERSION="$HELM_VERSION"

curl -s https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
while true; do [ -f /usr/local/bin/helm ] && break; sleep 2; done

if [ "x${MASTER}" = "xtrue" ]; then
	echo "$(date): installing Helm master instance";
	helm init --upgrade --service-account tiller;
else
	echo "$(date): installing Helm slave instance";
	helm init --client-only;
fi

helm repo update

exit 0
