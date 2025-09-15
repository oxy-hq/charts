#!/bin/bash

# Advanced feature tests for oxy-app Helm chart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

CHART_PATH="${CHART_PATH:-./charts/oxy-app}"
VALUES_DIR="${VALUES_DIR:-$CHART_PATH/test-values}"

test_postgres_deployment() {
    log_section "Testing deployment with PostgreSQL"

    local release_name="test-postgres"
    local values_file="$VALUES_DIR/with-postgres-values.yaml"

    # Update dependencies
    log_info "Updating Helm dependencies"
    helm dependency update "$CHART_PATH"

    # Install chart with longer timeout for PostgreSQL
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for both app and PostgreSQL
    wait_for_deployment "$release_name" 600s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=300s

    # Test database connectivity
    log_info "Testing PostgreSQL connectivity"
    local postgres_pod
    postgres_pod=$(kubectl get pod -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -it "$postgres_pod" -- pg_isready -U testuser -d testdb

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "PostgreSQL deployment test completed"
}

test_gitsync_deployment() {
    log_section "Testing deployment with git sync"

    local release_name="test-gitsync"
    local values_file="$VALUES_DIR/with-gitsync-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for StatefulSet
    wait_for_statefulset "oxy-test-gitsync" 1

    # Verify git sync sidecar exists
    log_info "Verifying git sync sidecar container"
    kubectl get pod oxy-test-gitsync-0 -o jsonpath='{.spec.containers[*].name}' | grep -q "git-sync"

    # Wait for git sync to clone (give it some time)
    log_info "Waiting for git sync to complete initial clone"
    sleep 30

    # Check if git repository content exists
    log_info "Checking if git repository was cloned"
    if kubectl exec -it oxy-test-gitsync-0 -c oxy-app -- ls -la /workspace/ | grep -q "README.md"; then
        log_success "Git sync successfully cloned repository"
    else
        log_warning "Git sync may still be in progress or repository is empty"
    fi

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "Git sync deployment test completed"
}

test_production_like_deployment() {
    log_section "Testing production-like deployment"

    local release_name="test-production"
    local values_file="$VALUES_DIR/production-like-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for deployment
    wait_for_deployment "$release_name" 600s

    # Verify service account annotations
    log_info "Verifying service account configuration"
    verify_resource "serviceaccount" "oxy-test-sa" '{.metadata.annotations.prometheus\.io/scrape}' "true"

    # Verify PVC is created and bound
    log_info "Verifying persistent volume claim"
    kubectl get pvc -l "app.kubernetes.io/instance=$release_name"
    kubectl wait --for=condition=bound pvc -l "app.kubernetes.io/instance=$release_name" --timeout=300s

    # Verify ingress configuration
    log_info "Verifying ingress configuration"
    kubectl get ingress -l "app.kubernetes.io/instance=$release_name"
    verify_resource "ingress" "oxy-test-prod" '{.spec.rules[0].host}' "oxy-test-prod.local"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "Production-like deployment test completed"
}

test_security_hardened_deployment() {
    log_section "Testing security hardened deployment"

    local release_name="test-security"
    local values_file="$VALUES_DIR/security-hardened-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for deployment
    wait_for_deployment "$release_name" 600s

    # Verify security context
    log_info "Verifying security context configuration"
    local pod_name
    pod_name=$(kubectl get pod -l "app.kubernetes.io/instance=$release_name" -o jsonpath='{.items[0].metadata.name}')

    verify_resource "pod" "$pod_name" '{.spec.securityContext.fsGroup}' "2000"
    verify_resource "pod" "$pod_name" '{.spec.securityContext.runAsNonRoot}' "true"
    verify_resource "pod" "$pod_name" '{.spec.securityContext.runAsUser}' "2000"

    # Verify resource limits
    log_info "Verifying resource limits"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].resources.limits.cpu}' "100m"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].resources.limits.memory}' "128Mi"

    # Verify probe configuration
    log_info "Verifying probe configuration"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].livenessProbe.failureThreshold}' "3"
    verify_resource "pod" "$pod_name" '{.spec.containers[0].readinessProbe.failureThreshold}' "3"

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "Security hardened deployment test completed"
}

test_external_database_deployment() {
    log_section "Testing external database deployment"

    local release_name="test-extdb"
    local values_file="$VALUES_DIR/external-db-values.yaml"

    # Install chart
    helm_install_with_retry "$release_name" "$CHART_PATH" "$values_file" "10m"

    # Wait for deployment
    wait_for_deployment "$release_name" 600s

    # Verify external database environment variables
    log_info "Verifying external database configuration"
    local pod_name
    pod_name=$(kubectl get pod -l "app.kubernetes.io/instance=$release_name" -o jsonpath='{.items[0].metadata.name}')

    # Check for external database URL
    kubectl get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="OXY_DATABASE_URL")].value}' | grep -q "external-postgres"
    kubectl get pod "$pod_name" -o jsonpath='{.spec.containers[0].env[?(@.name=="EXTERNAL_DB_MODE")].value}' | grep -q "true"

    # Verify no internal PostgreSQL is deployed
    log_info "Verifying no internal PostgreSQL was deployed"
    if kubectl get statefulset -l app.kubernetes.io/name=postgresql 2>/dev/null | grep -q postgresql; then
        log_error "Internal PostgreSQL found when using external database"
        return 1
    fi

    # Cleanup
    helm_uninstall_with_cleanup "$release_name" "10m"

    log_success "External database deployment test completed"
}

# Main execution
main() {
    log_section "Starting advanced feature tests"

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
    test_postgres_deployment
    test_gitsync_deployment
    test_production_like_deployment
    test_security_hardened_deployment
    test_external_database_deployment

    log_success "All advanced tests completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi