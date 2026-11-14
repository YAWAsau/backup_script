"""Compile pinned OpenCC phrase dictionaries into a compact embedded trie."""
from pathlib import Path
import base64
import hashlib
import json
import re
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'third_party/opencc-phrases'


def read_dictionary(name):
    entries = {}
    for line in (UPSTREAM / name).read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        key, candidates = line.split('\t', 1)
        assert key not in entries, key
        entries[key] = candidates.split(' ')[0]
    return entries


def compile_dictionary(entries):
    children, values = [{}], [None]
    for key, value in entries.items():
        units = struct.unpack('>' + 'H' * (len(key.encode('utf-16-be')) // 2), key.encode('utf-16-be'))
        node = 0
        for unit in units:
            if unit not in children[node]:
                children[node][unit] = len(children)
                children.append({})
                values.append(None)
            node = children[node][unit]
        values[node] = value
    nodes, edges, strings = bytearray(), bytearray(), bytearray()
    for child, value in zip(children, values):
        encoded = value.encode('utf-8') if value is not None else b''
        assert len(child) < 65536 and len(encoded) < 65536
        nodes += struct.pack('>IHHI', len(edges) // 8, len(child), len(encoded), len(strings))
        strings += encoded
        for unit, target in sorted(child.items()):
            edges += struct.pack('>II', unit, target)
    result = struct.pack('>III', len(children), len(edges) // 8, len(strings)) + nodes + edges + strings
    return result, len(entries)


def main():
    metadata = json.loads((UPSTREAM / 'upstream.json').read_text(encoding='utf-8'))
    for name, digest in metadata['files'].items():
        assert hashlib.sha256((UPSTREAM / name).read_bytes()).hexdigest() == digest, name
    dictionaries, ids = [], {}
    def merged(spec):
        if spec['type'] == 'ocd2':
            return read_dictionary(Path(spec['file']).stem + '.txt')
        assert spec['type'] == 'group' and spec['match_policy'] == 'union'
        result = {}
        for child in spec['dicts']:
            for key, value in merged(child).items():
                result.setdefault(key, value)
        return result
    def group(spec):
        if spec['type'] == 'group' and spec['match_policy'] == 'short_circuit':
            return [index for child in spec['dicts'] for index in group(child)]
        key = json.dumps(spec, sort_keys=True)
        if key not in ids:
            ids[key] = len(dictionaries)
            dictionaries.append(compile_dictionary(merged(spec))[0])
        return [ids[key]]
    profiles = {}
    for name in ['s2twp', 'tw2sp']:
        config = json.loads((UPSTREAM / (name + '.json')).read_text(encoding='utf-8'))
        assert config['segmentation']['type'] == 'mmseg'
        profiles[name] = ([group(step['dict']) for step in config.get('normalization', [])],
                          group(config['segmentation']['dict']),
                          [group(step['dict']) for step in config['conversion_chain']])
    binary = struct.pack('>II', 0x53424332, len(dictionaries))
    binary += b''.join(struct.pack('>I', len(d)) for d in dictionaries) + b''.join(dictionaries)
    def row(values):
        return '{' + ', '.join(map(str, values)) + '}'
    def matrix(values):
        return '{' + ', '.join(row(v) for v in values) + '}'
    fields = ''
    for name, (normalization, segmentation, chain) in profiles.items():
        prefix = name.upper()
        fields += '    static final int[][] ' + prefix + '_NORMALIZE = ' + matrix(normalization) + ';\n'
        fields += '    static final int[] ' + prefix + '_SEGMENT = ' + row(segmentation) + ';\n'
        fields += '    static final int[][] ' + prefix + '_CHAIN = ' + matrix(chain) + ';\n'
    packed = base64.b64encode(zlib.compress(binary, 9)).decode('ascii')
    target = ROOT / 'dex/app/src/main/java/com/xayah/dex/OpenCcPhraseData.java'
    # Keep a valid existing stream even if the host's zlib encodes it differently.
    # The semantic comparison is against the complete uncompressed trie.
    if target.exists():
        existing = ''.join(re.findall(r'        "([A-Za-z0-9+/=]+)",', target.read_text(encoding='utf-8')))
        try:
            if zlib.decompress(base64.b64decode(existing, validate=True)) == binary:
                packed = existing
        except (ValueError, zlib.error):
            pass
    chunks = [packed[i:i+16000] for i in range(0, len(packed), 16000)]
    source = '''package com.xayah.dex;

// Generated from pinned Apache-2.0 OpenCC dictionaries. Do not edit by hand.
final class OpenCcPhraseData {
    static final int UNCOMPRESSED_BYTES = %d;
    static final String[] CHUNKS = {
''' % len(binary)
    source = source.replace('    static final String[] CHUNKS', fields + '    static final String[] CHUNKS')
    source += ''.join('        "' + chunk + '",\n' for chunk in chunks)
    source += '    };\n}\n'
    if '--check' in sys.argv:
        assert target.read_bytes() == source.encode('utf-8'), 'Stale OpenCC phrase data'
    else:
        target.write_text(source, encoding='utf-8', newline='\n')
    print(f'OpenCC s2twp/tw2sp: {len(dictionaries)} tries, raw={len(binary)}, base64={len(packed)} bytes')


if __name__ == '__main__':
    main()
