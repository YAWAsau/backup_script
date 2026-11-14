# 常見問題與診斷

[返回首頁](../README.md) · [使用指南](USER_GUIDE.md) · [設定參考](CONFIGURATION.md) · [常見問題](FAQ.md) · [架構說明](ARCHITECTURE.md)

## 日誌與 debug

日常請在 App 的「執行日誌」查看工作狀態，可跟隨最新或翻頁回看；不需要開啟終端追蹤輸出。背景同時會在 `log/` 保存相容日誌，例如：

```text
log/log_2026-07-25_21-40.txt
```

同時，完整診斷資料會打包到 speed_debug：

```text
/data/speed_debug/speed_debug_session_<工作階段識別碼>.tar
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

## 常見問題

### 為什麼首頁顯示 SMB 2.0.2，而不是 3.1.1？

首頁顯示最近一次有效驗證連線的協商結果。版本取決於客戶端與伺服器共同支援及允許的協定，並非固定顯示最高設定值；SMB1 仍停用。若沒有明確協商回報，介面會標示未回報，離線或設定變更後也不沿用舊版本。

### 為什麼繁體的「腳本」變成「指令碼」？

`s2twp` 包含臺灣地區詞彙轉換，不只改字形。專案也保留少量指定用詞，例如儲存資訊標籤的繁體「硬碟」／簡體「存储」。原始路徑、識別碼與不應翻譯的資料保留原文。

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

## 目前核驗範圍

- 備份預估大小與實際打包大小分開核對，跳過、未知與失敗項目分開處理；沒有有效預掃計畫的項目不能只靠數值相同判定通過。
- 恢復清單檢查可發現缺檔、類型、大小與連結等差異，不包含逐檔內容雜湊及完整 SELinux／ACL 驗證。
- AppState／SSAID 核對通過後，仍需實際開啟 App 確認資料與登入；系統、廠商及伺服器限制不一定能由腳本還原。
- WebDAV 的串流耗時可能包含打包、壓縮、網路、讀取與守護收尾等待，小檔顯示的低速不能直接當成網路測速結果。
- 程序觀察器與穩定等待不是原子性的「禁止所有新程序啟動」保證。自訂程序名稱、ROM 政策及核心能力仍有限制。
- 備份封裝未因這些安全檢查而加密；HTTP 或 HTTPS 由遠端設定決定。重要資料請另存獨立備份。
- 效能數據及未採用方案見 [更新日誌](../CHANGELOG.md)，單機微基準不代表所有 ROM 或完整備份／恢復的加速比例。
