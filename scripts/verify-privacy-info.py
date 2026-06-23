#!/usr/bin/env python3
# verify-privacy-info.py
# Sprint 19 (2026-06-23): sanity check for the iOS app's Privacy Manifest.
#
# Validates:
#   1. PrivacyInfo.xcprivacy exists at the expected path
#   2. NSPrivacyTracking is explicitly set to false
#   3. NSPrivacyTrackingDomains is empty (no trackers)
#   4. NSPrivacyCollectedDataTypes is empty (no data collected)
#   5. All NSPrivacyAccessedAPITypes have at least one reason code
#   6. The plist parses as valid XML
#
# Run from the repo root:
#   python3 scripts/verify-privacy-info.py
#
# Exit code 0 on success, non-zero on any violation.

import os
import plistlib
import sys
from pathlib import Path

PRIVACY_INFO = "apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    privacy_path = repo_root / PRIVACY_INFO

    if not privacy_path.exists():
        fail(f"{PRIVACY_INFO} not found")

    print(f"Checking {PRIVACY_INFO}")

    try:
        with open(privacy_path, "rb") as f:
            data = plistlib.load(f)
    except Exception as exc:
        fail(f"{PRIVACY_INFO} is not a valid plist: {exc}")

    print("  [ok] valid plist")

    # NSPrivacyTracking must be false
    if data.get("NSPrivacyTracking") is not False:
        fail(
            f"NSPrivacyTracking must be 'false' (got: {data.get('NSPrivacyTracking')!r})"
        )
    print("  [ok] NSPrivacyTracking = false")

    # NSPrivacyTrackingDomains must be empty
    domains = data.get("NSPrivacyTrackingDomains", [])
    if len(domains) != 0:
        fail(f"NSPrivacyTrackingDomains must be empty (got {len(domains)} entries)")
    print("  [ok] NSPrivacyTrackingDomains is empty")

    # NSPrivacyCollectedDataTypes must be empty
    collected = data.get("NSPrivacyCollectedDataTypes", [])
    if len(collected) != 0:
        fail(
            f"NSPrivacyCollectedDataTypes must be empty "
            f"(got {len(collected)} entries). "
            f"See docs/app-store-privacy-labels.md for the canonical list of "
            f"categories we never collect."
        )
    print("  [ok] NSPrivacyCollectedDataTypes is empty")

    # NSPrivacyAccessedAPITypes must be non-empty
    accessed = data.get("NSPrivacyAccessedAPITypes", [])
    if len(accessed) == 0:
        fail("NSPrivacyAccessedAPITypes must list at least one API (iOS 17 requirement)")
    print(f"  [ok] NSPrivacyAccessedAPITypes has {len(accessed)} entries")

    # Every accessed-API entry must have a non-empty reasons array
    for i, api in enumerate(accessed):
        if not api.get("NSPrivacyAccessedAPIType"):
            fail(f"entry {i}: missing NSPrivacyAccessedAPIType")
        reasons = api.get("NSPrivacyAccessedAPITypeReasons", [])
        if len(reasons) == 0:
            fail(
                f"entry {i} ({api.get('NSPrivacyAccessedAPIType')}): "
                f"empty reasons array"
            )
    print("  [ok] every API entry has a non-empty reasons array")

    print()
    print("All checks passed. Loupe iOS app is ready for App Store Connect privacy labels.")


if __name__ == "__main__":
    main()
