# Backup_script 數據備份腳本

<p align="center">
 <a href="https://github.com/YAWAsau/backup_script/stargazers"><img src="https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars&style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases"><img src="https://img.shields.io/github/downloads/YAWAsau/backup_script/total?style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases/latest"><img src="https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release&style=flat-square" /></a>
 <a href="https://choosealicense.com/licenses/gpl-3.0"><img src="https://img.shields.io/github/license/YAWAsau/backup_script?label=License&style=flat-square" /></a>
 <a href="https://t.me/yawasau_script"><img src="https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram&style=flat-square" /></a>
</p>

---

## 概述

Backup_script 是一款專為 Android 設計的完整應用數據備份／恢復 Shell 腳本，支援應用資料、Split APK、SSAID、運行時權限、AppOps、特殊存取、電池策略、安裝來源、OBB 數據包、Wi-Fi 設定與自定義資料夾備份。適合換機、刷機、重裝系統後快速還原應用狀態。

腳本提供本地備份與遠端備份兩種模式。遠端備份支援 WebDAV / SMB，可上傳到 NAS、區網電腦、rclone serve webdav、Nextcloud 等服務，也可從遠端下載備份回手機後直接恢復。

新版支援流式備份：資料可直接 `tar | zstd | 傳輸`，不需要先落地成本機壓縮包，適合本機空間不足的裝置。對於沒有變化的應用，腳本會透過版本、資料大小、AppState、SSAID 與遠端檔案狀態進行 fast-skip，避免重複壓縮與重複上傳。

> 作者為台灣人，預設發布繁體版本。簡體中文環境下腳本可自動切換語言。

**系統需求：** `Android 8+` · `arm64 架構` · `Root 權限(Magisk / KernelSU)`

---

## 功能特色

| 功能 | 說明 |
|------|------|
| 完整數據備份 | 備份應用資料、APK、Split APK、user / user_de / data / OBB 等資料 |
| 完整恢復 | 支援批量恢復與單 App 恢復，恢復後自動校驗 AppState |
| Play 商店來源還原 | 支援恢復 installer / install source，使應用在系統中正確顯示來源 |
| SSAID 備份與恢復 | 支援備份與恢復 Android SSAID，適合 LINE 等依賴設備識別碼的應用 |
| 權限與 AppOps | 支援運行時權限、AppOps、特殊存取、電池策略等狀態備份與恢復 |
| 舊 JSON 相容 | 舊版 `app_details.json` 會自動轉換為新版 AppState restore record，不需手動轉檔 |
| Split APK | 支援多 split APK 備份與恢復 |
| OBB 數據包 | 可選備份外部 OBB 數據，如大型遊戲資料包 |
| Wi-Fi 備份 | 支援 Wi-Fi 設定備份與恢復 |
| 自定義資料夾 | 可備份與恢復 DCIM、Download、Music 等任意自定義目錄 |
| 壓縮方式 | 支援 `zstd` 壓縮與 `tar` 僅打包 |
| 增量備份 | 多維度比對版本、資料大小、權限、SSAID、AppState，無變化則跳過 |
| 全量 fast-skip | 本地 / WebDAV / SMB 全部無變化時可整批折疊跳過，不進逐 App 主流程 |
| 遠端備份 | 支援 WebDAV / SMB 備份、下載、恢復、列表與健康檢查 |
| 流式備份 | 邊壓縮邊傳輸，資料不落本機，節省本地空間 |
| 遠端預掃 | 遠端備份前批量取得遠端列表與 JSON，降低主循環網路開銷 |
| 遠端 JSON 健康檢查 | 遠端 `app_details.json` 缺失或損壞會列出清單，不靜默忽略 |
| SMB 掃描 | 自動掃描區網 SMB 主機與 share，免手動找 IP |
| WebDAV 相容 | 支援逐層建目錄、PUT/MOVE/STAT/GET 校驗、404 非致命判斷等 WebDAV 相容處理 |
| 日誌與 debug 包 | 自動生成 speed_debug 診斷包，legacy `log/log_yyyy-mm-dd_hh-mm.txt` 會同步主日誌摘要 |
| 後台執行 | 支援後台執行模式，log 持續刷新 |
| 狀態通知 | 支援備份 / 恢復進度與結果通知 |
| 多用戶支援 | 支援 user 0、999 等多用戶環境，可指定或自動選擇用戶 |
| 設定檔自動修補 | 升級後自動補齊 `backup_settings.conf` 缺少項目，不需手動重寫 |
| 自動更新 | 支援本地 ZIP 更新、Download / QQ 下載目錄檢測與 GitHub release 檢查 |
| 完整性校驗 | 內建工具 SHA-256 校驗、壓縮包完整性檢查與最終檔案核驗 |
| 啟動自我檢測 | `dex_check.sh` 檢測目前 Dex 能力與 tools.sh 使用的 Dex route |

---

## 主選單功能

### 備份模式

| 選項 | 功能 |
|------|------|
| 生成應用列表 | 掃描可備份應用並生成 `appList.txt` |
| 備份應用 | 根據列表與設定完整備份應用與資料 |
| 備份已更新應用 | 僅備份自上次備份後版本有變化的應用 |
| 備份自定義資料夾 | 備份 `backup_settings.conf` 中設定的自定義目錄 |
| 備份 Wi-Fi | 備份目前設備的 Wi-Fi 設定 |
| 測試遠端連線 | 驗證 WebDAV / SMB 設定與寫入能力 |
| 單獨上傳當前備份 | 將現有本地備份同步到遠端，不重新執行備份 |
| 列出遠端備份 | 連線遠端並產生 `appList_network.txt` |
| 從遠端下載備份 | 依清單下載遠端備份到本地，可直接恢復 |
| 殺死運行中腳本 | 安全終止正在執行的備份腳本進程樹 |

### 恢復模式

| 選項 | 功能 |
|------|------|
| 重新生成應用列表 | 刷新恢復資料夾內的 `appList.txt` |
| 恢復備份 | 根據列表完整恢復應用、資料與 AppState |
| 僅恢復包含 SSAID 應用(含數據) | 只恢復有 SSAID 的應用與完整資料 |
| 僅恢復包含 SSAID 應用(不含數據) | 只套用 SSAID，不覆蓋現有資料 |
| 恢復自定義資料夾 | 恢復備份的自定義目錄 |
| 恢復 Wi-Fi | 恢復已備份的 Wi-Fi 設定 |
| 壓縮檔完整性檢查 | 驗證備份壓縮包是否完整無損 |
| 轉換文件夾名稱 | 將備份資料夾名稱格式轉換，用於跨版本相容 |
| 殺死運行中腳本 | 安全終止正在執行的恢復腳本進程樹 |

---

## 目錄結構

```text
backup_script.zip
│
├── tools/
│   ├── busybox        # 核心工具集
│   ├── zstd           # zstd 壓縮工具
│   ├── tar            # tar 打包工具
│   ├── smbclient      # SMB 遠端傳輸
│   ├── jq             # JSON 處理
│   ├── find           # 檔案搜尋
│   ├── keycheck       # 音量鍵監聽
│   ├── cmd            # 系統指令橋接
│   ├── uidexec        # 指定 UID 執行輔助工具
│   ├── unixsock       # AF_UNIX socket 輔助工具
│   ├── filewatch      # 檔案狀態輔助工具
│   ├── procwait       # 進程等待輔助工具
│   ├── classes.dex    # Java / Dex 功能擴展
│   ├── soc.json       # 處理器資料庫
│   ├── Device_List    # 設備型號資料庫
│   └── tools.sh       # 核心腳本
│
├── backup_settings.conf # 備份行為設定檔
├── dex_check.sh         # Dex 能力與 route 自檢
└── start.sh             # 主執行入口
```

> **重要：** 無論備份或恢復，都必須確保 `tools/` 目錄完整存在，否則腳本可能無法正常運作。

備份完成後，每個 App 子目錄會生成 `backup.sh` / `recover.sh` / `upload.sh`，可單獨備份、恢復或上傳單一應用。

---

## 設定檔說明(`backup_settings.conf`)

| 設定項 | 說明 | 常用值 / 預設 |
|--------|------|---------------|
| `low_battery_mode` | 低電量行為：`1` 強制拒絕、`2` 不提示繼續、留空音量鍵選擇 | 留空 |
| `keyboard_input` | `1` 改用鍵盤輸入確認，留空使用音量鍵 | 留空 |
| `background_execution` | 後台執行：`1` 可關閉終端、`0` 保持終端顯示 | `0` |
| `notification_enable` | 狀態欄通知與進度條：`1` 開啟、`0` 關閉 | `1` |
| `Shell_LANG` | 語言：`0` 繁體中文、`1` 簡體中文、留空自動偵測 | 留空 / `0` |
| `setDisplayPowerMode` | 備份 / 恢復期間偽裝亮屏，避免 IO 因息屏降速 | `0` |
| `Output_path` | 自定義備份輸出位置，支援相對路徑 | 空 |
| `Backup_suffix` | 自定義備份目錄後綴，支援日期時間變數 | 空 |
| `list_location` | 自定義 `appList.txt` 位置 | 空 |
| `update` | 自動更新：`1` 開啟、`0` 關閉 | `1` |
| `cdn` | 更新 CDN 節點：`0` 直連、`1` ghfast、`2` workers | `0` |
| `mount_point` | 屏蔽外部掛載點，多個用 `|` 分隔 | 自訂 |
| `user` | 指定 Android 使用者 ID，例如 `0`、`999`；留空時自動判斷或詢問 | 空 |
| `Backup_Mode` | `1` 應用 + 資料、`0` 僅安裝包 | `1` |
| `Backup_user_data` | 是否備份 `/data/user/<user>/<package>` | `1` |
| `Backup_obb_data` | 是否備份 OBB / data 外部資料 | `1` |
| `backup_media` | App 備份後是否一併備份自定義資料夾 | `0` |
| `Background_apps_ignore` | 正在運行中的應用：`1` 忽略、`0` 嘗試停止後備份 | `0` |
| `Custom_path` | 自定義備份路徑，每行一個絕對路徑 | 依需求 |
| `blacklist_mode` | 黑名單：`1` 完全忽略、`0` 僅備份安裝包 | `0` |
| `blacklist` | 黑名單應用包名列表 | 空 |
| `whitelist` | 預裝應用白名單 | 依需求 |
| `system` | 系統應用白名單 | 依需求 |
| `Compression_method` | 壓縮方式：`zstd` 或 `tar`；`tar` 僅打包不壓縮 | `zstd` |
| `rgb_a` / `rgb_b` / `rgb_c` | 終端輸出主色與輔色，使用 256 色 ANSI 編號 | `220` / `51` / `213` |
| `remote_type` | 遠端備份類型：`webdav`、`smb`，留空不啟用 | 空 |
| `smb_url` | SMB 伺服器地址，例如 `smb://192.168.1.100/Backup` | 空 |
| `smb_remote_user` | SMB 認證用戶名 | 空 |
| `smb_remote_pass` | SMB 認證密碼 | 空 |
| `webdav_url` | WebDAV 地址，例如 `http://192.168.1.100:8080/dav/` | 空 |
| `webdav_remote_user` | WebDAV 認證用戶名 | 空 |
| `webdav_remote_pass` | WebDAV 認證密碼 | 空 |
| `remote_stream` | 流式備份：`1` 邊壓邊傳、`0` 先本地備份再上傳 | `0` |
| `diagnostic_mode` | 診斷模式：`1` 保留更多排查資料、`0` 一般使用 | `0` |
| `remote_keep_local` | 遠端備份完成後是否保留本地檔案 | `1` / 依需求 |
| `remote_upload_per_app` | 每個 App 備份後立即上傳，非流式模式下節省空間 | `0` |
| `log_max_size_mb` | `log/` 目錄大小上限，留空或 `0` 關閉自動清理 | `1` |

---

## 使用方式

> 推薦使用 MT 管理器或其他可授權 Root 的終端環境執行 `start.sh`。若使用 Termux，請直接授權 Root，不建議使用 `tsu` 包一層執行。

### 備份流程

**Step 1 — 生成應用列表**

解壓後執行 `start.sh`，選擇「生成應用列表」。執行完畢後，當前目錄會生成 `appList.txt`。

**Step 2 — 編輯應用列表**

打開 `appList.txt`，依需求調整：

- 行首加 `#`：注釋該應用，不備份
- 行首加 `!`：僅備份安裝包，不備份資料

**Step 3 — 調整設定檔**

編輯 `backup_settings.conf`，設定使用者、備份項目、遠端地址、流式備份與自定義路徑。

**Step 4 — 執行備份**

執行 `start.sh`，選擇「備份應用」。備份完成後會生成 `Backup_<壓縮方式>_<用戶ID>/` 目錄，例如 `Backup_zstd_0/`。

---

### 恢復流程

**Step 1 — 編輯恢復列表**

進入備份資料夾，打開 `appList.txt`，刪除或注釋不需要恢復的應用。

**Step 2 — 執行恢復**

執行備份資料夾內的 `start.sh`，選擇「恢復備份」。腳本會依列表恢復 APK、資料、SSAID、權限、AppOps、特殊存取、電池策略與安裝來源。

**Step 3 — 依提示重啟**

若恢復結束後提示存在 SSAID，建議立刻重啟後再開啟應用。若先開啟應用，Android 可能生成新的 SSAID，導致部分應用需要重新登入或狀態異常。

> 備份資料夾內每個應用子目錄都有 `backup.sh`、`recover.sh`、`upload.sh`，可單獨操作單一應用。

---

## 遠端備份

### 設定方式

SMB 與 WebDAV 地址分開設定，切換 `remote_type` 時不需要重複輸入另一種協議的地址：

```conf
remote_type=webdav

smb_url=smb://192.168.1.100/Backup
smb_remote_user=用戶名
smb_remote_pass=密碼

webdav_url=http://192.168.1.100:8080/dav/
webdav_remote_user=用戶名
webdav_remote_pass=密碼

remote_stream=1
remote_keep_local=1
```

| 協議 | 地址格式 | 適用場景 |
|------|----------|---------|
| SMB | `smb://192.168.1.100/share/path` | Windows 共享 / Samba / NAS |
| WebDAV | `http://192.168.1.100:8080/dav/` | NAS / Nextcloud / rclone serve webdav |

### 遠端目錄結構

腳本會在遠端地址下建立 `Backup_<壓縮方式>_<用戶ID>/`，與本地結構保持一致：

```text
Backup_zstd_0/
├── LINE/
│   ├── apk.tar.zst
│   ├── user.tar.zst
│   ├── user_de.tar.zst
│   ├── app_details.json
│   ├── backup.sh
│   ├── recover.sh
│   └── upload.sh
├── wifi/
│   └── wifi.json
├── tools/
├── start.sh
├── restore_settings.conf
└── appList.txt
```

不同 Android 使用者會分開到不同目錄，例如 `Backup_zstd_0/`、`Backup_zstd_999/`。

### 遠端備份特性

- **流式備份**：`remote_stream=1` 時，資料直接壓縮並傳輸到遠端，本地不落壓縮包。
- **遠端 fast-skip**：若遠端資料、版本、AppState 與檔案狀態都未變化，會整批跳過。
- **遠端 JSON 健康檢查**：缺失、損壞或格式不合法的 `app_details.json` 會列出清單。
- **失敗保護**：流式上傳失敗時不更新遠端 JSON，避免下輪誤判已備份完成。
- **WebDAV 目錄建立**：會逐層建立遠端目錄並 verify，降低不同 WebDAV server 的相容問題。
- **SMB 寫入預檢**：正式備份前會測試遠端目錄建立與寫入能力。

---

## 流式備份模式

`remote_stream=1` 啟用後，資料直接走：

```text
tar → zstd → WebDAV / SMB
```

優點：

- 不佔用本機壓縮包空間
- 適合本機剩餘空間不足的裝置
- 支援 WebDAV / SMB
- 支援遠端 fast-skip 與最終檔案核驗

限制：

- 傳輸過程依賴網路穩定性
- 本地不保留壓縮包時，無法做本地 tar/zstd 完整性校驗
- 若遠端上傳失敗，該 App 會保留失敗狀態，下輪重新備份

---

## 從遠端下載備份

**Step 1 — 列出遠端備份**

主選單選「列出遠端備份」，產生 `appList_network.txt`。

**Step 2 — 編輯下載列表**

打開 `appList_network.txt`，用 `#` 註解掉不需要下載的應用。

**Step 3 — 從遠端下載備份**

主選單選「從遠端下載備份」。下載完成後，直接執行下載資料夾中的 `start.sh` 進行恢復。

---

## 舊版 JSON 相容

新版恢復流程支援舊版 `app_details.json`。若舊 JSON 沒有新版 `app_state` 欄位，但仍保留：

```text
permissions
battery_settings
Ssaid
installer / install_diagnostics
apk_version
PackageName
user / user_de / data Size
```

腳本會在恢復時自動轉換為新版 AppState restore record，等效於：

```text
sourceFormat=legacy-app-details-migrated
recordType=snapshot
schemaVersion=2
```

也就是舊備份不需要手動轉檔。舊 JSON 已有的 SSAID、權限、AppOps、電池策略與安裝來源會盡量恢復；舊 JSON 本來沒有的新欄位則無法憑空補出。

---

## AppState / Dex 功能

`classes.dex` 用於實現 Shell 難以穩定完成的系統操作。目前主要負責：

- AppState snapshot / restore / verify
- SSAID 備份與恢復輔助
- 運行時權限、AppOps、特殊存取、電池策略狀態處理
- 安裝來源、installer、Play 來源恢復輔助
- App 名稱、包名、版本、split 資訊查詢
- WebDAV rel API、AF_UNIX daemon 與傳輸輔助
- SMB 主機與 share 掃描輔助
- 通知批量更新
- 權限 / AppOps / 特殊存取中文語意輸出

啟動自檢由 `dex_check.sh` 執行，只檢查目前 Dex 版本實際具備的能力與 `tools.sh` 當前使用的 Dex route。

---

## 腳本更新方式

1. **本地 ZIP 更新**：將完整 release `.zip` 不解壓，放到腳本目錄或其上層目錄，執行腳本時自動檢測更新。
2. **Download 目錄更新**：將完整 release `.zip` 放到 `/storage/emulated/0/Download/`，執行腳本時自動檢測。
3. **QQ 下載目錄更新**：從 QQ 下載的完整 release `.zip` 可直接放置後執行腳本更新。
4. **聯網自動更新**：`update=1` 時會檢查 GitHub release。

更新規則：

- 本地完整 release 同版本允許覆蓋更新，成功後刪除更新 ZIP。
- 低於目前版本的 ZIP 會拒絕更新。
- 線上 release 與本地版本相同時不提示新版。
- 更新只同步 release 內工具與入口檔，不會刪除既有備份資料。
- 更新失敗、拒絕或中止時會清理 `/data/local/tmp` 更新暫存。

> 腳本聯網僅用於檢查更新，不會收集或上傳使用者資料。

---

## 日誌與 debug

一般使用時，腳本會在 `log/` 目錄生成 legacy log，例如：

```text
log/log_2026-07-25_21-40.txt
```

同時，完整診斷資料會打包到 speed_debug：

```text
/data/speed_debug/speed_debug_yyyyMMdd-HHmmss.tar
```

排查問題時，請優先提供 speed_debug tar。裡面通常包含：

- `main.log`：主流程日誌
- `stderr.log`：Shell stderr，0KB 通常代表沒有錯誤
- `root_daemon_stderr.log`：Root daemon stderr，0KB 通常代表沒有錯誤
- `webdav_daemon_stderr.log`：WebDAV daemon stderr，0KB 通常代表沒有錯誤
- `app_state_output.log`：AppState restore 輸出
- `verify_app_state_output.log`：AppState verify 輸出
- `stream_upload.log` / `stream_download.log`：流式上傳 / 下載日誌
- `extract.log`：恢復解壓日誌

---

## 常見問題

<details>
<summary><b>Q1：批量備份 / 恢復大量提示失敗？</b></summary>

請先查看 `/data/speed_debug/` 內最新 debug 包。若是工具殘留或權限異常，可嘗試刪除 `/data/backup_tools/` 後重新執行。若仍失敗，請提交 speed_debug tar。
</details>

<details>
<summary><b>Q2：微信 / QQ 能完美備份恢復嗎？</b></summary>

無法保證。大型即時通訊 App 可能有服務常駐、資料庫鎖、伺服器校驗或加密狀態。建議同時使用你信任的官方或第三方方式額外備份重要資料。
</details>

<details>
<summary><b>Q3：為什麼部分應用備份很久？</b></summary>

可能是 user data、user_de、OBB 或外部 data 很大。可在 `backup_settings.conf` 將 `Backup_obb_data=0` 跳過外部 OBB / data 類大型資料。
</details>

<details>
<summary><b>Q4：腳本每次都是全量備份嗎？</b></summary>

不是。腳本會比對版本號、資料大小、SSAID、權限、AppOps、AppState 與遠端檔案狀態。無變化時會跳過；若全部選中 App 都無變化，本地與遠端都可整批 fast-skip。
</details>

<details>
<summary><b>Q5：為什麼腳本包含 classes.dex？</b></summary>

`classes.dex` 用於處理 Shell 難以穩定完成的 Android 系統能力，例如 AppState snapshot / restore / verify、SSAID、AppOps、WebDAV daemon、SMB 掃描、安裝來源恢復與通知更新。

感謝 [XayahSuSuSu](https://github.com/XayahSuSuSu) 的 [Android-DataBackup](https://github.com/XayahSuSuSu/Android-DataBackup) 提供 App 支持。
</details>

<details>
<summary><b>Q6：息屏後備份速度變慢？</b></summary>

這通常是 Android 內核或廠商 ROM 的 IO / CPU 節能策略。可在 `backup_settings.conf` 設置 `setDisplayPowerMode=1`，或備份期間保持螢幕常亮。
</details>

<details>
<summary><b>Q7：如何單獨備份 / 恢復 / 上傳單一應用？</b></summary>

進入備份資料夾內對應應用子目錄，執行：

- `backup.sh`：單獨備份該 App
- `recover.sh`：單獨恢復該 App
- `upload.sh`：單獨上傳該 App 到遠端
</details>

<details>
<summary><b>Q8：WebDAV 上傳顯示 HTTP 423 Locked？</b></summary>

通常是 WebDAV server 對檔案鎖定或大檔策略限制。建議改用自家 NAS、rclone serve webdav、Nextcloud，或改用 SMB 測試。
</details>

<details>
<summary><b>Q9：WebDAV 上傳或列表顯示 HTTP 404？</b></summary>

請檢查 `webdav_url` 是否指向正確 WebDAV 端點，例如 `/dav/`、`/remote.php/webdav/` 或 rclone serve 的根路徑。若是 app_details 不存在的 404，腳本會按「遠端尚無備份」處理，不一定是錯誤。
</details>

<details>
<summary><b>Q10：SMB 提示找不到 share 或寫入失敗？</b></summary>

請確認：

- Windows / Samba / NAS 已開啟 SMB2 / SMB3
- 共享名稱與路徑正確
- 帳號具備寫入權限
- 防火牆允許 445 port
- 主選單 SMB 掃描結果與 `smb_url` 一致
</details>

<details>
<summary><b>Q11：沒網路會影響本地備份嗎？</b></summary>

不會。若遠端不可用，腳本會在預檢階段中止遠端流程或停用遠端上傳；本地備份可繼續完成。
</details>

<details>
<summary><b>Q12：流式備份和一般備份有什麼差別？</b></summary>

| | 一般備份 | 流式備份 |
|---|---|---|
| 本機空間佔用 | 先壓縮到本機再上傳 | 不落本機，直接傳輸 |
| 增量 / fast-skip | 支援 | 支援 |
| 本機完整性校驗 | 支援 | 不支援完整本地校驗 |
| 適合場景 | 本機空間充足 | 本機空間有限、區網穩定 |
</details>

<details>
<summary><b>Q13：為什麼 log 裡有些 stderr 是 0KB？</b></summary>

`stderr.log`、`root_daemon_stderr.log`、`webdav_daemon_stderr.log` 為 0KB 通常是正常現象，代表沒有錯誤輸出。主流程請看 `main.log` 或 `log/log_yyyy-mm-dd_hh-mm.txt`。
</details>

---

## 問題反饋

遇到問題請攜帶截圖與 speed_debug 壓縮包，透過以下方式反饋：

- [GitHub Issues](https://github.com/YAWAsau/backup_script/issues)
- [Telegram 頻道](https://t.me/yawasau_script)
- QQ 群：`976613477`
- 酷安：[@落葉淒涼TEL](http://www.coolapk.com/u/2277637)

---

## 支持作者

備份腳本耗費了大量時間與精力，如果你覺得好用，歡迎贊助支持。

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=flat-square&logo=paypal)](https://paypal.me/YAWAsau?country.x=TW&locale.x=zh_TW)

---

## 銘謝貢獻

| 貢獻者 | 貢獻內容 |
|--------|----------|
| [kmou424](https://github.com/kmou424)(臭批老k) | 提供部分驗證函數思路 |
| [雄氏老方](http://www.coolapk.com/u/665894)(屑老方) | 提供自動更新腳本方案 |
| [sakuradairong](https://github.com/sakuradairong)(雨季騷年/胖子老陳) | 新增 WebDAV / SMB 功能與測試 |
| [XayahSuSuSu](https://github.com/XayahSuSuSu) | 提供 App 支持與 Dex 功能支持 |

`文檔編輯：Petit-Abba, YuKongA`

---

<p align="center">
 <sub>GPL-3.0 Licensed · Made with by <a href="https://github.com/YAWAsau">YAWAsau</a></sub>
</p>
