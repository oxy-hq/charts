#!/bin/bash
set -e

# Integration Test Script for Oxy-App Helm Chart
# Runs comprehensive integration tests against a Kubernetes cluster

CHART_PATH="./charts/oxy-app"
NAMESPACE="helm-integration-test"

# List of test release names used by cleanup routines. Keep in sync with test_* functions.
TEST_RELEASES=(
    "test-default"
    "test-ingress"
    "test-postgres"
    "test-production"
    "test-persist"
    "upgrade-test"
    "resource-test"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Integration test runner for oxy-app Helm chart

OPTIONS:
    --verbose           Enable verbose output
    --cleanup           Clean up test resources after completion

EXAMPLES:
    $0                  # Run integration tests
    $0 --cleanup        # Run integration tests and cleanup afterwards
    $0 --verbose        # Run with verbose output

ENVIRONMENT VARIABLES:
    CI                  Set to 'true' to skip local cluster setup
    NAMESPACE           Test namespace (default: helm-integration-test)

EOF
}

cleanup() {
    log_info "Cleaning up test resources..."

    # List of test releases to clean up (maintained in TEST_RELEASES)
    for release in "${TEST_RELEASES[@]}"; do
        if helm list -q -n "$NAMESPACE" 2>/dev/null | grep -q "^${release}$"; then
            log_info "Uninstalling release: $release"
            helm uninstall "$release" -n "$NAMESPACE" --wait --timeout=300s || true
        fi
    done

    # Aggressive PVC cleanup - delete any PVCs that might be stuck
    log_info "Cleaning up any remaining PVCs..."
    kubectl get pvc -n "$NAMESPACE" -o name 2>/dev/null | while read pvc; do
        if [ -n "$pvc" ]; then
            log_info "Force deleting PVC: $pvc"
            kubectl delete "$pvc" -n "$NAMESPACE" --force --grace-period=0 || true
        fi
    done

    # Clean up any stuck pods that might be holding PVCs
    log_info "Cleaning up any stuck pods..."
    kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | while read pod; do
        if [ -n "$pod" ]; then
            log_info "Force deleting pod: $pod"
            kubectl delete "$pod" -n "$NAMESPACE" --force --grace-period=0 || true
        fi
    done

    # Delete namespace if it exists (this should clean up everything)
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --wait=true --timeout=60s || true
    fi

    # Wait a moment for cleanup to complete
    sleep 2
}

aggressive_pre_cleanup() {
    log_info "Performing aggressive pre-test cleanup..."

    # If namespace exists, check for any existing resources
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Found existing test namespace, cleaning up..."

        # List what we're about to clean
        log_info "Existing resources in namespace:"
        kubectl get all,pvc,secrets,configmaps -n "$NAMESPACE" || true

        # Force cleanup everything
        cleanup

        # Recreate clean namespace
        log_info "Recreating clean namespace..."
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --wait=true --timeout=60s || true
        sleep 3
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    # Check if kubectl is installed (required for integration tests)
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi

    log_info "Prerequisites check passed!"
}

debug_kind_storage() {
    log_info "Debugging Kind cluster storage configuration..."

    # Check if this is a Kind cluster
    cluster_name=$(kubectl config current-context 2>/dev/null || echo "unknown")
    if [[ "$cluster_name" == *"kind"* ]]; then
        log_info "Detected Kind cluster: $cluster_name"

        # Check available storage classes
        log_info "Available StorageClasses:"
        kubectl get storageclass -o wide || true

        # Check if standard StorageClass exists (Kind default)
        if kubectl get storageclass standard >/dev/null 2>&1; then
            log_info "Standard StorageClass found:"
            kubectl describe storageclass standard || true
        else
            log_warn "Standard StorageClass not found"
        fi

        # Check for default StorageClass
        default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
        if [ -n "$default_sc" ]; then
            log_info "Default StorageClass: $default_sc"
        else
            log_warn "No default StorageClass configured"

            # Try to set standard as default if it exists
            if kubectl get storageclass standard >/dev/null 2>&1; then
                log_info "Setting 'standard' StorageClass as default for Kind cluster"
                kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || log_warn "Failed to set default StorageClass"
            fi
        fi

        # Check Kind node storage capacity
        log_info "Node storage information:"
        kubectl get nodes -o custom-columns=NAME:.metadata.name,CAPACITY:.status.capacity.storage,ALLOCATABLE:.status.allocatable.storage || true

        # Check if local-path-storage is running (Kind's default provisioner)
        log_info "Checking local-path-storage components:"
        kubectl get pods -n local-path-storage 2>/dev/null || log_warn "local-path-storage namespace not found"
        kubectl get pods -A | grep -E "(local-path|storage)" || log_warn "No storage-related pods found"

    else
        log_info "Not a Kind cluster (context: $cluster_name), skipping Kind-specific storage checks"
    fi
}

setup_test_environment() {
    log_info "Setting up test environment..."

    # Aggressive cleanup of any existing resources first
    aggressive_pre_cleanup

    # Create fresh namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Debug storage configuration
    debug_kind_storage

    # Update helm dependencies
    log_info "Updating Helm dependencies..."
    helm dependency update "$CHART_PATH"

    log_info "Test environment setup complete!"
}


test_simple_pvc() {
    log_info "Testing simple PVC creation before StatefulSet..."

    # Create a simple test PVC to verify storage provisioning works
    cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-simple
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF

    # Wait for PVC to be bound
    log_info "Waiting for test PVC to be bound..."
    if kubectl wait --for=condition=bound pvc test-pvc-simple -n "$NAMESPACE" --timeout=60s; then
        log_info "Simple PVC test passed - storage provisioning works"
        kubectl describe pvc test-pvc-simple -n "$NAMESPACE" || true
    else
        log_error "Simple PVC test failed - storage provisioning issues detected"
        kubectl describe pvc test-pvc-simple -n "$NAMESPACE" || true
        kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name=test-pvc-simple || true
    fi

    # Cleanup test PVC
    kubectl delete pvc test-pvc-simple -n "$NAMESPACE" || true
}

test_default_deployment() {
    log_info "Testing default deployment..."
    local test_start=$SECONDS

    helm install test-default "$CHART_PATH" \
        -f "$CHART_PATH/test-values/default-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m

    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=test-default \
        -n "$NAMESPACE" \
        --timeout=90s

    # Test service connectivity
    log_info "Testing service connectivity..."
    kubectl port-forward service/oxy-test-default 8080:80 -n "$NAMESPACE" &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to be ready (max 15s)
    for i in {1..30}; do
        if curl -fs http://localhost:8080/ >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    if curl -f http://localhost:8080/ >/dev/null 2>&1; then
        log_info "Default deployment health check passed!"
    else
        log_error "Default deployment health check failed!"
        kill $PORT_FORWARD_PID || true
        return 1
    fi

    kill $PORT_FORWARD_PID || true

    # Cleanup this test
    helm uninstall test-default -n "$NAMESPACE" --wait

    local test_duration=$((SECONDS - test_start))
    log_info "Default deployment test passed in ${test_duration}s!"
}

test_ingress_deployment() {
    log_info "Testing deployment with ingress..."

    helm install test-ingress "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-ingress-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m

    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=test-ingress \
        -n "$NAMESPACE" \
        --timeout=90s

    # Verify ingress is created
    if kubectl get ingress oxy-test-ingress -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' | grep -q "test-oxy-app.local"; then
        log_info "Ingress configuration verified!"
    else
        log_error "Ingress configuration failed!"
        return 1
    fi

    # Cleanup this test
    helm uninstall test-ingress -n "$NAMESPACE" --wait

    log_info "Ingress deployment test passed!"
}

test_postgres_deployment() {
    log_info "Testing deployment with PostgreSQL..."

    helm install test-postgres "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-postgres-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=5m

    # Wait for all pods to be ready (app + postgres)
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=test-postgres \
        -n "$NAMESPACE" \
        --timeout=210s

    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=postgresql \
        -n "$NAMESPACE" \
        --timeout=120s

    # Test database connectivity
    log_info "Testing database connectivity..."
    postgres_pod=$(kubectl get pod -l app.kubernetes.io/name=postgresql -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec -n "$NAMESPACE" "$postgres_pod" -- pg_isready -U testuser -d testdb >/dev/null 2>&1; then
        log_info "PostgreSQL connectivity test passed!"
    else
        log_error "PostgreSQL connectivity test failed!"
        return 1
    fi

    # Cleanup this test
    helm uninstall test-postgres -n "$NAMESPACE" --wait

    log_info "PostgreSQL deployment test passed!"
}

test_persistence_deployment() {
    log_info "Testing deployment with persistence..."

    # Run simple PVC test first
    test_simple_pvc

    # Debug: Check available StorageClasses before installation
    log_info "Available StorageClasses in cluster:"
    kubectl get storageclass -o wide || true

    # Debug: Check if default StorageClass exists
    default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
    if [ -n "$default_sc" ]; then
        log_info "Default StorageClass found: $default_sc"
    else
        log_warn "No default StorageClass found"
    fi

    # Install with enhanced debugging
    log_info "Installing Helm chart: test-persist with values: ./charts/oxy-app/test-values/with-persistence-values.yaml"
    if helm install test-persist "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-persistence-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m; then
        log_info "Helm install succeeded"
    else
        log_error "Helm install failed"
        # Debug: Show all resources created
        kubectl get all -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" || true
        kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" || true
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        return 1
    fi

    # Debug: Check StatefulSet status immediately after install
    log_info "StatefulSet status after install:"
    kubectl get statefulset oxy-test-persist -n "$NAMESPACE" -o wide || true
    kubectl describe statefulset oxy-test-persist -n "$NAMESPACE" || true

    # Debug: Check PVC status
    log_info "PVC status after install:"
    kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o wide || true

    # If PVC exists, describe it for more details
    pvc_name=$(kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$pvc_name" ]; then
        log_info "Describing PVC: $pvc_name"
        kubectl describe pvc "$pvc_name" -n "$NAMESPACE" || true
    else
        log_error "No PVC found for test-persist"
    fi

    # Debug: Check pod status
    log_info "Pod status after install:"
    kubectl get pods -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o wide || true

    # If pod exists, describe it
    pod_name=$(kubectl get pods -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$pod_name" ]; then
        log_info "Describing pod: $pod_name"
        kubectl describe pod "$pod_name" -n "$NAMESPACE" || true

        # Show pod logs if available
        log_info "Pod logs for: $pod_name"
        kubectl logs "$pod_name" -n "$NAMESPACE" --tail=50 || true
    fi

    # Debug: Show recent events
    log_info "Recent events in namespace:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' --field-selector reason!=Pulled,reason!=Created,reason!=Started | tail -10 || true

    # Check StatefulSet pod status before waiting
    log_info "Checking StatefulSet pod status..."
    kubectl get statefulset oxy-test-persist -n "$NAMESPACE" -o wide || true
    kubectl get pods -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o wide || true

    # Check if pod is stuck in Pending due to PVC issues
    pod_name="oxy-test-persist-0"
    if kubectl get pod "$pod_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        pod_phase=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        log_info "StatefulSet pod $pod_name is in phase: $pod_phase"

        if [ "$pod_phase" = "Pending" ]; then
            log_info "Pod is Pending, checking for scheduling issues:"
            kubectl describe pod "$pod_name" -n "$NAMESPACE" || true
            kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp' || true
        fi
    fi

    # Wait for StatefulSet to be ready (PVC should bind during pod startup)
    log_info "Waiting for StatefulSet pod to become ready (PVC should bind automatically)..."
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=test-persist \
        -n "$NAMESPACE" \
        --timeout=180s; then
        log_info "StatefulSet pod is ready!"

        # Verify PVC bound after pod is ready
        log_info "Verifying PVC status after pod is ready:"
        kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o wide || true

        pvc_status=$(kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$pvc_status" != "Bound" ]; then
            log_error "PVC is not bound even though pod is ready. PVC status: $pvc_status"
            kubectl describe pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" || true
            return 1
        fi
    else
        log_error "Timeout waiting for StatefulSet oxy-test-persist"

        # Enhanced debugging on timeout
        log_info "Final StatefulSet status:"
        kubectl get statefulset oxy-test-persist -n "$NAMESPACE" -o yaml || true

        log_info "Final pod status:"
        kubectl get pods -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o yaml || true

        log_info "Final PVC status:"
        kubectl get pvc -l app.kubernetes.io/instance=test-persist -n "$NAMESPACE" -o yaml || true

        log_info "All events in namespace (last 20):"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true

        return 1
    fi

    # Verify StatefulSet is used
    if kubectl get statefulset oxy-test-persist -n "$NAMESPACE" >/dev/null 2>&1; then
        log_info "StatefulSet created successfully!"
    else
        log_error "StatefulSet creation failed!"
        return 1
    fi

    # Test data persistence
    log_info "Testing data persistence..."
    kubectl exec -n "$NAMESPACE" oxy-test-persist-0 -- sh -c 'echo "test-data" > /workspace/test.txt'
    if kubectl exec -n "$NAMESPACE" oxy-test-persist-0 -- sh -c 'cat /workspace/test.txt' | grep -q "test-data"; then
        log_info "Data persistence test passed!"
    else
        log_error "Data persistence test failed!"
        return 1
    fi

    # Cleanup this test
    helm uninstall test-persist -n "$NAMESPACE" --wait

    log_info "Persistence deployment test passed!"
}

test_production_like_deployment() {
    log_info "Testing production-like deployment..."

    helm install test-production "$CHART_PATH" \
        -f "$CHART_PATH/test-values/production-like-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m

    # Debug: Check pod and PVC status immediately after install
    log_info "Checking pod and PVC status after install..."
    kubectl get pods -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o wide || true
    kubectl get pvc -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o wide || true

    # Check if pod is stuck and why
    pod_name=$(kubectl get pods -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$pod_name" ]; then
        pod_phase=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        log_info "Pod $pod_name is in phase: $pod_phase"

        if [ "$pod_phase" != "Running" ]; then
            log_info "Pod not running, describing it:"
            kubectl describe pod "$pod_name" -n "$NAMESPACE" || true

            log_info "Recent events for pod:"
            kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp' || true
        fi
    fi

    # Wait for pods to be ready (PVC should bind during this process)
    log_info "Waiting for pod to become ready (this should trigger PVC binding)..."
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=test-production \
        -n "$NAMESPACE" \
        --timeout=180s; then
        log_info "Pod is ready!"

        # Check PVC status after pod is ready
        log_info "Checking PVC status after pod is ready:"
        kubectl get pvc -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o wide || true

        # If PVC is still not bound, there's a problem
        pvc_status=$(kubectl get pvc -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$pvc_status" != "Bound" ]; then
            log_error "PVC is not bound even though pod is ready. PVC status: $pvc_status"
            kubectl describe pvc -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" || true
            return 1
        fi
    else
        log_error "Pod failed to become ready"
        # Enhanced debugging for failed pod
        kubectl get pods -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o yaml || true
        kubectl get pvc -l app.kubernetes.io/instance=test-production -n "$NAMESPACE" -o yaml || true
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
        return 1
    fi

    # Verify service account and annotations
    if kubectl get serviceaccount test-production-sa -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.prometheus\.io/scrape}' | grep -q "true"; then
        log_info "Service account annotations verified!"
    else
        log_error "Service account annotations verification failed!"
        return 1
    fi

    # Verify ingress configuration
    if kubectl get ingress test-production -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' | grep -q "test-production.local"; then
        log_info "Ingress configuration verified!"
    else
        log_error "Ingress configuration failed!"
        return 1
    fi

    # Cleanup this test
    helm uninstall test-production -n "$NAMESPACE" --wait

    log_info "Production-like deployment test passed!"
}

test_upgrade_scenarios() {
    log_info "Testing helm upgrade scenarios..."

    # Install with default values
    helm install upgrade-test "$CHART_PATH" \
        -f "$CHART_PATH/test-values/default-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m

    # Upgrade with ingress enabled
    helm upgrade upgrade-test "$CHART_PATH" \
        -f "$CHART_PATH/test-values/with-ingress-values.yaml" \
        -n "$NAMESPACE" \
        --wait --timeout=3m

    # Verify upgrade worked
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=upgrade-test \
        -n "$NAMESPACE" \
        --timeout=90s

    kubectl get ingress -l app.kubernetes.io/instance=upgrade-test -n "$NAMESPACE"

    # Test rollback
    log_info "Testing rollback..."
    helm rollback upgrade-test 1 -n "$NAMESPACE" --wait
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=upgrade-test \
        -n "$NAMESPACE" \
        --timeout=90s

    # Verify ingress is removed after rollback
    if kubectl get ingress oxy-test-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Ingress should be removed after rollback!"
        return 1
    fi

    # Cleanup this test
    helm uninstall upgrade-test -n "$NAMESPACE" --wait

    log_info "Upgrade/rollback test passed!"
}

run_integration_tests() {
    log_section "Running Integration Tests"

    # Check if kubectl is available and we have a cluster
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Integration tests require kubectl."
        return 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "No Kubernetes cluster available. Please ensure you have access to a cluster."
        return 1
    fi

    setup_test_environment

    # Run all integration tests
    test_default_deployment
    test_ingress_deployment
    test_postgres_deployment
    test_production_like_deployment
    test_persistence_deployment
    test_upgrade_scenarios

    local elapsed=$SECONDS
    log_info "All integration tests passed successfully in ${elapsed}s! 🎉"
}

main() {
    local cleanup_after=false
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                cleanup_after=true
                shift
                ;;
            --verbose)
                verbose=true
                set -x
                shift
                ;;
            help|--help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set cleanup trap if requested
    if [[ "$cleanup_after" == "true" ]]; then
        trap cleanup EXIT
    fi

    # Quietly reference verbose to satisfy linters if unused later
    if [[ "$verbose" == "true" ]]; then :; fi

    log_section "Oxy-App Helm Chart Integration Testing"
    log_info "Cleanup after: $cleanup_after"

    check_prerequisites

    run_integration_tests

    log_info "🎉 Integration tests completed successfully!"
}

# Run main function with all arguments
main "$@"