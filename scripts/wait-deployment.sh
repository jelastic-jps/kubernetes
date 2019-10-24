#!/bin/bash
# $1 is object name, $2 is namespace name, $3 is desired replica count, $4 is timeout

printError() {
  echo "Failed to verify deployment $1. Current replicas is '${CUNNRENT_COUNT}'"
  echo "Pods in $2 namespace:"
  kubectl get pods -n $2
  echo "Events in $2 namespace:"
  kubectl get events -n $2
}

if [ -z $1 ] || [ -z $2 ]; then
  echo "Deployment name and namespace are mandarory arguments. Rerun the script with deployment name and namespace as args"
  exit 1
fi
DEPLOYMENT=$1
NAMESPACE=$2
DEFAULT_REQUIRED_COUNT=1
REQUIRED_COUNT=${3:-${DEFAULT_REQUIRED_COUNT}}
DEFAULT_TIMEOUT=300
TIMEOUT=${4:-${DEFAULT_TIMEOUT}}
echo "Waiting for deployment $DEPLOYMENT. Timeout in $TIMEOUT seconds"
CUNNRENT_COUNT=$(kubectl get deployment/$DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.status.availableReplicas}')
if [ $? -ne 0 ]; then
  echo "An error occurred. Exiting"
  exit 1
fi
SLEEP=5
exit=$((SECONDS+TIMEOUT))
while [ "${CUNNRENT_COUNT}" -ne "${REQUIRED_COUNT}" ] && [ ${SECONDS} -lt ${exit} ]; do
  CUNNRENT_COUNT=$(kubectl get deployment/$DEPLOYMENT -n $NAMESPACE -o=jsonpath='{.status.availableReplicas}')
  timeout_in=$((exit-SECONDS))
  sleep ${SLEEP}
done

if [ "${CUNNRENT_COUNT}" -ne "${REQUIRED_COUNT}"  ]; then
  printError $DEPLOYMENT $NAMESPACE
  exit 1
elif [ ${SECONDS} -ge ${exit} ]; then
  echo "Deployment $DEPLOYMENT timed out. Current replicas is ${CUNNRENT_COUNT}"
  printError $DEPLOYMENT $NAMESPACE
  exit 1
fi
echo "Deployment $1 successfully scaled"
