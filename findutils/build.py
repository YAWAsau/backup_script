"""Build the pinned GNU findutils archive for Android ARM64/API28/16KiB.

Uses the same private Bionic compatibility CRT as the bundled GNU tar.
Build directories are private ASCII staging directories and retained on failure.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys, tarfile, tempfile

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / 'tar'))
from android_build_note import prepare_static_crt, describe_static_android_build
from build import verify_elf, msys, CONFIGURE_ENV, REVISION

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ndk', type=Path, default=Path.home()/'AppData/Local/Android/Sdk/ndk'/REVISION)
    ap.add_argument('--msys', type=Path, default=Path('C:/msys64'))
    ap.add_argument('--jobs', type=int, default=8)
    args = ap.parse_args()
    assert args.jobs > 0
    ndk = args.ndk.resolve()
    assert 'Pkg.Revision = '+REVISION in (ndk/'source.properties').read_text()
    info = json.loads((ROOT/'source.json').read_text())
    archive = ROOT/('findutils-'+info['version']+'.tar.xz')
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == info['sha256']
    stage = Path(tempfile.mkdtemp(prefix='sbfind-')).resolve()
    assert str(stage).isascii() and "'" not in str(stage)
    print('Build stage:', stage, flush=True)
    with tarfile.open(archive) as tf:
        tf.extractall(stage, filter='data')
    src = stage/('findutils-'+info['version'])
    # Preserve release-generated autotools files; do not regenerate with host versions.
    for p in src.rglob('*'):
        if p.is_file() and not p.is_symlink(): os.utime(p, (1783747440,1783747440))
    crt, crt_info = prepare_static_crt(ndk, stage/'crt')
    tool = ndk/'toolchains/llvm/prebuilt/windows-x86_64/bin'
    env = dict(CONFIGURE_ENV)
    env.update(CC=msys(tool/'clang.exe')+' --target=aarch64-linux-android28',
               AR=msys(tool/'llvm-ar.exe'), RANLIB=msys(tool/'llvm-ranlib.exe'),
               NM=msys(tool/'llvm-nm.exe'),
               CFLAGS='-O2 -fPIE -ffunction-sections -fdata-sections -Dtzalloc=sb_find_tzalloc -Dtzfree=sb_find_tzfree',
               LDFLAGS='-static -no-pie -Wl,--gc-sections -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -B'+crt.parent.as_posix()+'/ -L'+crt.parent.as_posix(),
               FORCE_UNSAFE_CONFIGURE='1')
    script=['#!/usr/bin/bash','set -eu','export PATH=/usr/bin:/bin','export LC_ALL=C','export TZ=UTC','export SOURCE_DATE_EPOCH=1783747440']
    for k,v in env.items():
        assert "'" not in v
        script.append("export "+k+"='"+v+"'")
    script += ["cd '"+msys(src)+"'", './configure --build=x86_64-pc-msys --host=aarch64-linux-android --disable-nls --without-selinux',
               'make -j'+str(args.jobs)+' -C gl/lib', 'make -j'+str(args.jobs)+' -C lib', 'make -j'+str(args.jobs)+' -C find find']
    (stage/'build.sh').write_text('\n'.join(script)+'\n',encoding='utf-8',newline='\n')
    subprocess.run([str(args.msys/'usr/bin/bash.exe'),'--noprofile','--norc',msys(stage/'build.sh')],check=True)
    out=ROOT/'out';out.mkdir(exist_ok=True)
    binary=src/'find/find'
    if not binary.exists(): binary=src/'find/find.exe'
    shutil.copy2(binary,out/'find')
    subprocess.run([str(tool/'llvm-strip.exe'),'--strip-all',str(out/'find')],check=True)
    manifest=dict(source=info,elf=verify_elf(out/'find'),android=describe_static_android_build(out/'find',ndk,REVISION,private_crt=crt),crt=crt_info,configure_environment=env)
    (out/'BUILD_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('Built',out/'find','; runtime tests required. Stage retained:',stage)

if __name__=='__main__': main()
