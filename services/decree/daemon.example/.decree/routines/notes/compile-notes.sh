#!/usr/bin/env bash
# Compile Notes
#
# Compiles Obsidian vault into per-directory markdown files for AI consumption.
# Each directory becomes an output file containing all notes within it and its
# subdirectories. Root-level files go into unfiled.md.
# Skips compilation if no changes detected since last run.
set -euo pipefail

message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    exit 0
fi

# --- Configuration ---
NOTES_DIR="${NOTES_DIR:-/notes_data}"
OUTPUT_DIR="${OUTPUT_DIR:-/dropbox_data}"
HASH_FILE="${OUTPUT_DIR}/.compile-hash"
MANIFEST="${OUTPUT_DIR}/.compile-manifest"

# --- Change Detection (content-based, ignores mtime) ---
current_hash=$(find "$NOTES_DIR" -type f \
  -not -path '*/.obsidian/*' \
  -not -path '*/.trash/*' \
  -not -path '*/.git/*' \
  -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')

if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" = "$current_hash" ]; then
    echo "No changes detected."
    exit 0
fi

echo "Changes detected, compiling..."

# --- Extract text from a file ---
extract() {
    local file="$1"
    local rel="${file#$NOTES_DIR/}"
    local name
    name=$(basename "$file")
    local ext="${file##*.}"

    echo "## $rel"
    echo ""

    if [[ "$name" == *.excalidraw.md ]]; then
        sed '/^%%$/,/^%%$/d; /^{$/,$d' "$file" 2>/dev/null || cat "$file"
    elif [[ "$ext" == "md" || "$ext" == "markdown" || "$ext" == "txt" ]]; then
        cat "$file"
    elif [[ "$ext" == "pdf" ]]; then
        if command -v pdftotext &>/dev/null; then
            pdftotext "$file" - 2>/dev/null || echo "*[PDF extraction failed]*"
        else
            echo "*[PDF — pdftotext not available]*"
        fi
    elif [[ "$ext" == "excalidraw" ]]; then
        if command -v python3 &>/dev/null; then
            python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for e in data.get('elements', []):
    if e.get('type') == 'text':
        print(e.get('text', ''))
" "$file" 2>/dev/null || echo "*[Excalidraw parse failed]*"
        else
            echo "*[Excalidraw — no parser available]*"
        fi
    else
        return
    fi

    echo ""
    echo "---"
    echo ""
}

# Track created files for cleanup
new_manifest=()

# --- Write only if content changed (avoids unnecessary mtime updates) ---
write_if_changed() {
    local target="$1"
    local tmp="${target}.tmp"
    cat > "$tmp"
    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$target"
    return 0
}

# --- Compile a directory (includes all subdirectory content) ---
compile_dir() {
    local dir="$1"
    local reldir="${dir#$NOTES_DIR/}"
    local name="${reldir//\//_}"
    local out="${OUTPUT_DIR}/${name}.md"
    local has_content=false

    # Check if directory has any matching files first
    local file_count
    file_count=$(find "$dir" -type f \
        \( -name '*.md' -o -name '*.txt' -o -name '*.pdf' -o -name '*.excalidraw' \) \
        -not -path '*/.obsidian/*' -not -path '*/.trash/*' -not -path '*/.git/*' \
        2>/dev/null | wc -l)

    if [ "$file_count" -eq 0 ]; then
        rm -f "$out"
        return
    fi

    {
        echo "# $name"
        echo ""
        echo "*Auto-compiled from Obsidian vault. Do not edit.*"
        echo ""

        while IFS= read -r -d '' file; do
            extract "$file"
        done < <(find "$dir" -type f \
            \( -name '*.md' -o -name '*.txt' -o -name '*.pdf' -o -name '*.excalidraw' \) \
            -not -path '*/.obsidian/*' -not -path '*/.trash/*' -not -path '*/.git/*' \
            -print0 2>/dev/null | sort -z)
    } | write_if_changed "$out" && echo "  Wrote: ${name}.md" || true

    new_manifest+=("$out")
}

# --- Root-level files → unfiled.md ---
unfiled="${OUTPUT_DIR}/unfiled.md"
has_root=false
for f in "$NOTES_DIR"/*; do
    [ -f "$f" ] || continue
    case "${f##*.}" in
        md|markdown|txt|pdf|excalidraw) has_root=true; break ;;
    esac
done

if [ "$has_root" = true ]; then
    {
        echo "# Unfiled"
        echo ""
        echo "*Auto-compiled from Obsidian vault. Do not edit.*"
        echo ""
        for f in "$NOTES_DIR"/*; do
            [ -f "$f" ] || continue
            case "${f##*.}" in
                md|markdown|txt|pdf|excalidraw) extract "$f" ;;
            esac
        done
    } | write_if_changed "$unfiled" && echo "  Wrote: unfiled.md" || true
    new_manifest+=("$unfiled")
else
    rm -f "$unfiled"
fi

# --- Walk all directories ---
while IFS= read -r -d '' dir; do
    compile_dir "$dir"
done < <(find "$NOTES_DIR" -mindepth 1 -type d \
    -not -path '*/.obsidian/*' -not -path '*/.trash/*' -not -path '*/.git/*' \
    -print0 2>/dev/null | sort -z)

# --- Clean up stale output files ---
if [ -f "$MANIFEST" ]; then
    while IFS= read -r old_file; do
        still_exists=false
        for new_file in "${new_manifest[@]}"; do
            if [ "$old_file" = "$new_file" ]; then
                still_exists=true
                break
            fi
        done
        if [ "$still_exists" = false ] && [ -f "$old_file" ]; then
            echo "  Removed stale: $(basename "$old_file")"
            rm -f "$old_file"
        fi
    done < "$MANIFEST"
fi

# --- Save state ---
printf '%s\n' "${new_manifest[@]}" > "$MANIFEST"
echo "$current_hash" > "$HASH_FILE"
echo "Compilation complete."
