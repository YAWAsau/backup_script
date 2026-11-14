#!/usr/bin/env python3
"""Check publication ordering against the previous repository ZIP (no writes)."""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def versions(text):
    return dict(line.split('=', 1) for line in text.splitlines()
                if line.strip() and not line.startswith('#'))
def stamp(text):
    found = re.search(r'^backup_version="([0-9]{12})"$', text, re.M)
    if not found:
        raise SystemExit('Missing updater timestamp')
    return int(found[1])
with zipfile.ZipFile(sys.argv[1]) as previous:
    old = versions(previous.read('versions.properties').decode())
    new = versions((root / 'versions.properties').read_text())
    if int(new['build'][1:]) <= int(old['build'][1:]):
        raise SystemExit('Published build version must increase')
    if stamp((root / 'tools/tools.sh').read_text(encoding='utf-8')) <= stamp(previous.read('tools/tools.sh').decode()):
        raise SystemExit('Published updater timestamp must increase')
    for key in old:
        if key not in new:
            raise SystemExit(f'Component key removed in new version: {key}')
        if int(new[key][1:]) < int(old[key][1:]):
            raise SystemExit(f'Component version regressed: {key}')
print('Release ordering checks passed')
