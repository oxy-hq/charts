# Authentication methods for git clone

This document explains the supported authentication methods for git operations in the oxy-app Helm chart's git init container. It covers HTTPS/HTTP authentication (username + password / token), SSH keys, and GitHub App authentication. For each method the doc explains inline vs secret-backed configuration, precedence rules, examples, and security best practices.

## Overview

The chart supports three authentication methods for cloning a git repository via the `git-clone` init container:

- **HTTP/HTTPS authentication** (`httpAuth`) — use username + password (or personal access token) for HTTPS repository URLs.
- **SSH key authentication** (`sshKey`) — single SSH private key for SSH repository URLs.
- **GitHub App authentication** (`git.githubApp`) — generate an installation access token from a GitHub App private key at clone time.

Choose the method that best fits your environment. The chart supports both inline (chart-created secret) and secret-backed (user-provided secret) workflows for sensitive data.

## Priority

The chart applies the following precedence when multiple authentication methods are configured:

1. **HTTP auth** (`httpAuth.username`) — takes highest precedence.
2. **GitHub App** (`git.githubApp`) — used when a private key or secretName is present.
3. **SSH key** (`sshKey`) — used when neither HTTP auth nor GitHub App are configured.

## HTTP Authentication

Use HTTP(S) authentication when cloning via HTTPS URLs.

Inline (chart creates secret, for development/testing):

```yaml
git:
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
git:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  branch: main

httpAuth:
  username: "github-bot"
  secretName: "git-credentials"
  passwordKey: "password" # defaults to "password"
```

How it works:

- If `httpAuth.password` is present and `httpAuth.secretName` is empty, the chart creates a secret `<release-name>-http-auth` and mounts `/etc/git-auth/password` in the init container.
- If `httpAuth.secretName` is provided, the chart mounts the provided secret and reads the `passwordKey`.
- The init container embeds the credentials directly in the clone URL.

Security notes:

- Never commit inline passwords in `values.yaml` for production. Use external secrets or pre-created Kubernetes Secrets.
- Use tokens with least privilege and rotate regularly.

## SSH Key Authentication

Inline (chart creates a secret):

```yaml
git:
  enabled: true
  repository: git@github.com:myorg/private-repo.git

sshKey:
  privateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...  # only for testing
```

Secret-backed (recommended):

Create a secret containing your private key and optionally known_hosts:

```bash
kubectl create secret generic my-git-ssh \
  --from-file=ssh=./id_rsa \
  --from-file=known_hosts=./known_hosts \
  -n my-namespace
```

Reference it in values:

```yaml
git:
  enabled: true
  repository: git@github.com:myorg/private-repo.git
  sshSecretName: my-git-ssh

sshKey:
  secretName: my-git-ssh
```

How it works:

- The init container copies the key to `/root/.ssh/id_rsa` (mode 600).
- If `known_hosts` is present in the mounted secret, it is copied to `/root/.ssh/known_hosts`. Otherwise, `ssh-keyscan` runs against the remote host at clone time.
- If `sshKey.privateKey` is provided inline, the chart creates a secret named `git.sshSecretName` (default: `oxy-git-ssh`).
- If `sshKey.secretName` is provided, that secret is mounted directly and takes precedence over `git.sshSecretName`.

Security notes:

- Protect your private key with proper RBAC and rotation policies.
- Prefer using external secret managers for production.

## GitHub App Authentication

The init container generates a short-lived installation access token at clone time using the GitHub App private key, then clones via HTTPS with that token.

### Required fields

When using GitHub App authentication without an external secret, you **must** provide:

- `git.githubApp.privateKey` — PEM private key for the GitHub App
- `git.githubApp.applicationId` — GitHub App Application ID
- `git.githubApp.installationId` — GitHub App Installation ID

### Secret key name fields

- `git.githubApp.privateKeyKey` — key name in the Secret for the private key (default: `github_app_private_key`)
- `git.githubApp.applicationIdKey` — key name in the Secret for the app ID (default: `github_app_application_id`)
- `git.githubApp.installationIdKey` — key name in the Secret for the installation ID (default: `github_app_installation_id`)

### External secret

- `git.githubApp.secretName` — name of an existing Secret containing all required keys

Inline (chart creates secret, for development/testing only):

```yaml
git:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  githubApp:
    privateKey: |-
      -----BEGIN PRIVATE KEY-----
      ...
      -----END PRIVATE KEY-----
    applicationId: "123"
    installationId: "456"
```

Secret-backed (recommended for production):

```bash
kubectl create secret generic my-github-app-secret \
  --from-file=github_app_private_key=./app.pem \
  --from-literal=github_app_application_id="123" \
  --from-literal=github_app_installation_id="456" \
  -n my-namespace
```

```yaml
git:
  enabled: true
  repository: https://github.com/myorg/private-repo.git
  githubApp:
    secretName: my-github-app-secret
    privateKeyKey: github_app_private_key
    applicationIdKey: github_app_application_id
    installationIdKey: github_app_installation_id
```

How it works in the chart:

- The init container installs `curl` and `openssl` via `apk`, then constructs a JWT from the private key.
- It exchanges the JWT for a GitHub App installation access token via the GitHub API.
- The token is embedded in the HTTPS clone URL as `x-access-token`.
- When inline fields are provided, the chart creates a Secret named `<release-name>-github-app`.
- When `secretName` is provided, the chart mounts that Secret directly.

Security notes:

- Prefer externally managed Secrets (or External Secrets Operator) in production.
- Keep private key files secure and rotate them regularly.

## Examples

SSH clone with external secret:

```yaml
git:
  enabled: true
  repository: git@github.com:myorg/repo.git
  sshSecretName: oxy-git-ssh

sshKey:
  secretName: oxy-git-ssh
```

GitHub App with pre-created secret (recommended):

```yaml
git:
  enabled: true
  repository: https://github.com/myorg/repo.git
  githubApp:
    secretName: my-github-app-secret
    privateKeyKey: github_app_private_key
    applicationIdKey: github_app_application_id
    installationIdKey: github_app_installation_id
```

Custom clone directory with subdirectory working dir:

```yaml
git:
  enabled: true
  repository: git@github.com:myorg/repo.git
  cloneDir: "myrepo"       # clones into <mountPath>/myrepo
  workingDir: "backend"    # sets workingDir to <mountPath>/myrepo/backend
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

## Troubleshooting

### Clone fails

Check init container logs:

```bash
kubectl logs <pod-name> -c git-clone
```

### Secret not found or missing keys

Verify your secret exists and contains the expected keys:

```bash
kubectl get secret <secret-name> -n <namespace> -o yaml
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data}' | jq
```

For GitHub App secrets, the following keys are required by default:

- `github_app_private_key`
- `github_app_application_id`
- `github_app_installation_id`
