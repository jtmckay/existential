#!/usr/bin/env python3
"""check-drift.py — compare every *.example to its rendered counterpart and
report what re-rendering would change, ignoring placeholder substitution.

Semantic: "if I re-ran ./existential.sh --force, but with the existing user
inputs preserved (EXIST_CLI values, generated passwords/keys, etc.), what
would actually differ?" Anything else is real drift you should reconcile.

On-demand only: invoked via `./existential.sh validate`. NOT part of the
default test suite.

Lines in the .example containing any EXIST_* placeholder are skipped from
the comparison entirely — their rendered counterparts would be whatever the
user entered or whatever was generated, so comparing them is just noise.
When the placeholder line has a key (KEY=VAL or `key: val`), the matching
line in the rendered file is dropped too so the diff stays aligned.

Each remaining diff line is classified:
  + line present in .example, missing or different in rendered  (upstream new)
  - line present in rendered, missing from .example             (local custom)
  ~ value differs at the same line position                      (manual edit)
"""

from __future__ import annotations

import difflib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

SKIP_DIRS = {"graveyard", "node_modules", ".git", "site"}

# Match a placeholder anywhere in a line.
PLACEHOLDER_RE = re.compile(
    r"(EXIST_24_CHAR_PASSWORD|EXIST_32_CHAR_HEX_KEY|EXIST_64_CHAR_HEX_KEY"
    r"|EXIST_TIMESTAMP|EXIST_UUID|EXIST_CLI|EXIST_DEFAULT_[A-Z0-9_]+)"
)

# Extract the key (LHS) of an env-style or YAML-style assignment.
ENV_KEY_RE = re.compile(r"^([A-Z_][A-Z0-9_]*)=")
YAML_KEY_RE = re.compile(r"^\s*([\w.-]+):\s*\S")


@dataclass
class DriftReport:
    file: Path
    rendered_missing: bool = False
    upstream_lines: list[tuple[int, str]] = field(default_factory=list)
    local_lines: list[tuple[int, str]] = field(default_factory=list)
    changed: list[tuple[int, str, str]] = field(default_factory=list)

    def has_drift(self) -> bool:
        if self.rendered_missing:
            return False
        return bool(self.upstream_lines or self.local_lines or self.changed)


def line_key(raw: str) -> str | None:
    """Return the LHS variable name for an assignment line, or None."""
    if m := ENV_KEY_RE.match(raw):
        return m.group(1)
    if m := YAML_KEY_RE.match(raw):
        return m.group(1)
    return None


def strip_placeholder_lines(
    example_lines: list[str],
    rendered_lines: list[str],
) -> tuple[list[str], list[int], list[str], list[int]]:
    """Drop placeholder-bearing lines from example, and drop same-keyed lines
    from rendered. Return (kept_lines, original_line_numbers) for each side.
    Line numbers are 1-based."""
    skip_keys: set[str] = set()
    example_kept: list[str] = []
    example_orig: list[int] = []
    for i, ln in enumerate(example_lines, start=1):
        if PLACEHOLDER_RE.search(ln):
            if k := line_key(ln):
                skip_keys.add(k)
            continue
        example_kept.append(ln)
        example_orig.append(i)

    rendered_kept: list[str] = []
    rendered_orig: list[int] = []
    for j, ln in enumerate(rendered_lines, start=1):
        if (k := line_key(ln)) and k in skip_keys:
            continue
        rendered_kept.append(ln)
        rendered_orig.append(j)

    return example_kept, example_orig, rendered_kept, rendered_orig


def compute_drift(example_path: Path, rendered_path: Path) -> DriftReport:
    report = DriftReport(file=example_path)
    if not rendered_path.exists():
        report.rendered_missing = True
        return report

    example_lines = example_path.read_text().splitlines()
    rendered_lines = rendered_path.read_text().splitlines()

    ex_kept, ex_orig, rn_kept, rn_orig = strip_placeholder_lines(
        example_lines, rendered_lines
    )

    matcher = difflib.SequenceMatcher(None, ex_kept, rn_kept)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        if tag == "replace":
            for offset in range(max(i2 - i1, j2 - j1)):
                has_ex = i1 + offset < i2
                has_rn = j1 + offset < j2
                if has_ex and has_rn:
                    report.changed.append(
                        (ex_orig[i1 + offset], ex_kept[i1 + offset], rn_kept[j1 + offset])
                    )
                elif has_ex:
                    report.upstream_lines.append(
                        (ex_orig[i1 + offset], ex_kept[i1 + offset])
                    )
                else:
                    report.local_lines.append(
                        (rn_orig[j1 + offset], rn_kept[j1 + offset])
                    )
        elif tag == "delete":
            for idx in range(i1, i2):
                report.upstream_lines.append((ex_orig[idx], ex_kept[idx]))
        elif tag == "insert":
            for idx in range(j1, j2):
                report.local_lines.append((rn_orig[idx], rn_kept[idx]))
    return report


def find_examples() -> list[Path]:
    examples: list[Path] = []
    for p in REPO_ROOT.rglob("*.example"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        examples.append(p)
    return sorted(examples)


def main() -> int:
    examples = find_examples()

    drift_count = 0
    missing_count = 0

    for example in examples:
        rendered = example.parent / example.name[: -len(".example")]
        report = compute_drift(example, rendered)

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
    print()
    print("Lines containing EXIST_* placeholders in .example are skipped — their")
    print("rendered counterparts are user-supplied or generated, so comparing them")
    print("would always report drift.")

    return 1 if drift_count else 0


if __name__ == "__main__":
    sys.exit(main())
