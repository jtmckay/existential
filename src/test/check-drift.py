#!/usr/bin/env python3
"""check-drift.py — compare every *.example to its rendered counterpart and
report what re-rendering would change, ignoring placeholder substitution.

Semantic: "if I re-ran ./existential.sh --force, but with the existing user
inputs preserved (EXIST_CLI values, generated passwords/keys, etc.), what
would actually differ?" Anything else is real drift you should reconcile.

On-demand only: invoked via `./existential.sh validate`. NOT part of the
default test suite.

Each diff line is classified:
  + line present in .example, missing or different in rendered  (upstream new)
  - line present in rendered, missing from .example             (local custom)
  ~ value differs and isn't explained by placeholder reuse      (manual edit)
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ENV_EXIST = REPO_ROOT / ".env.exist"

SKIP_DIRS = {"graveyard", "node_modules", ".git", "site"}

# Match a placeholder anywhere in a line.
PLACEHOLDER_RE = re.compile(
    r"(EXIST_24_CHAR_PASSWORD|EXIST_32_CHAR_HEX_KEY|EXIST_64_CHAR_HEX_KEY"
    r"|EXIST_TIMESTAMP|EXIST_UUID|EXIST_CLI|EXIST_DEFAULT_[A-Z0-9_]+)"
)

# Extract the key (LHS) of an env-style or YAML-style assignment.
ENV_KEY_RE = re.compile(r"^([A-Z_][A-Z0-9_]*)=")
YAML_KEY_RE = re.compile(r"^\s*([\w.-]+):\s*\S")

PLACEHOLDER_NAMES = {
    "EXIST_24_CHAR_PASSWORD",
    "EXIST_32_CHAR_HEX_KEY",
    "EXIST_64_CHAR_HEX_KEY",
    "EXIST_TIMESTAMP",
    "EXIST_UUID",
    "EXIST_CLI",
}


@dataclass
class DriftReport:
    file: Path
    rendered_missing: bool = False
    upstream_lines: list[tuple[int, str]] = None  # in .example, not in rendered
    local_lines: list[tuple[int, str]] = None     # in rendered, not in .example
    changed: list[tuple[int, str, str]] = None    # (line, example, rendered)

    def __post_init__(self):
        self.upstream_lines = self.upstream_lines or []
        self.local_lines = self.local_lines or []
        self.changed = self.changed or []

    def has_drift(self) -> bool:
        if self.rendered_missing:
            return False
        return bool(self.upstream_lines or self.local_lines or self.changed)


def load_env_file(path: Path) -> dict[str, str]:
    """Parse KEY=VALUE pairs from a dotenv-style file. Comments / blanks ignored."""
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        # Strip inline comments — anything after ` #`.
        value = value.split(" #", 1)[0].rstrip()
        out[key] = value
    return out


def extract_rendered_values(path: Path) -> dict[str, str]:
    """Best-effort: pull KEY=VALUE and `key: value` pairs from rendered file."""
    out: dict[str, str] = {}
    if not path.exists():
        return out
    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError):
        return out
    for raw in text.splitlines():
        if raw.lstrip().startswith("#"):
            continue
        # env-style
        if m := ENV_KEY_RE.match(raw):
            key = m.group(1)
            value = raw[m.end():].split(" #", 1)[0].rstrip()
            out.setdefault(key, value)
            continue
        # yaml-style — only set the FIRST occurrence (avoid clobbering on
        # nested keys with the same name).
        if m := YAML_KEY_RE.match(raw):
            key = m.group(1)
            value = raw[m.end()-1:].strip().split(" #", 1)[0].rstrip()
            out.setdefault(key, value)
    return out


def line_key(raw: str) -> str | None:
    """Return the LHS variable name for an assignment line, or None."""
    if m := ENV_KEY_RE.match(raw):
        return m.group(1)
    if m := YAML_KEY_RE.match(raw):
        return m.group(1)
    return None


def substitute_placeholders(
    example_line: str,
    rendered_values: dict[str, str],
    env_exist: dict[str, str],
) -> str:
    """Render a single .example line by replacing placeholders.

    EXIST_DEFAULT_X      → env_exist[X]
    Other EXIST_* tokens → rendered_values[<key on this line>] if available;
                           otherwise leave the placeholder in place.

    Placeholders are only substituted on the RHS of `=` / `:` assignments —
    the LHS may legitimately BE an EXIST_DEFAULT_X variable name and must not
    be clobbered. Lines outside that pattern (comments, freeform) substitute
    everywhere.
    """
    # Split the line into LHS / RHS at the first assignment delimiter.
    # We treat both env-style (KEY=VAL) and yaml-style (key: val) the same.
    if (m := ENV_KEY_RE.match(example_line)):
        prefix = example_line[: m.end()]                  # "KEY="
        body = example_line[m.end():]
    elif (m := YAML_KEY_RE.match(example_line)):
        # YAML_KEY_RE consumes up to the first non-space after the colon — back off.
        # Find the colon position and split there + 1.
        colon = example_line.index(":")
        prefix = example_line[: colon + 1]
        body = example_line[colon + 1:]
    else:
        prefix = ""
        body = example_line

    line_key_str = line_key(example_line)

    def repl(match: re.Match) -> str:
        token = match.group(1)
        if token.startswith("EXIST_DEFAULT_"):
            return env_exist.get(token, token)
        if line_key_str and line_key_str in rendered_values:
            return rendered_values[line_key_str]
        return token

    return prefix + PLACEHOLDER_RE.sub(repl, body)


def compute_drift(
    example_path: Path,
    rendered_path: Path,
    env_exist: dict[str, str],
) -> DriftReport:
    report = DriftReport(file=example_path)
    if not rendered_path.exists():
        report.rendered_missing = True
        return report

    rendered_values = extract_rendered_values(rendered_path)
    example_lines = example_path.read_text().splitlines()
    rendered_lines = rendered_path.read_text().splitlines()

    # Render the example with placeholders resolved.
    expected_lines = [
        substitute_placeholders(ln, rendered_values, env_exist)
        for ln in example_lines
    ]

    # Diff via simple difflib SequenceMatcher.
    import difflib
    matcher = difflib.SequenceMatcher(None, expected_lines, rendered_lines)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if tag == "replace":
            for offset in range(max(i2 - i1, j2 - j1)):
                ex = expected_lines[i1 + offset] if i1 + offset < i2 else ""
                rn = rendered_lines[j1 + offset] if j1 + offset < j2 else ""
                if ex and rn:
                    report.changed.append((i1 + offset + 1, ex, rn))
                elif ex:
                    report.upstream_lines.append((i1 + offset + 1, ex))
                else:
                    report.local_lines.append((j1 + offset + 1, rn))
        elif tag == "delete":
            # In expected but not rendered → upstream is ahead
            for idx in range(i1, i2):
                report.upstream_lines.append((idx + 1, expected_lines[idx]))
        elif tag == "insert":
            for idx in range(j1, j2):
                report.local_lines.append((idx + 1, rendered_lines[idx]))
    return report


def find_examples() -> list[Path]:
    examples: list[Path] = []
    for p in REPO_ROOT.rglob("*.example"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        examples.append(p)
    return sorted(examples)


def main() -> int:
    env_exist = load_env_file(ENV_EXIST)
    examples = find_examples()

    drift_count = 0
    missing_count = 0

    for example in examples:
        rendered = example.with_suffix("") if example.suffix == ".example" else None
        # `.example` is a *suffix* on the filename, not a Python suffix. Strip manually.
        rendered = example.parent / example.name[: -len(".example")]
        report = compute_drift(example, rendered, env_exist)

        if report.rendered_missing:
            missing_count += 1
            continue
        if not report.has_drift():
            continue

        drift_count += 1
        rel = example.relative_to(REPO_ROOT)
        print(f"\n{rel}:")
        for lineno, content in report.upstream_lines:
            print(f"  + L{lineno}  {content[:120]}")
        for lineno, content in report.local_lines:
            print(f"  - L{lineno}  {content[:120]}")
        for lineno, ex, rn in report.changed:
            print(f"  ~ L{lineno}")
            print(f"      example : {ex[:118]}")
            print(f"      rendered: {rn[:118]}")

    print()
    print(f"Examined:    {len(examples)} .example files")
    print(f"Not rendered: {missing_count}  (no counterpart on disk — nothing to compare)")
    print(f"Drifted:     {drift_count}")
    print()
    print("Legend:")
    print("  + = present in .example, missing/different in rendered  (upstream is ahead)")
    print("  - = present in rendered, not in .example                (local customization)")
    print("  ~ = both have a line at this position but they differ   (manual edit / stale)")

    # Exit non-zero only if there's drift, so this can fail CI on demand.
    return 1 if drift_count else 0


if __name__ == "__main__":
    sys.exit(main())
