# HTTP Authentication for Git-Sync

This document describes the HTTP authentication feature for git-sync in the oxy-app Helm chart.

## Overview

The chart now supports HTTP/HTTPS authentication for git repositories using username and password (or personal access tokens). This is useful when cloning from:
- GitHub using personal access tokens
- GitLab using personal access tokens or deploy tokens
- Bitbucket using app passwords
- Any other git server that supports HTTPS authentication

## Configuration

### Basic Usage with Inline Password

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/myrepo.git
  branch: main

httpAuth:
  username: "myusername"
  password: "ghp_myPersonalAccessToken123"
```

**⚠️ Warning**: Inline passwords are only recommended for development/testing. For production, use secret references.

### Production Usage with Secret Reference

1. Create a Kubernetes secret manually:

```bash
kubectl create secret generic git-credentials \
  --from-literal=password='your-personal-access-token'
```

2. Reference the secret in values:

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/myrepo.git
  branch: main

httpAuth:
  username: "myusername"
  secretName: "git-credentials"
  passwordKey: "password"  # Optional, defaults to "password"
```

## Configuration Options

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `httpAuth.username` | string | Yes | `""` | Username for HTTP authentication |
| `httpAuth.password` | string | No | `""` | Inline password (not recommended for production) |
| `httpAuth.secretName` | string | No | `""` | Name of existing secret containing the password |
| `httpAuth.passwordKey` | string | No | `"password"` | Key in the secret that contains the password |

## How It Works

1. **Secret Creation**: 
   - If `httpAuth.password` is provided (and `secretName` is not), the chart automatically creates a Kubernetes Secret named `<release-name>-http-auth`
   - If `httpAuth.secretName` is provided, the chart uses the existing secret

2. **Volume Mounting**:
   - The password secret is mounted to `/etc/git-auth/password` in both the git-clone init container and git-sync sidecar
   - The mount has restrictive permissions (`defaultMode: 0400`)

3. **Git-Sync Arguments**:
   - `--username=<username>` is passed to git-sync
   - `--password-file=/etc/git-auth/password` is passed to git-sync

## Priority

HTTP authentication takes precedence over SSH keys. If both `httpAuth.username` and `sshKeys` are configured, HTTP authentication will be used and SSH keys will be ignored.

## Examples

### GitHub with Personal Access Token

```yaml
gitSync:
  enabled: true
  repository: https://github.com/myorg/private-repo.git

httpAuth:
  username: "github-bot"
  password: "ghp_abc123def456ghi789"
```

### GitLab with Deploy Token

```yaml
gitSync:
  enabled: true
  repository: https://gitlab.com/myorg/private-repo.git

httpAuth:
  username: "deploy-token-username"
  secretName: "gitlab-deploy-token"
  passwordKey: "token"
```

### Bitbucket with App Password

```yaml
gitSync:
  enabled: true
  repository: https://bitbucket.org/myorg/private-repo.git

httpAuth:
  username: "myusername"
  password: "app-password-here"
```

## Security Best Practices

1. **Never commit passwords in values.yaml**: Use secret references for production
2. **Use Personal Access Tokens**: Instead of user passwords, use tokens with minimal required scopes
3. **Rotate tokens regularly**: Implement a token rotation policy
4. **Use RBAC**: Restrict access to secrets containing credentials
5. **Consider External Secrets Operator**: For advanced secret management

## Testing

The feature includes comprehensive unit tests:

```bash
helm unittest .
```

Test coverage includes:
- Secret creation from inline password
- Secret reference handling
- Volume mount configuration
- Git-sync argument generation
- Priority over SSH keys
- Edge cases (empty username, missing password, etc.)

## Troubleshooting

### Authentication Fails

Check the git-sync logs:
```bash
kubectl logs <pod-name> -c git-sync
```

Common issues:
- Incorrect username or password
- Token expired or revoked
- Insufficient token permissions
- Repository URL format (must be HTTPS, not SSH)

### Secret Not Found

Verify the secret exists:
```bash
kubectl get secret <secret-name> -n <namespace>
```

Check the secret has the correct key:
```bash
kubectl get secret <secret-name> -o jsonpath='{.data}' | jq
```

## Migration from SSH to HTTP Auth

To migrate from SSH authentication to HTTP:

1. Update the repository URL from SSH to HTTPS format:
   ```yaml
   # Before
   repository: git@github.com:myorg/repo.git
   
   # After
   repository: https://github.com/myorg/repo.git
   ```

2. Add HTTP auth configuration:
   ```yaml
   httpAuth:
     username: "your-username"
     secretName: "git-credentials"
   ```

3. Remove SSH keys configuration:
   ```yaml
   # Remove or comment out
   # sshKeys: [...]
   ```

4. Update your deployment:
   ```bash
   helm upgrade <release-name> ./charts/oxy-app -f values.yaml
   ```
