#!/bin/bash
set -e

# Integration Test Script for Oxy-App Helm Chart
#
# Runs the chart against a real Kubernetes cluster (kind in CI). Rewritten
# for speed: the suite used to run six releases SERIALLY in one namespace,
# each spinning up its OWN postgres StatefulSet + PVC, then tearing it down
# with `helm uninstall --wait`. On a flaky-storage runner every test ate a
# ~5min teardown tail and the whole suite hit 36min.
#
# This version:
#   - Starts ONE shared postgres (Deployment + Service, emptyDir, no PVC)
#     and gives each test its OWN database on it — so tests never spin up
#     their own postgres and never race on migrations.
#   - Runs each test in its OWN namespace, in a bounded PARALLEL pool.
#   - Never blocks on graceful teardown: the kind cluster is ephemeral, so
#     cleanup just deletes namespaces with --wait=false.
#   - Uses tight, explicit timeouts everywhere so storage flakiness fails
#     fast instead of burning the 5min helm default.

CHART_PATH="./charts/oxy-app"
INFRA_NS="helm-it-infra"           # holds the shared postgres
NS_PREFIX="helm-it"                # per-test namespaces: helm-it-<name>

# Shared postgres connection (one server, one DB per test).
PG_RELEASE_SVC="shared-postgres"
PG_USER="oxy"
PG_PASSWORD="oxypass"
PG_HOST="${PG_RELEASE_SVC}.${INFRA_NS}.svc.cluster.local"
PG_PORT=5432

# How many tests to run concurrently. Kept modest so a single kind node
# (and its storage provisioner) is not overwhelmed by parallel PVC binds.
MAX_PARALLEL="${MAX_PARALLEL:-3}"

# Tests to run. Each name maps to: a test-values file, a per-test database,
# and a test_<name> function. The dedicated "postgres" test was dropped —
# every test now exercises postgres, so it was pure duplication.
TESTS=(default ingress production persist upgrade)

# Namespaces we create (infra + one per test) — for cleanup.
ALL_NAMESPACES=("$INFRA_NS")
for t in "${TESTS[@]}"; do ALL_NAMESPACES+=("${NS_PREFIX}-${t}"); done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

# Dump every signal that diagnoses a failed helm install / pod-not-ready in
# a namespace. Called by the parallel runner when a test subshell exits
# non-zero, so the CI log shows describe + events + pod logs next to the
# failure instead of a bare "context deadline exceeded".
dump_failure_diagnostics() {
    local ns="$1"
    log_warn "Dumping cluster diagnostics for namespace '$ns'..."
    echo "--- pods ---"
    kubectl get pods -n "$ns" -o wide || true
    echo "--- pvcs ---"
    kubectl get pvc -n "$ns" || true
    echo "--- events (last 30, by lastTimestamp) ---"
    kubectl get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
    echo "--- describe pods ---"
    kubectl describe pods -n "$ns" 2>/dev/null | sed -n '1,300p' || true
    echo "--- logs (current container) ---"
    kubectl logs -n "$ns" --all-containers=true --tail=200 --prefix=true \
        -l app.kubernetes.io/name=oxy-app 2>/dev/null || true
    echo "--- logs (previous container, if any) ---"
    kubectl logs -n "$ns" --all-containers=true --tail=200 --previous --prefix=true \
        -l app.kubernetes.io/name=oxy-app 2>/dev/null || true
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Integration test runner for oxy-app Helm chart

OPTIONS:
    --verbose           Enable verbose output (set -x)
    --cleanup           Delete test namespaces after completion
    -h, --help          Show this help

ENVIRONMENT VARIABLES:
    NAMESPACE           Ignored (kept for back-compat; namespaces are derived)
    MAX_PARALLEL        Max concurrent tests (default: 3)
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=()
    command -v helm    &>/dev/null || missing+=("helm")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
    if ! kubectl cluster-info &>/dev/null; then
        log_error "No Kubernetes cluster available."
        exit 1
    fi
    log_info "Prerequisites check passed!"
}

# Per-test helm install flags that point the app at its dedicated database
# on the shared postgres and disable the bundled postgres subchart (which
# also strips the wait-for-postgres init container, since the server is
# already up before any test starts).
shared_db_args() {
    local db="$1"
    local url="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${db}"
    echo "--set database.postgres.enabled=false --set-string env.OXY_DATABASE_URL=${url}"
}

setup_shared_infra() {
    log_section "Setting up shared infrastructure"

    # Build chart dependencies from Chart.lock (subcharts are condition-gated
    # off at install time, but the packaged .tgz must exist to template).
    log_info "Adding Helm repositories + building dependencies..."
    helm repo add groundhog2k https://groundhog2k.github.io/helm-charts/ 2>/dev/null || true
    helm repo update >/dev/null
    helm dependency build "$CHART_PATH" >/dev/null

    log_info "Creating namespaces..."
    for ns in "${ALL_NAMESPACES[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    done

    log_info "Deploying shared postgres (emptyDir, no PVC)..."
    kubectl apply -n "$INFRA_NS" -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $PG_RELEASE_SVC
  labels: { app: shared-postgres }
spec:
  replicas: 1
  selector: { matchLabels: { app: shared-postgres } }
  template:
    metadata:
      labels: { app: shared-postgres }
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - { name: POSTGRES_USER, value: "$PG_USER" }
            - { name: POSTGRES_PASSWORD, value: "$PG_PASSWORD" }
            - { name: POSTGRES_DB, value: "postgres" }
            - { name: PGDATA, value: "/var/lib/postgresql/data/pgdata" }
          ports: [{ containerPort: 5432 }]
          readinessProbe:
            exec: { command: ["pg_isready", "-U", "$PG_USER"] }
            initialDelaySeconds: 3
            periodSeconds: 3
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 500m, memory: 512Mi }
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
      volumes:
        - { name: data, emptyDir: {} }
---
apiVersion: v1
kind: Service
metadata:
  name: $PG_RELEASE_SVC
spec:
  selector: { app: shared-postgres }
  ports: [{ port: 5432, targetPort: 5432 }]
EOF

    log_info "Waiting for shared postgres to be ready..."
    kubectl rollout status deploy/"$PG_RELEASE_SVC" -n "$INFRA_NS" --timeout=120s

    # One empty database per test — isolates migrations so parallel tests
    # never collide on a shared schema.
    log_info "Creating per-test databases..."
    local pg_pod
    pg_pod=$(kubectl get pod -n "$INFRA_NS" -l app=shared-postgres -o jsonpath='{.items[0].metadata.name}')
    for t in "${TESTS[@]}"; do
        kubectl exec -n "$INFRA_NS" "$pg_pod" -- \
            psql -U "$PG_USER" -d postgres -c "CREATE DATABASE db_${t} OWNER ${PG_USER};" >/dev/null 2>&1 || true
    done

    log_info "Shared infrastructure ready!"
}

# ── Individual tests ─────────────────────────────────────────────────────
# Each runs in its own namespace ${NS_PREFIX}-<name> against database db_<name>.
# No per-test teardown: namespaces are dropped wholesale at the end.

test_default() {
    local ns="${NS_PREFIX}-default"
    log_info "[default] installing..."
    # shellcheck disable=SC2046
    helm install test-default "$CHART_PATH" \
        -f "$CHART_PATH/test-values/default-values.yaml" \
        $(shared_db_args db_default) \
        -n "$ns" --wait --timeout=180s

    log_info "[default] checking service connectivity..."
    kubectl port-forward service/oxy-test-default 18080:80 -n "$ns" >/dev/null 2>&1 &
    local pf=$!
    local ok=1
    for _ in {1..30}; do
        if curl -fs http://localhost:18080/ >/dev/null 2>&1; then ok=0; break; fi
        sleep 0.5
    done
    kill $pf 2>/dev/null || true
    [[ $ok -eq 0 ]] || { log_error "[default] health check failed"; return 1; }
    log_info "[default] passed!"
}

test_ingress() {
    local ns="${NS_PREFIX}-ingress"
    log_info "[ingress] installing..."
    # shellcheck disable=SC2046
    helm install test-ingress "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-ingress-values.yaml" \
        $(shared_db_args db_ingress) \
        -n "$ns" --wait --timeout=180s

    if kubectl get ingress oxy-test-ingress -n "$ns" -o jsonpath='{.spec.rules[0].host}' | grep -q "test-oxy-app.local"; then
        log_info "[ingress] passed!"
    else
        log_error "[ingress] ingress host not as expected"; return 1
    fi
}

test_production() {
    local ns="${NS_PREFIX}-production"
    log_info "[production] installing (persistence + ingress + SA + PDB)..."
    # shellcheck disable=SC2046
    helm install test-production "$CHART_PATH" \
        -f "$CHART_PATH/test-values/production-like-values.yaml" \
        $(shared_db_args db_production) \
        -n "$ns" --wait --timeout=180s

    # PVC binds during install --wait; verify it ended up Bound.
    local pvc_status
    pvc_status=$(kubectl get pvc -l app.kubernetes.io/instance=test-production -n "$ns" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    [[ "$pvc_status" == "Bound" ]] || { log_error "[production] PVC not bound (status: ${pvc_status:-none})"; return 1; }

    if ! kubectl get serviceaccount test-production-sa -n "$ns" -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' | grep -q "true"; then
        log_error "[production] service account annotation missing"; return 1
    fi
    if ! kubectl get ingress test-production -n "$ns" -o jsonpath='{.spec.rules[0].host}' | grep -q "test-production.local"; then
        log_error "[production] ingress host not as expected"; return 1
    fi
    log_info "[production] passed!"
}

test_persist() {
    local ns="${NS_PREFIX}-persist"
    log_info "[persist] installing..."
    # shellcheck disable=SC2046
    helm install test-persist "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-persistence-values.yaml" \
        $(shared_db_args db_persist) \
        -n "$ns" --wait --timeout=180s

    # Must be a StatefulSet with a Bound PVC.
    kubectl get statefulset oxy-test-persist -n "$ns" >/dev/null 2>&1 \
        || { log_error "[persist] StatefulSet missing"; return 1; }
    local pvc_status
    pvc_status=$(kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$ns" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    [[ "$pvc_status" == "Bound" ]] || { log_error "[persist] PVC not bound (status: ${pvc_status:-none})"; return 1; }

    # Data survives a write/read round-trip on the mounted volume.
    kubectl exec -n "$ns" oxy-test-persist-0 -- sh -c 'echo "test-data" > /workspace/test.txt'
    if kubectl exec -n "$ns" oxy-test-persist-0 -- sh -c 'cat /workspace/test.txt' | grep -q "test-data"; then
        log_info "[persist] passed!"
    else
        log_error "[persist] data persistence check failed"; return 1
    fi
}

test_upgrade() {
    local ns="${NS_PREFIX}-upgrade"
    local db_args
    db_args="$(shared_db_args db_upgrade)"
    log_info "[upgrade] install -> upgrade -> rollback..."

    # shellcheck disable=SC2086
    helm install upgrade-test "$CHART_PATH" \
        -f "$CHART_PATH/test-values/default-values.yaml" \
        $db_args -n "$ns" --wait --timeout=180s

    # shellcheck disable=SC2086
    helm upgrade upgrade-test "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-ingress-values.yaml" \
        $db_args -n "$ns" --wait --timeout=180s

    kubectl get ingress -l app.kubernetes.io/instance=upgrade-test -n "$ns" >/dev/null 2>&1 \
        || { log_error "[upgrade] ingress not created on upgrade"; return 1; }

    helm rollback upgrade-test 1 -n "$ns" --wait --timeout=180s

    # Rollback to the ingress-less revision should remove the ingress object.
    if kubectl get ingress oxy-test-ingress -n "$ns" >/dev/null 2>&1; then
        log_error "[upgrade] ingress should be removed after rollback"; return 1
    fi
    log_info "[upgrade] passed!"
}

# Run a single named test in its own log file; on failure, append namespace
# diagnostics to that log so the parallel output stays self-contained.
run_one() {
    local name="$1"
    local ns="${NS_PREFIX}-${name}"
    local logf="$2"
    {
        if "test_${name}"; then
            echo "__RESULT__ ${name} PASS"
        else
            echo "__RESULT__ ${name} FAIL"
            dump_failure_diagnostics "$ns"
        fi
    } >"$logf" 2>&1
}

run_integration_tests() {
    log_section "Running Integration Tests (parallel, max ${MAX_PARALLEL})"
    setup_shared_infra

    local tmpdir
    tmpdir="$(mktemp -d)"
    local pids=() names=() logs=()
    local running=0

    for name in "${TESTS[@]}"; do
        # Throttle to MAX_PARALLEL concurrent jobs.
        while [[ "$running" -ge "$MAX_PARALLEL" ]]; do
            wait -n 2>/dev/null || true
            running=$((running - 1))
        done
        local logf="${tmpdir}/${name}.log"
        run_one "$name" "$logf" &
        pids+=($!); names+=("$name"); logs+=("$logf")
        running=$((running + 1))
        log_info "launched: $name"
    done

    # Wait for the remainder.
    wait

    # Collect + replay results in deterministic order.
    local failed=()
    for i in "${!names[@]}"; do
        echo ""
        log_section "Output: ${names[$i]}"
        cat "${logs[$i]}" || true
        if grep -q "__RESULT__ ${names[$i]} PASS" "${logs[$i]}" 2>/dev/null; then
            :
        else
            failed+=("${names[$i]}")
        fi
    done

    rm -rf "$tmpdir" 2>/dev/null || true

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_error "Failed tests: ${failed[*]}"
        return 1
    fi
    log_info "All integration tests passed! 🎉"
}

cleanup() {
    log_info "Cleaning up test namespaces (no --wait; cluster is ephemeral)..."
    for ns in "${ALL_NAMESPACES[@]}"; do
        kubectl delete namespace "$ns" --ignore-not-found=true --wait=false 2>/dev/null || true
    done
}

main() {
    local cleanup_after=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup) cleanup_after=true; shift ;;
            --verbose) set -x; shift ;;
            help|--help|-h) show_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; show_usage; exit 1 ;;
        esac
    done

    [[ "$cleanup_after" == "true" ]] && trap cleanup EXIT

    log_section "Oxy-App Helm Chart Integration Testing"
    log_info "Cleanup after: $cleanup_after | Max parallel: $MAX_PARALLEL"

    check_prerequisites
    run_integration_tests

    log_info "🎉 Integration tests completed successfully!"
}

main "$@"
