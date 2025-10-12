# Oxy App Helm Chart

## Quick start

- Basic local install (from repo root)

```bash
helm install oxy-app ./charts/oxy-app --namespace oxy --create-namespace
```

- Install using the chart's values file

```bash
helm install oxy-app ./charts/oxy-app -f charts/oxy-app/values.yaml --namespace oxy --create-namespace
```

- Install directly from the OCI registry

```bash
# install from the OCI registry
helm install oxy-app oci://ghcr.io/oxy-hq/helm-charts/oxy-app --namespace oxy --create-namespace

# with a values file
helm install oxy-app oci://ghcr.io/oxy-hq/helm-charts/oxy-app -f charts/oxy-app/values.yaml --namespace oxy --create-namespace
```

- Install from the classic Helm repository

```bash
helm repo add oxy-hq https://oxy-hq.github.io/charts/
helm repo update

helm install oxy-app oxy-hq/oxy-app --namespace oxy --create-namespace

# with a values file
helm install oxy-app oxy-hq/oxy-app -f charts/oxy-app/values.yaml --namespace oxy --create-namespace
```

Notes: replace `oxy-app` release name, namespace, or values file as needed for your environment.

## Overview

This doc tries to focus only on chart-specific, differential behavior you won't find in a generic Helm tutorial.

- Deployment type: StatefulSet (requires a PVC). Reason: the app needs persistent storage for state, database files (if you are using sqlite), and git repo clones.
- Architecture: single main container. Optional init containers are used only for git cloning when `gitSync.enabled` is true; env file assembly is no longer performed by an init-container.
- State directory & persistence
  - PVC mounted at `/workspace`. App defaults to `OXY_STATE_DIR=/workspace/oxy_data`.
  - A sqlite database file is created at `OXY_STATE_DIR` when no external DB is provided.
- Database selection precedence
  1. `env.OXY_DATABASE_URL`
  2. `database.external.connectionString` or composed `database.external.*`
  3. bundled postgres subchart (`database.postgres.enabled`)
  4. sqlite fallback
- For production, it is recommended to set `env.OXY_DATABASE_URL` or use an external managed DB.
- gitSync / init-container
  - By default, gitSync is disabled. We start oxy with `--cloud` mode and no git repo. Git setup will be handled by the app UI
  - Controlled by `gitSync.enabled` (default: `false`). When enabled, init containers clone and prepare `/workspace/current`. The chart no longer builds an `.env` in an init container; environment variables should be provided via `env`, `configMap`, or mounted secrets.
  - When disabled, init containers and git-ssh mounts are omitted and the app uses `--cloud` mode.
  - **SSH Key Management**:
    - For development/testing: You can provide SSH keys directly in `values.yaml` via `sshKey.privateKey` and optionally `sshKey.knownHosts`. The chart will create a Kubernetes Secret automatically.
    - For production: Create the SSH secret externally (manually or via External Secrets Operator) and reference it via `gitSync.sshSecretName` or `sshKey.secretName`. **Never commit SSH keys to version control.**
    - Secret naming: Use `sshKey.secretName` to specify where keys should be stored. If not set, defaults to `gitSync.sshSecretName` (which defaults to `oxy-git-ssh`).
- Extra containers
  - The chart supports user-supplied init containers and sidecars via `extraInitContainers` and `extraSidecars` in `values.yaml`.
  - Each entry should be a valid Kubernetes container spec (name, image, command, volumeMounts, etc.). These are rendered into the Pod `initContainers` and `containers` lists respectively.
  - If your custom containers require additional volumes, add them using the chart's supported volume or PVC fields and reference the volume names in your container's `volumeMounts`.
- External secrets
  - `externalSecrets.envSecretNames` copies secret keys & values as env vars
  - `externalSecrets.fileSecrets` copies secret keys as files into the workspace.

## Validation & Testing

### Unit Tests
The chart includes comprehensive unit tests covering all core functionality:

- **StatefulSet tests** - Container configuration, resources, probes, persistence
- **Services tests** - Main service and headless service configuration
- **Ingress tests** - Routing, TLS, annotations, multiple hosts
- **ServiceAccount tests** - RBAC, cloud provider annotations (AWS IRSA, GCP Workload Identity, Azure)
- **ConfigMap tests** - Configuration management and multiple file formats
- **Consistency tests** - Cross-template validation ensuring naming consistency, label alignment, and service references

**Running unit tests:**
```bash
# Install helm unittest plugin (one-time setup)
helm plugin install https://github.com/quintush/helm-unittest

# Run all unit tests
helm unittest charts/oxy-app

# Run specific test suite
helm unittest -f tests/statefulset_test.yaml charts/oxy-app
```

### Integration Tests
The repository includes comprehensive integration tests that validate real deployments:

```bash
# Requires kind and kubectl
ct install --config ct.yaml
```

### Validation
Use standard Helm validation commands:
```bash
helm lint charts/oxy-app
helm template charts/oxy-app --debug
```

The test suite ensures chart reliability across different configuration scenarios including production deployments, high availability setups, and security-hardened configurations.
