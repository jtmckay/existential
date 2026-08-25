module decree-webhook

// 1.22 is the floor: net/http.ServeMux gained {param} patterns there, which is
// what replaces the Express router. Keep this at the floor rather than letting
// `go get` raise it — the Dockerfile builder image must satisfy it.
go 1.22

require gopkg.in/yaml.v3 v3.0.1
