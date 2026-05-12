# Backup_script 數據備份腳本

<p align="center">
  <a href="https://github.com/YAWAsau/backup_script/stargazers"><img src="https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars&style=flat-square" /></a>
  <a href="https://github.com/YAWAsau/backup_script/releases"><img src="https://img.shields.io/github/downloads/YAWAsau/backup_script/total?style=flat-square" /></a>
  <a href="https://github.com/YAWAsau/backup_script/releases/latest"><img src="https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release&style=flat-square" /></a>
  <a href="https://choosealicense.com/licenses/gpl-3.0"><img src="https://img.shields.io/github/license/YAWAsau/backup_script?label=License&style=flat-square" /></a>
  <a href="https://t.me/yawasau_script"><img src="https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram&style=flat-square" /></a>
</p>

---

## 📖 概述

一款專為 Android 設計的完整應用數據備份／恢復 Shell 腳本，支援 SSAID、運行時權限、OBB 數據包、WiFi 設定等完整備份，讓你換機換系統後能無縫還原所有應用狀態。

> 作者為台灣人，預設發布繁體版本。CN 系統環境下腳本將自動翻譯為簡體中文。

**系統需求：** `Android 8+` · `arm64 架構` · `Root 權限（Magisk / KernelSU）`

---

## ✨ 功能特色

| 功能 | 說明 |
|------|------|
| 📦 完整數據備份 | 換機換系統後原有數據完整保留，無需重新登入或下載額外數據包 |
| 🔑 SSAID 備份 | 支援 SSAID 備份，可完美備份 LINE 等依賴設備識別碼的應用 |
| 🛡️ 權限備份 | 支援備份運行時權限（Runtime Permission）與 ops 權限 |
| 📂 Split APK | 支援備份與恢復 Split APK 格式 |
| 🎮 OBB 數據包 | 可選備份外部 OBB 數據（如原神、王者榮耀等大型遊戲） |
| 📡 WiFi 備份 | 支援備份與恢復 WiFi 設定 |
| 📁 自定義資料夾備份 | 可備份 DCIM、Download、Music 等任意自定義目錄 |
| 🗜️ 多種壓縮算法 | 支援 `tar`（僅打包）與 `zstd`（高壓縮率高速度） |
| ⚡ 高速壓縮 | zstd 壓縮速率快速，優於鈦備份、Swift Backup |
| 🔒 完整性校驗 | 內建 tools SHA-256 校驗與壓縮包完整性驗證 |
| 🔄 增量備份 | 比對上次備份大小，無變化則跳過，節省時間 |
| 🖥️ 後台執行 | 支援後台執行模式，可完全關閉終端，log 持續刷新 |
| 💡 偽裝亮屏 | 備份／恢復期間可偽裝亮屏，避免 IO 因息屏降速 |
| 🌐 自動更新 | 聯網偵測最新版本，支援 CDN 節點（適合中國大陸用戶） |
| 🌏 多語言 | 自動識別系統語言環境，支援繁體中文／簡體中文自動切換 |
| 👥 多用戶支援 | 支援多用戶環境（user 0、999 等），可手動或自動選擇用戶 |
| ⬛ 黑名單模式 | 黑名單應用可選「完全忽略」或「僅備份安裝包」 |
| ⬜ 白名單支援 | 支援預裝應用白名單與系統應用白名單，可指定備份範圍 |
| 📱 進程偵測 | 可設定忽略正在運行中的應用，避免備份數據不一致 |
| ☁️ 遠程備份 | 支援 WebDAV / FTP / SMB / SCP 四種協議，備份完成後自動上傳到遠端伺服器 |

---

## 🗂️ 主選單功能

### 備份模式

| 選項 | 功能 |
|------|------|
| 生成應用列表 | 掃描已安裝的第三方應用並生成 `appList.txt` |
| 備份應用 | 根據列表與設定完整備份應用數據 |
| 備份已更新應用 | 僅備份自上次備份以來有版本更新的應用 |
| 備份自定義資料夾 | 備份 `backup_settings.conf` 內設定的自定義目錄 |
| 備份 WiFi | 備份當前設備的 WiFi 設定 |
| 殺死運行中腳本 | 安全終止正在執行的備份腳本 |

### 恢復模式

| 選項 | 功能 |
|------|------|
| 重新生成應用列表 | 刷新恢復資料夾內的 `appList.txt` |
| 恢復備份 | 根據列表完整恢復應用與數據 |
| 僅恢復包含 SSAID 應用（含數據） | 只恢復有 SSAID 的應用及其完整數據 |
| 僅恢復包含 SSAID 應用（不含數據） | 只套用 SSAID，不覆蓋現有數據 |
| 恢復自定義資料夾 | 恢復備份的自定義目錄 |
| 恢復 WiFi | 恢復已備份的 WiFi 設定 |
| 壓縮檔完整性檢查 | 驗證備份壓縮包是否完整無損 |
| 轉換文件夾名稱 | 將備份資料夾名稱格式轉換（用於跨版本相容） |
| 殺死運行中腳本 | 安全終止正在執行的恢復腳本 |

---

## 📁 目錄結構

```
backup_script.zip
│
├── tools/
│   ├── busybox          # 核心工具集
│   ├── zstd             # zstd 壓縮工具
│   ├── tar              # tar 打包工具
│   ├── curl             # 遠程傳輸工具 (WebDAV/FTP/SMB)
│   ├── scp / ssh        # SCP 遠程傳輸
│   ├── jq               # JSON 處理
│   ├── bc               # 數學計算
│   ├── find             # 文件搜索
│   ├── keycheck         # 音量鍵監聽
│   ├── cmd              # 系統指令橋接
│   ├── classes.dex      # Java 功能擴展（詳見下方說明）
│   ├── soc.json         # 處理器資料庫
│   ├── Device_List      # 設備型號資料庫
│   └── tools.sh         # 核心腳本
│
├── backup_settings.conf  # 備份行為設定檔
└── start.sh              # 主執行腳本
```

> ⚠️ **重要：** 無論備份或恢復，都必須確保 `tools/` 目錄完整存在，否則腳本將無法正常運作。

---

## ⚙️ 設定檔說明（backup_settings.conf）

| 設定項 | 說明 | 預設值 |
|--------|------|--------|
| `Lo` | 操作方式：`0` 音量鍵 / `1` 音量鍵（強制） / `2` 鍵盤輸入 | `0` |
| `background_execution` | 後台執行：`1` 可關閉終端 / `0` 需保持終端開啟 | `0` |
| `setDisplayPowerMode` | 備份期間偽裝亮屏防止 IO 降速 | `0` |
| `Shell_LANG` | 語言：`0` 繁體中文 / `1` 簡體中文（留空自動偵測） | 自動 |
| `Output_path` | 自定義備份輸出路徑，支援相對路徑（留空使用當前目錄） | 空 |
| `list_location` | 自定義 appList.txt 位置（留空使用當前目錄） | 空 |
| `update` | 自動更新：`1` 開啟 / `0` 關閉 | `1` |
| `cdn` | 更新 CDN 節點：`0` 直連 / `1` ghfast.top / `2` workers.dev | `1` |
| `mount_point` | 屏蔽外部掛載點（OTG、虛擬 SD 等），多個用 `\|` 分隔 | `rannki\|0000-1` |
| `user` | 指定用戶 ID（留空自動選擇） | 空 |
| `Backup_Mode` | 備份模式：`1` 應用+數據 / `0` 僅安裝包 | `1` |
| `Backup_user_data` | 備份 user 數據：`1` 是 / `0` 否 | `1` |
| `Backup_obb_data` | 備份 OBB 外部數據：`1` 是 / `0` 否 | `1` |
| `backup_media` | 備份完成後一併備份自定義資料夾 | `0` |
| `Background_apps_ignore` | 忽略正在運行中的應用：`1` 忽略 / `0` 備份 | `0` |
| `Custom_path` | 自定義備份目錄列表（絕對路徑，每行一個） | DCIM / Download 等 |
| `blacklist_mode` | 黑名單模式：`1` 完全忽略 / `0` 僅備份安裝包 | `0` |
| `blacklist` | 黑名單應用包名列表 | 空 |
| `whitelist` | 預裝應用白名單包名列表 | 小米系列預裝 |
| `system` | 系統應用白名單包名列表 | Google 系列 |
| `Compression_method` | 壓縮算法：`zstd` 或 `tar` | `zstd` |
| `rgb_a` / `rgb_b` / `rgb_c` | 終端輸出主色／輔色（256 色代碼） | `226` / `123` / `177` |
| `remote_type` | 遠程備份協議：`webdav` / `ftp` / `smb` / `scp`（留空不啟用） | 空 |
| `remote_url` | 遠程伺服器地址（見下方格式說明） | 空 |
| `remote_user` | 遠程認證用戶名 | 空 |
| `remote_pass` | 遠程認證密碼 | 空 |

---

## 🚀 使用方式

> 推薦使用 [MT 管理器](https://www.coolapk.com/apk/bin.mt.plus) 執行腳本。若使用 Termux，請勿使用 `tsu`。

### 備份流程

**Step 1 — 生成應用列表**

解壓腳本後執行 `start.sh`，選擇「**生成應用列表**」。執行完畢後，當前目錄會生成 `appList.txt`，內含所有已安裝的第三方應用（預裝應用預設屏蔽，可於 `backup_settings.conf` 加入白名單）。

**Step 2 — 編輯應用列表**

打開 `appList.txt`，根據需求調整：
- 行首加 `#`：注釋掉該應用，不備份
- 行首加 `!`：僅備份安裝包，不備份數據

**Step 3 — 設置備份選項**

打開 `backup_settings.conf`，根據上方設定說明調整各選項後儲存。

**Step 4 — 執行備份**

執行 `start.sh`，選擇「**備份應用**」。備份完成後，當前目錄會生成 `Backup_<壓縮算法>_<用戶ID>/` 資料夾，將此資料夾完整保存至安全位置。

---

### 恢復流程

**Step 1 — 編輯恢復列表**

進入備份資料夾，打開 `appList.txt`，刪除或注釋不需要恢復的應用行。

**Step 2 — 執行恢復**

執行備份資料夾內的 `start.sh`，選擇「**恢復備份**」，等待腳本完成。

**Step 3 — 注意 SSAID**

若恢復結束後提示應用存在 SSAID，請**立刻重啟**後再開啟應用。若先開啟應用，Android 會生成新的 SSAID，導致應用白屏或需要重新登入。

> 💡 備份資料夾內每個應用子目錄都有獨立的 `backup.sh` 與 `recover.sh`，可單獨備份或恢復單一應用。

---

### 遠程備份

備份完成後自動將備份檔案上傳到遠端伺服器，支援四種協議：

| 協議 | `remote_url` 格式 |
|------|-------------------|
| WebDAV | `http://192.168.1.100:8080/dav/backup/` |
| FTP | `ftp://192.168.1.100/backup/` |
| SMB | `smb://192.168.1.100/share/backup/` |
| SCP | `192.168.1.100:/home/user/backup/` |

**設定方式：** 編輯 `backup_settings.conf`：
```conf
remote_type=webdav
remote_url=http://192.168.1.100:8080/dav/backup/
remote_user=用戶名
remote_pass=密碼
```

**SCP 注意事項：** SCP 優先使用 `sshpass` 進行密碼認證，若不支援則自動嘗試 SSH 密鑰認證。需確保遠端已安裝 SSH 伺服器。

**上傳範圍：** 僅上傳備份數據（應用檔案、WiFi、appList.txt），排除 `tools/`、`start.sh`、`restore_settings.conf` 等腳本文件。

---

## 🔄 腳本更新方式

支援以下四種更新方式：

1. **ZIP 放置更新**：將下載的 `.zip` 不解壓，直接放到腳本任意目錄（`tools/` 除外），執行任何腳本即自動更新。
2. **聯網自動更新**：腳本執行時自動連線 GitHub API 檢查版本，發現新版本時提示下載（需設置 `update=1`）。
3. **Download 目錄**：將 `.zip` 放置於 `/storage/emulated/0/Download/`，腳本自動偵測並更新。
4. **QQ 群下載**：從 QQ 群下載的腳本不解壓，直接放置後執行即可自動更新。

> 🔒 腳本聯網**僅用於檢查更新**，無任何資料收集或非法操作。

---

## ❓ 常見問題

<details>
<summary><b>Q1：批量備份／恢復大量提示失敗？</b></summary>

退出腳本，刪除 `/data/backup_tools/` 目錄後重新執行。若問題持續，請建立 [Issue](https://github.com/YAWAsau/backup_script/issues) 並附上截圖與 log。
</details>

<details>
<summary><b>Q2：微信／QQ 能完美備份恢復嗎？</b></summary>

無法保證。建議同時使用其他你信賴的備份工具針對微信／QQ 額外備份，以防丟失重要數據。
</details>

<details>
<summary><b>Q3：為什麼部分應用備份很久？</b></summary>

腳本會一同備份應用的 OBB 數據包，例如原神數據包超過 9GB，備份與恢復時間自然較長。可在 `backup_settings.conf` 設置 `Backup_obb_data=0` 跳過 OBB 備份。
</details>

<details>
<summary><b>Q4：腳本每次都是全量備份嗎？</b></summary>

否。腳本會比對上次備份的檔案大小，若無差異則跳過該應用，節省時間與空間。
</details>

<details>
<summary><b>Q5：為什麼腳本內包含 .dex 檔案？</b></summary>

`classes.dex` 用於實現 Shell 腳本難以達成的功能，包含：

- SSAID 備份與恢復
- 運行時權限（Runtime Permission）與 ops 權限備份恢復
- GitHub API 更新版本檢查與下載
- 應用名稱與包名查詢
- 繁體中文 ↔ 簡體中文自動翻譯
- 後台執行模式的推送通知

感謝 [XayahSuSuSu](https://github.com/XayahSuSuSu) 的 [Android-DataBackup](https://github.com/XayahSuSuSu/Android-DataBackup) 提供 App 支持。
</details>

<details>
<summary><b>Q6：息屏後備份速度變慢？</b></summary>

這是 Android 內核的 IO 節能機制導致的。建議在 `backup_settings.conf` 設置 `setDisplayPowerMode=1` 開啟偽裝亮屏，或在備份期間保持螢幕常亮。
</details>

<details>
<summary><b>Q7：如何單獨備份或恢復單一應用？</b></summary>

進入備份資料夾內對應的應用子目錄，直接執行 `backup.sh`（單獨備份）或 `recover.sh`（單獨恢復）即可。
</details>

---

## 📬 問題反饋

遇到問題請攜帶截圖與 log 檔，透過以下方式反饋：

- 🐛 [GitHub Issues](https://github.com/YAWAsau/backup_script/issues)
- 💬 [Telegram 頻道](https://t.me/yawasau_script)
- 🐧 QQ 群：`976613477`
- 🧊 酷安：[@落葉淒涼TEL](http://www.coolapk.com/u/2277637)

---

## ☕ 支持作者

備份腳本耗費了大量時間與精力，如果你覺得好用，歡迎贊助支持！

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=flat-square&logo=paypal)](https://paypal.me/YAWAsau?country.x=TW&locale.x=zh_TW)

---

## 🙏 銘謝貢獻

| 貢獻者 | 貢獻內容 |
|--------|----------|
| [kmou424](https://github.com/kmou424)（臭批老k） | 提供部分驗證函數思路 |
| [雄氏老方](http://www.coolapk.com/u/665894)（屑老方） | 提供自動更新腳本方案 |
| 雨季騷年（胖子老陳） | 協助測試 |
| [XayahSuSuSu](https://github.com/XayahSuSuSu) | 提供 App 支持與 dex 功能支持 |

`文檔編輯：Petit-Abba, YuKongA`

---

<p align="center">
  <sub>GPL-3.0 Licensed · Made with ❤️ by <a href="https://github.com/YAWAsau">YAWAsau</a></sub>
</p>
