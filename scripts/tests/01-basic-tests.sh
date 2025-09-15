#!/bin/bash

# Basic deployment tests for oxy-app Helm chart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

CHART_PATH="${CHART_PATH:-./charts/oxy-app}"
VALUES_DIR="${VALUES_DIR:-$CHART_PATH/test-values}"

test_default_deployment() {
    log_section "Testing default deployment"

    local release_name="test-default"
    local values_file="$VALUES_DIR/default-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file"

    # Wait for deployment
    wait_for_deployment "$release_name"

    # Test service connectivity
    test_service_connectivity "oxy-test-default" 8080 80

    # Cleanup
    helm_uninstall_with_cleanup "$release_name"

    log_success "Default deployment test completed"
}

test_ingress_deployment() {
    log_section "Testing deployment with ingress"

    local release_name="test-ingress"
    local values_file="$VALUES_DIR/with-ingress-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file"

    # Wait for deployment
    wait_for_deployment "$release_name"

    # Verify ingress exists and has correct host
    verify_resource "ingress" "oxy-test-ingress" '{.spec.rules[0].host}' "test-oxy-app.local"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name"

    log_success "Ingress deployment test completed"
}

test_persistence_deployment() {
    log_section "Testing deployment with persistence"

    local release_name="test-persist"
    local values_file="$VALUES_DIR/with-persistence-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for StatefulSet (default timeout should handle PVC creation)
    wait_for_statefulset "oxy-test-persist" 1

    # Verify StatefulSet exists
    if ! resource_exists "statefulset" "oxy-test-persist"; then
        log_error "StatefulSet not found"
        return 1
    fi

    # Verify PVC exists
    if ! kubectl get pvc -l "app.kubernetes.io/instance=$release_name" | grep -q "$release_name"; then
        log_error "PVC not found for persistent deployment"
        return 1
    fi

    # Test data persistence
    log_info "Testing data persistence"
    kubectl exec -it oxy-test-persist-0 -- sh -c 'echo "test-data" > /workspace/test.txt'
    kubectl exec -it oxy-test-persist-0 -- sh -c 'cat /workspace/test.txt' | grep -q "test-data"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "Persistence deployment test completed"
}

# Main execution
main() {
    log_section "Starting basic deployment tests"

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
    test_default_deployment
    test_ingress_deployment
    test_persistence_deployment

    log_success "All basic tests completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi