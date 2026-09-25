{{/*
Expand the name of the chart.
*/}}
{{- define "oxy-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "oxy-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "oxy-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "oxy-app.labels" -}}
helm.sh/chart: {{ include "oxy-app.chart" . }}
{{ include "oxy-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oxy-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oxy-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Compute the effective ServiceAccount name.
Behavior:
 - If .Values.serviceAccount.name is set, use it.
 - Else if .Values.serviceAccount.create is true, use the chart fullname.
 - Otherwise return empty string.
*/}}
{{- define "oxy-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else if .Values.serviceAccount.create }}
{{- include "oxy-app.fullname" . }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
Enterprise flag, inherited by the serve fleet from the ide.

`--enterprise` is an `oxy serve` flag (ServeArgs only — `oxy worker` rejects
it). The operator sets it on the ide through `app.args` / `app.command`.

It gates the observability UI: the frontend reads `enterprise` from
GET /api/auth/config and, when it is false, drops the entire observability
route tree and its sidebar entry. With `serveFleet.enabled`, that endpoint is
answered by a SERVE replica — the catch-all `/` ingress path lands there and
`/api/auth/config` is not one of the ide routes — so a serve fleet started
without the flag reports `enterprise: false` and observability disappears from
the UI even though the ide has it and spans are still being recorded.
(Recording is a separate axis: `observability_enabled`, driven by
OXY_OBSERVABILITY_BACKEND, stays true throughout.)

Returns "true" when the ide is configured for enterprise, "" otherwise, so the
serve fleet's DEFAULT command inherits it. An explicit `serveFleet.command`
(or `serveFleet.args`) is taken verbatim and is unaffected.
*/}}
{{- define "oxy-app.enterprise" -}}
{{- $enterprise := "" -}}
{{- range concat (.Values.app.args | default list) (.Values.app.command | default list) -}}
{{- if contains "--enterprise" (toString .) -}}
{{- $enterprise = "true" -}}
{{- end -}}
{{- end -}}
{{- $enterprise -}}
{{- end }}
