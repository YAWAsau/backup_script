"""Reject stale shell-source selftest assertions before a runtime ZIP is shipped.

Runtime capability and fixture tests remain authoritative on Android. This check
evaluates the source-only grep predicates against the source actually packaged,
so moving implementation to Rust cannot silently leave a stale runtime predicate.
"""
from pathlib import Path
import re
import shlex

ROOT = Path(__file__).resolve().parents[1]
GREP = re.compile(r'''grep\s+(?P<flags>(?:-[A-Za-z]+\s+|--\s+)*)(?P<pattern>'[^']*'|"(?:\\.|[^"\\])*")\s+"\$_tools_self"''')


def check_source_predicates(checker, tools):
    count = 0
    for number, line in enumerate(checker.splitlines(), 1):
        if line.lstrip().startswith('#') or 'grep' not in line or '"$_tools_self"' not in line:
            continue
        if line.lstrip().startswith('&& ! sed -n '):
            # This one predicate is scoped to a function rather than the whole file.
            if "'/^_sb_file_has_exact_line() {/,/^}/p'" not in line or 'grep -F "grep -Fqx"' not in line:
                raise ValueError(f'Unsupported scoped source predicate at {number}')
            body = re.search(r'^_sb_file_has_exact_line\(\) \{\n.*?^}', tools, re.M | re.S)
            if not body or 'grep -Fqx' in body.group():
                raise ValueError(f'Stale exact-line hot-path selftest at {number}')
            count += 1
            continue
        matches = list(GREP.finditer(line))
        if not matches or len(matches) != line.count('"$_tools_self"') - (1 if '[ -f "$_tools_self" ]' in line else 0):
            raise ValueError(f'Unsupported source predicate at {number}: {line}')
        for match in matches:
            pattern = shlex.split(match['pattern'])[0].replace('\\$', '$')
            fixed = 'F' in match['flags']
            # Current BRE predicates contain no BRE operators differing from Python.
            # Fail explicitly if a later change requires a richer grep interpreter.
            if not fixed and any(c in pattern for c in r'\[](){}+?|^$'):
                raise ValueError(f'Unsupported BRE source predicate at {number}: {pattern}')
            present = pattern in tools if fixed else re.search(pattern, tools) is not None
            negative = re.search(r'!\s*$', line[:match.start()]) is not None
            if present == negative:
                raise ValueError(f'Stale selftest source predicate at {number}: {pattern!r} (negative={negative})')
            count += 1
    if not count:
        raise ValueError('No source selftest predicates found')
    return count


if __name__ == '__main__':
    checker = (ROOT/'tools/dex_check.sh').read_text(encoding='utf-8')
    tools = (ROOT/'tools/tools.sh').read_text(encoding='utf-8')
    count = check_source_predicates(checker, tools)
    print(f'Selftest source predicates: {count} checked against packaged Shell source')
    rust = (ROOT/'rust/src/bin/speedscan.rs').read_text(encoding='utf-8')
    branch = re.search(r'^(?P<indent>[ \t]*)(?:Some\("--capabilities"\) \| )?Some\("capabilities"\) => \{(?P<body>.*?)^\1\}', rust, re.M | re.S)
    if not branch:
        raise ValueError('Missing speedscan capability declaration branch')
    declared = set(re.findall(r'speedscan\.[a-zA-Z0-9_.]+', branch.group('body')))
    required = set(re.findall(r'"\$_ss_caps" \| grep -Fx "([^"]+)"', checker))
    runtime = re.search(r'^SPEEDBACKUP_SPEEDSCAN_REQUIRED_CAPS="([^"]+)"', tools, re.M)
    if not required or not runtime:
        raise ValueError('Missing selftest/runtime capability requirements')
    missing = (required | set(runtime.group(1).split())) - declared
    if missing:
        raise ValueError(f'Stale speedscan capability requirements: {sorted(missing)}')
    print(f'Speedscan selftest: {len(required)} required capabilities match Rust declarations')
