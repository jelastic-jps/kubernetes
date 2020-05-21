#!/bin/bash
# set -x

# core
HELM_VERSION="v2.16.7"

HELP="Usage:
	$0 --type=(master|slave)
Options:
	--type=       instance type (values: master, slave)
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
	echo -e "Missing mandatory argument --type=(master|slave)"
	exit 1
fi
if [ "x${COMPTYPE}" != "xmaster" ] && [ "x${COMPTYPE}" != "xslave" ]; then
	echo -e "Invalid argument value --type=${COMPTYPE}"
	exit 1
fi

export DESIRED_VERSION="$HELM_VERSION"

curl -s https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
while true; do [ -f /usr/local/bin/helm ] && break; sleep 2; done

if [ "x${COMPTYPE}" = "xmaster" ]; then
	echo "$(date): installing Helm master instance";
	helm init --upgrade --service-account tiller;
else
	echo "$(date): installing Helm slave instance";
	helm init --client-only;
fi

helm repo update

exit 0
