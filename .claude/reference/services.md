# Services: lifecycle, privileges, coupling

## Core vs complementary

A service is **core** if something reaches it by bare container name over the `exist` bridge.
It is **complementary** if it is reached over a URL/protocol you could point anywhere (rclone
remote, S3 endpoint, DNS), or if nothing in the stack talks to it at all.

Complementary today: **NAS** (nextcloud, minio, collabora, redis — the core reaches these via
rclone remotes and the S3 API; `redis` serves only nextcloud), **immich** (nothing references
it), **homeassistant** (nothing references it either, and it is often bound to the host with the
USB radios plugged in), **pihole** (LAN DNS), **monitoring** (grafana/loki/prometheus/uptime-kuma
— they scrape, nothing depends on them).

A Caddy block and a Dashy tile do **not** make a service core — those are ingress and
navigation, and every complementary service has them. The test is a bare container name in
another service's config or env.

They all still join `exist` by default, which is fine on one host. The rule is about *not adding
new coupling*: **never introduce a bare-container-name dependency from the core stack into a
complementary service.** Reach it by configurable endpoint so it can move to another machine —
the recommended shape is three stacks (NAS / core / standalone immich + pihole). When adding a
service, decide which side it is on and wire it accordingly.

## Lifecycle scripts

```
./existential.sh run:
  1. templates.sh     Render *.exist.* → live files
  2. exist.initial.sh Pre-startup, idempotent, every run. No sentinels — check state, skip if done.
docker compose up -d  (user runs)
  3. entrypoint.sh    Inside the container, before the service starts. Trues up config it owns.
  4. exist.test.sh    Sidecar retries until this passes (service healthy)
  5. decree process   Runs pending one-time migrations from <service>/decree/migrations/
On demand:
  exist.<action>.sh   ./existential.sh run <slug> <action> — interactive/manual, documented as quest
  exist.test.sh       ./existential.sh run <slug> test — read-only validation
```

| Script | Write when… |
|---|---|
| `exist.initial.sh` | Files/dirs/system config needed before container start. Idempotent. |
| `entrypoint.sh` | Config the service owns, seeds at first boot, and re-reads only at startup — see below. |
| image entrypoint hook | Setup that must run *inside* the container, at a moment only the image knows. |
| migration `migrations/<name>.md` | Post-startup setup (API calls, user creation, seeds). Runs once. |
| `exist.<action>.sh` | Interactive on-demand ops a user triggers. Document in a quest. |
| `exist.test.sh` | Always. Every service ships one. Also what triage and the migration gate run. See `testing.md`. |

**Entrypoint true-up.** A wrapper set as the service's `entrypoint:`, which does its work and
then `exec`s the image's real entrypoint. Reach for this when a setting is *derived from
`.env.shared`* but lives inside the service's own datastore, and all three of these hold:

1. the file does not exist until the service's own first boot, so a pre-startup host script has
   nothing to edit;
2. the service rewrites it on shutdown, so an edit made while it runs is discarded;
3. it is the only copy the service actually reads.

Together those close every other window — which is the whole argument for the entrypoint: it is
the one moment the file exists and nothing is holding it.

Without it the setting silently freezes at whatever the first boot saw, while the rest of the
stack follows `.env.shared` immediately (caddy reads `{$CADDY_DOMAIN}` at runtime; `dashy-conf.yml`
and honcho's `config.toml` are `_ALWAYS_RENDER`). That asymmetry is the bug: `EXIST_DOMAIN`
becomes a one-way door and nothing says so.

In the stack today:

| Service | What it trues up | Why nothing else could |
|---|---|---|
| `services/homeassistant` | `.storage/http` — `use_x_forwarded_for`, `trusted_proxies` | HA serves `data.stable` only. It stages `configuration.yaml` into `data.pending` as `not_promoted` and never promotes it, not even across a restart, so proxied requests 400 forever. Restarts itself once when the file did not exist yet. |
| `nas/nextcloud` | `trusted_domains`, `overwrite*`, `trusted_proxies` (via a `before-starting` hook) | The installer reads them once and then ignores the environment. |
| `services/ntfy` | the publishing user and its ACL | `ntfy user add` needs the auth DB the server creates on first boot. |

Rules. Keep the true-up **idempotent and quiet** — converge, then say nothing, so a normal start
is silent (nextcloud's hook logs only what changed). **`exec` the real entrypoint** so the image's
init keeps PID 1. If a restart is genuinely needed, **bound it**: gate it on a condition the
restart itself resolves, or it becomes a crash loop. And leave a deliberate choice alone — reconcile
only while the value still looks like something existential set (hermes checks `provider: custom`
plus a `:11434` endpoint before touching `model:`; openviking applies the same test to `ov.conf`'s
`api_base`), so pointing a service at Anthropic or an external host is respected.

**Entrypoint hooks.** Some images run scripts from a directory at defined points in their own
startup — nextcloud's `/docker-entrypoint-hooks.d/{pre,post}-installation`, postgres'
`/docker-entrypoint-initdb.d`. Reach for one when the work needs a tool that only exists inside
the container (`occ`, `psql`) *and* a moment only the image can identify ("right after a
successful first install"). A decree migration cannot do this: no decree daemon has a docker
socket, so a migration can only reach a service over the network.

Mount the hook directory specifically, not its parent, so the image's other hook folders survive:

```yaml
    volumes:
      - ./hooks/post-installation:/docker-entrypoint-hooks.d/post-installation:ro,z
```

Two rules. The scripts need the **exec bit** (`755`) — nextcloud's runner skips any that lack it,
silently. And they must **exit 0 on every path**: a hook that fails can abort the install it was
meant to finish. Guard the body and log a warning instead. See
`nas/nextcloud/hooks/post-installation/01-minio-external-storage.sh`.

Scripts self-elevate into `existential-adhoc` when they need its tooling (`if [[ -z
"$IN_CONTAINER" ]]; then exec docker compose run …`). Init order (`run_initials`):
`hosting → nas → ai → services`.

## Container user & privileges

Least privilege is the default. An app container runs as the **host** user
(`user: "${EXIST_PUID:-1000}:${EXIST_PGID:-1000}"`), so bind-mount files stay deletable without
root **unless it structurally needs root** — in which case say why in a comment next to the
omission (see hermes-agent's s6 note). **Never hardcode the literal `1000:1000`** — always the
`${EXIST_PUID:-1000}:${EXIST_PGID:-1000}` form (enforced by `validate conventions`).
`EXIST_PUID`/`EXIST_PGID` are auto-detected from the host (`id -u`/`id -g`) by `existential.sh`'s
`_ensure_host_ids`, written into `.env.shared`, and default to `1000` when absent — so the stack
works for a user who isn't `1000:1000` (LDAP, a second account, a server) without any config.

**Pick the right mechanism, not always `user:`:** images with an s6/`PUID`-style init (it starts
as root then drops) break under `user:` — set their `PUID`/`PGID` (or `UID`/`GID`,
`HERMES_UID`/`GID`, …) **env** to `${EXIST_PUID:-1000}`/`${EXIST_PGID:-1000}` instead (lowcoder,
open-webui, hermes-agent do this). Use plain `user:` only for images that tolerate an arbitrary
uid.

Root is expected for: privileged-port binders that can't take a cap (use `cap_add` over
`privileged: true` when possible — Caddy uses `cap_add: [NET_BIND_SERVICE]`; the only blanket
`privileged: true` in the repo lives in an `x-exist-gpu.amd` block, see *GPU vendor wiring*
below), pihole (NET_ADMIN),
portainer (docker.sock), GPU/supervisor images (ollama, comfyui), multi-process app images
managed by an internal supervisor (appsmith, lowcoder, nextcloud), and images caching into
`/root` (whisperx, mcp).

## GPU vendor wiring

Templates declare the **nvidia** device reservation and nothing else. That is correct for the
majority of hosts, and `src/generate-compose.ts` rewrites it for everyone else from
`EXIST_GPU_VENDOR` (asked by quest as the first hardware question — `src/utils/gpu-vendor.sh`):

| vendor   | what the generator does                                                        |
|----------|--------------------------------------------------------------------------------|
| `nvidia` | nothing, beyond dropping the `x-exist-gpu` key                                  |
| `amd`    | strips the nvidia reservation, merges `x-exist-gpu.amd`                         |
| `none`   | strips the nvidia reservation, merges `x-exist-gpu.none`; `EXIST_VRAM_GB` is 0  |

The strip is not tidiness. Docker refuses to create a container whose device driver it cannot
satisfy (`could not select device driver … with capabilities: [[gpu]]`), and compose fails the
whole `up` — so one nvidia reservation on an AMD or CPU-only host takes down every other service
in the stack with it. A blank `EXIST_GPU_VENDOR` falls back to the older `EXIST_VRAM_GB == 0`
signal, so installs predating the question keep generating exactly what they did before.

When **both** are blank nothing has ever been answered — that is the shipped default, i.e. a
render that never reached quest (a fresh clone, CI, the e2e harness) — and it resolves to
`none`, not nvidia. It has to: otherwise a fresh clone on an AMD or CPU host gets a reservation
docker cannot satisfy and loses the entire `up`. Guessing wrong the safe way costs an nvidia
host acceleration until it answers the question; the other way costs everyone else a stack that
will not start.

**Vendor config lives with the service**, as an `x-exist-gpu.<vendor>` block in its
`docker-compose.exist.yml` — never as a table of container names in the generator, which would
mean editing two places to add a GPU service:

```yaml
    x-exist-gpu:
      amd:
        privileged: true
        environment:
          OLLAMA_VULKAN: "1"
```

The merge is one level deep and last-wins, except `environment`, which is *merged* so a block can
set one variable without restating the rest (list form `- KEY=value` is normalised to map form
first, so either style in the template works). The key itself never reaches the output.

`privileged: true` inside an `x-exist-gpu.amd` block is the **one sanctioned use** of privileged
in this repo: it is how Vulkan reaches `/dev/dri`, and living in the overlay means it can only
ever apply on a host that answered *AMD*. Never put it in the service body.

Two things worth stating plainly when you add a block: a stripped reservation only makes a
container **start**, it does not make a CUDA-only workload work (whisperx pins `DEVICE: cpu` for
both non-nvidia vendors because CTranslate2 has no ROCm backend — without it the container starts
and then dies on the first request), and an `x-exist-gpu.<vendor>: {}` is a legitimate way to
record "considered, nothing to do" rather than leaving the case looking forgotten.

`decree-backup` runs as the host user like everything else — the volume data it tars is
host-owned by the `volumes/` convention, so it needs no extra privilege. **DB/cache
images** (postgres, mariadb, mongo, redis) also run as the host user, but the data volume must be
owned by that uid first — pinning `user:` on a dir already initialized under the image's old
service uid breaks startup until the volume is `chown`-ed. Never use `user: "0:0"`.

## Decree image & daemons

The decree image is built **once** from `automations/Dockerfile` by `existential-adhoc`, tagged
`existential/decree:local`; both `decree` and `decree-backup` reference it via `image:` (not
rebuild). WORKDIR is `/work` (project at `/work/.decree`). Baked healthcheck: `grep -q decree
/proc/1/comm` with a long `start-period` (330s) so a daemon running as `bash` during its
migration wait shows `starting`, not `unhealthy`. Adhoc disables the healthcheck.

**There are exactly two daemons, and services do not get their own.** Both live in
`services/decree/`, one project dir each — the dir name *is* the container name, which is what
`quest.sh`'s `_decree_container_for` keys off. Each mirrors the same shape (`config.exist.yml` +
`routine_source`, `cron.example/`, gitignored runtime dirs), and both mount `automations/`'s
`shared_routines/`, `lib/` and `runs/`, so logs from either land in one audit trail.

| | `decree` (`decree/`) | `decree-backup` (`decree-backup/`) |
|---|---|---|
| Runs | routing, notes, triage, service-health, agent-task, **every service's migrations** | `volume-backup`, `db-backup`, `sqlite-backup`, `workspace-sync` |
| Sees | `/repo` read-only, `/workspace` read-write, `decree_data` | `volumes/` read-write, `/workspace` read-only |
| Credentials | enumerated, only the keys its routines use | the **master `.env`** via `env_file` |
| AI CLI | `DECREE_AI` from `.env` (opencode) | none — `DECREE_AI=` blanked to override `env_file` |

The split is the whole design. Backups need every volume and every DB credential; nothing else
does, and the container that runs an agent with terminal access must not have them. So `decree`
gets breadth of *reach* (it talks to services over the bridge, which needs no volume at all) and
`decree-backup` gets breadth of *data*, and neither gets both.

This replaced a `<slug>-decree` sidecar per backup-eligible service. Those isolated each service
to its own volumes and creds, which was stricter — the trade was deliberate: ten sidecars meant a
`decree/` subdir, a `cron.example/`, five gitignored runtime dirs and ~30 lines of hand-maintained
volume and credential YAML **per service**, against a repo whose whole claim is that adding a
service is adding a folder. Now a new service's backup is one cron file in
`decree-backup/cron.example/`, because `volumes/` is mounted wholesale and its dir appears there
the moment `generate-compose.ts` creates it. **Do not add a new `*-decree` sidecar.**

**Migration ordering.** `entrypoint.sh` gates `decree process` on `/work/exist.test.sh` passing,
retrying for `DECREE_MIGRATE_TIMEOUT` (300s). `decree`'s migrations target *other* services, so
that file is `services/decree/migration-gate.sh`, which probes each service it migrates and skips
the ones whose `EXIST_IS_*` flag is false. Add a migration for a new service and you add its probe
there. `decree-backup` mounts no such file, so it correctly skips the wait entirely.

**`decree-webhook` does not use this image.** It is a static Go binary
(`services/decree/webhook/`) on `distroless`, built by compose from its own `Dockerfile` rather
than by `existential-adhoc`, and shares nothing with the daemon but the inbox bind mount.
Because distroless ships no shell, curl or wget, its healthcheck is the binary probing itself
(`/webhook -healthcheck`). Its `README.md` documents the config-driven route table and the
behaviours that differ from a plain JSON endpoint — read it before changing anything in
`webhook/`.
