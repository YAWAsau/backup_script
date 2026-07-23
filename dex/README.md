SpeedBackup Dex v2.6.81 - SSAID metadata restore

目的：在 438 SSAID hardening 基礎上，修正 root/app_process 透過 SettingsState/AtomicFile 寫入 settings_ssaid.xml 後，檔案 owner/mode 可能從 system:system 0600 變成 root:root 0644 的問題。

本版只強化 SSAID metadata restore 與 AppOps effective-scope drift 容錯；不改 WebDAV/SMB/JSON/jq 主線。
