---
machine: plugin
automation: notes
chart:
  description: Pull the notes vault from Nextcloud, compile it, index it, and push the result to Dropbox.
  initial: sync
  states:
    sync:
      invoke: notes
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  notes: |
    #!/usr/bin/env bash
    # notes — Orchestrates the complete note processing pipeline.
    #
    # Container paths (all absolute):
    #   /data/notes     — Nextcloud sync cache (in the decree_data volume: notes/)
    #   /data/dropbox   — compiled output for Dropbox (in the decree_data volume: dropbox/)
    #   $DECREE_LIB/notes/ — pipeline scripts (this plugin's lib)

    set -euo pipefail

    echo "--- Starting notes pipeline ---"

    bash "$DECREE_LIB"/notes/pull-nextcloud.sh
    bash "$DECREE_LIB"/notes/compile-notes.sh
    bash "$DECREE_LIB"/notes/generate-index.sh
    bash "$DECREE_LIB"/notes/push-dropbox.sh

    echo "--- Notes pipeline finished ---"
lib:
  notes/compile-notes.sh: |
    #!/usr/bin/env bash
    # Compile Notes
    #
    # Compiles Obsidian vault into per-directory markdown files for AI consumption.
    # Each directory becomes an output file containing all notes within it and its
    # subdirectories. Root-level files go into unfiled.md.
    # Skips compilation if no changes detected since last run.
    set -euo pipefail

    # --- Configuration ---
    NOTES_DIR="${NOTES_DIR:-/data/notes}"
    OUTPUT_DIR="${OUTPUT_DIR:-/data/dropbox}"
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
            if command -v jq &>/dev/null; then
                jq -r '.elements[]? | select(.type == "text") | .text // ""' "$file" \
                    2>/dev/null || echo "*[Excalidraw parse failed]*"
            else
                echo "*[Excalidraw — jq not available]*"
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
  notes/generate-index.sh: |
    #!/usr/bin/env bash
    # Generate Index
    #
    # Builds an index.md from compiled notes for LLM reference.
    # Lists each output file with its note titles and size.
    # Run manually after notes have been compiled.
    set -euo pipefail

    # --- Configuration ---
    OUTPUT_DIR="${OUTPUT_DIR:-/data/dropbox}"
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
    } > "${INDEX}.tmp"

    if [ -f "$INDEX" ] && cmp -s "${INDEX}.tmp" "$INDEX"; then
        rm -f "${INDEX}.tmp"
        echo "No changes to index."
    else
        mv "${INDEX}.tmp" "$INDEX"
        echo "  Wrote: index.md"
    fi
  notes/pull-nextcloud.sh: |
    #!/usr/bin/env bash
    # Sync Nextcloud
    #
    # Syncs notes from Nextcloud to the local notes cache at /data/notes.
    # Requires NOTES_REMOTE_DIR to be set (e.g. "Notes") and a configured
    # "nextcloud:" rclone remote at /secrets/rclone/rclone.conf.
    set -euo pipefail

    [ -f /secrets/rclone/rclone.conf ] || { echo "rclone.conf not found at /secrets/rclone/rclone.conf — run the nextcloud_rclone_remote migration" >&2; exit 1; }
    : "${NOTES_REMOTE_DIR:?NOTES_REMOTE_DIR is not set — AUTOMATION_NOTES_DIR in services/automation/.env}"

    echo "Syncing nextcloud:${NOTES_REMOTE_DIR} -> /data/notes"

    mkdir -p /data/notes
    touch /data/notes/.write-test 2>/dev/null \
        || { echo "ERROR: /data/notes is not writable — check volume mount and ownership" >&2; exit 1; }
    rm -f /data/notes/.write-test

    before=$(find /data/notes -type f -not -name '.write-test' | wc -l)
    rclone sync --config /secrets/rclone/rclone.conf \
        --stats-one-line --stats 0 \
        "nextcloud:${NOTES_REMOTE_DIR}" /data/notes
    after=$(find /data/notes -type f | wc -l)
    echo "Sync complete: ${after} file(s) (was ${before})"
  notes/push-dropbox.sh: |
    #!/usr/bin/env bash
    # Sync Dropbox
    #
    # Syncs compiled output to Dropbox via rclone.
    # Skips sync if the output volume is empty.
    set -euo pipefail

    # Check if output directory has content before syncing
    count=$(find /data/dropbox -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        rclone sync --config /secrets/rclone/rclone.conf \
            --exclude ".sync_*" \
            --exclude ".compile-*" \
            /data/dropbox "dropbox:${DROPBOX_DEST_DIR}"
    else
        echo "Output volume is empty, skipping sync."
    fi
---
# notes

Pull the notes vault from Nextcloud, compile it, index it, and push the result to Dropbox.
