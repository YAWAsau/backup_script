#!/usr/bin/env sh
set -eu
NDK="${1:-${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}}"
ARCH="${2:-arm64}"
if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
  echo "usage: $0 /path/to/android-ndk-r28c [arm64|x86_64]" >&2
  exit 2
fi
API="${ANDROID_API:-28}"
HOST_TAG="${HOST_TAG:-linux-x86_64}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
case "$ARCH" in
  arm64|aarch64)
    TARGET="aarch64-linux-android"
    RUST_TARGET="aarch64-linux-android"
    CLANG="$TOOLCHAIN/aarch64-linux-android${API}-clang"
    OUT="out/android-arm64"
    ;;
  x86_64|amd64)
    TARGET="x86_64-linux-android"
    RUST_TARGET="x86_64-linux-android"
    CLANG="$TOOLCHAIN/x86_64-linux-android${API}-clang"
    OUT="out/android-x86_64"
    ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac
command -v cargo >/dev/null 2>&1 || { echo "cargo not found" >&2; exit 127; }
command -v rustup >/dev/null 2>&1 && rustup target add "$RUST_TARGET" >/dev/null 2>&1 || true
mkdir -p .cargo "$OUT"
cat > .cargo/config.toml <<CFG
[target.$RUST_TARGET]
linker = "$CLANG"

[build]
target = "$RUST_TARGET"
CFG
TARGET_ENV_LOWER=$(printf '%s' "$RUST_TARGET" | tr '-' '_')
TARGET_ENV_UPPER=$(printf '%s' "$RUST_TARGET" | tr '[:lower:]-' '[:upper:]_')
env \
  "CC_${TARGET_ENV_LOWER}=$CLANG" \
  "CC_${TARGET_ENV_UPPER}=$CLANG" \
  "CARGO_TARGET_${TARGET_ENV_UPPER}_LINKER=$CLANG" \
  CARGO_PROFILE_RELEASE_OPT_LEVEL=z \
  CARGO_PROFILE_RELEASE_LTO=true \
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
  CARGO_PROFILE_RELEASE_PANIC=abort \
  CARGO_PROFILE_RELEASE_STRIP=symbols \
  cargo build --release --bins --target "$RUST_TARGET"
STRIP="${LLVM_STRIP:-$TOOLCHAIN/llvm-strip}"
for b in eventwait filewatch netwatch procwait speedscan uidexec unixsock cgfreezer; do
  cp "target/$RUST_TARGET/release/$b" "$OUT/$b"
  if [ -x "$STRIP" ]; then
    "$STRIP" --strip-all "$OUT/$b" || "$STRIP" "$OUT/$b" || true
  fi
  chmod 0755 "$OUT/$b"
done
(cd "$OUT" && sha256sum eventwait filewatch netwatch procwait speedscan uidexec unixsock cgfreezer > SHA256SUMS.native-rust-r550)
echo "built: rust/$OUT"
