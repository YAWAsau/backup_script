"""Create/reuse a developer-owned APK signing identity and pin its public certificate."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import secrets
import subprocess

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    args = parser.parse_args()
    directory = args.directory.expanduser().resolve()
    if directory.is_relative_to(ROOT):
        raise ValueError('Signing keys must be stored outside the repository')
    jdk = Path(os.environ['JAVA_HOME'])
    suffix = '.exe' if os.name == 'nt' else ''
    keytool = jdk / 'bin' / ('keytool' + suffix)
    directory.mkdir(parents=True, exist_ok=True)
    key, password = directory / 'webview-release.p12', directory / 'password'
    if key.exists() != password.exists():
        raise ValueError('Incomplete signing identity; restore its matching key and password')
    if not key.exists():
        password.write_text(secrets.token_hex(32), encoding='ascii')
        password.chmod(0o600)
        subprocess.run([str(keytool), '-genkeypair', '-keystore', str(key), '-storetype', 'PKCS12',
            '-storepass:file', str(password), '-keypass:file', str(password), '-alias', 'webview',
            '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
            '-dname', 'CN=SpeedBackup Local Build', '-noprompt'], check=True)
        key.chmod(0o600)
    certificate = subprocess.check_output([str(keytool), '-exportcert', '-keystore', str(key),
        '-storepass:file', str(password), '-alias', 'webview'])
    digest = hashlib.sha256(certificate).hexdigest()
    host = ROOT / 'dex/app/src/main/java/com/xayah/dex/AppListReturn.java'
    source, count = re.subn(r'CERT="[0-9a-f]{64}"', 'CERT="' + digest + '"', host.read_text(encoding='utf8'))
    if count != 1:
        raise ValueError('Missing or ambiguous Dex certificate pin')
    host.write_text(source, encoding='utf8', newline='\n')
    print('Developer signing identity configured; certificate SHA256: ' + digest)


if __name__ == '__main__':
    main()
