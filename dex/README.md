
## v2.4.35 / 7.66-31 source-clean-only

This source keeps the v2.4.34 notify-no-actions-single-main API surface and removes zero-call dead code from HiddenApiUtil.java: `debugMsg(String msg)`, `isPackageInstalledCached(...)`, and the now-write-only `sPackageInstalledCache` field (its 3 `.put()` call sites removed along with it, since its only reader was `isPackageInstalledCached`).

<div align="center">
	<span style="font-weight: bold"> <a> English </a> </span>
</div>

# SpeedBackup dex helper

License target: GPL-3.0-or-later.

This dex module is the Android hidden-API execution layer used by SpeedBackup. It focuses on batchable backup/restore operations instead of exposing many one-off mutation commands. Compatibility structure references RikkaW/HiddenApi and HiddenApiRefinePlugin architecture; see `THIRDPARTY_NOTICE.md`.

## Usage

```sh
unset LD_LIBRARY_PATH
export CLASSPATH="/path_to_dex/classes.dex"
app_process /system/bin com.xayah.dex.HiddenApiUtil help
app_process /system/bin com.xayah.dex.CCUtil help
app_process /system/bin com.xayah.dex.HttpUtil help
app_process /system/bin com.xayah.dex.SsaidUtil help
app_process /system/bin com.xayah.dex.NotificationUtil help
app_process /system/bin com.xayah.dex.NetworkUtil help
```

Set `APP_LABEL_LOCALE` to control app-label locale. If unset, blank, or invalid, Android system locale is used.

```sh
APP_LABEL_LOCALE=zh-TW app_process /system/bin com.xayah.dex.HiddenApiUtil getInstalledPackagesAsUser 0 user label
```

## Current public commands

### HiddenApiUtil

```text
help
version / --version / -v

getPackageUid USER_ID PACKAGE...
getPackageLabel USER_ID PACKAGE...
getPackageArchiveInfo APK_FILE
getInstalledPackagesAsUser USER_ID FILTER_FLAG(user|system|xposed) FORMAT(label|pkgName|flag)

getRuntimePermissions USER_ID PACKAGE...
getNotificationSettings USER_ID PACKAGE...
getBatterySettings USER_ID PACKAGE...
getInstaller USER_ID PACKAGE...
getInstallSourceInfo USER_ID PACKAGE...
diagnosePlayRestore USER_ID PACKAGE...
compareInstallDiagnostics USER_ID [PACKAGE VERSION_CODE SIGNING_SHA256 SPLIT_COUNT]...

precheckInstallApks PACKAGE APK_FILE...
installSessionBatch USER_ID [OPTIONS] --pkg PACKAGE APK_DIR|APK_FILE [APK_FILE ...] [--pkg PACKAGE ...]

appOpsResetBatch USER_ID --stdin|PACKAGE...
appOpsScopeDetail USER_ID [PACKAGE OP OP ...]...
restoreAppStateBatch USER_ID --stdin
verifyAppStateBatch USER_ID --stdin

forceStopPackage USER_ID PACKAGE...
forceStopPackageBatch USER_ID --stdin
fixRuntimeAppOpsAllow USER_ID [PACKAGE PERM_NAME PERM_NAME ...]...
setDisplayPowerMode MODE
```

### SsaidUtil

```text
help
get USER_ID PACKAGE
set USER_ID PACKAGE SSAID
```

### NetworkUtil

```text
help
getNetworks
saveNetworks
restoreNetworks JSON_FILE
```

### HttpUtil

```text
help
get URL
```

### NotificationUtil

```text
help
notifyBatch --stdin

flags:
  -t|--title <text>
  -p|--progress <max> <progress> <indeterminate>

notifyBatch stdin:
  EVENT|BACKUP_PROGRESS|RESTORE_PROGRESS|BACKUP_DONE|RESTORE_DONE|ERROR|WARN|DEBUG
  TAG|speedbackup
  ID|1001
  CHANNEL|progress|result|error|debug
  TITLE|SpeedBackup
  TEXT|current task
  BIGTEXT|expanded text
  PROGRESS|100|50|0
  ONGOING|1
  AUTO_CANCEL|0
  ONLY_ALERT_ONCE|1
  END
```

### CCUtil

```text
help
s2t TEXT
t2s TEXT
```

## Architecture notes

- Runtime permission, AppOps, media/location semantic modes, pflags, ask-every-time, notification settings, battery settings, and installer markers are restored through `restoreAppStateBatch --stdin`.
- Status-bar notifications use only the high-level `NotificationUtil notifyBatch --stdin` event route, with progress/result/error/debug channels. The legacy `NotificationUtil notify` command is intentionally removed.
- Post-restore verification is consolidated through `verifyAppStateBatch --stdin`.
- Explicit AppOps reset is consolidated through `appOpsResetBatch --stdin`.
- PackageInstaller session install is consolidated through `installSessionBatch`.
- Per-field mutation commands are intentionally not public API. Keep the public surface small; batch commands are the stable integration contract.

## Build note

This source package requires `gradle/libs.versions.toml`. It is included in the build-fix package so Gradle can resolve the `libs.*` aliases used by `build.gradle.kts`.


## Notification no-actions mode

Current notification path is `NotificationUtil notifyBatch --stdin` only. It does not require installing a companion APK and does not display pause/stop/log/folder action buttons. Main notifications are normalized to `speedbackup_main/2020`; error aggregation uses `speedbackup_error/2021`.
