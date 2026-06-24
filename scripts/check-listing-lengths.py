#!/usr/bin/env python3
# scripts/check-listing-lengths.py
#
# Verifies that every field in docs/app-store-listing-copy.md
# is within App Store Connect's length limit. Used in CI
# (the GitHub Actions workflow `ios-listing.yml`) and as a
# pre-submit hook on the author's machine.
#
# Exit code 0 on success, 1 on any field exceeding the limit.
#
# The reason this is a Python script and not a bash one is
# that App Store Connect's field length rules are quirky
# (e.g. a "subtitle" is a short phrase, not a paragraph)
# and the file format mixes headings, fenced code blocks
# and free-form descriptions. A real parser is more
# reliable than a `sed | wc -c` pipeline.

import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
LISTING = os.path.join(REPO_ROOT, "docs", "app-store-listing-copy.md")

# Limits — must match the table in app-store-listing-copy.md.
LIMITS = {
    "Name": 30,
    "Subtitle": 30,
    "Promotional Text": 170,
    "Description": 4000,
    "What's New in this Version": 4000,
    "Keywords": 100,
}

# Locales we ship.
LOCALES = ["en-US", "de-DE", "fr-FR", "es-ES"]


def main() -> int:
    if not os.path.exists(LISTING):
        print(f"FAIL: listing file not found: {LISTING}", file=sys.stderr)
        return 1

    with open(LISTING, "r", encoding="utf-8") as f:
        text = f.read()

    # Split the file into per-locale blocks. Each block starts
    # with `## Locale: <id>` and ends at the next `## Locale:`
    # header (or end of file).
    blocks = re.split(r"^## Locale: ", text, flags=re.M)
    # blocks[0] is the preamble.
    per_locale = {}
    for block in blocks[1:]:
        head, _, body = block.partition("\n")
        locale = head.strip()
        per_locale[locale] = body

    failures = []
    totals = {locale: 0 for locale in LOCALES}

    for locale in LOCALES:
        if locale not in per_locale:
            print(f"  ✗ locale block missing: {locale}", file=sys.stderr)
            failures.append((locale, "missing", 0, 0))
            continue
        body = per_locale[locale]
        for field, limit in LIMITS.items():
            # The field body is the fenced code block
            # (```...```) immediately after the field header.
            # The header is e.g. `### Name (≤ 30 chars)`; we
            # skip it by looking for the first ``` fence after
            # it. The fenced block is the canonical store for
            # the value in this file.
            header_re = re.escape(f"### {field}") + r".*?\n"
            m = re.search(
                header_re + r"```[a-zA-Z]*\n(.*?)\n```",
                body,
                flags=re.S,
            )
            if not m:
                print(f"  ✗ field not found: {locale} / {field}", file=sys.stderr)
                failures.append((locale, field, 0, limit))
                continue
            body_text = m.group(1).rstrip()
            size = len(body_text.encode("utf-8"))
            totals[locale] += 1
            status = "✓" if size <= limit else "✗"
            print(f"  {status} {locale:6s} {field:30s} {size:4d} / {limit}")
            if size > limit:
                failures.append((locale, field, size, limit))

    # Summary table.
    print()
    print("Per-locale field count:")
    for locale in LOCALES:
        print(f"  {locale:6s} {totals[locale]} / {len(LIMITS)} fields ok")

    if failures:
        print()
        print(f"FAIL: {len(failures)} field(s) over limit", file=sys.stderr)
        for locale, field, size, limit in failures:
            print(f"  - {locale} / {field}: {size} > {limit}", file=sys.stderr)
        return 1

    print()
    print("OK: all listing fields are within App Store Connect limits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
