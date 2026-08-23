# oxy

![Version: 1.0.0](https://img.shields.io/badge/Version-1.0.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.5.49](https://img.shields.io/badge/AppVersion-0.5.49-informational?style=flat-square)

Deploys only the Oxy application workloads — the ide StatefulSet, the stateless serve and worker fleets, and the pre-upgrade migrate Job. Postgres, ClickHouse and Airhouse are external — managed outside this chart (RDS/CNPG, the ClickHouse operator, the airhouse chart) and wired in via connection env vars (OXY_DATABASE_*, OXY_CLICKHOUSE_*, AIRHOUSE_*). No bundled databases, no subchart dependencies.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Oxy Team | <hello@oxy.tech> |  |
| Luong Vo | <luong@oxy.tech> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| app.args | list | `[]` | Override the container args. Overrides the image CMD only, so the image ENTRYPOINT (tini) stays PID 1 and reaps orphans. Setting both renders both, per normal Kubernetes semantics. |
| app.command | list | `[]` | Override the container command. Replaces the image ENTRYPOINT — prefer `app.args`. |
| app.image | string | `"ghcr.io/oxy-hq/oxygen"` |  |
| app.imagePullPolicy | string | `"IfNotPresent"` |  |
| app.imageTag | string | `""` |  |
| app.internalHost | string | `""` |  |
| app.internalPort | int | `3001` |  |
| app.port | int | `3000` |  |
| appServer.inprocGlobalWorker | bool | `false` |  |
| compileBoundary.blobS3Bucket | string | `""` |  |
| configMap.data | object | `{}` |  |
| configMap.enabled | bool | `false` |  |
| encryptionKey.secretKey | string | `"OXY_ENCRYPTION_KEY"` |  |
| encryptionKey.secretName | string | `""` |  |
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
| extraVolumeMounts | list | `[]` |  |
| extraVolumes | list | `[]` |  |
| headlessService.enabled | bool | `true` |  |
| ideRoutes | list | `[{"path":"/ide"},{"path":"/ide/*"},{"path":"/api/*/files"},{"path":"/api/*/files/*"},{"path":"/api/*/compile"},{"path":"/api/*/compile/*"},{"path":"/api/*/branches"},{"path":"/api/*/branches/*"},{"path":"/api/*/switch-branch"},{"path":"/api/*/pull-changes"},{"path":"/api/*/fetch"},{"path":"/api/*/push-changes"},{"path":"/api/*/force-push"},{"path":"/api/*/discard-all"},{"path":"/api/*/abort-rebase"},{"path":"/api/*/continue-rebase"},{"path":"/api/*/resolve-conflict-file"},{"path":"/api/*/unresolve-conflict-file"},{"path":"/api/*/resolve-conflict-with-content"},{"path":"/api/*/reset-to-commit"},{"path":"/api/*/recent-commits"},{"path":"/api/*/revision-info"},{"path":"/api/*/repositories"},{"path":"/api/*/repositories/*"},{"path":"/api/*/onboarding"},{"path":"/api/*/onboarding/*"},{"path":"/api/*/onboarding-readiness"},{"path":"/api/*/modeling/*"},{"path":"/api/orgs/*/onboarding/demo"},{"path":"/api/orgs/*/onboarding/new"},{"path":"/api/orgs/*/onboarding/github"},{"path":"/api/*/events"},{"path":"/api/*/events/*"},{"path":"/api/*/world-model/events"}]` | ------------------------------------------------------------------------- Opt-in stateless HTTP Deployment that serves the compile-boundary read paths (customer-apps, external API, runtime serving) without touching the workspace filesystem. The existing StatefulSet stays as the singleton `oxy-ide` that owns working copies + file CRUD + git ops + the IDE Compile button. The two fleets share the same Postgres.  Topology when enabled:   - oxy-ide (StatefulSet, replicas=1): IDE / files / git / compile   - oxy-serve (Deployment, this stanza, replicas=N): everything that     only needs Postgres — customer-apps, external API, chat, admin, and     the runtime read paths (apps, procedures, agents, semantic). The     compile boundary is always-on (no per-surface flags).   - oxy-worker (Deployment, see `worker` stanza): TaskSpec consumers.  Enabled by default (prod-style HA). Set `serveFleet.enabled: false` to render no oxy-serve resources and fall back to single-StatefulSet behaviour.  Ingress routing:   - Legacy (additive) mode: `ideRoutes` empty → catch-all `/` stays on     the StatefulSet and `serveFleet.ingressPaths` peel off to oxy-serve.     Used during the initial HA-split rollout; safest, smallest blast     radius, but blocked from reaching the workspace-scoped tree     because `/api/{workspace_id}/...` can't be peeled by prefix match.   - Inverse mode: `ideRoutes` non-empty → catch-all `/` flips to     oxy-serve, and only the IdeOnly patterns in `ideRoutes` peel off     to the StatefulSet. This is the path to reach the original goal of     "only filesystem-touching surfaces live on oxy-ide". Patterns use     `pathType: ImplementationSpecific` so mid-segment wildcards like     `/api/*/files` work natively on AWS ALB. See `ideRoutes` below. The app-layer `OXY_ROLE` guardrail (returns 421 + `X-Oxy-Required-Role` when a request lands on the wrong fleet) is the actual safety net; ingress routing is an optimization on top.  ── REQUIRED config for the compile boundary ─────────────────────────── The stateless fleet can ONLY serve a workspace that has been compiled (it has no working copy to fall back to). So compiles MUST drain — set `appServer.inprocGlobalWorker: true` so the StatefulSet drives them. The `oxy worker` fleet does NOT compile (no working copy; per-worker clone-on-demand is a later phase). For S3 offload + DuckDB-on-fleet, set `compileBoundary.blobS3Bucket`. After deploy, compile existing workspaces once via the admin "Compile all uncompiled" backfill. ── IdeOnly route override (inverse routing) ───────────────────────────── When `serveFleet.enabled: true` AND this list is non-empty, the Ingress flips: catch-all `/` → oxy-serve, and ONLY the patterns below peel off to the singleton StatefulSet (oxy-ide). The default list mirrors the `IdeOnly` entries in `crates/app/src/server/role_manifest.rs` — surfaces that touch the workspace filesystem or `.git`. Operators normally do NOT need to set this from the workload values file; bump the chart `appVersion` when the role manifest changes upstream.  Each entry: `{path, pathType?}`. `pathType` defaults to `ImplementationSpecific` so mid-segment wildcards work on AWS ALB; override with `Prefix` for left-anchored paths if you prefer.  Set `ideRoutes: []` from the workload values to fall back to legacy additive routing (catch-all → StatefulSet; `serveFleet.ingressPaths` peeled to serve fleet).  Caveats — both benign in practice because the app-layer `OXY_ROLE` guardrail catches misroutes with a 421:   - ALB wildcards are greedy across slashes, so `/api/?/files` (with     the asterisk pattern) also matches `/api/a/b/files`. No such     paths exist today.   - A handful of GETs under an IdeOnly subtree (e.g.     `GET /api/{ws}/compile/status`) are FleetOk in the manifest but     land on `ide` here. Harmless — `ide` accepts FleetOk. |
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
| migrations.backoffLimit | int | `3` |  |
| migrations.enabled | bool | `true` |  |
| migrations.image.pullPolicy | string | `""` |  |
| migrations.image.repository | string | `""` |  |
| migrations.image.tag | string | `""` |  |
| migrations.podSecurityContext | object | `{}` |  |
| migrations.resources.limits.memory | string | `"1Gi"` |  |
| migrations.resources.requests.cpu | string | `"100m"` |  |
| migrations.resources.requests.memory | string | `"256Mi"` |  |
| migrations.serviceAccountName | string | `""` |  |
| minReadySeconds | int | `0` |  |
| name | string | `"oxy-app"` |  |
| nameOverride | string | `"oxy-app"` |  |
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
| serveFleet.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchLabels."app.kubernetes.io/component" | string | `"serve"` |  |
| serveFleet.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.topologyKey | string | `"kubernetes.io/hostname"` |  |
| serveFleet.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight | int | `100` |  |
| serveFleet.args | list | `[]` | Override the container args, keeping the image ENTRYPOINT. Setting both renders both, per normal Kubernetes semantics. |
| serveFleet.command | list | `[]` | Override the container command. Replaces the image ENTRYPOINT — prefer `serveFleet.args`. |
| serveFleet.containerSecurityContext | object | `{}` |  |
| serveFleet.enabled | bool | `true` |  |
| serveFleet.env | object | `{}` |  |
| serveFleet.extraEnv | list | `[]` |  |
| serveFleet.extraEnvFrom | list | `[]` |  |
| serveFleet.ideUpstream | string | `""` |  |
| serveFleet.image.pullPolicy | string | `""` |  |
| serveFleet.image.repository | string | `""` |  |
| serveFleet.image.tag | string | `""` |  |
| serveFleet.lifecycle.preStop.exec.command[0] | string | `"sleep"` |  |
| serveFleet.lifecycle.preStop.exec.command[1] | string | `"5"` |  |
| serveFleet.livenessProbe.httpGet.path | string | `"/api/live"` |  |
| serveFleet.livenessProbe.httpGet.port | int | `3000` |  |
| serveFleet.livenessProbe.initialDelaySeconds | int | `15` |  |
| serveFleet.livenessProbe.periodSeconds | int | `10` |  |
| serveFleet.nodeSelector | object | `{}` |  |
| serveFleet.podAnnotations | object | `{}` |  |
| serveFleet.podDisruptionBudget.enabled | bool | `true` |  |
| serveFleet.podDisruptionBudget.minAvailable | int | `1` |  |
| serveFleet.podLabels | object | `{}` |  |
| serveFleet.readinessProbe.httpGet.path | string | `"/api/ready"` |  |
| serveFleet.readinessProbe.httpGet.port | int | `3000` |  |
| serveFleet.readinessProbe.initialDelaySeconds | int | `5` |  |
| serveFleet.readinessProbe.periodSeconds | int | `5` |  |
| serveFleet.replicaCount | int | `2` |  |
| serveFleet.resources.limits.cpu | int | `1` |  |
| serveFleet.resources.limits.memory | string | `"1Gi"` |  |
| serveFleet.resources.requests.cpu | string | `"100m"` |  |
| serveFleet.resources.requests.memory | string | `"256Mi"` |  |
| serveFleet.securityContext | object | `{}` |  |
| serveFleet.service.annotations | object | `{}` |  |
| serveFleet.service.port | int | `80` |  |
| serveFleet.service.targetPort | int | `3000` |  |
| serveFleet.service.type | string | `"ClusterIP"` |  |
| serveFleet.serviceAccountName | string | `""` |  |
| serveFleet.stateDir | string | `"/var/lib/oxy"` |  |
| serveFleet.strategy.rollingUpdate.maxSurge | string | `"50%"` |  |
| serveFleet.strategy.rollingUpdate.maxUnavailable | int | `1` |  |
| serveFleet.strategy.type | string | `"RollingUpdate"` |  |
| serveFleet.terminationGracePeriodSeconds | int | `30` |  |
| serveFleet.tolerations | list | `[]` |  |
| service.internalPort | int | `3001` |  |
| service.name | string | `""` |  |
| service.port | int | `80` |  |
| service.targetPort | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| terminationGracePeriodSeconds | int | `30` |  |
| tolerations | string | `nil` |  |
| worker.affinity | object | `{}` |  |
| worker.args | list | `[]` | Override the container args, keeping the image ENTRYPOINT. Setting both renders both, per normal Kubernetes semantics. |
| worker.command | list | `[]` | Override the container command. Replaces the image ENTRYPOINT — prefer `worker.args`. |
| worker.containerSecurityContext | object | `{}` |  |
| worker.enabled | bool | `true` |  |
| worker.env.OXY_WORKER_MAX_INFLIGHT | string | `"32"` |  |
| worker.env.OXY_WORKER_RECOVERY_INTERVAL_SECS | string | `"30"` |  |
| worker.extraEnv | list | `[]` |  |
| worker.extraEnvFrom | list | `[]` |  |
| worker.extraSidecars | list | `[]` |  |
| worker.extraVolumeMounts | list | `[]` |  |
| worker.extraVolumes | list | `[]` |  |
| worker.healthPort | int | `8081` |  |
| worker.hpa.behavior | object | `{}` |  |
| worker.hpa.cpuUtilization | int | `0` |  |
| worker.hpa.enabled | bool | `false` |  |
| worker.hpa.maxReplicas | int | `10` |  |
| worker.hpa.metricName | string | `"oxy_agentic_task_queue_depth"` |  |
| worker.hpa.minReplicas | int | `2` |  |
| worker.hpa.queueDepthThreshold | int | `100` |  |
| worker.image.pullPolicy | string | `""` |  |
| worker.image.repository | string | `""` |  |
| worker.image.tag | string | `""` |  |
| worker.inheritExternalSecrets | bool | `true` |  |
| worker.lifecycle | object | `{}` |  |
| worker.livenessProbe.failureThreshold | int | `3` |  |
| worker.livenessProbe.httpGet.path | string | `"/healthz"` |  |
| worker.livenessProbe.httpGet.port | int | `8081` |  |
| worker.livenessProbe.initialDelaySeconds | int | `5` |  |
| worker.livenessProbe.periodSeconds | int | `30` |  |
| worker.livenessProbe.timeoutSeconds | int | `5` |  |
| worker.nodeSelector | object | `{}` |  |
| worker.pdb.enabled | bool | `true` |  |
| worker.pdb.maxUnavailable | string | `""` |  |
| worker.pdb.minAvailable | int | `1` |  |
| worker.podAnnotations | object | `{}` |  |
| worker.podLabels | object | `{}` |  |
| worker.readinessProbe.failureThreshold | int | `3` |  |
| worker.readinessProbe.httpGet.path | string | `"/readyz"` |  |
| worker.readinessProbe.httpGet.port | int | `8081` |  |
| worker.readinessProbe.initialDelaySeconds | int | `5` |  |
| worker.readinessProbe.periodSeconds | int | `5` |  |
| worker.readinessProbe.timeoutSeconds | int | `5` |  |
| worker.replicaCount | int | `2` |  |
| worker.resources.limits.cpu | string | `"1"` |  |
| worker.resources.limits.memory | string | `"1Gi"` |  |
| worker.resources.requests.cpu | string | `"250m"` |  |
| worker.resources.requests.memory | string | `"512Mi"` |  |
| worker.securityContext.fsGroup | int | `1000` |  |
| worker.service.annotations | object | `{}` |  |
| worker.service.enabled | bool | `true` |  |
| worker.service.port | int | `8081` |  |
| worker.service.type | string | `"ClusterIP"` |  |
| worker.serviceAccountName | string | `""` |  |
| worker.skipMigrations | bool | `true` |  |
| worker.terminationGracePeriodSeconds | int | `40` |  |
| worker.tolerations | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
