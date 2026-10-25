#!/usr/bin/env bash
# firecrawl.sh — the web, read through the stack's own Firecrawl.
#
# Sourced. Firecrawl searches DuckDuckGo itself and scrapes each result in the
# same call, so one web_search is a set of sources a model can read, not a list
# of links. Over the exist bridge it needs no key (caddy gates only the LAN side).
#
#   firecrawl_on              true when Firecrawl is enabled (or FIRECRAWL_URL set)
#   web_search <query> [n]    the top n results (default 5), each its page's text as
#                             Markdown inside <source url="...">…</source> (pages have
#                             headings of their own); nothing when nothing was found
#   web_read <url>            one page as Markdown
#
# Both fail, saying why, when Firecrawl is off or does not answer.

FIRECRAWL_URL="${FIRECRAWL_URL:-}"
[[ -z "$FIRECRAWL_URL" && "${EXIST_IS_AI_FIRECRAWL:-false}" == true ]] && FIRECRAWL_URL="http://firecrawl:3002"
# Characters kept of each page: five pages fit any tier's context with room to spare.
WEB_PAGE_CHARS="${WEB_PAGE_CHARS:-4000}"

firecrawl_on() { [[ -n "$FIRECRAWL_URL" ]]; }

_firecrawl() {  # _firecrawl <path> <json>
    firecrawl_on || { echo "firecrawl: not enabled (EXIST_IS_AI_FIRECRAWL=true turns it on)" >&2; return 1; }
    curl -fsS --max-time "${FIRECRAWL_TIMEOUT:-180}" -X POST "${FIRECRAWL_URL%/}$1" \
        -H "Content-Type: application/json" -d "$2" ||
        { echo "firecrawl: no answer from ${FIRECRAWL_URL}$1" >&2; return 1; }
}

web_search() {
    local reply
    reply="$(_firecrawl /v2/search "$(jq -n --arg q "$1" --argjson n "${2:-5}" \
        '{query: $q, limit: $n, scrapeOptions: {formats: ["markdown"], onlyMainContent: true}}')")" || return 1
    # Images are links a model cannot see: dropped, so the budget goes to text.
    jq -r --argjson max "$WEB_PAGE_CHARS" '.data.web[]? |
        ((.markdown // "") | gsub("\\[?!\\[[^\\]]*\\]\\([^)]*\\)(\\]\\([^)]*\\))?"; "") | gsub("\n\\s*\n(\\s*\n)+"; "\n\n")) as $text |
        "<source url=\"\(.url)\">\n# \(.title // .metadata.title // "untitled")\n\(.description // "")\n\n\($text[:$max])\n</source>\n"' <<<"$reply"
}

web_read() {
    local reply
    reply="$(_firecrawl /v2/scrape "$(jq -n --arg u "$1" '{url: $u, formats: ["markdown"], onlyMainContent: true}')")" || return 1
    jq -r '.data.markdown // ""' <<<"$reply"
}
