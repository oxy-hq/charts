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
  - By default, gitSync is disabled. We start oxy with `--readonly` mode and no git repo. Git setup will be handled by the app UI
  - Controlled by `gitSync.enabled` (default: `false`). When enabled, init containers clone and prepare `/workspace/current`. The chart no longer builds an `.env` in an init container; environment variables should be provided via `env`, `configMap`, or mounted secrets.
  - When disabled, init containers and git-ssh mounts are omitted and the app uses `--readonly` mode.
  - Provide SSH key material via an in-cluster Secret and set `gitSync.sshSecretName` (do not commit keys in `values.yaml`)
- Extra containers
  - The chart supports user-supplied init containers and sidecars via `extraInitContainers` and `extraSidecars` in `values.yaml`.
  - Each entry should be a valid Kubernetes container spec (name, image, command, volumeMounts, etc.). These are rendered into the Pod `initContainers` and `containers` lists respectively.
  - If your custom containers require additional volumes, add them using the chart's supported volume or PVC fields and reference the volume names in your container's `volumeMounts`.
- External secrets
  - `externalSecrets.envSecretNames` copies secret keys & values as env vars
  - `externalSecrets.fileSecrets` copies secret keys as files into the workspace.

Validation & testing

- Use `helm lint` and `helm template` to validate value changes. The chart contains lightweight tests under `charts/oxy-app/tests`.
- To run unit test, install helm unittest plugin: `helm plugin install https://github.com/quintush/helm-unittest` and run `helm unittest charts/oxy-app`.
- To run integration tests, install `kind` and `kubectl`, then run `ct install --config ct.yaml` from repo root
