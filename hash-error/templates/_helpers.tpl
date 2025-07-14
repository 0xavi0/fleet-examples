{{- define "microservice.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
