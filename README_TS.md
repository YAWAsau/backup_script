# backup_script 數據備份腳本
![主圖](https://github.com/Petit-Abba/backup_script_zh-CN/blob/06e06a015a1f672be52d980cb77ec0fd8dc4087d/File/mmexport1631297554615.png)
[![Stars](https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars)](https://github.com/YAWAsau)
[![Download](https://img.shields.io/github/downloads/YAWAsau/backup_script/total)](https://github.com/YAWAsau/backup_script/releases)
[![Release](https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release)](https://github.com/YAWAsau/backup_script/releases/latest)
[![License](https://img.shields.io/github/license/YAWAsau/backup_script?label=License)](https://choosealicense.com/licenses/gpl-3.0)

<div align="center">
    <span style="font-weight: bold"> <a href=README.md> 简体中文 </a> | 繁體中文 </span>
</div>

## 概述
  創作該腳本是為了使用戶能夠更加完整地**備份/恢復**軟件數據。

  (&) 由於本人習慣輸入繁體中文，所以發布的版本為繁體版，如果需要**簡體版**，可前往這裡下載。
  > 簡體中文版：[backup_script_zh-CN](https://github.com/Petit-Abba/backup_script_zh-CN)

## 優勢
   - 數據完整：在更換系統之後，原有的數據全部保留，無需重新登陸或者下載額外數據包。
   - 速度快：目前支持的壓縮算法有 `tar(默認)` `lz4` `zstd`
   - 易操作：下面簡單4步即可備份App完整數據！

## 如何使用
  `請認真閱讀以下說明，以減少不必要的問題。`

  **推薦工具**: [MT管理器](https://www.coolapk.com/apk/bin.mt.plus)

  > 1. __appname.sh__：將zip解壓縮到任意目錄，點擊`appname.sh`並勾選root執行腳本 [[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/1.png)，等待提示結束 [[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/2.png)。

  > 2. __Apkname.txt__：當前目錄下會生成一個`Apkname.txt`，這就是你**要備份的軟件列表**，你可以把**不需要備份的軟件那一行前加上`#`** [[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/3.png)，備份時就會跳過它；如果你只需要備份一兩個軟件，那麼你可以**全選刪除**，然後按照這個格式：`[App名稱 App包名]` 進行填寫需要備份的軟件 [[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/4.png)，這樣就不用一個一個去加`#`了。

  > 3. __backup.sh__：以上簡單兩步你就設置好了需要備份的軟件，接下來點擊`backup.sh`並勾選root執行，等待備份結束 [[示意圖]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/5.png)。

  > 4. __備份完成__：完成後會在當前目錄生成一個Backup資料夾，裡面是你的軟件備份，把這個資料夾整個備份起來，刷完機直接在裡面找到`還原備份.sh`即可恢復備份的所有數據，同樣道理裡面有個name.txt ，一樣跟第二步驟操作一樣不需要還原的刪除。

##### 附加說明[1]：backup_settings.conf (備份設置)
  ```
  1=是  0=否 

  # 是否在每次執行備份腳本使用音量鍵詢問如下備份需求
  Lo=0 (如果是1，那下面三項設置就被忽略，改為音量鍵選擇。)

  # 選擇是否只備份split apk(分割apk檔，1備份split apk 0混合備份)
  C=0

  # 是否備份外部數據 即比如原神的數據包(1備份0不備份)
  B=0

  # 備份路徑位置為絕對位置或是當前環境位置(1環境位置 0腳本所在位置)
  path=0

  # 壓縮算法(可用lz4 zstd tar tar為僅打包 有什麼好用的壓縮算法請聯繫我)
  # lz4壓縮最快，但是壓縮率略差 zstd擁有良好的壓縮率與速度 當然慢於lz4。
  Compression_method=tar
  ```
  `如果上面內容看不懂或者懶得看，你也可以選擇忽略，直接用默認即可。`

##### 附加說明[2]：打包成卡刷包.sh
  ```
  1. ROOT執行 recovery備份包名生成.sh

  2. 編輯 recovery.txt，自己想想如果開不了機只能進第三方rec的時候，你最想備份哪個應用，哪些又是不需要的，對，沒錯，把不需要的刪除。

  3. ROOT執行 打包成卡刷包.sh，執行完成後當前目錄就會出現 recovery備份.zip。

  4. 把 recovery備份.zip 保存好，以後開不了機只能進rec的時候，你就可以卡刷它，把App備份打包出來。
  ```

## 關於反饋
  - 如果使用過程中出現問題，請**攜帶截圖並詳細說明問題**建立[issues](https://github.com/YAWAsau/backup_script/issues)。
  - 酷安@[落葉淒涼TEL](http://www.coolapk.com/u/2277637)

## 常見問題
  ```
  Q：批量備份大量提示失敗怎麼辦？
  A：退出腳本，刪除Backup資料夾，再備份一次。

  Q：批量恢復大量提示失敗怎麼辦？
  A：退出腳本，再執行一次就好，不要刪除資料夾。如果還是錯誤，請建立issues，我幫你排除錯誤。

  Q：微信/QQ 能不能完美備份&恢復數據？
  A：不能保證，有的人說不能有的人說能，所以備份會有提示。建議用你信賴的備份軟件針對微信/QQ再備份一次，以防丟失重要數據。

  Q：為什麼部分APP備份很久？比如王者榮耀、PUBG、原神、微信、QQ。
  A：因為連同軟件數據包都給你備份了，原神數據包9GB 當然久到裂開了，恢復同理，還要解壓縮數據包。
  ```

## 銘謝貢獻
  - 臭批老k([kmou424](https://github.com/kmou424))：提供部分與驗證函數思路
  - 屑老方([雄氏老方](http://www.coolapk.com/u/665894))：提供自動更新腳本方案
  - 依心所言&情非得已c：提供appinfo替代aapt作為更高效的dump包名
  - 胖子老陳(雨季騷年)

  `文檔編輯：Petit-Abba`
