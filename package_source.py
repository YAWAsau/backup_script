"""Package the listed source files without build outputs or historical evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tomllib
import zipfile


ROOT = Path(__file__).resolve().parent
INVENTORY = "source-package.json"
FORBIDDEN_PARTS = {
    ".git", ".gradle", ".idea", ".build", "__pycache__", "target",
    "out", "out-history", "out-r30", "android-r30-direct", "host-direct",
    "ci-output", "deliverables", "evidence", "validation",
}
RUNTIME_BINARIES = {
    "busybox", "classes.dex", "cmd", "find", "keycheck",
    "smbclient", "speednative", "tar", "zstd",
}
APPLETS = ("cgfreezer", "eventwait", "filewatch", "netwatch", "procwait",
           "speedscan", "uidexec", "unixsock")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def digest(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def source_path(name: str) -> Path:
    relative = PurePosixPath(name)
    require(not relative.is_absolute() and ".." not in relative.parts
            and "\\" not in name and ":" not in name
            and relative.as_posix() == name, f"Invalid source path: {name}")
    path = ROOT / name
    # Existing FULL_SOURCE work folders used a flat shell-script layout.
    if name in ("tools/tools.sh", "tools/dex_check.sh") and not path.exists():
        path = ROOT / relative.name
    require(path.is_file(), f"Required source missing: {name}")
    require(path.resolve().is_relative_to(ROOT), f"Source escapes root: {name}")
    for item in (path, *path.parents):
        if item == ROOT:
            break
        require(not item.is_symlink()
                and not (hasattr(item, "is_junction") and item.is_junction()),
                f"Linked source is not supported: {name}")
    return path


def collect() -> tuple[dict[str, bytes], dict[str, str]]:
    require(not (ROOT / "tools/jq").exists(), "Retired runtime tool must be removed: tools/jq")
    inventory = json.loads((ROOT / INVENTORY).read_text(encoding="utf-8"))
    require(inventory.get("schema") == 1, "Unsupported source-package.json schema")
    names = inventory["files"]
    require(isinstance(names, list) and all(isinstance(n, str) for n in names),
            "Source inventory must contain a list of paths")
    require(len(names) == len({n.casefold() for n in names}), "Duplicate source path")
    required = {
        INVENTORY, "package_source.py", "package_source.ps1", "BUILDING.md", "LICENSE",
        "build.ps1", "read_versions.ps1", "sync_version.ps1", "sync_artifacts.ps1",
        "VERSION", "versions.properties", "start.sh", "tools/tools.sh", "tools/dex_check.sh",
        "dex/build_dex.ps1", "dex/gradlew", "dex/gradlew.bat", "dex/LICENSE",
        "dex/THIRDPARTY_NOTICE.md", "dex/gradle/wrapper/gradle-wrapper.jar",
        "dex/gradle/wrapper/gradle-wrapper.properties", "dex/release-version.properties",
        "rust/Cargo.toml", "rust/Cargo.lock", "rust/build.ps1", "rust/build.rs",
        "rust/src/main.rs", "rust/src/lib.rs", "rust/src/multicall.rs",
        "tar/build.ps1", "tar/build.py", "tar/android_build_note.py",
        "tar/SOURCE_MANIFEST.json", "tar/upstream/COPYING",
        "zstd/build.ps1", "zstd/build_native.py", "zstd/android_build_note.py",
        "zstd/upstream_source_sha256.json", "zstd/upstream/LICENSE", "zstd/upstream/COPYING",
    } | {f"rust/src/bin/{name}.rs" for name in APPLETS}
    require(required <= set(names), "Required paths removed from inventory: "
            + ", ".join(sorted(required - set(names))))
    files = {}
    for name in sorted(names):
        require(PurePosixPath(name).name.lower() not in {"jq", "jq.exe"},
                f"Retired JSON tool is not a source input: {name}")
        require(name != "SOURCE_SHA256SUMS.txt", "Checksum file is generated, not an input")
        # Pinned upstream snapshots retain their exact file sets, including licences.
        if not name.startswith(("tar/upstream/", "zstd/upstream/")):
            parts = PurePosixPath(name).parts
            require(not FORBIDDEN_PARTS.intersection(parts), f"Non-source directory: {name}")
            require("build" not in parts, f"Build output directory: {name}")
            require(not name.endswith((".log", ".pyc", ".dex", ".apk", ".zip", ".bak"))
                    and parts[-1] != "local.properties", f"Non-source file: {name}")
        require(not (name.startswith("tools/") and PurePosixPath(name).name in RUNTIME_BINARIES),
                f"Runtime binary belongs in a separate package: {name}")
        files[name] = source_path(name).read_bytes()
        if not name.startswith(("tar/upstream/", "zstd/upstream/")) and (
            PurePosixPath(name).suffix in {".sh", ".rs", ".java", ".kt", ".kts", ".aidl", ".ps1", ".py"}
            or name == "dex/gradlew"
        ):
            require(b"\r" not in files[name] and not files[name].startswith(b"\xef\xbb\xbf"),
                    f"Source must be UTF-8 without BOM and use LF: {name}")
            files[name].decode("utf-8")
    # A new module must be added to the inventory; never silently omit it.
    for directory in ("dex/app/src", "dex/hiddenapi/src", "rust/src"):
        for path in (ROOT / directory).rglob("*"):
            if path.is_file():
                name = path.relative_to(ROOT).as_posix()
                require(name in files, f"Unlisted source: {name}; add it to {INVENTORY}")
    for component, manifest in (("tar", "SOURCE_MANIFEST.json"),
                                ("zstd", "upstream_source_sha256.json")):
        expected = json.loads(files[f"{component}/{manifest}"])["files"]
        prefix = f"{component}/upstream/"
        actual = {name[len(prefix):] for name in files if name.startswith(prefix)}
        require(actual == set(expected), f"Incomplete {component} upstream snapshot")
        for name, sha in expected.items():
            require(digest(files[prefix + name]) == sha, f"Upstream source changed: {prefix}{name}")
    versions = {}
    for line in files["versions.properties"].decode("utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, value = line.strip().split("=", 1)
        require(key not in versions and re.fullmatch(r"v[1-9][0-9]{2}", value),
                f"Invalid component version: {line}")
        versions[key] = value
    require(set(versions) == {"build", "script", "dex", *APPLETS}, "Incomplete version configuration")
    require(files["VERSION"].decode().strip() == versions["build"], "VERSION is stale; run sync_version.ps1")
    script = files["tools/tools.sh"].decode("utf-8")
    check = files["tools/dex_check.sh"].decode("utf-8")
    require(f'speedbackup_script_version="{versions["script"]}"' in script,
            "Script version is stale; run sync_version.ps1")
    require(f'DEX_CHECK_VERSION="{versions["script"]}"' in check
            and f'DEX_CHECK_BUILD="{versions["build"]}"' in check,
            "Self-check version is stale; run sync_version.ps1")
    require(f'dex_check.sh {digest(files["tools/dex_check.sh"])}' in script,
            "Self-check SHA is stale; run sync_version.ps1")
    dex_versions = dict(line.split("=", 1) for line in
                        files["dex/release-version.properties"].decode("utf-8").splitlines()
                        if line and not line.startswith("#"))
    require(dex_versions.get("version") == versions["dex"]
            and dex_versions.get("build") == versions["build"],
            "Dex metadata is stale; run sync_version.ps1")
    cargo = tomllib.loads(files["rust/Cargo.toml"].decode("utf-8"))["package"]
    lock = tomllib.loads(files["rust/Cargo.lock"].decode("utf-8"))["package"]
    native_version = f'{int(versions["build"][1:])}.0.0'
    require(cargo["version"] == native_version
            and [p["version"] for p in lock if p["name"] == cargo["name"]] == [native_version],
            "Cargo metadata is stale; run sync_version.ps1")
    return files, versions


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New ZIP path; an existing ZIP is never overwritten")
    args = parser.parse_args()
    files, versions = collect()
    output = (args.output or ROOT / "deliverables" /
              f'SpeedBackup_{versions["build"]}_FULL_SOURCE_CLEAN.zip').resolve()
    require(not output.exists(), f"Output already exists: {output}; use a new --output path")
    hashes = {name: digest(body) for name, body in files.items()}
    files["SOURCE_SHA256SUMS.txt"] = "".join(
        f"{sha}  {name}\n" for name, sha in hashes.items()).encode("utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, body in files.items():
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            mode = 0o755 if body.startswith(b"#!") else 0o644
            entry.external_attr = (0o100000 | mode) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, body, compresslevel=9)
    with zipfile.ZipFile(output) as archive:
        require(archive.testzip() is None, "Source ZIP CRC failure")
        require(set(archive.namelist()) == set(files), "Source ZIP file set mismatch")
        for name, body in files.items():
            require(archive.read(name) == body, f"Source ZIP bytes differ: {name}")
    print(f"Packaged {len(files)} files: {output}")
    print(f"SHA256: {digest(output.read_bytes())}")
    print("Source completeness, pinned upstream hashes and ZIP bytes checked. No build or runtime test was run.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f"Source packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
