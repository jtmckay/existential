#!/usr/bin/env bash
# exist.test.sh — validate the decree daemon's supporting state.
#
# Read-only by design: an inbox file is something the daemon *executes*, so this
# observes the project and never queues a message.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "automation" EXIST_IS_SERVICES_AUTOMATION
skip_if_disabled

# ── 1. Rendered state ────────────────────────────────────────────────────────

file_present "decree inbox present" /repo/volumes/workspace_data/.decree/inbox
file_present "first note present" /repo/volumes/workspace_data/notes/my-first-note.md
# entrypoint.sh writes it on the daemon's first start.
file_present "decree skill for claude present" /repo/volumes/workspace_data/.claude/skills/decree/SKILL.md

finish
