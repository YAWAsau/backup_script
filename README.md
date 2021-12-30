# Backup_script 數據備份腳本
![主圖](https://github.com/Petit-Abba/backup_script_zh-CN/blob/main/File/mmexport1631297795059.png)
[![Stars](https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars)](https://github.com/YAWAsau)
[![Download](https://img.shields.io/github/downloads/YAWAsau/backup_script/total)](https://github.com/YAWAsau/backup_script/releases)
[![Release](https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release)](https://github.com/YAWAsau/backup_script/releases/latest)
[![License](https://img.shields.io/github/license/YAWAsau/backup_script?label=License)](https://choosealicense.com/licenses/gpl-3.0)

<div align="center">
<span style="font-weight: bold"><a href=README.md> 简体中文</a> | 繁體中文  </span>
</div>

## 概述

創作該腳本是為了使用戶能夠更加完整地**備份/恢復**應用數據，
支援設備必須符合以下條件：`Android 8+`+`Arm 64`。

由於本人是台灣人所以發布的版本為繁體版，如果需要**简体版**，可前往這裡下載：
> 简体中文版：[backup_script_zh-CN](https://github.com/Petit-Abba/backup_script_zh-CN) 。

PS. 簡體版本使用 Github Action 自動構建，30分鐘執行一次，所以在原倉庫發布新 release 後，不會立馬更新简体版。

## 優勢

- 數據完整：在更換系統之後，原有的數據全部保留，無需重新登陸或者下載額外數據包。
- 易操作：簡單几步即可備份應用完整數據！
- 限制少：不限制機型，可跨安桌版本。
- 功能強：可備份恢復`split apk`。
- 算法多：目前支持的壓縮算法有 `tar(默認)` `lz4` `zstd`。
- 速度快：即使使用`zstd`壓縮算法速率依舊快速（對比鈦備份 swift）。

## 如何使用
`請認真閱讀以下說明，以減少不必要的問題`

##### 推薦工具：[`MT管理器`](https://www.coolapk.com/apk/bin.mt.plus)，若使用`Termux`，則請勿使用`tsu`。

#### !!!以下操作皆須ROOT!!! ####

1. 首先將下載到的`數據備份脚本.zip`解壓到任意目錄後，可以看到以下4個文件或目錄：`Getlist.sh` `backup_settings.conf` `backup.sh` `tools`。

2. 然後執行`Getlist.sh`腳本，並等待腳本輸出結束[[示意圖]](https://raw.githubusercontent.com/YAWAsau/backup_script/0a08a49865fd9ec36d4fedd3e76ec68f841ff1d7/DCIM/Screenshot_20211230-185717_MT%E7%AE%A1%E7%90%86%E5%99%A8-01.jpeg)，再等待提示結束 [[示意圖]](https://raw.githubusercontent.com/YAWAsau/backup_script/master/DCIM/Screenshot_20211230-190000_MT%E7%AE%A1%E7%90%86%E5%99%A8-01.jpeg) [[示意圖]](https://raw.githubusercontent.com/YAWAsau/backup_script/master/DCIM/Screenshot_20211230-185941_MT%E7%AE%A1%E7%90%86%E5%99%A8-01.jpeg)，此時會在當前目錄生成一個`appList.txt`，這就是你當前安裝的所有第三方應用。

3. 現在打開生成的`appList.txt`，根據裏面的提示操作後保存[[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/3.png)，這樣你就設置好了需要備份的軟件。

4. 最後找到`backup_settings.conf`打開[[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/5.png)，再打開`backup.sh`，等候備份結束。完成後會在當前目錄生成一個以`Backup_壓縮算法名`命名的資料夾，裡面就是你的軟件備份。把這個資料夾整個保持到其他位置，刷完機后複製回手機，直接在資料夾裡找到`Restorebackup.sh`即可恢復備份的所有數據，同樣道理，裡面也有個`appList.txt`，使用方法跟第3步驟一樣，不需要還原的刪除即可。

 ##### 附加說明：如何恢復 以下是關於恢復資料夾內的文件說明?
```
1. 找到恢復資料夾內的appList.txt打開 編輯列表 保存退出

2. 找到Restorebackup.sh 給予root後等待腳本結束即可

3. recovery.conf可決定批量恢復的恢復模式

4. DumpName.sh可用於刷新appList.txt內的列表 使用時機為當你刪除列表內的任何應用備份時,抑或者是Restorebackup.sh提示列表錯誤時

5. delete_backup.sh用於刪除未安裝的備份
```

## 關於反饋
- 如果使用過程中出現問題，請攜帶截圖並詳細說明問題，建立 [issues](https://github.com/YAWAsau/backup_script/issues)。
- 酷安 @[落葉淒涼TEL](http://www.coolapk.com/u/2277637)
- QQ組 976613477

## 常見問題
```
Q1：批量備份大量提示失敗怎麼辦？
A1：退出腳本，刪除/data/backup_tools，再備份一次

Q2：批量恢復大量提示失敗怎麼辦？
A2：退出腳本，按照上面同樣操作。 如果還是錯誤，請建立issues，我幫你排除錯誤

Q3：微信/QQ 能不能完美備份&恢復數據？
A3：不能保證，有的人說不能有的人說能，所以備份會有提示。 建議用你信賴的備份軟件針對微信/QQ再備份一次，以防丟失重要數據

Q4：為什麼部分應用備份很久？ 例如王者榮耀、PUBG、原神、微信、QQ。
A4：因為連同軟件數據包都給你備份了，例如原神數據包9GB+，當然久到裂開了，恢復也是同理，還要解壓縮數據包
```

## 銘謝貢獻
- 臭批老k([kmou424](https://github.com/kmou424))：提供部分與驗證函數思路
- 屑老方([雄氏老方](http://www.coolapk.com/u/665894))：提供自動更新腳本方案
- 依心所言&情非得已c：提供appinfo替代aapt作為更高效的dump包名
- 胖子老陳(雨季騷年)
- XayahSuSuSu([XayahSuSuSu](https://github.com/XayahSuSuSu))：提供App支持
`文檔編輯：Petit-Abba, YuKongA`
