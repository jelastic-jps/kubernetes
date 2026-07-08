#!/usr/bin/env bash
set -Eeuo pipefail

# Rancher addon constants. Change these values to select another supported version.
RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
RANCHER_IMAGE_TAG="${RANCHER_IMAGE_TAG:-v${RANCHER_VERSION#v}}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.2}"
RANCHER_CHART_REPO_NAME="${RANCHER_CHART_REPO_NAME:-rancher-latest}"
RANCHER_CHART_REPO_URL="${RANCHER_CHART_REPO_URL:-https://releases.rancher.com/server-charts/latest}"
RANCHER_NAMESPACE="${RANCHER_NAMESPACE:-cattle-system}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
CA_BUNDLE_SOURCE="${CA_BUNDLE_SOURCE:-/etc/pki/tls/certs/ca-bundle.crt}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30m}"
RANCHER_STABLE_SECONDS="${RANCHER_STABLE_SECONDS:-180}"
RANCHER_PREPULL="${RANCHER_PREPULL:-true}"
RANCHER_PUBLIC_HTTPS_CHECK="${RANCHER_PUBLIC_HTTPS_CHECK:-true}"
RANCHER_REQUIRE_PUBLIC_HTTPS="${RANCHER_REQUIRE_PUBLIC_HTTPS:-false}"

TMP_FILES=()

cleanup() {
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    rm -f "${TMP_FILES[@]}" 2>/dev/null || true
  fi
  if [[ "${RANCHER_PREPULL}" == "true" ]]; then
    kubectl -n "$RANCHER_NAMESPACE" delete daemonset rancher-image-prepull \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "${RANCHER_HOSTNAME:-}" ]]; then
  echo "ERROR: RANCHER_HOSTNAME is required" >&2
  exit 2
fi

if [[ -z "${BOOTSTRAP_PASSWORD:-}" ]]; then
  if kubectl -n "$RANCHER_NAMESPACE" get secret bootstrap-secret >/dev/null 2>&1; then
    BOOTSTRAP_PASSWORD="$(
      kubectl -n "$RANCHER_NAMESPACE" get secret bootstrap-secret \
        -o jsonpath='{.data.bootstrapPassword}' | base64 -d
    )"
    echo "Reusing existing Rancher bootstrap password. It will not be printed."
  elif [[ -t 0 ]]; then
    read -r -s -p "Rancher bootstrap password: " BOOTSTRAP_PASSWORD
    echo
  fi
fi

if [[ -z "${BOOTSTRAP_PASSWORD:-}" ]]; then
  BOOTSTRAP_PASSWORD="$(openssl rand -hex 16)"
  echo "Generated Rancher bootstrap password. It will not be printed."
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 2
  }
}

log() {
  printf '\n== %s ==\n' "$*"
}

yaml_quote() {
  local value="$1"
  value=${value//\'/\'\'}
  printf "'%s'" "$value"
}

duration_seconds() {
  local value="$1"

  case "$value" in
    *h) echo $((${value%h} * 3600)) ;;
    *m) echo $((${value%m} * 60)) ;;
    *s) echo "${value%s}" ;;
    *) echo "$value" ;;
  esac
}

write_rancher_values_file() {
  local values_file
  values_file="$(mktemp)"
  TMP_FILES+=("$values_file")

  cat >"$values_file" <<EOF
hostname: $(yaml_quote "$RANCHER_HOSTNAME")
bootstrapPassword: $(yaml_quote "$BOOTSTRAP_PASSWORD")
replicas: 1
ingress:
  ingressClassName: $(yaml_quote "$INGRESS_CLASS_NAME")
  tls:
    source: rancher
tls: ingress
additionalTrustedCAs: true
useBundledSystemChart: true
startupProbe:
  failureThreshold: 180
  periodSeconds: 10
  timeoutSeconds: 5
livenessProbe:
  failureThreshold: 30
  periodSeconds: 30
  timeoutSeconds: 5
readinessProbe:
  failureThreshold: 30
  periodSeconds: 30
  timeoutSeconds: 5
extraEnv:
- name: CURL_CA_BUNDLE
  value: /etc/rancher/ssl/ca-additional.pem
- name: SSL_CERT_FILE
  value: /etc/rancher/ssl/ca-additional.pem
EOF

  RANCHER_VALUES_FILE="$values_file"
}

write_rancher_post_renderer() {
  local post_renderer
  post_renderer="$(mktemp)"
  TMP_FILES+=("$post_renderer")

  cat >"$post_renderer" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

workdir=\$(mktemp -d)
trap 'rm -rf "\$workdir"' EXIT

cat >"\$workdir/all.yaml"
cat >"\$workdir/kustomization.yaml" <<'KUSTOMIZE'
resources:
- all.yaml
patchesStrategicMerge:
- rancher-workarounds.yaml
KUSTOMIZE

cat >"\$workdir/rancher-workarounds.yaml" <<'PATCH'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rancher
spec:
  progressDeadlineSeconds: 3600
  template:
    spec:
      initContainers:
      - name: rancher-jailer-patch
        image: rancher/rancher:${RANCHER_IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        command:
        - /bin/sh
        - -ec
        args:
        - |
          sed -e 's/cp -r -l /cp -r /g' -e 's/cp -l /cp /g' /usr/bin/jailer.sh > /patched/jailer.sh
          chmod 0755 /patched/jailer.sh
          echo "patched /usr/bin/jailer.sh created"
          grep -nE 'cp[[:space:]]+(-r[[:space:]]+)?-?l|cp[[:space:]]+-r|cp[[:space:]]+' /patched/jailer.sh | head -40 || true
        volumeMounts:
        - name: rancher-jailer-script
          mountPath: /patched
      containers:
      - name: rancher
        env:
        - name: CATTLE_SYSTEM_CATALOG
          value: bundled
        - name: CURL_CA_BUNDLE
          value: /etc/rancher/ssl/ca-additional.pem
        - name: SSL_CERT_FILE
          value: /etc/rancher/ssl/ca-additional.pem
        volumeMounts:
        - name: rancher-jailer-script
          mountPath: /usr/bin/jailer.sh
          subPath: jailer.sh
          readOnly: true
        - name: rancher-jail
          mountPath: /opt/jail
        - name: tls-ca-additional-volume
          mountPath: /etc/rancher/ssl/ca-additional.pem
          subPath: ca-additional.pem
          readOnly: true
        - name: tls-ca-additional-volume
          mountPath: /etc/pki/trust/anchors/ca-additional.pem
          subPath: ca-additional.pem
          readOnly: true
      volumes:
      - name: rancher-jailer-script
        emptyDir: {}
      - name: rancher-jail
        emptyDir:
          medium: Memory
          sizeLimit: 1Gi
      - name: tls-ca-additional-volume
        secret:
          secretName: tls-ca-additional
          optional: false
PATCH

kubectl kustomize "\$workdir"
EOF

  chmod 0700 "$post_renderer"
  RANCHER_POST_RENDERER="$post_renderer"
}

start_rancher_image_prepull() {
  if [[ "${RANCHER_PREPULL}" != "true" ]]; then
    return 0
  fi

  log "Pre-pull Rancher image on schedulable nodes"
  kubectl -n "$RANCHER_NAMESPACE" apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: rancher-image-prepull
  labels:
    app: rancher-image-prepull
spec:
  selector:
    matchLabels:
      app: rancher-image-prepull
  template:
    metadata:
      labels:
        app: rancher-image-prepull
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: prepull
        image: rancher/rancher:${RANCHER_IMAGE_TAG}
        imagePullPolicy: IfNotPresent
        command:
        - /bin/sh
        - -ec
        - sleep 1800
EOF
}

refresh_tls_ca_secret() {
  local ca_data get_error get_rc patch_file

  get_error="$(mktemp)"
  patch_file="$(mktemp)"
  TMP_FILES+=("$get_error" "$patch_file")

  if kubectl -n "$RANCHER_NAMESPACE" get secret tls-ca-additional >/dev/null 2>"$get_error"; then
    ca_data="$(base64 "$CA_BUNDLE_SOURCE" | tr -d '\n')"
    cat >"$patch_file" <<EOF
{"data":{"ca-additional.pem":"$ca_data"}}
EOF
    if kubectl patch --help 2>/dev/null | grep -q -- '--patch-file'; then
      kubectl -n "$RANCHER_NAMESPACE" patch secret tls-ca-additional \
        --type=merge \
        --patch-file "$patch_file"
    else
      kubectl -n "$RANCHER_NAMESPACE" patch secret tls-ca-additional \
        --type=merge \
        -p "$(cat "$patch_file")"
    fi
  else
    get_rc=$?
    if grep -Eqi 'notfound|not found' "$get_error"; then
      kubectl -n "$RANCHER_NAMESPACE" create secret generic tls-ca-additional \
        --from-file=ca-additional.pem="$CA_BUNDLE_SOURCE"
    else
      cat "$get_error" >&2
      return "$get_rc"
    fi
  fi
}

wait_rancher_stable() {
  local stable_seconds="$RANCHER_STABLE_SECONDS"
  local deadline_seconds
  local interval=15
  local stable=0
  local last_restarts=""
  local pod_line pod_name pod_phase pod_ready pod_restarts
  local started_at

  deadline_seconds="$(duration_seconds "$WAIT_TIMEOUT")"
  started_at="$(date +%s)"

  log "Wait for Rancher to remain Ready for ${stable_seconds}s"
  while (( stable < stable_seconds )); do
    if (( $(date +%s) - started_at >= deadline_seconds )); then
      echo "ERROR: Rancher did not remain Ready for ${stable_seconds}s before timeout ${WAIT_TIMEOUT}" >&2
      kubectl -n "$RANCHER_NAMESPACE" get deploy,rs,pods,svc,ingress -l app=rancher -o wide >&2 || true
      kubectl -n "$RANCHER_NAMESPACE" logs -l app=rancher --all-containers --tail=250 --prefix >&2 || true
      return 1
    fi

    pod_line="$(
      kubectl -n "$RANCHER_NAMESPACE" get pods -l app=rancher \
        -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.status.containerStatuses[?(@.name=="rancher")].ready}{" "}{.status.containerStatuses[?(@.name=="rancher")].restartCount}{"\n"}{end}' \
        | head -1
    )"
    read -r pod_name pod_phase pod_ready pod_restarts _ <<<"${pod_line:-none none none none}"
    pod_name="${pod_name:-none}"
    pod_phase="${pod_phase:-none}"
    pod_ready="${pod_ready:-none}"
    pod_restarts="${pod_restarts:-none}"

    if [[ "$pod_phase" == "Running" && "$pod_ready" == "true" ]]; then
      if [[ "$pod_restarts" == "$last_restarts" ]]; then
        stable=$((stable + interval))
      else
        stable=0
        last_restarts="$pod_restarts"
      fi
      printf 'Rancher ready: pod=%s restarts=%s stable=%ss/%ss\n' \
        "$pod_name" "$pod_restarts" "$stable" "$stable_seconds"
    else
      stable=0
      last_restarts="$pod_restarts"
      printf 'Rancher not stable yet: pod=%s phase=%s ready=%s restarts=%s\n' \
        "$pod_name" "$pod_phase" "$pod_ready" "$pod_restarts"
    fi

    sleep "$interval"
  done
}

wait_https_ok() {
  local code

  if [[ "$RANCHER_PUBLIC_HTTPS_CHECK" != "true" ]]; then
    log "Skip Rancher public HTTPS endpoint check"
    return 0
  fi

  log "Wait for Rancher HTTPS endpoint"
  for _ in $(seq 1 80); do
    code="$(curl -kIs -o /dev/null -w '%{http_code}' --max-time 15 "https://${RANCHER_HOSTNAME}" 2>/dev/null || true)"
    if [[ "$code" =~ ^(200|30[1278])$ ]]; then
      curl -kIs --max-time 15 "https://${RANCHER_HOSTNAME}" | sed -n '1,12p'
      return 0
    fi
    echo "HTTPS not ready yet: HTTP ${code:-curl_failed}"
    sleep 15
  done

  if [[ "$RANCHER_REQUIRE_PUBLIC_HTTPS" == "true" ]]; then
    echo "ERROR: Rancher HTTPS endpoint did not return HTTP 200/3xx" >&2
    return 1
  fi

  echo "WARNING: Rancher public HTTPS endpoint did not return HTTP 200/3xx from this node; continuing because deployment, ingress, and certificate checks passed." >&2
  return 0
}

require_cmd kubectl
require_cmd helm
require_cmd openssl
require_cmd curl
kubectl kustomize --help >/dev/null 2>&1 || {
  echo "ERROR: kubectl kustomize is required for Helm post-rendering" >&2
  exit 2
}

if [[ ! -r "$CA_BUNDLE_SOURCE" ]]; then
  echo "ERROR: CA bundle is not readable: $CA_BUNDLE_SOURCE" >&2
  exit 2
fi

log "Helm repositories"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add "$RANCHER_CHART_REPO_NAME" "$RANCHER_CHART_REPO_URL" --force-update >/dev/null
helm repo update >/dev/null

log "Namespaces"
kubectl create namespace "$CERT_MANAGER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$RANCHER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

log "Install or update cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace "$CERT_MANAGER_NAMESPACE" \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true \
  --wait \
  --timeout "$WAIT_TIMEOUT"

kubectl -n "$CERT_MANAGER_NAMESPACE" rollout status deploy/cert-manager --timeout="$WAIT_TIMEOUT"
kubectl -n "$CERT_MANAGER_NAMESPACE" rollout status deploy/cert-manager-webhook --timeout="$WAIT_TIMEOUT"
kubectl -n "$CERT_MANAGER_NAMESPACE" rollout status deploy/cert-manager-cainjector --timeout="$WAIT_TIMEOUT"

start_rancher_image_prepull

log "Additional CA secret for Rancher"
refresh_tls_ca_secret

log "Install or update Rancher Helm release"
write_rancher_values_file
write_rancher_post_renderer

if [[ "${RANCHER_PREPULL}" == "true" ]]; then
  kubectl -n "$RANCHER_NAMESPACE" rollout status daemonset/rancher-image-prepull --timeout="$WAIT_TIMEOUT" || true
fi

helm upgrade --install rancher "$RANCHER_CHART_REPO_NAME/rancher" \
  --namespace "$RANCHER_NAMESPACE" \
  --version "$RANCHER_VERSION" \
  -f "$RANCHER_VALUES_FILE" \
  --post-renderer "$RANCHER_POST_RENDERER" \
  --wait=false \
  --timeout "$WAIT_TIMEOUT"

log "Stop stale Rancher ReplicaSets without the jailer patch"
while read -r rs; do
  [[ -n "$rs" ]] || continue
  init_names="$(kubectl -n "$RANCHER_NAMESPACE" get "$rs" -o jsonpath='{.spec.template.spec.initContainers[*].name}' 2>/dev/null || true)"
  init_image="$(kubectl -n "$RANCHER_NAMESPACE" get "$rs" -o jsonpath='{.spec.template.spec.initContainers[?(@.name=="rancher-jailer-patch")].image}' 2>/dev/null || true)"
  if [[ "$init_names" != *rancher-jailer-patch* || "$init_image" != "rancher/rancher:${RANCHER_IMAGE_TAG}" ]]; then
    echo "Scaling stale or incorrectly patched $rs to 0"
    kubectl -n "$RANCHER_NAMESPACE" scale "$rs" --replicas=0
  else
    echo "Keeping patched $rs"
  fi
done < <(kubectl -n "$RANCHER_NAMESPACE" get rs -l app=rancher -o name)

log "Wait for Rancher"
kubectl -n "$RANCHER_NAMESPACE" rollout status deployment/rancher --timeout="$WAIT_TIMEOUT" || {
  echo "Rancher did not become Ready. Recent status and logs follow." >&2
  kubectl -n "$RANCHER_NAMESPACE" get deploy,rs,pods,svc,ingress -l app=rancher -o wide >&2 || true
  kubectl -n "$RANCHER_NAMESPACE" logs -l app=rancher --all-containers --tail=250 --prefix >&2 || true
  exit 1
}

log "Rancher status"
kubectl -n "$RANCHER_NAMESPACE" get deploy,rs,pods,svc,ingress -l app=rancher -o wide
kubectl -n "$RANCHER_NAMESPACE" get issuer,certificate,certificaterequest 2>/dev/null || true

wait_rancher_stable

log "Wait for Rancher ingress certificate"
kubectl -n "$RANCHER_NAMESPACE" wait --for=condition=Ready issuer/rancher --timeout="$WAIT_TIMEOUT"
kubectl -n "$RANCHER_NAMESPACE" wait --for=condition=Ready certificate/tls-rancher-ingress --timeout="$WAIT_TIMEOUT"

wait_https_ok

log "Final Rancher status"
kubectl -n "$RANCHER_NAMESPACE" get deploy,rs,pods,svc,ingress -l app=rancher -o wide
kubectl -n "$RANCHER_NAMESPACE" get issuer,certificate,certificaterequest 2>/dev/null || true
