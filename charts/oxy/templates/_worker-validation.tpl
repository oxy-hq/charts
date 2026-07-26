{{- /*
Helm-time guard against the silent-stall misconfiguration where the
HTTP fleet is told NOT to drain the queue (`appServer.disableInprocessWorkers`)
but no standalone worker fleet is rendered (`worker.enabled: false`).

In that configuration nothing pulls from `agentic_task_queue`:
   - HTTP server sees `--no-workers` / `OXY_DISABLE_INPROCESS_WORKERS=1`
     and skips both the in-process worker AND the recovery driver.
   - `oxy worker` Deployment is not rendered, so no out-of-process
     consumer exists either.
Result: agentic runs, builder pipelines, airway runs, preagg cycles
all enqueue successfully but never execute. Symptoms surface as runs
stuck in `queued`, the queue-depth alert paging on-call after the
threshold breach, and operators chasing a phantom database issue.

The reverse misconfiguration (`worker.enabled: true` AND
`appServer.disableInprocessWorkers: false`) is benign — both fleets
drain the same queue concurrently. It wastes a worker pod, but the
SKIP-LOCKED semantics prevent double-execution. Skip the guard there
and let the user wire the topology as they intend.
*/}}
{{- define "oxy-app.validateWorkerTopology" -}}
{{- if and .Values.appServer.disableInprocessWorkers (not .Values.worker.enabled) -}}
{{- fail (printf "%s%s%s%s%s"
  "[oxy-app] Invalid worker topology: appServer.disableInprocessWorkers=true "
  "but worker.enabled=false. The HTTP fleet is configured to skip in-process "
  "workers, so nothing will drain the agentic_task_queue. Either set "
  "worker.enabled=true to render the standalone oxy worker Deployment, or set "
  "appServer.disableInprocessWorkers=false to keep the in-process worker.") -}}
{{- end -}}
{{- end -}}
