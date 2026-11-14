---
machine: plugin
automation: look_back
needs:
  - model
  - you_were_here
chart:
  description: A look back over a range of the "you were here" archive, written to workspace/ai/you-were-here/<YYYY>/look-back-<from>-<to>.md and pointed at through ntfy.
  data:
    workspace: {type: string, default: /workspace}
    ntfy_topic: {type: string, default: exist}
    # The range is the period up to `to` (today when blank): year to date by default.
    period: {type: string, enum: [week, month, quarter, year], default: year}
    # Either end, YYYY-MM-DD, overrides the period's.
    from: {type: string, default: ""}
    to: {type: string, default: ""}
    # work: only what ai/you-were-here/scope.md names.
    scope: {type: string, enum: [all, work], default: all}
    # For cron: write nothing unless today is the period's last day.
    period_end_only: {type: bool, default: false}
  initial: look_back
  states:
    look_back:
      invoke: look_back
      transitions: {done: done}
      emits: [notify]
    done: {final: true}
    failed: {final: true}
scripts:
  look_back: |
    #!/usr/bin/env bash
    # Look back
    #
    # "What did I even do this year?": a range of the "you were here" archive, read
    # into Highlights, Themes, Decisions made and By the numbers by
    # lib/look-back/look-back.ts. The chat model, through lib/model.sh, writes only
    # In short from those facts; with the model unreachable the look back is the data
    # sections alone. Reads the archive, never rewrites it.
    #
    # Writes ai/you-were-here/<YYYY>/look-back-<from>-<to>.md (-work.md for the
    # work scope) and pushes a short pointer to it through notify.
    # automation-webhook's POST /look-back runs it on demand.
    set -euo pipefail
    # shellcheck source=../../lib/model.sh
    source "${DECREE_LIB}/model.sh"
    look_back="${DECREE_LIB}/look-back/look-back.ts"

    # A retry reuses the run dir: nothing from an earlier attempt may be read as this one.
    rm -f "${DECREE_RUN_DIR}"/{facts.json,model.json,ntfy.md}
    tsx "$look_back" gather
    [[ -f "${DECREE_RUN_DIR}/facts.json" ]] || exit 0

    system="You write the opening of a person's look back over a stretch of their days, from the facts given, and nothing else.
    Reply with one JSON object and no other text:
    {\"summary\": \"one short paragraph: what this stretch was about, grouped as you see fit\"}
    Use only the facts given. Link every claim to the day note it came from as a markdown link,
    [words](path), using the path in parentheses after that fact. Plain and calm: no judgement,
    no praise, no counts of missed days."

    if reply="$(MODEL_TIMEOUT=300 model_chat "$system" "$(cat "${DECREE_RUN_DIR}/prompt.txt")" 1000)" &&
        printf '%s' "$reply" | sed '/^```/d' |
            jq -ce 'select(type == "object") | {summary: (.summary // "" | tostring)}' \
            > "${DECREE_RUN_DIR}/model.json" 2>/dev/null; then
        echo "look_back: the model wrote In short"
    else
        rm -f "${DECREE_RUN_DIR}/model.json"
        echo "look_back: no usable answer from the model at $(model_url chat); writing the data sections alone"
    fi

    tsx "$look_back" write

    [[ -f "${DECREE_RUN_DIR}/ntfy.md" ]] || { echo "look_back: nothing finished or decided; no push"; exit 0; }
    decree emit --machine notify --param ntfy_topic="$DECREE_DATA_NTFY_TOPIC" \
        --param ntfy_title="Look back" --param ntfy_tags=calendar <"${DECREE_RUN_DIR}/ntfy.md" >/dev/null
    echo "look_back: pushed"
lib:
  look-back/look-back.ts: |
    #!/usr/bin/env tsx
    // look_back's data half. Two steps, with the model call between them in bash
    // (scripts/look_back.sh, through lib/model.sh):
    //
    //   look-back.ts gather   resolves the range, reads the "you were here" archive into
    //                         items and writes $DECREE_RUN_DIR/facts.json and prompt.txt;
    //                         with period_end_only set and the period not ending today,
    //                         writes nothing
    //   look-back.ts write    renders facts.json (+ model.json when the model answered) into
    //                         ai/you-were-here/<YYYY>/look-back-<from>-<to>.md and writes
    //                         $DECREE_RUN_DIR/ntfy.md, when anything finished or was decided
    //
    // The archive is the day notes lib/you-were-here/digest.ts writes; this only reads
    // them. A full week or month that already has a look back is read from that look
    // back's data block instead of its day notes, so a year reads ~12 files, not 365.
    // Every section is built here; the model writes only In short.
    //
    // Env: DECREE_DATA_WORKSPACE (default /workspace), DECREE_DATA_PERIOD, _FROM, _TO,
    // _SCOPE, _PERIOD_END_ONLY, DECREE_RUN_DIR; LOOK_BACK_NOW (ISO) pins the clock for tests.
    import * as fs from "node:fs";
    import * as path from "node:path";

    const WS = process.env.DECREE_DATA_WORKSPACE || "/workspace";
    const RUN = process.env.DECREE_RUN_DIR!;
    const ARCHIVE = path.join(WS, "ai", "you-were-here");
    const SCOPE_FILE = path.join(ARCHIVE, "scope.md");
    const NOW = process.env.LOOK_BACK_NOW ? new Date(process.env.LOOK_BACK_NOW) : new Date();
    const pad = (n: number) => String(n).padStart(2, "0");
    const TODAY = `${NOW.getFullYear()}-${pad(NOW.getMonth() + 1)}-${pad(NOW.getDate())}`;
    const DATA = "<!-- look-back-data ";

    // Dates are YYYY-MM-DD strings; arithmetic is done at UTC midnight so no zone shifts a day.
    const utc = (s: string) => new Date(`${s}T00:00:00Z`);
    const iso = (d: Date) => d.toISOString().slice(0, 10);
    const addDays = (s: string, n: number) => iso(new Date(utc(s).getTime() + n * 86400e3));
    const monthEnd = (s: string) => addDays(iso(new Date(Date.UTC(+s.slice(0, 4), +s.slice(5, 7), 1))), -1);
    const DATE = /^\d{4}-\d{2}-\d{2}$/;

    type Period = "week" | "month" | "quarter" | "year";
    function periodStart(p: Period, to: string) {
      const [y, m] = [to.slice(0, 4), +to.slice(5, 7)];
      if (p === "week") return addDays(to, -((utc(to).getUTCDay() + 6) % 7));
      if (p === "month") return `${to.slice(0, 7)}-01`;
      if (p === "quarter") return `${y}-${pad(Math.floor((m - 1) / 3) * 3 + 1)}-01`;
      return `${y}-01-01`;
    }
    // The last day of the period: tomorrow starts a new one.
    const periodEndsOn = (p: Period, d: string) => periodStart(p, addDays(d, 1)) === addDays(d, 1);

    const read = (f: string) => { try { return fs.readFileSync(f, "utf8"); } catch { return ""; } };
    const ls = (d: string) => { try { return fs.readdirSync(d).sort(); } catch { return []; } };
    const writeAtomic = (f: string, s: string) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(`${f}.tmp`, s); fs.renameSync(`${f}.tmp`, f); };

    // ── the archive ───────────────────────────────────────────────────────────────

    interface Item {
      date: string;      // the day note it came from
      kind: "ticked" | "note" | "migration" | "machine" | "decision" | "worked" | "run";
      text: string;
      link: string;      // workspace-relative
      project: string;
      sources: string[]; // capture sources, for "worked"
      count: number;     // prompts, for "worked"
      state: string;     // for "run"
    }

    // The project an archived path belongs to: its folder under notes/, else its top folder.
    function projectOf(link: string) {
      const parts = link.split("/");
      if (parts[0] === "notes") return parts.length > 2 ? parts[1] : "notes";
      return parts[0] === ".decree" ? "decree" : parts[0];
    }
    const unescape = (s: string) => s.replace(/\\([\[\]])/g, "$1");
    const ws = (link: string) => link.replace(/^(\.\.\/)+/, "");

    // section <text> <heading line>: the lines under it, up to the next heading of its level or above.
    function section(text: string, heading: string) {
      const level = heading.match(/^#+/)![0].length;
      const lines = text.split("\n");
      const at = lines.indexOf(heading);
      if (at < 0) return [];
      const end = lines.findIndex((l, i) => i > at && /^#+ /.test(l) && l.match(/^#+/)![0].length <= level);
      return lines.slice(at + 1, end < 0 ? undefined : end);
    }

    // One day note's items, from its Done section and its Decisions list.
    function dayItems(date: string, text: string): Item[] {
      const item = (kind: Item["kind"], text: string, link: string, extra: Partial<Item> = {}): Item =>
        ({ date, kind, text: unescape(text), link: ws(link), project: projectOf(ws(link)), sources: [], count: 0, state: "", ...extra });
      const out: Item[] = [];
      for (const l of section(text, "## Done")) {
        let m;
        if ((m = l.match(/^- Ticked: (.+) \(\[note\]\((.+)\)\)$/))) out.push(item("ticked", m[1], m[2]));
        else if ((m = l.match(/^- New machine: \*\*(.+)\*\* \(\[machine\]\((.+)\)\)$/))) out.push(item("machine", m[1], m[2]));
        else if ((m = l.match(/^- Migration landed: (.+) \(\[run\]\((.+)\)\)$/))) out.push(item("migration", m[1], m[2]));
        else if ((m = l.match(/^- \*\*(.+)\*\* finished: (\S+) \(\[run\]\((.+)\)\)$/))) out.push(item("run", m[1], m[3], { state: m[2] }));
        else if ((m = l.match(/^- New note: \[(.+)\]\((.+)\)$/))) out.push(item("note", m[1], m[2]));
        else if ((m = l.match(/^- Worked on \*\*(.+)\*\*: (\d+) prompts?(?: via (.+?))? \(\[capture\]\((.+)\)\)$/)))
          out.push(item("worked", m[1], m[4], { project: unescape(m[1]), count: +m[2], sources: m[3] ? m[3].split(", ") : [] }));
      }
      for (const l of section(text, "### Decisions")) {
        const m = l.match(/^- \[(.+)\]\((.+)\)$/);
        if (m) out.push(item("decision", m[1], m[2]));
      }
      return out;
    }

    // What a look back keeps for a longer one to read: the items and the days they came from.
    interface Data { from: string; to: string; days: string[]; items: Item[] }
    const dataOf = (text: string): Data | null => {
      const at = text.lastIndexOf(DATA);
      if (at < 0) return null;
      try { return JSON.parse(text.slice(at + DATA.length, text.indexOf(" -->", at))); } catch { return null; }
    };

    function readArchive(from: string, to: string) {
      const years = ls(ARCHIVE).filter((y) => /^\d{4}$/.test(y));
      const files = years.flatMap((y) => ls(path.join(ARCHIVE, y)).map((f) => path.join(ARCHIVE, y, f)));

      // Rollups: the "everything" look back of a full week or month inside the range,
      // longest first, never two over the same day.
      const full = (f: string, t: string) => (utc(f).getUTCDay() === 1 && t === addDays(f, 6)) || (f.endsWith("-01") && t === monthEnd(f));
      const rollups = files
        .map((f) => ({ file: f, m: path.basename(f).match(/^look-back-(\d{4}-\d{2}-\d{2})-(\d{4}-\d{2}-\d{2})\.md$/) }))
        .filter((r) => r.m && full(r.m[1], r.m[2]) && r.m[1] >= from && r.m[2] <= to && !(r.m[1] === from && r.m[2] === to))
        .map((r) => ({ file: r.file, from: r.m![1], to: r.m![2] }))
        .sort((a, b) => utc(b.to).getTime() - utc(b.from).getTime() - (utc(a.to).getTime() - utc(a.from).getTime()) || a.from.localeCompare(b.from));
      const used: Data[] = [];
      for (const r of rollups) {
        if (used.some((u) => r.from <= u.to && u.from <= r.to)) continue;
        const data = dataOf(read(r.file));
        if (data) used.push(data);
      }
      const covered = (d: string) => used.some((u) => d >= u.from && d <= u.to);
      const dayNotes = files
        .map((f) => path.basename(f, ".md"))
        .filter((d) => DATE.test(d) && d >= from && d <= to && !covered(d));

      const items = [
        ...used.flatMap((u) => u.items),
        ...dayNotes.flatMap((d) => dayItems(d, read(path.join(ARCHIVE, d.slice(0, 4), `${d}.md`)))),
      ].sort((a, b) => a.date.localeCompare(b.date));
      const days = [...new Set([...used.flatMap((u) => u.days), ...dayNotes])].sort();
      return { items, days, lookBacks: used.length, dayNotes: dayNotes.length };
    }

    // ── scope ─────────────────────────────────────────────────────────────────────

    const SCOPE_TEMPLATE = `# Look back scope

    What counts as work for a \`work\` look back. One \`- \` line per entry under each heading;
    an item matching any entry is work, everything else is left out.

    ## Projects

    A capture context's folder name (\`acme\` for /workspace/acme), or a folder under notes/
    (\`acme\` for notes/acme/).

    ## Folders

    Workspace-relative, such as \`notes/work/\`.

    ## Sources

    Capture sources, such as \`claude-code\`, \`opencode\` or \`webhook\`.
    `;

    function readScope() {
      if (!fs.existsSync(SCOPE_FILE)) writeAtomic(SCOPE_FILE, SCOPE_TEMPLATE);
      const text = read(SCOPE_FILE);
      const entries = (h: string) => section(text, `## ${h}`)
        .map((l) => l.match(/^\s*[-*] +(.+?)\s*$/)?.[1]?.replace(/`/g, "").trim() ?? "")
        .filter(Boolean);
      return {
        projects: new Set(entries("Projects")),
        folders: entries("Folders").map((f) => f.replace(/^(\.\/|\/?workspace\/)/, "").replace(/\/?$/, "/")),
        sources: new Set(entries("Sources")),
      };
    }

    // ── gather ────────────────────────────────────────────────────────────────────

    function gather() {
      const env = (k: string) => (process.env[`DECREE_DATA_${k}`] ?? "").trim();
      const period = (env("PERIOD") || "year") as Period;
      const scope = env("SCOPE") || "all";
      if (!["week", "month", "quarter", "year"].includes(period)) throw new Error(`period must be week, month, quarter or year, not "${period}"`);
      if (!["all", "work"].includes(scope)) throw new Error(`scope must be all or work, not "${scope}"`);
      if (env("PERIOD_END_ONLY") === "true" && !periodEndsOn(period, TODAY)) {
        console.log(`gather: ${TODAY} is not the last day of its ${period}; nothing to write`);
        return;
      }
      const to = env("TO") || TODAY;
      const from = env("FROM") || periodStart(period, to);
      for (const d of [from, to]) if (!DATE.test(d) || iso(utc(d)) !== d) throw new Error(`not a date (YYYY-MM-DD): "${d}"`);
      if (from > to) throw new Error(`from ${from} is after to ${to}`);

      const archive = readArchive(from, to);
      const sc = readScope();
      const inScope = (i: Item) => scope === "all" || sc.projects.has(i.project) ||
        sc.folders.some((f) => i.link.startsWith(f)) || i.sources.some((s) => sc.sources.has(s));
      const items = archive.items.filter(inScope);
      const seen = new Set<string>();
      const once = (i: Item) => !seen.has(`${i.kind}\t${i.link}\t${i.text}`) && Boolean(seen.add(`${i.kind}\t${i.link}\t${i.text}`));
      const of = (...kinds: Item["kind"][]) => items.filter((i) => kinds.includes(i.kind)).filter(once);

      const highlights = new Map<string, Item[]>();
      for (const i of of("ticked", "note", "migration")) highlights.set(i.project, [...(highlights.get(i.project) ?? []), i]);
      const themes = new Map<string, { days: Set<string>; prompts: number }>();
      for (const i of items.filter((x) => ["worked", "ticked", "note"].includes(x.kind))) {
        const t = themes.get(i.project) ?? { days: new Set<string>(), prompts: 0 };
        t.days.add(i.date);
        t.prompts += i.count;
        themes.set(i.project, t);
      }
      const runs = items.filter((i) => i.kind === "run");
      const name = `look-back-${from}-${to}${scope === "work" ? "-work" : ""}.md`;

      const facts = {
        from, to, scope, today: TODAY,
        file: path.join("ai", "you-were-here", to.slice(0, 4), name),
        read: { lookBacks: archive.lookBacks, dayNotes: archive.dayNotes },
        highlights: [...highlights.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]))
          .map(([project, xs]) => ({ project, items: xs })),
        themes: [...themes.entries()].filter(([, t]) => t.days.size > 1)
          .sort((a, b) => b[1].days.size - a[1].days.size || a[0].localeCompare(b[0])).slice(0, 10)
          .map(([project, t]) => { const ds = [...t.days].sort(); return { project, days: ds.length, prompts: t.prompts, first: ds[0], last: ds[ds.length - 1] }; }),
        decisions: of("decision", "machine"),
        numbers: {
          days: archive.days.length,
          prompts: items.filter((i) => i.kind === "worked").reduce((n, i) => n + i.count, 0),
          ticked: items.filter((i) => i.kind === "ticked").length,
          notes: items.filter((i) => i.kind === "note").length,
          migrations: items.filter((i) => i.kind === "migration").length,
          machines: items.filter((i) => i.kind === "machine").length,
          decisions: new Set(items.filter((i) => i.kind === "decision").map((i) => i.link)).size,
          runs: runs.length,
          failed: runs.filter((i) => i.state !== "done").length,
        },
        // Only an "everything" look back is read by a longer one, so only it keeps the data.
        data: scope === "all" ? { from, to, days: archive.days, items: archive.items } : null,
      };
      writeAtomic(path.join(RUN, "facts.json"), JSON.stringify(facts, null, 2));

      // What the model sees: the facts it may cite, each with the day note to link it to.
      const prompt = [
        `A look back over ${from} to ${to}${scope === "work" ? ", work only" : ""}.`,
        `What shipped or finished, by project:\n${facts.highlights.map((h) => `- ${h.project}\n${h.items.map((i) => `  - ${label(i)} (${dayLink(i.date)})`).join("\n")}`).join("\n") || "- nothing"}`,
        `What they kept coming back to:\n${facts.themes.map((t) => `- ${t.project}: ${t.days} days, ${t.prompts} prompts (${dayLink(t.first)} to ${dayLink(t.last)})`).join("\n") || "- nothing on more than one day"}`,
        `Decisions:\n${facts.decisions.map((i) => `- ${label(i)} (${dayLink(i.date)})`).join("\n") || "- none"}`,
      ].join("\n\n");
      writeAtomic(path.join(RUN, "prompt.txt"), prompt + "\n");
      console.log(`gather: ${from} to ${to}, scope ${scope}: ${items.length} items from ${archive.lookBacks} look backs and ${archive.dayNotes} day notes`);
    }

    // Links from a look back, which sits in ai/you-were-here/<YYYY>/, to a day note in any year.
    const dayLink = (date: string) => `../${date.slice(0, 4)}/${date}.md`;
    const md = (s: string) => s.replace(/([\[\]])/g, "\\$1");
    function label(i: Item) {
      switch (i.kind) {
        case "ticked": return `Ticked: ${i.text}`;
        case "note": return `New note: ${i.text}`;
        case "migration": return `Migration landed: ${i.text}`;
        case "machine": return `New machine: ${i.text}`;
        case "decision": return `Decision: ${i.text}`;
        default: return i.text;
      }
    }

    // ── write ─────────────────────────────────────────────────────────────────────

    type Facts = {
      from: string; to: string; scope: string; file: string;
      highlights: { project: string; items: Item[] }[];
      themes: { project: string; days: number; prompts: number; first: string; last: string }[];
      decisions: Item[];
      numbers: Record<string, number>;
      data: Data | null;
    };

    function write() {
      const f = JSON.parse(read(path.join(RUN, "facts.json"))) as Facts;
      let summary = "";
      try { summary = String(JSON.parse(read(path.join(RUN, "model.json")) || "{}").summary ?? "").trim(); } catch { summary = ""; }
      const day = (d: string) => `[${d}](${dayLink(d)})`;
      const list = (xs: string[], empty: string) => (xs.length ? xs.map((x) => `- ${x}`).join("\n") : empty);
      const n = f.numbers;

      const doc = [
        `# Look back, ${f.from} to ${f.to}${f.scope === "work" ? " (work)" : ""}`,
        summary ? `## In short\n\n${summary}` : "",
        `## Highlights\n\n${f.highlights.map((h) => `### ${md(h.project)}\n\n${list(h.items.map((i) => `${md(label(i))} (${day(i.date)})`), "")}`).join("\n\n") || "Nothing finished in this range."}`,
        `## Themes\n\n${list(f.themes.map((t) => `**${md(t.project)}**: ${t.days} days${t.prompts ? `, ${t.prompts} prompt${t.prompts === 1 ? "" : "s"}` : ""}, ${day(t.first)} to ${day(t.last)}`), "Nothing came up on more than one day.")}`,
        `## Decisions made\n\n${list(f.decisions.map((i) => `${md(label(i))} (${day(i.date)})`), "No decisions recorded.")}`,
        `## By the numbers\n\n${list([
          `Days recorded: ${n.days}`, `Prompts: ${n.prompts}`, `Checkboxes ticked: ${n.ticked}`, `Notes created: ${n.notes}`,
          `Migrations landed: ${n.migrations}`, `Machines added: ${n.machines}`, `Decision notes: ${n.decisions}`,
          `Runs finished: ${n.runs} (${n.failed} not done)`,
        ], "")}`,
        f.data ? `${DATA}${JSON.stringify(f.data)} -->` : "",
      ].filter(Boolean).join("\n\n");
      writeAtomic(path.join(WS, f.file), `${doc}\n`);
      console.log(`write: ${f.file}`);

      // A push only when there is something to see: the file is written either way.
      const shipped = f.highlights.reduce((k, h) => k + h.items.length, 0);
      if (!shipped && !f.decisions.length) return;
      writeAtomic(path.join(RUN, "ntfy.md"),
        `${f.from} to ${f.to}${f.scope === "work" ? ", work" : ""}: ${shipped} highlight${shipped === 1 ? "" : "s"}, ` +
        `${f.decisions.length} decision${f.decisions.length === 1 ? "" : "s"} over ${n.days} recorded day${n.days === 1 ? "" : "s"}.\n\n` +
        `workspace/${f.file}\n`);
    }

    const step = process.argv[2];
    try {
      if (step === "gather") gather();
      else if (step === "write") write();
      else { console.error("usage: look-back.ts gather|write"); process.exit(1); }
    } catch (e) {
      console.error(`look-back: ${(e as Error).message}`);
      process.exit(1);
    }
endpoints:
  # A look back over the "you were here" archive: year to date by default, or the
  # week, month, quarter or year so far, optionally work only (scope.md in
  # ai/you-were-here/). Any other range: the machine from the work dir.
  - path: /look-back
    body: optional
    message:
      machine: look_back
  - path: /look-back/{period}
    body: optional
    patterns: {period: "week|month|quarter|year"}
    message:
      machine: look_back
      params: {period: "{{period}}"}
  - path: /look-back/{period}/{scope}
    body: optional
    patterns: {period: "week|month|quarter|year", scope: "all|work"}
    message:
      machine: look_back
      params: {period: "{{period}}", scope: "{{scope}}"}
---
# look_back

A look back over a range of the "you were here" archive, written to workspace/ai/you-were-here/<YYYY>/look-back-<from>-<to>.md and pointed at through ntfy.

It needs, on the stack that installs it:

- $DECREE_LIB/look-back/look-back.ts
- $DECREE_LIB/model.sh
