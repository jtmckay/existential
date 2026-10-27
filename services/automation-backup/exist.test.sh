#!/usr/bin/env bash
# exist.test.sh — validate the backup daemon's supporting state.
#
# Read-only by design: an inbox file is something the daemon *executes*, so this
# observes the project and never queues a message.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "automation-backup" EXIST_IS_SERVICES_AUTOMATION_BACKUP
skip_if_disabled

file_present "decree inbox present" /repo/services/automation-backup/inbox
file_present "triage cron active" /repo/services/automation-backup/cron/triage.md

finish
