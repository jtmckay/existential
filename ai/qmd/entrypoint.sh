#!/usr/bin/env bash
# qmd's entrypoint: write qmd's config from the workspace, keep the index fresh
# in the background, then serve MCP over HTTP.
#
# The workspace is mounted read-only; everything qmd writes (index, config,
# downloaded models) lives in /cache, which is safe to delete: the next start
# rebuilds it. Nothing here can stop the server starting, so an indexing or
# model-download failure leaves search answering what it already has.
set -uo pipefail

WS=/workspace
CFG="$XDG_CONFIG_HOME/qmd/index.yml"
REFRESH="${QMD_REFRESH_SECONDS:-60}"
# qmd reads QMD_EMBED_MODEL only when set; compose passes it blank by default.
[[ -n "${QMD_EMBED_MODEL:-}" ]] || unset QMD_EMBED_MODEL

log() { echo "[qmd] $*" >&2; }

# Each .gitignore under the workspace, as qmd ignore globs relative to the
# workspace root. Negations (!pattern) have no qmd equivalent and are skipped,
# so a re-included path stays out of the index. Hidden files and folders are
# never indexed by qmd itself, whatever the rules say.
gitignore_globs() {
  local f dir line p
  while IFS= read -r f; do
    dir="${f#"$WS"/}"; dir="${dir%.gitignore}"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "${line// /}" || "$line" == \#* ]] && continue
      if [[ "$line" == !* ]]; then log "ignoring negation in ${f#"$WS"/}: $line"; continue; fi
      p="${line%/}"
      if [[ "$p" == /* ]]; then p="${dir}${p#/}"
      elif [[ "$p" == */* ]]; then p="${dir}${p}"
      else p="${dir}**/${p}"
      fi
      printf '%s\n%s\n' "$p" "$p/**"
    done < "$f"
  done < <(find "$WS" -name .gitignore -not -path '*/.*/*' 2>/dev/null | sort)
}

write_config() {
  local tmp="$CFG.tmp" g
  mkdir -p "$(dirname "$CFG")"
  {
    echo "collections:"
    echo "  workspace:"
    echo "    path: $WS"
    echo "    pattern: \"**/*.md\""
    echo "    ignore:"
    # QMD_IGNORE: extra comma-separated globs, relative to the workspace.
    { gitignore_globs; tr ',' '\n' <<<"${QMD_IGNORE:-}"; } | sed '/^[[:space:]]*$/d' | sort -u |
      while IFS= read -r g; do printf '      - "%s"\n' "${g//\"/\\\"}"; done
    echo "    context:"
    echo "      \"/\": \"The person's own notes, project knowledge and decisions: plain Markdown they write and edit.\""
    echo "      \"/ai\": \"Written by automations, not by the person: drafts and results to check before relying on them.\""
    echo "      \"/ai/conversations\": \"Prompts the person typed into an AI assistant, dated and with a session id. Historical questions, ideas and tentative suggestions, not decisions: check later notes and decisions before treating any of it as settled.\""
  } > "$tmp"
  # An empty ignore list is not valid YAML for qmd: drop the key.
  grep -q '^      - ' "$tmp" || sed -i '/^    ignore:$/d' "$tmp"
  mv "$tmp" "$CFG"
}

# One pass: re-read the rules, index what changed, embed what is new. A
# changed embedding model re-embeds everything once (vectors of two models
# cannot be compared). The result is one line in /cache/refresh.status, which
# exist.test.sh reads.
refresh() {
  local model="${QMD_EMBED_MODEL:-default}" out
  write_config
  if ! out=$(qmd update 2>&1); then
    log "INDEX UPDATE FAILED: $out"; echo "update-failed $(date -u +%FT%TZ)" > /cache/refresh.status; return
  fi
  local force=() pending
  [[ "$(cat /cache/embed-model 2>/dev/null)" == "$model" ]] || force=(-f)
  # `qmd embed` exits 0 even when the model download fails, so what counts is
  # what is still waiting for a vector afterwards.
  out=$(qmd embed "${force[@]}" 2>&1)
  pending=$(qmd status 2>/dev/null | sed -n 's/^ *Pending: *\([0-9]*\).*/\1/p')
  if [[ "${pending:-0}" == 0 ]]; then
    echo "$model" > /cache/embed-model
    echo "ok $(date -u +%FT%TZ)" > /cache/refresh.status
  else
    log "NEURAL INDEX NOT READY: ${pending} file(s) have no vectors, so search finds them by keyword only." \
        "$(tr -d '\033' <<<"$out" | grep -iE 'error|status code|fail' | tail -2)"
    echo "keyword-only ${pending} $(date -u +%FT%TZ)" > /cache/refresh.status
  fi
}

# The server reads the collection list once, at start: it must exist first.
write_config
( while :; do refresh; sleep "$REFRESH"; done ) &

exec qmd mcp --http --host 0.0.0.0 --port 8181
