"""Reject static SMB artifacts missing the kernel-backed RNG link fix.
This structural/marker check is a release guard, not a replacement for device tests.
"""
from pathlib import Path
import struct
import sys

def verify(path):
    data = Path(path).read_bytes()
    def require(ok, message):
        if not ok:
            raise ValueError(str(path) + ': ' + message)
    require(len(data) >= 64 and data[:7] == b'\x7fELF\x02\x01\x01', 'expected ELF64 little endian')
    require(struct.unpack_from('<HH', data, 16) == (2, 183), 'expected static AArch64 ET_EXEC')
    phoff = struct.unpack_from('<Q', data, 32)[0]
    phsize, count = struct.unpack_from('<HH', data, 54)
    require(phsize == 56 and count > 0 and phoff + count * phsize <= len(data), 'invalid program headers')
    loads = 0
    for i in range(count):
        kind, flags, offset, address, _, size, memory, align = struct.unpack_from('<IIQQQQQQ', data, phoff + i * phsize)
        require(kind not in (2, 3), 'dynamic/interpreter segment forbidden')
        require(offset + size <= len(data), 'segment outside file')
        if kind == 1:
            loads += 1
            require(memory >= size and align >= 16384 and align & (align - 1) == 0 and offset % align == address % align, 'invalid LOAD alignment/size')
    require(loads > 0, 'missing LOAD segment')
    require(b'SpeedBackup: kernel random source failed\n' in data, 'kernel RNG marker missing')
    require(b'arc4random data MADV_WIPEONFORK failed' not in data, 'obsolete RNG abort path present')
    return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('usage: verify-rng-elf.py BINARY')
    verify(sys.argv[1])
    print('PASS static AArch64 RNG artifact guard')
