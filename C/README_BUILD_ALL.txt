SpeedBackup native tools all-binary build pack

Build on Windows:
  build_all_windows.bat

Override NDK path if needed:
  set EVENT_TOOLS_NDK_ROOT=D:\Android\android-ndk-r25c
  build_all_windows.bat

Outputs:
  out\filewatch
  out\propwait
  out\procwait
  out\unixsock
  out\netwatch
  out\uidexec
  out\SHA256SUMS.txt

uidexec.c in this pack is the original-interface hardened variant:
  uidexec <uid> <gid> <android_data_dir> -- <cmd> [args...]
  uidexec <uid> <gid> <android_data_dir> <classpath> <cmd> [args...]
  uidexec <uid> <gid> <android_data_dir> --classpath <classpath> -- <cmd> [args...]
