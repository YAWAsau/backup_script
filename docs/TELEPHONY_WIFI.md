# SpeedBackup v790 強制結束通知版

v789：App 與自訂媒體／資料夾備份、恢復的整輪工作結束後，只發送一次系統通知與提示音。無論成功或失敗，文字固定為「備份結束」或「恢復結束」，不表示操作成功；結果仍以終端與日誌為準。涵蓋原選單、本地／遠端串流、獨立入口及背景執行，WiFi／通訊等內部階段不重複提示。

v790：結束通知強制送出，不受 notification_enable 控制；此開關只控制既有一般／進度通知。設定為 0 時一般／進度通知仍關閉，結束仍通知並響一次。不修改使用者的此項設定。進度通知啟用時維持靜音；結束使用獨立的「SpeedBackup 結束提示」頻道與系統預設通知音，不強制更改音量、勿擾或使用者頻道設定。正常收尾與可捕捉的 EXIT 失敗共用一次性處理；斷電、強制殺程序、Android 通知服務不可用時無法保證送達。通知錯誤不改變備份／恢復退出碼。

修正 Android mksh 背景子程序不繼承 EXIT handler 的問題；背景工作自行收尾再交接父程序。Root 建立通知頻道時明確使用實際系統套件 UID，避免 UID 0 與 android/1000 不一致而被通知服務丟棄。通知 IPC 重試以操作識別去重。保留 v788 副使用者共用簡訊略過保護，Rust 工具沿用 v782。

驗證範圍與限制請見 BUILD_MANIFEST.json 的 operationCompletion。本版 PATCH 適用已有 v782 或更新原生工具的目錄；完整 TEST 包包含全部工具。只在腳本閒置時覆蓋 tools 內同名檔案。

## 既有通訊與 WiFi 功能

v788：副使用者恢復簡訊／MMS 前，先檢查 SMS 與 MMS Provider。若系統宣告 singleUser 且實際 Provider 屬於其他使用者，明確顯示「略過簡訊／MMS 恢復：系統共用資料無法隔離」，不下載訊息封裝、不寫入、不宣稱恢復成功，並繼續通話等後續項目。原始 DEX 恢復命令仍拒絕此情況；未解鎖、使用者不存在或其他 Provider 錯誤仍回報失敗。未加入共用資料放行選項。主使用者恢復行為不變，副使用者備份仍拒絕共用簡訊，避免把共用資料標為獨立備份。

備用機 user 11 原功能 11 實測：略過共用簡訊後繼續恢復通話；user 0 的 SMS/MMS 封裝內容摘要前後一致，測試通話只在 user 11。原設定已還原、合成通話已清除、test 使用者保留。Shell 另驗證略過時不讀封裝、一般錯誤不吞掉、独立 Provider 與 user 0 路徑可繼續。這台 ROM 無獨立副使用者簡訊 Provider，因此獨立路徑以替身測試，不能宣稱真實副使用者簡訊恢復通過。App 與 WiFi 流程未改，本輪未重跑。DEX 更新為 v788，Rust 沿用 v782。

v787：修正非主使用者 `am start-user` 讀取選單標準輸入，造成管線輸入被吃掉、未執行備份就結束的問題；啟動使用者改接 `/dev/null`。通訊 DEX 沿用 v786、Rust 沿用 v782。

使用既有 test／user 11，由原功能 2 備份、原功能 11 串流恢復。user、user_de、Android/data、Android/obb、Android/media 五個路徑刪除合成標記後均恢復且 SHA-256 一致，AppState 一致；遠端 APK 與五項資料封裝、WiFi、通話索引確認存在。恢復順序為 App 完成後 WiFi、通話，終端沒有原始 TELEPHONY 診斷。另刪除 user 11 的單筆合成通話後，以原功能 11 確認新增 1 筆；user 0 查不到該紀錄。原設定和清單已還原、合成資料已清除，使用者建立的 test／user 11 保留。

這台 ROM 將 user 11 的 SMS/MMS Provider 導回 user 0，因此新版拒絕讀寫，本輪未備份副使用者訊息。WiFi 是系統服務設定，不宣稱每個使用者獨立。APK 因同版本已安裝而跳過重裝；未測其他 ROM、SMB、自定義資料夾或逐一 WiFi AP 連線。v787 PATCH 適用已有 v782 或更新原生工具的目錄；完整 TEST 包含全部工具。

v786：訊息／通話直接沿用既有 `user` 設定，Shell、Provider 取得及 DEX 不再固定 user 0。操作前檢查使用者存在且已解鎖；非主使用者檢查實際 Provider UID，遇到系統導回其他使用者時拒絕操作，不會默默備份或恢復主使用者資料。SIM metadata 若只供主使用者使用，副使用者恢復採未指定 SIM，不切換使用者讀取。WiFi 保留系統服務原有行為，未新增按 user 隔離的 WiFi 功能。

真機 user 0 合成 SMS／MMS 附件／通話回歸通過；新建 user 10 後，兩使用者不同合成紀錄的備份、恢復、去重、驗證通過。user 10 真實通話 Provider 匯入一筆合成紀錄後可驗證、重複不新增，user 0 查不到該紀錄。不存在及已停止使用者被拒絕。這台 ROM 的 user 10 訊息 Provider 會導回 user 0，因此明確拒絕，不能宣稱副使用者真實 SMS/MMS 恢復已通過。臨時使用者及合成通話已移除；部署後原選單的 user 0 通訊／WiFi 恢復通過，設定已還原。logcat 有檢查，但未找到本次相關 Provider 條目；使用 DEX 的明確錯誤碼核對拒絕原因。

v785：批量恢復先完成全部 App、AppState 與自定義資料夾階段，再依序恢復 WiFi、訊息、通話。本地與串流流程均移至尾端；串流只選系統資料時不要求 App metadata。選取解析在開始時完成，但不提前寫入系統資料；清單標記順序不影響 WiFi → 訊息 → 通話的固定順序。系統資料失敗回傳非零狀態，App 恢復中斷時不繼續尾端遠端操作。備份維持 WiFi → 訊息 → 通話。

本輪備用機實測混合恢復及僅系統資料恢復；本地順序與失敗回傳以 Android mksh／替身 Provider 驗證。Dex 沿用 v783，Rust 沿用 v782。原設定與清單在測試後還原。

v784：補上 App `Android/media/<package>` 在串流恢復迴圈及 metadata mask 的漏項。已部署至備用機原目錄，使用原功能 2 備份、原功能 11 恢復 123云盘。遠端 APK、CE、DE、data、obb、media、WiFi、簡訊、通話共 9 項封裝確認存在。移除本地合成標記後，五種資料路徑全部恢復且 SHA-256 一致；AppState 驗證一致。新 WiFi 備份 11 筆與恢復後設定／金鑰比對通過；簡訊 94、通話 36 筆均跳過重複。備份及恢復退出碼均為 0，原設定與清單已還原、測試標記已清除、部署雜湊與鎖釋放已核對。

本輪 APK 因相同版本已安裝而略過重装；未測自定義資料夾、Thanox/HMA、SMB、跨 ROM 或逐一 WiFi AP 連線。Dex 沿用 v783，Rust 沿用 v782。v784 PATCH 適用已具 v782 原生工具的目錄；完整 TEST 包包含全部工具。獨立遠端測試備份保留於 `Backup_zstd_0_pathcheck_0`。

v783：原功能 11 補上所選 `wifi` 的恢復流程，支援 WiFi 單獨或與通訊／App 混合選取。遠端 WiFi 資料直接傳入 DEX，完整讀取並解析後才套用，輸入上限 16 MiB，不建立本地 WiFi 備份檔。下載或恢復失敗回傳失敗，不顯示完成。`TELEPHONY_*` 診斷只寫入日誌，終端保留易讀的完成／失敗提示。

備用機實測原選單 11：恢復 5 筆 WiFi，並確認系統設定中存在；簡訊 94 筆、通話 36 筆均辨識為既有紀錄，新增 0 筆。新版 DEX 合成 SMS／MMS 附件／通話測試、WiFi 標準輸入解析，以及 Shell 下載／DEX 失敗與輸出隔離測試通過。未測跨 ROM、SMB 或本輪完整 App 恢復。Rust 沿用 v782。

需要恢復 WiFi 時，在 `appList_network.txt` 保留獨立的 `wifi` 行，再使用功能 11。

v782：修權排除／擁有者／SELinux 彙整與程序鎖移入 Rust speedscan。Shell 僅保留呼叫、UI 及退出生命週期，不再逐子目錄啟動修權工具。SELinux 直接使用不跟隨 symlink 的 xattr，需系統後備時最多每批 64 個已選節點呼叫非遞迴 restorecon，不重掃 cache；鎖以 PID／process start／boot ID 綁定整個 Shell 生命週期，flock 僅保護取得和回收，釋放時核對 token。保留 `.backup_lock.guard` 檔案作為固定互斥 inode，檔案存在不代表上鎖。

歷史 FIX3：App 恢復後修正擁有者與 SELinux 時，跳過頂層 cache／code_cache（含 CE／DE／外部 data／obb），既有快取不修改，不存在不建立；一般資料使用既有原生掃描器，保留 symlink 不跟隨。修權或標籤修正失敗會使該 payload 失敗。重複啟動不再強制終止目前備份；未知鎖擁有者保守拒絕，失效 PID 以獨立回收鎖序列化處理。

FIX2：修復無 SIM／跨裝置恢復時，來源 SIM 編號不存在而被系統拒絕的問題；不存在的編號改為不指定 SIM，重複比對採相同規則。錯誤診斷納入 debug 包，不記錄簡訊內容。通訊檔案改放 `communications/`，不含舊 `wifi/` 相容讀取。

FIX1：修復通訊恢復清單解析。接受標記後的 `#` 說明、CRLF 與 BOM；未識別的通訊標記明確報錯。通訊項目不再落入 App 缺失清理，也不因其他 App 清理而從原清單遺失。

基於原 v780。原功能 2／3 的備份流程加入 SMS、MMS（含附件）及通話紀錄，功能 8／11 配合選取並串流恢復。沒有新增獨立主選單，也不包含 Rustic。

## 使用

完整 TEST.zip 可解壓至手機內部儲存，使用 root shell 執行 `sh /實際解壓路徑/start.sh`。工具沿用原啟動器的 `/data/backup_tools` 可執行快取。v783 PATCH.zip 供既有 v782 目錄覆蓋同名檔案；先退出原腳本，保留自己的設定與清單。

在原 `backup_settings.conf` 可設定：

```sh
backup_messages=1
backup_calllogs=1
```

原功能 2／3 完成應用備份後會一併備份通訊資料；舊設定未填時兩項預設開啟，設為 0 可個別關閉。Wi-Fi 原功能 5 保留用途。通訊備份失敗會保留前次成功索引，整輪回傳非零退出碼。

遠端恢復：先執行原功能 8，再於 `appList_network.txt` 加入要恢復的獨立行（或按生成的註解說明啟用），最後執行原功能 11：

```text
@telephony:messages
@telephony:calls
```

只保留這兩行也能單獨恢復通訊資料。特殊標記不會送進 APK 恢復流程。恢復前先讀完整個封裝檢查 CRC、結尾計數與 MMS 附件 SHA256，再讀第二遍合併匯入；不建立本地通訊封裝。重複紀錄依內容鍵與出現次數跳過，保留來源中本來就有的相同紀錄，不清空目標資料庫。中途失敗可能已有部分紀錄匯入；失敗的當筆 MMS 會嘗試刪除自己剛新增的紀錄，成功的前面紀錄保留，可重試。

本地備份恢復在 `restore_settings.conf` 明確開啟 `restore_messages=1`／`restore_calllogs=1`，再使用原恢復功能。預設關閉，避免原應用恢復操作意外加入系統紀錄。

## 格式與限制

- 通訊功能依既有 `user` 選擇目標；需要使用者已啟動、解鎖且 ROM 提供該使用者的獨立 Provider。跨使用者導向不會自動回退。不包含 RCS、LINE、WhatsApp、聯絡人或語音信箱音訊。
- `communications/` 目錄下的 `messages.current`／`calls.current` 指向不可變的 `.sbcomm` ZIP 世代；必須連同指向的檔案保存。不能交給 v780 或 Android-DataBackup 直接恢復。
- 新世代完整產生和上傳成功後才更新索引。中斷及舊世代暫不自動回收，因此多次備份會增加遠端用量；這是完整通訊快照，不是區塊增量。
- 串流模式不建立本地 SMS/MMS／通話紀錄封裝；原清單、Wi-Fi 控制檔和日誌仍可能暫存。本地模式則照原設定保存備份。通訊 ZIP 與既有 Wi-Fi Base64 格式均不是加密，沿用原遠端傳輸安全設定。
- 不直接覆蓋系統 SQLite 資料庫。採 Provider 欄位白名單，保留標準欄位；廠商私有欄位及跨裝置 SIM 對應不宣稱完整保留。
- TEST 包預設仍遵循原自動更新設定；測試本版時請在設定檔填 `update=0`，避免被正式發布版本覆蓋。

## Wi-Fi 修復

依原作者 2026-09-17 的恢復強化：檢查 addNetwork 結果、enableNetwork(id, false) 不停用其他網路、Android 11+ 還原 allowAutojoin、略過並回報不支援的 KeyMgmt 類型。保留既有 Base64 備份並接受原始 JSON 陣列。新增完整格式檢查後才以同目錄 rename 發布；失敗不預先清空 Wi-Fi 目錄、不刪除上次備份。恢復失敗不再寫成功紀錄，單獨 Wi-Fi 備份及批量備份會傳回失敗狀態。

來源：[RestoreNetworksHelper，提交 5020a312](https://github.com/XayahSuSuSu/Android-DataBackup/commit/5020a312f9ffa28d65be13385d00666b620ee21f)。資料分類參考同專案 `source-next` 的 BackupMessagesHelper／BackupCallLogsHelper；通訊串流格式及腳本接入為本次實作。沿用原專案 GPL 授權。

## 驗證範圍

Xiaomi 13／Android 17：真實 SMS/MMS／通話 Provider 唯讀探測；無通訊權限的合成 Provider 備份、恢復、重複恢復、Unicode、1 MiB MMS 附件逐位元組核對、附件失敗回滾、錯誤封裝拒絕；原腳本 WebDAV 串流上傳及恢復；Android mksh 失敗索引保護與 Wi-Fi 舊檔保護。另外在使用者授權的備用機成功恢復 94 筆真實 SMS；36 筆通話辨識為既有資料。實際串流備份至原設定遠端的 `communications/` 後再次恢復，94／36 筆均跳過、沒有新增重複；唯讀內容鍵核對通過。通訊 payload 目的地設為不可寫入的 `/proc/no-local-payload`，不建立本地通訊封裝。v783 已實際恢復 5 筆 Wi-Fi 並核對系統設定；未逐一連線驗證各 AP。

未實測：SMB、其他廠牌真實 Provider 寫入、真實 MMS 附件恢復、完整跨 ROM／SIM 相容性、企業 Wi-Fi 憑證轉移、真實 Wi-Fi 連線恢復，以及全量應用備份／恢復回歸。v782 重新編譯 speednative，speedscan 與腳本為 v782；Dex 維持 v781，其他 applet 功能版本及其他原生工具不變。

FIX3 驗證：Android mksh／原生 speedscan 在專用目錄實際修權，確認 cache/code_cache 的 UID/GID、mode、SELinux 完全不變，不建立缺少的快取；隱藏資料與一般資料正確修權；symlink 不修改外部目標；注入 SELinux 失敗得到非零狀態；未知、活動、失效、PID 發布中的鎖，以及六個獨立程序競爭新鎖／失效鎖（連續三輪）通過。沒有以此測試重寫真實 App 資料；通訊／WiFi shell 保護回歸通過。

v782 驗證：Android 原生安全流程重測（快取、缺少快取、symlink、空 context 後備、失敗、活動與失效鎖、錯誤 token），既有 Rust 93 項測試通過。隔離合成資料 2,000 個一般檔案＋3,000 個排除快取檔案、五輪交錯比較，修權中位數 Shell 約 935 ms、Rust 約 81 ms；這是核心修權測試，不是整體恢復倍速保證。
