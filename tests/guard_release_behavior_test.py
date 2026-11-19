"""Host behavior test of the production release orchestrator (requires JDK).
Run: python -m unittest discover -s tests -p guard_release_behavior_test.py
"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
JAVA = ROOT / 'dex/app/src/main/java/com/xayah/dex'

STUBS = r'''
package com.xayah.dex;
class ProcessObserverUtil {
 static String[] samples; static int reads;
 static String wchanStatus(int u,String p,String e) { return e.equals("frozen") ? "CGFREEZER_WCHAN_DONE ok=false\n" : samples[reads++]; }
 static String stopAsync(int t,int u,String p) { return "PROCESS_OBSERVER_DONE "; }
 static String topStatus(int u) { return ""; }
 static String foregroundStatus(int u,String[] p,int n) { return ""; }
 static boolean resumePausedPids(int u,String p,String s) { return true; }
}
class CgroupFreezeUtil {
 static int corrections; static boolean stopOk;
 static String refreshPrimaryAppScopePackageFreeze(int u,String p,String r,int t) { return ""; }
 static String stop(int t,int u,String p) { return new OperationResult("cgroup-stop",stopOk).token(t).restoration(stopOk,stopOk).appendTo(""); }
 static String correctiveThawPackage(int u,String p,int t) { corrections++; return "THAW_UID\n"; }
 static String restorePersistedPackage(int u,String p,String r) { return new OperationResult("cgroup-restore-package",true).restoration(true,true).appendTo(""); }
}
class UidNetworkBlockUtil {
 static String stop(int t,int u,String p) { return new OperationResult("uidnet-stop",true).token(t).restoration(true,true).appendTo(""); }
 static String restorePersistedPackage(int u,String p,String r) { return ""; }
}
class GuardReleaseBehavior {
 static final String BAD="CGFREEZER_WCHAN_DONE ok=false reason=expect_mismatch\n";
 static final String GOOD="CGFREEZER_WCHAN_DONE ok=true unknown=0\n";
 static void check(boolean expected,int budget,int corrections,boolean stopOk,String... samples) {
  ProcessObserverUtil.samples=samples; ProcessObserverUtil.reads=0;
  CgroupFreezeUtil.corrections=0; CgroupFreezeUtil.stopOk=stopOk;
  String out=BackupGuardRelease.release(new String[]{"backupGuardRelease","0","com.test.app","1","2","3","1000",""+budget,"-","1","700","0"});
  if(OperationResult.isOk(out,"backup-guard-release")!=expected || CgroupFreezeUtil.corrections!=corrections || ProcessObserverUtil.reads!=samples.length) throw new AssertionError(out);
  if(!expected && !out.contains("cgroupOk=false")) throw new AssertionError(out);
 }
 public static void main(String[] args) {
  check(true,1,1,true,BAD,GOOD);
  check(false,1,1,true,BAD,BAD);
  check(false,2,2,true,BAD,BAD,BAD);
  check(true,2,2,true,BAD,BAD,GOOD);
  check(false,0,0,true,BAD);
  check(false,1,1,false,BAD,BAD,BAD);
   check(true,1,1,false,BAD,BAD,GOOD); // fresh sample confirms successful persisted rescue
  check(true,1,0,true,"CGFREEZER_WCHAN_DONE ok=true unknown=1\n");
  check(false,1,0,true,"PROCESS_OBSERVER_WCHAN_ERROR reason=native_response\n");
 }
}
'''

class GuardReleaseBehaviorTest(unittest.TestCase):
    def test_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            stub = directory / 'GuardReleaseBehavior.java'
            stub.write_text(STUBS, encoding='utf-8')
            subprocess.run(['javac', '-d', tmp, str(JAVA / 'OperationResult.java'),
                            str(JAVA / 'BackupGuardRelease.java'), str(stub)], check=True)
            subprocess.run(['java', '-cp', tmp, 'com.xayah.dex.GuardReleaseBehavior'], check=True)

if __name__ == '__main__':
    unittest.main()
