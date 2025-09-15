#!/bin/bash

# Common utilities for Helm chart testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠ [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Check if running in CI or local
is_ci() {
    [[ "${CI:-false}" == "true" ]]
}

# Wait for deployment to be ready
wait_for_deployment() {
    local instance_name="$1"
    local timeout="${2:-300s}"

    log_info "Waiting for deployment $instance_name to be ready (timeout: $timeout)"
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/instance=$instance_name" --timeout="$timeout"
}

# Wait for statefulset to be ready
wait_for_statefulset() {
    local statefulset_name="$1"
    local expected_replicas="${2:-1}"
    local timeout="${3:-600}"

    log_info "Waiting for StatefulSet $statefulset_name to have $expected_replicas ready replicas"

    local count=0
    while [[ $count -lt $timeout ]]; do
        local ready=$(kubectl get statefulset "$statefulset_name" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [[ "$ready" == "$expected_replicas" ]]; then
            log_success "StatefulSet $statefulset_name is ready with $ready replicas"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done

    log_error "Timeout waiting for StatefulSet $statefulset_name"
    return 1
}

# Test service connectivity with port forwarding
test_service_connectivity() {
    local service_name="$1"
    local local_port="${2:-8080}"
    local service_port="${3:-80}"
    local test_path="${4:-/}"
    local expected_content="${5:-}"

    log_info "Testing connectivity to service $service_name"

    # Start port forwarding in background
    kubectl port-forward "service/$service_name" "$local_port:$service_port" &
    local pf_pid=$!

    # Cleanup function
    cleanup_port_forward() {
        if kill -0 $pf_pid 2>/dev/null; then
            kill $pf_pid
            wait $pf_pid 2>/dev/null || true
        fi
    }

    # Set trap to cleanup on exit
    trap cleanup_port_forward EXIT

    # Wait for port forward to be ready
    sleep 5

    # Test connectivity
    local url="http://localhost:$local_port$test_path"
    if [[ -n "$expected_content" ]]; then
        if curl -f "$url" | grep -q "$expected_content"; then
            log_success "Service connectivity test passed"
            cleanup_port_forward
            return 0
        else
            log_error "Service connectivity test failed - content mismatch"
            cleanup_port_forward
            return 1
        fi
    else
        if curl -f "$url" >/dev/null 2>&1; then
            log_success "Service connectivity test passed"
            cleanup_port_forward
            return 0
        else
            log_error "Service connectivity test failed"
            cleanup_port_forward
            return 1
        fi
    fi
}

# Install helm chart with retry
helm_install_with_retry() {
    local release_name="$1"
    local chart_path="$2"
    local values_file="$3"
    local timeout="${4:-5m}"
    local retries="${5:-3}"

    log_info "Installing Helm chart: $release_name with values: $values_file"

    for ((i=1; i<=retries; i++)); do
        if helm install "$release_name" "$chart_path" -f "$values_file" --wait --timeout="$timeout"; then
            log_success "Helm install succeeded on attempt $i"
            return 0
        else
            log_warning "Helm install failed on attempt $i/$retries"
            if [[ $i -lt $retries ]]; then
                log_info "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done

    log_error "Helm install failed after $retries attempts"
    return 1
}

# Uninstall helm chart with cleanup
helm_uninstall_with_cleanup() {
    local release_name="$1"
    local timeout="${2:-5m}"

    log_info "Uninstalling Helm release: $release_name"

    if helm list -q | grep -q "^$release_name$"; then
        helm uninstall "$release_name" --wait --timeout="$timeout" || {
            log_warning "Helm uninstall had issues, forcing cleanup..."
            # Force delete any remaining resources
            kubectl delete pods,pvc,ingress -l "app.kubernetes.io/instance=$release_name" --ignore-not-found=true
        }
        log_success "Helm release $release_name uninstalled"
    else
        log_info "Helm release $release_name not found, skipping uninstall"
    fi
}

# Verify resource exists and has expected properties
verify_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local jsonpath="$3"
    local expected_value="$4"

    log_info "Verifying $resource_type/$resource_name has $jsonpath=$expected_value"

    local actual_value
    actual_value=$(kubectl get "$resource_type" "$resource_name" -o jsonpath="$jsonpath" 2>/dev/null || echo "")

    if [[ "$actual_value" == "$expected_value" ]]; then
        log_success "Verification passed: $resource_type/$resource_name.$jsonpath = $expected_value"
        return 0
    else
        log_error "Verification failed: expected '$expected_value', got '$actual_value'"
        return 1
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"

    kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
}

# Create test secrets for integration tests
create_test_secrets() {
    log_info "Creating test secrets for integration tests"

    # TLS secrets for ingress testing
    kubectl create secret tls oxy-test-tls --cert=/dev/null --key=/dev/null --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret tls oxy-api-tls --cert=/dev/null --key=/dev/null --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret tls oxy-main-tls --cert=/dev/null --key=/dev/null --dry-run=client -o yaml | kubectl apply -f -

    # SSH secret for git sync testing
    kubectl create secret generic oxy-git-ssh \
        --from-literal=ssh-privatekey="$(echo -e '-----BEGIN OPENSSH PRIVATE KEY-----\nfake-key-for-testing\n-----END OPENSSH PRIVATE KEY-----')" \
        --from-literal=ssh-publickey="ssh-rsa fake-public-key-for-testing" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Environment secrets
    kubectl create secret generic oxy-env-secrets \
        --from-literal=DATABASE_PASSWORD="test-password" \
        --from-literal=API_KEY="test-api-key" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic oxy-db-secrets \
        --from-literal=CONNECTION_STRING="postgresql://test:test@localhost:5432/test" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic external-db-credentials \
        --from-literal=DATABASE_URL="postgresql://external:test@localhost:5432/external" \
        --from-literal=DATABASE_PASSWORD="external-password" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic warehouse-credentials \
        --from-literal=bigquery-key.json='{"type":"service_account","project_id":"test"}' \
        --from-literal=BIGQUERY_CREDENTIALS="test-credentials" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic oxy-certs \
        --from-literal=tls.crt="-----BEGIN CERTIFICATE-----\nfake-cert\n-----END CERTIFICATE-----" \
        --from-literal=tls.key="-----BEGIN PRIVATE KEY-----\nfake-key\n-----END PRIVATE KEY-----" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "Test secrets created successfully"
}

# Setup test environment (secrets, ingress controller, etc.)
setup_test_environment() {
    log_section "Setting up test environment"

    # Create test secrets
    create_test_secrets

    # Install NGINX Ingress Controller if not in CI (CI handles this separately)
    if ! is_ci; then
        log_info "Installing NGINX Ingress Controller for local testing"
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
        kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=90s
    fi

    log_success "Test environment setup completed"
}

# Update test values to use correct storage class for kind
update_test_values_for_kind() {
    log_info "Updating test values to use correct storage class for kind"

    local values_dir="${CHART_PATH}/test-values"
    local storage_class="standard"  # kind's default storage class

    # Find all values files that might use persistence
    local values_files=(
        "$values_dir/with-persistence-values.yaml"
        "$values_dir/production-like-values.yaml"
        "$values_dir/all-features-values.yaml"
        "$values_dir/advanced-networking-values.yaml"
        "$values_dir/with-gitsync-values.yaml"
        "$values_dir/failure-simulation-values.yaml"
    )

    for values_file in "${values_files[@]}"; do
        if [[ -f "$values_file" ]]; then
            log_info "Updating storage class in $(basename "$values_file")"

            # Update storageClassName if it exists
            if grep -q "storageClassName:" "$values_file"; then
                sed -i.bak "s/storageClassName: .*/storageClassName: $storage_class/" "$values_file"
                rm -f "${values_file}.bak"
            fi
        fi
    done

    log_success "Test values updated for kind environment"
}