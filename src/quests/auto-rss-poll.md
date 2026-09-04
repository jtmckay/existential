---
name: RSS Feed Watcher
tagline: Tap an RSS or Atom feed and get notified when an item matches your filter
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

Reference example for tapping an external feed: rss-poll fetches an RSS or
Atom feed on a schedule, filters new items against a regex you choose, and
hands matches to Decree — by default straight to a notify message, but any
routine can be on the other end.

How it works:
  - rss.ts (automation/lib/rss.ts) fetches the feed and parses each item's
    title, link, guid, and publish date
  - rss-poll (automation/shared_routines/rss-poll.sh) tracks which guids it
    has already seen per feed, tests filter_pattern against new titles, and
    queues one outbox message per match

IMPORTANT — the first run for a feed is a no-op by design. It records every
item currently in the feed as seen without filtering, so turning this on
against an established feed does not fire a notification for its entire
backlog. Every run after that only evaluates items published since the last
run.

Enable the routine in services/automation/decree/config.yml:
  rss-poll:
    enabled: true

Activate it:
  mkdir -p automation/cron/
  cp automation-examples/cron/rss-poll.md automation/cron/
  docker compose restart automation

Making it yours — everything is cron frontmatter, no code changes:
  feed_url         the RSS or Atom feed to poll. Any GitHub repo has one at
                    https://github.com/<owner>/<repo>/commits/<branch>.atom
                    (or /releases.atom); most blogs and news sites publish one too
  filter_pattern    an ERE tested case-insensitively against each new item's
                    title. This IS the deterministic filter — no model call,
                    just a regex
  chain_routine     which routine gets the match (default: notify). Point it
                    at your own routine instead and forward whatever params
                    it expects
  fwd_*             any frontmatter field prefixed fwd_ is forwarded into the
                    chained message with the prefix stripped — e.g.
                    fwd_ntfy_title becomes ntfy_title on a notify message

See it deliver:
  Matches chain to notify by default, which needs ntfy to actually reach you
  — see the Notifications (ntfy) quest if that is not set up yet.

Logs for each run land in automation/runs/ and are queryable in Grafana via
the Decree Overview dashboard.
