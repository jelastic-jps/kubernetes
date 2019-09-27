#!/bin/bash
# set -x
HELP="
Usage:
 $0 [options]
Options:
 -d=,   --domain=            environment domain without protocol (e.g. mykube.jelastic.com), mandatory, no defaults
 -i=,   --ingress=           ingress controller name
 -m=,   --monitoring=        check monitoring tools, defaults to false
 -r=,   --remote-api=        check remote api availability, defaults to false
 -s=,   --storage=           check NFS storage, defaults to false
 -app=, --sample-app         check either defualt Hello World app (cc) or a custom syntax [cmd], defaults to cc
 -h,    --help               show this help
"

if [[ $# -eq 0 ]] ; then
  echo -e "$HELP"
  exit 0
fi

for key in "$@"
do
  case $key in
    -d=*| --domain=*)
      DOMAIN="${key#*=}"
      shift
      ;;
    -m=*| --monitoring=*)
      MONITORING="${key#*=}"
      shift
      ;;
    -r=*| --remote-api=*)
      REMOTE_API=$(echo "${key#*=}")
      shift
      ;;
    -i=*| --ingress=*)
      INGRESS_CONTROLLER=$(echo "${key#*=}")
      shift
      ;;
    -app=*| --sample-app=*)
      SAMPLE_APP=$(echo "${key#*=}")
      shift
    ;;
    -s=*| --storage=*)
      STORAGE=$(echo "${key#*=}")
      shift
      ;;
    -h | --help)
      echo -e "$HELP"
      exit 1
      ;;
    *)
      echo "Unknown argument passed: '$key'."
      echo -e "$HELP"
      exit 1
      ;;
  esac
done
if [ -z "$DOMAIN" ]
  then
    echo -e "
Missing mandatory argument -d=\$DOMAIN.

Either rerun the stript with -d=\$DOMAIN flag:
$0 -d=nydomain.jelastic.com

or set a local DOMAIN variable:
DOMAIN=nydomain.jelastic.com; $0 [options]"
    exit 1
fi
K8S_EVENTS_LOG_FILE="/var/log/k8s-events.log"
METRICS_SERVER_NAME="metrics-server"
CNI_PLUGIN_NAME="weave-net"
DASHBOARD_DEPLOYMENT_NAME="kubernetes-dashboard"
NGINX_DEPLOYMENT_NAME="nginx-ingress-controller"

DEFAULT_SAMPLE_APP="cc"
SAMPLE_APP=${SAMPLE_APP:-${DEFAULT_SAMPLE_APP}}


DEFAULT_MONITORING="false"
MONITORING=${MONITORING:-${DEFAULT_MONITORING}}

DEFAULT_INGRESS_CONTROLLER="traefik"
INGRESS_CONTROLLER=${INGRESS_CONTROLLER:-${DEFAULT_INGRESS_CONTROLLER}}

DEFAULT_REMOTE_API="false"
REMOTE_API=${REMOTE_API:-${DEFAULT_REMOTE_API}}



printInfo() {
  echo "[INFO]: ${1}"
}

printWarning() {
  echo "[WARNING]: ${1}"
}

printError() {
  echo "[ERROR]: ${1}"
}

writeLog() {
  echo -e "\n[TIME]    : $(date)\n[COMMAND] : ${1}:\n[LOG START]:\n\n$(${1})\n[LOG END]\n" >> ${2}
}

checkWeaveStatus() {
  printInfo "Checking Weave CNI Plugin status..."
  command -v weave >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    printError "Weave CLI not installed. Cannot check weave health"
    WITH_ERROR="true"
  else
    STATUS=$(weave status | grep "Status: ready" > /dev/null)
    if [ $? -ne 0 ]; then
      printError "Weave has not reported ready status. Current status is:"
      weave status
      printError "Weave daemon set and pods status:"
      kubectl get ds/"${CNI_PLUGIN_NAME}" -n kube-system
      kubectl get pods -l=name="${CNI_PLUGIN_NAME}" -n kube-system
    else
      # get number of nodes and make sure there's the same number of Traefik pods in Running state
      NODES_NUMBER=$(kubectl get nodes --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | tee >(wc -l) | tail -1)
      END=`expr $NODES_NUMBER - 1`
      for ((i=0;i<=END;i++)); do
        NODENAME=$(kubectl get pods -l=name=${CNI_PLUGIN_NAME} -n kube-system -o jsonpath="{.items[$i].spec.nodeName}" 2> /dev/null)
        if [ $? -ne 0 ]; then
          printWarning "Failed to get node name because of array index out of bounds"
          break
        fi
        PODNAME=$(kubectl get pods -l=name=${CNI_PLUGIN_NAME} -n kube-system -o jsonpath="{.items[$i].metadata.name}" 2> /dev/null)
        STATUS=$(kubectl get pods -l=name=${CNI_PLUGIN_NAME} -n kube-system -o jsonpath="{.items[$i].status.phase}" 2> /dev/null)
        printInfo "Checking status on Node $NODENAME"
        if [ "$STATUS" != "Running" ]; then
          printError "Failed ${CNI_PLUGIN_NAME} pod ${PODNAME} on $NODENAME with status ${STATUS}"
          kubectl logs ${PODNAME} -n kube-system > /var/log/${PODNAME}.log
          printError "Check logs in /var/log/${PODNAME}.log"
          WITH_ERROR="true"
        else
          printInfo "${CNI_PLUGIN_NAME} pod ${PODNAME} on $NODENAME successfully started"
          WEAVE_STATUS="OK"
        fi
      done
    fi
  fi
}

checkMetricsServer() {
  printInfo "Checking Metrics Server status"
  readyReplicas=$(kubectl get deployment/"${METRICS_SERVER_NAME}" -o=jsonpath='{.status.readyReplicas}' -n kube-system 2> /dev/null)
  if [ $? -ne 0 ]; then
    printError "Metrics server deployment not found"
    WITH_ERROR="true"
  else
    if [ "${readyReplicas}" -lt 1 ]; then
      printInfo "${METRICS_SERVER_NAME} deployment isn't scaled to 1. Checking pods logs..."
      METRICS_SERVER_POD=$(kubectl get pods -l=k8s-app="${METRICS_SERVER_NAME}" -n kube-system --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
      if [ -z $METRICS_SERVER_POD ]; then
        printError "Failed to find ${METRICS_SERVER_NAME} pod"
        WITH_ERROR="true"
      else
        STATUS=$(kubectl get pods/${METRICS_SERVER_POD} -n kube-system -o jsonpath="{.status.phase}" 2> /dev/null)
        printError "Metrics server is not running and currently in status ${STATUS}"
        printError "${METRICS_SERVER_NAME} pod logs are available in /var/log/metrics-server.log"
        printError "Inspect K8s events in ${K8S_EVENTS_LOG_FILE}"
        kubectl logs ${METRICS_SERVER_POD} -n kube-system > /var/log/metrics-server.log
        WITH_ERROR="true"
      fi
    else
      printInfo "Metrics server is running"
      METRICS_STATUS="OK"
    fi
  fi
}

checkDashboard() {
  printInfo "Checking Kubernetes Dashboard deployment"
  readyReplicas=$(kubectl get deployment/"${DASHBOARD_DEPLOYMENT_NAME}" -o=jsonpath='{.status.readyReplicas}' -n ${DASHBOARD_DEPLOYMENT_NAME} 2> /dev/null)
  if [ $? -ne 0 ]; then
    printError "Deployment ${DASHBOARD_DEPLOYMENT_NAME} not found"
    WITH_ERROR="true"
  else
    if [ "${readyReplicas}" -lt 1 ]; then
      printInfo "${DASHBOARD_DEPLOYMENT_NAME} deployment isn't scaled to 1. Checking pods logs..."
      KUBERNETES_DASHBOARD_POD=$(kubectl get pods -l=k8s-app="${DASHBOARD_DEPLOYMENT_NAME}" -n kubernetes-dashboard --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
      if [ -z $KUBERNETES_DASHBOARD_POD ]; then
        printError "Failed to find ${DASHBOARD_DEPLOYMENT_NAME} pod"
        printError "Inspect K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
        WITH_ERROR="true"
      else
        DASHBOARD_POD_STATUS=$(kubectl get pods/$KUBERNETES_DASHBOARD_POD -n kubernetes-dashboard -o jsonpath="{.status.phase}" 2> /dev/null)
        printError "Kubernetes Dashboard is not running. Current status is: ${DASHBOARD_POD_STATUS}"
        printError "${DASHBOARD_DEPLOYMENT_NAME} pod logs are available in /var/log/kubernetes-dashboard.log"
        printError "Inspect K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
        kubectl logs ${KUBERNETES_DASHBOARD_POD} -n ${DASHBOARD_DEPLOYMENT_NAME} > /var/log/kubernetes-dashboard.log
        WITH_ERROR="true"
      fi
    else
      printInfo "Kubernetes Dashboard is running"
      DASHBOARD_STATUS="OK"
    fi
  fi
}

checkTraefikIngressController() {
  # check if there is at least one running Traefik pod
  POD_STATUS=$(kubectl get pods -l=name=traefik-ingress-lb -n kube-system -o jsonpath="{.items[0]}" 2> /dev/null)
  if [ $? -ne 0 ]; then
    printError "No traefik pods found. Either daemon set was not created or something prevented pods from scheduling"
    printError "Check K8s event in ${K8S_EVENTS_LOG_FILE} on a master node"
  else
  # get number of nodes and make sure there's the same number of Traefik pods in Running state
  MASTER_NODES=$(kubectl get nodes -l=node-role.kubernetes.io/master="" --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | tee >(wc -l) | tail -1)
  NODES_NUMBER=$(kubectl get nodes --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | tee >(wc -l) | tail -1)
  NODES=`expr $NODES_NUMBER - $MASTER_NODES`
  END=`expr $NODES - 1`
  for ((i=0;i<=END;i++)); do
    NODENAME=$(kubectl get pods -l=name=traefik-ingress-lb -n kube-system -o jsonpath="{.items[$i].spec.nodeName}" 2> /dev/null)
    if [ $? -ne 0 ]; then
      printWarning "Failed to get node name because of array index out of bounds"
      break
    fi
    PODNAME=$(kubectl get pods -l=name=traefik-ingress-lb -n kube-system -o jsonpath="{.items[$i].metadata.name}" 2> /dev/null)
    STATUS=$(kubectl get pods -l=name=traefik-ingress-lb -n kube-system -o jsonpath="{.items[$i].status.phase}" 2> /dev/null)
    printInfo "Checking Traefik pod status on Node $NODENAME"
    if [ "$STATUS" != "Running" ]; then
      printError "Failed Traefik pod ${PODNAME} on $NODENAME with status: $STATUS"
      kubectl logs ${PODNAME} -n kube-system > /var/log/${PODNAME}.log
      printError "Check logs in /var/log/${PODNAME}.log"
      WITH_ERROR="true"
      INGRESS_STATUS="FAIL"
    else
      printInfo "Traefik pod ${PODNAME} on $NODENAME successfully started"
      INGRESS_STATUS="OK"
    fi
  done
fi
}

checkNginxIngressController() {
  readyReplicas=$(kubectl get deployment/"${NGINX_DEPLOYMENT_NAME}" -o=jsonpath='{.status.readyReplicas}' -n ingress-nginx 2> /dev/null)
  if [ $? -ne 0 ]; then
    printError "${INGRESS_CONTROLLER} deployment not found. Check installation logs (CS) and K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
    INGRESS_STATUS="FAIL"
    WITH_ERROR="true"
  else
    if [ "${readyReplicas}" -lt 1 ]; then
      printInfo "${NGINX_DEPLOYMENT_NAME} deployment isn't scaled to 1. Checking pods logs..."
      NGINX_POD=$(kubectl get pods -l=app.kubernetes.io/name=ingress-nginx -n ingress-nginx --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
      if [ -z $NGINX_POD ]; then
        printError "Failed to find ${NGINX_POD} pod"
        INGRESS_STATUS="FAIL"
        WITH_ERROR="true"
      else
        printError "${NGINX_DEPLOYMENT_NAME} is not running"
        printError "${NGINX_DEPLOYMENT_NAME} pod logs are available in /var/log/${NGINX_POD}.log"
        printError "Inspect K8s events in ${K8S_EVENTS_LOG_FILE}"
        kubectl logs ${NGINX_POD} -n ingress-nginx > /var/log/${NGINX_POD}.log
        INGRESS_STATUS="FAIL"
        WITH_ERROR="true"
      fi
    else
      printInfo "Ingress controller ${INGRESS_CONTROLLER} is running"
      INGRESS_STATUS="OK"
    fi
  fi
}

checkHaproxyIngressController() {

  PODNAME=$(kubectl get pods -l=run=haproxy-ingress -n ingress-controller -o jsonpath='{.items[0].metadata.name}' 2> /dev/null)
  if [ $? -ne 0 ]; then
    DAEMON_SET=$(kubectl get ds/haproxy-ingress -n ingress-controller > /dev/null)
    if [ $? -ne 0 ]; then
      printError "Failed to find HAproxy pod because of a missing daemon set"
      INGRESS_STATUS="FAIL"
      WITH_ERROR="true"
    else
      printError "Failed to find HAproxy pod, though HAProxy daemon set was found"
      INGRESS_STATUS="FAIL"
      WITH_ERROR="true"
    fi
    printError "Check K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
  else
    HAPROXY_POD_STATUS=$(kubectl get pods -l=run=haproxy-ingress -n ingress-controller -o jsonpath='{.items[0].status.phase}' 2> /dev/null)
    if [ "$HAPROXY_POD_STATUS" != "Running" ]; then
      printError "HAProxy pod isn't in running state. Current status: $HAPROXY_POD_STATUS"
      kubectl logs ${PODNAME} -n ingress-controller > /var/log/${PODNAME}.log
      printError "Check logs in /var/log/${PODNAME}.log"
      INGRESS_STATUS="FAIL"
      WITH_ERROR="true"
    else
      printInfo "HAProxy pod ${PODNAME} successfully started"
      INGRESS_STATUS="OK"
    fi
 fi
}

checkIngressController() {
  printInfo "Checking ${INGRESS_CONTROLLER} ingress controller"
  if [ ${INGRESS_CONTROLLER} == "traefik" ]; then
    checkTraefikIngressController
  elif [ ${INGRESS_CONTROLLER} == "nginx" ]; then
    checkNginxIngressController
  else
    checkHaproxyIngressController
  fi
}

checkRemoteApi() {
  printInfo "Checking Remote API status"
  URL="http://${DOMAIN}/api"
  TOKEN=$(kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep fulladmin | awk '{print $1}')  | grep 'token:' | sed -e's/token:\| //g')
  STATUSCODE=$(curl -Lk --silent  --output /dev/null -X GET --output /dev/stderr --write-out "%{http_code}" --header "Authorization: Bearer $TOKEN" --insecure "${URL}")
  OUT=$?
  if [ $STATUSCODE -eq 403 ]; then
    printWarning "Remote API $URL is avaialbe but $STATUSCODE has been returned. Check fulladmin service account roles and rolebindings"
    REMOTEAPI_STATUS="WARNING. Check logs"
  elif [ $OUT -ne 0 ]; then
    printError "Remote API $URL is unavailable. cURL exit code is $OUT"
    WITH_ERROR="true"
  elif [ $STATUSCODE -ne 200 ]; then
    printError "Remote API $URL is unavailable and returned ${STATUSCODE}"
    WITH_ERROR="true"
  else
    printInfo "Remote API $URL is available and returned ${STATUSCODE}"
    REMOTEAPI_STATUS="OK"
  fi
}

getRootUrl()  {
  URL="http://${DOMAIN}/"
  STATUSCODE=$(curl --silent -Lk --output /dev/null -X GET --output /dev/stderr --write-out "%{http_code}" "${URL}")
  if [ $STATUSCODE -ne 200 ]; then
    printError "$URL is unavailable. cURL exit code is $STATUSCODE"
    WITH_ERROR="true"
  else
    printInfo "$URL is available and returned ${STATUSCODE}"
    APP_STATUS="OK"
  fi
}

checkSampleApp() {
  if [ "${SAMPLE_APP}" == "cmd" ]; then
    APP="app installed by a custom command"
  else
    APP="Hello World app"
fi
  printInfo "Checking ${APP}"
  if [ "${SAMPLE_APP}" == "cmd" ]; then
    OPEN_LIBERTY_INGRESS=$(kubectl get ingress/open-liberty -n default --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' 2> /dev/null)
    if [ $? -ne 0 ]; then
      printWarning "Default OpenLiberty ingress not found. Perhaps CMD command was modified"
      printWarning "Disregard this warning if you modified a custom cmd command"
      APP_STATUS="WARNING. Check logs"
    else
      getRootUrl
    fi
  else
    getRootUrl
  fi
}


checkNfsStorage() {
  printInfo "Checking status on NFS provisioner pods"
  END="2"
  for ((i=0;i<=END;i++)); do
    PODNAME=$(kubectl get pods -l=app=nfs-client-provisioner -n default -o jsonpath="{.items[$i].metadata.name}" 2> /dev/null)
    if [ $? -ne 0 ]; then
      printError "Failed to find NFS provisioner pods. NFS privioners may have failed or has not been deployed"
      printError "Check K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
      WITH_ERROR="true"
      break
    fi
    STATUS=$(kubectl get pods -l=app=nfs-client-provisioner -n default -o jsonpath="{.items[$i].status.phase}" 2> /dev/null)
    if [ "$STATUS" != "Running" ]; then
      printError "Failed pod ${PODNAME} with status $STATUS"
      kubectl logs ${PODNAME} -n default > /var/log/${PODNAME}.log
      printError "Check logs in /var/log/${PODNAME}.log"
      WITH_ERROR="true"
    else
      printInfo "Provisioner pod ${PODNAME} is running"
      NFS_STORAGE_STATUS="OK"
    fi
  done

}


checkMonitoring() {

  printInfo "Checking monitoring tools"

  DEPLOYMENTS=(
              monitoring-prometheus-alertmanager
              monitoring-prometheus-kube-state-metrics
              monitoring-prometheus-pushgateway
              monitoring-prometheus-server
              monitoring-grafana
              )
  PODS=( 0 1 2 4)

  for ((i=0;i<${#PODS[@]};++i));
  do
    readyReplicas=$(kubectl get deployment/"${DEPLOYMENTS[i]}" -o=jsonpath='{.status.readyReplicas}' -n kubernetes-monitoring 2> /dev/null)
    if [ $? -ne 0 ]; then
      printError "deployment ${DEPLOYMENTS[i]} not found. Check installation logs (CS) and K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
      MONIT_ERROR="true"
    else
      if [ "${readyReplicas}" -lt 1 ]; then
        printInfo "Deployment ${DEPLOYMENTS[i]} isn't scaled to 1. Checking pods logs..."
        APP="prometheus"
        if [ ${DEPLOYMENTS[i]} == "monitoring-grafana" ]; then
          APP="grafana"
        fi
        if [ ${DEPLOYMENTS[i]} == "monitoring-grafana" ]; then
          MONIT_POD=$(kubectl get pods -l=app=${APP} -n kubernetes-monitoring -o jsonpath="{.items[0].metadata.name}")
        else
          MONIT_POD=$(kubectl get pods -l=app=${APP} -n kubernetes-monitoring -o jsonpath="{.items[${PODS[i]}].metadata.name}")
        fi
        if [ -z $MONIT_POD ]; then
          printError "Failed to find ${MONIT_POD} pod"
          MONIT_ERROR="true"
          WITH_ERROR="true"
        else
          printError "${MONIT_POD} is not running"
          printError "${MONIT_POD} pod logs are available in /var/log/${MONIT_POD}.log"
          printError "It is recommended to inspect K8s events in ${K8S_EVENTS_LOG_FILE}"
          if [ ${DEPLOYMENTS[i]} == "monitoring-prometheus-server" ]; then
            kubectl logs ${MONIT_POD} -c prometheus-server-configmap-reload -n kubernetes-monitoring > /var/log/${MONIT_POD}.log
            kubectl logs ${MONIT_POD} -c prometheus-server -n kubernetes-monitoring >> /var/log/${MONIT_POD}.log
          elif [ ${DEPLOYMENTS[i]} == "monitoring-prometheus-alertmanager" ]; then
            kubectl logs ${MONIT_POD} -c prometheus-alertmanager-configmap-reload -n kubernetes-monitoring > /var/log/${MONIT_POD}.log
            kubectl logs ${MONIT_POD} -c prometheus-alertmanager -n kubernetes-monitoring >> /var/log/${MONIT_POD}.log
          else
          kubectl logs ${MONIT_POD} -n kubernetes-monitoring > /var/log/${MONIT_POD}.log
        fi
          MONIT_ERROR="true"
        fi
      fi
    fi
  done
  grafana_secret=$(kubectl get secret --namespace kubernetes-monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 --decode ; echo)
  URL="http://${DOMAIN}/grafana"
  STATUSCODE=$(curl -u "admin:${grafana_secret}" --silent -Lk --output /dev/null -X GET --output /dev/stderr --write-out "%{http_code}" "$URL")
  if [ $STATUSCODE -ne 200 ]; then
    printError "$URL is unavailable. cURL exit code is $STATUSCODE"
    MONIT_ERROR="true"
  else
    printInfo "$URL is available and returned ${STATUSCODE}"
    MONITORING_STATUS="OK"
  fi
  if [ -z $MONIT_ERROR ]; then
    printInfo "Monitoring tools are running"
    MONITORING_STATUS="OK"
  else
    printError "Monitoring tools are deployed but external endpoints are unavailable"
    MONIT_ERROR="true"
  fi
}

checkNodeProblemDetector(){
  printInfo "Checking Node problem detector deployment"
  POD_STATUS=$(kubectl get pods -l=app=node-problem-detector -n default -o jsonpath="{.items[0]}" 2> /dev/null)
  if [ $? -ne 0 ]; then
    kubectl get ds/node-problem-detector -o yaml &>> /var/log/node-problem-detector.yaml
    if [ $? -ne 0 ]; then
      printError "Node-problem detector daemon set not found"
      printError "Check available DaemonSets in /var/log/daemonsets-default-ns.log"
      writeLog "kubectl get ds" "/var/log/daemonsets.log"
      WITH_ERROR="true"
    else
      DEFAULT_NS_PODS_LOG_FILE="/var/log/pods-default-ns.log"
      NODE_PROBLEM_DETECTOR_PODS_LOG_FILE="/var/log/node-problem-detector-pods.log"
      writeLog "kubectl get pods -n default" ${DEFAULT_NS_PODS_LOG_FILE}
      writeLog "kubectl get pods -l=app=node-problem-detector -n default" ${NODE_PROBLEM_DETECTOR_PODS_LOG_FILE}
      printError "No node-problem-detector pods found. Daemon set has been created but no pods have been scheduled yet"
      printError "Check ${NODE_PROBLEM_DETECTOR_PODS_LOG_FILE}, ${DEFAULT_NS_PODS_LOG_FILE}, /var/log/node-problem-detector.yaml, and K8s events in ${K8S_EVENTS_LOG_FILE} on a master node"
      WITH_ERROR="true"
    fi
  else
    # get number of nodes and make sure there's the same number of pods in Running state
    MASTER_NODES=$(kubectl get nodes -l=node-role.kubernetes.io/master="" --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | tee >(wc -l) | tail -1)
    NODES_NUMBER=$(kubectl get nodes --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | tee >(wc -l) | tail -1)
    NODES=`expr $NODES_NUMBER - $MASTER_NODES`
    END=`expr $NODES - 1`
    for ((i=0;i<=END;i++)); do
      NODENAME=$(kubectl get pods -l=app=node-problem-detector -n default -o jsonpath="{.items[$i].spec.nodeName}" 2> /dev/null)
      if [ $? -ne 0 ]; then
        printWarning "Failed to get node name because of array index out of bounds"
        break
      fi
      PODNAME=$(kubectl get pods -l=app=node-problem-detector -n default -o jsonpath="{.items[$i].metadata.name}" 2> /dev/null)
      STATUS=$(kubectl get pods -l=app=node-problem-detector -n default -o jsonpath="{.items[$i].status.phase}" 2> /dev/null)
      printInfo "Checking node-problem-detector pod status on Node $NODENAME"
      if [ "$STATUS" != "Running" ]; then
        printError "Failed node-problem-detector pod ${PODNAME} on $NODENAME with status $STATUS"
        writeLog "kubectl logs ${PODNAME} -n default" "/var/log/${PODNAME}.log"
        printError "Check logs in /var/log/${PODNAME}.log"
        WITH_ERROR="true"
      else
        printInfo "Node-problem-detector pod ${PODNAME} on $NODENAME successfully started"
        NODE_PROBLEM_DETECTOR_STATUS="OK"
      fi
    done
 fi
}

printEvents() {
  printInfo "Saving events to ${K8S_EVENTS_LOG_FILE}"
  writeLog "kubectl get events --all-namespaces" ${K8S_EVENTS_LOG_FILE}
}

generateReport() {

  if [ "${REMOTE_API}" != "true" ] || [ "${MONITORING}" != "true" ] || [ "${STORAGE}" != "true" ]; then
    CURRENT_STATUS="Not Enabled"
  else
    MONITORING_STATUS=${MONITORING_STATUS:-"FAIL"}
    REMOTEAPI_STATUS=${REMOTEAPI_STATUS:-"FAIL"}
    NFS_STORAGE_STATUS=${NFS_STORAGE_STATUS:-"FAIL"}
  fi
  echo -e "
Cluster Health Check Report

[Weave CNI Plugin]      : ${WEAVE_STATUS:-"FAIL"}
[Ingres Controller]     : ${INGRESS_STATUS:-"FAIL"}
[Metrics Server]        : ${METRICS_STATUS:-"FAIL"}
[Kubernetes Dashboard]  : ${DASHBOARD_STATUS:-"FAIL"}
[Node Problem Detector] : ${NODE_PROBLEM_DETECTOR_STATUS:-"FAIL"}
[Monitoring Tools]      : ${MONITORING_STATUS:-${CURRENT_STATUS}}
[Remote API]            : ${REMOTEAPI_STATUS:-${CURRENT_STATUS}}
[NFS Storage]           : ${NFS_STORAGE_STATUS:-${CURRENT_STATUS}}
[Sample App]            : ${APP_STATUS:-"FAIL"}
  "

}

runCheck() {
  checkWeaveStatus
  checkIngressController
  checkMetricsServer
  if [ "${REMOTE_API}" == "true" ]; then
    checkRemoteApi
  fi
  checkDashboard
  if [ "${MONITORING}" == "true" ]; then
    checkMonitoring
  fi
  if [ "${STORAGE}" == "true" ]; then
    checkNfsStorage
  fi
  checkNodeProblemDetector
  checkSampleApp
  printEvents
  generateReport
}
runCheck
if [ "${WITH_ERROR}" == "true" ] || [ "${MONIT_ERROR}" == "true" ]; then
  printWarning "Waiting for 60 seconds and retrying"
  unset WITH_ERROR
  unset MONIT_ERROR
  sleep 60
  runCheck
  if [ "${WITH_ERROR}" == "true" ] || [ "${MONIT_ERROR}" == "true" ]; then
    exit 1
  fi
fi
