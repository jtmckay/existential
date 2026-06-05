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

function adjustVolume(vol: VolumeEntry, servicePrefix: string): VolumeEntry {
  if (typeof vol === 'object' && vol !== null) {
    const src = vol['source'] as string | undefined;
    if (src && !src.startsWith('/')) {
      return { ...vol, source: path.normalize(path.join(servicePrefix, src)) };
    }
    return vol;
  }

  if (typeof vol !== 'string' || !vol.includes(':')) return vol;

  const parts = vol.split(':');
  const src = parts[0];

  // Env-var-rooted path (e.g. ${EXIST_NFS_HOST_MOUNT}/foo) — resolved by Docker, leave as-is.
  if (src.startsWith('$')) return vol;

  // Absolute path or named volume (no leading dot or slash, and no directory separator)
  if (src.startsWith('/') || (!src.startsWith('.') && !src.includes('/') && src !== '.')) {
    return vol;
  }

  parts[0] = './' + path.normalize(path.join(servicePrefix, src));
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

function adjustServicePaths(svc: Record<string, unknown>, servicePrefix: string): Record<string, unknown> {
  const out = { ...svc };
  if (Array.isArray(out['volumes'])) {
    out['volumes'] = (out['volumes'] as VolumeEntry[]).map(v => adjustVolume(v, servicePrefix));
  }
  if ('build' in out) {
    out['build'] = adjustBuild(out['build'] as string | Record<string, unknown>, servicePrefix);
  }
  if ('env_file' in out) {
    out['env_file'] = adjustEnvFile(out['env_file'] as string | string[], servicePrefix);
  }
  return out;
}

// ── Merge ──────────────────────────────────────────────────────────────────────

function merge(repoRoot: string, enabled: string[], networkExternal = false): Record<string, unknown> {
  const services: Record<string, unknown> = {};
  const volumes: Record<string, unknown> = {};
  const networks: Record<string, unknown> = {};

  for (const relPath of enabled) {
    const composePath = path.join(repoRoot, relPath, 'docker-compose.yml');
    if (!fs.existsSync(composePath)) {
      process.stderr.write(`warning: ${composePath} not found — skipping\n`);
      continue;
    }
    const config = (yaml.load(fs.readFileSync(composePath, 'utf8')) ?? {}) as Record<string, unknown>;

    for (const [name, svc] of Object.entries((config['services'] ?? {}) as Record<string, Record<string, unknown>>)) {
      services[name] = adjustServicePaths(svc ?? {}, relPath);
    }
    for (const [name, vol] of Object.entries((config['volumes'] ?? {}) as Record<string, unknown>)) {
      if (!(name in volumes)) volumes[name] = vol;  // first definition wins
    }
    for (const [name, net] of Object.entries((config['networks'] ?? {}) as Record<string, unknown>)) {
      if (!(name in networks)) networks[name] = net;
    }
  }

  // Always use the configured exist network definition, ignoring per-service declarations
  networks['exist'] = networkExternal ? { external: true } : { driver: 'bridge' };

  const result: Record<string, unknown> = {};
  if (Object.keys(services).length) result['services'] = services;
  if (Object.keys(volumes).length) result['volumes'] = volumes;
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

// ── Volumes → host bind mounts ──────────────────────────────────────────────────

// We never use Docker-managed (opaque) volumes. Every top-level volume declared by a
// service is materialised as a host bind mount, then the top-level `volumes:` section is
// dropped entirely — so `docker volume ls` stays empty and all data lives in a visible,
// host-owned directory or on a host-mounted NFS share.
//
//   • Persistent NFS volumes (driver_opts.type: nfs) bind to ${EXIST_NFS_HOST_MOUNT}/<name>
//     when an NFS host mount is configured — the share is mounted on the *host*
//     (fstab/autofs); Docker no longer mounts NFS itself, so driver_opts is read only as a
//     persistence marker.
//   • Everything else — DBs, caches, and NFS volumes with no host mount — binds to
//     <hostRepoRoot>/volumes/<name>. That directory is created here (in the adhoc
//     container, as the host user) so Docker doesn't auto-create it as root.
function materializeBindMounts(
  merged: Record<string, unknown>,
  repoRoot: string,
  hostRepoRoot: string,
  nfsHostMount: string,
): void {
  const vols = merged['volumes'] as Record<string, unknown> | undefined;
  if (!vols) return;

  // Map each declared volume name → its host bind source path.
  const source: Record<string, string> = {};
  for (const [volName, volConfig] of Object.entries(vols)) {
    const cfg = volConfig as Record<string, unknown> | null;
    const driverOpts = cfg?.['driver_opts'] as Record<string, string> | undefined;
    const isNfs = driverOpts?.['type'] === 'nfs';

    if (isNfs && nfsHostMount) {
      source[volName] = path.posix.join(nfsHostMount, volName);
    } else {
      fs.mkdirSync(path.join(repoRoot, 'volumes', volName), { recursive: true });
      source[volName] = path.posix.join(hostRepoRoot, 'volumes', volName);
    }
  }

  // Rewrite every service's named-volume references into bind mounts.
  const services = (merged['services'] ?? {}) as Record<string, Record<string, unknown>>;
  for (const svc of Object.values(services)) {
    const list = svc['volumes'];
    if (!Array.isArray(list)) continue;
    svc['volumes'] = list.map((entry: unknown) => {
      if (typeof entry !== 'string') return entry;
      const idx = entry.indexOf(':');
      if (idx === -1) return entry;
      const src = entry.slice(0, idx);
      return (src in source) ? source[src] + entry.slice(idx) : entry;
    });
  }

  // Drop the top-level section — no Docker-managed volumes remain.
  delete merged['volumes'];
}

// ── Archive rotation ───────────────────────────────────────────────────────────

// How many timestamped docker-compose-<stamp>.yml archives to retain. The
// previous compose is archived on every run; without a cap these accumulate
// forever in the repo root.
const KEEP_ARCHIVES = 3;

function pruneArchives(repoRoot: string, keep: number): void {
  const archives = fs.readdirSync(repoRoot)
    .filter(f => /^docker-compose-[0-9].*\.yml$/.test(f))
    .sort();                       // lexical sort == chronological (ISO-ish stamp)
  for (const f of archives.slice(0, Math.max(0, archives.length - keep))) {
    try {
      fs.unlinkSync(path.join(repoRoot, f));
      process.stderr.write(`Pruned old archive: ${f}\n`);
    } catch { /* best-effort */ }
  }
}

// ── Entry point ────────────────────────────────────────────────────────────────

function main(): void {
  const [,, repoRoot, outputName = 'docker-compose.yml', hostRepoRoot] = process.argv;
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

  const networkExternal = (env['EXIST_NETWORK_EXTERNAL'] ?? 'false').toLowerCase() === 'true';
  const merged = merge(repoRoot, enabled, networkExternal);

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
  if (hostRepoRoot) {
    materializeBindMounts(merged, repoRoot, hostRepoRoot, nfsHostMount);
  }

  mergeEnv(repoRoot, enabled);

  if (fs.existsSync(outputPath)) {
    const now = new Date();
    const stamp = now.toISOString().slice(0, 19).replace('T', '_').replace(/:/g, '-');
    const backup = path.join(repoRoot, `docker-compose-${stamp}.yml`);
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
