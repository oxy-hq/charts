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

git-sync expects a Kubernetes Secret with an SSH private key and (optionally) a known_hosts file. Default secret name is configured in `values.yaml` as `git.sshSecretName`.

Create the secret before installing the chart:

```bash
kubectl create secret generic oxy-git-ssh \
  --from-file=ssh=./id_rsa \
  --from-file=known_hosts=./known_hosts \
  -n oxy-app
```

Ensure the private key file is a PEM private key and not checked into the repo. For production, prefer External Secrets Operator or your cloud secret manager.

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
