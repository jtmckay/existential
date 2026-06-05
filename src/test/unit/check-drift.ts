#!/usr/bin/env tsx
/**
 * check-drift.ts — compare every *.exist.* template to its rendered counterpart and
 * report what re-rendering would change, ignoring placeholder substitution.
 *
 * Lines in the template containing any EXIST_* placeholder are skipped from
 * the comparison entirely — their rendered counterparts would be whatever the
 * user entered or whatever was generated, so comparing them is just noise.
 *
 * Each remaining diff line is classified:
 *   + line present in template, missing or different in rendered  (upstream new)
 *   - line present in rendered, missing from template             (local custom)
 *   ~ value differs at the same line position                      (manual edit)
 */

import * as fs from 'fs';
import * as path from 'path';

// In the adhoc container /src and /repo are separate mounts, so __dirname-relative
// resolution lands on "/" (and findTemplates would then walk the whole container
// filesystem). Take the repo root explicitly — argv[2] or $REPO_DIR, same as the
// other validators — and fall back to __dirname-relative for host runs.
const REPO_ROOT = path.resolve(
  process.argv[2] ?? process.env.REPO_DIR ?? path.join(__dirname, '..', '..', '..'),
);
// Dirs that never hold templates — including runtime/data dirs that can be large
// or root-owned (secrets/, runs/, volumes/). The walk also tolerates EACCES as a
// backstop, but skipping these up front is faster and clearer.
const SKIP_DIRS = new Set([
  'graveyard', 'node_modules', '.git', 'site', 'secrets', 'runs', 'volumes',
]);
const PLACEHOLDER_RE = /EXIST_[A-Z0-9_]+/;
const ENV_KEY_RE = /^([A-Z_][A-Z0-9_]*)=/;
const YAML_KEY_RE = /^\s*([\w.-]+):\s*\S/;

// ── Diff (LCS-based sequence matcher) ─────────────────────────────────────────

type Tag = 'equal' | 'replace' | 'insert' | 'delete';
type Opcode = [Tag, number, number, number, number];

function diffOpcodes(a: string[], b: string[]): Opcode[] {
  const m = a.length;
  const n = b.length;

  // Build LCS DP table
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1] + 1
        : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  // Backtrack to get matching index pairs
  const matches: Array<[number, number]> = [];
  let i = m, j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] === b[j - 1]) {
      matches.unshift([i - 1, j - 1]);
      i--; j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }

  // Convert matches to opcodes
  const opcodes: Opcode[] = [];
  let ai = 0, bi = 0;

  for (const [ma, mb] of matches) {
    if (ai < ma || bi < mb) {
      if (ai < ma && bi < mb) opcodes.push(['replace', ai, ma, bi, mb]);
      else if (ai < ma)       opcodes.push(['delete',  ai, ma, bi, bi]);
      else                    opcodes.push(['insert',  ai, ai, bi, mb]);
    }
    // Extend last equal block if contiguous, else start a new one
    const last = opcodes[opcodes.length - 1];
    if (last?.[0] === 'equal' && last[2] === ma && last[4] === mb) {
      last[2] = ma + 1;
      last[4] = mb + 1;
    } else {
      opcodes.push(['equal', ma, ma + 1, mb, mb + 1]);
    }
    ai = ma + 1;
    bi = mb + 1;
  }

  if (ai < m || bi < n) {
    if (ai < m && bi < n) opcodes.push(['replace', ai, m, bi, n]);
    else if (ai < m)      opcodes.push(['delete',  ai, m, bi, bi]);
    else                  opcodes.push(['insert',  ai, ai, bi, n]);
  }

  return opcodes;
}

// ── Placeholder stripping ──────────────────────────────────────────────────────

function lineKey(raw: string): string | null {
  const em = ENV_KEY_RE.exec(raw);
  if (em) return em[1];
  const ym = YAML_KEY_RE.exec(raw);
  if (ym) return ym[1];
  return null;
}

function stripPlaceholderLines(
  exampleLines: string[],
  renderedLines: string[],
): [string[], number[], string[], number[]] {
  const skipKeys = new Set<string>();
  const exKept: string[] = [], exOrig: number[] = [];

  for (let i = 0; i < exampleLines.length; i++) {
    const ln = exampleLines[i];
    if (PLACEHOLDER_RE.test(ln)) {
      const k = lineKey(ln);
      if (k) skipKeys.add(k);
      continue;
    }
    exKept.push(ln);
    exOrig.push(i + 1);
  }

  const rnKept: string[] = [], rnOrig: number[] = [];
  for (let j = 0; j < renderedLines.length; j++) {
    const ln = renderedLines[j];
    const k = lineKey(ln);
    if (k && skipKeys.has(k)) continue;
    rnKept.push(ln);
    rnOrig.push(j + 1);
  }

  return [exKept, exOrig, rnKept, rnOrig];
}

// ── Template → destination path ───────────────────────────────────────────────

function templateToDst(tmpl: string): string {
  const fname = path.basename(tmpl);
  const dir = path.dirname(tmpl);

  if (fname.includes('.exist.')) {
    const [before, , after] = fname.split(/\.exist\.(.*)/s);
    // Palindrome (e.g. Caddyfile.exist.Caddyfile → Caddyfile)
    if (before.toLowerCase() === after.toLowerCase()) return path.join(dir, before);
    return path.join(dir, `${before}.${after}`);
  }
  // Ends with .env.exist → strip .exist suffix
  return path.join(dir, fname.slice(0, -6));
}

// ── Drift computation ──────────────────────────────────────────────────────────

interface DriftReport {
  file: string;
  renderedMissing: boolean;
  upstreamLines: Array<[number, string]>;
  localLines: Array<[number, string]>;
  changed: Array<[number, string, string]>;
}

function hasDrift(r: DriftReport): boolean {
  if (r.renderedMissing) return false;
  return r.upstreamLines.length > 0 || r.localLines.length > 0 || r.changed.length > 0;
}

function computeDrift(examplePath: string, renderedPath: string): DriftReport {
  const report: DriftReport = {
    file: examplePath,
    renderedMissing: false,
    upstreamLines: [],
    localLines: [],
    changed: [],
  };

  if (!fs.existsSync(renderedPath)) {
    report.renderedMissing = true;
    return report;
  }

  const exampleLines = fs.readFileSync(examplePath, 'utf8').split('\n');
  const renderedLines = fs.readFileSync(renderedPath, 'utf8').split('\n');

  const [exKept, exOrig, rnKept, rnOrig] = stripPlaceholderLines(exampleLines, renderedLines);
  const opcodes = diffOpcodes(exKept, rnKept);

  for (const [tag, i1, i2, j1, j2] of opcodes) {
    if (tag === 'equal') continue;

    if (tag === 'replace') {
      const len = Math.max(i2 - i1, j2 - j1);
      for (let offset = 0; offset < len; offset++) {
        const hasEx = i1 + offset < i2;
        const hasRn = j1 + offset < j2;
        if (hasEx && hasRn) {
          report.changed.push([exOrig[i1 + offset], exKept[i1 + offset], rnKept[j1 + offset]]);
        } else if (hasEx) {
          report.upstreamLines.push([exOrig[i1 + offset], exKept[i1 + offset]]);
        } else {
          report.localLines.push([rnOrig[j1 + offset], rnKept[j1 + offset]]);
        }
      }
    } else if (tag === 'delete') {
      for (let idx = i1; idx < i2; idx++) {
        report.upstreamLines.push([exOrig[idx], exKept[idx]]);
      }
    } else if (tag === 'insert') {
      for (let idx = j1; idx < j2; idx++) {
        report.localLines.push([rnOrig[idx], rnKept[idx]]);
      }
    }
  }

  return report;
}

// ── Template discovery ────────────────────────────────────────────────────────

function findTemplates(root: string): string[] {
  const results: string[] = [];

  function walk(dir: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (err) {
      // Runtime state dirs can be root-owned/unreadable by the adhoc user (uid
      // 1000) — e.g. automations/secrets/gmail (0700). They never hold templates,
      // so skip rather than crash. Surface anything unexpected.
      if ((err as NodeJS.ErrnoException).code === 'EACCES') return;
      throw err;
    }
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        if (entry.name.includes('.exist.') || entry.name.endsWith('.env.exist')) {
          results.push(full);
        }
      }
    }
  }

  walk(root);
  return results.sort();
}

// ── Main ──────────────────────────────────────────────────────────────────────

function main(): number {
  const templates = findTemplates(REPO_ROOT);
  let driftCount = 0;
  let missingCount = 0;

  for (const tmpl of templates) {
    const rendered = templateToDst(tmpl);
    const report = computeDrift(tmpl, rendered);

    if (report.renderedMissing) { missingCount++; continue; }
    if (!hasDrift(report)) continue;

    driftCount++;
    const rel = path.relative(REPO_ROOT, tmpl);
    console.log(`\n${rel}:`);
    for (const [lineno, content] of report.upstreamLines) {
      console.log(`  + L${lineno}  ${content.slice(0, 120)}`);
    }
    for (const [lineno, content] of report.localLines) {
      console.log(`  - L${lineno}  ${content.slice(0, 120)}`);
    }
    for (const [lineno, ex, rn] of report.changed) {
      console.log(`  ~ L${lineno}`);
      console.log(`      template: ${ex.slice(0, 118)}`);
      console.log(`      rendered: ${rn.slice(0, 118)}`);
    }
  }

  console.log();
  console.log(`Examined:     ${templates.length} template files`);
  console.log(`Not rendered: ${missingCount}  (no counterpart on disk — nothing to compare)`);
  console.log(`Drifted:      ${driftCount}`);
  console.log();
  console.log('Legend:');
  console.log('  + = present in template, missing/different in rendered  (upstream is ahead)');
  console.log('  - = present in rendered, not in template                (local customization)');
  console.log('  ~ = both have a line at this position but they differ   (manual edit / stale)');
  console.log();
  console.log('Lines containing EXIST_* placeholders in templates are skipped — their');
  console.log('rendered counterparts are user-supplied or generated, so comparing them');
  console.log('would always report drift.');

  return driftCount > 0 ? 1 : 0;
}

process.exit(main());
