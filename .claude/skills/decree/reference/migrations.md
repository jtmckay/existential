# Migrations Reference

## Format

Migration files are Markdown with YAML frontmatter:

```markdown
---
routine: develop
---

# Migration Title

Brief description of what this migration implements.

## Acceptance Criteria

- **Given** <precondition>
  **When** <action>
  **Then** <expected, verifiable result>
```

The `routine:` field is **required** — always set it explicitly even when a default is configured.

## Placement

New migration files belong in `.decree/migrations/`. Choose the next available numeric
prefix to maintain ordering. Never place them in `.decree/processed.md` or elsewhere.

## Acceptance Criteria

Use Given / When / Then. Each criterion must be automatable:

- **Given** — the precondition or initial state
- **When** — the action or trigger
- **Then** — observable outcome: exit codes, file contents, stdout, HTTP responses, database state

Avoid vague outcomes like "works correctly".

## Sizing — One Concern at a Time

Keep migrations **day-sized**: implementable in a single AI context window, completable in
one session, independently reviewable. Split work into the smallest feasible logical chunks.

Smaller migrations:
- Reduce partial-failure risk — a failed migration can be retried without undoing unrelated work
- Keep the AI's focus narrow enough to produce correct, reviewable output
- Produce cleaner commit history and review artifacts

Think of them like developer tickets: one focused ticket per engineer per day.

## Immutability Rule

Never edit a processed migration. If a processed migration needs correction:

1. Create a new migration with the next available numeric prefix
2. Describe what it fixes and why the previous one was insufficient
3. The new migration supersedes the old one; both remain in the repository
