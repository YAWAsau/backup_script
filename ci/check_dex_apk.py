"""Minimal bounded reader for ordinary little-endian DEX string_ids."""
import hashlib
import re
import struct
import zlib


def require(ok, message):
    if not ok:
        raise ValueError(message)


def dex_strings(data):
    # Deliberately reject compact DEX, reverse endian and container DEX.
    require(len(data) >= 112, "Truncated DEX header")
    require(data[:8] in {
        b"dex\n035\0", b"dex\n037\0", b"dex\n038\0",
        b"dex\n039\0", b"dex\n040\0",
    }, "Unsupported DEX magic/version")
    def u32(offset):
        return struct.unpack_from("<I", data, offset)[0]
    require(u32(32) == len(data), "DEX file_size mismatch")
    require(u32(36) == 112 and u32(40) == 0x12345678,
            "Unsupported DEX header/endian")
    require(data[12:32] == hashlib.sha1(data[32:]).digest(),
            "DEX signature mismatch")
    require(u32(8) == zlib.adler32(data[12:]) & 0xffffffff,
            "DEX checksum mismatch")
    count, table = u32(56), u32(60)
    size, start = u32(104), u32(108)
    end = start + size
    require(112 <= start <= end == len(data), "Invalid DEX data section")
    require(count > 0 and table >= 112 and table % 4 == 0
            and table <= start and count <= (start-table)//4,
            "Invalid DEX string_ids")
    seen = set()
    for index in range(count):
        pos = u32(table + index*4)
        require(start <= pos < end and pos not in seen,
                "Invalid/duplicate DEX string_data offset")
        seen.add(pos)
        units = 0
        for shift in range(0, 35, 7):
            require(pos < end, "Truncated DEX ULEB128")
            b = data[pos]
            pos += 1
            require(shift != 28 or b <= 15, "Overflow DEX ULEB128")
            units |= (b & 127) << shift
            if not b & 128:
                break
        else:
            raise ValueError("Unterminated DEX ULEB128")
        # MUTF-8 encodes UTF-16 code units, including isolated surrogates.
        chars = []
        while True:
            require(pos < end, "Unterminated DEX string")
            a = data[pos]
            pos += 1
            if a == 0:
                break
            if a < 128:
                value = a
            elif 0xc0 <= a <= 0xdf:
                require(pos < end and data[pos] & 0xc0 == 0x80,
                        "Malformed DEX MUTF-8")
                value = ((a & 31) << 6) | (data[pos] & 63)
                pos += 1
                require(value >= 128 or (a == 0xc0 and value == 0),
                        "Overlong DEX MUTF-8")
            elif 0xe0 <= a <= 0xef:
                require(pos + 1 < end
                        and data[pos] & 0xc0 == 0x80
                        and data[pos+1] & 0xc0 == 0x80,
                        "Malformed DEX MUTF-8")
                value = ((a & 15) << 12) | ((data[pos] & 63) << 6) | (data[pos+1] & 63)
                pos += 2
                require(value >= 2048, "Overlong DEX MUTF-8")
            else:
                raise ValueError("Malformed DEX MUTF-8 lead byte")
            chars.append(chr(value))
            require(len(chars) <= units, "DEX UTF-16 length mismatch")
        require(len(chars) == units, "DEX UTF-16 length mismatch")
        yield "".join(chars)


def verify_dex_apk(path, expected):
    require(isinstance(expected, str)
            and re.fullmatch(r"[0-9a-f]{64}", expected),
            "Invalid expected APK_SHA")
    # Consume every entry so malformed entries cannot be hidden after a match.
    found = False
    for value in dex_strings(path.read_bytes()):
        found |= value == expected
    require(found, f"{path}: compiled DEX APK_SHA differs from embedded APK; "
            "build APK, then Dex, then Rust")
