#!/bin/bash
# set -x

# core
HELM_VERSION="v3.21.2"
HELM_SHA256="0a745198de24545d0055cd8414bc8d2ba10363ef5f5d38369ea1b399671cc083"

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

install_helm() {
	local helm_archive="helm-${HELM_VERSION}-linux-amd64.tar.gz"
	local tmp_dir
	local moved_old=0

	tmp_dir="$(mktemp -d)" || return 1
	curl -fsSL -o "${tmp_dir}/${helm_archive}" "https://get.helm.sh/${helm_archive}" || { rm -rf "${tmp_dir}"; return 1; }
	echo "${HELM_SHA256}  ${tmp_dir}/${helm_archive}" | sha256sum -c - || { rm -rf "${tmp_dir}"; return 1; }
	tar xzf "${tmp_dir}/${helm_archive}" -C "${tmp_dir}" linux-amd64/helm || { rm -rf "${tmp_dir}"; return 1; }
	if [ -f /usr/local/bin/helm ]; then
		mv -f /usr/local/bin/helm /usr/local/bin/helm_old || { rm -rf "${tmp_dir}"; return 1; }
		moved_old=1
	fi
	install -m 0755 "${tmp_dir}/linux-amd64/helm" /usr/local/bin/helm || {
		[ "${moved_old}" = "1" ] && mv -f /usr/local/bin/helm_old /usr/local/bin/helm
		rm -rf "${tmp_dir}"
		return 1
	}
	rm -rf "${tmp_dir}"
}

install_helm || exit 1

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
