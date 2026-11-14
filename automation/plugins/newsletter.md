---
machine: plugin
automation: newsletter
needs:
  - model
  - rss
chart:
  description: Gather new items from my feeds, pick and summarise the ones that fit my taste, and write the issue to workspace/newsletter/.
  data:
    # The most new items gather hands to the model, newest first.
    NEWSLETTER_MAX_ITEMS: {type: int, default: 60}
    NEWSLETTER_DIR: {type: string, default: /workspace/newsletter}
  store:
    seen.tsv: Links already sent, so an item is never in two issues. gather reads it; deliver appends.
  initial: gather
  states:
    gather: # new items from lib/newsletter/feeds.txt, by link not in seen.tsv -> items.jsonl
      invoke: gather
      transitions: {done: write}
    write: # the chat model reads lib/newsletter/taste.md and items.jsonl, writes issue.md
      invoke: write
      transitions: {done: deliver}
    deliver: # issue.md to NEWSLETTER_DIR/<date>.md, its links to seen.tsv, a notify ping
      invoke: deliver
      transitions: {done: done}
      emits: [notify]
    done: {final: true}
    failed: {final: true}
scripts:
  deliver: |
    #!/usr/bin/env bash
    # newsletter's deliver: copy the run's issue.md to NEWSLETTER_DIR/<YYYY-MM-DD>.md (-2,
    # -3 when that day already has an issue), record every gathered link in
    # $DECREE_STORE/seen.tsv with the date, and send the issue's first lines as a
    # notification when anything was new. Safe to re-run: an identical issue is not copied twice, and a link
    # already in seen.tsv is not added again.
    #
    # Written straight to disk, so Nextcloud shows it but no file event fires.
    set -euo pipefail
    dir="$DECREE_DATA_NEWSLETTER_DIR"
    issue="${DECREE_RUN_DIR}/issue.md"
    items="${DECREE_RUN_DIR}/items.jsonl"
    today="$(date +%F)"
    mkdir -p "${dir}"

    # The day's file name: the first free one, or the one already holding this issue.
    target="${dir}/${today}.md"
    n=1
    while [ -e "${target}" ] && ! cmp -s "${issue}" "${target}"; do
      n=$((n + 1))
      target="${dir}/${today}-${n}.md"
    done
    cp "${issue}" "${target}"
    echo "deliver: ${target}"

    seen="${DECREE_STORE}/seen.tsv"
    touch "${seen}"
    added=0
    if [ -s "${items}" ]; then
      while IFS= read -r link; do
        if ! cut -f1 "${seen}" | grep -qxF -- "${link}"; then
          printf '%s\t%s\n' "${link}" "${today}" >> "${seen}"
          added=$((added + 1))
        fi
      done < <(jq -r '.link' "${items}")
    fi
    echo "deliver: ${added} links added to ${seen}"

    [ -s "${items}" ] || { echo "deliver: nothing new; no push"; exit 0; }
    head -n 5 "${target}" | decree emit --machine notify \
      --param ntfy_title="Newsletter, ${today}" --param ntfy_tags=newspaper >/dev/null
  gather.ts: |
    #!/usr/bin/env tsx
    // newsletter's gather: the new items of every feed in $DECREE_LIB/newsletter/feeds.txt.
    //
    // Writes $DECREE_RUN_DIR/items.jsonl, one JSON object per line (title, link, source,
    // published, summary), newest first, at most NEWSLETTER_MAX_ITEMS. An item is new when
    // its link is not in $DECREE_STORE/seen.tsv. It does not mark items seen: deliver does,
    // so a failed run gathers them again next time. A feed that fails is logged and
    // skipped; every feed failing is an error.
    import * as fs from "node:fs";
    import * as path from "node:path";
    import { fetchFeed } from "../../lib/rss";

    async function main(): Promise<number> {
      const lib = process.env.DECREE_LIB!;
      const runDir = process.env.DECREE_RUN_DIR!;
      const maxItems = Number(process.env.DECREE_DATA_NEWSLETTER_MAX_ITEMS ?? "60");

      const urls = fs.readFileSync(path.join(lib, "newsletter", "feeds.txt"), "utf8")
        .split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
      if (urls.length === 0) {
        console.error("gather: feeds.txt lists no feeds");
        return 1;
      }

      const seenFile = path.join(process.env.DECREE_STORE!, "seen.tsv");
      const seen = new Set(fs.existsSync(seenFile)
        ? fs.readFileSync(seenFile, "utf8").split("\n").map((l) => l.split("\t")[0].trim()).filter(Boolean)
        : []);

      const items = new Map<string, { title: string; link: string; source: string; published: string; summary: string }>();
      let failed = 0;
      for (const url of urls) {
        try {
          const found = await fetchFeed(url);
          const fresh = found.filter((i) => i.link && !seen.has(i.link));
          for (const i of fresh) {
            if (!items.has(i.link)) {
              const when = Date.parse(i.pubDate);
              items.set(i.link, {
                title: i.title, link: i.link, source: url, summary: i.summary,
                published: Number.isNaN(when) ? "" : new Date(when).toISOString(),
              });
            }
          }
          console.log(`gather: ${url}: ${found.length} items, ${fresh.length} new`);
        } catch (err) {
          console.error(`gather: skipping ${url}: ${(err as Error).message}`);
          failed++;
        }
      }
      if (failed === urls.length) {
        console.error(`gather: all ${failed} feeds failed`);
        return 1;
      }

      // Newest first; ISO 8601 strings sort as dates, and undated items go last.
      const newest = [...items.values()]
        .sort((a, b) => b.published.localeCompare(a.published))
        .slice(0, maxItems);
      const out = path.join(runDir, "items.jsonl");
      fs.writeFileSync(`${out}.tmp`, newest.map((i) => JSON.stringify(i) + "\n").join(""));
      fs.renameSync(`${out}.tmp`, out);
      console.log(`gather: ${newest.length} new items in items.jsonl`);
      return 0;
    }

    main().then((code) => process.exit(code));
  write: |
    #!/usr/bin/env bash
    # newsletter's write: the chat model (EXIST_MODEL_CHAT, on its own endpoint) reads
    # $DECREE_LIB/newsletter/taste.md and the run's items.jsonl, and picks and summarises
    # the items worth reading. Writes $DECREE_RUN_DIR/issue.md: a title with the date,
    # then the model's picks as markdown links. With no new items it says so, without
    # calling the model.
    set -euo pipefail
    # shellcheck source=../../lib/model.sh
    source "${DECREE_LIB}/model.sh"
    items="${DECREE_RUN_DIR}/items.jsonl"
    taste="${DECREE_LIB}/newsletter/taste.md"
    issue="${DECREE_RUN_DIR}/issue.md"
    today="$(date +%F)"
    : "${EXIST_MODEL_CHAT:?EXIST_MODEL_CHAT not set}"
    export MODEL_TIMEOUT=600

    if [ ! -s "${items}" ]; then
      printf '# Newsletter, %s\n\nNothing new in your feeds since the last issue.\n' "${today}" > "${issue}"
      echo "write: no new items; wrote the nothing-new issue without calling the model"
      exit 0
    fi

    instructions="You write a personal newsletter. The reader describes their taste below. Pick the items that fit it, and follow the format it asks for. Reply with the markdown list only: one line per item, '- [title](link): what it is and why it matters'. Use only links from the items given.

    $(cat "${taste}")"

    echo "write: asking ${EXIST_MODEL_CHAT} at $(model_url chat) about $(wc -l < "${items}") items"
    picks="$(model_chat "${instructions}" "The new items, one JSON object per line:

    $(cat "${items}")" 4000)"
    if [ -z "${picks//[[:space:]]/}" ]; then
      echo "write: the model's reply has no content" >&2
      exit 1
    fi

    printf '# Newsletter, %s\n\n%s\n' "${today}" "${picks}" > "${issue}.tmp"
    mv "${issue}.tmp" "${issue}"
    echo "write: wrote issue.md"
lib:
  newsletter/feeds.exist.txt: |
    # One RSS or Atom feed URL per line. Lines starting with # are comments.
    # The newsletter machine reads this every run — edit it, no restart needed.
    https://simonwillison.net/atom/everything/
    https://lwn.net/headlines/rss
    https://hnrss.org/best
  newsletter/taste.exist.md: |
    # What I want in my newsletter

    Edit this. It is the whole judgment: the model reads it every week and picks
    from your feeds (feeds.txt) by it.

    I run my own small servers and build things with them, so I want what changes
    how I work: releases of tools I could use this week, security fixes for software
    I am likely to run, and the occasional long piece that explains why something
    works the way it does. Practical beats clever.

    I skip announcements of events, job posts, funding news, and anything that is
    mostly a link to somewhere else. If two items are about the same thing, keep the
    better one.

    The format: at most 7 items, the best first, one line each. Each line says what
    it is and why it matters to me, in plain words, and links to it. If nothing is
    worth my time this week, say so in one line rather than padding the list.
---
# newsletter

Gather new items from my feeds, pick and summarise the ones that fit my taste, and write the issue to workspace/newsletter/.

It needs, on the stack that installs it:

- $DECREE_LIB/model.sh
- $DECREE_LIB/newsletter/taste.md
