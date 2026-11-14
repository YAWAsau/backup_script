"""Build the offline Rust catalogue from resolved Maven metadata and pinned references.

Refresh: export Gradle coordinates/POM paths with export_licenses.gradle, then
run this script --import-metadata WEBVIEW_JSON DEX_JSON. POM files remain in the
local Gradle cache; no machine paths are included in the distributable catalogue.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'third_party/licenses'
OUTPUT = ROOT / 'rust/src/open_source_licenses.json'
INPUTS = ['webview/app/build.gradle.kts', 'dex/app/build.gradle.kts',
          'dex/hiddenapi/build.gradle.kts', 'dex/gradle/libs.versions.toml',
          'rust/Cargo.toml', 'rust/Cargo.lock']
NS = {'m': 'http://maven.apache.org/POM/4.0.0'}

def hashes():
    return {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in INPUTS}

def secure_url(value):
    value = value.strip().replace('http://', 'https://', 1)
    u = urlsplit(value)
    if u.scheme != 'https' or not u.hostname or u.username or u.password:
        raise ValueError('Invalid project URL: ' + value)
    return value

def import_metadata(paths):
    records = {}
    overrides = {
        # JitPack core POM omits attribution; verified against libsu tag 6.0.0 LICENSE.
        'com.github.topjohnwu.libsu': ('https://github.com/topjohnwu/libsu', 'Apache-2.0', 'John Wu'),
        'com.google.guava': ('https://github.com/google/guava', 'Apache-2.0', 'Google'),
        'com.google.code.gson': ('https://github.com/google/gson', 'Apache-2.0', 'Google'),
        'com.google.errorprone': ('https://github.com/google/error-prone', 'Apache-2.0', 'Google'),
    }
    for component, path in zip(['APK／WebUI', 'Dex'], paths):
        for row in json.loads(Path(path).read_text(encoding='utf-8')):
            coordinate = ':'.join(row[k] for k in ['group', 'name', 'version'])
            scope = component + ('（編譯時）' if 'Runtime' not in row['configuration'] else '')
            if coordinate in records:
                records[coordinate]['components'].add(scope)
                continue
            pom = ET.parse(row['pom']).getroot()
            get = lambda key: (pom.findtext('m:' + key.replace('/', '/m:'), '', NS) or '').strip()
            url = get('url') or get('scm/url')
            author = get('organization/name') or ', '.join(
                n.text.strip() for n in pom.findall('m:developers/m:developer/m:name', NS) if n.text)
            licenses = [n.text.strip() for n in pom.findall('m:licenses/m:license/m:name', NS) if n.text]
            override = overrides.get(row['group'])
            if override:
                url = override[0]
                licenses = licenses or [override[1]]
                author = author or override[2]
            author = author or ('AndroidX' if row['group'].startswith('androidx.') else row['group'])
            if not licenses:
                raise ValueError('License metadata missing: ' + coordinate)
            records[coordinate] = {
                'id': coordinate, 'name': ('AndroidX ' if row['group'].startswith('androidx.') and not get('name').startswith('AndroidX') else '') + (get('name') or row['name']), 'author': author,
                'version': row['version'], 'license': ' / '.join(licenses),
                'url': secure_url(url), 'description': re.sub(r'\s+', ' ', get('description'))[:700],
                'components': {scope}, 'coordinate': coordinate,
            }
    entries = []
    for record in records.values():
        # Runtime already implies compile usage within the same component.
        scopes = record['components']
        for component in ['APK／WebUI', 'Dex']:
            if component in scopes:
                scopes.discard(component + '（編譯時）')
        record['components'] = sorted(scopes)
        entries.append(record)
    DATA.mkdir(parents=True, exist_ok=True)
    payload = {'sourceInputs': hashes(), 'entries': sorted(entries, key=lambda r: r['id'])}
    (DATA / 'resolved.json').write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--import-metadata', nargs=2)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.import_metadata:
        import_metadata(args.import_metadata)
    resolved = json.loads((DATA / 'resolved.json').read_text(encoding='utf-8'))
    if resolved['sourceInputs'] != hashes():
        raise ValueError('Dependency declarations changed; refresh the resolved license metadata.')
    references = json.loads((DATA / 'references.json').read_text(encoding='utf-8'))
    entries = references + resolved['entries']
    assert len({r['id'] for r in entries}) == len(entries)
    for entry in entries:
        secure_url(entry['url'])
        for key in ['name', 'author', 'version', 'license', 'description']:
            assert isinstance(entry[key], str) and len(entry[key]) <= 8192, (entry['id'], key)
        assert entry['components']
    # Maven multiplatform metadata and platform artifacts often describe the
    # same library. Combine display cards without dropping attribution records.
    grouped = {}
    for entry in entries:
        key = tuple(entry[k].strip() for k in ['name', 'author', 'url', 'license'])
        grouped.setdefault(key, []).append(entry)
    cards = []
    for members in grouped.values():
        card = dict(members[0])
        card['members'] = members
        card['version'] = ' / '.join(sorted({r['version'] for r in members}))
        card['components'] = sorted({c for r in members for c in r['components']})
        card['description'] = '\n'.join(dict.fromkeys(r['description'] for r in members))
        card['coordinates'] = sorted({r['coordinate'] for r in members if r.get('coordinate')})
        cards.append(card)
    entries = cards
    entries.sort(key=lambda r: (r['name'].casefold(), r['version']))
    catalog = {'schema': 1, 'note': '直接與間接依賴、原始碼引用及設計參照；編譯時項目另行標示。Rust Cargo 依賴已鎖版並隨源碼附上授權。', 'entries': entries}
    text = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        assert OUTPUT.read_text(encoding='utf-8') == text, 'Generated license catalogue is stale'
    else:
        OUTPUT.write_text(text, encoding='utf-8', newline='\n')
    print(f'License catalogue: {len(entries)} entries ({len(resolved["entries"])} resolved Maven modules, {len(references)} references/tools)')

if __name__ == '__main__':
    main()
