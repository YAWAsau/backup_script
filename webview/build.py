from pathlib import Path
import subprocess,os,json,hashlib,zipfile,re,sys,shutil
S=Path(__file__).resolve().parent
sdk=Path(os.environ.get('ANDROID_HOME',str(Path.home()/'AppData/Local/Android/Sdk')))
jdk=Path(os.environ.get('JAVA_HOME','C:/Program Files/Android/Android Studio/jbr'))
bt=sdk/'build-tools/37.0.0';jar=sdk/'platforms/android-36/android.jar'
out=S/'out';out.mkdir(exist_ok=True)
keydir=Path(os.environ.get('SPEEDBACKUP_SIGNING_DIR',str(Path.home()/'.codex/speedbackup-signing')));keydir.mkdir(exist_ok=True,parents=True)
password=keydir/'password';key=keydir/'webview-release.p12'
def run(args):
 r=subprocess.run([str(a) for a in args],capture_output=True)
 if r.returncode:raise RuntimeError(r.stderr.decode(errors='replace')+r.stdout.decode(errors='replace'))
 return r.stdout.decode(errors='replace')
embedded=S/'embedded';embedded.mkdir(exist_ok=True)
inputs=['build.py','gradlew','gradlew.bat','MainActivity.java','AndroidManifest.xml','build.gradle.kts','settings.gradle.kts','gradle.properties','app/build.gradle.kts','gradle/wrapper/gradle-wrapper.properties','gradle/wrapper/gradle-wrapper.jar']
inputs += [p.relative_to(S).as_posix() for base in ['res','app/src','third_party'] for p in sorted((S/base).rglob('*')) if p.is_file()]
source_hashes={n:hashlib.sha256((S/n).read_bytes()).hexdigest() for n in inputs}
def apk_version(apk):
 badging=run([bt/'aapt2.exe','dump','badging',apk])
 match=re.search(r"^package: name='io.github.yawasau.speedbackup.webview' versionCode='([0-9]+)'",badging,re.M)
 if not match or int(match.group(1))<=0:raise RuntimeError('Invalid native APK package/version')
 return int(match.group(1))

def sync_host_fingerprint(digest,version):
 host=S.parent/'dex/app/src/main/java/com/xayah/dex/AppListReturn.java'
 text=host.read_text(encoding='utf8')
 text,count=re.subn(r'APK_SHA="[0-9a-f]{64}"','APK_SHA="'+digest+'"',text)
 if count!=1:raise RuntimeError('Missing pinned WebView content hash')
 text,count=re.subn(r'APK_VERSION=[0-9]+;',f'APK_VERSION={version};',text)
 if count!=1:raise RuntimeError('Missing pinned native APK version')
 host.write_text(text,encoding='utf8',newline='\n')

pinned=re.search(r'CERT="([0-9a-f]{64})"',(S.parent/'dex/app/src/main/java/com/xayah/dex/AppListReturn.java').read_text()).group(1)
if not key.exists():
 apk=embedded/'speedbackup-webview.apk';meta=json.loads((embedded/'metadata.json').read_text())
 if meta['sources']!=source_hashes or meta['apk_sha256']!=hashlib.sha256(apk.read_bytes()).hexdigest():raise RuntimeError('Embedded APK is stale; rebuild with the release signing identity')
 verify=run([jdk/'bin/java.exe','-jar',bt/'lib/apksigner.jar','verify','--verbose','--print-certs',apk])
 cert=next(l.rsplit(': ',1)[1] for l in verify.splitlines() if 'certificate SHA-256 digest:' in l)
 if cert!=pinned:raise RuntimeError('Embedded APK signing identity mismatch')
 sync_host_fingerprint(meta['apk_sha256'],apk_version(apk))
 print('Verified signed embedded Native APK; no signing key distributed')
 sys.exit(0)
# Compose dependencies are shrunk with R8; private signing stays outside Gradle.
os.environ['JAVA_HOME']=str(jdk)
run([S/'gradlew.bat','-p',S,':app:assembleRelease','--console=plain'])
unsigned=S/'app/build/outputs/apk/release/app-release-unsigned.apk'
aligned=out/'aligned.apk'
run([bt/'zipalign.exe','-f','4',unsigned,aligned])
apk=out/'speedbackup-webview.apk'
run([jdk/'bin/java.exe','-jar',bt/'lib/apksigner.jar','sign','--ks',key,'--ks-key-alias','webview','--ks-pass','file:'+str(password),'--out',apk,aligned])
verify=run([jdk/'bin/java.exe','-jar',bt/'lib/apksigner.jar','verify','--verbose','--print-certs',apk]);(out/'verify.txt').write_text(verify)
cert=next(l.rsplit(': ',1)[1] for l in verify.splitlines() if 'certificate SHA-256 digest:' in l)
import re
pinned=re.search(r'CERT="([0-9a-f]{64})"',(S.parent/'dex/app/src/main/java/com/xayah/dex/AppListReturn.java').read_text()).group(1)
if cert!=pinned:raise RuntimeError('Signing certificate differs from pinned Dex identity; do not publish')
meta={'sources':source_hashes,'version':apk_version(apk),'protocol':1,'package':'io.github.yawasau.speedbackup.webview','certificate_sha256':cert,'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}
(out/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
shutil.copyfile(apk,embedded/apk.name);shutil.copyfile(out/'metadata.json',embedded/'metadata.json')
sync_host_fingerprint(meta['apk_sha256'],apk_version(apk))
print('Native APK built, independent version',meta['version'],'min API28, bytes',apk.stat().st_size)
