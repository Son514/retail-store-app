{{- define "ui.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "ui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ui.name" . }}
{{- end -}}

{{- define "ui.labels" -}}
{{ include "ui.selectorLabels" . }}
app.kubernetes.io/component: service
app.kubernetes.io/owner: retail-store-sample
{{- end -}}
