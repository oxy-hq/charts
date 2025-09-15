#!/bin/bash

# Cleanup utility for Helm chart tests
# Removes all test resources and verifies complete cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# List of all possible test instances
TEST_INSTANCES=(
    "test-default"
    "test-ingress"
    "test-postgres"
    "test-production"
    "test-persist"
    "test-gitsync"
    "test-all-features"
    "test-security"
    "test-extdb"
    "test-network"
    "test-failure"
    "test-probe-fail"
    "test-rollback"
    "upgrade-test"
    "resource-test"
)

# List of test secrets to clean up
TEST_SECRETS=(
    "oxy-test-tls"
    "oxy-api-tls"
    "oxy-main-tls"
    "oxy-git-ssh"
    "oxy-env-secrets"
    "oxy-db-secrets"
    "external-db-credentials"
    "warehouse-credentials"
    "oxy-certs"
)

cleanup_helm_releases() {
    log_section "Cleaning up Helm releases"

    local cleaned_releases=()
    local failed_releases=()

    for instance in "${TEST_INSTANCES[@]}"; do
        if helm list -q | grep -q "^$instance$"; then
            log_info "Uninstalling Helm release: $instance"
            if helm uninstall "$instance" --wait --timeout=5m; then
                cleaned_releases+=("$instance")
            else
                log_warning "Failed to cleanly uninstall $instance, will force cleanup"
                failed_releases+=("$instance")
            fi
        fi
    done

    if [[ ${#cleaned_releases[@]} -gt 0 ]]; then
        log_success "Successfully cleaned up releases: ${cleaned_releases[*]}"
    fi

    if [[ ${#failed_releases[@]} -gt 0 ]]; then
        log_warning "Failed to clean up releases: ${failed_releases[*]}"
        return 1
    fi

    log_success "All Helm releases cleaned up"
}

force_cleanup_resources() {
    log_section "Force cleaning up remaining Kubernetes resources"

    local resource_types=("pods" "statefulsets" "deployments" "services" "pvc" "ingress" "configmaps")
    local cleaned_any=false

    for instance in "${TEST_INSTANCES[@]}"; do
        log_info "Force cleaning resources for instance: $instance"

        for resource_type in "${resource_types[@]}"; do
            local resources
            resources=$(kubectl get "$resource_type" -l "app.kubernetes.io/instance=$instance" -o name 2>/dev/null || true)

            if [[ -n "$resources" ]]; then
                log_info "Deleting $resource_type for $instance"
                kubectl delete "$resource_type" -l "app.kubernetes.io/instance=$instance" --ignore-not-found=true --timeout=60s
                cleaned_any=true
            fi
        done
    done

    if [[ "$cleaned_any" == "true" ]]; then
        log_success "Force cleanup completed"
    else
        log_info "No resources found to force cleanup"
    fi
}

cleanup_test_secrets() {
    log_section "Cleaning up test secrets"

    local cleaned_secrets=()

    for secret in "${TEST_SECRETS[@]}"; do
        if kubectl get secret "$secret" >/dev/null 2>&1; then
            log_info "Deleting secret: $secret"
            kubectl delete secret "$secret" --ignore-not-found=true
            cleaned_secrets+=("$secret")
        fi
    done

    if [[ ${#cleaned_secrets[@]} -gt 0 ]]; then
        log_success "Cleaned up secrets: ${cleaned_secrets[*]}"
    else
        log_info "No test secrets found to clean up"
    fi
}

cleanup_persistent_volumes() {
    log_section "Cleaning up persistent volumes and claims"

    # Clean up PVCs that might be stuck
    local pvcs
    pvcs=$(kubectl get pvc -o name 2>/dev/null | grep -E "test-|oxy-test" || true)

    if [[ -n "$pvcs" ]]; then
        log_info "Found test PVCs to clean up"
        echo "$pvcs" | xargs -r kubectl delete --ignore-not-found=true --timeout=60s
        log_success "Persistent volume claims cleaned up"
    else
        log_info "No test PVCs found"
    fi

    # Clean up orphaned PVs if any
    local pvs
    pvs=$(kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.name | test("test-|oxy-test")) | .metadata.name' 2>/dev/null || true)

    if [[ -n "$pvs" ]]; then
        log_info "Found orphaned test PVs to clean up"
        echo "$pvs" | xargs -r kubectl delete pv --ignore-not-found=true
        log_success "Orphaned persistent volumes cleaned up"
    else
        log_info "No orphaned test PVs found"
    fi
}

cleanup_namespaced_resources() {
    log_section "Cleaning up other namespaced resources"

    # Clean up any remaining test-related resources
    local resource_types=("serviceaccounts" "roles" "rolebindings" "networkpolicies")

    for resource_type in "${resource_types[@]}"; do
        local resources
        resources=$(kubectl get "$resource_type" -o name 2>/dev/null | grep -E "test-|oxy-test" || true)

        if [[ -n "$resources" ]]; then
            log_info "Cleaning up $resource_type"
            echo "$resources" | xargs -r kubectl delete --ignore-not-found=true
        fi
    done

    log_success "Namespaced resources cleanup completed"
}

verify_cleanup() {
    log_section "Verifying complete cleanup"

    local cleanup_failed=false

    # Check for remaining test resources
    for instance in "${TEST_INSTANCES[@]}"; do
        # Check for pods
        if kubectl get pods -l "app.kubernetes.io/instance=$instance" 2>/dev/null | grep -q "$instance"; then
            log_error "Found remaining pods for instance: $instance"
            kubectl get pods -l "app.kubernetes.io/instance=$instance"
            cleanup_failed=true
        fi

        # Check for PVCs
        if kubectl get pvc -l "app.kubernetes.io/instance=$instance" 2>/dev/null | grep -q "$instance"; then
            log_error "Found remaining PVCs for instance: $instance"
            kubectl get pvc -l "app.kubernetes.io/instance=$instance"
            cleanup_failed=true
        fi

        # Check for ingress
        if kubectl get ingress -l "app.kubernetes.io/instance=$instance" 2>/dev/null | grep -q "$instance"; then
            log_error "Found remaining ingress for instance: $instance"
            kubectl get ingress -l "app.kubernetes.io/instance=$instance"
            cleanup_failed=true
        fi
    done

    # Check for remaining Helm releases
    local remaining_releases
    remaining_releases=$(helm list -q | grep -E "^($(IFS="|"; echo "${TEST_INSTANCES[*]}"))\$" || true)

    if [[ -n "$remaining_releases" ]]; then
        log_error "Found remaining Helm releases: $remaining_releases"
        cleanup_failed=true
    fi

    # Check for remaining test secrets
    for secret in "${TEST_SECRETS[@]}"; do
        if kubectl get secret "$secret" >/dev/null 2>&1; then
            log_error "Found remaining test secret: $secret"
            cleanup_failed=true
        fi
    done

    if [[ "$cleanup_failed" == "true" ]]; then
        log_error "Cleanup verification failed - some resources were not properly cleaned up"
        return 1
    fi

    log_success "Cleanup verification passed - all test resources removed"
}

cleanup_docker_images() {
    if command -v docker >/dev/null 2>&1; then
        log_section "Cleaning up Docker images (if applicable)"

        # Clean up any test-related images
        local test_images
        test_images=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "test-|oxy-test" || true)

        if [[ -n "$test_images" ]]; then
            log_info "Found test-related Docker images to clean up"
            echo "$test_images" | tail -n +2 | xargs -r docker rmi --force
            log_success "Docker images cleaned up"
        else
            log_info "No test-related Docker images found"
        fi
    fi
}

main() {
    local force_cleanup=false
    local verify_only=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_cleanup=true
                shift
                ;;
            -v|--verify-only)
                verify_only=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [OPTIONS]

Cleanup utility for Helm chart tests

OPTIONS:
    -f, --force         Force cleanup of stuck resources
    -v, --verify-only   Only verify cleanup, don't perform cleanup
    -h, --help          Show this help

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_section "Helm Chart Test Cleanup Utility"

    if [[ "$verify_only" == "true" ]]; then
        verify_cleanup
        exit $?
    fi

    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed"
        exit 1
    fi

    if ! command -v helm >/dev/null 2>&1; then
        log_error "Helm is not installed"
        exit 1
    fi

    # Perform cleanup
    local cleanup_steps=(
        "cleanup_helm_releases"
        "cleanup_test_secrets"
        "cleanup_persistent_volumes"
        "cleanup_namespaced_resources"
    )

    if [[ "$force_cleanup" == "true" ]]; then
        cleanup_steps+=("force_cleanup_resources")
    fi

    cleanup_steps+=("cleanup_docker_images")

    for step in "${cleanup_steps[@]}"; do
        if ! $step; then
            log_warning "Cleanup step '$step' had issues, continuing..."
        fi
    done

    # Verify cleanup
    verify_cleanup

    log_success "Cleanup completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi