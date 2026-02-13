# oxy-start

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.5.16](https://img.shields.io/badge/AppVersion-0.5.16-informational?style=flat-square)

Oxy with Docker-in-Docker — self-contained deployment using `oxy start` to manage all services internally

**Homepage:** <https://oxy.tech>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Oxy Team |  | <https://oxy.tech> |
| Luong Vo |  | <https://github.com/luongvo> |

## Source Code

* <https://github.com/oxy-hq/charts>

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
| configMap.data | object | `{}` |  |
| configMap.enabled | bool | `false` |  |
| dind.enabled | bool | `true` |  |
| dind.image | string | `"docker"` |  |
| dind.imagePullPolicy | string | `"IfNotPresent"` |  |
| dind.imageTag | string | `"27-dind"` |  |
| dind.resources.limits.cpu | string | `"2000m"` |  |
| dind.resources.limits.memory | string | `"4Gi"` |  |
| dind.resources.requests.cpu | string | `"500m"` |  |
| dind.resources.requests.memory | string | `"1Gi"` |  |
| dind.storageClassName | string | `""` |  |
| dind.storageSize | string | `"40Gi"` |  |
| env.OXY_STATE_DIR | string | `"/workspace/oxy_data"` |  |
| externalSecrets.create | bool | `false` |  |
| externalSecrets.envSecretMappings | object | `{}` |  |
| externalSecrets.envSecretNames | list | `[]` |  |
| externalSecrets.fileSecrets | list | `[]` |  |
| externalSecrets.storeRef.kind | string | `""` |  |
| externalSecrets.storeRef.name | string | `""` |  |
| extraInitContainers | list | `[]` |  |
| extraSidecars | list | `[]` |  |
| fullnameOverride | string | `""` |  |
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
| livenessProbe.failureThreshold | int | `5` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | int | `3000` |  |
| livenessProbe.initialDelaySeconds | int | `60` |  |
| livenessProbe.periodSeconds | int | `30` |  |
| livenessProbe.timeoutSeconds | int | `10` |  |
| name | string | `"oxy-start"` |  |
| nameOverride | string | `""` |  |
| nodeSelector | string | `nil` |  |
| oxyStart.clean | bool | `false` |  |
| oxyStart.enterprise | bool | `false` |  |
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
| readinessProbe.failureThreshold | int | `5` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | int | `3000` |  |
| readinessProbe.initialDelaySeconds | int | `60` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.timeoutSeconds | int | `5` |  |
| resources.limits.cpu | string | `"1000m"` |  |
| resources.limits.memory | string | `"2Gi"` |  |
| resources.requests.cpu | string | `"250m"` |  |
| resources.requests.memory | string | `"512Mi"` |  |
| securityContext.fsGroup | int | `1000` |  |
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
| tolerations | string | `nil` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
