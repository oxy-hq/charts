# Helm Chart Unit Test Organization

This directory contains comprehensive unit tests for the oxy-app Helm chart using [helm-unittest](https://github.com/quintush/helm-unittest).

## Test Organization

### Directory Structure

```
tests/
├── core/                    # Core functionality tests
│   ├── statefulset_comprehensive_test.yaml
│   ├── services_test.yaml
│   └── ingress_comprehensive_test.yaml
├── features/                # Feature-specific tests
│   ├── git_sync_test.yaml
│   ├── external_secrets_test.yaml
│   ├── database_test.yaml
│   └── init_containers_sidecars_test.yaml
├── edge-cases/              # Edge cases and boundary conditions
│   └── edge_cases_test.yaml
├── security/                # Security configuration tests
│   └── security_test.yaml
├── values/                  # Legacy/original tests (kept for compatibility)
│   ├── configmap_comprehensive_test.yaml
│   └── [original test files...]
└── README.md               # This file
```

## Test Categories

### Core Tests (`core/`)
Tests for basic chart functionality and standard Kubernetes resources:
- **StatefulSet**: Comprehensive validation of StatefulSet configuration, containers, volumes, probes, resources, etc.
- **Services**: Main service and headless service configuration
- **Ingress**: Multi-host, multi-path, TLS, annotations, and complex routing scenarios

### Feature Tests (`features/`)
Tests for advanced chart features and integrations:
- **Git Sync**: Init containers, sidecar containers, SSH configuration, volume mounts
- **External Secrets**: ESO integration, secret mappings, file/env secrets
- **Database**: Internal PostgreSQL, external database, connection string handling
- **Init/Sidecar Containers**: Custom containers, complex configurations, resource management

### Edge Case Tests (`edge-cases/`)
Tests for boundary conditions and unusual scenarios:
- Empty/null values handling
- Extreme resource configurations (very large/small)
- Special characters and Unicode
- Maximum/minimum values for timeouts, ports, etc.
- Complex regex patterns and long strings

### Security Tests (`security/`)
Tests for security configurations and compliance:
- Security contexts (pod and container level)
- Service account configuration and IRSA
- Secret handling and permissions
- Network policy compatibility
- Pod Security Standards compliance
- Resource limits and security boundaries

### Legacy Tests (`values/`)
Original test files preserved for backward compatibility and reference.

## Running Tests

### Run All Tests
```bash
helm unittest ./charts/oxy-app
```

### Run Specific Test Category
```bash
# Core functionality tests
helm unittest ./charts/oxy-app/tests/core/

# Feature tests
helm unittest ./charts/oxy-app/tests/features/

# Security tests  
helm unittest ./charts/oxy-app/tests/security/

# Edge case tests
helm unittest ./charts/oxy-app/tests/edge-cases/
```

### Run Specific Test File
```bash
helm unittest ./charts/oxy-app/tests/core/statefulset_comprehensive_test.yaml
```

### Run with Verbose Output
```bash
helm unittest -v ./charts/oxy-app
```

## Test Coverage

Our unit tests cover:

### Template Validation
- ✅ Correct Kubernetes resource types and API versions
- ✅ Proper metadata (labels, annotations, names)
- ✅ Template rendering with various value combinations

### Configuration Testing
- ✅ Default values produce valid configurations
- ✅ Custom values override defaults correctly
- ✅ Edge cases and boundary conditions
- ✅ Invalid configurations are handled gracefully

### Feature Integration
- ✅ Git sync initialization and sidecar containers
- ✅ External secrets operator integration
- ✅ Database configuration (internal/external)
- ✅ Init containers and sidecars
- ✅ ConfigMap generation and mounting
- ✅ Ingress with complex routing rules
- ✅ Service account and RBAC

### Security Validation
- ✅ Security contexts and user permissions
- ✅ Secret handling and mounting permissions
- ✅ Pod Security Standards compliance
- ✅ Resource limits and constraints
- ✅ Network policy compatibility

## Test Patterns

### Common Test Patterns Used

1. **Resource Existence**: Verify resources are created when expected
```yaml
- it: renders StatefulSet when enabled
  asserts:
    - equal:
        path: kind
        value: StatefulSet
```

2. **Conditional Rendering**: Test resources only render under correct conditions
```yaml
- it: does not render ConfigMap when disabled
  set:
    configMap.enabled: false
  asserts:
    - hasDocuments:
        count: 0
```

3. **Value Propagation**: Ensure values.yaml settings are correctly applied
```yaml
- it: applies custom replica count
  set:
    app.replicaCount: 3
  asserts:
    - equal:
        path: spec.replicas
        value: 3
```

4. **Complex Configuration**: Test interactions between multiple features
```yaml
- it: works with git sync and sidecars together
  set:
    gitSync.enabled: true
    extraSidecars: [...]
  asserts:
    - equal:
        path: spec.template.spec.containers | length
        value: 3  # main + git-sync + sidecar
```

## Writing New Tests

When adding new features to the chart, follow these guidelines:

### 1. Choose the Right Category
- Core functionality → `core/`
- New features → `features/`
- Edge cases → `edge-cases/`
- Security-related → `security/`

### 2. Test Structure
```yaml
suite: descriptive test suite name
templates:
  - template.yaml
  - other-template.yaml

tests:
  - it: describes what this test validates
    set:
      # Override values for this test
    asserts:
      - assertion_type:
          path: yaml.path.to.field
          value: expected_value
```

### 3. Comprehensive Coverage
For each new feature, test:
- ✅ Default behavior
- ✅ Feature enabled/disabled
- ✅ Custom configuration options
- ✅ Edge cases and error conditions
- ✅ Integration with existing features
- ✅ Security implications

### 4. Naming Conventions
- Test files: `feature_name_test.yaml`
- Test suites: `feature name comprehensive tests`
- Test cases: `describes the specific behavior being tested`

## Integration with CI/CD

These unit tests run automatically in GitHub Actions as part of:
1. **Lint and Test Phase**: Before integration tests
2. **Pull Request Validation**: On every PR
3. **Pre-release Validation**: Before chart releases

The tests must pass before any integration tests run, ensuring basic correctness before expensive Kubernetes testing.

## Maintenance

### Regular Maintenance Tasks
- 📅 **Monthly**: Review test coverage for new features
- 📅 **Per Release**: Update test values to match current defaults
- 📅 **As Needed**: Add tests for reported bugs before fixing
- 📅 **Quarterly**: Review and update edge case tests

### Adding Tests for Bug Fixes
When fixing bugs:
1. Add a failing test that reproduces the bug
2. Fix the chart templates
3. Verify the test now passes
4. Include both in the same PR

This ensures regressions are caught early and the fix is properly validated.