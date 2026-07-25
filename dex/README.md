SpeedBackup Dex v2.6.94 - HiddenApi synchronized / root-only daemon cleanup / WebDAV deep policy

Changes:
- WebDavUtil `ensurebaserel`: configured URL split, STAT, 404-only parent-chain MKCOL and final verification inside the daemon.
- Shell no longer owns the configured-base path state machine.
- Removed the unused `libsardine/` source tree; it was not included by settings.gradle.kts and was not part of classes.dex.
- Retains v2.6.88 localization repeat/merge fixes and all AppState/SSAID/WebDAV capabilities.

Build with `build_dex.ps1`, then replace `tools/classes.dex` together with the 460 single-tools shell package.

## v2.6.91

- `ensuredirrel`: relative collection STAT / 404-only parent MKCOL / final verify in Dex.
- `optionspreflightrel`: OPTIONS policy and advisory Allow-method analysis in Dex.
- Shell retains transport, logs, jq/app_details and backup/restore orchestration.


## v2.6.94

- HiddenApiUtil.runDaemonCommand() 改為 synchronized，配合 SpeedBackupRootDaemon concurrentClients=true，避免 hiddenapi HashMap cache 併發讀寫風險。
- 對應 tools 7.66-465 r16：HiddenApi/AppState/Notify 舊獨立 daemon fallback 清理。

- Adds SpeedBackupRootDaemon unified root-side AF_UNIX daemon for HiddenApi/AppState/Notification, with tools.sh fallback to legacy component daemons.
- Adds capability markers dex.root_unified_daemon.v1 and webdav.deep_policy_table.dex.v1.


## SpeedBackup 464 r3

Keeps `com.xayah.dex.SpeedBackupRootDaemon` in release/R8 output so `build_dex.ps1` verification succeeds.
