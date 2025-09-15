#!/bin/bash

# Helm Chart Test Runner
# Runs integration tests locally or in CI environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/common.sh"

# Configuration
CHART_PATH="${CHART_PATH:-./charts/oxy-app}"
VALUES_DIR="${VALUES_DIR:-$CHART_PATH/test-values}"
CLUSTER_NAME="${CLUSTER_NAME:-helm-test-cluster}"
KIND_CONFIG="${KIND_CONFIG:-./kind-config.yaml}"

# Test categories
AVAILABLE_TESTS=(
    "basic"
    "advanced"
    "comprehensive"
    "all"
)

# Default test selection
DEFAULT_TESTS="basic"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Helm Chart Test Runner - Run integration tests for oxy-app chart

OPTIONS:
    -t, --tests TESTS       Tests to run: ${AVAILABLE_TESTS[*]} (default: $DEFAULT_TESTS)
    -s, --setup             Setup test environment (kind cluster, secrets)
    -c, --cleanup           Cleanup test environment and resources
    -k, --keep-cluster      Keep kind cluster after tests (for debugging)
    -v, --verbose           Verbose output
    -h, --help              Show this help

EXAMPLES:
    # Run basic tests only
    $0 -t basic

    # Setup environment and run all tests
    $0 -s -t all

    # Run tests and cleanup everything
    $0 -t comprehensive -c

    # Setup, run all tests, but keep cluster for debugging
    $0 -s -t all -k

ENVIRONMENT VARIABLES:
    CHART_PATH             Path to chart directory (default: ./charts/oxy-app)
    VALUES_DIR             Path to test values directory (default: \$CHART_PATH/test-values)
    CLUSTER_NAME           Kind cluster name (default: helm-test-cluster)
    KIND_CONFIG            Kind cluster config file (default: ./kind-config.yaml)
    CI                     Set to 'true' to skip local environment setup

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites"

    local missing_tools=()

    if ! command -v helm >/dev/null 2>&1; then
        missing_tools+=("helm")
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi

    if ! is_ci && ! command -v kind >/dev/null 2>&1; then
        missing_tools+=("kind")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

setup_local_environment() {
    if is_ci; then
        log_info "Running in CI environment - skipping local setup"
        return 0
    fi

    log_section "Setting up local test environment"

    # Check if kind cluster exists
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log_info "Kind cluster '$CLUSTER_NAME' already exists"
    else
        log_info "Creating kind cluster '$CLUSTER_NAME'"
        if [[ -f "$KIND_CONFIG" ]]; then
            kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
        else
            log_warning "Kind config file not found at $KIND_CONFIG, using default config"
            kind create cluster --name "$CLUSTER_NAME"
        fi
    fi

    # Set kubectl context
    kubectl cluster-info --context "kind-$CLUSTER_NAME"

    # Setup test environment (secrets, ingress controller)
    setup_test_environment

    # Update test values for kind environment
    update_test_values_for_kind

    log_success "Local test environment ready"
}

cleanup_environment() {
    log_section "Cleaning up test environment"

    # Run cleanup script if it exists
    local cleanup_script="$SCRIPT_DIR/utils/cleanup.sh"
    if [[ -f "$cleanup_script" ]]; then
        log_info "Running cleanup script"
        "$cleanup_script"
    fi

    # Clean up any remaining test resources
    log_info "Cleaning up remaining test resources"
    local test_instances=(
        "test-default" "test-ingress" "test-postgres" "test-production"
        "test-persist" "test-gitsync" "test-all-features" "test-security"
        "test-extdb" "test-network" "test-failure" "test-probe-fail"
        "test-rollback" "upgrade-test" "resource-test"
    )

    for instance in "${test_instances[@]}"; do
        if helm list -q | grep -q "^$instance$"; then
            log_info "Cleaning up Helm release: $instance"
            helm uninstall "$instance" --wait --timeout=5m || true
        fi

        # Clean up any remaining Kubernetes resources
        kubectl delete pods,pvc,ingress,secrets,configmaps -l "app.kubernetes.io/instance=$instance" --ignore-not-found=true
    done

    log_success "Test environment cleanup completed"
}

cleanup_cluster() {
    if is_ci; then
        log_info "Running in CI environment - skipping cluster cleanup"
        return 0
    fi

    log_section "Cleaning up kind cluster"

    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        log_info "Deleting kind cluster '$CLUSTER_NAME'"
        kind delete cluster --name "$CLUSTER_NAME"
    else
        log_info "Kind cluster '$CLUSTER_NAME' not found"
    fi

    log_success "Cluster cleanup completed"
}

run_chart_testing() {
    log_section "Running chart-testing (lint and install)"

    # Run chart linting
    log_info "Running chart-testing (lint)"
    ct lint --target-branch main --config ct.yaml || {
        log_error "Chart linting failed"
        return 1
    }

    # Run helm unittest if available
    if helm plugin list | grep -q unittest; then
        log_info "Running helm unittest"
        helm unittest "$CHART_PATH" || {
            log_error "Helm unit tests failed"
            return 1
        }
    else
        log_warning "helm-unittest plugin not installed, skipping unit tests"
    fi

    # Run chart installation tests
    log_info "Running chart-testing (install)"
    ct install --target-branch main --config ct.yaml || {
        log_error "Chart installation tests failed"
        return 1
    }

    log_success "Chart testing completed successfully"
}

run_test_suite() {
    local test_type="$1"

    case "$test_type" in
        "basic")
            log_section "Running basic integration tests"
            "$SCRIPT_DIR/tests/01-basic-tests.sh"
            ;;
        "advanced")
            log_section "Running advanced feature tests"
            "$SCRIPT_DIR/tests/02-advanced-tests.sh"
            ;;
        "comprehensive")
            log_section "Running comprehensive feature tests"
            "$SCRIPT_DIR/tests/03-comprehensive-tests.sh"
            ;;
        "all")
            log_section "Running all test suites"
            "$SCRIPT_DIR/tests/01-basic-tests.sh"
            "$SCRIPT_DIR/tests/02-advanced-tests.sh"
            "$SCRIPT_DIR/tests/03-comprehensive-tests.sh"
            ;;
        *)
            log_error "Unknown test type: $test_type"
            log_info "Available tests: ${AVAILABLE_TESTS[*]}"
            return 1
            ;;
    esac
}

main() {
    local tests="$DEFAULT_TESTS"
    local setup_env=false
    local cleanup_env=false
    local keep_cluster=false
    local verbose=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--tests)
                tests="$2"
                shift 2
                ;;
            -s|--setup)
                setup_env=true
                shift
                ;;
            -c|--cleanup)
                cleanup_env=true
                shift
                ;;
            -k|--keep-cluster)
                keep_cluster=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate test selection
    if [[ ! " ${AVAILABLE_TESTS[*]} " =~ " $tests " ]]; then
        log_error "Invalid test selection: $tests"
        log_info "Available tests: ${AVAILABLE_TESTS[*]}"
        exit 1
    fi

    log_section "Helm Chart Integration Test Runner"
    log_info "Chart path: $CHART_PATH"
    log_info "Tests to run: $tests"
    log_info "CI mode: $(is_ci && echo "true" || echo "false")"

    # Check prerequisites
    check_prerequisites

    # Setup trap for cleanup on exit
    if [[ "$cleanup_env" == "true" ]]; then
        trap 'cleanup_environment' EXIT
    fi

    if [[ "$cleanup_env" == "true" ]] && [[ "$keep_cluster" == "false" ]]; then
        trap 'cleanup_environment; cleanup_cluster' EXIT
    fi

    # Setup environment if requested
    if [[ "$setup_env" == "true" ]]; then
        setup_local_environment
    fi

    # Run chart testing
    run_chart_testing

    # Run integration tests
    run_test_suite "$tests"

    # Cleanup if requested and not handled by trap
    if [[ "$cleanup_env" == "true" ]]; then
        cleanup_environment
        if [[ "$keep_cluster" == "false" ]]; then
            cleanup_cluster
        fi
    fi

    log_success "All tests completed successfully!"
}

# Make scripts executable
chmod +x "$SCRIPT_DIR/tests/"*.sh
chmod +x "$SCRIPT_DIR/utils/"*.sh

# Run main function
main "$@"