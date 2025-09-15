# Helm Chart Testing Guide

This repository now includes a comprehensive testing framework that makes integration tests more maintainable and runnable locally.

## Quick Start

### Local Testing

```bash
# Install prerequisites (if not already installed)
# - helm
# - kubectl
# - kind (for local Kubernetes cluster)
# - docker

# Run basic tests locally
./scripts/test-runner.sh --setup --tests basic --cleanup

# Run all tests with debugging (keep cluster after tests)
./scripts/test-runner.sh --setup --tests all --keep-cluster

# Cleanup everything when done debugging
./scripts/test-runner.sh --cleanup
```

### Available Test Suites

1. **Basic Tests** (`basic`): Core functionality
   - Default deployment
   - Ingress configuration
   - Persistence functionality

2. **Advanced Tests** (`advanced`): Feature-specific tests
   - PostgreSQL integration
   - Git sync functionality
   - Production-like configurations
   - Security hardened deployments
   - External database configurations

3. **Comprehensive Tests** (`comprehensive`): Complex scenarios
   - All features enabled simultaneously
   - Advanced networking configurations
   - Upgrade/rollback scenarios
   - Failure simulation and resilience testing

## Directory Structure

```
scripts/
├── test-runner.sh           # Main test runner script
├── utils/
│   ├── common.sh           # Shared utilities and functions
│   └── cleanup.sh          # Cleanup utility
└── tests/
    ├── 01-basic-tests.sh    # Basic integration tests
    ├── 02-advanced-tests.sh # Advanced feature tests
    └── 03-comprehensive-tests.sh # Complex scenario tests
```

## Usage Examples

### Running Specific Test Categories

```bash
# Basic tests only
./scripts/test-runner.sh -t basic

# Advanced tests only
./scripts/test-runner.sh -t advanced

# All tests
./scripts/test-runner.sh -t all
```

### Local Development Workflow

```bash
# Setup local environment once
./scripts/test-runner.sh --setup

# Run tests iteratively during development
./scripts/test-runner.sh -t basic
./scripts/test-runner.sh -t advanced

# Keep cluster running for debugging
./scripts/test-runner.sh -t comprehensive --keep-cluster

# Manual testing and debugging...
kubectl get pods
helm list

# Cleanup when done
./scripts/test-runner.sh --cleanup
```

### CI/CD Integration

The improved CI workflow (`.github/workflows/helm-ci-improved.yml`) uses the same scripts:

```yaml
- name: Run basic integration tests
  run: |
    export CI=true
    ./scripts/tests/01-basic-tests.sh

- name: Run advanced feature tests
  run: |
    export CI=true
    ./scripts/tests/02-advanced-tests.sh

- name: Run comprehensive feature tests
  run: |
    export CI=true
    ./scripts/tests/03-comprehensive-tests.sh
```

## Environment Variables

- `CHART_PATH`: Path to chart directory (default: `./charts/oxy-app`)
- `VALUES_DIR`: Path to test values directory (default: `$CHART_PATH/test-values`)
- `CLUSTER_NAME`: Kind cluster name (default: `helm-test-cluster`)
- `KIND_CONFIG`: Kind cluster config file (default: `./kind-config.yaml`)
- `CI`: Set to 'true' to skip local environment setup

## Test Configuration Files

The tests use the test values files in `charts/oxy-app/test-values/`:

- `default-values.yaml` - Basic deployment
- `with-ingress-values.yaml` - Ingress enabled
- `with-postgres-values.yaml` - PostgreSQL database
- `with-persistence-values.yaml` - Persistent storage
- `with-gitsync-values.yaml` - Git sync sidecar
- `production-like-values.yaml` - Production configuration
- `security-hardened-values.yaml` - Security focused
- `external-db-values.yaml` - External database
- `all-features-values.yaml` - All features enabled
- `advanced-networking-values.yaml` - Complex networking
- `failure-simulation-values.yaml` - Failure testing

## Cleanup and Maintenance

### Manual Cleanup

```bash
# Clean up test resources only
./scripts/utils/cleanup.sh

# Force cleanup stuck resources
./scripts/utils/cleanup.sh --force

# Verify cleanup completed
./scripts/utils/cleanup.sh --verify-only
```

### Troubleshooting

1. **Tests failing locally**: Check that kind cluster is running and kubectl context is correct
2. **Resource cleanup issues**: Use `./scripts/utils/cleanup.sh --force`
3. **Kind cluster issues**: Delete and recreate with `kind delete cluster --name helm-test-cluster`
4. **Permission issues**: Run `chmod +x scripts/**/*.sh`

## Benefits of This Approach

1. **Maintainability**: Tests are organized in logical modules
2. **Reusability**: Common functions shared across all tests
3. **Local Development**: Full test suite can run on developer machines
4. **Debugging**: Tests can be run individually with cluster preservation
5. **CI Optimization**: Same scripts used in CI reduce duplication
6. **Error Handling**: Comprehensive error handling and cleanup
7. **Documentation**: Self-documenting through consistent logging

## Chart Testing Integration

The framework avoids using the `ci/` folder (which can cause conflicts with chart-testing) and instead uses:

- `test-values/` - Existing directory for all test values (integration + unit tests)
- `chart-testing-values.yaml` - Special values file for ct install
- Updated `ct.yaml` configuration to use the dedicated values file

This approach prevents conflicts while maintaining compatibility with chart-testing tools.

## Migration from Old CI

The original CI workflow is preserved as `helm-ci.yml`. The new workflow `helm-ci-improved.yml` provides the same functionality but with better organization. To migrate:

1. Test the new workflow thoroughly
2. Rename `helm-ci.yml` to `helm-ci-legacy.yml`
3. Rename `helm-ci-improved.yml` to `helm-ci.yml`
4. Remove the legacy file once confident in the new approach