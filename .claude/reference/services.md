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
  3. exist.test.sh    Sidecar retries until this passes (service healthy)
  4. decree process   Runs pending one-time migrations from <service>/decree/migrations/
On demand:
  exist.<action>.sh   ./existential.sh run <slug> <action> — interactive/manual, documented as quest
  exist.test.sh       ./existential.sh run <slug> test — read-only validation
```

| Script | Write when… |
|---|---|
| `exist.initial.sh` | Files/dirs/system config needed before container start. Idempotent. |
| migration `migrations/<name>.md` | Post-startup setup (API calls, user creation, seeds). Runs once. |
| `exist.<action>.sh` | Interactive on-demand ops a user triggers. Document in a quest. |
| `exist.test.sh` | Always. Every service ships one. Also the sidecar health gate. See `testing.md`. |

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

The `*-decree` backup sidecars run as the host user like everything else — the volume data they
tar is host-owned by the `volumes/` convention, so they need no extra privilege. **DB/cache
images** (postgres, mariadb, mongo, redis) also run as the host user, but the data volume must be
owned by that uid first — pinning `user:` on a dir already initialized under the image's old
service uid breaks startup until the volume is `chown`-ed. Never use `user: "0:0"`.

## Decree image & sidecars

The decree image is built **once** from `automations/Dockerfile` by `existential-adhoc`, tagged
`existential/decree:local`; main `decree` and every `*-decree` sidecar reference it via `image:`
(not rebuild). WORKDIR is `/work` (project at `/work/.decree`). Baked healthcheck: `grep -q
decree /proc/1/comm` with a long `start-period` (330s) so a sidecar running as `bash` during its
migration wait shows `starting`, not `unhealthy`. Adhoc disables the healthcheck.

Each backup-eligible service ships a `decree/` subdir + a `<slug>-decree` sidecar that mounts
**only its own volumes** and receives **only its own DB creds** (no master `.env`). All daemons
share `automations/`'s `shared_routines/`, `lib/`, `runs/` via read-only mounts (routines at
`/work/.decree/shared_routines`), so logs from every daemon land in one audit trail. Sidecar
`decree/` dirs mirror the main daemon (`config.exist.yml` + `routine_source`, `cron.example/`,
gitignored runtime dirs).

**`decree-webhook` does not use this image.** It is a static Go binary
(`services/decree/webhook/`) on `distroless`, built by compose from its own `Dockerfile` rather
than by `existential-adhoc`, and shares nothing with the daemon but the inbox bind mount.
Because distroless ships no shell, curl or wget, its healthcheck is the binary probing itself
(`/webhook -healthcheck`). Its `README.md` documents the config-driven route table and the
behaviours that differ from a plain JSON endpoint — read it before changing anything in
`webhook/`.
