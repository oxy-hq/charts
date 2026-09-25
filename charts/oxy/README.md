# oxy

Helm chart for the **Oxy application workloads** — the single-writer `ide`
StatefulSet, the stateless `serve` and `worker` fleets, and the pre-upgrade
`migrate` Job, plus their Services / Ingress / PDBs / ServiceAccount /
ExternalSecrets.

It deploys **no databases**. Postgres, ClickHouse and Airhouse are external —
managed outside this chart (RDS / CloudNativePG, the ClickHouse operator, the
airhouse chart) and reached purely over the network via connection env vars.
This is the standalone successor to the `oxy-app` chart with the bundled
`postgres` / `clickhouse` subcharts removed.

This is a **cloud-only** chart: there is no local / git-sync mode (the app
serves workspace definitions from Postgres, not a cloned working tree) and no
in-process-worker toggle — the `ide` always runs its in-process workers.

## Topology

The default is the **prod-style HA topology**: one `ide` StatefulSet (single
writer, owns the `/workspace` RWO volume and drives the compile boundary) + N
stateless `serve` replicas (`oxy serve --no-workers`, serving the compiled read
paths) + a `worker` fleet draining the durable task queue. All fleets share the
same external Postgres. Set `serveFleet.enabled: false` and
`worker.enabled: false` for a single-instance install where the `ide`
StatefulSet handles every request and drains the queue in-process.

## Progressive delivery (`serveFleet.progressive`)

Opt-in, **off by default**, and off renders byte-identically to a chart without
it. On, an Argo Rollouts canary takes over the **serve fleet's** rollouts: a new
image first lands on a slice of the serve pods, the chart's `AnalysisTemplate`
measures *those pods'* 5xx ratio and p95 latency, and a bad image is aborted
automatically — canary scaled away, stable pods never touched. The `ide`
StatefulSet (single replica) and the worker fleet are not covered.

**Prerequisites** — each fails loudly or silently if skipped:

1. The Argo Rollouts controller and CRDs installed in the cluster. Without them
   `Rollout` is an unknown kind and the whole sync fails.
2. `serveFleet.metricsPort` set. The render fails without it.
3. `serveFleet.progressive.analysis.address` — a Prometheus-compatible query
   API (VictoriaMetrics serves one). The render fails without it.
4. A scrape of the metrics port that copies the pod label
   `rollouts-pod-template-hash` onto the series — with the VictoriaMetrics
   operator, `podTargetLabels: [rollouts-pod-template-hash]` on the
   `VMPodScrape`, which writes it as `rollouts_pod_template_hash`. **The chart
   cannot check this one.** Without it no series matches the canary, every
   measurement is Inconclusive and every rollout pauses for a human.

**Why `workloadRef`, not a replacement Rollout.** The Rollout carries no pod
template; it points at the existing serve Deployment, which stays the one place
the pod spec lives. When enabled, the chart stops declaring the Deployment's
`replicas` and the controller scales it down as the Rollout's pods turn Ready
(`scaleDown: progressively`). Replacing the Deployment with a templated Rollout
would delete it in the same sync that creates the Rollout, leaving the fleet
without a Ready endpoint while the new pods start (and wait on the ALB
readiness gate).

**What the flip does, once.** The undeclared `replicas` defaults to 1 the moment
the chart stops declaring it, so the fleet dips to one serving pod until the
Rollout's pods are Ready, then the Deployment goes to 0. It never reaches zero
serving pods. The Rollout's first revision is a straight scale-up — steps and
analysis apply from the first image change after it.

**Turning it off.** Set `enabled: false`. The Rollout carries ArgoCD's
`PruneLast`, so the Deployment regains its replicas and is Healthy before the
Rollout (and its pods) is deleted. Exception: while the Rollout is still on its
first revision (no canary has run since the flip), the controller is still
migrating and scales the Deployment straight back to 0 — set
`scaleDown: never`, sync, then disable.

**The analysis.** Both metrics read `http_server_request_duration_seconds`,
filtered to `job=<analysis.job>`, `namespace=<release namespace>` and
`<canaryHashLabel>="{{args.canary-hash}}"`, where Argo fills in the canary
ReplicaSet's pod-template hash per run. Stable pods carry a different hash, so
the canary is measured alone:

```promql
# error-rate: 5xx share of the canary's requests, health probes excluded
(
  sum(rate(http_server_request_duration_seconds_count{<sel>, http_response_status_code=~"5..", http_route!~"<errorRate.excludeRoutes>"}[<rateWindow>]))
  or vector(0)
)
/
sum(rate(http_server_request_duration_seconds_count{<sel>, http_route!~"<errorRate.excludeRoutes>"}[<rateWindow>]))

# latency-p95: streaming routes and probes excluded
histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{<sel>, http_route!~"<latencyP95.excludeRoutes>"}[<rateWindow>])))
```

- **No data is Inconclusive, not a pass and not an error.** Both conditions
  require a non-empty, non-NaN result, so a canary nobody sent traffic to
  neither passes nor fails. Past `inconclusiveLimit` the Rollout pauses for a
  human (`kubectl argo rollouts promote` / `abort`). Set `inconclusiveLimit`
  ≥ `count` to let a quiet canary through instead.
- **Query errors abort.** Past `consecutiveErrorLimit` (metrics backend down,
  bad PromQL) the analysis errors and the rollout aborts: a metrics outage
  blocks serve deploys rather than waving them through.
- **Pods that never become Ready** never reach an analysis step;
  `progressDeadlineAbort` aborts them after `progressDeadlineSeconds`.
- **`dryRun: true`** records every measurement without ever failing a rollout —
  calibrate the thresholds against real canaries with it first.

**Weights are replica-weighted** (no service mesh or traffic router): the
Service selects canary and stable pods alike, so a canary's traffic share is
its share of Ready pods. It is quantised by `replicaCount` (20% of 2 replicas
is 1 pod — up to half the new traffic) and skewed by load-balancer stickiness,
which keeps existing sessions on the pods they already have.

## Relationship to `oxy-app` (migration)

This chart renders **byte-identical Kubernetes objects** to `oxy-app` for the
external-DB value sets every environment uses (verified with `helm template`
diffs across dev / staging / prod — only the `helm.sh/chart` label and the
`# Source:` provenance comments differ). It is a **drop-in**:

- `nameOverride: oxy-app` (default) keeps every resource name identical
  (`<release>-oxy-app`), so there is **no StatefulSet/PVC rename** and no
  data-migration hazard. The internal template helpers are also kept under the
  `oxy-app.*` namespace, so existing values files render unchanged.
- **Adopt per environment** by pointing the pinned chart at `oxy` `1.0.0`
  (the `chartRevision` in the oxy-instances ApplicationSet, or `targetRevision`
  in the prod Application). **No values changes are required.** You may
  optionally delete the now-inert `clickhouse.enabled: false` line.

## Wiring external databases

Everything is env-driven (typically via `env:` + `externalSecrets`):

- **Postgres** — `OXY_DATABASE_URL` (URL mode) or the `OXY_DATABASE_*` vars
  (IAM mode: `OXY_DATABASE_AUTH_MODE`, `_HOST`, `_PORT`, `_NAME`, `_USER`,
  `_REGION`, `_SSL_MODE`).
- **ClickHouse** — `OXY_CLICKHOUSE_URL` / `_USER` / `_DATABASE` (+ password via
  an ExternalSecret listed in `externalSecrets.envSecretNames`).
- **Airhouse** — `AIRHOUSE_*`.

## Quick start (external Postgres)

```bash
helm install oxy ./charts/oxy -n oxy --create-namespace \
  --set env.OXY_DATABASE_URL="postgresql://user:pass@my-postgres:5432/oxydb"
```

Need an in-cluster database for local dev? Deploy it as its **own** release
(e.g. `helm install pg groundhog2k/postgres`) and point `env.OXY_DATABASE_URL`
at its Service. The chart deliberately does not couple the app's lifecycle to a
database's.

## Validation, testing, and CI

- `values.schema.json` enforces the input contract on `install` / `upgrade` /
  `lint` / `template` (permissive at the root so existing `oxy-app` value sets
  validate unchanged; tighten per-object over time).
- Unit tests (no cluster): `helm unittest ./charts/oxy` (helm-unittest). The
  suite is inherited from `oxy-app` plus a `no_bundled_db` suite.
- `helm lint --strict ./charts/oxy`; rendered-manifest validation with
  `helm template ./charts/oxy -f <env> | kubeconform -strict`.
- `chart-testing` (`ct`) auto-discovers the chart; `chart-releaser` publishes it
  to `oci://ghcr.io/oxy-hq/helm-charts` on merge.

## What was removed vs. what remains

Removed as part of the cloud-only refactor (all render-neutral for external-DB
envs — proven byte-identical to `oxy-app`, modulo removed comments):

- **Local / git-sync mode** — the `git-clone` init container, the `--local`
  flag, `workingDir`, the HTTP-auth / SSH / GitHub-App clone-credential secrets,
  the `startupProbe` (it was git-sync-era; readiness is the startup gate), and
  the top-level `git:` / `httpAuth:` / `sshKey:` values.
- **The `--no-workers` / `appServer.disableInprocessWorkers` toggle** — the
  `ide` always runs in-process workers. (The stateless `serve` fleet still runs
  `oxy serve --no-workers`; that is intrinsic to its role, not a toggle.)
- **Bundled databases** — the top-level `database:` / `clickhouse:` /
  `clickhouseSubchart:` values. Postgres and ClickHouse are external.
- **The otel-collector sidecar** — observability is handled in-house: the app
  writes directly to ClickHouse (`OXY_OBSERVABILITY_BACKEND` / `OXY_CLICKHOUSE_*`
  env), so the OTel collector, its ConfigMap, and the `otelCollector:` values
  are all gone. There is no ClickHouse dependency left in the chart at all.

**Follow-ups to the 2026 bar:** DRY the `OXY_DATABASE_URL` pass-through into a
`_helpers.tpl` partial (or an in-house `oxy-common` library chart shared with
`oxy-start`), digest-pin images (Renovate), and cosign-sign + attach SBOM/SLSA
on the OCI push.
