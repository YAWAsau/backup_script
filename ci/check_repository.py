#!/usr/bin/env python3
"""CI source/runtime integrity and packaging checks; never runs Android tools."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import tomllib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REQUIRED_TOOLS = {
    'busybox', 'classes.dex', 'cmd', 'dex_check.sh', 'find', 'jq',
    'keycheck', 'smbclient', 'speednative', 'tar', 'zstd',
}
TEXT_SUFFIXES = {'.sh', '.rs', '.java', '.kt', '.kts', '.ps1', '.toml', '.yml', '.yaml'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def runtime_table(script):
    blocks = list(re.finditer(r"(?m)^\s*cat <<'SB_TOOL_SHA_TABLE'\n(.*?)^SB_TOOL_SHA_TABLE$", script, re.S))
    require(len(blocks) == 1, 'Expected exactly one runtime SHA table')
    entries = {}
    for line in blocks[0].group(1).splitlines():
        match = re.fullmatch(r'([A-Za-z0-9_.-]+) ([0-9a-f]{64})', line)
        require(match is not None, f'Malformed runtime SHA row: {line!r}')
        name, digest = match.groups()
        require(name not in entries, f'Duplicate runtime SHA row: {name}')
        entries[name] = digest
    require(REQUIRED_TOOLS <= entries.keys(), 'Missing required runtime SHA rows')
    return entries


def verify_runtime(directory):
    script = (directory / 'tools.sh').read_bytes().decode('utf-8')
    require('\r' not in script, 'tools.sh must use LF')
    entries = runtime_table(script)
    for name, expected in entries.items():
        path = directory / name
        require(path.is_file() and not path.is_symlink(), f'Missing regular runtime file: {name}')
        actual = sha256(path.read_bytes())
        require(actual == expected, f'{name}: runtime SHA mismatch; expected {expected}, got {actual}')
    print(f'Runtime SHA: {len(entries)} files match')


def check_versions():
    config = ROOT / 'versions.properties'
    if not config.exists():
        print('Versions: existing legacy scheme (no versions.properties)')
        return
    values = {}
    for line in config.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        require(key not in values, f'Duplicate version key: {key}')
        require(re.fullmatch(r'v[1-9][0-9]{2}', value), f'Invalid version: {key}={value}')
        values[key] = value
    required = {'build', 'script', 'dex', 'cgfreezer', 'eventwait', 'filewatch',
                'netwatch', 'procwait', 'speedscan', 'uidexec', 'unixsock'}
    require(required == values.keys(), 'Missing or unknown component version keys')
    require((ROOT / 'VERSION').read_text().strip() == values['build'], 'VERSION differs from build')
    script = (ROOT / 'tools/tools.sh').read_text(encoding='utf-8')
    require(f'speedbackup_script_version="{values["script"]}"' in script, 'Script function version differs')
    if re.search(r'(?m)^speedbackup_patch_build=', script):
        require(f'speedbackup_patch_build="{values["build"]}"' in script, 'Script build version differs')
    for name in ('rust/build.rs', 'read_versions.ps1', 'sync_version.ps1', 'sync_artifacts.ps1', 'dex/release-version.properties'):
        require((ROOT / name).is_file(), f'Missing version build input: {name}')
    dex_versions = dict(line.split('=', 1) for line in
                        (ROOT / 'dex/release-version.properties').read_text(encoding='utf-8').splitlines()
                        if line.strip() and not line.lstrip().startswith('#'))
    require(dex_versions.get('version') == values['dex'] and
            dex_versions.get('build') == values['build'], 'Dex component/build version differs')
    self_check = (ROOT / 'tools/dex_check.sh').read_text(encoding='utf-8')
    require(f'DEX_CHECK_VERSION="{values["script"]}"' in self_check and
            f'DEX_CHECK_BUILD="{values["build"]}"' in self_check, 'Self-check component/build version differs')
    cargo = tomllib.loads((ROOT / 'rust/Cargo.toml').read_text(encoding='utf-8'))
    require(cargo['package']['version'] == f'{int(values["build"][1:])}.0.0', 'Cargo build version differs')
    print('Versions: centralized component metadata checked')


def check(shells=False):
    names = git('ls-files', '-z').decode('utf-8').rstrip('\0').split('\0')
    for name in ['start.sh', 'tools/tools.sh', 'tools/dex_check.sh', 'tools/soc.json',
                 'rust/Cargo.toml', 'rust/Cargo.lock', 'rust/src/main.rs', 'rust/build.ps1',
                 'dex/build_dex.ps1', 'dex/gradlew', 'dex/gradlew.bat',
                 'dex/gradle/wrapper/gradle-wrapper.jar', 'dex/gradle/wrapper/gradle-wrapper.properties']:
        require((ROOT / name).is_file(), f'Missing required file: {name}')
    for name in names:
        path = ROOT / name
        if path.suffix not in TEXT_SUFFIXES and name != 'dex/gradlew':
            continue
        data = path.read_bytes()
        require(not data.startswith(b'\xef\xbb\xbf'), f'Unexpected UTF-8 BOM: {name}')
        require(b'\r' not in data, f'Expected LF line endings: {name}')
        data.decode('utf-8')
    json.loads((ROOT / 'tools/soc.json').read_text(encoding='utf-8'))
    cargo = tomllib.loads((ROOT / 'rust/Cargo.toml').read_text(encoding='utf-8'))
    lock = tomllib.loads((ROOT / 'rust/Cargo.lock').read_text(encoding='utf-8'))
    packages = [p for p in lock['package'] if p['name'] == cargo['package']['name']]
    require(len(packages) == 1 and packages[0]['version'] == cargo['package']['version'], 'Cargo.lock package version differs')
    with zipfile.ZipFile(ROOT / 'dex/gradle/wrapper/gradle-wrapper.jar') as wrapper:
        require(wrapper.testzip() is None, 'Corrupt Gradle wrapper JAR')
        require('org/gradle/wrapper/GradleWrapperMain.class' in wrapper.namelist(), 'Missing wrapper entry point')
    wrapper_props = (ROOT / 'dex/gradle/wrapper/gradle-wrapper.properties').read_text(encoding='utf-8')
    require(re.search(r'(?m)^distributionSha256Sum=[0-9a-f]{64}$', wrapper_props),
            'Gradle distribution SHA256 must be pinned')
    verify_runtime(ROOT / 'tools')
    check_versions()
    if shells:
        for shell in ('bash', 'mksh'):
            require(shutil.which(shell), f'{shell} is not installed')
            for name in names:
                if name.endswith('.sh') or name == 'dex/gradlew':
                    subprocess.run([shell, '-n', str(ROOT / name)], cwd=ROOT, check=True)
        print('Shell syntax: Bash and mksh passed (scripts not executed)')
    print('Repository checks passed')


def package():
    dex = ROOT / 'dex/classes.dex'
    native = ROOT / 'rust/out/speednative'
    require(dex.is_file() and native.is_file(), 'Missing fresh build outputs')
    require(dex.read_bytes()[:4] == b'dex\n', 'Invalid Dex magic')
    elf = native.read_bytes()
    require(elf[:6] == b'\x7fELF\x02\x01' and struct.unpack_from('<H', elf, 18)[0] == 183,
            'Expected Android arm64 ELF64')
    # The Rust builder additionally checks PIE, 16 KiB segments and API28/r30 notes.
    native_info = json.loads((ROOT / 'rust/out/BUILD_INFO.json').read_text(encoding='utf-8-sig'))
    config = json.loads((ROOT / 'ci/toolchain.json').read_text(encoding='utf-8'))
    require(native_info['ndk'] == config['ndk'] and native_info['api'] == config['android_api'], 'Unexpected NDK/API build metadata')
    commit = git('rev-parse', 'HEAD').decode().strip()
    output = ROOT / 'ci-output'
    output.mkdir(exist_ok=True)
    prefix = f'SpeedBackup_{commit[:12]}'
    runtime_zip = output / f'{prefix}_CI_RUNTIME.zip'
    source_zip = output / f'{prefix}_SOURCE_SNAPSHOT.zip'
    with tempfile.TemporaryDirectory(prefix='speedbackup-ci-') as staging:
        stage = Path(staging)
        # Export tracked files only: exclude logs, machine configuration and build caches.
        tracked = git('ls-files', '-z').decode().rstrip('\0').split('\0')
        for name in tracked:
            if name.startswith('tools/') or name in ('start.sh', 'README.md', 'LICENSE'):
                dest = stage / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, dest)
        shutil.copyfile(dex, stage / 'tools/classes.dex')
        shutil.copyfile(native, stage / 'tools/speednative')
        script_path = stage / 'tools/tools.sh'
        script = script_path.read_text(encoding='utf-8')
        runtime_table(script)  # Reject malformed tables before changing generated entries.
        for name in ('classes.dex', 'speednative', 'dex_check.sh'):
            digest = sha256((stage / 'tools' / name).read_bytes())
            script, count = re.subn(rf'(?m)^{re.escape(name)} [0-9a-f]{{64}}$', f'{name} {digest}', script)
            require(count == 1, f'Missing/duplicate SHA row for {name}')
        script_path.write_text(script, encoding='utf-8', newline='\n')
        verify_runtime(stage / 'tools')
        artifact_hashes = {p.relative_to(stage).as_posix(): sha256(p.read_bytes()) for p in sorted(stage.rglob('*')) if p.is_file()}
        with zipfile.ZipFile(runtime_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name in artifact_hashes:
                archive.write(stage / name, name)
        with zipfile.ZipFile(runtime_zip) as archive:
            require(archive.testzip() is None, 'Runtime ZIP CRC failure')
            for name, digest in artifact_hashes.items():
                require(sha256(archive.read(name)) == digest, f'ZIP bytes differ: {name}')
    subprocess.run(['git', 'archive', '--format=zip', f'--output={source_zip}', commit], cwd=ROOT, check=True)
    info = {'commit': commit, 'toolchain': config, 'runtime_sha256': artifact_hashes,
            'android_runtime_tests': 'not executed; builds and static checks only',
            'source_snapshot': 'exact Git commit; prebuilt third-party tools retained; not a FULL_SOURCE package for all dependencies'}
    (output / 'BUILD_INFO.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    sums = ''.join(f'{sha256(p.read_bytes())}  {p.name}\n' for p in (runtime_zip, source_zip, output / 'BUILD_INFO.json'))
    (output / 'SHA256SUMS.txt').write_text(sums, encoding='ascii', newline='\n')
    print(f'Packaged {runtime_zip.name} and {source_zip.name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['check', 'package'])
    parser.add_argument('--shells', action='store_true')
    args = parser.parse_args()
    try:
        check(args.shells) if args.command == 'check' else package()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        print(f'CI ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
