#!/usr/bin/env tsx
/**
 * Generate a unified docker-compose.yml from all enabled services.
 *
 * Reads EXIST_IS_*=true entries from <repo>/.env.shared, finds the corresponding
 * docker-compose.yml for each enabled service, adjusts relative paths so they
 * resolve correctly from the repo root, then merges everything into one file.
 *
 * Usage (inside existential-adhoc container):
 *   tsx /src/generate-compose.ts /repo [output-filename]
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// ── .env parsing ──────────────────────────────────────────────────────────────

function loadEnv(filePath: string): Record<string, string> {
  const env: Record<string, string> = {};
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    for (const raw of content.split('\n')) {
      const line = raw.trim();
      if (!line || line.startsWith('#') || !line.includes('=')) continue;
      const eqIdx = line.indexOf('=');
      const key = line.slice(0, eqIdx).trim();
      let value = line.slice(eqIdx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      env[key] = value;
    }
  } catch {
    // file not found — return empty
  }
  return env;
}

// ── Service discovery ──────────────────────────────────────────────────────────

const SKIP_DIRS = new Set(['graveyard', '.git', 'site', 'src', 'automations', 'node_modules', 'volumes']);

function serviceEnvKey(relPath: string): string {
  return 'EXIST_IS_' + relPath.toUpperCase().replace(/[^A-Z0-9]/g, '_');
}

function findEnabledServices(repoRoot: string, env: Record<string, string>): string[] {
  const enabled: string[] = [];
  const topEntries = fs.readdirSync(repoRoot, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name));

  for (const top of topEntries) {
    if (!top.isDirectory() || SKIP_DIRS.has(top.name) || top.name.startsWith('.')) continue;
    const topPath = path.join(repoRoot, top.name);
    const subEntries = fs.readdirSync(topPath, { withFileTypes: true })
      .sort((a, b) => a.name.localeCompare(b.name));

    for (const sub of subEntries) {
      if (!sub.isDirectory()) continue;
      const composePath = path.join(topPath, sub.name, 'docker-compose.yml');
      if (fs.existsSync(composePath)) {
        const rel = `${top.name}/${sub.name}`;
        if ((env[serviceEnvKey(rel)] ?? 'false').toLowerCase() === 'true') {
          enabled.push(rel);
        }
      }
    }
  }
  return enabled;
}

// ── Path adjustment ────────────────────────────────────────────────────────────

type VolumeEntry = string | Record<string, unknown>;

interface VolumeContext {
  servicePrefix: string;
  volumeSpec: Record<string, VolumeSpec>;
  hostRepoRoot: string;
  nfsHostMount: string;
  repoRoot: string;
  /** EXIST_GPU_VENDOR — nvidia leaves templates alone; amd/none rewrite them. */
  gpuVendor: string;
}

/**
 * A volume's declared properties, from a service's top-level `x-exist-volumes`
 * block. The block is the single record of what a volume *is*; the directory it
 * ends up in is derived from it, never the other way round.
 *
 *     x-exist-volumes:
 *       nextcloud_data:     { nfs: true }
 *       nextcloud_sql_data: { db: true }        # embedded DB — never NFS
 *       ollama_cache:       {}                  # regenerable, local
 *
 * `nfs: true` is the only thing that moves a volume off local disk, and only
 * when EXIST_NFS_HOST_MOUNT is set. `db: true` records that the volume holds an
 * embedded database (SQLite/bbolt/TSDB/postgres data dir), which NFS corrupts —
 * validate conventions rejects `nfs: true` alongside it.
 */
interface VolumeSpec {
  nfs?: boolean;
  db?: boolean;
  backup?: boolean;
}

const VOLUME_SPEC_KEY = 'x-exist-volumes';

// True when some `<name>.exist.<ext>` template renders to this exact path — i.e.
// the destination is a file existential writes, not a directory to pre-create.
// Mirrors _template_to_dst in src/templates.sh: `foo.exist.bar` -> `foo.bar`,
// and `foo.exist.foo` (same word either side) -> `foo`.
function hasTemplateFor(abs: string): boolean {
  const dir = path.dirname(abs);
  const base = path.basename(abs);
  let entries: string[];
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return false;
  }
  return entries.some((name) => {
    const i = name.indexOf('.exist.');
    if (i < 0) return false;
    const before = name.slice(0, i);
    const after = name.slice(i + '.exist.'.length);
    const dst = before.toLowerCase() === after.toLowerCase() ? before : `${before}.${after}`;
    return dst === base;
  });
}

// A relative bind-mount source that does not exist yet is a trap: `docker compose
// up` asks the daemon for a path that is not there, and the daemon creates it as
// an empty root:root directory. That shadows whatever the image had at the mount
// point (hermes' .venv, gateway, node_modules and ui-tui are exactly this) and
// leaves behind a directory the host user cannot delete on the next render.
//
// Creating it here gets in first: this runs inside the adhoc container, which
// `run_adhoc` starts as the host uid:gid, so the daemon always finds an existing,
// correctly-owned directory. Only ever creates — never chowns, never touches
// anything that already exists. `./existential.sh run fix-permissions` is the
// repair path for a checkout that already has root-owned directories.
function ensureBindSource(rel: string, ctx: VolumeContext): void {
  // A source with a file extension is a file mount (a rendered .yml/.json/.conf).
  // Creating a directory there would make the container see an empty dir instead
  // of the file. Node reports '' for dot-leading names like '.venv', so those are
  // correctly treated as directories.
  if (path.extname(rel) !== '') return;

  // Never create outside the repo. A '../' chain that escapes the root is a
  // template bug, and silently materialising it elsewhere on the host hides it.
  const root = path.resolve(ctx.repoRoot);
  const abs = path.resolve(root, rel);
  if (abs !== root && !abs.startsWith(root + path.sep)) return;

  if (fs.existsSync(abs)) return;

  // Extension is not enough: hosting/caddy/Caddyfile is an extensionless SINGLE
  // FILE, rendered from Caddyfile.exist.Caddyfile. mkdir there mounts an empty
  // directory over caddy's config (it then fails to start) and blocks the next
  // render from writing the file. A sibling `<name>.exist.*` template is the
  // repo's own record that this destination is a rendered file, so ask it.
  if (hasTemplateFor(abs)) return;

  fs.mkdirSync(abs, { recursive: true });
}

function adjustVolume(vol: VolumeEntry, ctx: VolumeContext): VolumeEntry {
  if (typeof vol === 'object' && vol !== null) {
    const src = vol['source'] as string | undefined;
    if (src && !src.startsWith('/')) {
      const rel = path.normalize(path.join(ctx.servicePrefix, src));
      if (!src.startsWith('$')) ensureBindSource(rel, ctx);
      return { ...vol, source: rel };
    }
    return vol;
  }

  if (typeof vol !== 'string' || !vol.includes(':')) return vol;

  const parts = vol.split(':');
  const src = parts[0];

  // Env-var-rooted path — resolved by Docker, leave as-is.
  if (src.startsWith('$')) return vol;

  // Absolute path — leave unchanged.
  if (src.startsWith('/')) return vol;

  // Named volume (no leading dot, no path separator) — materialise as a host
  // bind mount, placed by its x-exist-volumes declaration.
  if (!src.startsWith('.') && !src.includes('/')) {
    const name = src;
    const spec = ctx.volumeSpec[name];

    // An undeclared name is not a Docker-managed volume by default — that is the
    // one thing this repo never wants (opaque, re-inits from the image, wrong
    // UID on NFS). Fail loudly instead of silently creating one.
    if (!spec) {
      process.stderr.write(
        `ERROR: volume '${name}' is mounted by ${ctx.servicePrefix} but not declared.\n` +
        `  Add it to the '${VOLUME_SPEC_KEY}:' block in that service's docker-compose.exist.yml:\n` +
        `\n    ${VOLUME_SPEC_KEY}:\n      ${name}: {}\n\n` +
        `  See .claude/reference/volumes.md for the properties.\n`,
      );
      process.exit(1);
    }

    let hostPath: string;
    if (spec.nfs && ctx.nfsHostMount) {
      // Lives on the NAS export, which the host mounts (fstab/autofs). Create the
      // per-volume directory inside it so Docker never root-creates one — but
      // only when the mountpoint itself is present. Creating it while the export
      // is unmounted would quietly write to the empty local mountpoint, and the
      // data would vanish the moment it mounted.
      hostPath = `${ctx.nfsHostMount}/${name}`;
      if (fs.existsSync(ctx.nfsHostMount)) {
        fs.mkdirSync(hostPath, { recursive: true });
      }
    } else {
      hostPath = `${ctx.hostRepoRoot}/volumes/${name}`;
      fs.mkdirSync(path.join(ctx.repoRoot, 'volumes', name), { recursive: true });
    }
    parts[0] = hostPath;
    return parts.join(':');
  }

  // Relative path — rewrite under service prefix, creating the source directory
  // so the Docker daemon never has to (see ensureBindSource above).
  const rel = path.normalize(path.join(ctx.servicePrefix, src));
  ensureBindSource(rel, ctx);
  parts[0] = './' + rel;
  return parts.join(':');
}

function adjustBuild(
  build: string | Record<string, unknown> | null | undefined,
  servicePrefix: string,
): typeof build {
  if (build == null) return build;
  if (typeof build === 'string') {
    return build.startsWith('/') ? build : './' + path.normalize(path.join(servicePrefix, build));
  }
  if (typeof build === 'object') {
    const ctx = build['context'] as string | undefined;
    if (ctx && !ctx.startsWith('/')) {
      return { ...build, context: './' + path.normalize(path.join(servicePrefix, ctx)) };
    }
  }
  return build;
}

function adjustEnvFile(
  ef: string | string[] | null | undefined,
  servicePrefix: string,
): typeof ef {
  if (ef == null) return ef;
  if (typeof ef === 'string') {
    return ef.startsWith('/') ? ef : path.join(servicePrefix, ef);
  }
  return ef.map(f => (typeof f === 'string' && !f.startsWith('/')) ? path.join(servicePrefix, f) : f);
}

/**
 * Remove GPU device reservations from a service.
 *
 * `deploy.resources.reservations.devices: [{driver: nvidia, capabilities: [gpu]}]`
 * is not a soft preference — on a host with no nvidia container runtime docker
 * refuses to create the container at all ("could not select device driver ...
 * with capabilities: [[gpu]]"), so a single GPU-reserving service takes down
 * `docker compose up` for the whole stack.
 *
 * That is what makes any non-nvidia host impossible without this: four services
 * declare the reservation (ollama, comfyui, whisperx, chatterbox) and ollama is
 * in Core. Stripping it here keeps the reservation in the templates — where it
 * is correct for the majority — rather than forking them per vendor.
 *
 * Applied for `none`, `amd` and `external` alike: an AMD card is no more able to
 * satisfy a `driver: nvidia` reservation than no card at all, and an `external`
 * host has no card to reserve because the models are on another machine. What
 * AMD gets instead comes from the service's own `x-exist-gpu.amd` block — see
 * applyGpuOverlay.
 *
 * This only makes the containers *start*. A service whose whole job is GPU work
 * (comfyui; whisperx and chatterbox with their cuda settings) is still not
 * useful on a CPU-only host. Core includes none of them.
 */
function stripGpuReservations(svc: Record<string, unknown>): Record<string, unknown> {
  const deploy = svc['deploy'] as Record<string, unknown> | undefined;
  const resources = deploy?.['resources'] as Record<string, unknown> | undefined;
  const reservations = resources?.['reservations'] as Record<string, unknown> | undefined;
  const devices = reservations?.['devices'];
  if (!Array.isArray(devices)) return svc;

  const kept = devices.filter(d => {
    const dev = (d ?? {}) as Record<string, unknown>;
    const caps = dev['capabilities'];
    const isGpu = (Array.isArray(caps) && caps.includes('gpu')) || dev['driver'] === 'nvidia';
    return !isGpu;
  });
  if (kept.length === devices.length) return svc;

  // Prune the now-empty ancestors rather than leaving `reservations: {}` behind:
  // compose accepts it, but it reads as "something was meant to be here".
  const newReservations: Record<string, unknown> = { ...reservations };
  if (kept.length) newReservations['devices'] = kept;
  else delete newReservations['devices'];

  const newResources: Record<string, unknown> = { ...resources };
  if (Object.keys(newReservations).length) newResources['reservations'] = newReservations;
  else delete newResources['reservations'];

  const newDeploy: Record<string, unknown> = { ...deploy };
  if (Object.keys(newResources).length) newDeploy['resources'] = newResources;
  else delete newDeploy['resources'];

  const out = { ...svc };
  if (Object.keys(newDeploy).length) out['deploy'] = newDeploy;
  else delete out['deploy'];
  return out;
}

/** The per-service, per-vendor overlay key. */
const GPU_OVERLAY_KEY = 'x-exist-gpu';

/** Vendors this generator knows how to wire. Mirrors src/utils/gpu-vendor.sh. */
const GPU_VENDORS = ['nvidia', 'amd', 'none', 'external'] as const;

/**
 * Decide the GPU vendor from the environment.
 *
 * EXIST_GPU_VENDOR is authoritative once set. When it is blank, what happens
 * next turns on whether EXIST_VRAM_GB was answered:
 *
 *   VRAM set    — an install that predates the vendor question. Fall back to
 *                 what VRAM already implied: 0 meant "no GPU", anything else
 *                 meant nvidia. Those .env.shared files keep generating exactly
 *                 the compose file they generated before this setting existed.
 *   VRAM blank  — NOTHING has been answered. Both keys ship blank, so this is a
 *                 render that never reached quest: a fresh clone, CI, the e2e
 *                 harness. Assuming nvidia there hands every non-nvidia host a
 *                 reservation its daemon cannot satisfy, and docker fails the
 *                 whole `up`, not just the GPU service. `none` is the only safe
 *                 guess: it costs an nvidia host acceleration until it answers
 *                 the question, where the other way costs everyone else a stack
 *                 that will not start.
 *
 * An unrecognised value is a typo, not a new vendor. Failing closed to nvidia
 * would silently hand an AMD host a reservation its daemon cannot satisfy, so
 * say so loudly and stop — a wrong compose file here breaks `up` for the whole
 * stack, and the error it produces points at docker, not at this typo.
 */
function resolveGpuVendor(env: Record<string, string>): string {
  const explicit = (env['EXIST_GPU_VENDOR'] ?? '').trim().toLowerCase();
  if (!explicit) {
    const vram = (env['EXIST_VRAM_GB'] ?? '').trim();
    if (vram === '') return 'none';
    return vram === '0' ? 'none' : 'nvidia';
  }
  if (!(GPU_VENDORS as readonly string[]).includes(explicit)) {
    process.stderr.write(
      `ERROR: EXIST_GPU_VENDOR='${explicit}' is not one of: ${GPU_VENDORS.join(', ')}.\n` +
      '  Fix it in .env.shared, or re-run: ./existential.sh run models\n',
    );
    process.exit(1);
  }
  return explicit;
}

/**
 * Apply a service's `x-exist-gpu.<vendor>` block, and drop the key either way.
 *
 * Vendor-specific wiring lives with the service rather than in a lookup table
 * here, because "adding a service is adding a folder" — a table of container
 * names in this file would make that sentence less true, and every new GPU
 * service would need an edit in two places.
 *
 * Shape, in a service's docker-compose.exist.yml:
 *
 *     x-exist-gpu:
 *       amd:
 *         privileged: true
 *         environment:
 *           OLLAMA_VULKAN: "1"
 *
 * The merge is one level deep and last-wins, with `environment` merged rather
 * than replaced so an overlay can set one variable without restating the rest.
 * A list-form `environment:` (`- KEY=value`) is normalised to map form first,
 * so a template can use either style and an overlay still lands correctly.
 *
 * nvidia is deliberately not an overlay: it is what the templates already say.
 */
function applyGpuOverlay(svc: Record<string, unknown>, vendor: string): Record<string, unknown> {
  const overlay = svc[GPU_OVERLAY_KEY] as Record<string, unknown> | undefined;
  const out = { ...svc };
  delete out[GPU_OVERLAY_KEY];
  if (!overlay || typeof overlay !== 'object') return out;

  const block = overlay[vendor] as Record<string, unknown> | undefined;
  if (!block || typeof block !== 'object') return out;

  for (const [key, value] of Object.entries(block)) {
    if (key === 'environment') {
      out['environment'] = { ...toEnvMap(out['environment']), ...toEnvMap(value) };
    } else {
      out[key] = value;
    }
  }
  return out;
}

/**
 * Normalise compose's two `environment:` spellings to map form.
 *
 * A list entry with no `=` ("PATH") means "inherit from the host" in compose,
 * which is a null value in map form — not an empty string, which would instead
 * set the variable to nothing.
 */
function toEnvMap(env: unknown): Record<string, unknown> {
  if (!env) return {};
  if (Array.isArray(env)) {
    const map: Record<string, unknown> = {};
    for (const entry of env) {
      if (typeof entry !== 'string') continue;
      const eq = entry.indexOf('=');
      if (eq === -1) map[entry] = null;
      else map[entry.slice(0, eq)] = entry.slice(eq + 1);
    }
    return map;
  }
  if (typeof env === 'object') return { ...(env as Record<string, unknown>) };
  return {};
}

function adjustServicePaths(svc: Record<string, unknown>, ctx: VolumeContext): Record<string, unknown> {
  // nvidia is the templates' own default, so it is a pure no-op beyond dropping
  // the overlay key. Anything else cannot satisfy a `driver: nvidia`
  // reservation, so the reservation goes and the vendor's overlay comes in.
  const out = ctx.gpuVendor === 'nvidia'
    ? applyGpuOverlay(svc, ctx.gpuVendor)
    : applyGpuOverlay(stripGpuReservations(svc), ctx.gpuVendor);
  if (Array.isArray(out['volumes'])) {
    out['volumes'] = (out['volumes'] as VolumeEntry[]).map(v => adjustVolume(v, ctx));
  }
  if ('build' in out) {
    out['build'] = adjustBuild(out['build'] as string | Record<string, unknown>, ctx.servicePrefix);
  }
  if ('env_file' in out) {
    out['env_file'] = adjustEnvFile(out['env_file'] as string | string[], ctx.servicePrefix);
  }
  return out;
}

// ── Merge ──────────────────────────────────────────────────────────────────────

function merge(
  repoRoot: string,
  hostRepoRoot: string,
  enabled: string[],
  nfsHostMount: string,
  networkExternal = false,
  gpuVendor = 'nvidia',
): Record<string, unknown> {
  // First pass: collect every enabled service's x-exist-volumes declarations.
  // Volumes are shared across services by name (decree-backup mounts the same
  // dir as the app it archives), so the spec is merged repo-wide, first wins.
  const volumeSpec: Record<string, VolumeSpec> = {};
  for (const relPath of enabled) {
    const composePath = path.join(repoRoot, relPath, 'docker-compose.yml');
    if (!fs.existsSync(composePath)) continue;
    const config = (yaml.load(fs.readFileSync(composePath, 'utf8')) ?? {}) as Record<string, unknown>;
    for (const [name, spec] of Object.entries((config[VOLUME_SPEC_KEY] ?? {}) as Record<string, VolumeSpec>)) {
      if (!(name in volumeSpec)) volumeSpec[name] = spec ?? {};
    }
  }

  // Second pass: merge services, materialising named volumes as host bind mounts.
  const services: Record<string, unknown> = {};
  const networks: Record<string, unknown> = {};

  for (const relPath of enabled) {
    const composePath = path.join(repoRoot, relPath, 'docker-compose.yml');
    if (!fs.existsSync(composePath)) {
      process.stderr.write(`warning: ${composePath} not found — skipping\n`);
      continue;
    }
    const config = (yaml.load(fs.readFileSync(composePath, 'utf8')) ?? {}) as Record<string, unknown>;

    const ctx: VolumeContext = { servicePrefix: relPath, volumeSpec, hostRepoRoot, nfsHostMount, repoRoot, gpuVendor };

    for (const [name, svc] of Object.entries((config['services'] ?? {}) as Record<string, Record<string, unknown>>)) {
      services[name] = adjustServicePaths(svc ?? {}, ctx);
    }
    for (const [name, net] of Object.entries((config['networks'] ?? {}) as Record<string, unknown>)) {
      if (!(name in networks)) networks[name] = net;
    }
  }

  // Always use the configured exist network definition, ignoring per-service declarations.
  networks['exist'] = networkExternal ? { external: true } : { driver: 'bridge' };

  const result: Record<string, unknown> = {};
  if (Object.keys(services).length) result['services'] = services;
  // Never emit a top-level volumes: block — all volumes are host bind mounts.
  result['networks'] = networks;
  return result;
}

// ── Master .env generation ─────────────────────────────────────────────────────

function mergeEnv(repoRoot: string, enabled: string[]): void {
  const merged: Record<string, string> = {};
  const paths = [
    path.join(repoRoot, '.env.shared'),
    ...enabled.map(r => path.join(repoRoot, r, '.env')),
  ];
  for (const p of paths) Object.assign(merged, loadEnv(p));

  const header = [
    '# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n',
    '# DO NOT EDIT — this file is auto-generated by existential.sh\n',
    '# Edit .env.shared (global) or service-level .env files instead\n',
    '# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n',
  ].join('');

  const envPath = path.join(repoRoot, '.env');
  // This merged file holds every service's secrets — keep it owner-only (600),
  // never the default 644. mode on writeFileSync only applies on create, so
  // chmod explicitly to cover the overwrite case too.
  fs.writeFileSync(envPath, header + Object.entries(merged).map(([k, v]) => `${k}=${v}\n`).join(''), { mode: 0o600 });
  fs.chmodSync(envPath, 0o600);
  process.stderr.write(`Written: ${envPath}\n`);
}

// ── Volumes ──────────────────────────────────────────────────────────────────
//
// We never use Docker-managed (opaque) volumes. Every volume becomes a host bind
// mount. Named volumes and NFS volumes declared in a top-level `volumes:` block are
// materialised by adjustVolume:
//   • non-NFS named volume:  → <hostRepoRoot>/volumes/<name>  (dir created locally)
//   • NFS named volume + no host mount: same local fallback
//   • NFS named volume + EXIST_NFS_HOST_MOUNT set: → <hostMount>/<name>
// The top-level `volumes:` block is never emitted in the output.

// ── Archive rotation ───────────────────────────────────────────────────────────

// How many timestamped docker-compose-<stamp>.yml archives to retain. The
// previous compose is archived on every run; without a cap these accumulate
// forever in the repo root.
const KEEP_ARCHIVES = 3;

function pruneArchives(repoRoot: string, keep: number): void {
  const archiveDir = path.join(repoRoot, 'archive');
  if (!fs.existsSync(archiveDir)) return;
  const archives = fs.readdirSync(archiveDir)
    .filter(f => /^docker-compose-[0-9].*\.yml$/.test(f))
    .sort();                       // lexical sort == chronological (ISO-ish stamp)
  for (const f of archives.slice(0, Math.max(0, archives.length - keep))) {
    try {
      fs.unlinkSync(path.join(archiveDir, f));
      process.stderr.write(`Pruned old archive: ${f}\n`);
    } catch { /* best-effort */ }
  }
}

// ── Entry point ────────────────────────────────────────────────────────────────

function main(): void {
  const [,, repoRoot, outputName = 'docker-compose.yml', hostRepoRoot = repoRoot] = process.argv;
  if (!repoRoot) {
    process.stderr.write('Usage: generate-compose.ts <repo_root> [output-filename] [host-repo-root]\n');
    process.exit(1);
  }

  const outputPath = path.join(repoRoot, outputName);
  const env = loadEnv(path.join(repoRoot, '.env.shared'));
  const enabled = findEnabledServices(repoRoot, env);

  if (!enabled.length) {
    process.stderr.write('No services enabled — set EXIST_IS_*=true in .env.shared\n');
    process.exit(0);
  }

  process.stderr.write(`Enabled (${enabled.length}): ${enabled.join(', ')}\n`);

  const nfsHostMount = (env['EXIST_NFS_HOST_MOUNT'] ?? '').trim();
  if ((env['EXIST_NFS_SERVER_ADDRESS'] ?? '').trim() && !nfsHostMount) {
    process.stderr.write(
      'ERROR: EXIST_NFS_SERVER_ADDRESS is set but EXIST_NFS_HOST_MOUNT is empty.\n' +
      '  Persistent data is bind-mounted from a host path — the NFS share must be mounted\n' +
      '  on the host (fstab/autofs), then set EXIST_NFS_HOST_MOUNT to that mountpoint\n' +
      '  (e.g. /mnt/nas). See the NAS Storage quest. Refusing to silently fall back to\n' +
      '  local disk for data you expect on NFS.\n',
    );
    process.exit(1);
  }

  const networkExternal = (env['EXIST_NETWORK_EXTERNAL'] ?? 'false').toLowerCase() === 'true';

  const gpuVendor = resolveGpuVendor(env);
  if (gpuVendor !== 'nvidia') {
    process.stderr.write(
      `EXIST_GPU_VENDOR=${gpuVendor} — stripping nvidia reservations` +
      `, applying ${GPU_OVERLAY_KEY}.${gpuVendor} overlays\n`,
    );
  }

  const merged = merge(repoRoot, hostRepoRoot, enabled, nfsHostMount, networkExternal, gpuVendor);

  mergeEnv(repoRoot, enabled);

  if (fs.existsSync(outputPath)) {
    const now = new Date();
    const stamp = now.toISOString().slice(0, 19).replace('T', '_').replace(/:/g, '-');
    // Same archive/ directory  uses, so generated files
    // never accumulate in the repo root.
    const archiveDir = path.join(repoRoot, 'archive');
    fs.mkdirSync(archiveDir, { recursive: true });
    const backup = path.join(archiveDir, `docker-compose-${stamp}.yml`);
    fs.renameSync(outputPath, backup);
    process.stderr.write(`Archived: ${backup}\n`);
    pruneArchives(repoRoot, KEEP_ARCHIVES);
  }

  const content = '# Generated by existential.sh — do not edit manually\n' +
    yaml.dump(merged, { noRefs: true, sortKeys: false });
  fs.writeFileSync(outputPath, content);
  process.stderr.write(`Written: ${outputPath}\n`);
}

main();
