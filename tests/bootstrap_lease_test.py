"""Host lease contract; run with python -m unittest discover -s tests -p bootstrap_lease_test.py.
Uses mksh when installed (sh otherwise). This is not an Android 10 device test.
The helper performs only the numeric-FD kernel flock used by Android 10 toybox.
No read-mode requirement is imposed. Device mksh/toybox integration is still required.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(os.name == 'posix', 'requires POSIX descriptor inheritance/flock')
class BootstrapLeaseTest(unittest.TestCase):
    def test_all_three_sources_hold_lease_through_exec(self):
        blocks = []
        handoffs = []
        for path in [ROOT / 'start.sh', ROOT / 'tools/tools.sh']:
            text = path.read_text(encoding='utf-8')
            blocks.extend(re.findall(r'exec 8[^\n]+\n\s*/system/bin/flock[^\n]+\n\s*export SPEEDBACKUP_CACHE_LEASE_FD=9', text))
            handoffs.extend(re.findall(r'exec "\$_sb_console_boot/speednative"[^\n]+"\$@" (9[^\n]+)', text))
        self.assertEqual(len(blocks), 3)
        self.assertEqual(handoffs, ['9>&8 8>&-'] * 3)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            lock = tmp / 'cache.lock'
            lock.write_bytes(b'unchanged')
            lock.chmod(0o600)
            shim = tmp / 'flock'
            shim.write_text('#!' + sys.executable + '\n' +
                            'import os, fcntl, sys\n'
                            'assert sys.argv[1:] == ["-s", "9"]\n'
                            'assert fcntl.fcntl(9, fcntl.F_GETFL) & os.O_ACCMODE == os.O_WRONLY\n'
                            'fcntl.flock(9, fcntl.LOCK_SH)\n')
            shim.chmod(0o700)
            handoff = tmp / 'handoff.py'
            handoff.write_text('''import os, sys, fcntl, subprocess
assert os.environ['SPEEDBACKUP_CACHE_LEASE_FD'] == '9'
assert os.fstat(9).st_ino == os.stat(sys.argv[1]).st_ino
assert fcntl.fcntl(9, fcntl.F_GETFL) & os.O_ACCMODE == os.O_WRONLY
try:
    os.fstat(8)
except OSError:
    pass
else:
    raise AssertionError('extra lease descriptor leaked')
assert sys.stdin.read() == 'original stdin'
# Separate open description must not obtain exclusive GC lease.
probe = "import fcntl,sys; f=open(sys.argv[1], 'r+'); fcntl.flock(f, fcntl.LOCK_EX|fcntl.LOCK_NB)"
r = subprocess.run([sys.executable, '-c', probe, sys.argv[1]], stderr=subprocess.DEVNULL)
assert r.returncode != 0
os.close(9)
subprocess.run([sys.executable, '-c', probe, sys.argv[1]], check=True)
''')
            for shell in dict.fromkeys(filter(None, [shutil.which('mksh'), shutil.which('sh')])):
                for block in blocks:
                    self.assertIn('exec 8>>', block)
                    script = block.replace('/system/bin/flock', '"$shim"')
                    script += '\nexec "$python" "$handoff" "$_sb_cache_lock" ' + handoffs[0] + '\n'
                    env = dict(os.environ, _sb_cache_lock=str(lock), shim=str(shim),
                               python=sys.executable, handoff=str(handoff))
                    subprocess.run([shell, '-c', script], env=env, input='original stdin', text=True, check=True, timeout=10)
                    self.assertEqual(lock.read_bytes(), b'unchanged')
                    # Lock errors remain fatal: never reach native handoff.
                    bad = script.replace('"$shim" -s 9', 'false')
                    result = subprocess.run([shell, '-c', bad], env=env, timeout=10)
                    self.assertEqual(result.returncode, 1)
