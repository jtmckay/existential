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
 * 10. Every `<cat>/<slug>/decree/config.exist.yml` has the required top-level `commands:`
 *      block (decree requires it — no serde default — and missing it crashes all sidecars).
 * 11. Every Caddy slug must equal the backendContainer name, or start with
 *      `{backendContainer}-`. A slug shorter/different than the container it proxies
 *      (e.g. `hermes.internal` → `hermes-agent`) is a convention violation — it implies
 *      a container that doesn't exist. When a container needs two URLs (two ports), the
 *      primary slug is the container name and any alias starts with `{container}-`.
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
const PORT_LINE_RE       = /^\s*-\s*"?(?:\$\{[^}]+\}|\d+):(\d+)(?:\/(?:tcp|udp))?"?\s*(?:#.*)?$/;
// Caddy hostnames use Caddy's env form `<slug>.{$CADDY_DOMAIN}` (resolved at runtime
// from the container env, NOT rendered). The validator reads the file, so it matches
// the literal token. (Dashy uses the bare EXIST_DOMAIN form — see DASHY_URL_RE.)
const CADDY_HEADER_RE    = /^([\w-]+)\.\{\$CADDY_DOMAIN\}\s*\{/;
const CADDY_PROXY_RE     = /^\s*reverse_proxy\s+(?:https?:\/\/)?([\w-]+):(\d+|\{[^}]+\})/;
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
// declare volumes directly as bind paths in one of three tiers — tier-1 NFS user data
// (${EXIST_NFS_HOST_MOUNT:-./volumes}/<name>), tier-2 local databases
// (../../volumes_local/<name>), or tier-3 service-dir scratch (./<dir>) — so there's no
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

// ── Decree config check ────────────────────────────────────────────────────────
// Every <cat>/<slug>/decree/config.exist.yml is a decree daemon config.
// decree 0.4.2 requires a top-level `commands:` block — it is the only field in
// AppConfig without a serde default, so a missing block fails all sidecars on startup.

function checkDecreeConfigs(): string[] {
  const errors: string[] = [];
  for (const cat of CATEGORY_DIRS) {
    const catPath = path.join(REPO_ROOT, cat);
    if (!fs.existsSync(catPath)) continue;
    for (const entry of fs.readdirSync(catPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const configPath = path.join(catPath, entry.name, 'decree', 'config.exist.yml');
      if (!fs.existsSync(configPath)) continue;
      const rel = path.relative(REPO_ROOT, configPath);
      let parsed: unknown;
      try {
        parsed = yaml.load(fs.readFileSync(configPath, 'utf8'));
      } catch (e) {
        errors.push(`${rel}: failed to parse YAML — ${e}`);
        continue;
      }
      if (!parsed || typeof parsed !== 'object') {
        errors.push(`${rel}: empty or invalid config`);
        continue;
      }
      const cfg = parsed as Record<string, unknown>;
      const cmds = cfg['commands'];
      if (!cmds || typeof cmds !== 'object') {
        errors.push(
          `${rel}: missing required 'commands:' block — ` +
          `decree requires it (add 'commands:\\n  ai_router: opencode run {prompt}\\n  ai_interactive: opencode')`,
        );
        continue;
      }
      const c = cmds as Record<string, unknown>;
      if (typeof c['ai_router'] !== 'string' || !c['ai_router']) {
        errors.push(`${rel}: 'commands.ai_router' must be a non-empty string`);
      }
      if (typeof c['ai_interactive'] !== 'string' || !c['ai_interactive']) {
        errors.push(`${rel}: 'commands.ai_interactive' must be a non-empty string`);
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

  // No hardcoded uid/gid — containers run as the host user via ${EXIST_PUID:-1000}
  errors.push(...checkHardcodedUids());

  // (10) Every decree/config.exist.yml has the required `commands:` block
  errors.push(...checkDecreeConfigs());

  // Quest files: e2e: false must have e2e_skip explaining why
  const questsDir = path.join(REPO_ROOT, 'src/quests');
  if (fs.existsSync(questsDir)) {
    for (const f of fs.readdirSync(questsDir).filter(n => /^\d.*\.yml$/.test(n))) {
      const content = fs.readFileSync(path.join(questsDir, f), 'utf8');
      const lines = content.split('\n');
      const hasE2eFalse = lines.some(l => /^e2e:\s*false/.test(l));
      const hasE2eSkip  = lines.some(l => /^e2e_skip:\s*\S/.test(l));
      if (hasE2eFalse && !hasE2eSkip) {
        errors.push(
          `src/quests/${f}: has 'e2e: false' but no 'e2e_skip:' explanation — add one`,
        );
      }
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
