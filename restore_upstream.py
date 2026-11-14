"""Verify bundled upstream sources locally; legacy filename retained for build compatibility."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify bundled files; no download or extraction')
    parser.parse_args()
    manifest = json.loads((ROOT / 'upstream-sources.json').read_text(encoding='utf-8'))
    for name, expected in manifest['files'].items():
        relative = PurePosixPath(name)
        path = ROOT / name
        if relative.is_absolute() or '..' in relative.parts or not path.resolve().is_relative_to(ROOT):
            raise ValueError('Invalid bundled source path: ' + name)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Bundled upstream missing or changed: ' + name + '; use the complete project checkout')
    print(f"Bundled upstream verified: {len(manifest['files'])} files; no download needed.")

if __name__ == '__main__':
    main()
