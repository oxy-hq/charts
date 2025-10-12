# Authentication methods for git-sync

This document explains the supported authentication methods for git operations in the oxy-app Helm chart's git-sync integration. It covers HTTPS/HTTP authentication (username + password / token), SSH keys (single-key workflow), and GitHub App authentication. For each method the doc explains inline vs secret-backed configuration, precedence rules, examples, security best practices, and troubleshooting.

## Overview

The chart supports three main authentication methods for git-sync:

- HTTP/HTTPS authentication (`httpAuth`) — use username + password (or personal access token) for HTTPS repository URLs.
- SSH key authentication (`sshKey`) — single SSH private key matched with known_hosts for SSH repository URLs.
- GitHub App authentication (`gitSync.githubApp`) — use a GitHub App private key with application/installation IDs for GitHub App auth (works with public GitHub and GitHub Enterprise).

Choose the method that best fits your environment. The chart supports both inline (chart-created secret) and secret-backed (user-provided secret) workflows for sensitive data.

## Priority

The chart applies the following precedence when multiple authentication methods are present:

1. HTTP auth (`httpAuth`) takes highest precedence when `httpAuth.username` is set.
2. GitHub App (`gitSync.githubApp`) is used when configured (private key or secretName present) for HTTPS GitHub repositories.
3. SSH key (`sshKey`) is used when neither HTTP auth nor GitHub App are configured and an SSH private key is provided.

If HTTP auth is configured it will be used and SSH keys are ignored.

## HTTP Authentication

Use HTTP(S) authentication when cloning via HTTPS URLs.

Inline (chart creates secret, for development/testing):

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  branch: main

httpAuth:
  username: "github-bot"
  password: "ghp_abc123def456ghi789" # inline only for testing
```

Secret-backed (recommended for production):

```bash
kubectl create secret generic git-credentials \
  --from-literal=password='your-personal-access-token' -n my-namespace
```

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  branch: main

httpAuth:
  username: "github-bot"
  secretName: "git-credentials"
  passwordKey: "password" # defaults to "password"
```

How it works:

- If `httpAuth.password` is present and `httpAuth.secretName` is empty the chart will create a secret `<release-name>-http-auth` and mount `/etc/git-auth/password` in the init-clone and git-sync sidecar.

- If `httpAuth.secretName` is provided the chart mounts the provided secret and reads the passwordKey.

- Flags passed to git-sync: `--username=<username> --password-file=/etc/git-auth/password`.

Security notes:

- Never commit inline passwords in `values.yaml` for production. Use external secrets or pre-created Kubernetes Secrets.

- Use tokens with least privilege and rotate regularly.

## SSH Key Authentication (single key)

This chart supports a single SSH key via `sshKey` (the plural form `sshKeys` is not used anymore).

Inline (chart creates a secret):

```yaml
gitSync:
  enabled: true
  repository: git@github.com:myorg/private-repo.git

sshKey:
  privateKey: "|\n-----BEGIN OPENSSH PRIVATE KEY-----\n..." # only for testing
```

Secret-backed (recommended):

Create a secret containing your private key (and optionally known_hosts):

```bash
kubectl create secret generic my-git-ssh \
  --from-file=ssh=./id_rsa --from-file=known_hosts=./known_hosts -n my-namespace
```

Reference it in values:

```yaml
gitSync:
  enabled: true
  repository: git@github.com:myorg/private-repo.git
  sshSecretName: my-git-ssh

sshKey:
  secretName: my-git-ssh
```

How it works:

- If `sshKey.privateKey` is present and `sshKey.secretName` is empty the chart creates a secret (default name is `gitSync.sshSecretName`) and mounts `/etc/git-secret/ssh` and `/etc/git-secret/known_hosts` for the init clone and git-sync sidecar.

- If `sshKey.secretName` is provided the chart mounts the provided secret.

- Flags passed to git-sync: `--ssh-key-file=/etc/git-secret/ssh --ssh-known-hosts-file=/etc/git-secret/known_hosts`.

Security notes:

- Protect your private key with proper RBAC and rotation policies.

- Prefer using external secret managers for production.

## GitHub App Authentication

This chart supports GitHub App authentication for git-sync using the GitHub App private key and application/installation identifiers.

Supported fields (values.yaml):

- `gitSync.githubApp.secretName` — optional: name of existing Secret containing keys/IDs.
- `gitSync.githubApp.privateKey` — inline PEM private key (chart-created secret if used).
- `gitSync.githubApp.privateKeyKey` — key name inside the Secret for the private key (default: `github_app_private_key`).
- `gitSync.githubApp.applicationId` / `applicationIdKey` — application ID (numeric) or key name in the secret.
- `gitSync.githubApp.installationId` / `installationIdKey` — installation ID or key name in secret.
- `gitSync.githubApp.clientId` / `clientIdKey` — optional App client ID/supporting value.
- `gitSync.githubApp.baseUrl` / `baseUrlKey` — optional GitHub API base URL (useful for GitHub Enterprise). Defaults to `https://api.github.com`.

Inline (chart creates secret):

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  githubApp:
    privateKey: |-
      -----BEGIN PRIVATE KEY-----
      ...
    applicationId: "123"
    installationId: "456"
```

Secret-backed (recommended for production):

Create a secret that contains the private key and IDs. The chart expects keys as configured in `*Key` fields. Example:

```bash
kubectl create secret generic my-github-app-secret \
  --from-file=github_app_private_key=./app.pem \
  --from-literal=github_app_application_id="123" \
  --from-literal=github_app_installation_id="456" \
  -n my-namespace
```

Then reference it in values:

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  githubApp:
    secretName: my-github-app-secret
    privateKeyKey: github_app_private_key
    applicationIdKey: github_app_application_id
    installationIdKey: github_app_installation_id
```

How it works in the chart:

- If inline `gitSync.githubApp.privateKey` (or other inline fields) are provided and `secretName` is empty, the chart creates a Secret `<release-name>-github-app` containing the specified keys (privateKey, applicationId, installationId, etc.). For that chart-created Secret the template mounts only the private key file into `/etc/github-app/<privateKeyKey>` so git-sync can use the `--github-app-private-key-file` flag.

- If `gitSync.githubApp.secretName` is provided, the chart mounts the provided Secret at `/etc/github-app` (no items filter), and reads IDs via env `valueFrom.secretKeyRef` for `GITSYNC_GITHUB_APP_APPLICATION_ID`, `GITSYNC_GITHUB_APP_INSTALLATION_ID`, `GITSYNC_GITHUB_APP_CLIENT_ID`, and `GITSYNC_GITHUB_BASE_URL`.

- Git-sync flags used: `--github-app-private-key-file=/etc/github-app/<privateKeyKey>`; optionally `--github-app-client-id` and `--github-base-url` when supplied inline.

Notes on numeric values:

- When supplying numeric IDs (applicationId, installationId) via `--set` on the CLI, convert them to strings or let Helm coerce them; the chart templates coerce values to strings when creating chart-generated Secrets to avoid b64 encoding errors.

Security notes:

- Prefer using externally managed Secrets (or External Secrets Operator) and reference them via `gitSync.githubApp.secretName` in production.

- Keep private key files secure and rotate them regularly.

## Examples

- GitHub App inline (only for testing):

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/repo.git
  githubApp:
    privateKey: |-
      -----BEGIN PRIVATE KEY-----
      ...
    applicationId: "123"
    installationId: "456"
```

- GitHub App with pre-created secret (recommended):

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/repo.git
  githubApp:
    secretName: my-github-app-secret
    privateKeyKey: my_private_key
    applicationIdKey: my_app_id
    installationIdKey: my_install_id
```

## Security Best Practices

- Never commit credentials or private keys into `values.yaml` in a production context.
- Use pre-created Kubernetes Secrets or external secret managers.
- Use least-privilege tokens and narrow-scoped GitHub App permissions.
- Rotate keys and tokens regularly.
- Restrict access to secrets with RBAC.

## Testing

Run unit tests with:

```bash
helm unittest charts/oxy-app
```

Tests cover:

- Secret creation from inline values

- Secret reference handling

- Volume mount configuration

- Git-sync argument generation for HTTP, SSH, GitHub App

- Priority/precedence rules

## Troubleshooting

### Authentication fails

Check git-sync logs:

```bash
kubectl logs <pod-name> -c git-sync
```

### Secret not found or missing keys

Verify your secret exists and contains the keys expected by your configuration:

```bash
kubectl get secret <secret-name> -n <namespace> -o yaml
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}' | jq
```

If using `gitSync.githubApp.secretName`, ensure the secret contains keys matching the configured `*Key` fields (e.g. `github_app_private_key`, `github_app_application_id`).

## Migration notes

To migrate from SSH to HTTP/GitHub App:
To migrate from SSH to HTTP/GitHub App:

1. Change `gitSync.repository` to HTTPS format.

2. Add `httpAuth` or `gitSync.githubApp` configuration.

3. Remove `sshKey` (if present).

4. Run `helm upgrade` with your new values.

---

If you want this doc copied or referenced from `docs/http-auth.md` or surfaced in another user-facing location (README or top-level docs), tell me where and I will update those files or add cross-links.

