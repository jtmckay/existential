# decree-webhook

An authenticated HTTP receiver that turns a POST into a decree inbox message.

It does not run any work itself. Each accepted request becomes one markdown file
in the decree inbox (`services/automation/decree/inbox/`, mounted at `/inbox`); the
decree daemon picks that file up and runs the routine named in its frontmatter.

```
POST /notify/Backup%20done          →  inbox/notify-143052.md
Authorization: Bearer <secret>
                                       ---
disk 3 is full                         routine: notify
                                       ntfy_priority: high
                                       ntfy_title: Backup done
                                       ntfy_topic: exist
                                       ---

                                       disk 3 is full
```

The service is a single static Go binary on `distroless` — no shell, no
interpreter, no package tree. Because distroless ships no `curl` or `wget`, the
healthcheck is the binary probing itself (`/webhook -healthcheck`), and its
`go test` suite runs separately from `./existential.sh test` (see
`.claude/reference/testing.md`).

---

## How it works

1. **Startup** reads `config.yml`, validates every endpoint, and registers one
   route per entry. Anything invalid is fatal — the process exits rather than
   starting with a half-working route table.
2. **A request** is matched to its endpoint, authenticated against that
   endpoint's bearer secret, and its path parameters validated.
3. **The frontmatter** for that endpoint is copied, `{{param}}` placeholders are
   substituted, and the result is marshalled to YAML.
4. **The file** `<routine>-<HHMMSS>.md` is written to the inbox with the request
   body as its markdown body. The response is `201` with the filename.

### Configuration

Routes live in `config.yml`, rendered from `config.exist.yml` by
`./existential.sh`. That file is the whole API surface — there is no route table
in the code.

```yaml
secret: <32+ chars>          # default for every endpoint

endpoints:
  - path: /notify/{title}    # {name} declares a path parameter
    secret: <32+ chars>      # optional per-endpoint override
    params:
      title: '[0-9a-f]{8}'   # optional, stricter than the default charset
    frontmatter:             # emitted verbatim, with {{title}} substituted
      routine: notify
      ntfy_title: '{{title}}'
```

Validated at startup, all fatal: path shape (`^/[A-Za-z0-9._\-/{}]+$`, no `..`),
duplicate paths, conflicting route patterns, missing `frontmatter`, a `params`
key not present in the path, an uncompilable param regex, and a secret that is
missing, shorter than 32 characters, or still an unrendered `EXIST_*` template
placeholder.

### Environment

| Variable | Default | Meaning |
|---|---|---|
| `DECREE_WEBHOOK_PORT` | `8801` | Listen port. The stack does not set it — the container is reached only over the `exist` bridge and caddy hardcodes `8801`. Override it only alongside an uncommented `ports:` block. |
| `DECREE_WEBHOOK_INBOX` | `/inbox` | Inbox directory, must be writable at startup |
| `DECREE_WEBHOOK_CONFIG` | `/app/config.yml` | Config path |
| `DECREE_WEBHOOK_MAX_BODY_BYTES` | `262144` | Request body limit |
| `DECREE_WEBHOOK_RATE_WINDOW_MS` | `60000` | Rate limit window |
| `DECREE_WEBHOOK_RATE_MAX` | `60` | Requests allowed per window |
| `DECREE_WEBHOOK_RATE_FAIL_MAX` | `10` | Rejected requests allowed per window |

### Responses

| Status | When |
|---|---|
| `201` | Enqueued. Body: `{"file": "notify-143052.md", "path": "/notify"}` |
| `400` | Empty body, or a missing / overlong / invalid path parameter |
| `401` | Missing, malformed, or wrong `Authorization: Bearer` header |
| `404` | Unknown path — **and any non-POST method** (see below) |
| `413` | Body over the size limit |
| `429` | Request or failure budget exhausted |
| `500` | Could not write the file (includes the same-second collision below) |

`GET /healthz` returns `{"ok": true}` and is exempt from rate limiting.

---

## Differences from a standard API endpoint

These are the behaviours that will surprise someone who reads the code expecting
a conventional JSON service. Each is deliberate; most are load-bearing.

**Routes are configuration, not code.** Adding an endpoint means editing
`config.exist.yml` and re-rendering — no Go changes, no redeploy of new source.

**The request body is never parsed.** It is opaque bytes, copied into the
markdown body verbatim regardless of `Content-Type`. Only two things happen to
it: it must be non-blank, and a trailing newline is added if missing. Do not add
JSON parsing here — callers post plain text.

**A wrong method returns 404, not 405.** Routes are registered without a method
so `ServeMux` cannot answer 405 on its own; the handler returns 404 to match the
Express service this replaced. Callers may depend on it.

**Exactly one trailing slash is stripped**, so `/notify/` still resolves to
`/notify`. This cannot be expressed as a `ServeMux` pattern — a trailing slash
there means subtree match, which would swallow `/notify/{title}`. `/notify//`
still 404s.

**Frontmatter is built by marshalling a YAML node tree, never by string
interpolation.** This is the injection boundary: a path parameter reaches
frontmatter as a value, and letting it reach the file as text would let a caller
forge frontmatter keys. Keep substitution on the node tree.

- Substitution applies to string scalars only, so a config `port: 8080` stays an
  integer and an unknown `{{placeholder}}` is left verbatim.
- Values that YAML 1.1 resolves to non-strings (`y`, `no`, `off`, `null`, `42`,
  …) are force-quoted, so `POST /notify/y` yields `ntfy_title: 'y'` rather than a
  boolean when read by a 1.1 parser.
- Key order follows `config.yml`. That is why frontmatter stays a `yaml.Node`
  tree rather than becoming a `map` — a map would emit alphabetically.
- Collections below the root are emitted inline (`tags: [api, ingest]`).

**Path parameters are charset-restricted, not escaped.** The default is
`[A-Za-z0-9_\-!]+` with a 200-character cap; a per-endpoint `params` regex can
narrow it further but never widen it. Anything else is a 400. There is no
URL-decoding leniency and no sanitising fallback — reject, don't repair.

**The filename comes from the raw config, not from the request.** The routine
slug is read off the *unsubstituted* frontmatter, so a `{{param}}` in `routine:`
yields the literal placeholder rather than attacker-chosen text in a filename.

**Two messages for the same routine in the same second collide, and the second
one gets a 500.** The file is opened `O_EXCL` because the daemon derives message
identity from the filename, so overwriting would silently drop a message.
Failing loudly is the intended trade; changing it is a separate decision.

**Rate limiting is global, not per-IP.** The service sits behind Caddy and sees
one source address, so per-IP buckets would all be the same bucket. There are
two fixed windows: `all` (every request) and `failures`, which is only charged
when a request is rejected — the brute-force brake that a busy legitimate caller
never trips.

**Auth is a static per-endpoint bearer token** compared in constant time, with a
length check first so a wrong-length token cannot be distinguished by timing.
There are no sessions, scopes, or token rotation. The 32-character floor exists
because this token is the only thing between the internet and a routine the
daemon will execute.

**Config changes restart the process instead of hot-reloading.** A goroutine
polls the file's mtime every 2s and exits 0 on change; Docker's `unless-stopped`
policy brings it back with the new config. Polling rather than inotify because
the config is a bind-mounted file and an editor replacing the inode drops a
watch. There is no `/reload` endpoint by design — a reload path would be a
second, less-tested way to load config.

**The healthcheck is the binary probing itself** (`/webhook -healthcheck`).
distroless ships no curl or wget, so `-healthcheck` makes one request to
`127.0.0.1/healthz` and maps the result to an exit code.

**This image is built by compose, not by `existential-adhoc`.** Every other
decree container shares `existential/decree:local`; this one has its own
`Dockerfile` and shares nothing with the daemon but the inbox bind mount.

---

## Development

The dependency is `gopkg.in/yaml.v3` and nothing else. `go.mod` is pinned at Go
1.22 — the floor for `ServeMux` `{param}` patterns — deliberately, so the
builder image can be upgraded without the module requiring a newer toolchain.

**Tests** (`main_test.go`) are not part of `./existential.sh test`; the adhoc
container has no Go toolchain. Run them from this directory:

```bash
go test ./...
# or, without Go on the host:
docker run --rm -v "$PWD":/src -w /src golang:1.26.5-alpine3.23 go test ./...
```

The suite is golden-file based: it asserts the exact bytes written to the inbox,
so a formatting regression in the YAML output fails loudly. It also covers auth,
param rejection, both rate limiters, file mode, the same-second collision, and
every startup config validation.

Its golden frontmatter came from `difftest.sh`, the parity harness that ran this
server and the original Express `server.js` side by side and diffed status, body,
and the resulting inbox bytes. Both are gone: the port is done, and this suite is
what the harness was distilled into. That is the only parity record now, so a
change to the inbox format must update the goldens deliberately.

**`exist.test.sh`** at `services/automation/` is the live-stack check: liveness
through both Docker DNS and Caddy, plus read-only rejection probes (401, 404)
that deliberately spend from the failure budget rather than writing to the inbox.
