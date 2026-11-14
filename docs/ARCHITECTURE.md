# 架構與資料格式

[返回首頁](../README.md) · [使用指南](USER_GUIDE.md) · [設定參考](CONFIGURATION.md) · [常見問題](FAQ.md) · [架構說明](ARCHITECTURE.md)

## 介面與腳本語言

切換繁體／簡體後會儲存語言設定，閒置時自動重新載入腳本並回到設定頁；工作執行中收到語言切換時，會等工作安全收尾後再載入，不會重跑工作。既有日誌維持原文。

繁簡轉換由 Dex CLI 單次啟動、串流處理，依固定 OpenCC `s2twp`／`tw2sp` 設定執行正規化、詞組切分與有序轉換，並共用至 APK 介面與 Dex 通知；資料版本見 `third_party/opencc-phrases/upstream.json`。改善「頭髮／發現」「乾淨／餅乾」「皇后／後來」等字形選擇，並保留專案用詞。這是詞組與地區用詞轉換，不是理解整句的翻譯模型；Java 實作依固定設定執行，未嵌入 OpenCC 原生函式庫。

正式腳本切回繁體時，另以該版本生成的完整行對照表還原已知差異；v1117 已在備用機驗證 11 次往返 SHA-256 相同。使用者自行修改或其他版本未收錄的行不保證無損，一般文字與 conf 也不套用腳本還原規則。

建置入口會自動生成詞組索引與腳本還原表，CI 檢查生成結果是否過期；詞庫在每個轉換程序內只載入一次，不需外部詞庫或 JNI。

## 後端職責

Rust 負責設定檔的字面值解析、舊欄位遷移與原子保存、遠端地址追蹤與帳密重填協調，以及診斷 tar 的鎖定和原子更新。Dex 負責 Android 通知的文字、進度校正、節流與通知分類。Shell 保留備份／恢復流程、傳輸介接與設定模板；APK 保留原本介面。既有 conf、帳密重試／返回、地址記憶及單一診斷包的操作方式不變。

## 遠端帳密與診斷

WebDAV 回傳 401 或 SMB 明確認證拒絕時，前台操作會開啟帳號、密碼重填頁。按「儲存並重試」寫回對應 conf，再重試連線預檢；按「返回」停止本次操作。權限、路徑與網路錯誤分開處理，不會自動重播上傳或刪除。背景模式需回到設定修正帳密。

同一工作服務階段共用一份 `speed_debug_session_*.tar`，包內使用單一根目錄及連續日誌，不再為每次操作保留獨立 run 子目錄。快照與重試避免重複併入，JSON 保留最新有效內容及歷史索引。關閉 APK 後接回仍屬同一階段；結束服務後重新啟動才建立新包。每次安全收尾原子更新歸檔，失敗保留原歸檔與待合併日誌。

## 功能特色

| 功能 | 說明 |
|------|------|
| 應用數據備份 | 備份應用資料、APK、Split APK、user / user_de / data / OBB 等資料 |
| 應用恢復 | 支援批量與單 App 恢復，核對檔案與 AppState；受系統限制的項目會分開顯示 |
| Play 安裝者身分 | 目標使用者的 Play 商店可用且通過檢查時優先使用其身分安裝；否則使用普通安裝，不保證 Play 授權或認證 |
| 應用列表 | Dex 提供新鮮完整已安裝集合，Rust 一次合併、清理、排序與驗證，保留註解及既有已安裝系統 App |
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
| 遠端已卸載應用清理 | 比對本機已安裝套件與遠端備份，列出候選並確認後刪除；資訊不足不直接判為可刪除 |
| 統一備份統計 | 彙總逐項、每個 App 與整輪結果，分開核對預估與實際大小；跳過不計本輪實際量，APK 僅重打包才計入 |
| 恢復檔案核對 | 依備份包清單核對落地檔案、目錄、大小與連結；不包含逐檔內容雜湊及完整 SELinux／ACL 驗證 |
| 事件等待與進程穩定檢查 | 使用 `eventwait` / `procwait` 輔助遠端串流等待、備份前穩定等待與恢復守護收尾 |
| 遠端預掃 | 遠端備份前批量取得遠端列表與 metadata 狀態，降低主循環網路開銷 |
| 遠端 metadata 健康檢查 | 遠端 `app_details_bundle.tar.zst` 缺失、損壞或內容不完整會明確提示，不靜默忽略 |
| 遠端串流測速 | 依目前設定進行 SMB／WebDAV 5 GiB 上傳及下載，不在手機建立大型測速檔 |
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
│   ├── find                # 檔案搜尋
│   ├── keycheck            # 部分啟動／更新流程使用的按鍵工具
│   ├── cmd                 # 系統指令橋接
│   ├── classes.dex         # Android 系統操作與遠端傳輸輔助
│   ├── soc.json            # 處理器資料庫
│   ├── dex_check.sh        # Dex／原生能力與流程自檢
│   └── tools.sh            # 核心腳本
├── backup_settings.conf    # 備份設定，可由腳本補齊
└── start.sh                # 執行入口
```

啟動時會在 `/data/.speedbackup/tools/` 釋放工具，並把 `cgfreezer`、`eventwait`、`filewatch`、`netwatch`、`procwait`、`speedscan`、`uidexec`、`unixsock` 建立為指向 `speednative` 的軟連結。原有呼叫名稱保留，不必自行在手機共享儲存空間建立連結。

**請保留完整 `tools/`，並使用同一發行包的腳本、Dex 與原生工具。** 不要把不同版本的單一檔案混用。

本地備份的 App 子目錄可生成 `backup.sh`／`recover.sh`／`upload.sh`，供單 App 操作。遠端不必保存這些入口與整套工具；遠端下載流程完成後會使用本機工具補齊。因此遠端只有資料壓縮包與 metadata，沒有 `tools/`，可以是正常狀態。

## APK 安裝策略與恢復安全

- 目標 Android 使用者的 Play 商店存在、啟用且身分可確認時，優先使用 Play 安裝者身分，不依 JSON 原始 installer 分流。資料目錄或靜默安裝權限不足時不切換 Play UID；沒有可用 Play 身分則使用普通 PM 安裝。
- Play 混合 session 由每 App 一次的 Rust 協調器執行：以 Play UID 建立／提交，root 寫入 APK。系統 PM 仍有子程序成本；不是 Java 安裝器，也不是整批常駐安裝 worker。
- 不再需要 `!play`；舊恢復清單前綴只作相容性處理。JSON 安裝來源欄位仍可用於診斷，不是本次選擇路徑的依據。此功能不保證 `packageSource=STORE`、Play 授權、免登入或完整性認證。
- 保留路徑、owner、UID/GID、檔案描述符、逾時與 commit guard 檢查。提交結果不明會回報狀態 75，封鎖本輪同使用者／套件重試及其資料／AppState 恢復；只有明確失敗才可依既有政策回退。重啟腳本前先確認前次 session 結果。
- 提交期間可能暫時停用 Android BackupManager 的全域自動還原，再依日誌恢復；同一窗口內其他來源的安裝也可能受影響，並非單一 App 隔離開關。
- 內部資料依目前套件 UID／seInfo 修復 ownership 與 SELinux；外部 data／obb 另走 Android 儲存政策。終端宿主與無法安全停止的 App 仍受保護；從 Termux 自身執行時不恢復其宿主資料。
- 直接串流恢復會改動目標資料，沒有整批回滾；失敗可能已有部分內容寫入。請保留獨立備份，勿把「來源預檢通過」當成恢復一定成功。

## AppState metadata bundle

新版 AppState metadata 以備份根目錄的 `app_details_bundle.tar.zst` 為主，不再把遠端逐 App `app_details.json` 作為上傳／遠端下載 的 metadata 同步主路徑。

### 產生與上傳

遠端備份流程會彙總根層 `app_details_bundle.tar.zst`。使用「單獨上傳當前備份」時，腳本會先掃描本地備份目錄內的：

```text
<App目錄>/app_details.json
```

並重新彙總成：

```text
app_details_bundle.tar.zst
```

然後再上傳到遠端根層。「單獨上傳當前備份」的清單會過濾逐 App `app_details.json`，metadata 只同步 bundle。

### 下載與解包

遠端非串流恢復的下載階段會要求遠端根層存在：

```text
app_details_bundle.tar.zst
```

下載成功後，腳本會在本地備份根目錄同級解包，恢復成：

```text
<App目錄>/app_details.json
```

如果遠端缺少 `app_details_bundle.tar.zst`，遠端下載會中止；不再 fallback 到遠端逐 App `app_details.json`。

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

舊 JSON 已有的 SSAID、權限、AppOps、電池策略會盡量恢復；安裝來源紀錄保留作診斷，APK 依現行 Play 優先策略安裝。舊 JSON 本來沒有的新欄位則無法憑空補出。

> 注意：此相容僅針對本地既有舊備份恢復。新版上傳／遠端下載 的遠端同步流程採 `app_details_bundle.tar.zst` bundle-only，不再使用遠端逐 App `app_details.json` 作為 metadata 主路徑。

## AppState / Dex 功能

`classes.dex` 用於實現 Shell 難以穩定完成的系統操作。目前主要負責：

- AppState snapshot / restore / verify
- SSAID 備份與恢復輔助
- 運行時權限、AppOps、特殊存取、電池策略狀態處理
- 安裝來源診斷、目標使用者的 Play 身分及安裝條件查詢
- 批次取得 App 名稱、包名、版本、split 資訊與安裝後狀態
- WebDAV 連線、相對路徑檢查與傳輸服務
- SMB 主機與 share 掃描輔助
- 通知批量更新
- 權限 / AppOps / 特殊存取中文語意輸出
- 查詢預設桌面、輸入法、電話、簡訊、瀏覽器與助理
- 查詢儲存空間與媒體路徑
- 內建設備型號資料庫，release 內不再需要外置 `tools/Device_List`

Rust 原生工具負責應用列表、JSON、備份計畫、統計、受保護的檔案操作及每 App 安裝 session 協調；Dex 負責 Android 狀態、儲存政策及相關傳輸能力。一般檔案查詢仍保留 GNU find，未全面改為 Rust。AppState／SSAID 的恢復與驗證由 Dex 直接產生分類摘要，避免腳本靠訊息措辭重新猜結果。

啟動自檢由 `tools/dex_check.sh` 執行，依實際能力檢查相容性，不只比較版本字串。摘要會分開列出成功、警告、失敗與核心失敗；部分新流程使用 `SBRESULT` 統一結果格式。

**自檢通過不等於完成一輪真實備份與恢復。** `partial` 可能表示有警告或核驗不完整，請看原因；受廠商限制、資料不符與執行失敗也不能視為同一種結果。
