SpeedBackup Dex v2.6.97 - AppInventory source path cache / unified root daemon

Changes:
- Adds AppInventoryUtil snapshot API.
- HiddenApiUtil exposes `appInventorySnapshot USER_ID [jsonl|appinfo|pkgName|pkgVerMap|pkgUidMap] [user|system|xposed|all] [refresh]`.
- SpeedBackupRootDaemon HiddenApi namespace reuses AppInventory cache within the same process/run.
- Inventory fields include packageName, label, uid, versionCode, versionName, enabled, installed, system, updatedSystem, xposed, sourceDir and splitCount.
- tools.sh r43 routes Getlist, pkg version map, uid map and installed package map through AppInventory first, with existing pm/Dex fallbacks preserved.
- Retains v2.6.95 AppOps location verify and all previous WebDAV/AppState/root-daemon capabilities.

Dex requirement for tools r43:
`v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify`

Build with `build_dex.ps1`, then replace `tools/classes.dex` together with the r43 tools package.
