#!/usr/bin/env tsx
/**
 * validate-conventions.ts — verify slugs are wired consistently across
 * service compose files, piHole, Caddy, and dashy.
 *
 * Conventions checked:
 *   1. Every container_name is lowercase-hyphenated only.
 *   2. Every container_name starts with its folder's slug.
 *   3. Every piHole record has a matching Caddy reverse_proxy block.
 *   4. Every Caddy block has a matching piHole record.
 *   5. Every dashy item points at a slug that has a piHole record.
 *   6. Every key in a service's .env.exist starts with <SLUG>_.
 *   7. Every key in .env.exist.shared starts with EXIST_, no legacy prefixes.
 *   8. The master docker-compose.yml uses only host bind mounts — no top-level `volumes:`
 *      section and no bare named-volume references (`docker volume ls` stays empty).
 *  9. No service hardcodes a numeric uid/gid (`user:` or a *UID/*GID env) — all run as
 *      the host user via the `${EXIST_PUID:-1000}` convention.
 * 12. Every Caddy slug must equal the backendContainer name, or start with
 *      `{backendContainer}-`. A slug shorter/different than the container it proxies
 *      (e.g. `hermes.internal` → `hermes-agent`) is a convention violation — it implies
 *      a container that doesn't exist. When a container needs two URLs (two ports), the
 *      primary slug is the container name and any alias starts with `{container}-`.
 * 13. Every service folder has exactly one docs page (`service:` frontmatter), every such
 *      page names a real folder, and every README.md link into the docs site resolves.
 * 14. README.md and site/docs/intro.md list exactly Core's services under "## What Core installs".
 * 15. Every service in every template is `restart: unless-stopped`.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// In the adhoc container /src and /repo are separate mounts, so __dirname-relative
// resolution lands on "/" — every path below would then point at a nonexistent
// file and the check would pass vacuously. Take the repo root explicitly (argv[2]
// or $REPO_DIR, same as the other validators); fall back to __dirname for host runs.
const REPO_ROOT = path.resolve(
  process.argv[2] ?? process.env.REPO_DIR ?? path.join(__dirname, '..', '..', '..'),
);
const PIHOLE   = path.join(REPO_ROOT, 'hosting/pihole/docker-compose.exist.yml');
const CADDY    = path.join(REPO_ROOT, 'hosting/caddy/Caddyfile.exist.Caddyfile');
const DASHY    = path.join(REPO_ROOT, 'services/dashy/dashy-conf.exist.yml');
const ENV_SHARED  = path.join(REPO_ROOT, '.env.exist.shared');
const MASTER_COMPOSE = path.join(REPO_ROOT, 'docker-compose.yml');

const CATEGORY_DIRS = ['ai', 'services', 'hosting', 'nas'];

const CONTAINER_NAME_RE  = /^\s*container_name:\s*([\w-]+)\s*$/;
const PORT_LINE_RE       = /^\s*-\s*"?(?:127\.0\.0\.1:)?(?:\$\{[^}]+\}|\d+):(\d+)(?:\/(?:tcp|udp))?"?\s*(?:#.*)?$/;
// Caddy hostnames use Caddy's env form `<slug>.{$CADDY_DOMAIN}` (resolved at runtime
// from the container env, NOT rendered). The validator reads the file, so it matches
// the literal token. (Dashy uses the bare EXIST_DOMAIN form — see DASHY_URL_RE.)
const CADDY_HEADER_RE    = /^([\w-]+)\.\{\$CADDY_DOMAIN\}\s*\{/;
// An upstream may be a Caddy env expansion with a default -- `{$VAR:host:port}` --
// used where the destination is configurable (ollama can live on another box).
// The default is what ships, so it is what the slug/container convention is
// checked against; a deployment that overrides the env var is deliberately
// pointing the hostname somewhere this repo cannot know about.
const CADDY_PROXY_RE     = /^\s*reverse_proxy\s+(?:\{\$[A-Z_][A-Z0-9_]*:)?(?:https?:\/\/)?([\w-]+):(\d+|\{[^}]+\})/;
// piHole no longer enumerates slugs — a single wildcard record points the whole
// EXIST_DOMAIN at the Caddy host. This is the line we assert exists.
const PIHOLE_WILDCARD_RE = /address=\/\$\{EXIST_DOMAIN\}\/\$\{EXIST_LOCAL_HOST_IP\}/;
const DASHY_URL_RE       = /^\s*url:\s*https?:\/\/([\w-]+)\.EXIST_DOMAIN\/?\s*$/;
const ENV_KEY_LINE_RE    = /^([A-Z_][A-Z0-9_]*)=/;

// ── Types ──────────────────────────────────────────────────────────────────────

interface ServiceDecl {
  slug: string;
  file: string;
  line: number;
  folderSlug: string;
  ports: number[];
}

interface CaddyBlock {
  slug: string;
  backendContainer: string;
  backendPort: string;
  line: number;
}

interface DashyItem {
  slug: string;
  line: number;
}

// ── Parsers ────────────────────────────────────────────────────────────────────

function parseServiceComposes(): Map<string, ServiceDecl> {
  const services = new Map<string, ServiceDecl>();

  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;

    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const composePath = path.join(catPath, entry.name, 'docker-compose.exist.yml');
      if (!fs.existsSync(composePath)) continue;

      const folderSlug = entry.name;
      let currentDecl: ServiceDecl | null = null;
      const lines = fs.readFileSync(composePath, 'utf8').split('\n');

      for (let lineno = 0; lineno < lines.length; lineno++) {
        const raw = lines[lineno];
        const nm = CONTAINER_NAME_RE.exec(raw);
        if (nm) {
          currentDecl = {
            slug: nm[1],
            file: composePath,
            line: lineno + 1,
            folderSlug,
            ports: [],
          };
          if (!services.has(nm[1])) services.set(nm[1], currentDecl);
          continue;
        }
        if (!currentDecl) continue;
        const pm = PORT_LINE_RE.exec(raw);
        if (pm) currentDecl.ports.push(parseInt(pm[1], 10));
      }
    }
  }

  return services;
}

function checkPiholeWildcard(): string[] {
  const errors: string[] = [];

  if (fs.existsSync(PIHOLE)) {
    const body = fs.readFileSync(PIHOLE, 'utf8');
    if (!PIHOLE_WILDCARD_RE.test(body)) {
      errors.push(
        `hosting/pihole/docker-compose.exist.yml: ` +
        `missing the wildcard DNS record ` +
        `'address=/\${EXIST_DOMAIN}/\${EXIST_LOCAL_HOST_IP}' ` +
        `(FTLCONF_misc_dnsmasq_lines) — without it no '<slug>.<domain>' resolves`,
      );
    }
  }

  if (fs.existsSync(ENV_SHARED)) {
    const hasDomain = envFileKeys(ENV_SHARED).some(([, k]) => k === 'EXIST_DOMAIN');
    if (!hasDomain) {
      errors.push(
        `.env.exist.shared: EXIST_DOMAIN is not defined — ` +
        `every '<slug>.<domain>' hostname depends on it`,
      );
    }
  }

  return errors;
}

function parseCaddy(): Map<string, CaddyBlock> {
  const blocks = new Map<string, CaddyBlock>();
  if (!fs.existsSync(CADDY)) return blocks;

  let currentSlug: string | null = null;
  let currentLine = 0;
  const lines = fs.readFileSync(CADDY, 'utf8').split('\n');

  for (let lineno = 0; lineno < lines.length; lineno++) {
    const raw = lines[lineno];
    const hm = CADDY_HEADER_RE.exec(raw);
    if (hm) { currentSlug = hm[1]; currentLine = lineno + 1; continue; }
    if (currentSlug) {
      const pm = CADDY_PROXY_RE.exec(raw);
      if (pm) {
        blocks.set(currentSlug, {
          slug: currentSlug,
          backendContainer: pm[1],
          backendPort: pm[2],
          line: currentLine,
        });
        currentSlug = null;
      }
    }
  }

  return blocks;
}

function parseDashy(): DashyItem[] {
  const items: DashyItem[] = [];
  if (!fs.existsSync(DASHY)) return items;

  const lines = fs.readFileSync(DASHY, 'utf8').split('\n');
  for (let lineno = 0; lineno < lines.length; lineno++) {
    const raw = lines[lineno];
    if (raw.trimStart().startsWith('#')) continue;
    const m = DASHY_URL_RE.exec(raw);
    if (m) items.push({ slug: m[1], line: lineno + 1 });
  }

  return items;
}

// ── Env checks ─────────────────────────────────────────────────────────────────

function envFileKeys(filePath: string): Array<[number, string]> {
  if (!fs.existsSync(filePath)) return [];
  const out: Array<[number, string]> = [];
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (!raw.trim() || raw.trimStart().startsWith('#')) continue;
    const m = ENV_KEY_LINE_RE.exec(raw);
    if (m) out.push([i + 1, m[1]]);
  }
  return out;
}

function checkServiceEnvPrefixes(): string[] {
  const errors: string[] = [];
  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;

    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const envFile = path.join(catPath, entry.name, '.env.exist');
      if (!fs.existsSync(envFile)) continue;

      const head = fs.readFileSync(envFile, 'utf8').split('\n').slice(0, 5).join('\n');
      if (head.includes('convention-exempt: upstream-env')) continue;

      const slug = entry.name;
      const prefix = slug.replace(/-/g, '_').toUpperCase() + '_';
      const rel = path.relative(REPO_ROOT, envFile);

      for (const [lineno, key] of envFileKeys(envFile)) {
        if (!key.startsWith(prefix)) {
          errors.push(
            `${rel}:${lineno}: key '${key}' must start with '${prefix}' ` +
            `(map image-required names like MYSQL_USER in docker-compose.exist.yml instead)`,
          );
        }
      }
    }
  }
  return errors;
}

function checkTopLevelEnvKeys(): string[] {
  const errors: string[] = [];
  for (const [lineno, key] of envFileKeys(ENV_SHARED)) {
    if (!key.startsWith('EXIST_')) {
      errors.push(`.env.exist.shared:${lineno}: key '${key}' must start with 'EXIST_'`);
      continue;
    }
    if (key.startsWith('EXIST_DEFAULT_')) {
      const newKey = 'EXIST_' + key.slice('EXIST_DEFAULT_'.length);
      errors.push(`.env.exist.shared:${lineno}: key '${key}' uses the legacy DEFAULT prefix — rename to '${newKey}'`);
    } else if (key.startsWith('EXIST_ENABLE_')) {
      const newKey = 'EXIST_IS_' + key.slice('EXIST_ENABLE_'.length);
      errors.push(`.env.exist.shared:${lineno}: key '${key}' uses the legacy ENABLE prefix — rename to '${newKey}'`);
    }
  }
  return errors;
}

// The generated master compose must use only host bind mounts. Service templates
// declare volumes directly as bind paths in one of three tiers — nfs-declared user data
// (a bare name declared in x-exist-volumes, materialised under volumes/) — so there's no
// top-level `volumes:` section and `docker volume ls` stays empty. This is the opposite
// of that guarantee — it trips if a Docker-managed (named) volume survives into the
// generated compose.
function checkBindMounts(): string[] {
  const errors: string[] = [];
  if (!fs.existsSync(MASTER_COMPOSE)) return errors;

  let data: Record<string, unknown>;
  try {
    data = (yaml.load(fs.readFileSync(MASTER_COMPOSE, 'utf8')) ?? {}) as Record<string, unknown>;
  } catch (e) {
    return [`docker-compose.yml: failed to parse — ${e}`];
  }

  const topVolumes = Object.keys((data['volumes'] ?? {}) as Record<string, unknown>);
  if (topVolumes.length) {
    errors.push(
      `docker-compose.yml: top-level \`volumes:\` must be empty — every volume is a host ` +
      `bind mount (found: ${topVolumes.join(', ')})`,
    );
  }

  const services = (data['services'] ?? {}) as Record<string, Record<string, unknown>>;
  for (const [svcName, svc] of Object.entries(services)) {
    const list = (svc ?? {})['volumes'];
    if (!Array.isArray(list)) continue;
    for (const entry of list) {
      if (typeof entry !== 'string') continue;
      const src = entry.split(':')[0];
      // A host bind source starts with /, ./ (or ../) or ${…}. A bare name with no
      // separator is a Docker-managed named volume — forbidden.
      const isBareNamed = src.length > 0 && !src.startsWith('/') &&
        !src.startsWith('.') && !src.startsWith('$') && !src.includes('/');
      if (isBareNamed) {
        errors.push(
          `docker-compose.yml: service '${svcName}' mounts named volume '${src}' — must be a ` +
          `host bind mount (/…, ./… or \${…})`,
        );
      }
    }
  }
  return errors;
}

// A container must run as the host user via the ${EXIST_PUID:-1000} convention, never a
// hardcoded numeric uid/gid — that only works on a 1000:1000 host. Flag literal `user:`
// values and literal uid/gid *env* values (PUID/PGID/UID/GID and prefixed forms like
// HERMES_UID, LOWCODER_PUID). The resolved ${EXIST_…} form starts with `$`, so it never
// matches the numeric patterns below.
const USER_LITERAL_RE   = /^\s*user:\s*["']?\d+:\d+["']?\s*(?:#.*)?$/;
const UID_ENV_KEY_RE     = /^\s*([A-Za-z_][A-Za-z0-9_]*):\s*["']?(\d+)["']?\s*(?:#.*)?$/;
const UID_ENV_NAME_RE    = /(?:PUID|PGID|UID|GID)$/;

/**
 * Volume declarations. Every volume a service mounts by bare name must have an
 * `x-exist-volumes` entry in that service's own template, and the entry's
 * properties must agree with the name's suffix.
 *
 * The suffix is the part a human reads before deciding whether something is safe
 * to delete, so it is enforced rather than merely conventional:
 *
 *   _data    precious — user data or a live database; never auto-deleted
 *   _backup  decree-backup archives of a _data volume
 *   _cache   regenerable; refetched or rebuilt on next start (reset deletes these)
 *
 * Also rejects the NFS/embedded-DB footgun: an mmap/flock database (SQLite WAL,
 * bbolt, a TSDB, a postgres data dir) is corrupted by NFS, so `db: true` and
 * `nfs: true` can never appear together.
 */
function checkVolumeSpecs(): string[] {
  const errors: string[] = [];
  const SUFFIXES = ['_data', '_backup', '_cache'];

  for (const cat of CATEGORY_DIRS) {
    const catDir = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catDir)) continue;
    for (const slug of fs.readdirSync(catDir)) {
      const file = path.join(catDir, slug, 'docker-compose.exist.yml');
      if (!fs.existsSync(file)) continue;
      const rel = `${cat}/${slug}/docker-compose.exist.yml`;

      let data: Record<string, unknown>;
      try {
        data = (yaml.load(fs.readFileSync(file, 'utf8')) ?? {}) as Record<string, unknown>;
      } catch {
        continue; // parse errors are reported by other checks
      }

      const spec = (data['x-exist-volumes'] ?? {}) as Record<string, Record<string, unknown> | null>;
      const declared = new Set(Object.keys(spec));
      const mounted = new Set<string>();

      for (const svc of Object.values((data['services'] ?? {}) as Record<string, Record<string, unknown>>)) {
        for (const entry of ((svc ?? {})['volumes'] ?? []) as unknown[]) {
          if (typeof entry !== 'string') continue;
          const src = entry.replace(/^['"]|['"]$/g, '').split(':')[0];
          // A bare name may carry a subpath into the volume (`name/.venv`) — the
          // volume being declared is the first segment.
          const isBareNamed = src.length > 0 && !src.startsWith('/') &&
            !src.startsWith('.') && !src.startsWith('$');
          if (isBareNamed) mounted.add(src.split('/')[0]);
        }
      }

      for (const name of mounted) {
        if (!declared.has(name)) {
          errors.push(
            `${rel}: mounts '${name}' but does not declare it — add it to the ` +
            `x-exist-volumes block (see .claude/reference/volumes.md)`,
          );
        }
      }
      for (const name of declared) {
        if (!mounted.has(name)) {
          errors.push(`${rel}: declares volume '${name}' but no service mounts it`);
        }
        if (!SUFFIXES.some(sfx => name.endsWith(sfx))) {
          errors.push(
            `${rel}: volume '${name}' must end in ${SUFFIXES.join(', ')} — the suffix is ` +
            `what says whether it is safe to delete`,
          );
        }
        const props = (spec[name] ?? {}) as Record<string, unknown>;
        if (props['db'] === true && props['nfs'] === true) {
          errors.push(
            `${rel}: volume '${name}' is both db and nfs — an embedded database on NFS ` +
            `corrupts (mmap/flock). Drop 'nfs: true'.`,
          );
        }
        if (name.endsWith('_cache') && props['backup'] === true) {
          errors.push(`${rel}: volume '${name}' is a _cache but declares backup: true`);
        }
      }
    }
  }
  return errors;
}

// Every service comes back on its own once the engine starts, which is how the
// stack starts with the machine (see site/docs/getting-started.md).
function checkRestartPolicy(): string[] {
  const errors: string[] = [];
  for (const cat of CATEGORY_DIRS) {
    const catDir = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catDir)) continue;
    for (const slug of fs.readdirSync(catDir)) {
      const file = path.join(catDir, slug, 'docker-compose.exist.yml');
      if (!fs.existsSync(file)) continue;
      let data: Record<string, unknown>;
      try {
        data = (yaml.load(fs.readFileSync(file, 'utf8')) ?? {}) as Record<string, unknown>;
      } catch {
        continue; // parse errors are reported by other checks
      }
      for (const [name, svc] of Object.entries((data['services'] ?? {}) as Record<string, Record<string, unknown>>)) {
        if ((svc ?? {})['restart'] !== 'unless-stopped') {
          errors.push(`${cat}/${slug}/docker-compose.exist.yml: service '${name}' needs \`restart: unless-stopped\``);
        }
      }
    }
  }
  return errors;
}

function checkHardcodedUids(): string[] {
  const errors: string[] = [];
  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;

    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const composePath = path.join(catPath, entry.name, 'docker-compose.exist.yml');
      if (!fs.existsSync(composePath)) continue;

      const rel = path.relative(REPO_ROOT, composePath);
      const lines = fs.readFileSync(composePath, 'utf8').split('\n');
      for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        if (raw.trimStart().startsWith('#')) continue;
        if (USER_LITERAL_RE.test(raw)) {
          errors.push(
            `${rel}:${i + 1}: hardcoded \`user:\` uid/gid — use ` +
            `\`user: "\${EXIST_PUID:-1000}:\${EXIST_PGID:-1000}"\` so it runs as the host user`,
          );
          continue;
        }
        const km = UID_ENV_KEY_RE.exec(raw);
        if (km && UID_ENV_NAME_RE.test(km[1])) {
          const isGid = /GID$/.test(km[1]);
          const repl = isGid ? '${EXIST_PGID:-1000}' : '${EXIST_PUID:-1000}';
          errors.push(
            `${rel}:${i + 1}: env '${km[1]}' is a hardcoded uid/gid — use "${repl}"`,
          );
        }
      }
    }
  }
  return errors;
}

// ── Main ──────────────────────────────────────────────────────────────────────

function main(): number {
  const services  = parseServiceComposes();
  const caddy     = parseCaddy();
  const dashyItems = parseDashy();

  const errors: string[] = [];
  const warnings: string[] = [];

  // (1) container_name format — lowercase-hyphenated only
  const badNameRe = /[A-Z_]/;
  for (const [slug, decl] of services) {
    if (badNameRe.test(slug)) {
      errors.push(
        `${path.relative(REPO_ROOT, decl.file)}:${decl.line}: ` +
        `container_name '${slug}' is not lowercase-hyphenated`,
      );
    }
  }

  // (2) container_name prefixed with folder slug
  for (const [slug, decl] of services) {
    if (!decl.folderSlug) continue;
    if (slug === decl.folderSlug) continue;
    if (!slug.startsWith(`${decl.folderSlug}-`)) {
      errors.push(
        `${path.relative(REPO_ROOT, decl.file)}:${decl.line}: ` +
        `container_name '${slug}' must start with '${decl.folderSlug}-' ` +
        `(or equal '${decl.folderSlug}') so it's obvious which service it belongs to`,
      );
    }
  }

  // (3) piHole carries the single wildcard record + EXIST_DOMAIN is defined.
  // Caddy is the source of truth for which slugs exist (checks 5/6/11); piHole
  // resolves the whole domain in one line, so there is nothing per-slug to mirror.
  errors.push(...checkPiholeWildcard());

  const caddySlugSet = new Set(caddy.keys());

  // (5) Caddy backend matches an actual container
  const containerPorts = new Map<string, Set<number>>();
  for (const [slug, decl] of services) {
    containerPorts.set(slug, new Set(decl.ports));
  }

  for (const [slug, block] of caddy) {
    const decl = services.get(block.backendContainer);
    if (!decl) {
      errors.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile:${block.line}: ` +
        `'${slug}.<domain>' proxies to '${block.backendContainer}' — ` +
        `no service compose declares that container_name`,
      );
      continue;
    }
    if (block.backendPort.startsWith('{')) continue;
    const portInt = parseInt(block.backendPort, 10);
    if (isNaN(portInt)) continue;
    const ports = containerPorts.get(block.backendContainer) ?? new Set();
    if (ports.size > 0 && !ports.has(portInt)) {
      warnings.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile:${block.line}: ` +
        `'${slug}.<domain>' → ${block.backendContainer}:${portInt}, but ` +
        `the compose file only publishes [${[...ports].sort().join(', ')}] ` +
        `(${path.relative(REPO_ROOT, decl.file)}:${decl.line}). ` +
        `OK if the container exposes more than it publishes.`,
      );
    }
  }

  // (11) When a container already has an exact-match slug (slug === containerName),
  // any OTHER Caddy slug routing to that same container must start with
  // `{containerName}-`. This prevents a short alias like `hermes.internal`
  // → `hermes-agent` from implying a "hermes" container that doesn't exist,
  // while still allowing `immich.internal` → `immich-server` (no exact-match
  // `immich-server.internal` exists, so the rule doesn't apply).
  const exactMatchContainers = new Set<string>();
  for (const [slug, block] of caddy) {
    if (slug === block.backendContainer) exactMatchContainers.add(slug);
  }
  for (const [slug, block] of caddy) {
    const c = block.backendContainer;
    if (slug === c) continue;
    if (exactMatchContainers.has(c) && !slug.startsWith(c + '-')) {
      errors.push(
        `hosting/caddy/Caddyfile.exist.Caddyfile:${block.line}: ` +
        `'${slug}.<domain>' proxies to '${c}', but '${c}.<domain>' already exists — ` +
        `aliases for the same container must start with '${c}-' ` +
        `(e.g. '${c}-dashboard.<domain>')`,
      );
    }
  }

  // (6) Dashy items point at slugs Caddy actually fronts (Caddy = source of truth)
  for (const item of dashyItems) {
    if (!caddySlugSet.has(item.slug)) {
      errors.push(
        `services/dashy/dashy-conf.exist.yml:${item.line}: ` +
        `item references '${item.slug}.<domain>' but no Caddy reverse_proxy block exists`,
      );
    }
  }

  // (7) Service env var keys start with <SLUG>_
  errors.push(...checkServiceEnvPrefixes());

  // (8) .env.exist.shared keys start with EXIST_, no legacy prefixes
  errors.push(...checkTopLevelEnvKeys());

  // (9) Master compose uses only host bind mounts — no Docker-managed volumes
  errors.push(...checkBindMounts());

  errors.push(...checkVolumeSpecs());

  // No hardcoded uid/gid — containers run as the host user via ${EXIST_PUID:-1000}
  errors.push(...checkHardcodedUids());
  errors.push(...checkRestartPolicy());


  // Quest files: markdown with YAML frontmatter, then the guide as the body.
  // Scope every check to the frontmatter — the body is free-form prose, and a
  // guide that happens to show an `e2e: false` line in an example is not config.
  const questsDir = path.join(REPO_ROOT, 'src/quests');
  const questFm = new Map<string, string>();   // filename -> frontmatter body
  if (fs.existsSync(questsDir)) {
    for (const f of fs.readdirSync(questsDir).filter(n => n.endsWith('.md'))) {
      const content = fs.readFileSync(path.join(questsDir, f), 'utf8');
      const fm = content.match(/^---\n([\s\S]*?)\n---/);
      if (!fm) {
        errors.push(`src/quests/${f}: no YAML frontmatter — a quest is fenced metadata, then the guide`);
        continue;
      }
      questFm.set(f, fm[1]);
      const lines = fm[1].split('\n');
      // Core's numbered slices are what e2e must cover, so only they owe an excuse.
      if (/^\d/.test(f)) {
        const hasE2eFalse = lines.some(l => /^e2e:\s*false/.test(l));
        const hasE2eSkip  = lines.some(l => /^e2e_skip:\s*\S/.test(l));
        if (hasE2eFalse && !hasE2eSkip) {
          errors.push(
            `src/quests/${f}: has 'e2e: false' but no 'e2e_skip:' explanation — add one`,
          );
        }
      }
      if (!lines.some(l => /^name:\s*\S/.test(l))) {
        errors.push(`src/quests/${f}: frontmatter has no 'name:' — the picker needs it`);
      }
    }
  }

  // The numbered quests ARE Core, cut into slices you can do one at a time. That
  // only holds if they partition it exactly: every Core service and every file
  // Core copies belongs to one slice and no two. Break the partition and quest.sh
  // silently stops crossing a slice off after a Core run — a wrong ✓, or a missing
  // one, with nothing to point at. So it is checked rather than remembered.
  //
  // Walked line by line for the same reason the tour count below is: `copies:`
  // entries carry `requires:` keys naming the same EXIST_IS_ flags, so a block
  // regex over the whole frontmatter would count them twice.
  const fmList = (body: string, key: string, item: RegExp): string[] => {
    const lines = body.split('\n');
    const start = lines.findIndex(l => new RegExp(`^${key}:\\s*$`).test(l));
    if (start === -1) return [];
    const out: string[] = [];
    for (const line of lines.slice(start + 1)) {
      if (/^\S/.test(line)) break;                       // next top-level key
      const m = line.match(item);
      if (m) out.push(m[1]);
    }
    return out;
  };
  // Core's `copies:` are src/dst pairs; the file that ends up on disk is what a
  // slice names in `done.files`, so compare destinations.
  const copyDests = (body: string): string[] => {
    const out: string[] = [];
    let dst = '';
    const lines = body.split('\n');
    const start = lines.findIndex(l => /^copies:\s*$/.test(l));
    if (start === -1) return out;
    let src = '';
    for (const line of lines.slice(start + 1)) {
      if (/^\S/.test(line)) break;
      const s = line.match(/^\s*-\s*src:\s*(\S+)/);
      if (s) { src = s[1]; continue; }
      const d = line.match(/^\s*dst:\s*(\S+)/);
      if (d) { dst = d[1]; if (src) out.push(dst.replace(/\/$/, '') + '/' + path.basename(src)); }
    }
    return out;
  };

  const coreFm = questFm.get('00-core.md');
  const slices = [...questFm.keys()].filter(f => /^\d/.test(f) && f !== '00-core.md').sort();
  if (coreFm && slices.length) {
    const owner = new Map<string, string>();
    const claim = (what: string, kind: string, f: string) => {
      const prev = owner.get(what);
      if (prev) {
        errors.push(`src/quests: ${kind} ${what} is claimed by both ${prev} and ${f} — a slice owns it alone`);
      } else owner.set(what, f);
    };
    for (const f of slices) {
      const body = questFm.get(f)!;
      for (const v of fmList(body, 'services', /^\s*-\s*var:\s*(EXIST_IS_\S+)/)) claim(v, 'service', f);
      for (const p of fmList(body, 'done', /^\s*-\s*(\S+)/))                     claim(p, 'file', f);
    }
    for (const v of fmList(coreFm, 'services', /^\s*-\s*var:\s*(EXIST_IS_\S+)/)) {
      if (!owner.has(v)) {
        errors.push(`src/quests/00-core.md: ${v} is in Core but in no numbered slice — add it to the one that owns it`);
      }
    }
    for (const d of copyDests(coreFm)) {
      if (!owner.has(d)) {
        errors.push(`src/quests/00-core.md: copies ${d}, which no numbered slice names in done.files — a Core run would not cross that slice off`);
      }
    }
    // The other direction: a slice must not promise a service Core does not install.
    const coreVars = new Set(fmList(coreFm, 'services', /^\s*-\s*var:\s*(EXIST_IS_\S+)/));
    for (const f of slices) {
      for (const v of fmList(questFm.get(f)!, 'services', /^\s*-\s*var:\s*(EXIST_IS_\S+)/)) {
        if (!coreVars.has(v)) {
          errors.push(`src/quests/${f}: enables ${v}, which is not part of Core — numbered quests are Core's slices, everything else is an unnumbered quest`);
        }
      }
    }
  }

  // (13) Every service folder has a docs page, and every docs link lands on one.
  // A page owns a folder by naming it in its frontmatter (`service: ai/ollama`);
  // the filename can't be the key because storage/ is nas/, open-web-ui is
  // open-webui, and the automation folder's page is decree/decree.md. README.md
  // links the site by absolute URL, which the site build never checks, so its
  // links are resolved here; links inside site/docs/ are the build's job.
  const docsDir = path.join(REPO_ROOT, 'site/docs');
  const pageService = new Map<string, string>();   // docs path (no .md) -> service folder
  if (fs.existsSync(docsDir)) {
    const walk = (dir: string): string[] => fs.readdirSync(dir, {withFileTypes: true}).flatMap(e =>
      e.isDirectory() ? walk(path.join(dir, e.name)) : e.name.endsWith('.md') ? [path.join(dir, e.name)] : []);
    for (const f of walk(docsDir)) {
      const rel = path.relative(docsDir, f).replace(/\.md$/, '');
      if (rel.startsWith('graveyard/')) continue;
      const fm = fs.readFileSync(f, 'utf8').match(/^---\n([\s\S]*?)\n---/);
      const svc = fm?.[1].match(/^service:\s*(\S+)\s*$/m)?.[1];
      if (!svc) continue;
      if (!CATEGORY_DIRS.includes(svc.split("/")[0]) || !fs.existsSync(path.join(REPO_ROOT, svc))) {
        errors.push(`site/docs/${rel}.md: documents service ${svc}, which has no folder — move the page to graveyard/ or fix the path`);
      } else if ([...pageService.values()].includes(svc)) {
        errors.push(`site/docs/${rel}.md: documents ${svc}, which another page already claims — one page per service`);
      }
      pageService.set(rel, svc);
    }
    const documented = new Set(pageService.values());
    for (const cat of CATEGORY_DIRS) {
      const catDir = path.join(REPO_ROOT, cat);
      if (!fs.existsSync(catDir)) continue;
      for (const e of fs.readdirSync(catDir, {withFileTypes: true})) {
        if (e.isDirectory() && !documented.has(`${cat}/${e.name}`)) {
          errors.push(`${cat}/${e.name}: no docs page — add one under site/docs/ with \`service: ${cat}/${e.name}\` in its frontmatter`);
        }
      }
    }
  }
  const docExists = (p: string): boolean => {
    p = p.replace(/[#?].*$/, '').replace(/\/$/, '');
    return [`${p}.md`, `${p}/index.md`, `${p}/${path.basename(p)}.md`]
      .some(c => fs.existsSync(path.join(docsDir, c)));
  };
  const readmePath = path.join(REPO_ROOT, 'README.md');
  const readme = fs.existsSync(readmePath) ? fs.readFileSync(readmePath, 'utf8') : '';
  for (const m of readme.matchAll(/https:\/\/existential\.company\/docs\/([^)\s]*)/g)) {
    if (!docExists(m[1])) errors.push(`README.md: links docs/${m[1]}, which is no page in site/docs/`);
  }

  // (14) README.md and the intro page each list what Core installs, under a
  // `## What Core installs` heading, as links to service pages. The services
  // those pages document must be exactly Core's `services:` block.
  if (coreFm) {
    const coreSet = new Set(fmList(coreFm, 'services', /^\s*-\s*var:\s*(EXIST_IS_\S+)/));
    const varFor = (svc: string) => 'EXIST_IS_' + svc.replace('/', '_').toUpperCase().replace(/-/g, '_');
    for (const [file, linkRe] of [
      ['README.md', /\]\(https:\/\/existential\.company\/docs\/([^)#\s]+)/g],
      ['site/docs/intro.md', /\]\(\.\/([^)#\s]+)/g],
    ] as const) {
      const full = path.join(REPO_ROOT, file);
      if (!fs.existsSync(full)) continue;
      const section = fs.readFileSync(full, 'utf8').match(/^## What Core installs\n([\s\S]*?)(?=^## |(?![\s\S]))/m);
      if (!section) {
        errors.push(`${file}: no "## What Core installs" section to check against src/quests/00-core.md`);
        continue;
      }
      const listed = new Set<string>();
      for (const m of section[1].matchAll(linkRe)) {
        const p = m[1].replace(/\.md$/, '').replace(/\/$/, '');
        const svc = pageService.get(p) ?? pageService.get(`${p}/index`) ?? pageService.get(`${p}/${path.basename(p)}`);
        if (svc) listed.add(varFor(svc));
      }
      for (const v of coreSet) if (!listed.has(v)) errors.push(`${file}: "What Core installs" leaves out ${v}, which Core enables`);
      for (const v of listed) if (!coreSet.has(v)) errors.push(`${file}: "What Core installs" lists ${v}, which Core does not enable`);
    }
  }

  // ── Report ──────────────────────────────────────────────────────────────────
  console.log(`Services declared:    ${services.size}`);
  console.log(`Caddy blocks:         ${caddy.size}`);
  console.log(`Dashy items:          ${dashyItems.length}`);
  console.log();

  if (warnings.length) {
    console.log(`Warnings (${warnings.length}):`);
    for (const w of warnings) console.log(`  - ${w}`);
    console.log();
  }

  if (errors.length) {
    console.log(`Errors (${errors.length}):`);
    for (const e of errors) console.log(`  ✗ ${e}`);
    console.log();
    console.log('Validation FAILED. Fix the above to keep conventions in sync.');
    return 1;
  }

  console.log('Validation passed.');
  return 0;
}

process.exit(main());
