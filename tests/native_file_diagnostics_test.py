"""Focused source contract for the file RPC diagnostic/protocol boundary.
Run: python3 -m unittest discover -s tests -p native_file_diagnostics_test.py
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeFileDiagnostics(unittest.TestCase):
    def test_response_routing_and_failure_order(self):
        source = (ROOT / 'dex/app/src/main/java/com/xayah/dex/NativeFileClient.java').read_text(encoding='utf-8')
        run = source[source.index('static synchronized void run('):]
        failure = run.index('if(r.rc!=0) {')
        write = run.index('System.err.write(r.body);System.err.flush();', failure)
        throw = run.index('throw new OperationFailure(r.rc);', write)
        diagnostic = run.index('DiagnosticLog.write("root_daemon_diagnostic.log"', throw)
        catch = run.index('} catch(Exception e)', diagnostic)
        self.assertLess(failure, write)
        self.assertLess(write, throw)
        self.assertLess(throw, diagnostic)
        self.assertIn('String diagnostics=new String(r.body,StandardCharsets.UTF_8)', run[throw:diagnostic])
        self.assertIn('line.startsWith("RESTORE_PACKAGE_MAP_UPDATE_ERROR ")', run[throw:diagnostic])
        self.assertIn('line.startsWith("OOM_PROTECT ")', run[throw:diagnostic])
        self.assertIn('System.err.println(line)', run[throw:diagnostic])
        self.assertIn('diagnostics', run[diagnostic:catch])
        self.assertIn('FILE_RPC_OK command=', run[diagnostic:catch])
        self.assertNotIn('System.err', run[diagnostic:catch])
        self.assertNotIn('System.out', run)
        # Transport failures and unsafe outcomes must still be visible and thrown.
        self.assertIn('((TransportFailure)e).written)uncertain=true', run[catch:])
        self.assertIn('((OperationFailure)e).code==125)uncertain=true', run[catch:])
        self.assertIn('System.err.println((uncertain?"FILE_RPC_UNSAFE":"FILE_RPC_FAILED")', run[catch:])
        self.assertIn('throw e;', run[catch:])

    def test_external_policy_info_routing_and_phase_boundaries(self):
        source = (ROOT / 'dex/app/src/main/java/com/xayah/dex/ExternalRestorePolicy.java').read_text(encoding='utf-8')
        sink = 'DiagnosticLog.write("root_daemon_diagnostic.log", '
        self.assertEqual(source.count(sink), 6)
        # Phase-begin receipts must remain before the work, not buffered until success.
        for stage, work in (
            ('precheck', 'StructStat old=stat(target);'),
            ('vold', 'if(vold!=null) setup.invoke(vold,storage,app.uid);'),
            ('postcheck', 'StructStat s=Os.lstat(target.getPath());'),
            ('clear', 'if(!nativeClear) clear(target,s.st_dev);'),
        ):
            receipt = source.index(sink + '"EXTERNAL_PREPARE_PHASE_BEGIN stage=' + stage)
            following = source.index('\n', receipt)
            self.assertTrue(source[following:].lstrip().startswith(work), stage)
        self.assertIn(sink + '"EXTERNAL_PREPARE_PHASES native=', source)
        self.assertIn(sink + '"EXTERNAL_REPAIR_TIMING nativePreflight=', source)
        self.assertNotIn('System.err.println("EXTERNAL_', source)
        # Command replies and the exceptional path remain separate from diagnostics.
        self.assertIn('DaemonOutput.current().println(p.target.getPath()', source)
        self.assertIn('DaemonOutput.current().println("EXTERNAL_POLICY_PATH_TOO_LONG");', source)
        self.assertIn('throw new IllegalStateException("External restore policy failed",e);', source)

    def test_native_capture_and_result_remain_authoritative(self):
        native = (ROOT / 'rust/src/file_rpc.rs').read_text(encoding='utf-8')
        self.assertIn('dup2(writer.as_raw_fd(), 1)', native)
        self.assertIn('dup2(writer.as_raw_fd(), 2)', native)
        self.assertIn('waitpid(pid, &mut status, 1)', native)
        log = (ROOT / 'dex/app/src/main/java/com/xayah/dex/DiagnosticLog.java').read_text(encoding='utf-8')
        self.assertIn('if (!parent.isDirectory()) return;', log)
        self.assertIn('OsConstants.O_NOFOLLOW', log)
        self.assertIn('if (st.st_size >= 1048576) return;', log)
        self.assertNotIn('System.out', log)


if __name__ == '__main__':
    unittest.main()
