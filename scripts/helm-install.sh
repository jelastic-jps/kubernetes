#!/bin/bash
# set -x

# core
HELM_VERSION="v3.12.3"

HELP="Usage:
	$0 --migrate=(main|secondary)
Options:
	--migrate=    migration instance type (values: main, secondary)
	-h, --help    show this help
"

for key in "$@"; do
	case $key in
	--migrate=*)
		MIG_TYPE="${key#*=}"
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

if [ -n "${MIG_TYPE}" ] && [ "x${MIG_TYPE}" != "xmain" ] && [ "x${MIG_TYPE}" != "xsecondary" ]; then
	echo -e "Invalid argument value --migrate=${MIG_TYPE}"
	exit 1
fi

migrate_config() {

	/usr/bin/yum install -y git
	helm plugin install https://github.com/helm/helm-2to3
	helm 2to3 move config --skip-confirmation
	helm repo remove "local"
}

migrate_full() {

	migrate_config

	HELM_RELEASES=$(/usr/local/bin/helm_old list -aq)
	while IFS= read -r release; do
		helm 2to3 convert ${release};
	done <<< "${HELM_RELEASES}"

	helm list
	helm 2to3 cleanup --skip-confirmation
}

mv -f /usr/local/bin/helm /usr/local/bin/helm_old &>/dev/null

export DESIRED_VERSION="$HELM_VERSION"

while true; do
	curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash;
	[ -f /usr/local/bin/helm ] && break; sleep 5;
done

if [ -n "${MIG_TYPE}" ]; then

	if /usr/local/bin/helm_old version | grep -q 'SemVer:\"v2\.'; then
		case "x${MIG_TYPE}" in
		xmain)
			migrate_full
			;;
		xsecondary)
			migrate_config
			;;
		esac
	else
		echo "Helm 2 wasn't detected, migration skipped"
	fi
fi

rm -f /usr/local/bin/helm_old

helm repo add "stable" "https://charts.helm.sh/stable" --force-update

helm repo update

exit 0
