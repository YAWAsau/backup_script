#!/system/bin/sh
if [ "$(whoami)" != root ]; then
	echo "你是憨批？不給Root用你媽 爬"
	exit 1
fi
[[ -d /data/cache ]] && set -x 2> /data/cache/debug_output.log
shell_language="zh-TW"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
script="${0##*/}"
backup_version="202605161105"
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
update_backup_settings_conf() {
    echo "#0關閉音量鍵選擇 (如選項未設置，則強制使用音量鍵選擇)
#1開啟音量鍵選擇 (如選項已設置，則跳過該選項提示)
#2使用鍵盤輸入，適用於無音量鍵可用設備選擇 (如選項未設置，則強制使用鍵盤輸入)
Lo="${Lo:-0}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#腳本語言設置 留空則自動識別系統語言環境並翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#備份開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#自定義備份文件輸出位置 支持相對路徑(留空則默認當前路徑)
Output_path=\""$Output_path"\"

#自定義applist.txt位置 支持相對路徑(留空則默認當前路徑)
list_location=\""$list_location"\"

#自動更新腳本(留空強制選擇)
#1開啟 0關閉
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#自定義屏蔽外部掛載點 例：OTG 虛擬SD等 多個掛載點請使用 | 區隔
#屏蔽後不會提示音量鍵選擇，不影響Output_path指定外置存儲位置
mount_point=\""${mount_point:-rannki|0000-1}"\"

#使用者(如0 999等用戶，如存在多個用戶留空強制選擇，無多個用戶則默認用戶0不詢問)
user="$user"

#備份模式
#1包含數據+安裝包，0僅包安裝包
#此選項設置1時Backup_obb_data，Backup_user_data，blacklist_mode將可設置 0時Backup_user_data，Backup_obb_data，blacklist_mode選項不生效
#此外設置0時將同時忽略appList.txt的!與任何黑名單設置（包括黑名單列表）
Backup_Mode="${Backup_Mode:-1}"

#是否備份使用者數據 (1備份 0不備份 留空強制選擇)
Backup_user_data="${Backup_user_data:-1}"

#是否備份外部數據 例：原神的數據包(1備份 0不備份 留空強制選擇)
Backup_obb_data="${Backup_obb_data:-1}"

#是否在應用數據備份完成後備份自定義目錄
#1開啟 0關閉
backup_media="${backup_media:-0}"

#存在進程忽略備份(1忽略0備份)
Background_apps_ignore="${Background_apps_ignore:-0}"

#添加自定義備份路徑 例：Download DCIM等文件夾 請使用絕對路徑，請勿刪除\"\"
Custom_path=\""${Custom_path:-
/storage/emulated/0/Pictures/
/storage/emulated/0/Download/
/storage/emulated/0/Music
/storage/emulated/0/DCIM/
/data/adb
}"\"

#黑名單模式(1完全忽略，不備份  0僅備份安裝包，注意！此選項Backup_Mode=1時黑名單模式才能使用)
blacklist_mode="${blacklist_mode:-0}"

#備份黑名單（備份策略由「黑名單模式」控制，此處只作為黑名單應用列表）
blacklist=\""${blacklist:-
#com.esunbank
#com.chailease.tw.app.android.ccfappcust}"\"

#位於data的預裝應用白名單 例：相冊 錄音機 天氣 計算器等(默認屏蔽備份預裝應用，如需備份請添加預裝應用白名單)
whitelist=\""${whitelist:-
com.xiaomi.xmsf
com.xiaomi.xiaoailite
com.xiaomi.hm.health
com.duokan.phone.remotecontroller
com.miui.weather2
com.milink.service
com.android.soundrecorder
com.miui.virtualsim
com.xiaomi.vipaccount
com.miui.fm
com.xiaomi.shop
com.xiaomi.smarthome
com.miui.notes
com.xiaomi.router
com.xiaomi.mico
dev.miuiicons.pedroz}"\"

#可被備份的系統應用白名單(默認屏蔽備份系統應用，如需備份請添加系統應用白名單)
system=\""${system:-
com.google.android.calendar
com.google.android.gm
com.google.android.googlequicksearchbox
com.google.android.tts
com.google.android.apps.maps
com.google.android.apps.messaging
com.google.android.inputmethod.latin
com.instagram.android
com.facebook.orca
sh.siava.AOSPMods
com.facebook.katana
com.android.chrome}"\"

#壓縮算法(可用zstd tar，tar為僅打包 有什麼好用的壓縮算法請聯系我
#zstd擁有良好的壓縮率與速度
Compression_method=${Compression_method:-zstd}

#主色
rgb_a="${rgb_a:-226}"
#輔色
rgb_b="${rgb_b:-123}"
rgb_c="${rgb_c:-177}"

#遠程備份類型 (留空不啟用)
#推薦 webdav (穩定)
#smb 僅支援 SMB1/CIFS，Windows Server 需手動開啟
remote_type="${remote_type:-}"

#遠程地址
#WebDAV例: http://192.168.1.100:8080/dav/
#SMB例:    smb://192.168.1.100/backup/
remote_url="${remote_url:-}"

#遠程認證用戶名
remote_user="${remote_user:-}"

#遠程認證密碼
remote_pass="${remote_pass:-}"

#遠程備份完成後是否保留本地檔案
#1保留本地檔案(上傳後不刪除) 0上傳成功後刪除本地檔案
remote_keep_local="${remote_keep_local:-0}"
" | sed '
    /^Custom_path/ s/ /\n/g;
    /^blacklist/ s/ /\n/g;
    /^whitelist/ s/ /\n/g;
    /^system/ s/ /\n/g;
    /^am_start/ s/ /\n/g;
    s/true/1/g;
    s/false/0/g'
}
update_Restore_settings_conf() {
    echo "#0關閉音量鍵選擇 (如選項未設置，則強制使用音量鍵選擇)
#1開啟音量鍵選擇 (如選項已設置，則跳過該選項提示)
#2使用鍵盤輸入，適用於無音量鍵可用設備選擇 (如選項未設置，則強制使用鍵盤輸入)
Lo="${Lo:-0}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#恢復開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#腳本語言設置 為空自動針對當前系統語言環境自動翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#自動更新腳本(留空強制選擇)
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#恢復模式(1恢復未安裝應用 0全恢復)
recovery_mode="${recovery_mode:-0}"

#恢復資料夾
media_recovery="${media_recovery:-0}"

#存在進程忽略恢復(1忽略0恢復)
Background_apps_ignore="${Background_apps_ignore:-0}"

#使用者(如0 999等用戶，留空如存在多個用戶強制音量鍵選擇，無多用戶則默認0不詢問)
user="$user"

#主色
rgb_a="${rgb_a:-226}"
#輔色
rgb_b="${rgb_b:-123}"
rgb_c="${rgb_c:-177}"" | sed 's/true/1/g ; s/false/0/g'
}
if [[ ! -d $tools_path ]]; then
	tools_path="${MODDIR%/*}/tools"
	[[ ! -d $tools_path ]] && echo "$tools_path二進制目錄遺失" && EXIT="true"
fi
_update_conf() {
    case $conf_path in
    *backup_settings.conf)  update_backup_settings_conf>"$conf_path" ;;
    *restore_settings.conf) update_Restore_settings_conf>"$conf_path" ;;
    *) echo "$conf_path配置遺失" && exit 1 ;;
    esac
}
if [[ ! -f $conf_path ]]; then
    _update_conf
    echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
fi
[[ ! -f $conf_path ]] && echo "$conf_path遺失" && exit 2
. "$conf_path" &>/dev/null
_update_conf
case $Shell_LANG in
1) LANG="CN" ;;
0) LANG="TW" ;;
*) LANG="${LANG:="$(getprop "persist.sys.locale")"}" ;;
esac
echoRgb() {
	#轉換echo顏色提高可讀性
	local color
	case $2 in
	0) color=197 ;;
	1) color=121 ;;
	2) color=$rgb_c ;;
	3) color=$rgb_b ;;
	*) color=$rgb_a ;;
	esac
	echo -e "\e[38;5;${color}m -$1\e[0m"
}
