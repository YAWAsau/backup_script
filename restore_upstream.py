"""Restore the exact separately distributed upstream snapshots; no network access."""
import argparse
import hashlib
import json
import subprocess
import re
import os
from pathlib import Path, PurePosixPath
import zipfile

ROOT = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def target(name):
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts or '\\' in name or ':' in name or rel.as_posix() != name:
        raise ValueError('Invalid source path: ' + name)
    path = ROOT / name
    if not path.resolve().is_relative_to(ROOT):
        raise ValueError('Path escapes repository: ' + name)
    for node in (path, *path.parents):
        if node == ROOT:
            break
        if node.is_symlink() or (hasattr(node, 'is_junction') and node.is_junction()):
            raise ValueError('Linked path: ' + name)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, nargs='?')
    parser.add_argument('--github-repo', help='Find the pinned asset among this owner/repo Releases using gh')
    parser.add_argument('--check', action='store_true', help='Verify restored files without downloading')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'upstream-sources.json').read_text(encoding='utf8'))
    if args.check:
        for name, expected in manifest['files'].items():
            path = target(name)
            if not path.is_file() or sha(path.read_bytes()) != expected:
                raise ValueError('Upstream missing or changed: ' + name + '; run restore_upstream.py <archive.zip> first')
        print('All upstream files verified.')
        return
    if args.archive is None:
        if not args.github_repo or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.github_repo):
            parser.error('Provide an archive path or --github-repo owner/repo')
        filename = manifest['archive']
        if Path(filename).name != filename or '/' in filename or '\\' in filename:
            raise ValueError('Invalid archive filename')
        directory = ROOT / 'ci-output' / 'upstream'
        directory.mkdir(parents=True, exist_ok=True)
        args.archive = directory / filename
        if not args.archive.exists():
            repositories = list(dict.fromkeys([args.github_repo, manifest.get('archive_repository', args.github_repo)]))
            for repository in repositories:
                if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
                    raise ValueError('Invalid upstream repository')
                pages = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
                    'repos/' + repository + '/releases?per_page=100'], text=True, encoding='utf8'))
                release = next((release for page in pages for release in page
                    if any(asset['name'] == filename for asset in release['assets'])), None)
                if release is not None:
                    subprocess.run(['gh', 'release', 'download', release['tag_name'], '--repo', repository,
                        '--pattern', filename, '--dir', str(directory)], check=True)
                    break
            else:
                raise ValueError('Upload ' + filename + ' to a Release in ' + ' or '.join(repositories) + ' before running CI')
    if sha(args.archive.read_bytes()) != manifest['archive_sha256']:
        raise ValueError('Wrong upstream archive SHA256; expected ' + manifest['archive'])
    files = manifest['files']
    with zipfile.ZipFile(args.archive) as archive:
        if len(archive.namelist()) != len(files) or set(archive.namelist()) != set(files):
            raise ValueError('Upstream archive file list mismatch')
        # Validate every file and existing destination before writing any file.
        for name, expected in files.items():
            path = target(name)
            if sha(archive.read(name)) != expected:
                raise ValueError('Source hash mismatch: ' + name)
            if path.exists() and (not path.is_file() or sha(path.read_bytes()) != expected):
                raise ValueError('Refusing to overwrite modified source: ' + name)
        for name in files:
            path = target(name)
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(name))
            if os.name != 'nt':
                mode = archive.getinfo(name).external_attr >> 16
                path.chmod(0o755 if mode & 0o111 else 0o644)
    print(f'Restored and verified {len(files)} upstream files.')


if __name__ == '__main__':
    main()
