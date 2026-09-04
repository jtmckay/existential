// Fetch and parse an RSS or Atom feed into a flat list of items.
// Works as a reusable library function OR as a standalone entry point when called
// directly by tsx (reads FEED_URL from env, writes one JSON object per line to stdout).

export interface FeedItem {
  guid: string;
  title: string;
  link: string;
  pubDate: string;
}

function decodeEntities(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/<[^>]+>/g, "")
    .trim();
}

function extractTag(block: string, tag: string): string {
  const m = block.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"));
  return m ? decodeEntities(m[1]) : "";
}

function extractLink(block: string): string {
  // Atom: <link href="..." rel="alternate"?/>
  const atomMatch = block.match(/<link\b[^>]*\bhref=["']([^"']+)["'][^>]*\/?>/i);
  if (atomMatch) return atomMatch[1];
  // RSS: <link>...</link>
  return extractTag(block, "link");
}

export async function fetchFeed(url: string): Promise<FeedItem[]> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Feed fetch failed (${res.status}): ${url}`);
  }
  const xml = await res.text();

  const rssBlocks = [...xml.matchAll(/<item\b[\s\S]*?<\/item>/gi)].map((m) => m[0]);
  const blocks = rssBlocks.length > 0
    ? rssBlocks
    : [...xml.matchAll(/<entry\b[\s\S]*?<\/entry>/gi)].map((m) => m[0]);

  return blocks
    .map((block) => {
      const link = extractLink(block);
      return {
        title: extractTag(block, "title"),
        link,
        guid: extractTag(block, "guid") || extractTag(block, "id") || link,
        pubDate: extractTag(block, "pubDate") || extractTag(block, "updated") || extractTag(block, "published"),
      };
    })
    .filter((item) => item.guid);
}

if (require.main === module) {
  const feedUrl = process.env.FEED_URL ?? "";
  if (!feedUrl) {
    console.error("FEED_URL is required");
    process.exit(1);
  }

  fetchFeed(feedUrl)
    .then((items) => {
      for (const item of items) {
        process.stdout.write(JSON.stringify(item) + "\n");
      }
    })
    .catch((err: Error) => {
      console.error(err.message);
      process.exit(1);
    });
}
