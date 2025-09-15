#!/bin/bash

# Comprehensive all-features and complex scenario tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

CHART_PATH="${CHART_PATH:-./charts/oxy-app}"
VALUES_DIR="${VALUES_DIR:-$CHART_PATH/test-values}"

test_all_features_deployment() {
    log_section "Testing ALL FEATURES deployment (maximum complexity)"

    local release_name="test-all-features"
    local values_file="$VALUES_DIR/all-features-values.yaml"

    # Update dependencies
    log_info "Updating Helm dependencies"
    helm dependency update "$CHART_PATH"

    # Install chart with extended timeout
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "15m"

    # Wait for all components
    log_info "Waiting for all components to be ready"
    kubectl get all -l "app.kubernetes.io/instance=$release_name"
    wait_for_deployment "$release_name" 900s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=600s

    # Verify StatefulSet with replicas
    log_info "Verifying StatefulSet configuration"
    wait_for_statefulset "oxy-test-all" 2

    # Verify container configuration
    log_info "Verifying container configuration"
    local container_count
    container_count=$(kubectl get pod oxy-test-all-0 -o jsonpath='{.spec.containers[*].name}' | wc -w)
    if [[ $container_count -lt 4 ]]; then
        log_error "Expected at least 4 containers (main + git-sync + 2 sidecars), found $container_count"
        return 1
    fi

    # Verify init containers
    log_info "Verifying init containers completed successfully"
    local init_status
    init_status=$(kubectl get pod oxy-test-all-0 -o jsonpath='{.status.initContainerStatuses[*].state.terminated.reason}')
    echo "$init_status" | grep -q "Completed"

    # Verify service account annotations
    log_info "Verifying service account annotations"
    kubectl get serviceaccount oxy-test-all-sa -o jsonpath='{.metadata.annotations}' | grep -q "prometheus.io/scrape"
    kubectl get serviceaccount oxy-test-all-sa -o jsonpath='{.metadata.annotations}' | grep -q "eks.amazonaws.com/role-arn"

    # Verify ConfigMap mounts
    log_info "Verifying ConfigMap is mounted and accessible"
    kubectl exec -it oxy-test-all-0 -c oxy-app -- ls -la /etc/config/ | grep -q "app.conf"
    kubectl exec -it oxy-test-all-0 -c oxy-app -- cat /etc/config/custom.json | grep -q "feature_flags"

    # Verify persistence
    log_info "Verifying persistent storage"
    kubectl get pvc -l "app.kubernetes.io/instance=$release_name"
    kubectl exec -it oxy-test-all-0 -c oxy-app -- ls -la /workspace/oxy_data
    kubectl exec -it oxy-test-all-0 -c oxy-app -- echo "all-features-test" > /workspace/oxy_data/test.txt
    kubectl exec -it oxy-test-all-0 -c oxy-app -- cat /workspace/oxy_data/test.txt | grep -q "all-features-test"

    # Verify ingress configuration
    log_info "Verifying multiple ingress hosts and paths"
    kubectl get ingress -l "app.kubernetes.io/instance=$release_name"
    kubectl get ingress oxy-test-all -o jsonpath='{.spec.rules[*].host}' | grep -q "oxy-test-all.local"
    kubectl get ingress oxy-test-all -o jsonpath='{.spec.rules[*].host}' | grep -q "oxy-alt.local"

    # Verify TLS configuration
    log_info "Verifying TLS configuration"
    kubectl get ingress oxy-test-all -o jsonpath='{.spec.tls[*].secretName}' | grep -q "oxy-test-tls"

    # Verify PostgreSQL connectivity
    log_info "Verifying PostgreSQL database connectivity"
    local postgres_pod
    postgres_pod=$(kubectl get pod -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -it "$postgres_pod" -- pg_isready -U oxy_test -d oxydb_test

    # Verify git sync functionality
    log_info "Verifying git sync functionality"
    if kubectl exec -it oxy-test-all-0 -c git-sync -- ls -la /workspace/git | grep -q "Hello-World"; then
        log_success "Git sync working correctly"
    else
        log_warning "Git sync still in progress or repository structure different"
    fi

    # Verify sidecar containers
    log_info "Verifying sidecar containers are running"
    kubectl get pod oxy-test-all-0 -o jsonpath='{.status.containerStatuses[?(@.name=="log-forwarder")].state.running.startedAt}' | grep -q "T"
    kubectl get pod oxy-test-all-0 -o jsonpath='{.status.containerStatuses[?(@.name=="metrics-collector")].state.running.startedAt}' | grep -q "T"

    # Test service connectivity
    log_info "Testing service connectivity"
    test_service_connectivity "oxy-all-service" 8081 80 "/" "All features test OK"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "All features deployment test completed"
}

test_advanced_networking() {
    log_section "Testing advanced networking configuration"

    local release_name="test-network"
    local values_file="$VALUES_DIR/advanced-networking-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for deployment
    wait_for_deployment "$release_name" 600s

    # Verify multiple replicas
    log_info "Verifying multiple replicas for networking"
    wait_for_statefulset "oxy-test-network" 2

    # Verify complex ingress configuration
    log_info "Verifying complex ingress configuration"
    kubectl get ingress oxy-test-network -o jsonpath='{.spec.rules[*].host}' | grep -q "api.oxy-test.local"
    kubectl get ingress oxy-test-network -o jsonpath='{.spec.rules[*].host}' | grep -q "admin.oxy-test.local"
    kubectl get ingress oxy-test-network -o jsonpath='{.spec.rules[*].host}' | grep -q "oxy-test-network.local"

    # Verify TLS for multiple hosts
    log_info "Verifying TLS configuration for multiple hosts"
    kubectl get ingress oxy-test-network -o jsonpath='{.spec.tls[*].secretName}' | grep -q "oxy-api-tls"
    kubectl get ingress oxy-test-network -o jsonpath='{.spec.tls[*].secretName}' | grep -q "oxy-main-tls"

    # Verify ingress annotations
    log_info "Verifying ingress annotations for advanced features"
    kubectl get ingress oxy-test-network -o jsonpath='{.metadata.annotations}' | grep -q "nginx.ingress.kubernetes.io/cors-allow-origin"
    kubectl get ingress oxy-test-network -o jsonpath='{.metadata.annotations}' | grep -q "nginx.ingress.kubernetes.io/proxy-body-size"

    # Verify nginx configuration
    log_info "Verifying ConfigMap with nginx configuration"
    kubectl get configmap -l "app.kubernetes.io/instance=$release_name"
    kubectl exec -it oxy-test-network-0 -- cat /etc/config/nginx.conf | grep -q "upstream backend"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "Advanced networking test completed"
}

test_upgrade_scenarios() {
    log_section "Testing helm upgrade scenarios"

    local release_name="upgrade-test"

    # Install with default values
    log_info "Installing with default values"
    helm_install_with_retry "$release_name" "$CHART_PATH" "$VALUES_DIR/default-values.yaml"

    # Upgrade with ingress enabled
    log_info "Upgrading to enable ingress"
    helm upgrade "$release_name" "$CHART_PATH" -f "$VALUES_DIR/with-ingress-values.yaml" --wait --timeout=5m

    # Verify both app and ingress are working
    wait_for_deployment "$release_name" 300s
    kubectl get ingress -l "app.kubernetes.io/instance=$release_name"

    # Test rollback
    log_info "Testing rollback functionality"
    helm rollback "$release_name" 1 --wait
    wait_for_deployment "$release_name" 300s

    # Verify ingress is removed after rollback
    if kubectl get ingress oxy-test-ingress 2>/dev/null; then
        log_error "Ingress should be removed after rollback"
        return 1
    fi

    # Cleanup
    helm_uninstall_with_cleanup "$release_name"

    log_success "Upgrade/rollback tests completed"
}

test_failure_scenarios() {
    log_section "Testing failure scenarios and resilience"

    local release_name="test-failure"
    local values_file="$VALUES_DIR/failure-simulation-values.yaml"

    # Install with resource constraints
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"
    wait_for_deployment "$release_name" 600s

    # Verify resource constraints
    log_info "Verifying tight resource constraints"
    local pod_name
    pod_name=$(kubectl get pod -l "app.kubernetes.io/instance=$release_name" -o jsonpath='{.items[0].metadata.name}')

    verify_resource "pod" "$pod_name" '{.spec.containers[0].resources.limits.cpu}' "20m"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].resources.limits.memory}' "64Mi"

    # Verify probe settings
    log_info "Verifying aggressive probe settings"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].livenessProbe.failureThreshold}' "2"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].readinessProbe.failureThreshold}' "1"

    # Test init container completion
    log_info "Verifying init containers with delays completed"
    kubectl get pod oxy-test-fail-0 -o jsonpath='{.status.initContainerStatuses[?(@.name=="failure-sim-init")].state.terminated.reason}' | grep -q "Completed"

    # Verify failure marker
    log_info "Verifying failure marker was created by init container"
    kubectl exec -it oxy-test-fail-0 -c oxy-app -- cat /workspace/test-failure/marker | grep -q "failure-test"

    # Test pod restart resilience
    log_info "Testing pod restart resilience"
    kubectl exec -it oxy-test-fail-0 -c oxy-app -- kill 1 || true
    sleep 30
    kubectl wait --for=condition=ready pod oxy-test-fail-0 --timeout=300s

    # Cleanup
    helm_uninstall_with_cleanup "$release_name"

    log_success "Failure scenario tests completed"
}

# Main execution
main() {
    log_section "Starting comprehensive feature tests"

    # Check prerequisites
    if ! command -v helm >/dev/null 2>&1; then
        log_error "Helm is not installed"
        exit 1
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed"
        exit 1
    fi

    # Run tests
    test_all_features_deployment
    test_advanced_networking
    test_upgrade_scenarios
    test_failure_scenarios

    log_success "All comprehensive tests completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi