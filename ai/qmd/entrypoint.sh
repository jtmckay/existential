#!/usr/bin/env bash
# qmd's entrypoint: write qmd's config from the workspace, keep the index fresh
# in the background, then serve MCP over HTTP.
#
# The workspace is mounted read-only; everything qmd writes (index, config,
# downloaded models, the text of PDF and Word files) lives in /cache, which is
# safe to delete: the next start rebuilds it. Nothing here can stop the server
# starting, so an indexing or model-download failure leaves search answering
# what it already has.
set -uo pipefail

WS=/workspace
DOCS=/cache/documents
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

# Every ignore rule: the .gitignore files plus QMD_IGNORE (comma-separated).
ignore_globs() {
  { gitignore_globs; tr ',' '\n' <<<"${QMD_IGNORE:-}"; } | sed '/^[[:space:]]*$/d' | sort -u
}

# Whether <path> matches one of the globs. In [[ ]] a * also crosses /, so this
# matches at least what qmd's own matcher does: in doubt, a file is left out.
ignored() {  # <path> <glob>...
  local rel=$1 g p; shift
  for g; do
    p="${g//\*\*/*}"
    # shellcheck disable=SC2053  # the glob is the point
    [[ "$rel" == $p ]] && return 0
    # shellcheck disable=SC2053  # and "**/x" also matches x at the top level
    [[ "$g" == '**/'* && "$rel" == ${p#\*/} ]] && return 0
  done
  return 1
}

# Each PDF and Word (.docx) file in the workspace as Markdown qmd can index:
# $DOCS/<path>.md holds the text of <path>, a PDF's pages as "## Page N"
# headings. Text layers only, no OCR: a file with no text (a scan) gets
# <path>.md.none with the reason instead. Each output carries its source's
# mtime, so a file is converted again only when it changes, and an output whose
# source is gone or now ignored is deleted.
convert_documents() {
  local -a globs; mapfile -t globs < <(ignore_globs)
  local -A keep=()
  local src rel out f body why rc
  while IFS= read -r -d '' src; do
    rel="${src#"$WS"/}"
    ignored "$rel" "${globs[@]}" && continue
    out="$DOCS/$rel.md"; keep["$out"]=1
    for f in "$out" "$out.none"; do
      [[ -e "$f" && ! "$f" -nt "$src" && ! "$f" -ot "$src" ]] && continue 2
    done
    mkdir -p "$(dirname "$out")"; rm -f "$out" "$out.none"
    rc=0
    case "${src,,}" in
      *.pdf)  body=$(pdftotext -q -enc UTF-8 "$src" - |
                awk 'BEGIN { RS = "\f" } NF { printf "## Page %d\n\n%s\n\n", NR, $0 }') || rc=$? ;;
      # Images come out as data: URIs, which are not text, and punctuation
      # comes out backslash-escaped ("HO\-3"), which a snippet shouldn't show.
      *.docx) body=$(mammoth --output-format=markdown "$src" 2>/dev/null |
                sed -E 's/!\[[^]]*\]\(data:[^)]*\)//g; s/\\([[:punct:]])/\1/g') || rc=$? ;;
    esac
    if (( rc == 0 )) && grep -q '[[:alnum:]]' <<<"$body"; then
      printf '# %s\n\nText extracted from `%s` in the workspace.\n\n%s\n' "${rel##*/}" "$rel" "$body" > "$out.tmp"
      mv "$out.tmp" "$out"; touch -r "$src" "$out"
    else
      why="no text layer: a scan or images only (OCR is not supported)"
      (( rc == 0 )) || why="could not be read (encrypted or damaged)"
      echo "$why" > "$out.none"; touch -r "$src" "$out.none"
      log "not searchable: $rel: $why"
    fi
  done < <(find "$WS" -path '*/.*' -prune -o -type f \( -iname '*.pdf' -o -iname '*.docx' \) -print0 2>/dev/null)
  while IFS= read -r -d '' out; do
    [[ -n "${keep[${out%.none}]:-}" ]] || rm -f "$out"
  done < <(find "$DOCS" -type f \( -name '*.md' -o -name '*.none' \) -print0)
  find "$DOCS" -mindepth 1 -type d -empty -delete
}

write_config() {
  local tmp="$CFG.tmp" ignore
  mkdir -p "$(dirname "$CFG")" "$DOCS"
  # The documents mirror the workspace's paths, so the same rules apply to both.
  ignore=$(ignore_globs | while IFS= read -r g; do printf '      - "%s"\n' "${g//\"/\\\"}"; done)
  {
    echo "collections:"
    echo "  workspace:"
    echo "    path: $WS"
    echo "    pattern: \"**/*.md\""
    [[ -z "$ignore" ]] || printf '    ignore:\n%s\n' "$ignore"
    echo "    context:"
    echo "      \"/\": \"The person's own notes, project knowledge and decisions: plain Markdown they write and edit.\""
    echo "      \"/ai\": \"Written by automations, not by the person: drafts and results to check before relying on them.\""
    echo "      \"/ai/conversations\": \"Prompts the person typed into an AI assistant, dated and with a session id. Historical questions, ideas and tentative suggestions, not decisions: check later notes and decisions before treating any of it as settled.\""
    echo "  documents:"
    echo "    path: $DOCS"
    echo "    pattern: \"**/*.md\""
    [[ -z "$ignore" ]] || printf '    ignore:\n%s\n' "$ignore"
    echo "    context:"
    echo "      \"/\": \"Text extracted from the person's PDF and Word files, which they keep but did not necessarily write. qmd://documents/<path>.md is the text of <path> in the workspace; '## Page N' headings are a PDF's pages, and line numbers count lines of this text, not of the original file.\""
  } > "$tmp"
  mv "$tmp" "$CFG"
}

# One pass: re-read the rules, convert changed documents, index what changed,
# embed what is new. A changed embedding model re-embeds everything once
# (vectors of two models cannot be compared). The result is one line in
# /cache/refresh.status, which exist.test.sh reads.
refresh() {
  local model="${QMD_EMBED_MODEL:-default}" out
  write_config
  convert_documents
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
