# Routine Authoring Guide

A routine is a shell script in `.decree/routines/` that decree executes
with env vars populated from message frontmatter and runtime context.
Routines invoke AI tools to perform work. They can be nested in
subdirectories for organization.

## Required Structure

Every routine must follow this structure:

    #!/usr/bin/env bash
    # Title
    #
    # Short description (shown in `decree routine` list).
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

## Environment Variables

Decree sets these env vars before running every routine and hook:

| Variable | Source | Description |
|---|---|---|
| `message_file` | auto | Path to message.md in the run directory |
| `message_id` | auto | Unique message identifier (e.g., `D0001-1432-01-add-auth-0`) |
| `message_dir` | auto | Run directory path (contains logs from prior attempts) |
| `chain` | frontmatter | Chain ID (`D<NNNN>-HHmm-<name>`) |
| `seq` | frontmatter | Sequence number in chain |

Additional env vars set for lifecycle hooks only:

| Variable | Hooks | Description |
|---|---|---|
| `DECREE_HOOK` | all hooks | Hook type name (`beforeAll`, `afterAll`, `beforeEach`, `afterEach`) |
| `DECREE_ATTEMPT` | beforeEach, afterEach | Current attempt number (1-indexed) |
| `DECREE_MAX_RETRIES` | beforeEach, afterEach | Configured max retries |
| `DECREE_ROUTINE_EXIT_CODE` | afterEach | Exit code of the routine that just ran |
| `DECREE_PRE_CHECK` | pre-check | Set to `"true"` during pre-check runs |

Custom frontmatter fields are also set as env vars (any key not in the
standard set is passed through).

## AI Invocations

Routines call AI tools directly — there is no magic variable. Write the
exact command you want:

    claude -p "Read ${message_file} and implement the requirements."
    copilot -p "Read ${message_file} and implement the requirements."
    opencode run "Read ${message_file} and implement the requirements."

The `decree init` command detects your AI backend and writes the correct
invocation into the default routines. If you switch tools or want a
different invocation, edit your routine scripts directly.

## Custom Parameter Discovery

Decree scans the routine from top to bottom:
1. Skips: shebang, comments, blanks, `set` builtins, pre-check block
2. Matches: `var_name="${var_name:-default_value}"`
3. Stops at first non-matching line
4. Excludes standard parameter names
5. Remaining variables are custom parameters
6. Empty defaults (`${var:-}`) mean optional with no default

Custom values come from message frontmatter — any key not in the
standard set is passed as an env var.

## Pre-Check Section

Every routine must include a pre-check gate:
- Gate on `DECREE_PRE_CHECK=true` env var
- Place after standard params, before custom params
- Exit 0 = routine is ready, exit non-zero = not ready
- Print missing dependency to **stderr** on failure
- Used by `decree routine <name>` and `decree verify`

## Nested Routines

Routines can be organized in subdirectories:

    .decree/routines/
    ├── develop.sh           # routine: develop
    ├── deploy/
    │   ├── staging.sh       # routine: deploy/staging
    │   └── production.sh    # routine: deploy/production
    └── review/
        └── pr.sh            # routine: review/pr

## Tips

- **Pre-check required**: Every routine must have a pre-check section
- **Parameter comments**: Use `# --- Standard Environment Variables ---` block to document vars
- **Optional marker**: Mark optional params with "Optional." in the comment
- **Discovery boundary**: Use a comment like `# --- Implementation ---`
- **Default values**: Use meaningful defaults where possible
- **`set -euo pipefail`**: Always include — decree expects non-zero on failure
- **Run directory**: Use `${message_dir}` for logs and context from prior attempts
- **AI-specific**: Routines should invoke an AI tool — they are not
  general-purpose shell scripts

## Available Routines

{routines}
