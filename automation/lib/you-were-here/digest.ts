#!/usr/bin/env tsx
// you_were_here's data half. Two steps, with the model call between them in bash
// (scripts/you_were_here.sh, through lib/model.sh):
//
//   digest.ts gather   reads the project (.decree/, the cwd's), the workspace and the
//                      store; writes $DECREE_RUN_DIR/facts.json and prompt.txt
//   digest.ts write    renders facts.json (+ model.json when the model answered) into
//                      notes/you-were-here.md and today's archive, saves the store, and
//                      writes $DECREE_RUN_DIR/ntfy.md only when something changed
//
// Every section but The picture, One next thing and the feed reasons is built here,
// from files, so the digest works with no model at all. Links are written relative
// to the workspace and rebased for the note they land in.
//
// "Recent" is since the last digest; when nothing new came in since then, it stays
// the window of the last digest that showed something new, so a gap never empties it.
//
// Env: DECREE_DATA_WORKSPACE (default /workspace), DECREE_STORE, DECREE_RUN_DIR;
// DIGEST_NOW (ISO) pins the clock for tests.
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { fetchFeed } from "../rss";

const WS = process.env.DECREE_DATA_WORKSPACE || "/workspace";
const PROJECT = ".decree";
const STORE = process.env.DECREE_STORE!;
const RUN = process.env.DECREE_RUN_DIR!;
const SELF = ["you_were_here", "notify"]; // its own runs, and the push it emits
const NOW = process.env.DIGEST_NOW ? new Date(process.env.DIGEST_NOW) : new Date();
const pad = (n: number) => String(n).padStart(2, "0");
const day = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const TODAY = day(NOW);
const NTFY_LIMIT = 4096; // bytes; ntfy turns a longer message into an attachment

interface State {
  last_at: string | null;      // the last digest
  window_from: string;         // where "recent" starts
  fingerprint: string;
  notes: Record<string, string>;   // note -> the day it first appeared ("" = before the first digest)
  checked: Record<string, string>; // "note\ttext" -> the day it was first seen ticked
  machines: Record<string, string>;
}

const read = (f: string) => { try { return fs.readFileSync(f, "utf8"); } catch { return ""; } };
const ls = (d: string) => { try { return fs.readdirSync(d).sort(); } catch { return []; } };
const mtime = (f: string) => fs.statSync(f).mtime.toISOString();
const oneLine = (s: string, n = 140) => { const t = s.replace(/\s+/g, " ").trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };
const writeAtomic = (f: string, s: string) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(`${f}.tmp`, s); fs.renameSync(`${f}.tmp`, f); };

function frontmatter(text: string): Record<string, string> {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  const out: Record<string, string> = {};
  for (const line of m ? m[1].split("\n") : []) {
    const kv = line.match(/^([A-Za-z_]+):\s*(.*)$/);
    if (kv) out[kv[1]] = kv[2].replace(/^["']|["']$/g, "");
  }
  return out;
}

function walk(dir: string): string[] {
  return ls(dir).flatMap((name) => {
    const p = path.join(dir, name);
    if (name.startsWith(".")) return [];
    return fs.statSync(p).isDirectory() ? walk(p) : [p];
  });
}

// ── gather ────────────────────────────────────────────────────────────────────

interface Run { id: string; machine: string; trigger: string; file: string; state: string; at: string; waiting: boolean }

function runs(): Run[] {
  return ls(path.join(PROJECT, "runs")).flatMap((id) => {
    const lines = read(path.join(PROJECT, "runs", id, "events.jsonl")).split("\n").filter(Boolean);
    const events = lines.flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
    if (events.length === 0) return [];
    const first = events[0], last = events[events.length - 1];
    const fin = [...events].reverse().find((e) => e.type === "run_finished");
    return [{
      id, machine: first.machine ?? "", trigger: first.trigger ?? "", file: first.file ?? "",
      state: fin && last === fin ? fin.state : "", at: fin && last === fin ? fin.ts : "",
      waiting: last.type === "waiting" && Boolean(last.wait_id),
    }];
  });
}

function capturesSince(from: string) {
  const dir = path.join(WS, ".capture");
  return ls(dir).filter((f) => f.endsWith(".jsonl")).flatMap((f) =>
    read(path.join(dir, f)).split("\n").filter(Boolean).flatMap((l) => {
      try {
        const c = JSON.parse(l);
        return c.ts > from ? [{ ts: c.ts as string, source: String(c.source ?? ""), context: c.context as string | null, session: c.session == null ? null : String(c.session), text: String(c.text ?? ""), file: `.capture/${f}` }] : [];
      } catch { return []; }
    })).sort((a, b) => a.ts.localeCompare(b.ts));
}

const project = (c: { context: string | null; source: string }) => (c.context ? path.basename(c.context) : c.source) || "elsewhere";
const DECISION = /\b(decided|decide to|let'?s go with|going with|we'?ll use|from now on|settled on|the plan is|always use|never use)\b/i;

// One thread per project; within it, the last prompt of each session. A line captured
// without a session id shares one bucket with the rest of its context.
function threads(caps: ReturnType<typeof capturesSince>) {
  const group = <T,>(xs: T[], key: (x: T) => string) => {
    const by = new Map<string, T[]>();
    for (const x of xs) by.set(key(x), [...(by.get(key(x)) ?? []), x]);
    return [...by.values()];
  };
  return group(caps, project)
    .map((cs) => ({
      project: project(cs[0]), count: cs.length, sources: [...new Set(cs.map((c) => c.source))].sort(), last_ts: cs[cs.length - 1].ts, file: cs[cs.length - 1].file,
      sessions: group(cs, (c) => c.session ?? `context:${c.context ?? ""}`)
        .map((ss) => ss[ss.length - 1])
        .sort((a, b) => b.ts.localeCompare(a.ts))
        .map((c) => ({ text: oneLine(c.text), file: c.file })),
    }))
    .sort((a, b) => b.last_ts.localeCompare(a.last_ts));
}

function notes() {
  const root = path.join(WS, "notes");
  return walk(root)
    .filter((f) => f.endsWith(".md"))
    .map((f) => path.relative(WS, f))
    .filter((rel) => rel !== "notes/you-were-here.md" && !rel.startsWith("notes/you-were-here/"))
    .map((rel) => {
      const text = read(path.join(WS, rel));
      const boxes = (mark: string) => [...text.matchAll(new RegExp(`^\\s*[-*] \\[${mark}\\] (.+)$`, "gm"))].map((m) => oneLine(m[1]));
      return { path: rel, mtime: mtime(path.join(WS, rel)), open: boxes(" "), checked: boxes("[xX]"), title: (text.match(/^# (.+)$/m)?.[1] ?? path.basename(rel, ".md")).trim() };
    });
}

const STOP = new Set("that this with from have what when where which would could should there their about into your just like then than them they were been will make more some only also need want does done here back over each".split(" "));
const words = (s: string) => new Set((s.toLowerCase().match(/[a-z][a-z0-9-]{3,}/g) ?? []).filter((w) => !STOP.has(w)));

async function feeds(focus: Set<string>) {
  const file = path.join(WS, "notes", "feeds.md");
  if (!fs.existsSync(file)) return null;
  const shown = new Set(read(path.join(STORE, "feeds-shown.tsv")).split("\n").map((l) => l.split("\t")[0]).filter(Boolean));
  const urls = [...new Set(read(file).match(/https?:\/\/[^\s)>\]]+/g) ?? [])];
  const items: { title: string; link: string; summary: string; score: number; published: string }[] = [];
  for (const url of urls) {
    try {
      for (const i of await fetchFeed(url)) {
        if (!i.link || shown.has(i.link) || items.some((x) => x.link === i.link)) continue;
        const score = [...words(`${i.title} ${i.summary}`)].filter((w) => focus.has(w)).length;
        items.push({ title: oneLine(i.title, 120), link: i.link, summary: oneLine(i.summary, 300), score, published: i.pubDate });
      }
    } catch (err) {
      console.error(`gather: skipping feed ${url}: ${(err as Error).message}`);
    }
  }
  items.sort((a, b) => b.score - a.score);
  const related = items.filter((i) => i.score > 0).length;
  return items.slice(0, Math.min(5, Math.max(3, related)));
}

async function gather() {
  const prev: State | null = fs.existsSync(path.join(STORE, "state.json")) ? JSON.parse(read(path.join(STORE, "state.json"))) : null;
  const lastAt = prev?.last_at ?? new Date(NOW.getTime() - 7 * 86400e3).toISOString();
  const allRuns = runs();
  const allNotes = notes();
  const decisionNotes = allNotes.filter((n) => n.path.startsWith("notes/decisions/"));

  // Recent: since the last digest, unless nothing new came in since then.
  const fresh = capturesSince(lastAt).length > 0 || allNotes.some((n) => n.mtime > lastAt);
  const from = fresh || !prev ? lastAt : prev.window_from;
  const caps = capturesSince(from);

  const attention = ls(path.join(PROJECT, "attention")).filter((f) => f.endsWith(".md")).map((f) => {
    const fm = frontmatter(read(path.join(PROJECT, "attention", f)));
    return { id: f.replace(/\.md$/, ""), machine: fm.machine ?? "", status: fm.status ?? "", state: fm.state ?? "", since: fm.since ?? "", path: `.decree/attention/${f}` };
  });
  const waitingRuns = allRuns.filter((r) => r.waiting && !attention.some((a) => a.id === r.id))
    .map((r) => ({ id: r.id, machine: r.machine, status: "waiting", state: "", since: "", path: `.decree/runs/${r.id}/message.md` }));
  const waiting = [...attention, ...waitingRuns].sort((a, b) => a.since.localeCompare(b.since));

  const lastByMachine = new Map<string, Run>();
  for (const r of allRuns) if (r.at && !SELF.includes(r.machine)) lastByMachine.set(r.machine, r);
  const steady = [...lastByMachine.values()].filter((r) => r.state === "done").sort((a, b) => a.machine.localeCompare(b.machine))
    .map((r) => ({ machine: r.machine, path: `.decree/runs/${r.id}/message.md` }));
  const schedules = ls(path.join(PROJECT, "cron")).filter((f) => f.endsWith(".md")).map((f) => {
    const fm = frontmatter(read(path.join(PROJECT, "cron", f)));
    return { name: f.replace(/\.md$/, ""), cron: fm.cron ?? "", machine: fm.machine ?? "", path: `.decree/cron/${f}` };
  });

  const touched = allNotes.filter((n) => n.mtime > from && !n.path.startsWith("notes/decisions/"));
  const focus = words([...caps.map((c) => c.text), ...touched.map((n) => `${n.title} ${n.open.join(" ")}`)].join(" "));

  // What first appeared today, against what the store saw before. The first digest
  // records what is already there without calling any of it done.
  const stamp = (old: Record<string, string> | undefined, keys: string[]) =>
    Object.fromEntries(keys.map((k) => [k, old ? (old[k] ?? TODAY) : ""]));
  const machineNames = ls(path.join(PROJECT, "machines")).filter((f) => f.endsWith(".yml")).map((f) => f.replace(/\.yml$/, ""));
  const next: Omit<State, "fingerprint"> = {
    last_at: NOW.toISOString(),
    window_from: from,
    notes: stamp(prev?.notes, allNotes.map((n) => n.path)),
    checked: stamp(prev?.checked, allNotes.flatMap((n) => n.checked.map((t) => `${n.path}\t${t}`))),
    machines: stamp(prev?.machines, machineNames),
  };
  const today = (m: Record<string, string>) => Object.keys(m).filter((k) => m[k] === TODAY);
  const finishedToday = allRuns.filter((r) => r.at && day(new Date(r.at)) === TODAY && !SELF.includes(r.machine));

  const facts = {
    now: NOW.toISOString(), today: TODAY, window_from: from, prev_fingerprint: prev?.fingerprint ?? "",
    waiting,
    steady, schedules,
    threads: threads(caps),
    decisions: decisionNotes.filter((n) => n.mtime > from).map((n) => ({ path: n.path, title: n.title })),
    candidates: caps.filter((c) => DECISION.test(c.text)).map((c) => ({ project: project(c), text: oneLine(c.text), file: c.file })),
    notes: touched.map((n) => ({ path: n.path, title: n.title, open: n.open })),
    changed: {
      captures: capturesSince(prev?.last_at ?? from).length,
      notes: allNotes.filter((n) => n.mtime > (prev?.last_at ?? from)).map((n) => n.path),
      runs: allRuns.filter((r) => r.at > (prev?.last_at ?? from) && !SELF.includes(r.machine)).map((r) => ({ machine: r.machine, state: r.state, path: `.decree/runs/${r.id}/message.md` })),
    },
    feeds: await feeds(focus),
    done: {
      ticked: today(next.checked).map((k) => { const [p, t] = k.split("\t"); return { path: p, text: t }; }),
      machines: today(next.machines),
      migrations: finishedToday.filter((r) => r.trigger === "migration" && r.state === "done").map((r) => ({ file: r.file, path: `.decree/runs/${r.id}/message.md` })),
      runs: finishedToday.filter((r) => r.trigger !== "migration").map((r) => ({ machine: r.machine, state: r.state, path: `.decree/runs/${r.id}/message.md` })),
      notes: today(next.notes),
      threads: threads(caps.filter((c) => day(new Date(c.ts)) === TODAY)).map((t) => ({ project: t.project, count: t.count, sources: t.sources, file: t.file })),
    },
    next,
  };
  writeAtomic(path.join(RUN, "facts.json"), JSON.stringify(facts, null, 2));

  // What the model sees: the facts it may cite, each with the path to link it to.
  const prompt = [
    `Today is ${TODAY}.`,
    `Waiting on the person:\n${facts.waiting.slice(0, 3).map((w) => `- ${w.machine} is ${w.status}${w.state ? ` in ${w.state}` : ""} (${w.path})`).join("\n") || "- nothing"}`,
    `Holding steady:\n${facts.steady.map((s) => `- ${s.machine} last run succeeded (${s.path})`).join("\n") || "- nothing yet"}`,
    `What they were working on:\n${facts.threads.map((t) => `- ${t.project}: ${t.count} prompts${t.sessions.map((s) => `\n  - last of a session: "${s.text}" (${s.file})`).join("")}`).join("\n") || "- nothing captured"}`,
    `Notes touched, with open checkboxes:\n${facts.notes.map((n) => `- ${n.title} (${n.path})${n.open.map((o) => `\n  - [ ] ${o}`).join("")}`).join("\n") || "- none"}`,
    `Decisions:\n${facts.decisions.map((d) => `- ${d.title} (${d.path})`).join("\n") || "- none"}`,
    facts.feeds ? `New feed items, by link:\n${facts.feeds.map((f) => `- ${f.link}: ${f.title}. ${f.summary}`).join("\n") || "- none"}` : "",
  ].filter(Boolean).join("\n\n");
  writeAtomic(path.join(RUN, "prompt.txt"), prompt + "\n");
  console.log(`gather: ${waiting.length} waiting, ${steady.length} steady, ${facts.threads.length} threads, ${facts.notes.length} notes, feeds ${facts.feeds ? facts.feeds.length : "off"}, recent since ${from}`);
}

// ── write ─────────────────────────────────────────────────────────────────────

type Facts = Awaited<ReturnType<typeof loadFacts>>;
const loadFacts = () => JSON.parse(read(path.join(RUN, "facts.json"))) as {
  today: string; prev_fingerprint: string;
  waiting: { machine: string; status: string; state: string; since: string; path: string }[];
  steady: { machine: string; path: string }[];
  schedules: { name: string; cron: string; machine: string; path: string }[];
  threads: { project: string; count: number; sessions: { text: string; file: string }[] }[];
  decisions: { path: string; title: string }[];
  candidates: { project: string; text: string; file: string }[];
  notes: { path: string; title: string; open: string[] }[];
  changed: { captures: number; notes: string[]; runs: { machine: string; state: string; path: string }[] };
  feeds: { title: string; link: string }[] | null;
  done: { ticked: { path: string; text: string }[]; machines: string[]; migrations: { file: string; path: string }[]; runs: { machine: string; state: string; path: string }[]; notes: string[]; threads: { project: string; count: number; sources: string[]; file: string }[] };
  next: Omit<State, "fingerprint">;
};

interface Model { picture?: string; next?: string; reasons?: Record<string, string> }

const list = (items: string[], empty: string) => (items.length ? items.map((i) => `- ${i}`).join("\n") : empty);
const md = (s: string) => s.replace(/([\[\]])/g, "\\$1");

function sections(f: Facts, m: Model) {
  const waiting = f.waiting.slice(0, 3).map((w) => `**${w.machine}** is ${w.status}${w.state ? ` in ${w.state}` : ""}${w.since ? ` since ${w.since.slice(0, 10)}` : ""} ([details](${w.path}))`);
  if (f.waiting.length > 3) waiting.push(`and ${f.waiting.length - 3} more in [.decree/attention/](.decree/attention/)`);
  const steady = f.steady.map((s) => `**${s.machine}**: last run succeeded ([run](${s.path}))`);
  if (f.schedules.length) steady.push(`Schedules active: ${f.schedules.map((s) => `[${s.name}](${s.path})`).join(", ")}`);
  const changed = [
    ...(f.changed.captures ? [`${f.changed.captures} new captures`] : []),
    ...f.changed.notes.map((p) => `[${p}](${p}) changed`),
    ...f.changed.runs.map((r) => `**${r.machine}** ran: ${r.state} ([run](${r.path}))`),
  ];
  return {
    picture: m.picture?.trim() ? `## The picture\n\n${m.picture.trim()}` : "",
    waiting: `## Waiting on you\n\n${list(waiting, "Nothing is waiting on you.")}`,
    next: m.next?.trim() ? `## One next thing\n\n${m.next.trim()}` : "",
    steady: `## Holding steady\n\n${list(steady, "Nothing has run yet.")}`,
    leftOff: `## Where you left off\n\n${list(f.threads.map((t) => `**${md(t.project)}**: ${t.count} prompt${t.count === 1 ? "" : "s"}${t.sessions.map((s) => `\n  - last: "${md(s.text)}" ([capture](${s.file}))`).join("")}`), "Nothing captured since the last digest.")}`,
    feeds: f.feeds === null ? "" : `## From your feeds\n\n${list(f.feeds.map((i) => `[${md(i.title || i.link)}](${i.link})${m.reasons?.[i.link] ? `: ${oneLine(m.reasons[i.link])}` : ""}`), "Nothing new in your feeds.")}`,
    rest: [
      "## Everything else",
      `### Decisions\n\n${list(f.decisions.map((d) => `[${md(d.title)}](${d.path})`), "No new decisions in notes/decisions/.")}`,
      ...(f.candidates.length ? [`### Decision candidates (not decided until you confirm)\n\n${list(f.candidates.map((c) => `${md(c.project)}: "${md(c.text)}" ([capture](${c.file}))`), "")}`] : []),
      `### Notes touched\n\n${list(f.notes.map((n) => `[${md(n.title)}](${n.path})${n.open.map((o) => `\n  - [ ] ${o}`).join("")}`), "None.")}`,
      `### Scheduled\n\n${list(f.schedules.map((s) => `[${s.name}](${s.path}): \`${s.cron}\` runs **${s.machine}**`), "Nothing scheduled.")}`,
      `### Changed since the last digest\n\n${list(changed, "Nothing.")}`,
    ].join("\n\n"),
    done: [
      "## Done",
      list([
        ...f.done.ticked.map((t) => `Ticked: ${t.text} ([note](${t.path}))`),
        ...f.done.machines.map((n) => `New machine: **${n}** ([machine](.decree/machines/${n}.yml))`),
        ...f.done.migrations.map((r) => `Migration landed: ${r.file} ([run](${r.path}))`),
        ...f.done.runs.map((r) => `**${r.machine}** finished: ${r.state} ([run](${r.path}))`),
        ...f.done.notes.map((p) => `New note: [${p}](${p})`),
        ...f.done.threads.map((t) => `Worked on **${md(t.project)}**: ${t.count} prompt${t.count === 1 ? "" : "s"}${t.sources.length ? ` via ${t.sources.join(", ")}` : ""} ([capture](${t.file}))`),
      ], "Nothing recorded today."),
    ].join("\n\n"),
  };
}

// Links are workspace-relative; a note in notes/ or notes/you-were-here/<YYYY>/ gets them rebased.
const rebase = (s: string, prefix: string) => s.replace(/\]\((?![a-z]+:)([^)]+)\)/g, (_, p) => `](${prefix}${p})`);
const plain = (s: string) => s.replace(/\[([^\]]+)\]\((?![a-z]+:)[^)]+\)/g, "$1").replace(/\\([\[\]])/g, "$1");

function write() {
  const f = loadFacts();
  let m: Model = {};
  try { m = JSON.parse(read(path.join(RUN, "model.json")) || "{}"); } catch { m = {}; }
  const s = sections(f, m);
  const head = `# You were here, ${f.today}`;
  const body = [s.picture, s.waiting, s.next, s.steady, s.leftOff, s.feeds, s.rest].filter(Boolean).join("\n\n");

  writeAtomic(path.join(WS, "notes", "you-were-here.md"), rebase(`${head}\n\n${body}\n`, "../"));
  const archive = path.join(WS, "notes", "you-were-here", f.today.slice(0, 4), `${f.today}.md`);
  writeAtomic(archive, rebase(`${head}\n\n${body}\n\n${s.done}\n`, "../../../"));
  console.log(`write: notes/you-were-here.md and ${path.relative(WS, archive)}`);

  fs.mkdirSync(STORE, { recursive: true });
  if (f.feeds?.length) fs.appendFileSync(path.join(STORE, "feeds-shown.tsv"), f.feeds.map((i) => `${i.link}\t${f.today}\n`).join(""));
  // Only what the data says, never the model's prose or a run id, decides "changed".
  const fingerprint = crypto.createHash("sha256").update(JSON.stringify([
    f.waiting.map((w) => [w.path, w.status, w.state]), f.steady.map((x) => x.machine), f.schedules,
    f.threads.map((t) => [t.project, t.count, t.sessions.map((s) => s.text)]), f.decisions, f.candidates, f.notes, f.feeds?.map((i) => i.link) ?? null,
  ])).digest("hex");
  writeAtomic(path.join(STORE, "state.json"), JSON.stringify({ ...f.next, fingerprint }, null, 2));

  if (fingerprint === f.prev_fingerprint) {
    console.log("write: nothing changed since the last digest, so no push");
    return;
  }
  // The push: The picture, Waiting on you, One next thing, Holding steady, then the
  // note. Cut at a section boundary to stay under ntfy's limit.
  // note_link wins; else code-server on the tailnet name Core is served on.
  const tailnet = process.env.EXIST_TAILNET_NAME;
  const link = process.env.DECREE_DATA_NOTE_LINK ||
    (tailnet ? `notes/you-were-here.md, in https://${tailnet}` : "workspace/notes/you-were-here.md");
  const footer = `Full digest: ${link}`;
  let push = "";
  for (const part of [s.picture, s.waiting, s.next, s.steady].filter(Boolean).map(plain)) {
    if (Buffer.byteLength(`${push}${part}\n\n${footer}`) > NTFY_LIMIT) break;
    push += `${part}\n\n`;
  }
  writeAtomic(path.join(RUN, "ntfy.md"), `${push}${footer}\n`);
  console.log("write: ntfy.md ready");
}

const step = process.argv[2];
if (step === "gather") gather().catch((e) => { console.error(e); process.exit(1); });
else if (step === "write") write();
else { console.error("usage: digest.ts gather|write"); process.exit(1); }
