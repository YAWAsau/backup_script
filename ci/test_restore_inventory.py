from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "tools/tools.sh").read_text(encoding="utf-8")
BASH = os.environ.get("SB_TEST_BASH") or shutil.which("bash") or "C:/Program Files/Git/bin/bash.exe"


def extract(name):
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^}", SOURCE, re.M | re.S)
    assert match is not None, name
    return match.group()


def inventory_cases():
    header = "RESTORE_MAPS_1\t0\n"
    rows = "com.fixture.one\t12345\t9007199254740993\ncom.fixture.two\t-1\t2\ncom.fixture.three\t12347\t-1\n"
    valid = header + rows + "END_RESTORE_MAPS_1\t3\n"
    cases = {
        "valid": (valid, "", True),
        "leading_zero_user": (valid, "USER_ID=000", True),
        "unowned_directory": (valid, "SPEEDBACKUP_RUN_TMPDIR_OWN=0", False),
        "mismatched_directory": (valid, "SPEEDBACKUP_RUN_TMPDIR=/other", False),
        "invalid_user": (valid, "typeset +i USER_ID; USER_ID=invalid", False),
        "stage_failure": (valid, "mktemp() { return 1; }", False),
        "transport_failure": (valid, "RETURN_CODE=1", False),
        "wrong_user": (valid.replace("MAPS_1\t0", "MAPS_1\t10"), "", False),
        "missing_header": (rows + "END_RESTORE_MAPS_1\t3\n", "", False),
        "missing_footer": (header + rows, "", False),
        "wrong_count": (valid.replace("MAPS_1\t3", "MAPS_1\t4"), "", False),
        "duplicate": (header + rows + rows + "END_RESTORE_MAPS_1\t6\n", "", False),
        "extra_footer": (valid + "END_RESTORE_MAPS_1\t3\n", "", False),
        "after_footer": (valid + "com.extra\t10\t20\n", "", False),
        "invalid_uid": (valid.replace("12345", "1x"), "", False),
        "negative_uid": (valid.replace("12345", "-2"), "", False),
        "invalid_version": (valid.replace("9007199254740993", "1e9"), "", False),
        "extra_column": (valid.replace("12345\t", "12345\textra\t"), "", False),
        "invalid_package": (valid.replace("com.fixture.one", "../escape"), "", False),
        "embedded_nul": (valid.replace("com.fixture.one", "com.fixture.\0one"), "", False),
        "empty": (header + "END_RESTORE_MAPS_1\t0\n", "", False),
        "no_uid": (header + "com.fixture.one\t-1\t1\nEND_RESTORE_MAPS_1\t1\n", "", False),
        "no_version": (header + "com.fixture.one\t1\t-1\nEND_RESTORE_MAPS_1\t1\n", "", False),
        "awk_failure": (valid, "awk() { return 1; }", False),
        "publish_failure": (valid, "mv() { return 1; }", False),
        "partial_publish": (valid, 'mv() { command mv "$2" "$5/"; return 1; }', False),
        "old_dex_format": ('{"packageName":"com.fixture.one","uid":12345}\n', "", False),
    }
    return cases


def test_maps():
    cases = inventory_cases()
    with tempfile.TemporaryDirectory(prefix="sb-inventory-ci-") as temporary:
        assert Path(temporary).resolve().parent == Path(tempfile.gettempdir()).resolve()
        for name, (fixture, injection, expected) in cases.items():
            folder = Path(temporary) / name
            folder.mkdir()
            (folder / "input").write_bytes(fixture.encode())
            script = extract("prepare_restore_inventory_maps") + """
cd "$1" || exit 99
TMPDIR="$PWD"; SPEEDBACKUP_RUN_TMPDIR="$PWD"; SPEEDBACKUP_RUN_TMPDIR_OWN=1
SPEED_DEBUG_ERR_LOG=/dev/null; USER_ID=0; RETURN_CODE=0
appinventory() {
    [[ "$*" = "restoreMaps all refresh" ]] || return 98
    cat input
    return "$RETURN_CODE"
}
_speed_debug_log() { :; }
""" + injection + "\nprepare_restore_inventory_maps\n"
            local = folder / "test.sh"
            local.write_text(script, encoding="utf-8", newline="\n")
            result = subprocess.run([BASH, str(local), str(folder)], capture_output=True, timeout=20)
            assert (result.returncode == 0) == expected, (name, result.returncode, result.stderr)
            paths = [folder / filename for filename in (".pkg_uid", ".pkg_ver", ".installed_pkgs")]
            if expected:
                assert paths[0].read_text() == "com.fixture.one\t12345\ncom.fixture.three\t12347\n"
                assert paths[1].read_text() == "com.fixture.one\t9007199254740993\ncom.fixture.two\t2\n"
                assert paths[2].read_text() == "com.fixture.one\ncom.fixture.two\ncom.fixture.three\n"
            else:
                assert all(not path.exists() for path in paths), name
            assert not list(folder.glob(".restore_inventory.*")), name
    return len(cases)


def test_failure_order():
    with tempfile.TemporaryDirectory(prefix="sb-inventory-order-") as temporary:
        folder = Path(temporary)
        assert folder.resolve().parent == Path(tempfile.gettempdir()).resolve()
        script = folder / "test.sh"
        body = extract("Restore") + """
cd "$1" || exit 99
path2="$PWD"
_maps_timeline_discard_deferred() { :; }
_speedbackup_operation_begin() { :; }
self_test() { :; }
_speedbackup_refresh_terminal_host() { :; }
_speed_debug_log() { :; }
_appstate_require_main_capabilities() { :; }
_speedscan_require_main_capabilities() { :; }
_audio_playback_guard_prepare() { :; }
_action_foreground_dex_display() { :; }
_prepare_timed() { return 1; }
echoRgb() { :; }
disable_verify() { : > security-setting-touched; }
Restore
status=$?
[[ $status = 1 && ! -e security-setting-touched ]]
"""
        script.write_text(body, encoding="utf-8", newline="\n")
        subprocess.run([BASH, str(script), str(folder)], check=True, timeout=20)


if __name__ == "__main__":
    count = test_maps()
    test_failure_order()
    print(f"PASS {count} inventory cases and failure-order safety")
