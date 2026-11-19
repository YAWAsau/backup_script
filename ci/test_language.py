"""Host regressions for language conversion of files containing user data."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "tools/tools.sh").read_text(encoding="utf-8")
CONFIG = """# 資料夾設定
Output_path="/sdcard/備份資料夾/文件夹"
smb_remote_pass='測試檔案#密碼'
Custom_path="
/sdcard/相機
#資料夾內的文字也是值
"
Shell_LANG="1"
"""


def extract(name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^}", SOURCE, re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing shell function: {name}")
    return match.group()


FUNCTIONS = "\n".join(extract(name) for name in (
    "ts", "ts_inplace", "_speedbackup_translate_file_once", "_sb_update_translate_target_confs",
))
FIXTURE = r'''
_dex_raw() {
    [ "$1" = com.xayah.dex.CCUtil ] || return 90
    printf '%s\n' "$2" >> "$TMPDIR/converter.calls"
    [ "${CONVERTER_FAIL:-0}" = 1 ] && return 1
    case $2 in
    t2s) sed 's/資料夾/文件夹/g; s/檔案/文件/g; s/密碼/密码/g' ;;
    s2t) sed 's/文件夹/資料夾/g; s/文件/檔案/g; s/密码/密碼/g' ;;
    *) return 91 ;;
    esac
}
# Language switching must also leave comment-like lines in multiline values intact.
_conf_sanitize_legacy_comment_noise() {
    printf '%s\n' "$1" >> "$TMPDIR/config-sanitize.calls"
    return 1
}
_sb_file_has_exact_line() { grep -Fxq -- "$1" "$2"; }
_sb_update_report_line() { printf '%s\n' "$2" >> "$1"; }
'''


class LanguageTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="speedbackup-language-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "backup_settings.conf"
        self.config.write_text(CONFIG, encoding="utf-8")
        self.config.chmod(0o600)

    def run_shell(self, body: str, **environment: str) -> subprocess.CompletedProcess[str]:
        interpreter = ["bash", "--noprofile", "--norc"]
        if os.environ.get("SB_TEST_SHELL") == "busybox":
            interpreter = ["busybox", "ash"]
        env = {key: value for key, value in os.environ.items() if key not in {"BASH_ENV", "ENV"}}
        env.update(TMPDIR=str(self.root), TARGET=str(self.config), SCRIPT_LANG="zh-CN",
                   Script_target_language="zh-CN")
        env.update(environment)
        return subprocess.run(
            [*interpreter, "-c", FUNCTIONS + "\n" + FIXTURE + "\n" + body],
            cwd=self.root, env=env, capture_output=True, text=True, encoding="utf-8", timeout=15,
        )

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_config_unchanged(self, config: Path) -> None:
        self.assertEqual(config.read_bytes(), CONFIG.encode("utf-8"))
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.root / "converter.calls").exists())
        self.assertFalse((self.root / "config-sanitize.calls").exists())

    def test_configuration_bytes_are_preserved(self) -> None:
        for language in ("zh-CN", "zh-TW"):
            for name in ("backup_settings.conf", "restore_settings.conf", "自訂 設定.conf"):
                with self.subTest(language=language, name=name):
                    config = self.root / name
                    config.write_text(CONFIG, encoding="utf-8")
                    config.chmod(0o600)
                    self.assert_success(self.run_shell(
                        'ts_inplace "$TARGET"', TARGET=str(config), SCRIPT_LANG=language,
                        Script_target_language=language,
                    ))
                    self.assert_config_unchanged(config)

    def test_configuration_does_not_require_converter(self) -> None:
        self.assert_success(self.run_shell('ts_inplace "$TARGET"', CONVERTER_FAIL="1"))
        self.assert_config_unchanged(self.config)

    def test_startup_conf_translation_preserves_values(self) -> None:
        self.assert_success(self.run_shell(
            '_speedbackup_translate_file_once "$TARGET" "$TMPDIR/done.list"',
        ))
        self.assert_config_unchanged(self.config)
        self.assertEqual((self.root / "done.list").read_text(encoding="utf-8"), f"{self.config}\n")

    def test_update_conf_translation_preserves_values(self) -> None:
        restore = self.root / "restore_settings.conf"
        restore.write_text(CONFIG, encoding="utf-8")
        restore.chmod(0o600)
        self.assert_success(self.run_shell(
            '_sb_update_translate_target_confs "$TMPDIR" "$TMPDIR/report.txt"',
        ))
        self.assert_config_unchanged(self.config)
        self.assert_config_unchanged(restore)
        self.assertIn("preserved conf files: 2", (self.root / "report.txt").read_text(encoding="utf-8"))

    def test_non_configuration_file_is_converted(self) -> None:
        target = self.root / "測試 script.sh"
        for language, original, expected in (
            ("zh-CN", 'echo "資料夾 檔案"\n', 'echo "文件夹 文件"\n'),
            ("zh-TW", 'echo "文件夹 文件"\n', 'echo "資料夾 檔案"\n'),
        ):
            with self.subTest(language=language):
                target.write_text(original, encoding="utf-8")
                target.chmod(0o750)
                self.assert_success(self.run_shell(
                    'ts_inplace "$TARGET"', TARGET=str(target), SCRIPT_LANG=language,
                    Script_target_language=language,
                ))
                self.assertEqual(target.read_text(encoding="utf-8"), expected)
                self.assertEqual(target.stat().st_mode & 0o777, 0o750)
                self.assertEqual(list(self.root.glob("*.ts.*")), [])

    def test_failed_converter_preserves_original(self) -> None:
        target = self.root / "script.sh"
        original = 'echo "資料夾"\n'
        target.write_text(original, encoding="utf-8")
        result = self.run_shell('ts_inplace "$TARGET"', TARGET=str(target), CONVERTER_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(encoding="utf-8"), original)
        self.assertEqual(list(self.root.glob("*.ts.*")), [])

    def test_symlink_is_rejected(self) -> None:
        link = self.root / "link.conf"
        link.symlink_to(self.config)
        result = self.run_shell('ts_inplace "$TARGET"', TARGET=str(link))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(link.is_symlink())
        self.assert_config_unchanged(self.config)

    def test_missing_file_is_not_created(self) -> None:
        missing = self.root / "missing.conf"
        result = self.run_shell('ts_inplace "$TARGET"', TARGET=str(missing))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(missing.exists())


if __name__ == "__main__":
    unittest.main()
