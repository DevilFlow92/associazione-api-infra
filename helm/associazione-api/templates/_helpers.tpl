{{/*
Expand the name of the chart.
*/}}
{{- define "associazione-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "associazione-api.fullname" -}}
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
Create chart label.
*/}}
{{- define "associazione-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "associazione-api.labels" -}}
helm.sh/chart: {{ include "associazione-api.chart" . }}
{{ include "associazione-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "associazione-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "associazione-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "associazione-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "associazione-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Migration job name — suffixed with chart version to force re-run on upgrade.
*/}}
{{- define "associazione-api.migrationJobName" -}}
{{- printf "%s-migrate-%s" (include "associazione-api.fullname" .) .Chart.Version | replace "." "-" | trunc 63 | trimSuffix "-" }}
{{- end }}