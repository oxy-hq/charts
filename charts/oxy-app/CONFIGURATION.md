# oxy-app

![Version: 0.4.1](https://img.shields.io/badge/Version-0.4.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.5.19](https://img.shields.io/badge/AppVersion-0.5.19-informational?style=flat-square)

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
| oci://registry-1.docker.io/bitnamicharts | clickhouseSubchart(clickhouse) | 9.4.4 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| app.command | list | `[]` |  |
| app.image | string | `"ghcr.io/oxy-hq/oxy"` |  |
| app.imagePullPolicy | string | `"IfNotPresent"` |  |
| app.imageTag | string | `""` |  |
| app.internalHost | string | `""` |  |
| app.internalPort | int | `3001` |  |
| app.port | int | `3000` |  |
| app.replicaCount | int | `1` |  |
| clickhouse.database | string | `"otel"` |  |
| clickhouse.enabled | bool | `false` |  |
| clickhouse.existingSecret.name | string | `""` |  |
| clickhouse.existingSecret.passwordKey | string | `"password"` |  |
| clickhouse.existingSecret.usernameKey | string | `"username"` |  |
| clickhouse.password | string | `""` |  |
| clickhouse.tcpEndpoint | string | `""` |  |
| clickhouse.url | string | `""` |  |
| clickhouse.username | string | `"default"` |  |
| clickhouseSubchart.auth.existingSecret | string | `""` |  |
| clickhouseSubchart.auth.existingSecretPasswordKey | string | `"password"` |  |
| clickhouseSubchart.auth.password | string | `"clickhouse"` |  |
| clickhouseSubchart.auth.username | string | `"default"` |  |
| clickhouseSubchart.fullnameOverride | string | `""` |  |
| clickhouseSubchart.image.repository | string | `"bitnamilegacy/clickhouse"` |  |
| clickhouseSubchart.keeper.enabled | bool | `true` |  |
| clickhouseSubchart.keeper.image.repository | string | `"bitnamilegacy/clickhouse-keeper"` |  |
| clickhouseSubchart.persistence.enabled | bool | `true` |  |
| clickhouseSubchart.persistence.size | string | `"10Gi"` |  |
| clickhouseSubchart.persistence.storageClass | string | `""` |  |
| clickhouseSubchart.replicaCount | int | `1` |  |
| clickhouseSubchart.resources.limits.cpu | string | `"1000m"` |  |
| clickhouseSubchart.resources.limits.memory | string | `"2Gi"` |  |
| clickhouseSubchart.resources.requests.cpu | string | `"250m"` |  |
| clickhouseSubchart.resources.requests.memory | string | `"512Mi"` |  |
| clickhouseSubchart.shards | int | `1` |  |
| clickhouseSubchart.zookeeper.enabled | bool | `false` |  |
| clickhouseSubchart.zookeeper.image.repository | string | `"bitnamilegacy/zookeeper"` |  |
| configMap.data | object | `{}` |  |
| configMap.enabled | bool | `false` |  |
| database.clickhouse.enabled | bool | `false` |  |
| database.clickhouse.host | string | `""` |  |
| database.clickhouse.httpPort | int | `8123` |  |
| database.clickhouse.tcpPort | int | `9000` |  |
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
| gitSync.workingDir | string | `""` |  |
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
| lifecycle.preStop.exec.command[0] | string | `"sleep"` |  |
| lifecycle.preStop.exec.command[1] | string | `"5"` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | int | `3000` |  |
| livenessProbe.initialDelaySeconds | int | `10` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.timeoutSeconds | int | `10` |  |
| name | string | `"oxy-app"` |  |
| nodeSelector | string | `nil` |  |
| otelCollector.clickhouse.asyncInsert | bool | `true` |  |
| otelCollector.clickhouse.compress | string | `"lz4"` |  |
| otelCollector.clickhouse.createSchema | bool | `true` |  |
| otelCollector.clickhouse.database | string | `""` |  |
| otelCollector.clickhouse.enabled | bool | `true` |  |
| otelCollector.clickhouse.endpoint | string | `""` |  |
| otelCollector.clickhouse.logsTableName | string | `"otel_logs"` |  |
| otelCollector.clickhouse.metricsTableName | string | `"otel_metrics"` |  |
| otelCollector.clickhouse.password | string | `""` |  |
| otelCollector.clickhouse.retry.enabled | bool | `true` |  |
| otelCollector.clickhouse.retry.initialInterval | string | `"5s"` |  |
| otelCollector.clickhouse.retry.maxElapsedTime | string | `"300s"` |  |
| otelCollector.clickhouse.retry.maxInterval | string | `"30s"` |  |
| otelCollector.clickhouse.timeout | string | `"5s"` |  |
| otelCollector.clickhouse.tracesTableName | string | `"otel_traces"` |  |
| otelCollector.clickhouse.ttl | string | `"72h"` |  |
| otelCollector.clickhouse.username | string | `""` |  |
| otelCollector.debug.enabled | bool | `false` |  |
| otelCollector.debug.verbosity | string | `"detailed"` |  |
| otelCollector.enabled | bool | `false` |  |
| otelCollector.image | string | `"otel/opentelemetry-collector-contrib"` |  |
| otelCollector.imagePullPolicy | string | `"IfNotPresent"` |  |
| otelCollector.imageTag | string | `"latest"` |  |
| otelCollector.ports.metrics | int | `8888` |  |
| otelCollector.ports.otlpGrpc | int | `4317` |  |
| otelCollector.ports.otlpHttp | int | `4318` |  |
| otelCollector.processors.batch.sendBatchMaxSize | int | `1000` |  |
| otelCollector.processors.batch.sendBatchSize | int | `100` |  |
| otelCollector.processors.batch.timeout | string | `"10s"` |  |
| otelCollector.processors.memoryLimiter.checkInterval | string | `"1s"` |  |
| otelCollector.processors.memoryLimiter.limitMib | int | `512` |  |
| otelCollector.resources.limits.cpu | string | `"500m"` |  |
| otelCollector.resources.limits.memory | string | `"512Mi"` |  |
| otelCollector.resources.requests.cpu | string | `"100m"` |  |
| otelCollector.resources.requests.memory | string | `"128Mi"` |  |
| otelCollector.telemetry.logs.level | string | `"info"` |  |
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
| service.internalPort | int | `3001` |  |
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
| terminationGracePeriodSeconds | int | `30` |  |
| tolerations | string | `nil` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
