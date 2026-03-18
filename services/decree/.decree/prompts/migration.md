# Migration Template

Each migration is a self-contained unit of work. Migrations are immutable —
once created, they are processed exactly once and never modified.

## Format

    ---
    routine: develop
    ---
    # NN: Title

    ## Overview
    Brief description of what this migration accomplishes.

    ## Requirements
    Detailed technical requirements.

    ## Files to Modify
    - path/to/file.rs — description of changes

    ## Acceptance Criteria
    Write acceptance criteria as BDD-style Given / When / Then statements.

## Acceptance Criteria Guidelines

- One behaviour per criterion — if you need "And" more than once, split
  into separate criteria.
- **Given** sets up state: configuration, data, environment. Be specific
  enough that a test can reproduce it.
- **When** is a single action: a command invocation, a function call, a
  user interaction.
- **Then** is an assertion: what changed, what was produced, what was
  returned. Must be objectively verifiable — no "should work correctly".
- Cover the happy path, key error cases, and edge cases.

### Example

- **Given** a project with no `.decree/` directory
  **When** the user runs `decree init`
  **Then** `.decree/` is created with all expected subdirectories

- **Given** `decree init` has already been run in this directory
  **When** the user runs `decree init` again
  **Then** existing files are not overwritten and a warning is printed

## Rules

- **Naming**: `NN-descriptive-name.md` (e.g., `01-add-auth.md`)
- **Frontmatter**: Optional YAML with `routine:` field (defaults to develop)
- **Ordering**: Alphabetical by filename determines execution order
- **Immutability**: Never edit a processed migration — create a new one
- **Self-contained**: Each migration should be independently implementable
- **Day-sized**: Each migration should be completable in one day or less
- **Testable**: Every acceptance criterion must be verifiable by an automated test

## Existing Migrations

{migrations}

## Processed

{processed}
