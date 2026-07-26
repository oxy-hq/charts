# PostgreSQL Migration Guide

## Overview

The Bitnami PostgreSQL chart has been deprecated. This guide covers the migration to **CloudNativePG**, a CNCF-supported PostgreSQL operator that provides production-grade PostgreSQL clusters.

## What Changed

### Before (Bitnami)
- Repository: `https://charts.bitnami.com/bitnami`
- Chart: `postgresql` v16.7.27
- Image: `docker.io/bitnami/postgresql:17.6.0-debian-12-r4`

### After (CloudNativePG)
- Repository: `https://cloudnative-pg.github.io/charts`
- Chart: `cluster` v0.0.10 (alias: `postgresql`)
- Image: `ghcr.io/cloudnative-pg/postgresql:17.2`

## Key Differences

### 1. Service Naming
CloudNativePG creates multiple services:
- `<release-name>-postgresql-rw` - Read-Write service (primary)
- `<release-name>-postgresql-ro` - Read-Only service (replicas)
- `<release-name>-postgresql-r` - Read service (any instance)

### 2. Configuration Structure

**Bitnami:**
```yaml
postgresql:
  auth:
    username: myuser
    password: mypass
    database: mydb
  primary:
    persistence:
      enabled: true
```

**CloudNativePG:**
```yaml
postgresql:
  type: postgresql
  instances: 1
  bootstrap:
    initdb:
      database: mydb
      owner: myuser
  credentials:
    username: myuser
    password: mypass
  storage:
    size: 1Gi
```

## Migration Steps

### 1. Update Dependencies

Run this to update your chart dependencies:
```bash
cd charts/oxy-app
helm dependency update
```

### 2. Backup Your Data (Production)

Before migrating production databases:
```bash
# Backup using pg_dump
kubectl exec -it <postgresql-pod> -- pg_dump -U <user> <database> > backup.sql
```

### 3. Update Values Files

If you have custom values files using PostgreSQL, update them:

```yaml
# Old Bitnami configuration
database:
  postgres:
    enabled: true
postgresql:
  auth:
    username: oxy
    password: postgres
    database: oxydb

# New CloudNativePG configuration
database:
  postgres:
    enabled: true
postgresql:
  type: postgresql
  instances: 1
  bootstrap:
    initdb:
      database: oxydb
      owner: oxy
  credentials:
    username: oxy
    password: postgres
  storage:
    size: 8Gi
```

### 4. Deploy

```bash
helm upgrade --install oxy-app ./charts/oxy-app -f your-values.yaml
```

### 5. Restore Data (if needed)

```bash
# Restore from backup
kubectl exec -it <new-postgresql-pod> -- psql -U <user> <database> < backup.sql
```

## Benefits of CloudNativePG

✅ **Active Development**: Regularly updated and maintained by the CNCF community  
✅ **Production Ready**: Built for production workloads with HA support  
✅ **Better Monitoring**: Native integration with Prometheus metrics  
✅ **Backup/Recovery**: Built-in backup and point-in-time recovery  
✅ **Rolling Updates**: Zero-downtime PostgreSQL version upgrades  
✅ **Connection Pooling**: Native PgBouncer integration  

## Alternative Options

If CloudNativePG doesn't fit your needs, consider:

### 1. Crunchy Data PostgreSQL Operator
```yaml
dependencies:
  - name: pgo
    version: 5.x.x
    repository: "https://helm.crunchydata.com"
```

### 2. Official PostgreSQL (Simple Deployment)
Create your own PostgreSQL deployment without a subchart dependency:
```yaml
# No dependency, just deploy postgres directly in your templates
```

### 3. Managed Database Services
Use cloud provider managed services (AWS RDS, GCP Cloud SQL, Azure Database) and configure as external database:
```yaml
database:
  external:
    enabled: true
    host: your-db.region.rds.amazonaws.com
    port: 5432
```

## Troubleshooting

### Issue: Service not found
**Problem:** App can't connect to PostgreSQL  
**Solution:** Verify service name includes `-rw` suffix:
```
<release-name>-postgresql-rw.<namespace>.svc.cluster.local
```

### Issue: Credentials not working
**Problem:** Authentication failed  
**Solution:** Check credentials in the cluster secret:
```bash
kubectl get secret <release-name>-postgresql-app -o jsonpath='{.data.username}' | base64 -d
```

### Issue: Image pull failures
**Problem:** Can't pull CloudNativePG image  
**Solution:** Ensure you have access to ghcr.io or use a mirror:
```yaml
postgresql:
  imageName: your-registry.com/postgresql:17.2
```

## Support

- CloudNativePG Docs: https://cloudnative-pg.io/documentation/
- GitHub Issues: https://github.com/cloudnative-pg/cloudnative-pg/issues
- Slack: https://cloudnativepg.slack.com/

## Rollback

If you need to rollback to Bitnami (temporarily):

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: 16.7.27
    repository: "https://charts.bitnami.com/bitnami"
    condition: database.postgres.enabled
```

Note: Bitnami charts may become unavailable, so this is not a long-term solution.
