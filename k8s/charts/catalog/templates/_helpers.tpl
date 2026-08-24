{{- define "catalog.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "catalog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "catalog.name" . }}
{{- end -}}

{{- define "catalog.labels" -}}
{{ include "catalog.selectorLabels" . }}
app.kubernetes.io/component: service
app.kubernetes.io/owner: retail-store-sample
{{- end -}}
