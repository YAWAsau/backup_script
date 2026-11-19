#!/usr/bin/env python3
"""Run against retained real stale and rebuilt DEX artifacts."""
import argparse
import json
from pathlib import Path
from check_dex_apk import dex_strings, verify_dex_apk

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--metadata", type=Path, required=True)
    p.add_argument("--stale-dex", type=Path, required=True)
    p.add_argument("--current-dex", type=Path, required=True)
    a = p.parse_args()
    expected = json.loads(a.metadata.read_text())["apk_sha256"]
    # First establish that the stale fixture is readable, not merely corrupt.
    stale_strings = set(dex_strings(a.stale_dex.read_bytes()))
    if expected in stale_strings:
        raise ValueError("Stale fixture already contains current APK_SHA")
    verify_dex_apk(a.current_dex, expected)
    try:
        verify_dex_apk(a.stale_dex, expected)
    except ValueError as exc:
        if "compiled DEX APK_SHA differs" not in str(exc):
            raise
    else:
        raise AssertionError("Stale DEX accepted")
    print("Real rebuilt DEX passed; real stale DEX rejected")

if __name__ == "__main__":
    main()
