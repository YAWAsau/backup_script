# SpeedBackup

Android 應用與資料備份工具，提供原生 App 介面、本地備份及 SMB／WebDAV 遠端備份。

<p align="center">
 <a href="https://deepwiki.com/YAWAsau/backup_script"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki" /></a>
 <a href="https://github.com/YAWAsau/backup_script/stargazers"><img src="https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars&style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases"><img src="https://img.shields.io/github/downloads/YAWAsau/backup_script/total?style=flat-square" /></a>
 <a href="https://github.com/YAWAsau/backup_script/releases/latest"><img src="https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release&style=flat-square" /></a>
 <a href="https://choosealicense.com/licenses/gpl-3.0"><img src="https://img.shields.io/github/license/YAWAsau/backup_script?label=License&style=flat-square" /></a>
 <a href="https://t.me/yawasau_script"><img src="https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram&style=flat-square" /></a>
</p>

<p align="center">
  <a href="https://github.com/YAWAsau/backup_script/releases/latest">下載最新版</a> ·
  <a href="docs/USER_GUIDE.md">使用指南</a> ·
  <a href="docs/FAQ.md">常見問題</a> ·
</p>

## 特色

- **應用與資料**：批次備份／恢復 APK、Split APK、應用資料、OBB、自訂資料夾及 Wi-Fi 設定。
- **應用狀態**：支援 SSAID、權限、AppOps 與電池策略等狀態的備份與恢復。
- **本地與遠端**：支援 SMB／WebDAV、自動搜尋設備及串流備份／恢復，減少本機暫存空間需求。
- **連線狀態**：已保存連線先在背景驗證；首頁顯示驗證連線實際協商的 SMB 版本，離線後清除舊值。
- **跳過未變更項目**：依版本、大小與狀態紀錄判斷是否需要重新備份。
- **雙介面風格**：Material／Miuix、深淺色、壁紙與液態玻璃，支援繁體／簡體中文，切換時同步轉換地區用詞。
- **背景工作**：關閉畫面後繼續執行，重新啟動可接回進度；提供日誌、狀態通知與除錯包。


## 開始使用

**需求：Android 9 以上、arm64 裝置及 Root 權限（Magisk／KernelSU）。**

1. 從 [Releases](https://github.com/YAWAsau/backup_script/releases/latest) 下載完整手機執行包並解壓。
2. 使用已取得 Root 權限的 MT 管理器或終端執行 `start.sh`，依提示進入 SpeedBackup App。
3. 在「設定 → 備份設定」選擇備份位置與項目，儲存後到功能頁開始備份。

本地恢復請執行備份目錄中的 `start.sh`；遠端恢復可從 App 選擇先下載或串流恢復。完整步驟見 [使用指南](docs/USER_GUIDE.md)。

更新前請讓工作正常結束並退出腳本，使用同一發行包的完整工具。GitHub 自動產生的 **Source code** 壓縮檔是原始碼，不能當作完整手機執行包。

## 文件

| 想了解的內容 | 文件 |
|---|---|
| 備份、恢復、遠端連線、外觀與更新 | [使用指南](docs/USER_GUIDE.md) |
| 進階設定欄位 | [設定檔參考](docs/CONFIGURATION.md) |
| 常見問題、日誌與核驗範圍 | [問題排查](docs/FAQ.md) |
| 後端分工、資料格式與相容性 | [架構說明](docs/ARCHITECTURE.md) |

## 問題回報

請附上版本、重現步驟、截圖及 App 匯出的 `speed_debug` 除錯包。

- [GitHub Issues](https://github.com/YAWAsau/backup_script/issues)
- [Telegram 頻道](https://t.me/yawasau_script)
- QQ 群：`976613477`
- 酷安：[@落葉淒涼TEL](http://www.coolapk.com/u/2277637)

## 鳴謝

感謝所有提供程式碼、想法、測試與文件協助的貢獻者。

<details>
<summary>查看貢獻者與貢獻內容</summary>

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

</details>

第三方元件及授權見 [開源授權說明](docs/OPEN_SOURCE_LICENSES.md)。

## 支持與授權

如果 SpeedBackup 對你有幫助，歡迎 [贊助支持](https://paypal.me/YAWAsau?country.x=TW&locale.x=zh_TW)。

本專案採用 [GNU GPL v3.0](LICENSE)，第三方元件依各自授權條款提供。
