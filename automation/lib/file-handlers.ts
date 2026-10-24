// file-handlers — a change to a file in the workspace starts the machine of every
// handler in .decree/handlers.yml whose glob matches it, with `path` (relative to
// the workspace) and `change` (created, modified or deleted) as its params.
//
// Started by the `automation` container's entrypoint, which restarts it if it
// dies. A handler fires once its file has been quiet for `quiet` seconds (30 by
// default), so autosaves while you type make one run; a delete fires at once.
// handlers.yml is re-read whenever it changes, no restart.
//
// Skipped, whatever a handler matches: anything inside a .git/, and every path a
// .gitignore in the workspace ignores (git itself decides, as workspace_sync's
// filter does), which is what keeps decree's own run state from firing anything.
//
//   FILE_HANDLERS_WORKSPACE  the workspace to watch (default /workspace)

import { watch, statSync, readdirSync, mkdtempSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { tmpdir } from "node:os";

type Change = "created" | "modified" | "deleted";
interface Handler {
  match: RegExp;
  glob: string;
  machine: string;
  changes: Change[];
  quiet: number;
}

const root = process.env.FILE_HANDLERS_WORKSPACE || "/workspace";
const handlersFile = join(root, ".decree", "handlers.yml");
const log = (msg: string) => console.error(`[file-handlers] ${msg}`);

// A glob as a regex over a workspace-relative path: `**/` is any number of
// folders, `*` and `?` stay within one, `{a,b}` is either. Dotfiles match too:
// "anywhere in the workspace" includes .decree/.
function globToRegExp(glob: string): RegExp {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (glob.startsWith("**/", i)) { re += "(?:.*/)?"; i += 2; }
    else if (glob.startsWith("**", i)) { re += ".*"; i += 1; }
    else if (c === "*") re += "[^/]*";
    else if (c === "?") re += "[^/]";
    else if (c === "{") re += "(?:";
    else if (c === "}") re += ")";
    else if (c === ",") re += "|";
    else re += c.replace(/[.+^$()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${re}$`);
}

// handlers.yml, re-parsed only when its mtime moves. A broken file is reported
// once and means no handlers until it is fixed.
let handlersMtime = -1;
let handlers: Handler[] = [];
function currentHandlers(): Handler[] {
  let mtime = 0;
  try { mtime = statSync(handlersFile).mtimeMs; } catch { /* no file: no handlers */ }
  if (mtime === handlersMtime) return handlers;
  handlersMtime = mtime;
  handlers = [];
  if (!mtime) return handlers;
  try {
    const r = spawnSync("yq", ["-o=json", handlersFile], { encoding: "utf8" });
    if (r.status !== 0) throw new Error((r.stderr || r.error?.message || "").trim());
    const doc = JSON.parse(r.stdout);
    for (const h of (Array.isArray(doc) ? doc : []) as Record<string, unknown>[]) {
      if (typeof h?.match !== "string" || typeof h?.machine !== "string") {
        log(`handlers.yml: skipping an entry without match and machine: ${JSON.stringify(h)}`);
        continue;
      }
      handlers.push({
        match: globToRegExp(h.match),
        glob: h.match,
        machine: h.machine,
        changes: Array.isArray(h.changes) ? h.changes : ["created", "modified", "deleted"],
        quiet: typeof h.quiet === "number" ? h.quiet : 30,
      });
    }
    log(`handlers.yml: ${handlers.length} handler(s)`);
  } catch (e) {
    log(`handlers.yml does not parse, no handlers until it does: ${(e as Error).message}`);
  }
  return handlers;
}

// An empty repository outside the workspace lets git read the workspace's
// .gitignore files whether or not it is a repo.
const gitDir = join(mkdtempSync(join(tmpdir(), "file-handlers-")), "git");
spawnSync("git", ["init", "-q", "--bare", gitDir]);
function ignored(path: string): boolean {
  return spawnSync("git", ["--git-dir", gitDir, "--work-tree", root, "check-ignore", "-q", "--no-index", "--", path],
    { cwd: root }).status === 0;
}

function run(h: Handler, path: string, change: Change) {
  if (ignored(path)) return;
  const r = spawnSync("decree", ["emit", "--no-color", "--machine", h.machine, "--param", `path=${path}`, "--param", `change=${change}`],
    { cwd: root, input: `# ${path} was ${change}\n\nMatched the file handler \`${h.glob}\`.\n`, encoding: "utf8" });
  if (r.status === 0) log(`${change} ${path} -> ${h.machine} ${r.stdout.trim()}`);
  else log(`${change} ${path} -> ${h.machine} failed: ${(r.stderr || r.error?.message || "").trim()}`);
}

const inGit = (path: string) => path === ".git" || path.startsWith(".git/") || path.includes("/.git/") || path.endsWith("/.git");

// Every file that existed when we last looked, so a change can tell created from modified.
const known = new Set<string>();
// A change waiting out its quiet period: the change it started as, and one timer per handler.
const pending = new Map<string, { change: Change; timers: Map<string, NodeJS.Timeout> }>();

function walk(dir: string, each: (path: string) => void) {
  let entries;
  try { entries = readdirSync(join(root, dir), { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const path = dir ? `${dir}/${e.name}` : e.name;
    if (e.name === ".git") continue;
    if (e.isDirectory()) walk(path, each);
    else each(path);
  }
}

function changed(path: string) {
  if (inGit(path)) return;
  let stat;
  try { stat = statSync(join(root, path)); } catch { stat = null; }
  if (stat?.isDirectory()) return walk(path, changed);   // a folder moved in: each file in it
  if (!stat) {
    // Gone: this path, or every file under it if it was a folder.
    for (const p of [...known].filter((k) => k === path || k.startsWith(`${path}/`))) deleted(p);
    return;
  }
  let p = pending.get(path);
  if (!p) {
    p = { change: known.has(path) ? "modified" : "created", timers: new Map() };
    pending.set(path, p);
  }
  known.add(path);
  for (const h of currentHandlers()) {
    if (!h.match.test(path) || !h.changes.includes(p.change)) continue;
    // Keyed by what the handler is, not the object, which a reload replaces.
    const key = `${h.machine}\0${h.glob}`;
    clearTimeout(p.timers.get(key));
    const entry = p;
    entry.timers.set(key, setTimeout(() => {
      entry.timers.delete(key);
      if (!entry.timers.size) pending.delete(path);
      run(h, path, entry.change);
    }, h.quiet * 1000));
  }
  if (!p.timers.size) pending.delete(path);
}

function deleted(path: string) {
  known.delete(path);
  const p = pending.get(path);
  if (p) {
    for (const t of p.timers.values()) clearTimeout(t);
    pending.delete(path);
    if (p.change === "created") return;   // came and went inside its quiet period
  }
  for (const h of currentHandlers()) {
    if (h.match.test(path) && h.changes.includes("deleted")) run(h, path, "deleted");
  }
}

// Watch first, then look, so nothing changed in between is missed.
watch(root, { recursive: true }, (_event, name) => { if (name) changed(name.toString()); })
  .on("error", (e) => { log(`watch failed: ${e.message}`); process.exit(1); });
walk("", (path) => known.add(path));
currentHandlers();
log(`watching ${root} (${known.size} files)`);
