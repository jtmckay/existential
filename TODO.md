# TODO

A running cleanup backlog — things we know we want to delete or collapse, not a spec for anything
new. Items come off the list as they land; if an item stops being true, delete the line rather
than rewriting it.

## Open

- [ ] **Cron rows in results.md are timing-dependent since the migration switch.** The old
      inbox-drain wait incidentally gave the daemon's `triage`/`notify` crons time to fire and be
      graded; `await_migrations` returns as soon as migrations finish, so the same tree reports
      10/10 or 12/12 depending on timing. Either wait deliberately for them or stop grading them,
      but a table that changes run to run is not evidence.
- [ ] Three `.gitkeep`s under `services/decree/` could not be positively justified *or* ruled out:
      `decree/migrations/`, `decree-backup/cron/`, `decree-backup/inbox/`. Each is gitignored, so
      the `.gitkeep` is the only thing putting the directory into a fresh clone or e2e's copy —
      but none is a bind source or target, and nothing `mkdir -p`s them. Settle it against the
      upstream decree crate (not vendored in this checkout).
- [ ] `graveyard/lightrag/docker-compose.exist.yml:41` and
      `graveyard/vikunja/docker-compose.yml.example:55` still set the now-deleted
      `DECREE_SIDECAR=true`. Left alone per CLAUDE.md's "ignore `graveyard/`", but they will keep
      surfacing in greps for the old name.
- [ ] `e2e_fm_get` is stricter than the `grep` it replaced: `e2e:  true   ` (trailing whitespace)
      now matches neither `= true` nor `= false`, so such a quest would vanish from `--all` *and*
      from the picker's excluded list with no warning. No quest has it today; a `tr -d ' \r'`
      would close it.

## Done

Cleared in the e2e-simplification pass — `src/test/e2e/e2e.sh` 855 → 762 lines (−92), plus the
dead-mechanism deletions below.

- [x] Deleted the `e2e_requires` mechanism (`quest_requires`, `quest_requirements_met`, the
      `RUNNABLE`/`SKIP` triage) — a frontmatter key no quest declared.
- [x] Deleted `check_meta`; its awk body was byte-identical to `e2e_fm_get` in `results.sh`, which
      `e2e.sh` already sourced.
- [x] Collapsed the quest frontmatter readers onto `e2e_fm_get`. `quest_fm` survives only for
      `quest_vars`, since `services:` is a list rather than a scalar key.
- [x] `run_quest` calls `quest_name` instead of re-inlining it.
- [x] `cleanup` and the `up -d --build` step use the `_compose` helper.
- [x] Dropped the duplicate `sweep_leftover_workdirs` call (`preflight_check` → `e2e_down` already
      sweeps).
- [x] Stopped double-grading the stuck inbox; kept the copy-to-`stuck/` evidence, which the crash
      path still needs.
- [x] Deleted the no-fzf numbered-prompt picker — `src/quest.sh` already hard-fails without fzf.
- [x] Deleted the "typo or non-e2e quest?" rescan in `quests_by_names`.
- [x] Reworded `results.sh`'s header, which cited a `src/utils` convention from a directory it
      does not live in.
- [x] Deleted the dead `E2E_MODE` skip in `ai/ollama/exist.test.sh` — nothing set it, and e2e now
      pulls ollama's models by migration.
- [x] Removed the stale "EXIST_E2E_OLLAMA_URL still overrides all of them" claim in
      `src/test/fixtures/env.shared`.
- [x] Collapsed `DECREE_SIDECAR` into the pre-existing `DECREE_DAEMON` (the two were always set
      together, to the same value) — one line of config deleted rather than a variable renamed.
- [x] Deleted `services/decree/decree/{cron,inbox}/.gitkeep` — `exist.initial.sh` mkdirs the
      first, `generate-compose.ts`'s `ensureBindSource` creates the second.
- [x] Restored Caddy routing checks inside `decree`. Collapsing `DECREE_SIDECAR` into
      `DECREE_DAEMON` was wrong: the flag was only ever set on `decree-backup`, so the collapse
      silently turned `probe_caddy` into a no-op inside `decree` — which is where triage runs
      every service's test. Split back out as `DECREE_BACKUP`, set on the backup daemon only.
- [x] e2e now copies the **working tree** instead of `git archive HEAD`, so uncommitted work is
      what gets tested. Filtered by `git ls-files --cached --others --exclude-standard`, so git's
      own ignore rules keep secrets and rendered files out.
- [x] e2e now applies a quest's `copies:` block, so the clone gets the same migrations a real
      install does. Parsed from frontmatter with awk, since the host has no `yq`.
- [x] Registered/enabled the routines the shipped migrations name: `ollama-pull` was
      `enabled: false`, `minio-bucket` and `minio-service-account` were unlisted (= invisible).
      Every ollama and MinIO migration was a silent no-op, and because `decree process` halts at
      the first dead letter, migration 10's failure hid every one behind it. Affected real Core
      installs, not just e2e.
- [x] hermes' memory round-trip now skips when `EXIST_VRAM_GB=0` instead of failing. It makes two
      real ~20k-token inferences (~45s warm on a GPU); on CPU both curls burn their 120s and
      report "no response", which also blew triage's own 120s per-service cap. Added a `skip()`
      helper to `exist-test.sh` for this — the vocabulary was missing.
- [x] Cut the harness down: `e2e.sh` 833 -> 510, deleted the per-service tier (`00-services.md`)
      and the `TRIAGE_STRICT` knob that served it, the fzf picker and its fallback, the 60-line
      preflight collision negotiation, and `var_to_path`. e2e's remit is now one sentence: does a
      fresh install come up working? Per-service health is triage's job, continuously, on the
      real stack.
- [x] Consolidated onto ONE mechanism. The single remaining check is a decree **migration**
      (numbered `90-`, after the product's own), not an inbox message, so `drop_checks` +
      `await_checks` collapsed into one `await_migrations`. The "messages not migrations"
      rationale only held when there were several checks; with one, nothing can be hidden.
- [x] `file-processors.example/example.sh` now asserts its input is non-empty before processing.
      A processor that reports success over a file that never downloaded hides the broken half of
      the chain — and this is the file every user copies from.
- [x] e2e now takes a machine-wide lock (`/tmp/exist-e2e.lock`, fd 9 + flock, the same idiom as
      `openviking-index-dir.sh`). A second run — or an `e2e down` during one — refuses with a
      message instead of tearing the live run's stack down mid-flight. flock frees on process
      death, so a crash leaves no stale lock.
