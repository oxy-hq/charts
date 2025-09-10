# Oxy App Helm Chart

A Helm chart for deploying the Oxy application as a StatefulSet on EKS.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- EKS cluster with IRSA configured
- External Secrets Operator (if using external secrets)

## Installation

### Basic Installation

```bash
helm install oxy-app ./helm-charts/oxy-app \
  --namespace oxy-app \
  --create-namespace
```

### Installation with Custom Values

```bash
helm install oxy-app ./helm-charts/oxy-app \
  --namespace oxy-app \
  --create-namespace \
  --set app.image=ghcr.io/oxy-hq/oxy-internal:latest \
  --set env.CLUSTER_NAME=my-cluster \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789012:role/oxy-app-role
```

### Installation with Values File

Create a custom values file:

```yaml
# custom-values.yaml
app:
  replicaCount: 2
  image: ghcr.io/oxy-hq/oxy-internal:latest

env:
  CLUSTER_NAME: my-cluster
  ENVIRONMENT: production

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/oxy-app-role

persistence:
  size: 50Gi

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

Then install:

```bash
helm install oxy-app ./helm-charts/oxy-app \
  --namespace oxy-app \
  --create-namespace \
  --values custom-values.yaml
```

## Configuration

The following table lists the configurable parameters and their default values:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `app.name` | Application name | `oxy-app` |
| `app.image` | Container image | `ghcr.io/oxy-hq/oxy-internal:20250624` |
| `app.port` | Application port | `3000` |
| `app.replicaCount` | Number of replicas | `1` |
| `env.AWS_REGION` | AWS region | `us-west-2` |
| `env.CLUSTER_NAME` | EKS cluster name | `""` |
| `env.ENVIRONMENT` | Environment name | `dev` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `oxy-app-sa` |
| `serviceAccount.annotations` | Service account annotations | `{}` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | Storage size | `20Gi` |
| `persistence.storageClassName` | Storage class | `gp3` |
| `resources.requests.cpu` | CPU requests | `250m` |
| `resources.requests.memory` | Memory requests | `512Mi` |
| `resources.limits.cpu` | CPU limits | `1000m` |
| `resources.limits.memory` | Memory limits | `2Gi` |

## Upgrading

```bash
helm upgrade oxy-app ./helm-charts/oxy-app \
  --namespace oxy-app \
  --values custom-values.yaml
```

## Uninstalling

```bash
helm uninstall oxy-app --namespace oxy-app
```

## Security Considerations

1. **SSH Keys**: The current chart includes SSH keys directly in values. In production, use External Secrets or Kubernetes secrets.

2. **IRSA**: Configure the service account with proper IAM role annotations for AWS permissions.

3. **External Secrets**: Enable external secrets for secure credential management.

## Monitoring

The application exposes health checks on:

- Liveness probe: `GET /` on port 3000
- Readiness probe: `GET /` on port 3000

## Troubleshooting

### Pod Stuck in Init

Check init container logs:

```bash
kubectl logs -n oxy-app oxy-app-0 -c workspace-init
kubectl logs -n oxy-app oxy-app-0 -c env-setup
```

### External Secrets Not Working

Check External Secret status:

```bash
kubectl get externalsecret -n oxy-app
kubectl describe externalsecret oxy-env-secret -n oxy-app
```

### Storage Issues

Check PVC status:

```bash
kubectl get pvc -n oxy-app
kubectl describe pvc workspace-oxy-app-0 -n oxy-app
```

## Database options

The chart supports three database modes. Configure under `values.yaml` in the `database` section.

- sqlite (default)
  - Uses a local sqlite file inside the application workspace.
  - No external credentials required.
  - Example values:

```yaml
database:
  type: sqlite
```

- postgres (optional subchart)
  - Enable the bundled postgres dependency (set in Chart.yaml via `database.postgres.enabled`).
  - Example values:

```yaml
database:
  type: postgres
  postgres:
    enabled: true
```

- external
  - Use an existing external database by supplying a connection string.
  - Example values:

```yaml
database:
  type: external
  external:
    connectionString: "postgres://user:password@host:5432/dbname"
```

## Git SSH secret (oxy-git-ssh)

git-sync expects a Kubernetes Secret with an SSH private key and (optionally) a known_hosts file. Default secret name is configured in `values.yaml` as `gitSync.sshSecretName`.

Create the secret before installing the chart (or provide `sshKey.privateKey` in a values file):

```bash
kubectl create secret generic oxy-git-ssh \
  --from-file=ssh=./id_rsa \
  --from-file=known_hosts=./known_hosts \
  -n oxy-app
```

Ensure the private key file is a PEM private key and avoid checking it into the repo. For production, prefer External Secrets Operator or your cloud secret manager.

## External Secrets usage

The chart supports mounting existing Kubernetes Secrets into the pod. Use
`externalSecrets.envSecretNames` to list Secret names whose keys will be
concatenated into a single `.env` file, and `externalSecrets.fileSecrets`
to specify named secrets and keys to copy as files into the workspace.

Example values snippet:

```yaml
externalSecrets:
  create: false
  envSecretNames:
    - my-app-env-secret
  fileSecrets:
    - name: my-datawarehouse-secret
      key: credentials.json
      dest: credentials.json
```

## Chart notes and important behaviors

These notes explain subtle behaviors of the chart that affect runtime and upgrades.

### State directory and PVC (OXY_STATE_DIR)

- The chart provisions a PersistentVolumeClaim via the StatefulSet `volumeClaimTemplates` named `workspace`. This PVC is mandatory for the StatefulSet and is used to persist application data across pod restarts and rescheduling.
- The application environment variable `OXY_STATE_DIR` defaults to `/workspace/oxy_data` (see `values.yaml`). The container mounts the PVC at `/workspace` and the application uses `OXY_STATE_DIR` to locate its state files (for example the sqlite DB file when the chart uses local sqlite).
- In practice:
  - If you keep the default `OXY_STATE_DIR`, the sqlite fallback DB will be created at `/workspace/oxy_data/oxy.db` and persist on the PVC.
  - If you change `persistence.storageClassName` or `persistence.size`, the underlying volume backing the workspace will change on next PVC reprovision (careful during upgrades).
  - Do not mount another volume over `/workspace` from an external source unless you intend to replace the PVC-backed workspace.

### Database selection and OXY_DATABASE_URL precedence

- The chart chooses the database connection in this order of precedence:

  1. The explicit environment value `env.OXY_DATABASE_URL` (highest priority). If you supply this value, it will be used as-is and the chart will not attempt to compose a connection string from the `database.*` sections.
  2. `database.external.connectionString` or the `database.external` block (if enabled). If `external.connectionString` is set it will be used directly; otherwise the chart will attempt to compose a postgres URL from `database.external.user`, `password`, `host`, `port`, and `database`.
  3. The bundled postgres subchart (when `database.postgres.enabled: true`) — the chart will reference the postgres service inside the same release.
  4. Fallback to a local sqlite file under the workspace: `sqlite:////workspace/oxy_data/oxy.db`.

- Practical guidance:
  - For production, prefer explicitly setting `env.OXY_DATABASE_URL` to a managed database connection string (RDS, Cloud SQL, etc.).
  - If you use the built-in postgres subchart, enable `database.postgres.enabled` and provide credentials via the `database.postgres.*` keys (or better, use External Secrets to manage them).
  - If you switch from sqlite to an external DB, ensure you migrate the sqlite data or reinitialize the app appropriately.

### gitSync behavior (optional) and readonly fallback

- The chart includes optional git-sync behavior controlled by `gitSync.enabled` (default: `true`). When enabled, an init container performs a one-time secure clone into the workspace; optionally a long-running git-sync sidecar could be added if you prefer continuous updates.

- Key values:

  1. `gitSync.repository` (repo URL or SSH remote)
  2. `gitSync.branch` (branch to check out)
  3. `gitSync.sshSecretName` (name of a Kubernetes Secret containing `ssh` and `known_hosts` files used for SSH cloning)
  4. `gitSync.enabled` (boolean to enable/disable the git clone init flow)

- Behavior when `gitSync.enabled: true`:

  - The chart will run a `git-clone` init container which creates a linked copy under `/workspace/current` (the workspace is mounted at `/workspace`).
  - An `env-setup` init container runs to assemble `.env` and copy file secrets into `/workspace/customer-demo` before the app starts.

- Behavior when `gitSync.enabled: false`:

  - The `git-clone` and `env-setup` init containers are not rendered into the pod spec.
  - The `git-ssh` secret volume is not mounted.
  - The application command defaults to starting the server with the `--readonly` flag. This prevents the app from attempting to write content to the (empty) workspace directory when no git checkout is present.

- Security note: don't place private SSH keys directly in `values.yaml` for production. Instead create the secret in-cluster (or use External Secrets) and set `gitSync.sshSecretName` to point to it.

### Recommended validation steps after changing chart values

- After changing `gitSync` settings or persistence settings, run `helm template` or `helm lint` to verify manifests render correctly.
- If you change the `persistence.storageClassName` or size, confirm the underlying PV/PVC behavior in your cluster before upgrading the release to avoid data loss.

If you'd like, I can add a templated optional `git-ssh` Secret that the chart can create from `sshKey.*` values (gated behind a flag), or add helm-unittest cases asserting `git-clone`/`env-setup` appear only when `gitSync.enabled` is true. Let me know which you prefer.
