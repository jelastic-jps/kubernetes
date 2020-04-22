#!/bin/bash
# set -x

# components
METALLB_VER="0.9.3"

HELP="Usage:
	$0 --base-url=<base64-encoded-url> --admin-account=(true|false) --metallb=(true|false) --metrics-server=(true|false) --dashboard=version(1|2) --ingress-name=<ingress-controller>
Options:
	--base-url=         manifest baseUrl
	--admin-account=    setup admin account
	--metallb=          install metallb-controller
	--metrics-server=   install metrics-server
	--dashboard=        install kubernetes-dashboard
	--ingress-name=     ingress controller used
	-h, --help          show this help
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
	--admin-account=*)
		ADMIN_ACCOUNT="${key#*=}"
		shift
		;;
	--metallb=*)
		METALLB="${key#*=}"
		shift
		;;
	--metrics-server=*)
		METRICS_SERVER="${key#*=}"
		shift
		;;
	--dashboard=*)
		DASHBOARD="${key#*=}"
		shift
		;;
	--ingress-name=*)
		INGRESS_NAME="${key#*=}"
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

( ( echo "$(date): --- install components started";

	BASE_URL="$(echo ${BASE_URL} | base64 --decode)"

	if [ "x${ADMIN_ACCOUNT}" = "xtrue" ]; then
		echo "$(date): setting admin account";
		kubectl create -f "${BASE_URL}/addons/admin-account.yaml";
	else
		echo "$(date): admin account setting skipped"
	fi

	if [ "x${METALLB}" = "xtrue" ]; then
		echo "$(date): installing metallb-controller"
		kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/v${METALLB_VER}/manifests/namespace.yaml";
		kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/v${METALLB_VER}/manifests/metallb.yaml";
		kubectl -n metallb-system get secret memberlist &>/dev/null || \
			kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(/usr/bin/openssl rand -base64 128)";
		kubectl apply -f "${BASE_URL}/addons/metallb-config.yaml";
	else
		echo "$(date): metallb-controller installation skipped"
	fi

	if [ "x${METRICS_SERVER}" = "xtrue" ]; then
		echo "$(date): installing metrics-server";
		kubectl create -f "${BASE_URL}/addons/metrics-server/aggregated-metrics-reader.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/auth-delegator.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/auth-reader.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/metrics-apiservice.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/metrics-server-deployment.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/metrics-server-service.yaml";
		kubectl create -f "${BASE_URL}/addons/metrics-server/resource-reader.yaml";
		wait-deployment.sh metrics-server kube-system 1 720
	else
		echo "$(date): metrics-server installation skipped"
	fi

	if [ -n "${DASHBOARD}" ] && [ -n "${INGRESS_NAME}" ]; then
		echo "$(date): installing kubernetes-dashboard '${DASHBOARD}'";
		case "${DASHBOARD}" in
		version1)
			kubectl create -f "${BASE_URL}/addons/kubernetes-dashboard.yaml";
			kubectl create -f "${BASE_URL}/addons/ingress/${INGRESS_NAME}/dashboard-ingress.yaml";
		;;
		version2)
			kubectl apply -f "${BASE_URL}/addons/kubernetes-dashboard-beta.yaml";
			kubectl apply -f "${BASE_URL}/addons/ingress/${INGRESS_NAME}/dashboard-ingress-beta.yaml";
		;;
		*)
			echo "$(date): unknown kubernetes-dashboard version '${DASHBOARD}', skipped"
		;;
		esac
	else
		echo "$(date): kubernetes-dashboard installation skipped"
	fi

	echo "$(date): --- install components finished";
) &>>/var/log/kubernetes/k8s-install-components.log & )&

echo "${HOSTNAME} install components spawned"

exit 0
