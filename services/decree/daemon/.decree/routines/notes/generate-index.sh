#!/usr/bin/env bash
# Generate Index
#
# Builds an index.md from compiled notes for LLM reference.
# Lists each output file with its note titles and size.
# Run manually after notes have been compiled.
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
OUTPUT_DIR="${OUTPUT_DIR:-/dropbox_data}"
INDEX="${OUTPUT_DIR}/index.md"
MANIFEST="${OUTPUT_DIR}/.compile-manifest"

if [ ! -f "$MANIFEST" ]; then
    echo "No manifest found. Run compile-notes first." >&2
    exit 1
fi

echo "Generating index..."

{
    echo "# Notes Index"
    echo ""
    echo "Reference guide to compiled Obsidian vault contents."
    echo "Each file below contains all notes from the corresponding vault directory"
    echo "and its subdirectories. Use this to find relevant files without reading everything."
    echo ""

    while IFS= read -r filepath; do
        [ -f "$filepath" ] || continue
        filename=$(basename "$filepath")

        # File size in human-readable form
        size=$(du -h "$filepath" | awk '{print $1}')

        # Count notes (## headings = individual notes)
        note_count=$(grep -c '^## ' "$filepath" 2>/dev/null || echo "0")

        echo "## ${filename%.md}"
        echo ""
        echo "**File:** \`${filename}\` | **Notes:** ${note_count} | **Size:** ${size}"
        echo ""
        echo "**Contents:**"

        # Extract ## headings (note titles) as a bulleted list
        grep '^## ' "$filepath" 2>/dev/null | while IFS= read -r heading; do
            title="${heading#\#\# }"
            echo "- ${title}"
        done

        echo ""
    done < "$MANIFEST"
} > "$INDEX"

echo "  Wrote: index.md"
