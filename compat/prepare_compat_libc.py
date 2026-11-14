"""Create a private NDK r30 libc.a with stateless kernel-backed arc4random."""
from pathlib import Path
import hashlib,shutil,subprocess

def prepare(ndk, output):
 ndk=Path(ndk);output=Path(output);output.mkdir(parents=True,exist_ok=True)
 assert '30.0.16248370' in (ndk/'source.properties').read_text()
 tc=ndk/'toolchains/llvm/prebuilt/windows-x86_64'
 source=tc/'sysroot/usr/lib/aarch64-linux-android/libc.a'
 c=Path(__file__).with_name('arc4random_kernel.c');obj=output/'arc4random.o';dest=output/'libc.a'
 subprocess.run([str(tc/'bin/clang.exe'),'--target=aarch64-linux-android28','-O2','-fPIC','-ffunction-sections','-fdata-sections','-c',str(c),'-o',str(obj)],check=True)
 members=subprocess.check_output([str(tc/'bin/llvm-ar.exe'),'t',str(source)],text=True).splitlines()
 assert members.count('arc4random.o')==1
 shutil.copyfile(source,dest)
 subprocess.run([str(tc/'bin/llvm-ar.exe'),'r',str(dest),str(obj)],check=True)
 return {'kind':'stateless-getrandom-arc4random-v1','source_libc_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'private_libc_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'compat_source_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'runtime_compatibility_changed':True,'installed_ndk_unchanged':True}
