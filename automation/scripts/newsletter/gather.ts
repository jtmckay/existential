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
