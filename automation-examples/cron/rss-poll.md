---
cron: "*/15 * * * *"
routine: rss-poll
feed_url: https://github.com/kubernetes/kubernetes/commits/master.atom
filter_pattern: "security|CVE|vulnerab"
fwd_ntfy_title: RSS match
fwd_ntfy_topic: decree
---

Polls a repo's commit feed every 15 minutes and queues a `notify` message for
any item whose title matches `filter_pattern` (an ERE, matched
case-insensitively) — any GitHub repo has one at
`https://github.com/<owner>/<repo>/commits/<branch>.atom`, and most blogs and
news sites publish an RSS or Atom feed too. Swap `feed_url` and
`filter_pattern` for your own feed and keywords.

The first run for a given `feed_url` only records its current items as seen
— it writes nothing to the outbox, so activating this against an established
feed doesn't flood you with its entire backlog. Every run after that only
evaluates items published since the last run.

`chain_routine` (default: `notify`) is the routine each match is handed to.
Any frontmatter field prefixed `fwd_` is forwarded into that message with the
prefix stripped — e.g. `fwd_ntfy_title`/`fwd_ntfy_topic` above become
`ntfy_title`/`ntfy_topic` on the `notify` message. Point `chain_routine` at a
different routine and forward whatever params it expects instead.

Copy to automation/cron/ and restart automation to activate.
