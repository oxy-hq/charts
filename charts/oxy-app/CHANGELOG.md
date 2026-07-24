# Changelog — oxy-app

## 1.0.0 — drop bundled database subcharts (breaking)

**What changed**

- **Removed the bundled `postgres` (groundhog2k) and `clickhouse` (Bitnami)
  subchart dependencies.** They are deleted from `Chart.yaml`, and the vendored
  archives (`charts/postgres-1.6.1.tgz`, `charts/clickhouse-9.4.4.tgz`) and
  `Chart.lock` are removed. `oxy-app` now deploys **only** the Oxy application
  workloads (the `ide` StatefulSet, the stateless `serve`/`worker` fleets, and
  the `migrate` Job). Postgres, ClickHouse and Airhouse are **external** —
  managed outside the chart (RDS/CNPG, the ClickHouse operator, the airhouse
  chart) and wired in via connection env vars.
- Fixed `NOTES.txt` referencing the undefined `.Values.replicaCount` (rendered
  blank) — the ide StatefulSet is always single-replica.

**Why**

Every real deployment (oxy-dev, oxy-staging, oxy-prod) already runs against
external managed databases: `database.postgres.enabled`,
`database.clickhouse.enabled` and `clickhouse.enabled` are **all `false`**, so
the subcharts rendered nothing. Bundling them meant the chart carried, pulled
and lock-pinned two database charts it never deployed — dead weight and a supply
-chain surface for no benefit. A workload chart should not ship its stateful
databases; those belong to an operator / managed service / their own chart.

**Migration (render-identical for external-DB values — drop-in)**

For any deployment that already sets the DB subcharts to disabled (all Oxy
envs), upgrading `0.6.x → 1.0.0` is a **no-op to the rendered manifests** — the
only change is the `helm.sh/chart` version label. Verified with
`helm template` diffs across the oxy-dev, oxy-staging and oxy-prod value sets:
identical output apart from that label.

Adopt per environment by bumping the pinned chart version (e.g. the
`chartRevision` in the oxy-instances ApplicationSet, or `targetRevision` in the
prod Application) `0.6.x → 1.0.0`. No values changes are required. You may
optionally delete the now-inert `clickhouse.enabled: false` line from each
env's values.

Keep connecting to external databases exactly as today, via env:

- Postgres: `env.OXY_DATABASE_URL` (URL mode) or the `OXY_DATABASE_*` vars
  (IAM mode: `OXY_DATABASE_AUTH_MODE`, `_HOST`, `_PORT`, `_NAME`, `_USER`,
  `_REGION`, `_SSL_MODE`).
- ClickHouse: `env.OXY_CLICKHOUSE_URL` / `_USER` / `_DATABASE` (+ password via
  an ExternalSecret in `externalSecrets.envSecretNames`).
- Airhouse: `env.AIRHOUSE_*`.

**If you actually need an in-cluster database for local/dev**

Deploy it as its own release alongside `oxy-app` (e.g. `helm install pg
groundhog2k/postgres`) and point `env.OXY_DATABASE_URL` at its Service. The
chart no longer couples the app's lifecycle to a database's.

**Follow-ups (tracked separately, not in 1.0.0)**

- `1.1.0` cleanup: remove the now-dead `database.*` / `postgres.*` /
  `clickhouseSubchart.*` template branches (the `wait-for-postgres` /
  `wait-for-clickhouse` init containers, the subchart ClickHouse env block, the
  postgres/external `OXY_DATABASE_URL` construction branches) and the
  corresponding `values.yaml` keys. These are gated on the now-removed
  `*.enabled` flags, so they already render nothing — pure dead-code removal,
  shipped separately so the breaking dependency change stays reviewable on its
  own.
- DRY the four byte-identical `OXY_DATABASE_URL` blocks and the shared
  encryption-key / compile-bucket env into `_helpers.tpl` partials.
- Add `values.schema.json` for input validation.
