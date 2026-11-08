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

> 本文件對應 v1123／原生介面 1.80（versionCode 81）。介面已遷移至 Kotlin／Compose，APK 直接連接本機 Rust API，不再使用 WebView／JavaScript 或瀏覽器操作入口。操作與接回見 [原生主選單](WEB_MAIN_MENU.md)。[本次更新：v1102 → v1117](docs/updates-since-793d285.md) · [完整更新日誌](CHANGELOG.md)

---

## 介面與腳本語言

切換繁體／簡體後會儲存語言設定，閒置時自動重新載入腳本並回到設定頁；工作執行中收到語言切換時，會等工作安全收尾後再載入，不會重跑工作。既有日誌維持原文。

繁簡轉換由 Dex CLI 單次啟動、串流處理，加入 OpenCC 1.4.2 詞組資料，改善「頭髮／發現」「乾淨／餅乾」「皇后／後來」等字形選擇，並保留專案用詞。這是詞組匹配，不是理解整句的翻譯模型，也不是完整 OpenCC 原生引擎。

正式腳本切回繁體時，另以該版本生成的完整行對照表還原已知差異；v1117 已在備用機驗證 11 次往返 SHA-256 相同。使用者自行修改或其他版本未收錄的行不保證無損，一般文字與 conf 也不套用腳本還原規則。

建置入口會自動生成詞組索引與腳本還原表，CI 檢查生成結果是否過期；詞庫在每個轉換程序內只載入一次，不需外部詞庫或 JNI。

## 後端職責

Rust 負責設定檔的字面值解析、舊欄位遷移與原子保存、遠端地址追蹤與帳密重填協調，以及診斷 tar 的鎖定和原子更新。Dex 負責 Android 通知的文字、進度校正、節流與通知分類。Shell 保留備份／恢復流程、傳輸介接與設定模板；APK 保留原本介面。既有 conf、帳密重試／返回、地址記憶及單一診斷包的操作方式不變。

## 遠端帳密與診斷

WebDAV 回傳 401 或 SMB 明確認證拒絕時，前台操作會開啟帳號、密碼重填頁。按「儲存並重試」寫回對應 conf，再重試連線預檢；按「返回」停止本次操作。權限、路徑與網路錯誤分開處理，不會自動重播上傳或刪除。背景模式需回到設定修正帳密。

同一工作服務階段共用一份 `speed_debug_session_*.tar`，包內使用單一根目錄及連續日誌，不再為每次操作保留獨立 run 子目錄。快照與重試避免重複併入，JSON 保留最新有效內容及歷史索引。關閉 APK 後接回仍屬同一階段；結束服務後重新啟動才建立新包。每次安全收尾原子更新歸檔，失敗保留原歸檔與待合併日誌。

## 自動發現與地址追蹤

在「設定 → 備份設定 → 遠端連線與傳輸」選擇 SMB 或 WebDAV，再設定「SMB／WebDAV 自動發現地址」開關：

- **關閉（手動地址）**：沿用原本網址與帳密輸入，也能搜尋後填入地址。本地備份不啟動搜尋。
- **開啟（自動追蹤設備）**：首次開始遠端備份／恢復時，開啟設備選擇及連線設定；選擇後填寫帳密，SMB 需填共用資料夾。按底部「連線並繼續」儲存地址、帳密及設備身分至 conf，再由原本連線預檢驗證，未通過就停止本次操作。
- 下次優先使用原地址；確認同一設備只是換 IP 時，提示地址已更新，直接使用並寫回 conf。帳密與資料夾路徑保留。找不到原設備時重新開啟選擇，不會自動換成其他設備。
- 發現與追蹤由 Rust 後端執行，APK 僅顯示、選擇及編輯。結果一到即顯示，不需等 15 秒搜尋結束；SMB 原地址先做識別驗證，未匹配才並行探測私有 IPv4 網段（每段最多 /24、合計 512 地址、32 個工作執行緒）。
- SpeedBackup Server 若公告持久化 TXT `id`，以該 ID 跨重啟與網卡變更追蹤；其他 WebDAV 使用 DNS-SD 服務名稱、主機名稱與協定（服務名稱須保持穩定）；SMB 可透過 SMB2/3 NEGOTIATE 讀取 ServerGuid，不需安裝廣播服務，也不傳送帳密。未取得識別碼的「SMB 候選」只能手動使用。這些識別資訊供換址追蹤，並非密碼學認證；實際連線仍須通過 SMB 認證／HTTPS 憑證驗證。
- 選定地址、帳密與設備識別存於原 conf；自動換址只原子更新對應 URL，保留其他欄位，遇到同時編輯則拒絕覆寫。進行中的傳輸不切換目的地，也不因回到家中網路就自行開始作業。
- DNS-SD 支援 `_webdav._tcp`、`_webdavs._tcp`、`_smb._tcp`。隔離網路、跨網段、自訂 SMB 埠或 IPv6 link-local scope 可能需手動輸入。Windows／NAS 的既有 SMB 分享不用更換伺服器。

## 概述

Backup_script 是一款專為 Android 設計的應用數據備份／恢復 Shell 腳本，支援應用資料、Split APK、SSAID、運行時權限、AppOps、特殊存取、電池策略、安裝來源診斷、OBB 數據包、Wi-Fi 設定與自定義資料夾備份。適合換機、刷機、重裝系統後快速還原應用狀態。

腳本提供本地備份與遠端備份兩種模式。遠端備份支援 WebDAV / SMB，可上傳到 NAS、區網電腦、rclone serve webdav、Nextcloud 等服務，可先下載備份回手機再恢復，也可直接從遠端串流解壓恢復。

新版支援流式備份：資料可直接 `tar | zstd | 傳輸`，不需要先落地成本機壓縮包，適合本機空間不足的裝置。對於沒有變化的應用，腳本會透過版本、資料大小、AppState、SSAID 與遠端檔案狀態進行 fast-skip，避免重複壓縮與重複上傳。

AppState metadata 採用 `app_details_bundle.tar.zst` 集中同步。「單獨上傳當前備份」會先彙總 metadata 再上傳；「從遠端非串流恢復（先下載）」會下載 metadata 與所選資料後接著恢復。

> 作者為台灣人，預設發布繁體版本。簡體中文環境下腳本可自動切換語言。

**系統需求：** `Android 9+` · `arm64 架構` · `Root 權限(Magisk / KernelSU)`

---

## 從終端操作遷移至 App

原本在終端顯示的主選單、互動提示、備份／恢復進度與彩色執行日誌，現已集中到 SpeedBackup App。應用選擇、設定與一般確認改用畫面點選，執行期間可在 App 查看進度、跟隨最新日誌或翻閱歷史，不必一直停留在 MT 管理器的終端畫面。

App 負責操作與顯示，實際備份／恢復仍由背景的 Root 腳本、Dex 與原生工具執行。終端仍作為 `start.sh` 的啟動入口，啟動檢查及部分更新流程仍可能顯示終端提示；不是把整個備份引擎改寫成 APK。

### 啟動與操作

使用具 Root 權限的終端執行 `start.sh`，依啟動提示進入原生介面。主選單、應用清單、備份設定、路徑選擇與執行日誌均在 APK 中操作。既有備份資料與設定檔繼續沿用，不需因介面遷移重新備份。

- **工作接回**：工作啟動後可關閉畫面或終端，備份／恢復會繼續。再次從相同入口啟動可接回目前工作；需要中止時使用「停止工作」。關閉畫面不會自動儲存尚未確認的編輯。
- **應用清單**：支援搜尋、篩選、分頁及勾選。圖示優先準備首批、分批載入並預載下一頁，重用快取以減少空圖示閃爍。
- **逐行名單編輯**：黑名單、白名單與 system 清單可新增一行、按 × 刪除及貼上多行；超過 100 項分頁。按「確定」先回填設定草稿，仍須「儲存設定」才寫入檔案；路徑選擇同樣先回填欄位。
- **多行輸入**：輸入框隨內容增高，刪除後縮回，短內容不再固定佔用三行。
- **返回與日誌**：系統返回依頁面及資料夾層級逐層退回，有未儲存修改時提示確認。日誌可跟隨最新或回看歷史；壓縮／解壓進度保留平滑過渡與等寬數字。

### 外觀、壁紙與玻璃

一般控件統一使用 Miuix，主畫面按鈕與底部導覽保留液態玻璃。淺色／深色採用與 KernelSU 相同的 Miuix 標準語意配色；星空／夜空保留背景動畫，控件採標準深色。莫奈動態配色選項只在支援的外觀顯示。

「設定 → 壁紙」提供匯入圖片、使用系統靜態壁紙、啟用開關、還原背景，以及透明度／模糊度／壓暗調整。圖片縮圖後存於應用私有目錄，模糊結果在背景執行緒計算並重用。動態壁紙不擷取桌面；無法匯入時依畫面提示處理。

| 設定 | 行為 |
|---|---|
| 壁紙透明度 | 目前滑桿 100% 為完整顯示壁紙、0% 隱藏壁紙；與玻璃透明度方向不同 |
| 壁紙模糊 | 調整背景圖片；液態玻璃取樣畫面上已模糊的壁紙 |
| 全局高斯模糊 | 控制卡片、按鈕、輸入框、選單及對話框等控件的背景模糊；關閉時一般控件使用實色，不支援 GPU 模糊時採實色回退 |
| 自適應玻璃亮度 | 開啟時依背景調整玻璃效果及文字對比；關閉時不自動調整玻璃亮度，但使用壁紙時仍獨立選擇黑／白文字 |
| 玻璃透明度 | 100% 不額外加入底色填充、0% 使用不透明底色；沒有強制最低不透明度，邊界與折射效果仍保留 |
| 折射強度 | 0% 關閉折射、100% 使用原有效果 |

壁紙操作參考 [Tweak-Alpha](https://github.com/lumkit/Tweak-Alpha/tree/e86ff392b7a1d22408305c8ffd1a3a1b9130e299) 獨立實作。程式及歷史文件中的 `webview`／`web` 名稱保留升級相容，不代表目前仍使用網頁介面。

---

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

---

## App 功能入口

從工具根目錄的 `start.sh` 啟動後，在 App「功能」頁點選功能分類；從備份目錄的 `start.sh` 啟動則進入本地恢復模式。以下使用功能名稱，不需輸入舊終端選單編號。

| 要做的事 | 操作入口與行為 |
|---|---|
| 備份應用 | 選「備份應用」，等待清單同步後勾選「僅 APK」或「完整」，再按下一步 |
| 只備份更新過的應用 | 選「備份已更新應用」，依畫面確認選擇 |
| 備份資料夾／Wi-Fi | 選「備份自定義資料夾」或「備份WiFi」 |
| 調整備份設定 | 在設定頁開啟「備份設定」，修改後儲存 |
| 測試遠端／掃描區網 | 在網路連線相關功能選「測試遠端連線」，再點選連線測試、SMB／WebDAV 掃描或測速 |
| 上傳已有備份 | 選「單獨上傳當前備份」，同步本地備份及 metadata bundle |
| 遠端恢復 | 選「從遠端非串流恢復（先下載）」或「從遠端串流恢復(不佔本機)」，在遠端清單勾選項目後繼續 |
| 清理遠端備份 | 選「編輯遠端備份」多選刪除，或「刪除遠端已卸載應用」檢查候選；依畫面確認後才刪除 |
| 本地恢復 | 從備份目錄入口選「恢復備份」，在清單勾選需要的項目 |
| SSAID 相關恢復 | 在本地恢復模式選「僅恢復包含ssaid應用(含數據)」或「僅恢復包含SSAID應用的App狀態(不含數據)」；後者不覆蓋資料，並非只寫 SSAID |
| 恢復資料夾／Wi-Fi | 在本地恢復模式選「恢復自定義資料夾」或「恢復wifi」 |
| 檢查與維護 | 工具相關功能提供統計、壓縮檔完整性檢查、JSON 結構檢查、重生 metadata 或轉換資料夾名稱；項目依目前模式顯示 |
| 查看或停止工作 | 在「工作執行中」查看進度與日誌；中止時使用「停止工作」，等待收尾 |

「重生現有備份JSON」會使用本機目前可取得的應用狀態，不能補回從未備份的歷史狀態。一般備份／恢復不需要每次手動執行。

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

---

## 在 App 備份與恢復

設定中的包名清單與自定義路徑建議每行一項；不要把含空白的路徑自行拆開。舊設定保留原值，新增欄位由腳本補齊。`diagnostic_mode` 已不是公開設定，模板同步會移除舊欄位；一般執行仍會保留 speed_debug。

### 備份流程

1. 將完整發行包解壓，用具 Root 權限的 MT 管理器或終端執行根目錄 `start.sh`，依提示進入 App。
2. 在設定頁開啟「備份設定」，選擇使用者、備份項目及本地備份位置；需要遠端備份時一併設定連線與傳輸方式，完成後儲存。
3. 回到功能頁選「備份應用」。清單會在進入時同步；等待圖示準備完成後，利用搜尋或篩選選擇應用，勾選「僅 APK」或「完整」，兩者皆不勾選則略過。
4. 按清單的「下一步」，完成畫面提示後開始工作。在 App 查看進度與日誌；啟動後可關閉畫面或終端，重新啟動相同入口可接回。
5. 完成後查看結果摘要與失敗項目。本地備份預設位於 `Backup_<壓縮方式>_<用戶ID>/`，例如 `Backup_zstd_0/`，實際位置依設定而定。

不需要先在終端執行「生成應用列表」，也不需要用文字編輯器逐行修改 `appList.txt` 才能備份。清單同步會保留既有選擇與註解；無法完整取得清單時會顯示失敗，不應把準備失敗當成空清單繼續。

### 本地恢復流程

1. 執行備份資料夾內的 `start.sh`，進入本地恢復模式；需要調整恢復項目時先開啟「恢復設定」並儲存。
2. 選「恢復備份」，在 App 清單搜尋、篩選及勾選需要恢復的應用或其他項目。
3. 按下一步，依畫面確認後開始恢復。App 顯示 APK、資料與 AppState 等處理進度，完成後查看結果摘要。
4. 若結果提示存在 SSAID，依提示重啟後再開啟應用，確認登入與資料狀態；SSAID 核對通過不代表伺服器登入驗證一定通過。

### 清單與設定的進階用法

App 會管理 `appList.txt`、遠端清單及設定檔。需要手動維護時，請先結束工作並關閉未儲存的編輯頁，再修改對應檔案：

- `appList.txt` 行首 `#` 表示略過該應用。
- 應用名稱前 `!` 表示在 `Backup_Mode=1` 時僅備份安裝包，不備份資料；不是 Play 安裝來源開關。
- 黑名單、白名單與自定義路徑每行一項；不要把含空白的路徑拆開。日常使用可直接在 App 逐行新增、刪除或使用路徑選擇器。
- 設定檔缺少新欄位時會自動補齊，已有值會保留。

### 調整壓縮

在「備份設定」調整「壓縮格式」「壓縮等級」「壓縮線程」及小檔案相關選項後儲存，不需重新編譯。提高 zstd 等級通常會增加耗時與記憶體；影音、APK 等已壓縮內容改善可能有限。壓縮線程 `0` 代表自動使用可用核心，不是壓縮等級。

一般 Media／自定義資料夾採 tar 僅打包，不受 zstd 等級影響。小檔切換與大小提示只在取得有效大小計畫時生效；debug 的 `ZSTD_EFFECTIVE_PARAMS` 可查看實際參數。

---

## APK 安裝策略與恢復安全

- 目標 Android 使用者的 Play 商店存在、啟用且身分可確認時，優先使用 Play 安裝者身分，不依 JSON 原始 installer 分流。資料目錄或靜默安裝權限不足時不切換 Play UID；沒有可用 Play 身分則使用普通 PM 安裝。
- Play 混合 session 由每 App 一次的 Rust 協調器執行：以 Play UID 建立／提交，root 寫入 APK。系統 PM 仍有子程序成本；不是 Java 安裝器，也不是整批常駐安裝 worker。
- 不再需要 `!play`；舊恢復清單前綴只作相容性處理。JSON 安裝來源欄位仍可用於診斷，不是本次選擇路徑的依據。此功能不保證 `packageSource=STORE`、Play 授權、免登入或完整性認證。
- 保留路徑、owner、UID/GID、檔案描述符、逾時與 commit guard 檢查。提交結果不明會回報狀態 75，封鎖本輪同使用者／套件重試及其資料／AppState 恢復；只有明確失敗才可依既有政策回退。重啟腳本前先確認前次 session 結果。
- 提交期間可能暫時停用 Android BackupManager 的全域自動還原，再依日誌恢復；同一窗口內其他來源的安裝也可能受影響，並非單一 App 隔離開關。
- 內部資料依目前套件 UID／seInfo 修復 ownership 與 SELinux；外部 data／obb 另走 Android 儲存政策。終端宿主與無法安全停止的 App 仍受保護；從 Termux 自身執行時不恢復其宿主資料。
- 直接串流恢復會改動目標資料，沒有整批回滾；失敗可能已有部分內容寫入。請保留獨立備份，勿把「來源預檢通過」當成恢復一定成功。

---

## 遠端備份

### 設定方式

在 App「備份設定」選擇「備份方式」，填入對應 SMB 或 WebDAV 地址、帳號與密碼，設定「遠程數據交換方式」及非串流檔案保留方式後儲存。兩種協議的地址分別保留，切換時不需重新輸入。

WebDAV 可依伺服器類型明確套用設定範本，再核對地址；套用範本不等於連線成功。回功能頁使用「測試遠端連線」確認。以下是進階設定檔範例，日常操作不必直接編輯：

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

### 5 GiB 串流測速

在 App 選「測試遠端連線」，再選測速項目（5 GiB 串流），使用目前儲存的遠端類型與帳密。上傳隨機資料至本輪專用遠端目錄，下載時計數後丟棄；手機不建立 5 GiB 測速檔。

- 遠端需約 5 GiB 可用空間，上下傳合計約 10 GiB 流量；請確認網路費用與伺服器配額。
- App 執行日誌顯示進度與速度，最終摘要使用完整傳輸平均值。短傳輸或失敗不給成功評級。
- 正常完成或一般中止會嘗試清理本輪目錄；清理失敗或強制終止後可能殘留，依提示確認，不要刪除其他備份。
- 數字包含資料產生、協議、遠端儲存與快取影響，是端到端吞吐量，不是純網路測速或完整備份速度。

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
- **WebDAV 相容處理**：依服務實際能力選擇目錄列舉與提交方式；覆寫既有檔案使用暫存上傳後提交，MOVE 不可用時失敗，不改成直接破壞舊檔的 PUT。請預留新舊檔共存空間；上傳後核對遠端檔案，大小無法取得時明確標示核驗範圍。
- **SMB 寫入預檢**：正式備份前會測試遠端目錄建立與寫入能力。

---

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

## 從遠端恢復

在 App 功能頁選擇「從遠端非串流恢復（先下載）」或「從遠端串流恢復(不佔本機)」。進入時會取得遠端資料並同步清單，直接在畫面搜尋、篩選與勾選，再按下一步；不需要先執行舊「列出遠端備份」或手動修改 `appList_network.txt`。

| 方式 | 工作流程 | 本地空間需求 |
|---|---|---|
| 非串流恢復（先下載） | 下載 metadata 與所選備份，完成後自動接著恢復 | 下載資料包、保留的舊內容及解壓後資料 |
| 串流恢復 | 從遠端傳輸並直接解壓所選項目 | 不先保存完整資料包，仍需解壓後資料及 metadata／日誌空間 |

**「非串流恢復（先下載）」是下載後接著恢復的操作，不是只下載。** 確認下一步前請核對所選應用與恢復設定。

遠端下載需要根層 `app_details_bundle.tar.zst`。下載階段在交易暫存區處理 metadata 與所選資料，成功發布後，各 App 的 `app_details.json` 位於本地備份根目錄對應子目錄；缺少 bundle 時中止，不產生 metadata 不完整的本地備份。

非串流下載會保留發布日誌及舊內容，失敗時依日誌回復；回復失敗會停止，不把遠端缺檔當成刪除本地舊備份的授權。這是可恢復的多步交易，不是整批原子替換，也不適用於直接串流恢復。請預留足夠空間，不要在工作中手動刪除交易目錄。

---

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

舊 JSON 已有的 SSAID、權限、AppOps、電池策略會盡量恢復；安裝來源紀錄保留作診斷，APK 依現行 Play 優先策略安裝。舊 JSON 本來沒有的新欄位則無法憑空補出。

> 注意：此相容僅針對本地既有舊備份恢復。新版上傳／遠端下載 的遠端同步流程採 `app_details_bundle.tar.zst` bundle-only，不再使用遠端逐 App `app_details.json` 作為 metadata 主路徑。

---

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

---

## 腳本更新方式

1. **本地 ZIP 更新**：將完整 release `.zip` 不解壓，放到腳本目錄或其上層目錄，執行腳本時自動檢測更新。
2. **Download 目錄更新**：將完整 release `.zip` 放到 `/storage/emulated/0/Download/`，執行腳本時自動檢測。
3. **QQ 下載目錄更新**：從 QQ 下載的完整 release `.zip` 可直接放置後執行腳本更新。
4. **聯網自動更新**：在 App「備份設定」開啟「腳本自更新」後，啟動時檢查 GitHub release。

**先讓備份／恢復正常結束並退出腳本，再更新；不要修改執行中的工具。** 手動差異更新包只適用其標示的完整基底，按包內說明整組替換；來源碼包不是手機安裝包。例如 v1100 → v1101 更新包需先有完整 v1100，不能直接套到更舊版本。

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

日常請在 App 的「執行日誌」查看工作狀態，可跟隨最新或翻頁回看；不需要開啟終端追蹤輸出。背景同時會在 `log/` 保存相容日誌，例如：

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
- `install_session.log` / `install_method.log`：安裝 session 與路徑判定診斷

stderr 為 0KB 只代表該輸出檔沒有記錄，不代表所有檢查通過。請一併看 `main.log` 的結果摘要、失敗原因、備份預估／實際差異，以及 AppState／SSAID 驗證結果。沒有有效計畫時，單看 `mismatch=0` 也不能判定核對通過。

一般模式會精簡成功恢復的詳細清單，speed_debug 仍會保留。舊 `diagnostic_mode=1` 已不適用；深入排查請依維護者指示使用對應診斷環境變數。實際檔名與輸出位置以當輪提示為準。分享前請檢查包名、路徑及其他個人資訊。

---

## 常見問題

<details>
<summary><b>Q1：批量備份 / 恢復大量提示失敗？</b></summary>

請先查看當輪 speed_debug 的第一個失敗原因及自檢摘要。若提示工具 SHA-256 或能力不符，先結束正在執行的工作，再使用同一完整發行包修復工具；不要在備份途中刪除 `/data/.speedbackup/tools/`。仍失敗時請提交 debug 包。
</details>

<details>
<summary><b>Q2：微信 / QQ 能完美備份恢復嗎？</b></summary>

無法保證。大型即時通訊 App 可能有服務常駐、資料庫鎖、伺服器校驗或加密狀態。建議同時使用你信任的官方或第三方方式額外備份重要資料。
</details>

<details>
<summary><b>Q3：為什麼部分應用備份很久？</b></summary>

可能是 user data、user_de、OBB 或外部 data 很大，也可能包含儲存、傳輸或守護收尾等待。確認不需要這些外部資料後，才在 App「備份設定」關閉「備份obb數據」（`Backup_obb_data=0`） 跳過外部 OBB / data 類大型資料。
</details>

<details>
<summary><b>Q4：腳本每次都是全量備份嗎？</b></summary>

不是。腳本會比對版本號、資料大小、SSAID、權限、AppOps、AppState 與遠端檔案狀態。無變化時會跳過；若全部選中 App 都無變化，本地與遠端都可整批 fast-skip。這是依記錄判斷是否需要重新打包，不是區塊增量或逐檔雜湊比對；內容改動但大小等條件相同時，不能保證一定辨識。
</details>

<details>
<summary><b>Q5：為什麼腳本包含 classes.dex？</b></summary>

`classes.dex` 用於處理 Shell 難以穩定完成的 Android 系統能力，例如 AppState snapshot / restore / verify、SSAID、AppOps、WebDAV daemon、SMB 掃描、安裝條件查詢與通知更新。APK session 協調由 Rust 執行，不是改用 Java 安裝。

感謝 [XayahSuSuSu](https://github.com/XayahSuSuSu) 的 [Android-DataBackup](https://github.com/XayahSuSuSu/Android-DataBackup) 提供 App 支持。
</details>

<details>
<summary><b>Q6：息屏後備份速度變慢？</b></summary>

這通常是 Android 內核或廠商 ROM 的 IO / CPU 節能策略。可在 App「備份設定」開啟「亮屏偽裝」（`setDisplayPowerMode=1`），或備份期間保持螢幕常亮。
</details>

<details>
<summary><b>Q7：如何單獨備份 / 恢復 / 上傳單一應用？</b></summary>

單一應用備份／恢復可在 App 清單只勾選該應用後繼續。進階使用者也可從備份資料夾內對應應用子目錄執行獨立入口：

- `backup.sh`：單獨備份該 App
- `recover.sh`：單獨恢復該 App
- `upload.sh`：單獨上傳該 App 到遠端

注意：新版遠端恢復 metadata 以根層 `app_details_bundle.tar.zst` 為準。若手動執行單 App `upload.sh`，建議再回主選單執行「單獨上傳當前備份」，讓腳本重新彙總並上傳 metadata bundle。
</details>

<details>
<summary><b>Q8：WebDAV 上傳顯示 HTTP 423 Locked？</b></summary>

先查看服務端日誌中的檔案鎖定原因，確認是否有其他用戶端正在寫入同一目標，再在 App 使用「測試遠端連線」檢查寫入。請保留失敗請求與 debug；不能只憑 HTTP 423 判定手機壓縮或備份內容有錯。
</details>

<details>
<summary><b>Q9：WebDAV 上傳或列表顯示 HTTP 404？</b></summary>

請檢查 `webdav_url` 是否指向正確 WebDAV 端點，例如 `/dav/`、`/remote.php/webdav/` 或 rclone serve 的根路徑。若是 `app_details_bundle.tar.zst` 不存在，遠端下載會中止；備份或上傳流程請先生成並同步 metadata bundle。
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
<summary><b>Q13：遠端恢復提示缺少 app_details_bundle.tar.zst？</b></summary>

新版遠端下載需要根層 `app_details_bundle.tar.zst`。請先使用新版完整備份，或在本地備份資料夾使用「單獨上傳當前備份」，讓腳本彙總本地各 App 的 `app_details.json` 並上傳 metadata bundle。
</details>

<details>
<summary><b>Q14：為什麼 log 裡有些 stderr 是 0KB？</b></summary>

`stderr.log`、`root_daemon_stderr.log`、`webdav_daemon_stderr.log` 為 0KB 通常是正常現象，代表沒有錯誤輸出。主流程請看 `main.log` 或 `log/log_yyyy-mm-dd_hh-mm.txt`。
</details>

---

## 目前核驗範圍

- 備份預估大小與實際打包大小分開核對，跳過、未知與失敗項目分開處理；沒有有效預掃計畫的項目不能只靠數值相同判定通過。
- 恢復清單檢查可發現缺檔、類型、大小與連結等差異，不包含逐檔內容雜湊及完整 SELinux／ACL 驗證。
- AppState／SSAID 核對通過後，仍需實際開啟 App 確認資料與登入；系統、廠商及伺服器限制不一定能由腳本還原。
- WebDAV 的串流耗時可能包含打包、壓縮、網路、讀取與守護收尾等待，小檔顯示的低速不能直接當成網路測速結果。
- 程序觀察器與穩定等待不是原子性的「禁止所有新程序啟動」保證。自訂程序名稱、ROM 政策及核心能力仍有限制。
- 備份封裝未因這些安全檢查而加密；HTTP 或 HTTPS 由遠端設定決定。重要資料請另存獨立備份。
- 效能數據及未採用方案見 [更新日誌](CHANGELOG.md)，單機微基準不代表所有 ROM 或完整備份／恢復的加速比例。

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

## 鳴謝貢獻

App 內可從「關於 → 鳴謝」查看頭像與貢獻說明；說明跟隨繁簡語言，名稱保留原樣。

| 貢獻者 | 貢獻內容 |
|--------|----------|
| [kmou424](https://github.com/kmou424)(臭批老k) | 提供部分驗證函數思路 |
| skkk-10p | 提供早期 native static 支持 |
| 雨季少年 | 提供早期 Samba 構建與伺服器支持，遠端備份思路發起者 |
| h1jacker | 提供自動發現 WebDAV 方案，以及早期各種構建支持 |
| [雄氏老方](http://www.coolapk.com/u/665894)(屑老方) | 提供自動更新腳本方案 |
| [sakuradairong](https://github.com/sakuradairong)(雨季騷年/胖子老陳) | 新增 WebDAV / SMB 功能與測試 |
| [XayahSuSuSu](https://github.com/XayahSuSuSu) | 數據備份 App 作者，提供 SELinux context 與腳本早期 Dex 支持 |

`文檔編輯：Petit-Abba, YuKongA`

---

<p align="center">
 <sub>GPL-3.0 Licensed · Made with ❤️ by <a href="https://github.com/YAWAsau">YAWAsau</a></sub>
</p>
