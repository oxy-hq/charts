# Standalone Worker Fleet

Run Oxy's durable orchestrator as a separate Deployment so HTTP frontends
and queue workers scale independently.

Background and protocol design live in the oxygen-internal repo:

- PR oxy-hq/oxygen-internal#2409 (`feat/worker-fleet-separation`)
- `internal-docs/worker-fleet.md` on the same branch — the canonical
  dev/operator guide

The chart pieces below mirror that guide; if the two disagree, the
oxygen-internal doc wins.

## When to enable

| Mode | Chart config | Use when |
| --- | --- | --- |
| Single-process | `worker.enabled: false` (default) | Local dev, single-node prod. HTTP and workers share one StatefulSet pod. |
| Split fleet | `worker.enabled: true` + `appServer.disableInprocessWorkers: true` | Production where HTTP and worker scaling signals diverge (request rate vs queue depth), or where you want different node pools / rollout cadences for each. |

Both deployments must point at the **same Postgres**. The durable queue
(`agentic_task_queue`) is the only coordination surface.

## Topology

```
+--------------------+         +--------------------+
| oxy serve          |         | oxy worker         |
| --no-workers       |         | --health-port 8081 |
| (StatefulSet)      |         | (Deployment xN)    |
|                    |         |                    |
|  HTTP frontend     |         |  Drains queue via  |
|  + PostgresRouter  |         |  SKIP LOCKED       |
+---------+----------+         +---------+----------+
          |                              |
          +----------+ Postgres +--------+
                     |
              agentic_task_queue
```

## Enabling

Minimal turn-on:

```yaml
appServer:
  disableInprocessWorkers: true   # HTTP fleet stops draining the queue

worker:
  enabled: true                   # Worker Deployment renders
  replicaCount: 2
```

The chart will then render:

- `Deployment/{release}-oxy-app-worker` (N replicas of `oxy worker`)
- `Service/{release}-oxy-app-worker` (ClusterIP on the health port, for
  probes / in-cluster scrape only)
- `PodDisruptionBudget/{release}-oxy-app-worker-pdb` (minAvailable: 1)
- HPA when `worker.hpa.enabled: true` (see below)

And the existing HTTP StatefulSet picks up:

- `--no-workers` appended to `oxy serve`
- `OXY_DISABLE_INPROCESS_WORKERS=1` as a belt-and-suspenders env

When `worker.enabled` is left at `false` (the default) no worker
resources are rendered — existing deploys upgrade with zero impact.

## Key knobs (`worker.*`)

| Key | Default | Purpose |
| --- | --- | --- |
| `worker.enabled` | `false` | Master switch for the worker Deployment + Service + PDB + (optional) HPA. |
| `worker.replicaCount` | `2` | Worker pod count. Bump this OR `worker.resources` when individual workers peg. |
| `worker.image.repository` / `worker.image.tag` / `worker.image.pullPolicy` | inherited from `app.image*` | Pin worker fleet to a different image (canary). |
| `worker.healthPort` | `8081` | Port `oxy worker` binds `/healthz` + `/readyz` on. Used by both probes and the worker Service. |
| `worker.skipMigrations` | `true` | Passes `--skip-migrations` so worker replicas don't race the HTTP fleet's migrator. The HTTP StatefulSet is the canonical migrator on rollout. |
| `worker.env.OXY_WORKER_MAX_INFLIGHT` | `"32"` | Concurrent task cap per worker process. |
| `worker.env.OXY_WORKER_RECOVERY_INTERVAL_SECS` | `"30"` | Recovery loop (reaper pre-pass) cadence. |
| `worker.terminationGracePeriodSeconds` | `40` | Graceful drain budget (30 s recovery + 5 s health-server + buffer). Bump if you raise `OXY_WORKER_RECOVERY_INTERVAL_SECS`. |
| `worker.pdb.enabled` | `true` | PDB so node rollouts don't drain the fleet to zero. |
| `worker.hpa.enabled` | `false` | Off until you wire the queue-depth metric — see below. |
| `worker.inheritExternalSecrets` | `true` | Mount the same `externalSecrets.envSecretNames` / `fileSecrets` the HTTP fleet sees. |

## `--skip-migrations` rationale

Both fleets share a Postgres. If every worker pod on rollout tried to
run migrations, they'd race for the same `INFORMATION_SCHEMA` /
`sea_orm_migrations` rows. To avoid that:

1. The HTTP StatefulSet (single pod by default) runs migrations on
   startup — it is the canonical migrator.
2. Worker pods skip migrations (`worker.skipMigrations: true`, the
   default) and assume the schema is already up to date.

If you'd rather run migrations as a one-shot `oxy migrate` Job, set
`worker.skipMigrations: true` on the worker fleet AND ensure
`oxy serve` is started after the Job completes. The chart does not (yet)
ship that Job — see "Punted" below.

## HPA wiring

The HPA is **off by default** because it depends on a custom external
metric. The canonical query, taken from
`internal-docs/worker-fleet.md`:

```sql
SELECT count(*) FROM agentic_task_queue WHERE queue_status = 'queued';
```

Recommended pipeline:

1. Run `prometheus-postgres-exporter` against the same Postgres your
   Oxy deployment uses.
2. Add a custom query that maps the SQL above to a metric:
   `oxy_agentic_task_queue_depth` (override via `worker.hpa.metricName`).
3. Expose the metric through your cluster's external-metrics adapter
   (e.g. `k8s-prometheus-adapter`).
4. Flip `worker.hpa.enabled: true` and tune `queueDepthThreshold` so
   scale-up fires well before the reaper's visibility timeout (default
   5 min) — that way the queue can't back up faster than scale events.

The chart renders a v2 HPA with an `External` metric and an optional
`Resource` metric (CPU) as a fallback when `worker.hpa.cpuUtilization`
is set to a non-zero percentage.

## Image pinning

By default, the worker fleet inherits the HTTP fleet's image
(`app.image` + `app.imageTag` falling back to `Chart.AppVersion`).
Override `worker.image.tag` to pin a different tag — useful for canary
rollouts where you want to shift queue drainage to a candidate image
before flipping HTTP traffic.

## Punted (intentional first-cut limitations)

These follow the limitations called out in
`internal-docs/worker-fleet.md`:

- **Migration Job**: the chart does not ship a dedicated `oxy migrate`
  Helm hook / Job. The HTTP StatefulSet is the migrator; if you need a
  Job-based migration path, add it out-of-band.
- **Stranded-run sweep**: the standalone worker's recovery loop only
  runs a reaper pre-pass. Cloud-mode multi-workspace stranded-run replay
  still requires at least one HTTP pod with in-process workers.
- **HPA observability adapter**: the chart describes the metric, but
  does not deploy the exporter or adapter. Wire those yourself.
- **Worker ServiceMonitor**: the chart does not render a Prometheus
  Operator `ServiceMonitor`. Add one against the worker Service's
  `health` port if you scrape `/healthz` / `/readyz` directly.
