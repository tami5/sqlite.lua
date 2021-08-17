{{ range .Versions }}
<a name="{{ .Tag.Name }}"></a>

## {{ if .Tag.Previous }}[{{ .Tag.Name }}]({{ $.Info.RepositoryURL }}/compare/{{ .Tag.Previous.Name }}...{{ .Tag.Name }}){{ else }}{{ .Tag.Name }}{{ end }}

> {{ datetime "2006-01-02" .Tag.Date }}


{{ range .CommitGroups -}}
### {{ .Title }}

{{ range .Commits -}}
{{if .Body }}
<details style="text-indent: 1.1em;"><summary style="text-indent: 1.1em;"><a href="{{ $.Info.RepositoryURL }}/commit/{{ .Hash.Long }}">{{ .Subject }}</a></summary>{{ .Body }}</details>
{{ else }}
* [{{ .Subject }}]({{ $.Info.RepositoryURL }}/commit/{{ .Hash.Long }})
{{ end }}
{{ end }}
{{ end -}}

{{- if .RevertCommits -}}
### Reverts

{{ range .RevertCommits -}}
* {{ .Revert.Header }}
{{ end }}
{{ end -}}

{{- if .NoteGroups -}}
{{ range .NoteGroups -}}
### {{ .Title }}

{{ range .Notes }}
{{ .Body }}
{{ end }}
{{ end -}}
{{ end -}}
{{ end -}}