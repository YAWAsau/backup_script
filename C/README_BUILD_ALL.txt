SpeedBackup native tools all-binary build pack

Build type in this pack:
  arm64 dynamic PIE
  INTERP: /system/bin/linker64
  NEEDED: libc.so required; libdl.so allowed
  LOAD alignment: 0x4000 / 16 KB aligned

Build on Windows:
  build_all_windows.bat

Override NDK path if needed:
  set EVENT_TOOLS_NDK_ROOT=D:\Android\android-ndk-r25c
  build_all_windows.bat

Or:
  set ANDROID_NDK_HOME=C:\Users\22995\AppData\Local\Android\Sdk\ndk\25.2.9519653
  build_all_windows.bat

Outputs:
  out\filewatch
  out\propwait
  out\procwait
  out\unixsock
  out\netwatch
  out\uidexec
  out\SHA256SUMS.txt

Verification performed by build_all_windows.bat:
  Type must be DYN.
  Program interpreter must be /system/bin/linker64.
  Dynamic dependencies must include libc.so; libdl.so is allowed; anything else is rejected.
  All LOAD segments must be aligned to 0x4000.

uidexec.c in this pack is the original-interface hardened variant:
  uidexec <uid> <gid> <android_data_dir> -- <cmd> [args...]
  uidexec <uid> <gid> <android_data_dir> <classpath> <cmd> [args...]
  uidexec <uid> <gid> <android_data_dir> --classpath <classpath> -- <cmd> [args...]


Verifier note:
- build_all_windows.bat calls verify_elf_dynamic16k.ps1 for ELF checks.
- This avoids inline PowerShell escaping issues around 2>&1 and pipelines inside .bat files.
