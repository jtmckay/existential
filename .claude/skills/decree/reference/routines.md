# Routines Reference

## Script Structure

```bash
#!/usr/bin/env bash
# Title
#
# Description shown by `decree routine`.
# Additional lines shown in detail view.
set -euo pipefail

# --- Standard Environment Variables ---
# message_file  - Path to message.md in the run directory
# message_id    - Full message ID (e.g., D0001-1432-01-add-auth-0)
# message_dir   - Run directory path (contains logs from prior attempts)
# chain         - Chain ID (D<NNNN>-HHmm-<name>)
# seq           - Sequence number in chain
message_file="${message_file:-}"
message_id="${message_id:-}"
message_dir="${message_dir:-}"
chain="${chain:-}"
seq="${seq:-}"

# Pre-check (required — exit 0 if ready, non-zero if not):
if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    command -v claude >/dev/null 2>&1 || { echo "claude not found" >&2; exit 1; }
    exit 0
fi

# Custom params (from frontmatter, discovered automatically):
my_param="${my_param:-default}"

# --- Implementation ---
claude -p "Read ${message_file} and implement the requirements.
Previous attempt logs (if any) are in ${message_dir} for context."
```

Routines call AI tools directly:

```bash
claude   -p "Read ${message_file} and implement the requirements."
copilot  -p "Read ${message_file} and implement the requirements."
opencode run "Read ${message_file} and implement the requirements."
```

## Pre-Check

Every routine must include a pre-check gate:
- Gate on `DECREE_PRE_CHECK=true`
- Place after standard params, before custom params
- Exit 0 = ready; non-zero = not ready (print missing dependency to stderr)
- Used by `decree routine <name>` and `decree verify`

## Custom Parameter Discovery

Decree scans the routine top to bottom:
1. Skips: shebang, comments, blanks, `set` builtins, pre-check block
2. Matches: `var_name="${var_name:-default_value}"`
3. Stops at first non-matching line after the pre-check block
4. Excludes standard parameter names
5. Empty defaults (`${var:-}`) = optional with no default

Values come from message frontmatter fields of the same name.

## Nested Routines

```
automations/shared_routines/
├── db-backup.sh         # routine: db-backup
├── volume-backup.sh     # routine: volume-backup
├── file-processor.sh    # routine: file-processor
```

## Registry & Shared Routines

In this repo all routines live in `automations/shared_routines/` (mounted as
`/work/.decree/shared_routines`). They are registered per-daemon in `config.exist.yml`:

```yaml
routine_source: "/work/.decree/shared_routines"
shared_routines:
  db-backup:
    enabled: true
  volume-backup:
    enabled: true
  notify:
    enabled: false    # opt-in
```

There are no daemon-local routines — the shared directory is the only source.

Discovery runs automatically at `decree process`, `decree daemon`, and `decree init`.
Hooks bypass the registry — they only need the script to exist on disk.

## Tips

- **`set -euo pipefail`**: Always include — Decree treats non-zero exit as failure
- **Run directory**: Use `${message_dir}` for logs and context from prior attempts
- **Routines are non-interactive**: Must run without user input
- **Outbox**: Write follow-up messages to `.decree/outbox/`, not `.decree/inbox/` — see SKILL.md
