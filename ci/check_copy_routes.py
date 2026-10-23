"""Conservative source inventory for direct shell cp calls; no runtime hook."""
import collections
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = {'private-copy', 'fresh-stage', 'preserve-metadata', 'retained-existing'}


def scan(root):
    rows = collections.Counter()
    # Product entry scripts and runtime scripts, including newly added files.
    paths = set(root.glob('*.sh')) | set((root / 'tools').rglob('*.sh'))
    for path in sorted(paths):
        context = '<top-level>'
        for line in path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            match = re.match(r'(?:function\s+)?([A-Za-z_][A-Za-z_0-9]*)\s*\(\s*\)\s*\{', line)
            if match:
                context = match.group(1)
            # Deliberately conservative: quoted commands count too. This is
            # a review tripwire, not a full shell parser or a security boundary.
            if re.search(r'(?<![A-Za-z0-9_])cp(?![A-Za-z0-9_])', line):
                rows[(path.relative_to(root).as_posix(), context, line)] += 1
    return rows


def check(root=ROOT):
    data = json.loads((root / 'ci/copy_routes.json').read_text(encoding='utf-8'))
    if data.get('schema') != 1:
        raise ValueError('Unsupported copy route schema')
    expected = collections.Counter()
    for row in data['routes']:
        key = (row['file'], row['context'], row['line'])
        if key in expected or row['category'] not in CATEGORIES:
            raise ValueError(f'Duplicate or unclassified copy route: {key}')
        if not isinstance(row['reason'], str) or len(row['reason'].strip()) < 20:
            raise ValueError(f'Copy route needs a concrete review reason: {key}')
        if type(row['count']) is not int or row['count'] < 1:
            raise ValueError(f'Invalid copy route count: {key}')
        expected[key] = row['count']
    actual = scan(root)
    added, removed = actual - expected, expected - actual
    if added or removed:
        details = '\n'.join(f'{kind} x{count}: {key}' for kind, rows in
                            [('NEW/CHANGED', added), ('STALE', removed)]
                            for key, count in sorted(rows.items()))
        raise ValueError('Copy routes require review; use _generated_file_publish for generated-file overwrite. '
                         'Do not copy template reasons: describe the concrete destination and why cp semantics are needed.\n' + details)
    print(f'Copy route inventory: {sum(actual.values())} source lines match')


if __name__ == '__main__':
    check()
