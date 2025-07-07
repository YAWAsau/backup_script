# Backup_script 數據備份腳本
[![Stars](https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars)](https://github.com/YAWAsau)
[![Download](https://img.shields.io/github/downloads/YAWAsau/backup_script/total)](https://github.com/YAWAsau/backup_script/releases)
[![Release](https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release)](https://github.com/YAWAsau/backup_script/releases/latest)
[![License](https://img.shields.io/github/license/YAWAsau/backup_script?label=License)](https://choosealicense.com/licenses/gpl-3.0)
[![Channel](https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram)](https://t.me/yawasau_script)

## 概述

創作該腳本是為了使用戶能夠更加完整地**備份/恢復**應用數據，
支援設備必須符合以下條件：`Android 8+`+`arm64`。

由於本人是台灣人所以發布的版本為繁體版
(CN系統將自動翻譯自身腳本為簡體中文）


## 優勢

- 數據完整：在更換系統之後，原有的數據全部保留，無需重新登陸或者下載額外數據包。
- 支援備份SSAID 可完美備份LINE
- 支援備份應用權限 可備份運行時權限與ops權限
- 易操作：簡單几步即可備份應用完整數據！
- 限制少：不限制機型，可跨安桌版本。
- 功能強：可備份恢復`split apk`。
- 算法多：目前支持的壓縮算法有 `tar(默認)`
- `zstd`。
- 速度快：即使使用`zstd`壓縮算法速率依舊快速（對比鈦備份 swift backup）。
- 腳本自帶tools完整性效驗與壓縮包效驗
## 如何使用
`請認真閱讀以下說明，以減少不必要的問題`

##### 推薦工具：[`MT管理器`](https://www.coolapk.com/apk/bin.mt.plus)，若使用`Termux`，則請勿使用`tsu`。

#### !!!以下操作皆須ROOT!!! ####

1. 首先將下載到的腳本解壓到任意目錄後，可以看到以下目錄結構 警告! 不論備份或是恢復都必須保證tools的存在與完整性 否則腳本失效或是二進制調用失敗。

`這是腳本結構與說明`
```
backup_script.zip
│
├── tools
│       ├── Device_List
│       ├── bc
│       ├── busybox
│       ├── classes.dex
│       ├── cmd             
│       ├── jq                
│       ├── find              
│       ├── keycheck         
│       ├── soc.json
│       ├── tar
│       ├── tools.sh
│       ├── update-binary
│       ├── zip
│       └── zstd
├── backup_settings.conf         <--- 腳本默認行為設置      customize.sh 由 update-binary 执行(sourced)
└── start.sh          <--- 執行腳本
```

2. 然後執行`start.sh`腳本音量鍵選擇生成應用列表，等待腳本輸出提示結束，此時會在當前目錄生成一個`appList.txt`，這就是你當前安裝的所有第三方應用(腳本會屏蔽預裝應用，可於backup_settings.conf設置需要備份包名)。

3. 現在打開生成的`appList.txt`，根據裏面的提示操作後保存，這樣你就設置好了需要備份的軟件。

4. 最後找到`backup_settings.conf`打開後根據提示設置保存，再打開`start.sh`，音量鍵選擇備份應用，備份結束完成後會在當前目錄生成一個以`Backup_壓縮算法名`命名的資料夾，裡面就是你的軟件備份。把這個資料夾整個保持到其他位置，刷完機后複製回手機，直接執行`Backup_壓縮算法名/start.sh`即可恢復備份的所有數據，同樣道理，裡面也有個`appList.txt`，使用方法跟第3步驟一樣，不需要還原的刪除即可，另外進去備份好的資料夾找到單獨應用資料夾有個 backup.sh and recover.sh可以單獨備份與恢復腳本。

5. 腳本執行過程中請留意紅色字眼提示有無任何錯誤，並且使用恢復腳本時留意恢復結束後是否提示應用存在ssaid，假設提示存在ssaid請在恢復後立刻重啟已便套用ssaid,假設恢復ssaid後立刻打開應用會導致ssaid套用失敗，因為Android會產生一個新的saaid，如此會導致應用卡白屏或是提示需要登錄，ssaid是判斷應用是否換過環境與設備的判斷之一，保持一致可以減少諸如提示異地登錄或是需要重新登入驗證的方法。


 ##### 附加說明：如何恢復 以下是關於恢復資料夾內的文件說明?

1. 找到恢復資料夾內的appList.txt打開 編輯列表 保存退出

2. 找到start.sh 給予root音量鍵選擇恢復備份後等待腳本結束即可

3. start.sh的重新生成應用列表功能可用於刷新appList.txt內的列表 使用時機為當你刪除列表內的任何應用備份時,抑或者是恢復備份提示列表錯誤時

4. start.sh的終止腳本功能用於突然想要終止腳本或是意外操作時使用 同理備份也有一個，因為腳本無須後台特性不能使用常規手段終結，故此另外寫了一個終止


# 關於如何更新腳本？
- 目前有三種更新方法，有下列方式
- 1.手動將下載的備份腳本zip不解壓縮直接放到腳本任意目錄(不包括tools目錄內)的任意地方執行任何腳本即可更新，腳本將提示
- 2.此備份的任何腳本在執行時均會聯網檢測腳本版本，當更新時會自己提示與下載，根據腳本提示操作的即可(conf update=1時生效),腳本聯網僅作為檢查更新用途，無任何非法操作亦或是下發格機
- 3.將下載的壓縮包不解壓縮直接放在/storage/emulated/0/Download腳本自動檢測更新，並按照提示操作即可
- 4.在QQ群內下載的腳本不解壓縮腳本會自己檢測更新

## 關於反饋
- 如果使用過程中出現問題，請攜帶截圖並詳細說明問題，建立 [issues](https://github.com/YAWAsau/backup_script/issues)。
- 酷安 @[落葉淒涼TEL](http://www.coolapk.com/u/2277637)
- QQ組 976613477 很少上 盡量來TG
- TG https://t.me/yawasau_script

## 答疑
- 一個shell腳本內為什麼有dex?
- dex用來實現腳本難以實現的目的，目前saaid備份恢復，備份恢復運行時權限與ops權限，下載與訪問GitHub api來檢查腳本更新，列出使用者應用名稱與包名，繁體轉簡體均為dex的功能，感謝[Android-DataBackup](https://github.com/XayahSuSuSu/Android-DataBackup) by [XayahSuSuSu](https://github.com/XayahSuSuSu)

## 常見問題

Q1：批量備份大量提示失敗怎麼辦？
A1：退出腳本，刪除/data/backup_tools，再備份一次

Q2：批量恢復大量提示失敗怎麼辦？
A2：退出腳本，按照上面同樣操作。 如果還是錯誤，請建立issues，我幫你排除錯誤

Q3：微信/QQ 能不能完美備份&恢復數據？
A3：不能保證，有的人說不能有的人說能，所以備份會有提示。 建議用你信賴的備份軟件針對微信/QQ再備份一次，以防丟失重要數據

Q4：為什麼部分應用備份很久？ 例如王者榮耀、PUBG、原神、微信、QQ。
A4：因為連同軟件數據包都給你備份了，例如原神數據包9GB+，當然久到裂開了，恢復也是同理，還要解壓縮數據包

Q5:腳本每次備份都是全新備份嗎？
A5;腳本備份時會比對上次備份時的備份SIZE大小 如果有差異就備份,反之忽略備份節省時間

備份腳本耗費了我大量時間與精力 如果你覺得好用，可以捐贈XD
.(https://paypal.me/YAWAsau?country.x=TW&locale.x=zh_TW))


## 銘謝貢獻
- 臭批老k([kmou424](https://github.com/kmou424))：提供部分與驗證函數思路
- 屑老方([雄氏老方](http://www.coolapk.com/u/665894))：提供自動更新腳本方案
- 胖子老陳(雨季騷年)
- XayahSuSuSu([XayahSuSuSu](https://github.com/XayahSuSuSu))：提供App支持,dex支持

`文檔編輯：Petit-Abba, YuKongA`
