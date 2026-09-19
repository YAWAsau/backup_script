# SpeedBackup / Backup_script 數據備份腳本

<p align="center">
 <a href="https://deepwiki.com/YAWAsau/backup_script"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki" /></a>
 <a href="https://github.com/YAWAsau/backup_script/stargazers"><img src="https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars&style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases"><img src="https://img.shields.io/github/downloads/YAWAsau/backup_script/total?style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases/latest"><img src="https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release&style=flat-square" /></a>
 <a href="https://choosealicense.com/licenses/gpl-3.0"><img src="https://img.shields.io/github/license/YAWAsau/backup_script?label=License&style=flat-square" /></a>
 <a href="https://t.me/yawasau_script"><img src="https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram&style=flat-square" /></a>
</p>

---

## 概述

Backup_script 是一款專為 Android 設計的應用數據備份／恢復 Shell 腳本，支援應用資料、Split APK、SSAID、運行時權限、AppOps、特殊存取、電池策略、安裝來源、OBB 數據包、Wi-Fi 設定與自定義資料夾備份。適合換機、刷機、重裝系統後快速還原應用狀態。

腳本提供本地備份與遠端備份兩種模式。遠端備份支援 WebDAV / SMB，可上傳到 NAS、區網電腦、rclone serve webdav、Nextcloud 等服務，可先下載備份回手機再恢復，也可直接從遠端串流解壓恢復。

新版支援流式備份：資料可直接 `tar | zstd | 傳輸`，不需要先落地成本機壓縮包，適合本機空間不足的裝置。對於沒有變化的應用，腳本會透過版本、資料大小、AppState、SSAID 與遠端檔案狀態進行 fast-skip，避免重複壓縮與重複上傳。

新版 AppState metadata 採用 `app_details_bundle.tar.zst` bundle-only 遠端同步流程：功能 7 會先彙總本地 metadata 再上傳，功能 10 會先下載 bundle 並同級解包，再下載所選備份；恢復需另外執行。

> 作者為台灣人，預設發布繁體版本。簡體中文環境下腳本可自動切換語言。

**系統需求：** `Android 9+` · `arm64 架構` · `Root 權限(Magisk / KernelSU)`

---

## 功能特色

| 功能 | 說明 |
|------|------|
| 應用數據備份 | 備份應用資料、APK、Split APK、user / user_de / data / OBB 等資料 |
| 應用恢復 | 支援批量與單 App 恢復，核對檔案與 AppState；受系統限制的項目會分開顯示 |
| Play 商店來源還原 | 支援恢復 installer / install source，依備份記錄與支援的安裝流程設定來源 |
| SSAID 備份與恢復 | 支援備份與恢復 Android SSAID，協助保留依賴此識別碼的應用狀態，不保證免登入 |
| 權限與 AppOps | 支援運行時權限、AppOps、特殊存取、電池策略等狀態備份與恢復 |
| AppState metadata bundle | 新版 metadata 統一彙總為根層 `app_details_bundle.tar.zst`，遠端同步與下載以 bundle 為準 |
| 本地舊 JSON 恢復相容 | 本地既有舊備份的 `app_details.json` 可在恢復時轉換為新版 AppState restore record |
| Split APK | 支援多 split APK 備份與恢復 |
| OBB 數據包 | 可選備份外部 OBB 數據，如大型遊戲資料包 |
| Wi-Fi 備份 | 支援 Wi-Fi 設定備份與恢復 |
| 自定義資料夾 | 可備份與恢復 DCIM、Download、Music 等任意自定義目錄 |
| 壓縮方式 | 支援 `zstd` 壓縮與 `tar` 僅打包 |
| 增量備份 | 多維度比對版本、資料大小、權限、SSAID、AppState，無變化則跳過 |
| 全量 fast-skip | 本地 / WebDAV / SMB 全部無變化時可整批折疊跳過，不進逐 App 主流程 |
| 遠端備份 | 支援 WebDAV / SMB 備份、下載、恢復、列表與健康檢查 |
| 流式備份／恢復 | 不先暫存完整資料壓縮包；仍需 metadata、日誌與恢復後資料的空間 |
| 遠端已卸載應用清理 | 功能 9 比對本機已安裝套件與遠端備份，列出候選並確認後刪除；資訊不足不直接判為可刪除 |
| 統一備份統計 | 彙總逐項、每個 App 與整輪結果，分開核對預估與實際大小；跳過不計本輪實際量，APK 僅重打包才計入 |
| 恢復檔案核對 | 依備份包清單核對落地檔案、目錄、大小與連結；不包含逐檔內容雜湊及完整 SELinux／ACL 驗證 |
| 事件等待與進程穩定檢查 | 使用 `eventwait` / `procwait` 輔助遠端串流等待、備份前穩定等待與恢復守護收尾 |
| 遠端預掃 | 遠端備份前批量取得遠端列表與 metadata 狀態，降低主循環網路開銷 |
| 遠端 metadata 健康檢查 | 遠端 `app_details_bundle.tar.zst` 缺失、損壞或內容不完整會明確提示，不靜默忽略 |
| SMB 掃描 | 自動掃描區網 SMB 主機與 share，免手動找 IP |
| WebDAV 相容 | 支援逐層建目錄、PUT/MOVE/STAT/GET 校驗、404 非致命判斷等 WebDAV 相容處理 |
| 日誌與 debug 包 | 自動生成 speed_debug 診斷包，legacy `log/log_yyyy-mm-dd_hh-mm.txt` 會同步主日誌摘要 |
| 後台執行 | 支援後台執行模式，log 持續刷新 |
| 狀態通知 | 支援備份 / 恢復進度與結果通知 |
| 多用戶支援 | 支援 user 0、999 等多用戶環境，可指定或自動選擇用戶 |
| 設定檔自動修補 | 升級後自動補齊 `backup_settings.conf` 缺少項目，不需手動重寫 |
| 自動更新 | 支援本地 ZIP 更新、Download / QQ 下載目錄檢測與 GitHub release 檢查 |
| 完整性檢查 | 工具 SHA-256、壓縮包檢查、遠端大小與恢復清單核對分別處理；未知或未檢查不等同通過 |
| 啟動自我檢測 | `tools/dex_check.sh` 檢查 Dex／原生工具能力與目前使用的流程，彙整成功、警告與失敗 |
| 單一原生工具 | 八個 Rust 工具整合為 `speednative`，啟動後建立原名稱軟連結 |

---

## 主選單功能

備份與恢復模式的編號不同，請先確認目前位於工具根目錄或備份目錄。以下為 r718 選單。

### 備份模式

| 編號 | 功能 | 說明 |
|---|---|---|
| 1 | 生成應用列表 | 產生 `appList.txt` |
| 2 | 備份應用 | 依列表與設定備份，符合跳過條件的項目不重打包 |
| 3 | 備份已更新應用 | 備份版本有變化的應用 |
| 4 | 備份自定義資料夾 | 使用 `Custom_path` 設定 |
| 5 | 備份 Wi-Fi | 備份目前設備的 Wi-Fi 設定 |
| 6 | 測試遠端連線 | 檢查 WebDAV／SMB 連線與寫入能力 |
| 7 | 單獨上傳當前備份 | 上傳現有本地備份並彙總 metadata bundle，不重新備份資料 |
| 8 | 列出遠端備份 | 產生 `appList_network.txt` |
| 9 | 刪除遠端已卸載應用 | 列出本機已卸載、遠端仍有備份的候選，確認後刪除 |
| 10 | 從遠端下載備份 | 下載 metadata bundle 與所選備份，補齊本地恢復入口 |
| 11 | 從遠端流式恢復 | 直接傳輸並解壓所選備份，不先存整包 |
| 12 | 從遠端流式恢復自定義資料夾 | 直接恢復遠端 Media／自定義目錄 |
| 13 | 目前備份統計 | 查看備份統計 |
| 14 | 重生現有備份 JSON | 更新 metadata，保留既有大小、版本、時間與 SSAID，不重打包資料 |
| 15 | 殺死運行中腳本 | 終止正在執行的腳本流程 |
| 0 | 離開腳本 | 結束選單 |

### 恢復模式

| 編號 | 功能 | 說明 |
|---|---|---|
| 1 | 重新生成應用列表 | 刷新備份目錄的 `appList.txt` |
| 2 | 恢復備份 | 依列表恢復應用、資料與 AppState |
| 3 | 僅恢復包含 SSAID 應用（含數據） | 篩選有 SSAID 備份值的應用後恢復 |
| 4 | 僅恢復包含 SSAID 應用的 App 狀態（不含數據） | 對已安裝的應用恢復 App 狀態，不覆蓋應用資料；並非只寫 SSAID |
| 5 | 恢復自定義資料夾 | 恢復已備份的自定義目錄 |
| 6 | 恢復 Wi-Fi | 恢復 Wi-Fi 設定 |
| 7 | 壓縮檔完整性檢查 | 檢查備份壓縮包，不等同確認 App 恢復後可正常登入 |
| 8 | JSON 結構檢查 | 檢查 metadata 結構 |
| 9 | 重生現有備份 JSON | 保留大小、版本、時間與 SSAID，更新 metadata |
| 10 | 轉換文件夾名稱 | 轉換備份資料夾名稱格式 |
| 11 | 殺死運行中腳本 | 終止正在執行的腳本流程 |
| 0 | 離開腳本 | 結束選單 |

「重生 JSON」會使用本機目前可取得的應用狀態，不能補回從未備份的歷史狀態。一般備份／恢復不需要每次手動執行。

---

## 目錄結構

完整發行包解壓後的主要檔案如下；原始碼包的目錄配置不同。

```text
SpeedBackup/
├── tools/
│   ├── busybox             # 核心工具集
│   ├── speednative         # 八個 Rust 工具共用的原生程式
│   ├── zstd                # 壓縮工具
│   ├── tar                 # 打包工具
│   ├── smbclient           # SMB 傳輸
│   ├── jq                  # JSON 處理
│   ├── find                # 檔案搜尋
│   ├── keycheck            # 音量鍵輸入
│   ├── cmd                 # 系統指令橋接
│   ├── classes.dex         # Android 系統操作與遠端傳輸輔助
│   ├── soc.json            # 處理器資料庫
│   ├── dex_check.sh        # Dex／原生能力與流程自檢
│   └── tools.sh            # 核心腳本
├── backup_settings.conf    # 備份設定，可由腳本補齊
└── start.sh                # 執行入口
```

啟動時會在 `/data/backup_tools/` 釋放工具，並把 `cgfreezer`、`eventwait`、`filewatch`、`netwatch`、`procwait`、`speedscan`、`uidexec`、`unixsock` 建立為指向 `speednative` 的軟連結。原有呼叫名稱保留，不必自行在手機共享儲存空間建立連結。

**請保留完整 `tools/`，並使用同一發行包的腳本、Dex 與原生工具。** 不要把不同版本的單一檔案混用。

本地備份的 App 子目錄可生成 `backup.sh`／`recover.sh`／`upload.sh`，供單 App 操作。遠端不必保存這些入口與整套工具；功能 10 下載後會使用本機工具補齊。因此遠端只有資料壓縮包與 metadata，沒有 `tools/`，可以是正常狀態。

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
| `mount_point` | 屏蔽外部掛載點，多個用 `\|` 分隔 | 自訂 |
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
| `Compression_method` | App 資料使用 `zstd` 或 `tar`；一般 Media／自定義目錄另走 tar 僅打包 | `zstd` |
| `Zstd_level` | 壓縮等級 `1`～`22`；`20`～`22` 會啟用 ultra | `6` |
| `Zstd_threads` | 一般壓縮執行緒 `0`～`64`；`0` 自動使用可用核心 | 新建設定 `0`；舊設定補齊可能為 `4` |
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
| `diagnostic_mode` | 診斷模式：`1` 保留更多排查資料、`0` 一般使用 | `0` |
| `remote_keep_local` | 非流式上傳成功後：`1` 保留本地資料包、`0` 刪除；不會讓流式備份額外保存整包 | `0` |
| `remote_upload_per_app` | 每個 App 備份後立即上傳，非流式模式下節省空間 | `0` |
| `log_max_size_mb` | `log/` 目錄大小上限，留空或 `0` 關閉自動清理 | 留空 |

---

## 使用方式

### 調整 zstd 壓縮

直接修改 `backup_settings.conf`，不用重新編譯。例如：

```conf
Compression_method=zstd
Zstd_level=6
Zstd_threads=0
Zstd_small_max_bytes=1048576
Zstd_small_threads=1
Zstd_size_hint=1
```

想提高壓縮率可調高 `Zstd_level`，代價是更多時間與記憶體；影音、APK 等已壓縮內容可能改善有限。`Zstd_threads` 控制並行程度，不是壓縮等級。已有設定不會自動改成新預設；r718 對缺少此欄位的舊設定仍補入 `4`，想自動使用核心請明確填 `0`。

一般 Media／自定義資料夾採 tar 僅打包，調整 `Zstd_level` 不會讓這些 tar 變小。小檔切換與大小提示也只在取得有效大小計畫時生效。debug 的 `ZSTD_EFFECTIVE_PARAMS` 可查看每個項目實際使用的值。

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

若恢復結束後提示存在 SSAID，建議立刻重啟後再開啟應用。開啟 App 後仍需確認登入與資料狀態；SSAID 核對成功不代表伺服器登入驗證一定通過。

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
remote_keep_local=0
```

上述為流式範例，不會額外保留本機整包。若要保留本機備份並上傳，請改為 `remote_stream=0`、`remote_keep_local=1`。

| 協議 | 地址格式 | 適用場景 |
|------|----------|---------|
| SMB | `smb://192.168.1.100/share/path` | Windows 共享 / Samba / NAS |
| WebDAV | `http://192.168.1.100:8080/dav/` | NAS / Nextcloud / rclone serve webdav |

### 遠端目錄結構

腳本會在遠端地址下建立 `Backup_<壓縮方式>_<用戶ID>/`。以下為示意，實際項目依備份內容而定：

```text
Backup_zstd_0/
├── app_details_bundle.tar.zst  # AppState 與備份 metadata
├── LINE/
│   ├── apk.tar.zst
│   ├── user.tar.zst
│   └── user_de.tar.zst
├── Media/
│   └── Download.tar           # 自定義資料夾，檔名依設定而定
└── wifi/
    └── wifi.json
```

遠端資料目錄不需要與本地工具目錄完全相同。`start.sh`、App 操作入口、設定與 `tools/` 由下載流程在本機補齊；不要因遠端缺少這些檔案就判定備份不完整。

不同 Android 使用者會分開到不同目錄，例如 `Backup_zstd_0/`、`Backup_zstd_999/`。

新版遠端 metadata 採用 bundle-only 流程。遠端根層的 `app_details_bundle.tar.zst` 是恢復與遠端下載所需的 metadata 主檔；bundle 內部保留 App 目錄結構，下載後會在本地備份根目錄同級解包成 `<App目錄>/app_details.json`。

### 遠端備份特性

- **流式備份**：`remote_stream=1` 時，資料直接打包並傳輸到遠端，不先暫存完整資料包；metadata 與日誌仍會保存在本機。
- **遠端 fast-skip**：比對版本、大小、AppState 等記錄，符合條件時跳過；這不是逐檔內容雜湊比對。
- **遠端 metadata bundle 健康檢查**：缺失、損壞或內容不完整的 `app_details_bundle.tar.zst` 會明確提示。
- **失敗保護**：流式上傳失敗時不更新遠端 metadata 狀態，避免下輪誤判已備份完成。
- **WebDAV 相容處理**：依服務實際能力選擇目錄列舉與提交方式；上傳後核對遠端檔案，大小無法取得時明確標示核驗範圍。
- **SMB 寫入預檢**：正式備份前會測試遠端目錄建立與寫入能力。

---

## AppState metadata bundle

新版 AppState metadata 以備份根目錄的 `app_details_bundle.tar.zst` 為主，不再把遠端逐 App `app_details.json` 作為功能 7 / 功能 10 的 metadata 同步主路徑。

### 產生與上傳

遠端備份流程會彙總根層 `app_details_bundle.tar.zst`。使用功能 7「單獨上傳當前備份」時，腳本會先掃描本地備份目錄內的：

```text
<App目錄>/app_details.json
```

並重新彙總成：

```text
app_details_bundle.tar.zst
```

然後再上傳到遠端根層。功能 7 的上傳清單會過濾逐 App `app_details.json`，metadata 只同步 bundle。

### 下載與解包

功能 10「從遠端下載備份」會要求遠端根層存在：

```text
app_details_bundle.tar.zst
```

下載成功後，腳本會在本地備份根目錄同級解包，恢復成：

```text
<App目錄>/app_details.json
```

如果遠端缺少 `app_details_bundle.tar.zst`，功能 10 會中止下載；不再 fallback 到遠端逐 App `app_details.json`。

---

## 流式備份模式

`remote_stream=1` 啟用後，資料直接走：

```text
tar → zstd（選用壓縮時）→ WebDAV / SMB
```

優點：

- 不先暫存完整資料壓縮包，但仍需 metadata、工具與日誌空間
- 適合本機剩餘空間不足的裝置
- 支援 WebDAV / SMB
- 支援遠端 fast-skip 與傳輸結果、遠端大小核對；不是遠端逐位元組內容校驗

限制：

- 傳輸過程依賴網路穩定性；流式不可用時會中止，不會偷偷改成整包本機暫存
- 本地不保留壓縮包時，無法做本地 tar/zstd 完整性校驗
- 若遠端上傳失敗，該 App 會保留失敗狀態，下輪重新備份

---

## 從遠端下載備份

需要在本地保存壓縮包時使用功能 **10**；想直接恢復 App 使用功能 **11**，只恢復自定義資料夾使用功能 **12**。流式恢復仍需要足夠空間放解壓後的資料。

**Step 1 — 列出遠端備份**

備份模式選功能 **8「列出遠端備份」**，產生 `appList_network.txt`。

**Step 2 — 編輯下載列表**

打開 `appList_network.txt`，用 `#` 註解掉不需要下載的應用。

**Step 3 — 從遠端下載備份**

備份模式選功能 **10「從遠端下載備份」**。腳本會先下載遠端根層 `app_details_bundle.tar.zst`，並在本地備份根目錄同級解包出各 App 的 `app_details.json`。若遠端缺少 `app_details_bundle.tar.zst`，下載會中止，避免產生 metadata 不完整的本地備份。

下載完成後，直接執行下載資料夾中的 `start.sh` 進行恢復。

---

## 本地舊版 JSON 恢復相容

本地既有舊備份仍可在恢復時讀取逐 App `app_details.json`。若舊 JSON 沒有新版 `app_state` 欄位，但仍保留：

```text
permissions
battery_settings
Ssaid
installer / install_diagnostics
apk_version
PackageName
user / user_de / data Size
```

腳本會在恢復時嘗試轉換為新版 AppState restore record，等效於：

```text
sourceFormat=legacy-app-details-migrated
recordType=snapshot
schemaVersion=2
```

舊 JSON 已有的 SSAID、權限、AppOps、電池策略與安裝來源會盡量恢復；舊 JSON 本來沒有的新欄位則無法憑空補出。

> 注意：此相容僅針對本地既有舊備份恢復。新版功能 7 / 功能 10 的遠端同步流程採 `app_details_bundle.tar.zst` bundle-only，不再使用遠端逐 App `app_details.json` 作為 metadata 主路徑。

---

## AppState / Dex 功能

`classes.dex` 用於實現 Shell 難以穩定完成的系統操作。目前主要負責：

- AppState snapshot / restore / verify
- SSAID 備份與恢復輔助
- 運行時權限、AppOps、特殊存取、電池策略狀態處理
- 安裝來源、installer、Play 來源恢復輔助
- 批次取得 App 名稱、包名、版本、split 資訊與安裝後狀態
- WebDAV 連線、相對路徑檢查與傳輸服務
- SMB 主機與 share 掃描輔助
- 通知批量更新
- 權限 / AppOps / 特殊存取中文語意輸出
- 查詢預設桌面、輸入法、電話、簡訊、瀏覽器與助理
- 查詢儲存空間與媒體路徑
- 內建設備型號資料庫，release 內不再需要外置 `tools/Device_List`

Rust 原生工具負責檔案樹、備份計畫、統計與檔案驗證；Dex 負責 Android 狀態及相關傳輸能力。AppState／SSAID 的恢復與驗證由 Dex 直接產生分類摘要，避免腳本靠訊息措辭重新猜結果。

啟動自檢由 `tools/dex_check.sh` 執行，依實際能力檢查相容性，不只比較版本字串。摘要會分開列出成功、警告、失敗與核心失敗；部分新流程使用 `SBRESULT` 統一結果格式。

**自檢通過不等於完成一輪真實備份與恢復。** `partial` 可能表示有警告或核驗不完整，請看原因；受廠商限制、資料不符與執行失敗也不能視為同一種結果。

---

## 腳本更新方式

1. **本地 ZIP 更新**：將完整 release `.zip` 不解壓，放到腳本目錄或其上層目錄，執行腳本時自動檢測更新。
2. **Download 目錄更新**：將完整 release `.zip` 放到 `/storage/emulated/0/Download/`，執行腳本時自動檢測。
3. **QQ 下載目錄更新**：從 QQ 下載的完整 release `.zip` 可直接放置後執行腳本更新。
4. **聯網自動更新**：`update=1` 時會檢查 GitHub release。

**舊版升級請整套更新，不要只替換 `tools.sh`。** 舊更新器可能仍要求原先的獨立工具檔名，因而拒絕新版 `speednative` 配置。遇到「缺少舊工具」時，使用發行者提供的相容更新包，或把完整發行包解壓到新的工具目錄後使用，保留原備份資料。

請從工具根目錄執行更新。位於單一 App 的備份目錄時，只提示返回工具根目錄，不在該目錄下載或套用更新。

更新規則：

- 本地完整 release 同版本允許覆蓋更新，成功後刪除更新 ZIP。
- 低於目前版本的 ZIP 會拒絕更新。
- 線上 release 與本地版本相同時不提示新版。
- 更新只同步 release 內工具與入口檔，不會刪除既有備份資料。
- 更新失敗、拒絕或中止時會清理 `/data/local/tmp` 更新暫存。

> 本地備份可離線使用。開啟遠端功能會向你設定的服務傳送備份；開啟線上更新會連線 GitHub 或所選 CDN。

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
- `stderr.log`：Shell 錯誤輸出
- `root_daemon_stderr.log`：Root daemon 錯誤輸出
- `webdav_daemon_stderr.log`：WebDAV daemon 錯誤輸出
- `app_state_output.log`：AppState restore 輸出
- `verify_app_state_output.log`：AppState verify 輸出
- `stream_upload.log` / `stream_download.log`：流式上傳 / 下載日誌
- `extract.log`：恢復解壓日誌
- `restore_app_phase_timing.tsv`：恢復階段耗時統計
- `restore_apk_timing.tsv`：APK 安裝階段耗時統計

stderr 為 0KB 只代表該輸出檔沒有記錄，不代表所有檢查通過。請一併看 `main.log` 的結果摘要、失敗原因、備份預估／實際差異，以及 AppState／SSAID 驗證結果。沒有有效計畫時，單看 `mismatch=0` 也不能判定核對通過。

一般模式會精簡成功恢復的詳細清單；需要深入排查時才開啟 `diagnostic_mode=1`，debug 包也會變大。實際檔名與輸出位置以當輪提示為準。

---

## 常見問題

<details>
<summary><b>Q1：批量備份 / 恢復大量提示失敗？</b></summary>

請先查看當輪 speed_debug 的第一個失敗原因及自檢摘要。若提示工具 SHA-256 或能力不符，先結束正在執行的工作，再使用同一完整發行包修復工具；不要在備份途中刪除 `/data/backup_tools/`。仍失敗時請提交 debug 包。
</details>

<details>
<summary><b>Q2：微信 / QQ 能完美備份恢復嗎？</b></summary>

無法保證。大型即時通訊 App 可能有服務常駐、資料庫鎖、伺服器校驗或加密狀態。建議同時使用你信任的官方或第三方方式額外備份重要資料。
</details>

<details>
<summary><b>Q3：為什麼部分應用備份很久？</b></summary>

可能是 user data、user_de、OBB 或外部 data 很大，也可能包含儲存、傳輸或守護收尾等待。確認不需要這些外部資料後，才在 `backup_settings.conf` 將 `Backup_obb_data=0` 跳過外部 OBB / data 類大型資料。
</details>

<details>
<summary><b>Q4：腳本每次都是全量備份嗎？</b></summary>

不是。腳本會比對版本號、資料大小、SSAID、權限、AppOps、AppState 與遠端檔案狀態。無變化時會跳過；若全部選中 App 都無變化，本地與遠端都可整批 fast-skip。這是依記錄判斷是否需要重新打包，不是區塊增量或逐檔雜湊比對；內容改動但大小等條件相同時，不能保證一定辨識。
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

注意：新版遠端恢復 metadata 以根層 `app_details_bundle.tar.zst` 為準。若手動執行單 App `upload.sh`，建議再回主選單執行「單獨上傳當前備份」，讓腳本重新彙總並上傳 metadata bundle。
</details>

<details>
<summary><b>Q8：WebDAV 上傳顯示 HTTP 423 Locked？</b></summary>

先查看服務端日誌中的檔案鎖定原因，確認是否有其他用戶端正在寫入同一目標，再使用功能 6 測試寫入。請保留失敗請求與 debug；不能只憑 HTTP 423 判定手機壓縮或備份內容有錯。
</details>

<details>
<summary><b>Q9：WebDAV 上傳或列表顯示 HTTP 404？</b></summary>

請檢查 `webdav_url` 是否指向正確 WebDAV 端點，例如 `/dav/`、`/remote.php/webdav/` 或 rclone serve 的根路徑。若是 `app_details_bundle.tar.zst` 不存在，功能 10 會中止下載；備份或上傳流程請先生成並同步 metadata bundle。
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

未啟用遠端時，本地備份可離線執行。非流式模式在遠端連線預檢失敗時，會停用上傳並保留本地備份；`remote_stream=1` 則會中止，不會自動改成佔用本機整包空間的備份。
</details>

<details>
<summary><b>Q12：流式備份和一般備份有什麼差別？</b></summary>

| | 一般備份 | 流式備份 |
|---|---|---|
| 本機空間佔用 | 保存資料包，遠端模式再上傳 | 不先存完整資料包，仍有 metadata／日誌等 |
| 增量 / fast-skip | 支援 | 支援 |
| 本機完整性校驗 | 支援 | 不支援完整本地校驗 |
| 適合場景 | 本機空間充足 | 本機空間有限、區網穩定 |
</details>

<details>
<summary><b>Q13：功能 10 提示缺少 app_details_bundle.tar.zst？</b></summary>

新版遠端下載需要根層 `app_details_bundle.tar.zst`。請先使用新版完整備份，或在本地備份資料夾使用「單獨上傳當前備份」，讓腳本彙總本地各 App 的 `app_details.json` 並上傳 metadata bundle。
</details>

<details>
<summary><b>Q14：為什麼 log 裡有些 stderr 是 0KB？</b></summary>

`stderr.log`、`root_daemon_stderr.log`、`webdav_daemon_stderr.log` 為 0KB 通常是正常現象，代表沒有錯誤輸出。主流程請看 `main.log` 或 `log/log_yyyy-mm-dd_hh-mm.txt`。
</details>

---

## 目前核驗範圍

- 備份預估大小與實際打包大小分開核對，跳過、未知與失敗項目分開處理。Media 尚未完整納入全局精確大小計畫。
- 恢復清單檢查可發現缺檔、類型、大小與連結等差異，不包含逐檔內容雜湊及完整 SELinux／ACL 驗證。
- AppState／SSAID 核對通過後，仍需實際開啟 App 確認資料與登入；系統、廠商及伺服器限制不一定能由腳本還原。
- WebDAV 的串流耗時可能包含打包、壓縮、網路、讀取與守護收尾等待，小檔顯示的低速不能直接當成網路測速結果。

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
 <sub>GPL-3.0 Licensed · Made with ❤️ by <a href="https://github.com/YAWAsau">YAWAsau</a></sub>
</p>
