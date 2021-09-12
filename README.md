# backup_script 数据备份脚本
![主图](https://github.com/Petit-Abba/backup_script_zh-CN/blob/06e06a015a1f672be52d980cb77ec0fd8dc4087d/File/mmexport1631297554615.png)
[![Stars](https://img.shields.io/github/stars/YAWAsau/backup_script?label=stars)](https://github.com/YAWAsau)
[![Download](https://img.shields.io/github/downloads/YAWAsau/backup_script/total)](https://github.com/YAWAsau/backup_script/releases)
[![Release](https://img.shields.io/github/v/release/YAWAsau/backup_script?label=release)](https://github.com/YAWAsau/backup_script/releases/latest)
[![License](https://img.shields.io/github/license/YAWAsau/backup_script?label=License)](https://choosealicense.com/licenses/gpl-3.0)

<div align="center">
    <span style="font-weight: bold"> 简体中文 | <a href=README_TS.md> 繁体中文 </a> </span>
</div>

## 概述
  创作该脚本是为了使用户能够更加完整地**备份/恢复**软件数据。

  (&) 由于本人习惯输入繁体中文，所以发布的版本为繁体版，如果需要**简体版**，可前往这里下载。
  > 简体中文版：[backup_script_zh-CN](https://github.com/Petit-Abba/backup_script_zh-CN)

## 优势
   - 数据完整：在更换系统之后，原有的数据全部保留，无需重新登陆或者下载额外数据包。
   - 速度快：目前支持的压缩算法有 `tar(默认)` `lz4` `zstd`
   - 易操作：下面简单4步即可备份App完整数据！

## 如何使用
  `请认真阅读以下说明，以减少不必要的问题。`

  **推荐工具**: [MT管理器](https://www.coolapk.com/apk/bin.mt.plus)

  > 1. __appname.sh__：将zip解压缩到任意目录，点击`appname.sh`并勾选root执行脚本 [[示意图]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/1.png)，等待提示结束 [[示意图]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/2.png)。

  > 2. __Apkname.txt__：当前目录下会生成一个`Apkname.txt`，这就是你**要备份的软件列表**，你可以把**不需要备份的软件那一行前加上`#`** [[示意图]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/3.png)，备份时就会跳过它；如果你只需要备份一两个软件，那么你可以**全选删除**，然后按照这个格式：`[App名称 App包名]` 进行填写需要备份的软件 [[示意图]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/4.png)，这样就不用一个一个去加`#`了。

  > 3. __backup.sh__：以上简单两步你就设置好了需要备份的软件，接下来点击`backup.sh`并勾选root执行，等待备份结束 [[示意图]](https://github.com/Petit-Abba/backup_script_zh-CN//raw/main/File/Picture/5.png)。

  > 4. __备份完成__：完成后会在当前目录生成一个Backup资料夹，里面是你的软件备份，把这个资料夹整个备份起来，刷完机直接在里面找到`还原备份.sh`即可恢复备份的所有数据，同样道理里面有个name.txt ，一样跟第二步骤操作一样不需要还原的删除。

##### 附加说明[1]：backup_settings.conf (备份设置)
  ```
  1=是  0=否 

  # 是否在每次执行备份脚本使用音量键询问如下备份需求
  Lo=0 (如果是1，那下面三项设置就被忽略，改为音量键选择。)

  # 选择是否只备份split apk(分割apk档，1备份split apk 0混合备份)
  C=0

  # 是否备份外部数据 即比如原神的数据包(1备份0不备份)
  B=0

  # 备份路径位置为绝对位置或是当前环境位置(1环境位置 0脚本所在位置)
  path=0

  # 压缩算法(可用lz4 zstd tar tar为仅打包 有什么好用的压缩算法请联系我)
  # lz4压缩最快，但是压缩率略差 zstd拥有良好的压缩率与速度 当然慢于lz4。
  Compression_method=tar
  ```
  `如果上面内容看不懂或者懒得看，你也可以选择忽略，直接用默认即可。`

##### ~附加说明[2]：打包成卡刷包.sh (8.8.9版本之后已经移除)~
  ```
  1. ROOT执行 recovery备份包名生成.sh

  2. 编辑 recovery.txt，自己想想如果开不了机只能进第三方rec的时候，你最想备份哪个应用，哪些又是不需要的，对，没错，把不需要的删除。

  3. ROOT执行 打包成卡刷包.sh，执行完成后当前目录就会出现 recovery备份.zip。~

  4. 把 recovery备份.zip 保存好，以后开不了机只能进rec的时候，你就可以卡刷它，把App备份打包出来。
  ```

##### 附加说明[3]：安装Magisk模块进行自动备份.sh (8.8.9版本更新加入)
  ```
  1. ROOT执行 安装Magisk模块进行自动备份.sh，会安装 数据备份脚本 的Magisk模块。

  2. 相关路径查看：/storage/emulated/0/Android/backup_script/

  3. Magisk模块会生成卡刷包，并且每隔一小时监控第三方软件数量进行卡刷包生成服务，防止突然不能开机时丢失软件。

  4. 生成的卡刷包必须进入recovery才能刷入进行备份，每天凌晨3点进行总体数据备份。
  ```

## 关于反馈
  - 如果使用过程中出现问题，请**携带截图并详细说明问题**建立[issues](https://github.com/YAWAsau/backup_script/issues)。
  - 酷安@[落叶凄凉TEL](http://www.coolapk.com/u/2277637)

## 常见问题
  ```
  Q：批量备份大量提示失败怎么办？
  A：退出脚本，删除Backup资料夹，再备份一次。

  Q：批量恢复大量提示失败怎么办？
  A：退出脚本，再执行一次就好，不要删除资料夹。如果还是错误，请建立issues，我帮你排除错误。

  Q：微信/QQ 能不能完美备份&恢复数据？
  A：不能保证，有的人说不能有的人说能，所以备份会有提示。建议用你信赖的备份软件针对微信/QQ再备份一次，以防丢失重要数据。

  Q：为什么部分APP备份很久？比如王者荣耀、PUBG、原神、微信、QQ。
  A：因为连同软件数据包都给你备份了，原神数据包9GB+当然久到裂开了，恢复同理，还要解压缩数据包。
  ```

## 铭谢贡献
  - 臭批老k([kmou424](https://github.com/kmou424))：提供部分与验证函数思路
  - 屑老方([雄氏老方](http://www.coolapk.com/u/665894))：提供自动更新脚本方案
  - 依心所言&情非得已c：提供appinfo替代aapt作为更高效的dump包名
  - 胖子老陈(雨季骚年)

  `文档编辑：Petit-Abba`
