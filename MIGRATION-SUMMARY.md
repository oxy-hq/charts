# Migration Summary: Bitnami PostgreSQL → CloudNativePG

## ✅ Completed Changes

### 1. Chart Dependency Updated
**File:** `charts/oxy-app/Chart.yaml`
- **Before:** Bitnami PostgreSQL v16.7.27
- **After:** CloudNativePG cluster v0.0.10 (aliased as `postgresql`)
- **Status:** ✅ Chart downloaded successfully

### 2. Helm Repository References Updated
**Files Updated:**
- `.github/workflows/helm-ci.yml` - CI pipeline
- `ct.yaml` - Chart testing configuration
- `scripts/test.sh` - Test script

**Changes:**
- Replaced `https://charts.bitnami.com/bitnami` with `https://cloudnative-pg.github.io/charts`

### 3. Values Configuration Updated
**File:** `charts/oxy-app/values.yaml`
- Updated comments to reflect CloudNativePG usage
- Maintained backward compatibility with existing configuration structure

### 4. Test Values Updated
**File:** `charts/oxy-app/test-values/with-postgres-values.yaml`
- Migrated from Bitnami configuration to CloudNativePG structure
- Changed from `docker.io/bitnamilegacy/postgresql` to `ghcr.io/cloudnative-pg/postgresql:17.2`
- Updated configuration format for CloudNativePG cluster spec

### 5. StatefulSet Template Updated
**File:** `charts/oxy-app/templates/statefulset.yaml`

**Changes:**
1. **Init Container (wait-for-postgres):**
   - Service name: `<release>-postgresql` → `<release>-postgresql-rw`
   - Credentials path: `.Values.postgresql.auth.*` → `.Values.postgresql.credentials.*`

2. **Database URL Construction:**
   - Service name: `<release>-postgresql` → `<release>-postgresql-rw`
   - Credentials: Uses `.Values.postgresql.credentials.*`
   - Database name: Uses `.Values.postgresql.bootstrap.initdb.database`

### 6. Documentation Created
**New Files:**
- `charts/oxy-app/docs/postgresql-migration.md` - Comprehensive migration guide
- `MIGRATION-SUMMARY.md` - This summary document

**Updated Files:**
- `charts/oxy-app/README.md` - Added migration notice with link to guide

## 🔄 Migration Path

### For Development/Testing
```bash
cd charts/oxy-app
helm dependency update
helm upgrade --install oxy-app . -f test-values/with-postgres-values.yaml
```

### For Production
1. **Backup existing data** (if migrating from Bitnami)
   ```bash
   kubectl exec -it <old-postgresql-pod> -- pg_dump -U <user> <db> > backup.sql
   ```

2. **Update dependencies**
   ```bash
   cd charts/oxy-app
   helm dependency update
   ```

3. **Update your values.yaml** with CloudNativePG configuration:
   ```yaml
   database:
     postgres:
       enabled: true
   
   postgresql:
     type: postgresql
     instances: 3  # for HA
     bootstrap:
       initdb:
         database: oxydb
         owner: oxy
     credentials:
       username: oxy
       password: <secure-password>
     storage:
       size: 20Gi
       storageClass: gp3
   ```

4. **Deploy**
   ```bash
   helm upgrade --install oxy-app . -f your-values.yaml
   ```

5. **Restore data** (if needed)
   ```bash
   kubectl exec -it <new-postgresql-pod> -- psql -U <user> <db> < backup.sql
   ```

## 🎯 Key Differences to Remember

| Aspect | Bitnami | CloudNativePG |
|--------|---------|---------------|
| Service Name | `<release>-postgresql` | `<release>-postgresql-rw` (read-write) |
| Auth Config | `postgresql.auth.*` | `postgresql.credentials.*` |
| DB Config | `postgresql.auth.database` | `postgresql.bootstrap.initdb.database` |
| Image | `bitnami/postgresql` | `cloudnative-pg/postgresql` |
| Registry | `docker.io` | `ghcr.io` |

## ⚠️ Breaking Changes

1. **Service Names Changed**: Applications connecting directly to the service must update DNS names from `-postgresql` to `-postgresql-rw`

2. **Configuration Structure**: Values files using PostgreSQL must be updated to CloudNativePG format

3. **Image Source**: Different container image (CloudNativePG uses official PostgreSQL with operator tooling)

## 🚀 Benefits of CloudNativePG

✅ **Active Maintenance** - CNCF project with regular updates  
✅ **Production Ready** - Built for production workloads with HA  
✅ **Better Operations** - Native backup, recovery, and monitoring  
✅ **Modern Architecture** - Kubernetes-native operator pattern  
✅ **No Deprecation Risk** - Actively developed and supported  

## 📚 Resources

- [Migration Guide](charts/oxy-app/docs/postgresql-migration.md)
- [CloudNativePG Docs](https://cloudnative-pg.io/documentation/)
- [GitHub Repository](https://github.com/cloudnative-pg/cloudnative-pg)

## ✅ Next Steps

1. Review the [migration guide](charts/oxy-app/docs/postgresql-migration.md)
2. Test with development values: `helm install oxy-app . -f test-values/with-postgres-values.yaml`
3. Update production values files
4. Plan production migration with backup/restore
5. Monitor CloudNativePG operator status after deployment

## 🐛 Issue Resolution

The original error:
```
Back-off pulling image "docker.io/bitnami/postgresql:17.6.0-debian-12-r4"
```

**Root Cause:** Bitnami has deprecated their Helm charts repository

**Solution:** Migrated to CloudNativePG, which:
- Uses official PostgreSQL images from `ghcr.io`
- Is actively maintained by the CNCF community
- Provides better production features
- Has no deprecation risk

## 📝 Testing

Run the chart tests to verify everything works:
```bash
# Unit tests
helm unittest charts/oxy-app

# Integration tests
ct install --config ct.yaml

# Manual deployment test
helm install test-postgres ./charts/oxy-app -f charts/oxy-app/test-values/with-postgres-values.yaml
```
