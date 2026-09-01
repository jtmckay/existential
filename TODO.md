# TODO

A running cleanup backlog — things we know we want to delete or collapse, not a spec for anything
new. Items come off the list as they land; if an item stops being true, delete the line rather
than rewriting it.

## Open

- [ ] `DECREE_DAEMON` now carries two jobs. `automations/entrypoint.sh` reads it to decide whether
      to run the migration gate and `exec decree daemon`; `src/test/exist-test.sh:77,264,271` read
      it to mean "am I inside a decree container, where the enablement flags and Caddy are
      unreachable". Nothing sets it `false` today so behavior is identical, but a one-shot decree
      container would silently re-enable checks that cannot work there. If that ever matters, the
      test-side guard wants to be `IN_CONTAINER=1` — which is currently set on `decree-backup` but
      not on `decree`.
- [ ] Three `.gitkeep`s under `services/decree/` could not be positively justified *or* ruled out:
      `decree/migrations/`, `decree-backup/cron/`, `decree-backup/inbox/`. Each is gitignored, so
      the `.gitkeep` is the only thing putting the directory into a fresh clone or e2e's
      `git archive` — but none is a bind source or target, and nothing `mkdir -p`s them. Settle it
      against the upstream decree crate (not vendored in this checkout): if `decree` creates its
      own `migrations/`, `cron/` and `inbox/` at startup, all three can go.
- [ ] `graveyard/lightrag/docker-compose.exist.yml:41` and
      `graveyard/vikunja/docker-compose.yml.example:55` still set the now-deleted
      `DECREE_SIDECAR=true`. Left alone per CLAUDE.md's "ignore `graveyard/`", but they will keep
      surfacing in greps for the old name.

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
