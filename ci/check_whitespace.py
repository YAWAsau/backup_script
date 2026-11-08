"""Check every shipped source file in an isolated Git index, without staging user work."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repository', action='store_true', help='Check tracked repository files instead of the full source distribution')
    args = parser.parse_args()
    if args.repository:
        top = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=ROOT).decode().strip()).resolve()
        if top != ROOT.resolve():
            raise SystemExit('Repository check must run from its own Git checkout')
        names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
        names = sorted(n for n in names if n)
        if not names:
            raise SystemExit('No tracked repository files to check')
    else:
        names = json.loads((ROOT / 'source-package.json').read_text(encoding='utf-8'))['files']
        names = sorted(set(names + ['source-package.json']))
    missing = [name for name in names if not (ROOT / name).is_file()]
    if missing:
        raise SystemExit('Missing required files: ' + str(len(missing)) + '\n' + '\n'.join(missing))
    env = {k: v for k, v in os.environ.items() if k.upper() not in {
        'GIT_INDEX_FILE', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR',
        'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'}}
    with tempfile.TemporaryDirectory(prefix='speedbackup-whitespace-') as tmp:
        scratch = Path(tmp)
        git_dir = scratch / 'git'
        subprocess.run(['git', 'init', '--bare', '-q', str(git_dir)], check=True, env=env)
        paths = scratch / 'paths'
        paths.write_bytes(b''.join(n.encode('utf-8') + b'\0' for n in names))
        git = ['git', '--git-dir=' + str(git_dir), '--work-tree=' + str(ROOT),
               '-c', 'core.bare=false', '-c', 'core.autocrlf=false', '-c', 'core.longpaths=true']
        subprocess.run(git + ['add', '-f', '--pathspec-from-file=' + str(paths),
                              '--pathspec-file-nul'], check=True, cwd=ROOT, env=env)
        subprocess.run(git + ['-c', 'core.whitespace=-space-before-tab',
                              'diff', '--cached', '--check'], check=True, cwd=ROOT, env=env)
    print(f'Git whitespace check passed: {len(names)} source files; user index untouched')


if __name__ == '__main__':
    main()
