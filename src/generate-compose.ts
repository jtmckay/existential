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
  topLevelVolumes: Record<string, unknown>;
  hostRepoRoot: string;
  nfsHostMount: string;
  repoRoot: string;
}

function isNfsVolume(vol: unknown): boolean {
  if (!vol || typeof vol !== 'object') return false;
  const opts = (vol as Record<string, unknown>)['driver_opts'] as Record<string, unknown> | undefined;
  return !!(opts && opts['type'] === 'nfs');
}

function adjustVolume(vol: VolumeEntry, ctx: VolumeContext): VolumeEntry {
  if (typeof vol === 'object' && vol !== null) {
    const src = vol['source'] as string | undefined;
    if (src && !src.startsWith('/')) {
      return { ...vol, source: path.normalize(path.join(ctx.servicePrefix, src)) };
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

  // Named volume (no leading dot, no path separator) — materialise as a host bind mount.
  if (!src.startsWith('.') && !src.includes('/')) {
    const name = src;
    const nfs = isNfsVolume(ctx.topLevelVolumes[name]);
    let hostPath: string;
    if (nfs && ctx.nfsHostMount) {
      hostPath = `${ctx.nfsHostMount}/${name}`;
    } else {
      hostPath = `${ctx.hostRepoRoot}/volumes/${name}`;
      fs.mkdirSync(path.join(ctx.repoRoot, 'volumes', name), { recursive: true });
    }
    parts[0] = hostPath;
    return parts.join(':');
  }

  // Relative path — rewrite under service prefix.
  parts[0] = './' + path.normalize(path.join(ctx.servicePrefix, src));
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

function adjustServicePaths(svc: Record<string, unknown>, ctx: VolumeContext): Record<string, unknown> {
  const out = { ...svc };
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
): Record<string, unknown> {
  // First pass: collect all top-level volume definitions (needed to detect NFS).
  const topLevelVolumes: Record<string, unknown> = {};
  for (const relPath of enabled) {
    const composePath = path.join(repoRoot, relPath, 'docker-compose.yml');
    if (!fs.existsSync(composePath)) continue;
    const config = (yaml.load(fs.readFileSync(composePath, 'utf8')) ?? {}) as Record<string, unknown>;
    for (const [name, vol] of Object.entries((config['volumes'] ?? {}) as Record<string, unknown>)) {
      if (!(name in topLevelVolumes)) topLevelVolumes[name] = vol;
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

    const ctx: VolumeContext = { servicePrefix: relPath, topLevelVolumes, hostRepoRoot, nfsHostMount, repoRoot };

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
  const merged = merge(repoRoot, hostRepoRoot, enabled, nfsHostMount, networkExternal);

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
