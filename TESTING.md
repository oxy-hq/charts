# Helm Chart Testing Guide

This document describes the comprehensive testing setup for the oxy-app Helm chart.

## Testing Structure

### Unit Tests
- **Location**: `charts/oxy-app/tests/`
- **Tool**: [helm-unittest](https://github.com/quintush/helm-unittest)
- **Purpose**: Test template rendering and value validation
- **Command**: `helm unittest ./charts/oxy-app`

### Integration Tests
- **Location**: `charts/oxy-app/ci/`
- **Tool**: [chart-testing (ct)](https://github.com/helm/chart-testing)
- **Purpose**: Test actual deployment in Kubernetes clusters
- **Command**: `ct install --config ct.yaml`

## Test Scenarios

The integration tests cover the following deployment scenarios:

### 1. Default Deployment (`default-values.yaml`)
- Minimal configuration with nginx for testing
- No external dependencies
- Basic resource limits
- Tests core functionality

### 2. Ingress Enabled (`with-ingress-values.yaml`)
- NGINX ingress controller setup
- Custom hostname configuration
- Ingress path routing

### 3. PostgreSQL Enabled (`with-postgres-values.yaml`)
- Bitnami PostgreSQL dependency
- Database connectivity testing
- StatefulSet validation

### 4. Production-like (`production-like-values.yaml`)
- Based on actual production configuration
- Service account with annotations
- Persistence enabled
- Ingress with production-like settings

### 5. Persistence Only (`with-persistence-values.yaml`)
- StatefulSet behavior validation
- PVC creation and binding
- Data persistence verification

### 6. Git Sync (`with-gitsync-values.yaml`)
- Sidecar container testing
- Git repository cloning
- Volume sharing validation

## GitHub Actions Workflow

The CI pipeline includes:

1. **Chart Linting**: Static analysis and best practices validation
2. **Unit Tests**: Template rendering tests
3. **Kind Cluster Setup**: Local Kubernetes cluster for testing
4. **NGINX Ingress**: Ingress controller installation
5. **Chart Testing**: Standard ct install tests
6. **Comprehensive Integration Tests**: Custom test scenarios
7. **Upgrade/Rollback Tests**: Helm upgrade and rollback validation
8. **Resource Tests**: CPU/memory limits verification
9. **Cleanup Verification**: Ensures no resources leak

## Running Tests Locally

### Prerequisites
- Docker and Kind (for local cluster)
- Helm 3.x
- kubectl
- helm-unittest plugin

### Setup
```bash
# Install helm-unittest
helm plugin install https://github.com/quintush/helm-unittest

# Create kind cluster
kind create cluster --name helm-testing

# Install NGINX ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
```

### Run Unit Tests
```bash
helm unittest ./charts/oxy-app
```

### Run Integration Tests
```bash
# Using chart-testing
ct install --config ct.yaml

# Using custom integration script
./scripts/test-integration.sh
```

### Run Specific Test Scenario
```bash
# Test with PostgreSQL
helm install test-postgres ./charts/oxy-app -f ./charts/oxy-app/ci/with-postgres-values.yaml

# Test production-like deployment
helm install test-prod ./charts/oxy-app -f ./charts/oxy-app/ci/production-like-values.yaml
```

## Test Configuration Files

### `ct.yaml`
Chart-testing configuration with:
- Chart directories to scan
- Repository dependencies
- Helm extra arguments
- Validation options

### CI Values Files
Each `ci/*.yaml` file represents a different deployment scenario:
- Lightweight configurations for CI/CD
- Real-world feature combinations
- Edge case testing

## Best Practices Implemented

1. **Comprehensive Coverage**: Tests cover all major chart features
2. **Production Similarity**: Test scenarios mirror production usage
3. **Resource Efficiency**: CI-optimized resource limits
4. **Proper Cleanup**: All test resources are cleaned up
5. **Failure Detection**: Tests fail fast with clear error messages
6. **Upgrade Testing**: Validates helm upgrade/rollback scenarios
7. **Security Testing**: Verifies RBAC and security configurations
8. **Dependency Testing**: Validates external chart dependencies

## Test Maintenance

When adding new chart features:

1. Add unit tests in `tests/` directory
2. Create appropriate CI values file in `ci/` directory
3. Add integration test scenario to workflow
4. Update cleanup verification
5. Test locally before submitting PR

## Troubleshooting

### Common Issues

1. **Resource Constraints**: Increase timeouts or reduce resource requests
2. **Image Pull Issues**: Use lightweight test images (nginx)
3. **PVC Binding**: Ensure cluster has default storage class
4. **Network Policies**: May interfere with ingress testing

### Debug Commands
```bash
# Check pod status
kubectl get pods -A

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check helm releases
helm list -A

# Check PVC status
kubectl get pvc -A
```

## Continuous Improvement

The testing setup should evolve with:
- New chart features
- Production feedback
- Helm best practices updates
- Security requirements changes