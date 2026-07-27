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
