"""Shell facade uses native probe/state; native integration tests exercise transport."""
from pathlib import Path
import os,re,shutil,subprocess
source=(Path(__file__).resolve().parent.parent/'tools/tools.sh').read_text(encoding='utf-8')
def extract(name):return re.search(r'^'+re.escape(name)+r'\(\) \{\n.*?^}',source,re.M|re.S).group()
bash=os.environ.get('SB_TEST_BASH') or shutil.which('bash') or 'C:/Program Files/Git/bin/bash.exe'
script='\n'.join(extract(n) for n in ['_remote_connection_probe','remote_precheck','_remote_health_webdav_failure','_remote_health_webdav_reason'])+r'''
conf_path=/private/config;remote_type=smb;remote_user=u;remote_pass=p
_speedscan_cmd(){
 case "$1 $2" in
 'remote-probe /private/config') [ "$#" = 2 ] || exit 90;printf '%s\n' "$probe_reason";return "$probe_rc";;
 'remote-health ready') return "$cache_rc";;
 'remote-control webdav-reason') printf '%s\n' auth_failed;;
 *) return 91;;
 esac
}
probe_rc=0;probe_reason=ready
_remote_connection_probe || exit 1
[ "$_REMOTE_HEALTH_REASON" = ready ] || exit 2
probe_rc=1;probe_reason=$'auth_failed\n1\nSMB rejected\nCheck password'
_remote_connection_probe && exit 3
[ "$_REMOTE_HEALTH_REASON" = auth_failed ] && [ "$_SMB_AUTH_REJECTED" = 1 ] && [ "$_SMB_TARGET_PROBE_ERROR_ZH" = 'SMB rejected' ] || exit 4
SPEEDBACKUP_REMOTE_HEALTH_DIR=/private;cache_rc=0
remote_precheck host 445 backup || exit 5
cache_rc=1;remote_precheck host 445 restore && exit 6
probe_rc=0;remote_precheck host 445 manual && exit 7
# Manual entries share the same cached generation; only absent health state
# falls back to a transport probe.
unset SPEEDBACKUP_REMOTE_HEALTH_DIR
remote_precheck host 445 manual || exit 10
probe_rc=1;remote_precheck host 445 manual && exit 11
_remote_health_event(){ failures=$((failures+1)); }
failures=0;_WEBDAV_HTTP_CODE=404;_remote_health_webdav_failure
_WEBDAV_HTTP_CODE=409;_remote_health_webdav_failure
[ "$failures" = 0 ] || exit 8
_WEBDAV_HTTP_CODE=401;_remote_health_webdav_failure
[ "$failures" = 1 ] && [ "$_REMOTE_HEALTH_REASON" = auth_failed ] || exit 9
'''
r=subprocess.run([bash],input=script,text=True,encoding='utf-8',capture_output=True)
assert r.returncode==0,(r.returncode,r.stdout,r.stderr)
print('Remote health native facade: PASS')
