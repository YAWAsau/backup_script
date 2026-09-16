#!/usr/bin/env sh
set -eu
# Generate an Android NDK compilation database for C2Rust.
# Usage: sh rust/c2rust_make_android_compile_commands.sh /path/to/android-ndk-r28c [arm64|x86_64] [out_dir]
NDK="${1:-${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}}"
ARCH="${2:-${ARCH:-arm64}}"
ROOT_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${3:-$ROOT_DIR/rust/parity/c2rust_android_compile_db}"
API="${ANDROID_API:-28}"
HOST_TAG="${HOST_TAG:-linux-x86_64}"
TOOLS="${TOOLS:-eventwait filewatch netwatch procwait speedscan uidexec unixsock cgfreezer}"

if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  echo "usage: $0 /path/to/android-ndk-r28c [arm64|x86_64] [out_dir]" >&2
  exit 2
fi

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
SYSROOT="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
case "$ARCH" in
  arm64|aarch64)
    TARGET="aarch64-linux-android"
    CLANG="$TOOLCHAIN/aarch64-linux-android${API}-clang"
    ;;
  x86_64|amd64)
    TARGET="x86_64-linux-android"
    CLANG="$TOOLCHAIN/x86_64-linux-android${API}-clang"
    ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac

if [ ! -x "$CLANG" ]; then
  echo "clang not found or not executable: $CLANG" >&2
  exit 2
fi
if [ ! -d "$SYSROOT" ]; then
  echo "sysroot not found: $SYSROOT" >&2
  exit 2
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

C_DIR="$ROOT_DIR/c"
mkdir -p "$OUT_DIR/obj"
DB="$OUT_DIR/compile_commands.json"
{
  printf '[\n'
  first=1
  for tool in $TOOLS; do
    src="$C_DIR/$tool.c"
    if [ ! -f "$src" ]; then
      echo "missing C source: $src" >&2
      exit 1
    fi
    obj="$OUT_DIR/obj/$tool.o"
    cmd="$CLANG -std=c11 -O0 -g0 -fPIE -fPIC -Wall -Wextra -D_GNU_SOURCE -D__ANDROID__ -D__ANDROID_API__=$API --target=$TARGET --sysroot=$SYSROOT -c $src -o $obj"
    if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
    printf '  {"directory":"%s","command":"%s","file":"%s"}' \
      "$(json_escape "$C_DIR")" "$(json_escape "$cmd")" "$(json_escape "$src")"
  done
  printf '\n]\n'
} > "$DB"

echo "compile database: $DB"
echo "tools: $TOOLS"
echo "target: $TARGET api=$API sysroot=$SYSROOT"
