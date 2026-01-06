# oxy-app

![Version: 0.3.3](https://img.shields.io/badge/Version-0.3.3-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.4.4](https://img.shields.io/badge/AppVersion-0.4.4-informational?style=flat-square)

A Helm chart for Oxy application deployment on kubernetes

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Oxy Team | <hello@oxy.tech> |  |
| Luong Vo | <luong@oxy.tech> |  |

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://groundhog2k.github.io/helm-charts/ | postgres | 1.6.1 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| app.command | list | `[]` |  |
| app.image | string | `"ghcr.io/oxy-hq/oxy"` |  |
| app.imagePullPolicy | string | `"IfNotPresent"` |  |
| app.imageTag | string | `""` |  |
| app.port | int | `3000` |  |
| app.replicaCount | int | `1` |  |
| configMap.data | object | `{}` |  |
| configMap.enabled | bool | `false` |  |
| database.external.connectionString | string | `""` |  |
| database.external.dataWarehouseSecret.backend | string | `""` |  |
| database.external.dataWarehouseSecret.key | string | `""` |  |
| database.external.dataWarehouseSecret.path | string | `""` |  |
| database.external.database | string | `""` |  |
| database.external.enabled | bool | `false` |  |
| database.external.envSecret.backend | string | `""` |  |
| database.external.envSecret.key | string | `""` |  |
| database.external.envSecret.path | string | `""` |  |
| database.external.host | string | `""` |  |
| database.external.password | string | `""` |  |
| database.external.port | int | `5432` |  |
| database.external.storeRef.kind | string | `"SecretStore"` |  |
| database.external.storeRef.name | string | `""` |  |
| database.external.user | string | `""` |  |
| database.postgres.enabled | bool | `false` |  |
| database.postgres.host | string | `""` |  |
| database.postgres.port | int | `5432` |  |
| env.OXY_DATABASE_URL | string | `""` |  |
| env.OXY_STATE_DIR | string | `"/workspace/oxy_data"` |  |
| externalSecrets.create | bool | `false` |  |
| externalSecrets.envSecretMappings | object | `{}` |  |
| externalSecrets.envSecretNames | list | `[]` |  |
| externalSecrets.fileSecrets | list | `[]` |  |
| externalSecrets.storeRef.kind | string | `""` |  |
| externalSecrets.storeRef.name | string | `""` |  |
| extraInitContainers | list | `[]` |  |
| extraSidecars | list | `[]` |  |
| gitSync.branch | string | `"main"` |  |
| gitSync.enabled | bool | `false` |  |
| gitSync.githubApp.applicationId | string | `""` |  |
| gitSync.githubApp.applicationIdKey | string | `"github_app_application_id"` |  |
| gitSync.githubApp.baseUrl | string | `"https://api.github.com"` |  |
| gitSync.githubApp.baseUrlKey | string | `"github_app_base_url"` |  |
| gitSync.githubApp.clientId | string | `""` |  |
| gitSync.githubApp.clientIdKey | string | `"github_app_client_id"` |  |
| gitSync.githubApp.installationId | string | `""` |  |
| gitSync.githubApp.installationIdKey | string | `"github_app_installation_id"` |  |
| gitSync.githubApp.privateKey | string | `""` |  |
| gitSync.githubApp.privateKeyKey | string | `"github_app_private_key"` |  |
| gitSync.githubApp.secretName | string | `""` |  |
| gitSync.imagePullPolicy | string | `"IfNotPresent"` |  |
| gitSync.link | string | `""` |  |
| gitSync.period | string | `"15s"` |  |
| gitSync.repository | string | `""` |  |
| gitSync.root | string | `""` |  |
| gitSync.sshSecretName | string | `"oxy-git-ssh"` |  |
| headlessService.enabled | bool | `true` |  |
| httpAuth.password | string | `""` |  |
| httpAuth.passwordKey | string | `"password"` |  |
| httpAuth.secretName | string | `""` |  |
| httpAuth.username | string | `""` |  |
| ingress.annotations | object | `{}` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"chart-example.local"` |  |
| ingress.hosts[0].paths | list | `[]` |  |
| ingress.ingressClassName | string | `""` |  |
| ingress.path | string | `"/"` |  |
| ingress.pathType | string | `"Prefix"` |  |
| ingress.tls | list | `[]` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | int | `3000` |  |
| livenessProbe.initialDelaySeconds | int | `10` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.timeoutSeconds | int | `10` |  |
| name | string | `"oxy-app"` |  |
| nodeSelector | string | `nil` |  |
| pdb.enabled | bool | `false` |  |
| pdb.maxUnavailable | string | `""` |  |
| pdb.minAvailable | string | `""` |  |
| pdb.selector | object | `{}` |  |
| persistence.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.annotations | object | `{}` |  |
| persistence.enabled | bool | `true` |  |
| persistence.folder | string | `"oxy_data"` |  |
| persistence.labels | object | `{}` |  |
| persistence.mountPath | string | `"/workspace"` |  |
| persistence.selector | object | `{}` |  |
| persistence.size | string | `"20Gi"` |  |
| persistence.storageClassName | string | `""` |  |
| persistence.volumeMode | string | `"Filesystem"` |  |
| postgres.fullnameOverride | string | `""` |  |
| postgres.settings.superuserPassword.value | string | `"postgres"` |  |
| postgres.storage.className | string | `""` |  |
| postgres.storage.requestedSize | string | `"8Gi"` |  |
| postgres.userDatabase.name.value | string | `"postgres"` |  |
| postgres.userDatabase.password.value | string | `"postgres"` |  |
| postgres.userDatabase.user.value | string | `"postgres"` |  |
| readinessProbe.failureThreshold | int | `3` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | int | `3000` |  |
| readinessProbe.initialDelaySeconds | int | `10` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.timeoutSeconds | int | `5` |  |
| resources.limits.cpu | string | `"1000m"` |  |
| resources.limits.memory | string | `"2Gi"` |  |
| resources.requests.cpu | string | `"250m"` |  |
| resources.requests.memory | string | `"512Mi"` |  |
| securityContext.fsGroup | int | `1000` |  |
| semanticEngine.enabled | bool | `false` |  |
| semanticEngine.image | string | `"ghcr.io/oxy-hq/oxy-semantic-engine"` |  |
| semanticEngine.imagePullPolicy | string | `"IfNotPresent"` |  |
| semanticEngine.imageTag | string | `""` |  |
| service.name | string | `""` |  |
| service.port | int | `80` |  |
| service.targetPort | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| sshKey.knownHosts | string | `""` |  |
| sshKey.privateKey | string | `""` |  |
| sshKey.secretName | string | `""` |  |
| tolerations | string | `nil` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
