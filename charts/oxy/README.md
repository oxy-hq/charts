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

## Known follow-ups

- A few vestigial `database.*` / `postgres.*` / `clickhouseSubchart.*` template
  branches (the wait-for-DB init containers, the subchart ClickHouse env block,
  the postgres `OXY_DATABASE_URL` construction) remain **inert behind
  default-false flags**. Removing them + their values keys is pure dead-code
  cleanup (render-neutral for external-DB envs) and is tracked separately so the
  drop-in stays trivially verifiable.
- Raise to the 2026 bar: DRY the duplicated `OXY_DATABASE_URL` block into a
  `_helpers.tpl` partial (or an in-house `oxy-common` library chart shared with
  `oxy-start`), digest-pin images (Renovate), and cosign-sign + attach
  SBOM/SLSA on the OCI push.
