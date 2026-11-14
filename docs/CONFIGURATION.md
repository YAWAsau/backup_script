# 設定檔參考

[返回首頁](../README.md) · [使用指南](USER_GUIDE.md) · [設定參考](CONFIGURATION.md) · [常見問題](FAQ.md) · [架構說明](ARCHITECTURE.md)

## 進階：設定檔欄位參考

一般操作請在 App 的「備份設定」或「恢復設定」調整並儲存，不必手動編輯檔案。以下列出 `backup_settings.conf` 的儲存值，供進階使用、舊設定遷移及排查問題。請勿在工作執行中或編輯頁仍有草稿時從外部改寫設定檔。

| 設定項 | 說明 | 常用值 / 預設 |
|--------|------|---------------|
| `low_battery_mode` | 低電量行為：`1` 強制拒絕、`2` 不提示繼續、留空在開始時由 App 提示確認 | 留空 |
| `background_execution` | 背景模式與互動策略：`1` 啟用、`0` 關閉；原生介面的工作啟動後可關閉終端，不以此設定作為接回開關 | `0` |
| `notification_enable` | 狀態欄通知與進度條：`1` 開啟、`0` 關閉 | `1` |
| `Shell_LANG` | 語言：`0` 繁體中文、`1` 簡體中文、留空自動偵測 | 留空 / `0` |
| `setDisplayPowerMode` | 備份 / 恢復期間偽裝亮屏，避免 IO 因息屏降速 | `0` |
| `Output_path` | 自定義備份輸出位置，支援相對路徑 | 空 |
| `Backup_suffix` | 自定義備份目錄後綴，支援日期時間變數 | 空 |
| `list_location` | 自定義 `appList.txt` 位置 | 空 |
| `update` | 自動更新：`1` 開啟、`0` 關閉 | `1` |
| `cdn` | 更新 CDN 節點：`0` 直連、`1` ghfast、`2` workers | 新建設定 `1` |
| `mount_point` | 屏蔽外部掛載點，多個用 `\|` 分隔 | 自訂 |
| `user` | 指定 Android 使用者 ID，例如 `0`、`999`；留空時自動判斷或詢問 | 空 |
| `Backup_Mode` | `1` 應用 + 資料、`0` 僅安裝包 | `1` |
| `Backup_user_data` | 是否備份 `/data/user/<user>/<package>` | `1` |
| `Backup_obb_data` | 是否備份 OBB / data 外部資料 | `1` |
| `backup_media` | App 備份後是否一併備份自定義資料夾 | `0` |
| `backup_messages` / `backup_calllogs` | 備份簡訊／MMS與通話紀錄，依系統 Provider 能力處理 | `1` |
| `Background_apps_ignore` | 正在運行中的應用：`1` 忽略、`0` 嘗試停止後備份 | `0` |
| `Custom_path` | 自定義備份路徑，每行一個絕對路徑 | 依需求 |
| `blacklist_mode` | 黑名單：`1` 完全忽略、`0` 僅備份安裝包 | `0` |
| `blacklist` | 黑名單應用包名，每行一項；列表生成會忽略註解中的包名 | 空 |
| `whitelist` | 預裝應用白名單，每行一項；不覆蓋黑名單優先順序 | 依需求 |
| `system` | 系統應用白名單 | 依需求 |
| `Compression_method` | App 資料使用 `zstd` 或 `tar`；一般 Media／自定義目錄另走 tar 僅打包 | `zstd` |
| `Zstd_level` | 壓縮等級 `1`～`22`；`20`～`22` 會啟用 ultra | `6` |
| `Zstd_threads` | 一般壓縮執行緒 `0`～`64`；`0` 自動使用可用核心 | 新建與缺少欄位補齊均為 `0` |
| `Zstd_small_max_bytes` | 已知 tar 輸入不超過此大小時使用小檔執行緒；`0` 關閉切換 | `1048576`（1 MiB） |
| `Zstd_small_threads` | 小檔使用的執行緒數，與 `--single-thread` 不同 | `1` |
| `Zstd_size_hint` | 使用既有大小計畫提供壓縮提示，不另外掃描 | `1` |
| `rgb_a` / `rgb_b` / `rgb_c` | 終端輸出主色與輔色，使用 256 色 ANSI 編號 | `220` / `51` / `213` |
| `remote_type` | 遠端備份類型：`webdav`、`smb`，留空不啟用 | 空 |
| `smb_url` | SMB 伺服器地址，例如 `smb://192.168.1.100/Backup` | 空 |
| `smb_remote_user` | SMB 認證用戶名 | 空 |
| `smb_remote_pass` | SMB 認證密碼 | 空 |
| `webdav_url` | WebDAV 地址，例如 `http://192.168.1.100:8080/dav/` | 空 |
| `webdav_remote_user` | WebDAV 認證用戶名 | 空 |
| `webdav_remote_pass` | WebDAV 認證密碼 | 空 |
| `remote_stream` | 流式備份：`1` 邊壓邊傳、`0` 先本地備份再上傳 | `0` |
| `remote_keep_local` | 非流式上傳成功後：`1` 保留本地資料包、`0` 刪除；不會讓流式備份額外保存整包 | `0` |
| `remote_upload_per_app` | 每個 App 備份後立即上傳，非流式模式下節省空間 | `0` |
| `log_max_size_mb` | `log/` 目錄大小上限，留空或 `0` 關閉自動清理 | 新建設定留空；舊設定缺項補入 `1` |
