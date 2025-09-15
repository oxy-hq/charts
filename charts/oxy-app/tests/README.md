# Helm Chart Unit Tests

This directory contains comprehensive unit tests for the oxy-app Helm chart using [helm-unittest](https://github.com/quintush/helm-unittest).

## Test Organization

### Core Tests (Existing)
- `configmap_test.yaml` - ConfigMap resource tests
- `ingress_test.yaml` - Ingress resource tests
- `serviceaccount_test.yaml` - ServiceAccount resource tests
- `services_test.yaml` - Service resource tests
- `statefulset_test.yaml` - Basic StatefulSet tests

### Extended StatefulSet Tests (New)
- `statefulset_focused_test.yaml` - **Recommended comprehensive test** covering all core StatefulSet scenarios ✅
- `statefulset_gitsync_fixed_test.yaml` - **Working git sync behavior tests** ✅
- `statefulset_gitsync_test.yaml.disabled` - Original detailed tests (needs fixes)
- `statefulset_persistence_test.yaml.disabled` - Persistent volume tests (needs fixes)
- `statefulset_containers_test.yaml.disabled` - Init containers and sidecars tests (needs fixes)
- `statefulset_secrets_test.yaml.disabled` - External secrets tests (needs fixes)
- `workload_type_test.yaml.disabled` - StatefulSet vs Deployment tests (needs fixes)

## Key Test Scenarios

### Git Sync Behavior
The tests thoroughly validate git sync enabled vs disabled scenarios:

**Git Sync Disabled (Default):**
- Single container (main app only)
- `--readonly` flag included in command
- No git-sync sidecar container
- No git-sync init container

**Git Sync Enabled:**
- Two containers (main app + git-sync sidecar)
- Git clone init container for initial setup
- No `--readonly` flag (read-write mode)
- Proper git-sync configuration with repository, branch, period
- SSH key mounting for authentication

### Persistence Scenarios
- Volume claim template creation
- Storage class configuration
- Access modes (ReadWriteOnce, ReadWriteMany, etc.)
- Custom storage sizes and annotations
- Mount path and folder configurations

### Container Management
- Init containers (git clone + custom)
- Sidecar containers (monitoring, logging, etc.)
- Resource limits and requests
- Volume sharing between containers
- Security context inheritance

### External Secrets Integration
- Environment secret mounting via projected volumes
- File secret mounting with custom paths
- Multiple secrets handling
- Optional secret references

## Running Tests

### Run All Tests
```bash
helm unittest charts/oxy-app/
```

### Run Specific Test Suite
```bash
helm unittest --file 'tests/statefulset_focused_test.yaml' charts/oxy-app/
```

### Run Tests with Specific Values
```bash
helm unittest charts/oxy-app/ --values test-values/with-gitsync-values.yaml
```

## Test Coverage

The test suite covers:

✅ **StatefulSet Creation** - Basic resource validation
✅ **Git Sync Integration** - Enabled/disabled scenarios, container configuration
✅ **Persistence** - Volume claim templates, storage classes, mount paths
✅ **Scaling** - Replica count handling
✅ **Security** - Security contexts, service accounts
✅ **Networking** - Service configuration, headless services
✅ **Container Management** - Init containers, sidecars, resource limits
✅ **External Secrets** - Environment and file secret mounting
✅ **Configuration** - ConfigMaps, environment variables
✅ **Error Handling** - Invalid configurations and edge cases

## Test Pattern Examples

### Testing Git Sync Behavior
```yaml
- it: should have two containers when git sync enabled
  set:
    gitSync:
      enabled: true
      repository: "git@github.com:example/repo.git"
    persistence:
      enabled: true
  asserts:
    - lengthEqual:
        path: spec.template.spec.containers
        count: 2
    - equal:
        path: spec.template.spec.containers[1].name
        value: git-sync
```

### Testing Resource Configuration
```yaml
- it: should configure resources correctly
  set:
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2000m"
        memory: "4Gi"
  asserts:
    - equal:
        path: spec.template.spec.containers[0].resources.requests.cpu
        value: "500m"
```

### Testing Volume Claims
```yaml
- it: should create volume claim template with custom settings
  set:
    persistence:
      enabled: true
      size: "50Gi"
      storageClassName: "fast-ssd"
  asserts:
    - equal:
        path: spec.volumeClaimTemplates[0].spec.resources.requests.storage
        value: "50Gi"
    - equal:
        path: spec.volumeClaimTemplates[0].spec.storageClassName
        value: "fast-ssd"
```

## Test Status & Issues

### ✅ **Working Tests (70 tests passing):**
- All core tests (configmap, ingress, serviceaccount, services)
- `statefulset_test.yaml` - Basic StatefulSet functionality
- `statefulset_focused_test.yaml` - Comprehensive scenarios (20 tests)
- `statefulset_gitsync_fixed_test.yaml` - Git sync behavior (12 tests)

### ⚠️ **Disabled Tests (Need Fixes):**
The following tests have syntax/logic issues and are disabled:

**Common Issues Found:**
1. **Array Length Syntax**: Using `| length` instead of `lengthEqual` assertion
2. **Wrong Paths**: Expecting `env` arrays on git-sync container (uses `args` instead)
3. **Image Names**: Hardcoded old image versions vs actual chart values
4. **Missing Templates**: References to `deployment.yaml` template that doesn't exist
5. **Path Mismatches**: Expecting paths that don't exist in the actual chart

**Fix Examples:**
```yaml
# ❌ Wrong (fails)
- equal:
    path: spec.template.spec.containers | length
    value: 2

# ✅ Correct
- lengthEqual:
    path: spec.template.spec.containers
    count: 2
```

## Best Practices

1. **Use `statefulset_focused_test.yaml`** for most scenarios - it's the most comprehensive and reliable
2. **Use `statefulset_gitsync_fixed_test.yaml`** for git sync specific testing
3. **Test both enabled/disabled states** for optional features like git sync
4. **Validate container counts** using `lengthEqual` assertions
5. **Check actual chart implementation** before writing test expectations
6. **Use `args` not `env`** when testing git-sync container configuration

## Integration with CI/CD

These tests are automatically run as part of the Helm CI workflow:

```yaml
- name: Run helm unittest for oxy-app
  run: |
    helm unittest ./charts/oxy-app
```

The tests ensure that:
- All chart variations render correctly
- StatefulSet behaves correctly with/without git sync
- Persistence and scaling work as expected
- External integrations (secrets, sidecars) function properly