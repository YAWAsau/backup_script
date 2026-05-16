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
backup_version="202508162209"
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
# 產生 backup_settings.conf 的內容模板 (寫到 stdout)
# 透過重定向到檔案來生成或更新備份設定檔
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

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"

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
# 產生 restore_settings.conf 的內容模板 (寫到 stdout)
# 備份完成時呼叫此函數寫入備份目錄,讓恢復端有獨立的設定檔
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

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"" | sed 's/true/1/g ; s/false/0/g'
}
if [[ ! -d $tools_path ]]; then
	tools_path="${MODDIR%/*}/tools"
	[[ ! -d $tools_path ]] && echo "$tools_path二進制目錄遺失" && EXIT="true"
fi
# 根據當前 conf_path 判斷類型,觸發對應模板重新寫入
# 用於腳本版本升級時自動補齊新增的設定欄位
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
# 帶色彩輸出, 用法: echoRgb "訊息" [色碼]
# 色碼:
#   0 = 紅色 (197)    - 錯誤/警告
#   1 = 亮綠 (121)    - 成功
#   2 = rgb_c (213)   - 強調/變數值 (粉紅, 預設)
#   3 = rgb_b (51)    - 提示/進度 (亮青, 預設)
#   其他/省略 = rgb_a (220) - 一般資訊 (亮黃, 預設)
# rgb_a/b/c 可在 conf 自訂, 全部都是 256 色 ANSI 編號
echoRgb() {
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
rgb_a="${rgb_a:=220}"
abi="$(getprop ro.product.cpu.abi)"
sdk="$(getprop ro.build.version.sdk)"
release="$(getprop ro.build.version.release)"
case $abi in
arm64*)
	if [[ $sdk -lt 24 ]]; then
		echoRgb "設備Android ${release}版本過低 請升級至Android 8+" "0"
		exit 1
	else
		case $sdk in
		26|27|28)
			echoRgb "設備Android ${release}版本偏低，無法確定腳本能正確的使用" "0"
			;;
		esac
	fi
	;;
*)
	echoRgb "未知的架構: $abi" "0"
	exit 1
	;;
esac
get_mv="$(which mv)"
PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:/sbin/.magisk/busybox:/sbin/.magisk:/sbin:/system_ext/bin:/vendor/bin:/vendor/xbin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
_magisk_path="$(magisk --path 2>/dev/null)"
if [[ -d $_magisk_path ]]; then
	PATH="$_magisk_path/.magisk/busybox:$PATH"
else
	[[ $(ksud -V 2>/dev/null) = "" ]] && echo "Magisk busybox Path does not exist"
fi
export PATH="$PATH"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$tools_path/busybox"
#排除自身
exclude="
update
soc.json
classes.dex
Device_List"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echoRgb "設置busybox環境中"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -f $busybox && -f $busybox2 ]]; then
	filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
	filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
	if [[ $filesha256 != $filesha256_1 ]]; then
		echoRgb "busybox sha256不一致 重新創立環境中"
		rm -rf "$filepath"/*
	fi
fi
find "$tools_path" -maxdepth 1 ! -path "$tools_path/tools.sh" -type f | grep -Ev "$(echo $exclude | sed 's/ /\|/g')" | while read -r; do
	File_name="${REPLY##*/}"
	if [[ ! -f $filepath/$File_name ]]; then
		cp -r "$REPLY" "$filepath"
		chmod 0777 "$filepath/$File_name"
		echoRgb "$File_name > $filepath/$File_name"
	else
		filesha256="$(sha256sum "$filepath/$File_name" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$tools_path/$File_name" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echoRgb "$File_name sha256不一致 重新創建"
			cp -r "$REPLY" "$filepath"
			chmod 0777 "$filepath/$File_name"
			echoRgb "$File_name > $filepath/$File_name"
		fi
	fi
done
if [[ -f $busybox ]]; then
	"$busybox" --list | while read -r; do
		if [[ $REPLY != tar && $REPLY != bc && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
fi
[[ ! -f $filepath/zstd ]] && echoRgb "$filepath缺少zstd" && exit 2
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
ln -fs "$tools_path/classes.dex" "$filepath/classes.dex"
export CLASSPATH="$filepath/classes.dex"
quit=0
while read -r file expected_hash; do
    if [[ -f $tools_path/$file ]]; then
        computed_hash="$(sha256sum "$tools_path/$file" | awk '{print $1}')"
        if [[ $computed_hash = $expected_hash ]]; then
            echoRgb "✅ $file: 驗證通過"
        else
            echoRgb "❌ $tools_path/$file: SHA-256 不一致\n -\"$computed_hash\""
            quit=2
            break
        fi
    else
        echoRgb "⚠️ 檔案 $tools_path/$file 不存在"
        quit=1
        break
    fi
done <<EOF
zstd 9ef4b54148699c9874cfd45aaf38e5cc950e5d168afdcf2edf58a2463f5561ed
tar 882639ac310a7eb4052c68c21cea02633307700f9cc8c7c469c2dd18d734a112
classes.dex 63934f7d15de40f4b188672e36fe22a01b55abb235becee2c2738f29aaf8299b
bc b15d730591f6fb52af59284b87d939c5bea204f944405a3518224d8df788dc15
busybox 4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651
find 7fa812e58aafa29679cf8b50fc617ecf9fec2cfb2e06ea491e0a2d6bf79b903b
jq 6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
keycheck 50645ee0e0d2a7d64fb4a1286446df7a4445f3d11aefd49eeeb88515b314c363
cmd 08da8ac23b6e99788fd3ce6c19c7b5a083b2ad48be35963a48d01d6ee7f3bb6d
smbclient 0fe8aa0abcf2ab81387d25dfb4a47369925e475bcf0c32acc9846753775ec35e
EOF
if [[ $background_execution = 1 || $setDisplayPowerMode = 1 ]]; then
    notification() { app_process /system/bin com.xayah.dex.NotificationUtil notify -t 'SpeedBackup' "$@"; }
else
    notification() { :; }
fi
if [[ $quit -ne 0 ]]; then
  exit "$quit"
fi
# Logo
echo -e "\e[38;5;51m"
cat <<'LOGO'
░██████╗██████╗░███████╗███████╗██████╗░
██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗
╚█████╗░██████╔╝█████╗░░█████╗░░██║░░██║
░╚═══██╗██╔═══╝░██╔══╝░░██╔══╝░░██║░░██║
██████╔╝██║░░░░░███████╗███████╗██████╔╝
╚═════╝░╚═╝░░░░░╚══════╝╚══════╝╚═════╝░
██████╗░░█████╗░░█████╗░██╗░░██╗██╗░░░██╗██████╗░
██╔══██╗██╔══██╗██╔══██╗██║░██╔╝██║░░░██║██╔══██╗
██████╦╝███████║██║░░╚═╝█████═╝░██║░░░██║██████╔╝
██╔══██╗██╔══██║██║░░██╗██╔═██╗░██║░░░██║██╔═══╝░
██████╦╝██║░░██║╚█████╔╝██║░╚██╗╚██████╔╝██║░░░░░
╚═════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚═════╝░╚═╝░░░░░
LOGO
echo -e "\e[38;5;213m        » RESTORE // SYNC «\e[0m"
sleep 1 && clear
TMPDIR="/data/local/tmp"
rm -rf "$TMPDIR"/*
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
chmod 771 "$TMPDIR"
chown '2000:2000' "$TMPDIR"
if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
if [[ $(which toybox | grep -Eo "system") != system ]]; then
	echoRgb "系統變量中沒有找到toybox" "0"
	exit 1
fi
#下列為自定義函數
alias down="app_process /system/bin com.xayah.dex.HttpUtil get $@"
case $LANG in
*CN* | *cn*)
    alias ts="app_process /system/bin com.xayah.dex.CCUtil t2s $@" ;;
*)
    alias ts="app_process /system/bin com.xayah.dex.CCUtil s2t $@" ;;
esac
alias LS="toybox ls -Zd"
alias mv="$get_mv"
# 給 trap / 流程控制用的 return 函數
# Set_back_0 永遠回 0 (成功), Set_back_1 永遠回 1 (失敗)
Set_back_0() {
	return 0
}
Set_back_1() {
	return 1
}
# 計算並輸出某段流程的耗時
# 用法: endtime <計時編號> <名稱>
# 計時編號: 1=讀 starttime1, 2=讀 starttime2 (需先在外面 set 變數)
# 輸出格式: " -<名稱>用時:X天X時X分X秒"
endtime() {
	case $1 in
	1) starttime="$starttime1" ;;
	2) starttime="$starttime2" ;;
	esac
	endtime="$(date -u "+%s")"
	duration="$(echo $((endtime - starttime)) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')"
	[[ $duration != "" ]] && echo " -$2用時:$duration" || echo " -$2用時:0秒"
}
nskg=1
# 從 GitHub Release API 取得腳本最新版本號
# 透過 CDN (ghfast / cloudflare worker) 加速避免被牆
get_version() {
	while :; do
		keycheck
		case $? in
		42)
			[[ $Select_user = true ]] && branch="$1" || branch=true
			echoRgb "$1" "1"
			;;
		41)
			[[ $Select_user = true ]] && branch="$2" || branch=false
			echoRgb "$2" "0"
			;;
		*)
			echoRgb "keycheck錯誤" "0"
			continue
			;;
		esac
		sleep 0.3
		break
	done
}
# 規範化布林值,將 1/true/yes 等變成 true,其他變成 false
# 用於 conf 讀進來的開關項統一格式
isBoolean() {
    unset nsx
	nsx="$1"
	if [[ $1 = 1 ]]; then
		nsx=true
	elif [[ $1 = 0 ]]; then
		nsx=false
	else
		echoRgb "$conf_path $2=$1填寫錯誤，正確值1or0" "0"
		exit 2
	fi
}
# 根據上一條命令的退出碼輸出成功/失敗訊息
# 用法: echo_log "操作名稱" [skip_success_msg]
# 第二個參數非空時, 成功不輸出訊息 (只設變數)
echo_log() {
	if [[ $? = 0 ]]; then
		[[ $2 = "" ]] && echoRgb "$1成功" "1"
		result=0
		Set_back_0
	else
		echoRgb "$1失敗，過世了" "0"
		notification "$RANDOM" "$name1: $1失敗，過世"
		result=1
		Set_back_1
	fi
}
# 殺死先前殘留的腳本進程,並設置 lock 防止重複執行
# trap EXIT 會清 lock 並觸發 remote_cleanup (若有遠端設定)
kill_Serve() {
    local LOCK_DIR="/data/.backup_lock"
    local MY_PID="$$"
    # 使用 mkdir 作為原子鎖操作，避免 TOCTOU 競態條件
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        if [[ -f $LOCK_DIR/pid ]]; then
            OLD_PID="$(cat "$LOCK_DIR/pid")"
            if kill -0 "$OLD_PID" 2>/dev/null; then
                echo "發現先前的備份程序 (PID=$OLD_PID)，將其終止"
                kill -KILL "$OLD_PID"
                echo "結束自身，避免重複執行"
                exit 1
            else
                echo "發現 lock 但程序已不存在，視為殘留 lock"
                rm -rf "$LOCK_DIR"
                mkdir "$LOCK_DIR" 2>/dev/null || exit 1
            fi
        else
            rm -rf "$LOCK_DIR"
            mkdir "$LOCK_DIR" 2>/dev/null || exit 1
        fi
    fi
    echo "$MY_PID" > "$LOCK_DIR/pid"
    trap "rm -rf '$LOCK_DIR'; remote_cleanup" EXIT
}
kill_Serve
# -------- 遠程備份功能 --------
# 預連線測試 (避免後續操作卡住)
# 用法: remote_precheck <host> <port>
remote_precheck() {
	local host="$1" port="$2"
	[[ -z $host ]] && { echoRgb "remote_precheck: host為空" "0"; return 1; }
	# 嘗試用 nc 或 /dev/tcp 在3秒內判斷可否連線
	if command -v nc >/dev/null 2>&1; then
		nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && return 0
	fi
	# fallback: 用 timeout + bash /dev/tcp
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 sh -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1 && return 0
	fi
	return 1
}

# 寫入遠端上傳 log (帶時間戳)
# 用法: remote_log "訊息"
remote_log() {
	[[ -z $MODDIR ]] && return
	local logf="$MODDIR/log/remote_upload.log"
	mkdir -p "${logf%/*}" 2>/dev/null
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$logf"
}

# 上傳結束時統一輸出總結並決定是否刪本地
# 參數: $1=協議名 $2=成功清單檔 $3=失敗清單檔
upload_summary() {
	local proto="$1" ok_list="$2" fail_list="$3"
	local ok_count=0 fail_count=0
	[[ -f $ok_list ]] && ok_count="$(wc -l < "$ok_list" 2>/dev/null)"
	[[ -f $fail_list ]] && fail_count="$(wc -l < "$fail_list" 2>/dev/null)"
	ok_count=${ok_count:-0}
	fail_count=${fail_count:-0}
	# 計算總耗時
	local elapsed_str=""
	if [[ -n $UPLOAD_START_TS ]]; then
		local elapsed=$(( $(date +%s) - UPLOAD_START_TS ))
		elapsed_str=" 用時${elapsed}秒"
	fi
	echoRgb "_______________________________________" "2"
	echoRgb "$proto 上傳完成: 成功 $ok_count / 失敗 $fail_count${elapsed_str}" "3"
	remote_log "$proto 上傳結束: 成功 $ok_count / 失敗 $fail_count${elapsed_str}"
	if [[ $fail_count -gt 0 ]]; then
		echoRgb "失敗清單(已記錄到 $MODDIR/log/remote_upload.log):" "0"
		local n=0
		while read -r line && [[ $n -lt 5 ]]; do
			echoRgb "  $line" "0"
			let n++
		done < "$fail_list"
		[[ $fail_count -gt 5 ]] && echoRgb "  ...還有 $((fail_count - 5)) 個,請看 log" "0"
	fi
	# 刪本地檔案的策略: remote_keep_local=true 永遠保留
	# 否則: 必須「全部成功」才刪除所有上傳過的檔案
	if [[ $remote_keep_local != true ]]; then
		if [[ $fail_count -eq 0 && $ok_count -gt 0 ]]; then
			echoRgb "全部上傳成功,清除本地已上傳檔案" "1"
			while read -r f; do
				[[ -n $f ]] && rm -f "$f"
			done < "$ok_list"
		elif [[ $fail_count -gt 0 ]]; then
			echoRgb "部分上傳失敗,本地檔案全部保留 (含已上傳的)" "0"
			remote_log "部分失敗,本地檔案全部保留"
		fi
	else
		echoRgb "remote_keep_local=1 本地檔案保留" "3"
	fi
	rm -f "$ok_list" "$fail_list" 2>/dev/null
	unset UPLOAD_START_TS
	[[ $fail_count -eq 0 ]]
}

# URL 編碼 (處理 UTF-8 多 byte, 保留 / 不編碼以保持路徑結構)
# 用法: url_encode_path <string>
url_encode_path() {
	local s="$1"
	# 用 od 把每個 byte 印成 hex, awk 處理 hex 字串轉換
	# 避免 strtonum (busybox awk 不支援)
	printf '%s' "$s" | od -An -tx1 -v | tr -s ' \n' ' ' | awk '
	BEGIN {
		# 建立 hex → dec 對照表
		for (i=0; i<10; i++) hex2int[sprintf("%d",i)] = i
		hex2int["a"]=10; hex2int["b"]=11; hex2int["c"]=12
		hex2int["d"]=13; hex2int["e"]=14; hex2int["f"]=15
	}
	{
		n = split($0, a, " ")
		for (i=1; i<=n; i++) {
			h = a[i]
			if (h == "") continue
			# 把兩個 hex 字元轉成 dec
			val = hex2int[substr(h,1,1)] * 16 + hex2int[substr(h,2,1)]
			# 不編碼: A-Z a-z 0-9 - _ . ~ /
			if ((val>=48 && val<=57) || (val>=65 && val<=90) || (val>=97 && val<=122) \
				|| val==45 || val==95 || val==46 || val==126 || val==47) {
				printf "%c", val
			} else {
				printf "%%%s", toupper(h)
			}
		}
	}'
}

# URL 解碼 (處理 %XX, 含 UTF-8 多 byte)
url_decode_path() {
	local s="$1"
	local converted
	converted=$(echo "$s" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
	printf '%b' "$converted"
}

# 計算速度顯示字串
# 用法: speed_calc <總bytes> <用時秒數>
# 輸出: "8.5 MB/s" 或 "512 KB/s" 或 "" (時間=0時)
speed_calc() {
	local bytes="$1" secs="$2"
	[[ -z $bytes || -z $secs || $secs -le 0 || $bytes -le 0 ]] && return
	if [[ $bytes -ge 1048576 ]]; then
		echo "$(echo "scale=2; $bytes / $secs / 1048576" | bc) MB/s"
	elif [[ $bytes -ge 1024 ]]; then
		echo "$(echo "scale=1; $bytes / $secs / 1024" | bc) KB/s"
	else
		echo "$((bytes / secs)) B/s"
	fi
}

# 計算清單檔案總大小 (bytes)
list_total_size() {
	local list="$1"
	[[ ! -f $list ]] && { echo 0; return; }
	awk '{
		cmd="stat -c%s \""$0"\" 2>/dev/null"
		cmd | getline sz
		close(cmd)
		s+=sz+0
	} END{print s+0}' "$list"
}

# 收集本次需要上傳的清單 (而非整個Backup)
# 結果寫入 $1 指定的list_file
# 範圍由以下變數控制 (在各備份入口設定,只反映「本次執行」):
#   REMOTE_APPLIST    : 字串,本次備份的 app 清單 (跟 $txt 同格式)
#   REMOTE_UPLOAD_MEDIA=1 : 本次有跑 Media 備份, 要上傳 $Backup/Media
#   REMOTE_UPLOAD_WIFI=1  : 本次有跑 wifi 備份, 要上傳 $Backup/wifi
# app 上傳條件:
#   1. 該行未被 #/＃/! 註解
#   2. $Backup/$name1 目錄存在
#   3. 目錄內至少有一個有效檔案
remote_collect_targets() {
	local list_file="$1"
	local tmp_collect="$TMPDIR/.rcollect"
	: > "$list_file"
	if [[ -n $REMOTE_APPLIST ]]; then
		echoRgb "讀取本次備份名單" "2"
		echo "$REMOTE_APPLIST" | grep -Ev '^[[:space:]]*[#＃!]|^[[:space:]]*$' | while read -r line; do
			local name1="${line%% *}"
			[[ -z $name1 ]] && continue
			local full="$Backup/$name1"
			[[ -d $full ]] || continue
			find "$full" -type f  > "$tmp_collect" 2>/dev/null
			[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
		done
	fi
	if [[ $REMOTE_UPLOAD_MEDIA = 1 && -d $Backup/Media ]]; then
		find "$Backup/Media" -type f  > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $Backup/wifi ]]; then
		find "$Backup/wifi" -type f  > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	# 固定附加: tools/ 資料夾、start.sh、restore_settings.conf
	# 只要 list_file 已經有內容(代表本次有東西要上傳)就一併帶上,讓遠端目錄能獨立還原
	if [[ -s $list_file ]]; then
		[[ -d $Backup/tools ]] && find "$Backup/tools" -type f >> "$list_file" 2>/dev/null
		[[ -f $Backup/start.sh ]] && echo "$Backup/start.sh" >> "$list_file"
		[[ -f $Backup/restore_settings.conf ]] && echo "$Backup/restore_settings.conf" >> "$list_file"
	fi
	rm -f "$tmp_collect" 2>/dev/null
}
# 掃描區網內所有開放 SMB (445 port) 的主機
# 50 個 IP 一批並行掃描, 然後 smbclient -L 列出每台的 share
# 需要 nc 命令 (busybox 通常有)
scan_smb() {
    local my_ip
    my_ip="$(ip route get 1 2>/dev/null | awk '{print $7; exit}')"
    [[ -z $my_ip ]] && my_ip="$(ifconfig 2>/dev/null | grep -m1 'inet addr:192' | awk '{print $2}' | cut -d: -f2)"
    [[ -z $my_ip ]] && { echoRgb "無法取得本機 IP" "0"; return 1; }
    local subnet="${my_ip%.*}"
    echoRgb "本機 IP: $my_ip" "2"
    echoRgb "掃描 $subnet.0/24 上的 SMB 主機 (445 port)..." "3"
    if ! command -v nc >/dev/null 2>&1; then
        echoRgb "未找到 nc 命令,無法掃描" "0"
        return 1
    fi
    local results="$TMPDIR/.smb_scan_results"
    : > "$results"
    local i pids=""
    for i in $(seq 1 254); do
        local target="$subnet.$i"
        ( nc -z -w 1 "$target" 445 >/dev/null 2>&1 && echo "$target" >> "$results" ) &
        pids="$pids $!"
        if [[ $((i % 50)) -eq 0 ]]; then
            wait $pids 2>/dev/null
            pids=""
            echoRgb "  ...已掃描 $i/254" "2"
        fi
    done
    wait $pids 2>/dev/null
    if [[ ! -s $results ]]; then
        echoRgb "未發現 SMB 主機" "0"
        rm -f "$results"
        return 1
    fi
    echoRgb "------- 掃描完成 -------" "3"
    sort -t. -k4 -n "$results" | while read -r target; do
        echoRgb "發現 SMB: $target" "1"
        # 查主機名 (有 nmblookup 才查)
        if command -v nmblookup >/dev/null 2>&1; then
            local hn
            hn="$(nmblookup -A "$target" 2>/dev/null | awk 'NR==2{print $1}' | tr -d '<>\t ')"
            [[ -n $hn ]] && echoRgb "  主機名: $hn" "2"
        fi
        # 列 share — 用 awk 不用 grep,避開 busybox grep regex 限制
        smbclient -L "//$target" -N -t 3 -s /dev/null 2>/dev/null \
            | awk '/Disk/ {print "  共享: "$1}' \
            | while read -r line; do echoRgb "$line" "2"; done
    done
    rm -f "$results"
}
# SMB 上傳實作 (使用 smbclient)
# 流程: 解析 URL → 預檢 → 收集檔案 → 按目錄分組 → 每組一次 smbclient 批次傳輸
# 跟 upload_remote 的差別: SMB 用獨立的 smbclient 二進制, 不走 curl
upload_smb() {
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	echoRgb "使用: $filepath/smbclient" "2"
	# 解析 smb://server/share/remotepath
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="Backup_${Compression_method}_${user:-0}"
	rem_path="${rem_path}/${backup_subdir}"
	# 拆出 host 和 port (從 share 反推)
	local _hp="${share#//}"; _hp="${_hp%%/*}"
	local host="${_hp%%:*}"
	local port="${_hp#*:}"
	[[ $port = $_hp ]] && port=445
	echoRgb "SMB: $share (路徑: ${rem_path:-/})" "2"
	# 連線預檢
	if ! remote_precheck "$host" "$port"; then
		echoRgb "SMB伺服器無法連線: $host:$port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	local list_file="$TMPDIR/.slist"
	local ok_list="$TMPDIR/.sok"
	local fail_list="$TMPDIR/.sfail"
	: > "$ok_list"; : > "$fail_list"
	remote_collect_targets "$list_file"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>/dev/null
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	echoRgb "準備上傳 $total 個檔案" "3"
	remote_log "SMB 開始: $share, 共 $total 檔"
	# smbclient 共用參數:
	#   -t 10           : 命令 timeout 秒數
	#   -s /dev/null    : 跳過讀取 smb.conf (避免手動編譯版找不到 conf 噴警告)
	local SMB_OPTS="-t 10 -s /dev/null"
	# 收集所有需要建立的目錄
	local mkdir_script="$TMPDIR/.smb_mkdir"
	: > "$mkdir_script"
	{
		while read -r f; do
			local d="${f#$Backup/}"
			d="${d%/*}"
			[[ -n $d && $d != "${f#$Backup/}" ]] && echo "${rem_path:+$rem_path/}$d"
		done < "$list_file"
	} | sort -u | while read -r d; do
		# 對每層路徑都產生 mkdir 命令
		# 注意: smbclient 內部命令不認 shell 引號, 不能加 '' 或 ""
		local cur=""
		local OLDIFS="$IFS"
		IFS='/'
		set -- $d
		IFS="$OLDIFS"
		for seg; do
			[[ -z $seg ]] && continue
			cur="$cur/$seg"
			echo "mkdir $cur" >> "$mkdir_script"
		done
	done
	# 一次連線執行所有 mkdir (比每個目錄重新連快很多)
	if [[ -s $mkdir_script ]]; then
		echo "exit" >> "$mkdir_script"
		smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS < "$mkdir_script" 2>&1 \
			| grep -Ev '^Domain=|^OS=|NT_STATUS_OBJECT_NAME_COLLISION|^Try "help"|^dos charset|^Can.t load' >&2
	fi
	rm -f "$mkdir_script" 2>/dev/null
	# 按目錄分組上傳 (同一目錄的所有檔案,一次連線傳完)
	# 先依遠端目錄分組
	local group_dir="$TMPDIR/.smb_groups"
	mkdir -p "$group_dir" && rm -f "$group_dir"/*
	while read -r f; do
		[[ -z $f ]] && continue
		local rel="${f#$Backup/}"
		local file_dir="$(dirname "$rel")"
		local rem_dir="$rem_path"
		[[ $file_dir != . ]] && rem_dir="${rem_dir:+$rem_dir/}$file_dir"
		[[ -z $rem_dir ]] && rem_dir="/"
		# 用 base64 或 hash 當分組 key,避免路徑裡的 / 影響檔名
		local key="$(echo "$rem_dir|$(dirname "$f")" | md5sum 2>/dev/null | cut -c1-12)"
		[[ -z $key ]] && key="$(echo "$rem_dir|$(dirname "$f")" | cksum | cut -d' ' -f1)"
		local gf="$group_dir/$key"
		[[ ! -f $gf ]] && {
			echo "$rem_dir" > "$gf.meta"
			echo "$(dirname "$f")" >> "$gf.meta"
		}
		echo "$f" >> "$gf"
	done < "$list_file"
	# 對每個分組執行批次上傳
	local idx=0
	# 算總目錄數 (用於進度計算; 不含 wifi, wifi 不參與百分比)
	local total_dirs done_dirs=0
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local rem_dir_check
		rem_dir_check="$(sed -n 1p "$gf.meta")"
		# wifi 目錄不算進總數
		[[ $rem_dir_check = */wifi || $rem_dir_check = wifi || $rem_dir_check = */wifi/* ]] && continue
		let total_dirs++
	done
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local meta="$gf.meta"
		local rem_dir local_dir
		rem_dir="$(sed -n 1p "$meta")"
		local_dir="$(sed -n 2p "$meta")"
		local file_count
		file_count="$(wc -l < "$gf")"
		# 判斷是否為 wifi (不計入進度)
		local is_wifi=0
		[[ $rem_dir = */wifi || $rem_dir = wifi || $rem_dir = */wifi/* ]] && is_wifi=1
		echoRgb "上傳目錄 $rem_dir ($file_count 檔)" "3"
		local dir_start
		dir_start=$(date +%s)
		# 建立 smbclient batch script
		local batch="$TMPDIR/.smb_batch"
		echo "cd $rem_dir" > "$batch"
		echo "lcd $local_dir" >> "$batch"
		while read -r f; do
			local fname="$(basename "$f")"
			echo "put $fname" >> "$batch"
		done < "$gf"
		echo "exit" >> "$batch"
		# 跑 batch, 解析每個 put 的結果
		local smb_out
		smb_out="$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS < "$batch" 2>&1)"
		# 對應每個檔案的成功/失敗
		while read -r f; do
			let idx++
			local rel="${f#$Backup/}"
			local fname="$(basename "$f")"
			if echo "$smb_out" | grep -F "$fname" | grep -qE 'NT_STATUS|does not exist|ERR'; then
				echo "$rel" >> "$fail_list"
				echoRgb "[$idx/$total] ✗ $rel" "0"
				remote_log "FAIL SMB $rel"
			else
				echo "$f" >> "$ok_list"
				echoRgb "[$idx/$total] ✓ $rel" "1"
			fi
		done < "$gf"
		rm -f "$batch"
		# 此目錄完成,印整體進度 (wifi 不算)
		if [[ $is_wifi = 0 && $total_dirs -gt 0 ]]; then
			let done_dirs++
			local dir_speed=""
			local dir_bytes
			dir_bytes=$(list_total_size "$gf")
			local dir_elapsed=$(( $(date +%s) - dir_start ))
			local sp
			sp=$(speed_calc "$dir_bytes" "$dir_elapsed")
			[[ -n $sp ]] && dir_speed=" ($sp)"
			echoRgb "完成$((done_dirs * 100 / total_dirs))%${dir_speed}" "3"
		fi
	done
	rm -rf "$group_dir" 2>/dev/null
	rm -f "$list_file" 2>/dev/null
	upload_summary "SMB" "$ok_list" "$fail_list"
}

# 遠端上傳分派器 + WebDAV 實作
# $1=協議名 (webdav/smb), smb 會轉派給 upload_smb
# WebDAV: 用 curl 逐檔 PUT, 預先 MKCOL 建好目錄結構
upload_remote() {
	local proto="$1"
	[[ $proto = smb ]] && { upload_smb; return $?; }
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	local base_url
	case $proto in
	webdav)
		base_url="${remote_url%/}"
		[[ $base_url != http://* && $base_url != https://* ]] && { echoRgb "WebDAV地址格式錯誤: $remote_url" "0"; return 1; }
		;;
	*) echoRgb "未支援的協議: $proto" "0"; return 1 ;;
	esac
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="Backup_${Compression_method}_${user:-0}"
	base_url="$base_url/$backup_subdir"
	# 連線預檢: 從 base_url 解出 host:port
	local _hp="${base_url#*://}"
	_hp="${_hp%%/*}"
	local _host="${_hp%%:*}"
	local _port="${_hp#*:}"
	if [[ $_port = $_hp ]]; then
		[[ $base_url = https://* ]] && _port=443 || _port=80
	fi
	if ! remote_precheck "$_host" "$_port"; then
		echoRgb "$proto伺服器無法連線: $_host:$_port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	echoRgb "使用: $filepath/curl" "2"
	local list_file="$TMPDIR/.rlist"
	local ok_list="$TMPDIR/.rok"
	local fail_list="$TMPDIR/.rfail"
	: > "$ok_list"; : > "$fail_list"
	[[ -z $Backup ]] && { echoRgb "Backup路徑為空" "0"; return 1; }
	remote_collect_targets "$list_file"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>/dev/null
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	echoRgb "準備上傳 $total 個檔案" "3"
	remote_log "$proto 開始: $base_url, 共 $total 檔"
	# WebDAV: 先建初始目錄 (Backup_zstd_X 自己)
	curl -sS -L --http1.1 -X MKCOL -u "$remote_user:$remote_pass" "$base_url" >/dev/null 2>&1
	# WebDAV: 創建遠程子目錄 (MKCOL)
	while read -r f; do
		local d="${f#$Backup/}"
		d="${d%/*}"
		[[ -n $d && $d != "${f#$Backup/}" ]] && echo "$d"
	done < "$list_file" | sort -u | while read -r d; do
		local enc_d="$(url_encode_path "$d")"
		local cur="$base_url"
		local IFS='/'
		set -- $enc_d
		for seg; do
			cur="$cur/$seg"
			curl -sS -L --http1.1 -X MKCOL -u "$remote_user:$remote_pass" "$cur" >/dev/null 2>&1
		done
	done
	# 預掃總目錄數 (排除 wifi, 不計入百分比)
	local total_dirs done_dirs=0 last_dir="" cur_top_dir=""
	local dir_start=0 dir_bytes_accum=0
	while read -r f; do
		local top="${f#$Backup/}"
		top="${top%%/*}"
		[[ $top = wifi ]] && continue
		echo "$top"
	done < "$list_file" | sort -u | while read -r d; do echo "$d"; done > "$TMPDIR/.dirs_count"
	total_dirs="$(wc -l < "$TMPDIR/.dirs_count" 2>/dev/null)"
	rm -f "$TMPDIR/.dirs_count"
	# 上傳檔案
	local idx=0
	while read -r f; do
		[[ -z $f ]] && continue
		let idx++
		local rel="${f#$Backup/}"
		local cur_top="${rel%%/*}"
		# 判斷是「目錄內檔案」還是「根目錄檔案」
		# rel 含 / → 目錄內檔案, cur_top 是目錄名
		# rel 不含 / → 根目錄檔案, cur_top 是檔案名本身
		local is_root_file=0
		[[ $rel = "$cur_top" ]] && is_root_file=1
		# 目錄切換時印上一個目錄的進度
		if [[ -n $last_dir && $cur_top != "$last_dir" ]]; then
			if [[ $last_dir != wifi && $total_dirs -gt 0 ]]; then
				let done_dirs++
				local dir_speed=""
				local dir_elapsed=$(( $(date +%s) - dir_start ))
				local sp
				sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
				[[ -n $sp ]] && dir_speed=" ($sp)"
				echoRgb "完成$((done_dirs * 100 / total_dirs))%${dir_speed}" "3"
			fi
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		elif [[ -z $last_dir ]]; then
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		fi
		last_dir="$cur_top"
		# 累計這個目錄已上傳的 bytes
		local _sz
		_sz=$(stat -c%s "$f" 2>/dev/null)
		dir_bytes_accum=$(( dir_bytes_accum + ${_sz:-0} ))
		local target_url
		if [[ $proto = webdav ]]; then
			local enc_rel="$(url_encode_path "$rel")"
			target_url="$base_url/$enc_rel"
		else
			target_url="$base_url/$rel"
		fi
		local http_code curl_err
		# stderr → 檔案 (curl 自己的錯誤訊息)
		# body → /dev/null (不需要)
		# stdout → http_code 變數 (-w 的輸出)
		http_code="$(curl -sS -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
			-T "$f" -u "$remote_user:$remote_pass" -w '%{http_code}' \
			-o /dev/null "$target_url" 2>"$TMPDIR/.curl_stderr")"
		curl_err="$(cat "$TMPDIR/.curl_stderr" 2>/dev/null)"
		rm -f "$TMPDIR/.curl_stderr"
		# http_code 2xx 視為成功
		case $http_code in
		2*)
			echo "$f" >> "$ok_list"
			echoRgb "[$idx/$total] ✓ $rel" "1"
			;;
		*)
			echo "$rel  (HTTP $http_code)" >> "$fail_list"
			echoRgb "[$idx/$total] ✗ $rel (HTTP $http_code)" "0"
			[[ -n $curl_err ]] && remote_log "FAIL $proto $rel HTTP=$http_code err=$curl_err" \
				|| remote_log "FAIL $proto $rel HTTP=$http_code"
			;;
		esac
	done < "$list_file"
	# 最後一個目錄(非wifi)的進度
	if [[ -n $last_dir && $last_dir != wifi && $total_dirs -gt 0 ]]; then
		let done_dirs++
		local dir_speed=""
		local dir_elapsed=$(( $(date +%s) - dir_start ))
		local sp
		sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
		[[ -n $sp ]] && dir_speed=" ($sp)"
		echoRgb "完成$((done_dirs * 100 / total_dirs))%${dir_speed}" "3"
	fi
	rm -f "$list_file" 2>/dev/null
	upload_summary "$proto" "$ok_list" "$fail_list"
}


# 從 remote_url 解析出 host 和 port (依 remote_type)
# 結果寫到全域變數 REMOTE_HOST 和 REMOTE_PORT
remote_parse_endpoint() {
	REMOTE_HOST=""; REMOTE_PORT=""
	case $remote_type in
	smb)
		local u="${remote_url#smb://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"; [[ $REMOTE_PORT = $u ]] && REMOTE_PORT=445
		;;
	webdav)
		local u="${remote_url#*://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"
		if [[ $REMOTE_PORT = $u ]]; then [[ $remote_url = https://* ]] && REMOTE_PORT=443 || REMOTE_PORT=80; fi
		;;
	esac
}

# 解析 SMB URL 並設定 SMB_SHARE / SMB_REM_PATH 全域變數
# SMB_SHARE     = //server/share_name (smbclient -L 用)
# SMB_REM_PATH  = /sub/path (空字串代表 share 根目錄, 不含結尾斜線)
# 重複的 SMB URL 解析邏輯抽出 (原本有 4 個地方各自解析)
remote_parse_smb_url() {
	local url="${remote_url#smb://}"; url="${url%/}"
	local server="${url%%/*}"
	local after_server="${url#$server/}"
	local share_name="${after_server%%/*}"
	local rem_path="/${after_server#$share_name}"
	rem_path="${rem_path%/}"
	[[ $rem_path = / ]] && rem_path=""
	SMB_SHARE="//$server/$share_name"
	SMB_REM_PATH="$rem_path"
}

# 過濾 smbclient 輸出的雜訊行 (Try help / dos charset / OS= 等橫幅文字)
# 用法: smb_filter_noise <輸入字串>
smb_filter_noise() {
	echo "$1" | grep -Ev '^Try "help"|^dos charset|^Can.t load|^Domain=|^OS=|^$'
}

# 判斷目錄是否含任何檔案 (非空)
# 用法: dir_has_files <目錄路徑>
# 回傳: 0=有檔案, 1=空目錄或不存在
dir_has_files() {
	[[ -d $1 ]] || return 1
	[[ -n $(find "$1" -type f -print -quit 2>/dev/null) ]]
}

# 啟動時的遠端設定初始化
# 規範化 remote_keep_local 值, 驗證 remote_type, TCP 預檢
# 失敗時清空 remote_type 停用上傳但保留本地備份
remote_setup() {
	[[ -z $remote_type ]] && return
	# 規範化 remote_keep_local 成 true/false
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	echoRgb "遠程備份: $remote_type -> $remote_url" "3"
	case $remote_type in
	webdav|smb)
		;;
	*) echoRgb "未知遠程類型: $remote_type (可選: webdav/smb)" "0"; remote_type=""; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置，停用遠端上傳" "0"; remote_type=""; return 1; }
	# 事前連線測試: 從各協議解出 host:port 做快速 TCP 探測
	remote_parse_endpoint
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線測試通過 ($REMOTE_HOST:$REMOTE_PORT)" "1"
		if [[ $remote_keep_local = true ]]; then
			echoRgb "備份完成後將自動上傳到遠端 (保留本地檔案)" "3"
		else
			echoRgb "備份完成後將自動上傳到遠端 (上傳成功後刪除本地檔案)" "3"
		fi
	else
		echoRgb "遠端連線測試失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		echoRgb "可能原因: 未開WiFi/位址錯誤/伺服器未啟動" "0"
		echoRgb "本次將停用遠端上傳，備份僅保留在本地" "0"
		remote_type=""
	fi
}

# 獨立的測試遠端入口 (給選單用)
# 1. 顯示 conf 設定
# 2. TCP 預檢
# 3. 嘗試認證 + list 遠端目錄
# 不會實際上傳任何東西
# 單獨上傳某個 app 的備份 (給子目錄 upload.sh 用)
# 假設呼叫時 Backup 是備份根目錄 (Backup_zstd_X)
# $1 = app 名 (子目錄名)
single_upload() {
	local app_name="$1"
	[[ -z $app_name ]] && { echoRgb "single_upload: 缺少 app 名" "0"; return 1; }
	[[ -z $Backup ]] && Backup="$MODDIR"
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && { echoRgb "找不到目錄: $target" "0"; return 1; }
	dir_has_files "$target" || { echoRgb "$app_name 目錄為空,沒有東西可上傳" "0"; return 1; }
	# 重置範圍 flag, 只標記這一個
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	case $app_name in
	Media) REMOTE_UPLOAD_MEDIA=1 ;;
	wifi) REMOTE_UPLOAD_WIFI=1 ;;
	*) REMOTE_APPLIST="$app_name" ;;
	esac
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	echoRgb "—————— 單獨上傳: $app_name ——————" "3"
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 主選單觸發: 讀 appList.txt + Custom_path, 直接上傳對應目錄
# 不互動,等同於跑完整備份後的自動上傳,但不重新備份
upload_current_backup() {
	backup_path
	[[ ! -d $Backup ]] && { echoRgb "本地備份目錄不存在: $Backup" "0"; return 1; }
	echoRgb "本地備份: $Backup" "2"
	# 讀 appList.txt (跟備份用同一個解析邏輯)
	local applist=""
	if [[ -n $list_location ]]; then
		if [[ ${list_location:0:1} = / ]]; then
			[[ -f $list_location ]] && applist="$list_location"
		else
			[[ -f $MODDIR/$list_location ]] && applist="$MODDIR/$list_location"
		fi
	fi
	[[ -z $applist && -f $MODDIR/appList.txt ]] && applist="$MODDIR/appList.txt"
	# 組裝 REMOTE_APPLIST (跟 backup() 用同一個變數,讓 collect_targets 認得)
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	if [[ -n $applist ]]; then
		REMOTE_APPLIST="$(cat "$applist")"
		local app_count
		app_count=$(echo "$REMOTE_APPLIST" | grep -cEv '^[[:space:]]*[#＃!]|^[[:space:]]*$')
		echoRgb "讀取 $applist (有效 $app_count 個 app)" "2"
	else
		echoRgb "找不到 appList.txt" "0"
	fi
	# 讀 Custom_path: 有設就帶上 Media
	if [[ -n $Custom_path ]]; then
		if dir_has_files "$Backup/Media"; then
			REMOTE_UPLOAD_MEDIA=1
			echoRgb "Custom_path 已設, 將上傳 Media" "2"
		fi
	fi
	# wifi 目錄存在就一併上傳
	if dir_has_files "$Backup/wifi"; then
		REMOTE_UPLOAD_WIFI=1
		echoRgb "wifi 目錄存在, 將上傳 wifi" "2"
	fi
	if [[ -z $REMOTE_APPLIST && $REMOTE_UPLOAD_MEDIA != 1 && $REMOTE_UPLOAD_WIFI != 1 ]]; then
		echoRgb "沒有可上傳項目 (appList 為空, Custom_path 未設, 無 wifi)" "0"
		return 1
	fi
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 測試遠端連線完整性 (主選單第 6 項)
# 三層測試: TCP 預檢 → 認證 → 路徑訪問
# 每層失敗都有具體錯誤訊息 (帳密錯/路徑不存在/分享不存在等)
remote_test() {
	echoRgb "============== 遠端連線測試 ==============" "3"
	if [[ -z $remote_type ]]; then
		echoRgb "remote_type 未設定" "0"
		echoRgb "請編輯 $conf_path 設定 remote_type/remote_url/remote_user/remote_pass" "3"
		return 1
	fi
	echoRgb "類型: $remote_type" "2"
	echoRgb "位址: $remote_url" "2"
	echoRgb "帳號: ${remote_user:-(未設)}" "2"
	[[ -n $remote_pass ]] && echoRgb "密碼: ********" "2" || echoRgb "密碼: (未設)" "2"
	echoRgb "保留本地: ${remote_keep_local:-0}" "2"
	case $remote_type in
	webdav|smb) ;;
	*) echoRgb "未知 remote_type: $remote_type (可選: webdav/smb)" "0"; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url 未設置" "0"; return 1; }
	scan_smb
	# 第一關: TCP 預檢
	remote_parse_endpoint
	echoRgb "—————— TCP 連線測試 ——————" "3"
	echoRgb "目標: $REMOTE_HOST:$REMOTE_PORT" "2"
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "TCP 連線通過" "1"
	else
		echoRgb "TCP 連線失敗" "0"
		echoRgb "可能原因:" "0"
		echoRgb "  - WiFi 未開啟或不在同網段" "0"
		echoRgb "  - 伺服器 IP / port 寫錯" "0"
		echoRgb "  - 伺服器未啟動 / 防火牆阻擋" "0"
		return 1
	fi
	# 第二關: 認證 + 列目錄
	echoRgb "—————— 認證與列目錄測試 ——————" "3"
	case $remote_type in
	smb)
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local out
		out="$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
			-c "cd ${rem_path:-/}; ls; exit" 2>&1)"
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_LOGON_FAILURE'; then
			echoRgb "認證失敗 (帳號或密碼錯誤)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_BAD_NETWORK_NAME'; then
			echoRgb "share 名稱錯誤: $share_name (請檢查伺服器是否有此分享)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端路徑不存在: $rem_path (將在首次上傳時建立)" "3"
		elif echo "$out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "SMB 錯誤:" "0"
			echo "$out" | head -5
			return 1
		else
			echoRgb "認證通過, share 可存取" "1"
			[[ -n $rem_path ]] && echoRgb "遠端路徑 $rem_path 可存取" "1"
		fi
		;;
	webdav)
		local base_url="${remote_url%/}"
		local code
		code="$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 0" -w '%{http_code}' -o /dev/null "$base_url" 2>&1)"
		case $code in
		2*|207) echoRgb "WebDAV 認證通過 (HTTP $code)" "1" ;;
		401) echoRgb "認證失敗 (HTTP 401, 帳號或密碼錯誤)" "0"; return 1 ;;
		403) echoRgb "權限不足 (HTTP 403)" "0"; return 1 ;;
		404) echoRgb "路徑不存在 (HTTP 404)" "0"; return 1 ;;
		000) echoRgb "curl 無法完成請求 (可能 SSL / 解析問題)" "0"; return 1 ;;
		*)   echoRgb "WebDAV 異常 (HTTP $code)" "0"; return 1 ;;
		esac
		;;
	esac
	echoRgb "========================================" "3"
	echoRgb "全部測試通過, 可以開始備份" "1"
	return 0
}

# 列出遠端可用的備份目錄並產生 appList_network.txt
# 流程: 連遠端 → 列 Backup_*_* 目錄 → 讓使用者選 → 檢查必要檔案 → 掃 app 清單 → 輸出
remote_list_backups() {
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	# 規範化 remote_keep_local
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	# 目標目錄 = 跟本地備份一樣的命名規則
	local target_dir="Backup_${Compression_method}_${user:-0}"
	echoRgb "目標遠端目錄: $target_dir" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	# 進入目標目錄, 列出檔案/子資料夾
	local sub_listing="$TMPDIR/.remote_sub_listing"
	: > "$sub_listing"
	if [[ $remote_type = smb ]]; then
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local smb_out
		smb_out=$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
			-c "cd ${rem_path:-/}/$target_dir; ls; exit" 2>&1)
		if echo "$smb_out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端目錄不存在: $target_dir" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			rm -f "$sub_listing"
			return 1
		fi
		if echo "$smb_out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "讀取遠端失敗:" "0"
			echo "$smb_out" | grep -E 'NT_STATUS|ERR' | head -3
			rm -f "$sub_listing"
			return 1
		fi
		# 格式: "D dirname" 或 "N filename"
		echo "$smb_out" | awk 'NF>=5 && $1 != "." && $1 != ".." {print $2, $1}' > "$sub_listing"
	elif [[ $remote_type = webdav ]]; then
		local base_url="${remote_url%/}"
		local http_code
		http_code=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$TMPDIR/.wdav_out" \
			"$base_url/$target_dir/" 2>/dev/null)
		case $http_code in
		2*) ;;
		404) echoRgb "遠端目錄不存在: $target_dir (HTTP 404)" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		*) echoRgb "讀取遠端失敗 (HTTP $http_code)" "0"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		esac
		local propfind_out
		propfind_out=$(cat "$TMPDIR/.wdav_out" 2>/dev/null)
		rm -f "$TMPDIR/.wdav_out"
		# 解析每個 response, 過濾掉「目錄自己」(href 跟 base 同名)
		# 收集成 "D|encoded_name" 或 "N|encoded_name"
		local raw_listing="$TMPDIR/.raw_wdav_listing"
		echo "$propfind_out" | tr '><' '\n' | awk '
			/^D:response$/ { in_resp=1; href=""; is_dir=0 }
			/^\/D:response$/ {
				if (in_resp && href != "") {
					# 從 href 取最後一段 (URL 編碼狀態)
					n = split(href, a, "/")
					name = a[n]
					if (name == "" && n > 1) name = a[n-1]
					if (name != "" && name != "/") {
						print (is_dir ? "D" : "N") "|" name
					}
				}
				in_resp=0
			}
			/^D:href$/ { getline href }
			/^D:collection/ { is_dir=1 }
		' > "$raw_listing"
		# 過濾掉目錄自己 (encoded 或非 encoded 都比對)
		# target_dir 是 "Backup_zstd_0" 純 ASCII,不需要編碼
		grep -vE "\|${target_dir}\$" "$raw_listing" > "$sub_listing"
		rm -f "$raw_listing"
		# URL 解碼 (支援 UTF-8 中文)
		# 用 printf 將 %XX 轉成實際字元
		local decoded="$TMPDIR/.decoded_listing"
		: > "$decoded"
		while IFS='|' read -r typ name; do
			[[ -z $name ]] && continue
			# printf '%b' 不認 %XX, 要先轉成 \xXX
			local converted
			converted=$(echo "$name" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
			# 用 printf 把 \xXX 還原成真實字元
			local real
			real=$(printf '%b' "$converted")
			echo "$typ $real" >> "$decoded"
		done < "$sub_listing"
		mv "$decoded" "$sub_listing"
	fi
	if [[ ! -s $sub_listing ]]; then
		echoRgb "遠端目錄為空或讀取失敗" "0"
		rm -f "$sub_listing"
		return 1
	fi
	# 檢查必要檔案: tools/ start.sh restore_settings.conf
	local has_tools=0 has_start=0 has_conf=0
	while read -r type name; do
		case "$name" in
		tools) [[ $type = D ]] && has_tools=1 ;;
		start.sh) [[ $type != D ]] && has_start=1 ;;
		restore_settings.conf) [[ $type != D ]] && has_conf=1 ;;
		esac
	done < "$sub_listing"
	local missing=""
	[[ $has_tools = 0 ]] && missing="$missing tools/"
	[[ $has_start = 0 ]] && missing="$missing start.sh"
	[[ $has_conf = 0 ]] && missing="$missing restore_settings.conf"
	if [[ -n $missing ]]; then
		echoRgb "錯誤: 遠端 $target_dir 缺少必要檔案:$missing" "0"
		echoRgb "此備份不完整,無法用於恢復" "0"
		rm -f "$sub_listing"
		return 1
	fi
	echoRgb "必要檔案檢查通過 (tools/ start.sh restore_settings.conf)" "1"
	# 產生 appList_network.txt
	# 規則:
	#   - 排除 tools, start.sh, restore_settings.conf (固定下載項)
	#   - 是目錄: wifi/Media → 特殊項; 其他 → app
	#   - 是檔案就忽略
	local out="$MODDIR/appList_network.txt"
	{
		echo "# 遠端備份目錄: $target_dir"
		echo "# 連線: $remote_type://$REMOTE_HOST/"
		echo "# 用 # 註解掉不要下載的項目, 編輯完選 '從遠端下載備份' 即可"
		echo ""
		echo "# ---- 應用 (每行一個 app) ----"
		local apps="$TMPDIR/.apps_list"
		: > "$apps"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in
			tools|wifi|Media) continue ;;
			esac
			echo "$name" >> "$apps"
		done < "$sub_listing"
		sort "$apps"
		rm -f "$apps"
		echo ""
		echo "# ---- 特殊項目 (非 app, 有就會下載) ----"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in
			wifi|Media) echo "$name" ;;
			esac
		done < "$sub_listing"
	} > "$out"
	rm -f "$sub_listing"
	echoRgb "已輸出清單: $out" "1"
	echoRgb "請編輯該檔案,留下你要下載的項目,然後選 '從遠端下載備份'" "3"
}

# 依 appList_network.txt 下載備份到 $MODDIR/Backup_*_$user
remote_download_backup() {
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	local list="$MODDIR/appList_network.txt"
	if [[ ! -f $list ]]; then
		echoRgb "找不到 $list" "0"
		echoRgb "請先執行 '列出遠端備份' 產生清單" "3"
		return 1
	fi
	local dl_start
	dl_start=$(date +%s)
	# 目標目錄 = 跟本地備份一樣的命名規則
	local chosen="Backup_${Compression_method}_${user:-0}"
	echoRgb "目標遠端目錄: $chosen" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	# 解析清單 (去除註解/空行)
	local items_file="$TMPDIR/.dl_items"
	grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$list" > "$items_file"
	if [[ ! -s $items_file ]]; then
		echoRgb "清單為空,沒有東西需要下載" "0"
		rm -f "$items_file"
		return 1
	fi
	local item_count
	item_count=$(wc -l < "$items_file")
	echoRgb "將下載 $item_count 個項目 + 固定 3 項 (tools/ start.sh restore_settings.conf)" "3"
	# 下載目標: $MODDIR/$chosen (例: $MODDIR/Backup_zstd_0)
	local dest="$MODDIR/$chosen"
	mkdir -p "$dest" 2>/dev/null
	echoRgb "下載到: $dest" "2"
	# 依協議分派
	local fail=0
	if [[ $remote_type = smb ]]; then
		_remote_download_smb "$chosen" "$dest" "$items_file" || fail=1
	elif [[ $remote_type = webdav ]]; then
		_remote_download_webdav "$chosen" "$dest" "$items_file" || fail=1
	fi
	rm -f "$items_file"
	local dl_elapsed=$(( $(date +%s) - dl_start ))
	if [[ $fail -eq 0 ]]; then
		echoRgb "_______________________________________" "2"
		echoRgb "下載完成: $dest 用時${dl_elapsed}秒" "1"
		echoRgb "可直接執行 $dest/start.sh 進行恢復" "3"
		remote_log "下載完成: $dest 用時${dl_elapsed}秒"
	else
		echoRgb "下載過程有失敗,請檢查上方訊息 (用時${dl_elapsed}秒)" "0"
		remote_log "下載失敗 用時${dl_elapsed}秒"
		return 1
	fi
}

# SMB 下載實作
# 每個 item 一次 smbclient (用 -D 直接切目錄,避免 cd 路徑解析問題)
# $1=遠端 Backup_zstd_X 目錄名, $2=本地目標, $3=要下載的項目清單檔
_remote_download_smb() {
	local chosen="$1" dest="$2" items_file="$3"
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	local SMB_OPTS="-t 30 -s /dev/null"
	local base="${rem_path:+$rem_path/}$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local idx=0 fail_total=0
	# 下載每個項目 (用 -D 切到指定目錄, 再 mget *)
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		echoRgb "[$idx/$total_items] 下載 $item" "3"
		mkdir -p "$dest/$item" 2>/dev/null
		local out
		out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
			-D "$base/$item" \
			-c "lcd $dest/$item; prompt off; recurse on; mget *; exit" 2>&1)
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_[A-Z_]+' \
			|| [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "  ✗ $item" "0"
			echo "$out" | grep -E 'NT_STATUS' | head -3
			let fail_total++
		else
			echoRgb "  ✓ $item" "1"
		fi
	done < "$items_file"
	# 固定 3 項: tools/ (獨立連線)
	echoRgb "下載固定項目: tools/ start.sh restore_settings.conf" "3"
	mkdir -p "$dest/tools" 2>/dev/null
	local tools_out
	tools_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base/tools" \
		-c "lcd $dest/tools; prompt off; recurse on; mget *; exit" 2>&1)
	tools_out="$(smb_filter_noise "$tools_out")"
	# 固定 3 項: start.sh / restore_settings.conf (獨立連線)
	local fix_out
	fix_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base" \
		-c "lcd $dest; prompt off; get start.sh; get restore_settings.conf; exit" 2>&1)
	fix_out="$(smb_filter_noise "$fix_out")"
	# 驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "  固定項目下載有錯誤" "0"
		echo "$tools_out
$fix_out" | grep -E 'NT_STATUS' | head -5
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "  tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "  start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "  restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "  ✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}

# WebDAV 下載實作 (並行模式: 先遞迴掃出所有檔案 url, 再 curl -Z 並行下載)
_remote_download_webdav() {
	local chosen="$1" dest="$2" items_file="$3"
	local base_url="${remote_url%/}/$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local fail_total=0
	# 遞迴掃描 WebDAV 路徑, 把所有檔案 (含子目錄內) 寫入清單檔
	# 清單格式: <遠端編碼URL>\t<本地完整路徑>
	# $1=遠端 base url (已編碼), $2=本地目錄, $3=清單檔
	_webdav_scan_files() {
		local r_url="$1" l_dir="$2" out_list="$3"
		mkdir -p "$l_dir" 2>/dev/null
		local out
		out=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" "$r_url/" 2>/dev/null)
		local parsed="$TMPDIR/.wdav_scan_$$"
		echo "$out" | tr '><' '\n' | awk '
			/^D:response$/ { in_resp=1; href=""; is_dir=0 }
			/^\/D:response$/ {
				if (in_resp && href != "") {
					print (is_dir ? "D" : "F") "\t" href
				}
				in_resp=0
			}
			/^D:href$/ { getline href }
			/^D:collection/ { is_dir=1 }
		' > "$parsed"
		local r_url_basename_encoded r_url_basename
		r_url_basename_encoded="$(echo "$r_url" | sed 's|/$||; s|.*/||')"
		r_url_basename=$(url_decode_path "$r_url_basename_encoded")
		local rc=0
		while IFS=$'\t' read -r typ href; do
			[[ -z $href ]] && continue
			local encoded_name name
			encoded_name="$(echo "$href" | sed 's|/$||; s|.*/||')"
			name=$(url_decode_path "$encoded_name")
			[[ -z $name ]] && continue
			[[ $name = "$r_url_basename" ]] && continue
			if [[ $typ = D ]]; then
				_webdav_scan_files "$r_url/$encoded_name" "$l_dir/$name" "$out_list" || rc=1
			else
				# 寫入清單: URL\t本地路徑
				echo -e "$r_url/$encoded_name\t$l_dir/$name" >> "$out_list"
			fi
		done < "$parsed"
		rm -f "$parsed"
		return $rc
	}
	# 用 curl -Z (--parallel) 批次下載清單內的所有檔案
	# 每行 "url\tlocal_path", 並行度預設 4
	_webdav_parallel_get() {
		local list="$1"
		[[ ! -s $list ]] && return 0
		# 組裝 curl --config 格式: url + output 一對一
		local cfg="$TMPDIR/.curl_cfg_$$"
		: > "$cfg"
		while IFS=$'\t' read -r url lpath; do
			# curl config 格式: 每組 url + output
			# 路徑要用引號避開空白
			echo "url = \"$url\"" >> "$cfg"
			echo "output = \"$lpath\"" >> "$cfg"
		done < "$list"
		curl -sS -L --http1.1 --connect-timeout 10 --retry 2 -Z --parallel-max 4 \
			-u "$remote_user:$remote_pass" -K "$cfg" 2>/dev/null
		local rc=$?
		rm -f "$cfg"
		return $rc
	}
	# 1. 遞迴掃描所有要下載的檔案
	local all_files="$TMPDIR/.wdav_all_files"
	: > "$all_files"
	local idx=0
	local scan_fail=0
	# 1a. items_file 內每個項目
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		local encoded_item
		encoded_item=$(url_encode_path "$item")
		[[ -z $encoded_item ]] && encoded_item="$item"
		echoRgb "[$idx/$total_items] 掃描 $item" "3"
		if ! _webdav_scan_files "$base_url/$encoded_item" "$dest/$item" "$all_files"; then
			echoRgb "  ✗ 掃描失敗: $item" "0"
			scan_fail=1
			let fail_total++
		fi
	done < "$items_file"
	# 1b. 固定項目 tools/
	echoRgb "掃描固定項目: tools/" "3"
	if ! _webdav_scan_files "$base_url/tools" "$dest/tools" "$all_files"; then
		echoRgb "  ✗ 掃描失敗: tools/" "0"
		scan_fail=1
		let fail_total++
	fi
	# 1c. 固定檔案 start.sh / restore_settings.conf 直接加進清單
	for f in start.sh restore_settings.conf; do
		echo -e "$base_url/$f\t$dest/$f" >> "$all_files"
	done
	# 2. 並行下載
	local total_files
	total_files=$(wc -l < "$all_files")
	echoRgb "並行下載 $total_files 個檔案 (4 路同時)" "3"
	_webdav_parallel_get "$all_files"
	rm -f "$all_files"
	# 3. 事後驗證每個項目本地是否有檔案
	while read -r item; do
		[[ -z $item ]] && continue
		if [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "  ✗ $item (本地為空)" "0"
			let fail_total++
		else
			echoRgb "  ✓ $item" "1"
		fi
	done < "$items_file"
	# 固定項目驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "  固定項目下載有錯誤" "0"
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "  tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "  start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "  restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "  ✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}

# trap EXIT 觸發的遠端上傳函數
# 只在 backup/backup_media/backup_update_apk 成功完成後才觸發上傳
# 其他選項 (測試/列出/下載/退出) 不觸發, 由 REMOTE_TRIGGER 旗標控制
remote_cleanup() {
	# 只有在 backup / backup_media / backup_update_apk 跑完後才上傳
	# 其他功能 (測試連線、生成列表、檢查壓縮等) 不觸發上傳
	[[ $REMOTE_TRIGGER != 1 ]] && return 0
	case $remote_type in
	webdav) upload_remote "webdav" ;;
	smb) upload_remote "smb" ;;
	*) return 0 ;;
	esac
}
# 從 /proc/uptime 算出開機時長並格式化成 X天X時X分X秒
Show_boottime() {
	awk -F '.' '{run_days=$1 / 86400;run_hour=($1 % 86400)/3600;run_minute=($1 % 3600)/60;run_second=$1 % 60;printf("%d天%d時%d分%d秒",run_days,run_hour,run_minute,run_second)}' /proc/uptime 2>/dev/null
}
[[ -f /sys/block/sda/size ]] && ROM_TYPE="UFS" || ROM_TYPE="eMMC"
if [[ -f /proc/scsi/scsi ]]; then
	UFS_MODEL="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $2,$4}')"
else
	UFS_MODEL="$(cat "/sys/class/block/sda/device/inquiry" 2>/dev/null)"
	[[ $UFS_MODEL = "" ]] && UFS_MODEL="unknown"
fi
_model="$(getprop ro.product.model 2>/dev/null)"
Device_name="$(grep -Ew "$_model" "$tools_path/Device_List" 2>/dev/null | awk -F'"' '{print $4}' | head -1)"
[[ $Device_name = "" ]] && Device_name="$_model"
Manager_version="$(su -v 2>/dev/null)"
if [[ $Manager_version != "" ]]; then
    [[ $Manager_version = *KernelSU* ]] && ksu="ksu"
    [[ $ksu = "" && -d /data/adb/ksu ]] && ksu="ksu"
else
    if [[ -d /data/adb/ksu ]]; then
        Manager_version=KernelSU
        ksu="ksu"
    fi
fi
Socname="$(getprop ro.soc.model)"
if [[ $Socname != "" && -f $tools_path/soc.json ]]; then
    DEVICE_NAME="$(jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' "$tools_path/soc.json" 2>/dev/null)"
    RAMINFO="$(jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' "$tools_path/soc.json" 2>/dev/null)"
    [[ $DEVICE_NAME = null || $DEVICE_NAME = "" ]] && DEVICE_NAME="處理器:null"
    [[ $RAMINFO = null || $RAMINFO = "" ]] && RAMINFO="RAM:null"
else
    DEVICE_NAME="處理器:null"
    RAMINFO="RAM:null"
fi
_brand="$(getprop ro.product.brand 2>/dev/null)"
_device="$(getprop ro.product.device 2>/dev/null)"
_busybox_path="$(which busybox)"
_busybox_ver="$(busybox | head -1 | cut -d' ' -f2)"
echoRgb "---------------------SpeedBackup---------------------"
echoRgb "腳本路徑:$MODDIR\n -已開機:$(Show_boottime)\n -執行時間:$(date +"%Y-%m-%d %H:%M:%S")\n -busybox路徑:$_busybox_path\n -busybox版本:$_busybox_ver\n -腳本版本:$backup_version\n -管理器:$Manager_version\n -品牌:$_brand\n -型號:$Device_name($_device)\n -閃存顆粒:$UFS_MODEL($ROM_TYPE)\n -$DEVICE_NAME\n -$RAMINFO\n -Android版本:$release SDK:$sdk\n -內核:$(uname -r)\n -Selinux狀態:$([[ $(getenforce) = Permissive ]] && echo "寬容" || echo "嚴格")\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
case $MODDIR in
*Backup_*)
    if [[ -f $MODDIR/app_details.json ]]; then
        if [[ -d ${MODDIR%/*/*}/tools ]]; then
	        path_hierarchy="${MODDIR%/*/*}"
	    else
	        path_hierarchy="${MODDIR%/*}"
	    fi
	else
	    if [[ -d ${MODDIR%/*}/tools ]]; then
	        path_hierarchy="${MODDIR%/*}"
	    else
	        [[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR"
	    fi
	fi ;;
*) [[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR" ;;
esac
[[ $LANG = "" ]] && echoRgb "系統無參數語言獲取失敗\n -如果需要更改腳本語言請於$conf_path\n -Shell_LANG=填入對應數字" "0"
case $LANG in
*TW* | *tw* | *HK*)
	Script_target_language="zh-TW" ;;
*CN* | *cn*)
	Script_target_language="zh-CN" ;;
esac
echoRgb "$Script_target_language腳本"
# 互動式輸入選項 (音量鍵或數字鍵)
# 配合 keycheck 抓音量鍵, 沒音量鍵則退回鍵盤輸入
Enter_options() {
    echoRgb "$1" "2"
    unset option parameter
    while true ;do
        if [[ $option != "" ]]; then
            case $option in
            0|1)
                parameter="$option"
                [[ $option = 1 ]] && echoRgb "$2" "2" || echoRgb "$3" "2"
                break ;;
            *)
                echoRgb "$option參數錯誤 只能是0或1" "0"
                read option ;;
            esac
        else
            read option
        fi
    done
}
# 在生成 appList.txt 時, 為某個 app 補上額外資訊欄位
# (例如版本號、apk 路徑等), 供後續使用
add_entry() {
    app_name="$1"
    package_name="$2"
    # 檢查是否已經存在同樣的應用名稱
    if [[ $(echo "$3" | cut -d' ' -f1 | grep -w "^$app_name$") = $app_name ]]; then
        if [[ $(echo "$3" | cut -d' ' -f2 | grep -w "^$package_name$") != $package_name ]]; then
            # 如果應用名稱存在但包名不同，則需要添加數字後綴
            count=1
            new_app_name="${app_name}_${count}"
            while echo "$3" | grep -q "$new_app_name"; do
                count=$((count + 1))
                new_app_name="${app_name}_${count}"
            done
            app_name="$new_app_name"
        fi
    fi
    REPLY="$app_name $package_name"
}
if [[ ! -f ${0%/*}/app_details.json ]]; then
    if [[ $user = "" ]]; then
	    user_id="$(ls /data/user | tr ' ' '\n')"
	    if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
		    echo "$user_id" | while read -r; do
			    [[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
		    done
	        echoRgb "設備存在多用戶,選擇操作目標用戶"
	        if [[ $(echo "$user_id" | wc -l) = 2 ]]; then
	            user1="$(echo "$user_id" | sed -n '1p')"
	            user2="$(echo "$user_id" | sed -n '2p')"
	            case $Lo in
	            0|1)
	                echoRgb "音量上選擇用戶:$user1，音量下選擇用戶:$user2" "2"
	                Select_user="true"
		            get_version "$user1" "$user2" && user="$branch"
		            unset Select_user ;;
	            2)
	                Enter_options "輸入1選擇用戶:$user1 0用戶:$user2" "$user1" "$user2"
	                case $parameter in
	                0) user="$user2" ;;
	                1) user="$user1" ;;
	                esac ;;
	            esac
	        else
    	        while true ;do
    		        if [[ $option != "" ]]; then
    		            user="$option"
    			        break
    		        else
    		            echoRgb "請輸入需要操作目標分區" "1"
    			        read option
    	    	    fi
        	    done
            fi
        else
    	    user="0"
        fi
    else
        user_id="$(ls /data/user | tr ' ' '\n')"
	    if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
		    echo "$user_id" | while read -r; do
			    [[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
		    done
		else
		    echoRgb "主用戶:$user_id" "2" 
	    fi
	fi
else
    case $(echo "${0%}") in
    *zstd*) user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')" ;;
    *tar*) user="$(echo "${0%}" | sed 's/.*\/Backup_tar_\([0-9]*\).*/\1/')" ;;
    *) echoRgb "請勿修改備份資料夾名稱，保持原本的Backup_壓縮算法名稱_使用者id" "0" && exit 2 ;;
    esac
fi
[[ $user != 0 ]] && am start-user "$user"
path="/data/media/$user/Android"
path2="/data/user/$user"
path3="/data/user_de/$user"
[[ ! -d $path2 ]] && echoRgb "$user分區不存在，請將上方提示的用戶id按照需求填入\n -$conf_path配置項user=,一次只能填寫一個" "0" && exit 2
echoRgb "當前操作為用戶$user"
export USER_ID="$user"
unset LD_LIBRARY_PATH
#因接收USER_ID環境變量問題故將函數放在此處
alias appinfo="app_process /system/bin com.xayah.dex.HiddenApiUtil getInstalledPackagesAsUser $USER_ID $@"
alias appinfo2="app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageLabel $USER_ID $@"
alias appinfo3="app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageArchiveInfo $@"
alias get_ssaid="app_process /system/bin com.xayah.dex.SsaidUtil get $USER_ID $@"
alias set_ssaid="app_process /system/bin com.xayah.dex.SsaidUtil set $USER_ID $@"
alias get_uid="app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageUid $USER_ID $@"
alias get_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil getRuntimePermissions $USER_ID $@"
alias Set_true_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil grantRuntimePermission $USER_ID $@"
alias Set_false_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil revokeRuntimePermission $USER_ID $@"
alias Set_Ops="app_process /system/bin com.xayah.dex.HiddenApiUtil setOpsMode $USER_ID $@"
alias setDisplay="app_process /system/bin com.xayah.dex.HiddenApiUtil setDisplayPowerMode $@"
find_tools_path="$(find "$path_hierarchy"/* -maxdepth 1 -name "tools" -type d ! -path "$path_hierarchy/tools")"
# 備份 WiFi 密碼到指定目錄, 用 classes.dex 讀 system 內的 WifiConfigStore
backup_wifi() {
    local wifi_dir="$1"
    [[ -z $wifi_dir ]] && echoRgb "backup_wifi: 目錄參數為空" "0" && return 1
    [[ ! -d $wifi_dir ]] && mkdir -p "$wifi_dir"
    if [[ -d $wifi_dir ]]; then
        echoRgb "備份wifi密碼"
        rm -rf "${wifi_dir:?}"/*
        app_process /system/bin com.xayah.dex.NetworkUtil saveNetworks>"$wifi_dir/wifi.json"
        echo_log "wifi備份"
    fi
}
# 從備份恢復 WiFi 密碼 (寫回 WifiConfigStore)
recover_wifi() {
    if [[ -d $1 ]]; then
        if [[ -f $1/wifi.json ]]; then
            echoRgb "恢復wifi密碼"
            app_process /system/bin com.xayah.dex.NetworkUtil restoreNetworks "$1/wifi.json"
            echo_log "wifi恢復"
        else
            echoRgb "wifi.json遺失"
        fi
    else
        echoRgb "$1不存在 wifi無法恢復" "0"
    fi
}
Rename_script () {
    HT="${HT:=0}"
	find "$path_hierarchy" -maxdepth 3 -name "*.sh" -type f -not -name "tools.sh" | sort | while read -r; do
        MODDIR_NAME="${REPLY%/*}"
        FILE_NAME="${REPLY##*/}"
        if [[ -f ${REPLY%/*}/app_details.json || -f ${REPLY%/*}/app_details ]]; then
            if [[ $FILE_NAME = backup.sh ]]; then
                touch_shell "1" "$REPLY"
            elif [[ $FILE_NAME = recover.sh ]]; then
                touch_shell "3" "$REPLY"
            fi
        else
            if [[ -d ${REPLY%/*}/tools ]]; then
                if [[ $FILE_NAME = start.sh ]]; then
                    [[ -f ${REPLY%/*}/backup_settings.conf ]] && touch_shell "0" "$REPLY"
                    [[ -f ${REPLY%/*}/restore_settings.conf ]] && touch_shell "2" "$REPLY"
                fi
            fi
            let HT++
        fi
	done
	unset HT
}
# 在指定路徑生成入口腳本 (start.sh / backup.sh / recover.sh / upload.sh)
# $1=模式 (0/1/2/3/5), $2=目標檔案路徑
# 模式對應的 MODDIR 路徑推算規則不同 (依腳本放置位置)
touch_shell() {
    unset conf_path MODDIR_Path
    case $1 in
    0)
        MODDIR_Path='${0%/*}'
        MODDIR_Path1="$MODDIR_Path"
        conf_path='${0%/*}/backup_settings.conf' ;;
    1)
        MODDIR_Path='${0%/*/*/*}'
        MODDIR_Path1="$MODDIR_Path"
        conf_path='${0%/*/*/*}/backup_settings.conf' ;;
    2)
        MODDIR_Path='${0%/*}'
        MODDIR_Path1="$MODDIR_Path"
        conf_path='${0%/*}/restore_settings.conf' ;;
    3)        
        MODDIR_Path='${0%/*/*}'
        MODDIR_Path1='${0%/*}'
        conf_path='${0%/*/*}/restore_settings.conf' ;;
    5)
        # upload.sh: 放在 Backup_zstd_X/<app>/, MODDIR 是 Backup_zstd_X 自己
        MODDIR_Path='${0%/*/*/*}'
        MODDIR_Path1='${0%/*/*}'
        conf_path='${0%/*/*/*}/backup_settings.conf' ;;
    esac
    echo "#!/system/bin/sh
if [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then
    MODDIR=\"$MODDIR_Path1\"
    conf_path=\"$conf_path\"
    [ ! -f \"$conf_path\" ] && . \"$MODDIR_Path/tools/tools.sh\"
else
    echo \"$MODDIR_Path/tools/tools.sh遺失\"
fi
mkdir -p \"\${0%/*}/log\" 2>/dev/null
logfile=\"\${0%/*}/log/log_\$(date +%Y-%m-%d_%H-%M).txt\"
. \"$MODDIR_Path/tools/tools.sh\" | tee \"\$logfile\"
sed -i \"\$(printf 's/\033\[[0-9;]*m//g')\" \"\$logfile\"" > "$2"
}
# 從 zip 檔自動更新腳本 (檢測 $MODDIR 內的 .zip 並提取 tools.sh)
update_script() {
	[[ $zipFile = "" ]] && zipFile="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)"
	if [[ $zipFile != "" ]]; then
		case $(echo "$zipFile" | wc -l) in
		1)
			if [[ $(unzip -l "$zipFile" | awk '{print $4}' | grep -Eo "^backup_settings.conf$") != "" ]]; then
				unzip -o "$zipFile" -j "tools/tools.sh" -d "$MODDIR" &>/dev/null
				if [[ -f $MODDIR/tools.sh ]]; then
				    if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(awk '/backup_version/{print $1}' "$MODDIR/tools.sh" | cut -f2 -d '=' | head -1 | sed 's/\"//g' | tr -d "a-zA-Z")") -eq 0 ]]; then
					    shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$MODDIR/tools.sh")"
					    case $MODDIR in
					    *Backup_*)
						    if [[ -f $MODDIR/app_details.json ]]; then
                                echoRgb "請在${MODDIR%/*}更新腳本" "0"
                                rm -rf "$MODDIR/tools.sh"
                                exit 2
                            fi ;;
					    esac
					    echoRgb "從$zipFile更新"
					    if [[ -d $path_hierarchy/tools ]]; then
					        mv "$path_hierarchy/tools" "$TMPDIR"
					        [[ -d $TMPDIR/tools ]] && {
					        unzip -o "$zipFile" tools/* -d "$path_hierarchy" | sed 's/inflating/釋放/g ; s/creating/創建/g ; s/Archive/解壓縮/g'
					        echo_log "解壓縮${zipFile##*/}"
					        if [[ $result = 0 ]]; then
                                if [[ $shell_language != $Script_target_language ]]; then
                                    echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
                                    ts <"$path_hierarchy/tools/Device_List">temp && cp temp "$path_hierarchy/tools/Device_List" && rm temp
                                    echo_log "$path_hierarchy/tools/Device_List翻譯"
					                ts <"$path_hierarchy/tools/tools.sh">temp && cp temp "$path_hierarchy/tools/tools.sh" && rm temp && sed "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$path_hierarchy/tools/tools.sh" > temp && cp temp "$path_hierarchy/tools/tools.sh" && rm temp
                                    echo_log "$path_hierarchy/tools/tools.sh翻譯"
                                    HT=1
                                fi
                                update_backup_settings_conf>"$path_hierarchy/backup_settings.conf"
                                ts <"$path_hierarchy/backup_settings.conf">temp && cp temp "$path_hierarchy/backup_settings.conf" && rm temp
                                echo_log "$path_hierarchy/backup_settings.conf翻譯"
                                echo "$find_tools_path" | while read -r; do
                                    if [[ $REPLY != $path_hierarchy/tools ]]; then
                                        rm -rf "$REPLY"
                                        cp -r "$path_hierarchy/tools" "${REPLY%/*}"
                                        update_Restore_settings_conf>"${REPLY%/*}/restore_settings.conf"
                                        ts <"${REPLY%/*}/restore_settings.conf">temp && cp temp "${REPLY%/*}/restore_settings.conf" && rm temp
                                        echo_log "${REPLY%/*}/restore_settings.conf翻譯"
    							    fi
    							done
							    Rename_script
							    if [[ $Output_path != "" ]]; then
		                            [[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		                            if [[ ${Output_path:0:1} != / ]]; then
		                                update_path="$MODDIR/$Output_path/Backup_${Compression_method}_$user"
		                            else
		                                update_path="$Output_path/Backup_${Compression_method}_$user"
		                            fi
		                            rm -rf "$update_path/tools"
		                            cp -r "$path_hierarchy/tools" "$update_path"
		                            echoRgb "$update_path/tools已經更新完成"
		                        fi
					        else
						        mv "$TMPDIR/tools" "$MODDIR"
					        fi
					        rm -rf "$TMPDIR"/* "$zipFile" "$MODDIR/tools.sh"
					        echoRgb "更新完成 請重新執行腳本" "2"
					        exit
					        } || echoRgb "tools移動到TMPDIR失敗" "0"
					    fi
				    else
					    echoRgb "${zipFile##*/}版本低於當前版本,自動刪除" "0"
					    rm -rf "$zipFile" "$path_hierarchy/tools.sh"
				    fi
				else
				    rm -rf "$zipFile"
				    unset zipFile
				fi
			fi ;;
		*)
            echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zipFile" "0"
			exit 1 ;;
		esac
	fi
	unset NAME
}
update_script
zipFile="$(ls -t /storage/emulated/0/Download/*.zip 2>/dev/null | head -1)"
if [[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | grep -Ewo "^backup_settings.conf$") != "" ]]; then
    update_script
else
    zipFile="$(ls -t /storage/emulated/0/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv/*.zip 2>/dev/null | head -1)"
    [[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | grep -Ewo "^backup_settings.conf$") != "" ]] && update_script
fi
if [[ $sdk -lt 30 ]]; then
	alias INSTALL="pm install --user $user -r -t >/dev/null"
	alias create="pm install-create --user $user -tl"
else
    if [[ $sdk -gt 33 ]]; then
	    alias INSTALL="pm install -r --bypass-low-target-sdk-block -i com.android.vending --user $user -t >/dev/null"
        alias create="pm install-create -i com.android.vending --bypass-low-target-sdk-block --user $user -t"
    else
        alias INSTALL="pm install -r -i com.android.vending --user $user -t >/dev/null"
        alias create="pm install-create -i com.android.vending --user $user -t"
    fi
fi
#settings get system system_locales
Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
if [[ $path_hierarchy != "" && $Script_target_language != ""  ]]; then
	K=1
	J="$(find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | wc -l)"
	find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | while read -r; do
	    unset shell_language
	    shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY")"
	    case $shell_language in
	    zh-CN|zh-TW)
	        if [[ $Script_target_language != $shell_language ]]; then
	            [[ $K = 1 ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
	            ts <"$REPLY">temp && cp temp "$REPLY" && rm temp
	            if [[ $? = 0 ]]; then
	                touch "$TMPDIR/0"
	                echo_log "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")翻譯"
	                MODDIR="${0%/*}"
                    if [[ -f ${REPLY%/*/*}/backup_settings.conf ]]; then
                        update_backup_settings_conf>"${REPLY%/*/*}/backup_settings.conf"
                        ts <"${REPLY%/*/*}/backup_settings.conf">temp && cp temp "${REPLY%/*/*}/backup_settings.conf" && rm temp
                        echo_log "${REPLY%/*/*}/backup_settings.conf翻譯"
                    fi
                    if [[ -f ${REPLY%/*/*}/restore_settings.conf ]]; then
                        update_Restore_settings_conf>"${REPLY%/*/*}/restore_settings.conf"
                        ts <"${REPLY%/*/*}/restore_settings.conf">temp && cp temp "${REPLY%/*/*}/restore_settings.conf" && rm temp
                        echo_log "${REPLY%/*/*}/restore_settings.conf翻譯"
                    fi
	                sed "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$REPLY" > temp && cp temp "$REPLY" && rm temp
	                [[ $shell_language != $(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY") ]] && echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改成功" || echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改失敗" "0"
	                ts <"${REPLY%/*}/Device_List">temp && cp temp "${REPLY%/*}/Device_List" && rm temp
	                echo_log "${REPLY%/*}/Device_List翻譯"
	                [[ $K = 1 ]] && Rename_script
	            else
	                echoRgb "$REPLY ts進程出現錯誤" "0"
	            fi
	            let K++
	        fi ;;
	    esac
	done
    [[ -e $TMPDIR/0 ]] && rm "$TMPDIR/0" && echoRgb "轉換腳本完成，退出腳本重新執行即可使用" && exit 2
fi
#校驗選填是否正確
case $Lo in
0)
	[[ $update != "" ]] && isBoolean "$update" "update" && update="$nsx" || {
	echoRgb "自動更新腳本?\n -音量上更新，下不更新"
    get_version "更新" "不更新" && update="$branch"
    } ;;
1)
    [[ $update = "" ]] && {
    echoRgb "自動更新腳本?\n -音量上更新，下不更新"
	get_version "更新" "不更新" && update="$branch"
	} || isBoolean "$update" "update" && update="$nsx" ;;
2)
    [[ $update = "" ]] && {
    Enter_options "輸入1自動更新腳本，輸入0不自動更新腳本" "更新" "不更新" && isBoolean "$parameter" "update" && update="$nsx"
    } || {
    isBoolean "$update" "update" && update="$nsx"
    } ;;
*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
esac
if [[ $update = true ]]; then
    json="$(down "$Language")"
else
    echoRgb "自動更新被關閉" "0"
fi
if [[ $json != "" ]]; then
	tag="$(jq -r '.tag_name'<<< "$json" 2>/dev/null)"
	if [[ $tag != "" && $backup_version != $tag ]]; then
		if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$tag" | tr -d "a-zA-Z")") -eq 0 ]]; then
			download="$(jq -r '.assets[].browser_download_url'<<< "$json")"
			case $cdn in
			0) zip_url="$download" ;;
			1) zip_url="https://ghfast.top/$download" ;;
			2) zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download" ;;
			*) echoRgb "$conf_path cdn=設置錯誤 範圍只能是0-2" && exit 2 ;;
			esac
			if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$download" | tr -d "a-zA-Z")") -eq 0 ]]; then
				echoRgb "發現新版本:$tag"
				if [[ $update = true ]]; then
				    echoRgb "$(ts "更新日誌:\n$(down "$Language" | jq -r '.body')")"
					case $Lo in
					0|1) 
					    echoRgb "是否更新腳本？\n -音量上更新，音量下不更新" "2"
					    get_version "更新" "不更新" && choose="$branch" ;;
					2)
					    Enter_options "輸入1自動更新腳本，輸入0不自動更新腳本" "更新" "不更新" && isBoolean "$parameter" "update" && update="$nsx" ;;
					esac
					if [[ $choose = true ]]; then
					    echoRgb "下載中.....耐心等待 如果下載失敗請掛飛機"
						starttime1="$(date -u "+%s")"
						down "$zip_url" >"$MODDIR/update.zip" &
						wait
					    endtime 1
					    [[ ! -f $MODDIR/update.zip ]] && echoRgb "下載失敗" && exit 2
					    zipFile="$MODDIR/update.zip"
					fi
				else
					echoRgb "$conf_path內update選項為0忽略更新僅提示更新" "0"
				fi
			fi
		fi
	fi
else
    [[ $update = true ]] && echoRgb "更新獲取失敗" "0"
fi
update_script
# 計算本地備份目錄路徑
# 格式: $Output_path/Backup_${Compression_method}_${user}
# 並建立目錄, 設定 $Backup 全域變數供其他函數使用
backup_path() {
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		if [[ ${Output_path:0:1} != / ]]; then
		    Directory_type="相對路徑"
		    Backup="$MODDIR/$Output_path/Backup_${Compression_method}_$user"
		else
		    Directory_type="絕對路徑"
		    Backup="$Output_path/Backup_${Compression_method}_$user"
		fi
		outshow="使用自定義目錄($Directory_type)"
	else
	    Backup="$MODDIR/Backup_${Compression_method}_$user"
	    if [[ ! -f ${0%/*}/app_details.json ]]; then
		    outshow="使用當前路徑作為備份目錄"
		else
		    [[ -d $Backup ]] && outshow="使用上層路徑作為備份目錄" || echoRgb "$Backup目錄不存在" "0"
		fi
	fi
	PU="$(mount | awk '$3 ~ "/mnt/media_rw/[^/]+$" {print $3, $5}' | grep -Ev "$mount_point")"
	OTGPATH="$(echo "$PU" | cut -d' ' -f1)"
	OTGFormat="$(echo "$PU" | cut -d' ' -f2)"
	if [[ -d $OTGPATH ]]; then
		if [[ $(echo "$MODDIR" | grep -Eo "^${OTGPATH}") != "" ]]; then
			hx="true"
			Backup="$MODDIR/Backup_${Compression_method}_$user"
		else
		    case $Lo in
		    0|1)
			    echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
			    get_version "選擇了隨身碟備份" "選擇了本地備份" ;;
			2)
			    Enter_options "檢測到隨身碟，輸入1使用隨身碟備份 0本地備份" "選擇了隨身碟備份" "本地備份" && isBoolean "$parameter" "branch" && branch="$nsx" ;;
			esac
			[[ $branch = true ]] && hx="$branch"
			[[ $hx = true ]] && Backup="$OTGPATH/Backup_${Compression_method}_$user"
		fi
		if [[ $hx = true ]]; then
			if [[ $OTGFormat = vfat ]]; then
				echoRgb "隨身碟檔案系統$OTGFormat不支持超過單檔4GB\n -請格式化為exfat" "0"
				exit 
		    fi
		    outshow="於隨身碟備份" && hx=usb
		fi
	fi
	[[ ! -d $Backup ]] && mkdir -p "$Backup"
	#分區詳細
	if [[ $(echo "$Backup" | grep -Eo "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
	remote_setup
}
# 計算指定目錄的總大小並輸出可讀字串 (KB/MB/GB)
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(find "$1" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
    if [[ $filesizee -gt $filesize ]]; then
        NJL="本次備份增加 $(size "$(echo "scale=2; $filesizee - $filesize" | bc)")"
    elif [[ $filesizee -lt $filesize ]]; then
        NJL="本次備份減少 $(size "$(echo "scale=2; $filesize - $filesizee" | bc)")"
    else
        NJL="文件大小未改變"
    fi
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(size "$filesizee")"
	echoRgb "$NJL"
}
# 把 bytes 轉成人類可讀格式 (B/KB/MB/GB)
# 用法: size <bytes 數值> 或 size <檔案路徑> (會 stat 取大小)
size() {
    local b_size get_size
    case $1 in
    *[!0-9]*)
        b_size="$(ls -l "$1" 2>/dev/null | awk '{print $5}')" ;;
    *)
        b_size="$1" ;;
    esac
    if [[ $b_size -eq 0 ]]; then
	    get_size="0 bytes"
    elif [[ $(echo "$b_size < 1024" | bc) -eq 1 ]]; then
        get_size="${b_size} bytes"
    elif [[ $(echo "$b_size < 1048576" | bc) -eq 1 ]]; then
        get_size="$(echo "scale=2; $b_size / 1024" | bc) KB"
    elif [[ $(echo "$b_size < 1073741824" | bc) -eq 1 ]]; then
        get_size="$(echo "scale=2; $b_size / 1048576" | bc) MB"
    else
        get_size="$(echo "scale=2; $b_size / 1073741824" | bc) GB"
    fi
    echo "$get_size"
}
#分區佔用信息
partition_info() {
    unset Skip
	Occupation_status="$(df -B1 "${1%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1)}')"
	Filesize2="$(size "$Filesize")"
	echo " -$2大小:$Filesize2 剩餘大小:$(size "$Occupation_status")"
	if [[ -n $Filesize ]]; then
        if awk -v a="$Filesize" -v b="$Occupation_status" 'BEGIN{exit !(a+0 > b+0)}'; then
            echoRgb "$2備份大小將超出rom可用大小" "0"
            Skip=1
        fi
    fi
	Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
# 取得指定 app 的後台運行 PID (用於跳過正在運行的 app)
Process_Information() {
    dumpsys activity processes | awk -v key="$1" -v user="$user" 'function getUserFromUid(uid){return int(uid/100000)} /^ *user #[0-9]+ uid=/ {if($0 ~ /ISOLATED uid=[0-9]+/){uid="";pid="";pkg="";next} if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)){print pid}} uid="";pid="";pkg=""; if($0 ~ /uid=/ && uid==""){tmp=$0; sub(/^.*uid=/,"",tmp); sub(/ .*/,"",tmp); uid=tmp}} /packageList=\{/ {tmp=$0; sub(/^.*packageList=\{/,"",tmp); sub(/\}.*/,"",tmp); pkg=tmp} /pid=/ {tmp=$0; sub(/^.*pid=/,"",tmp); sub(/ .*/,"",tmp); pid=tmp} END {if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)){print pid}}}'
}
# 強制終止指定 app (am force-stop + pkill 雙保險)
kill_app() {
    process_Information="$(Process_Information "$name2")"
    if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
        if [[ $process_Information != "" ]]; then
            am force-stop --user "$user" "$name2" &>/dev/null
            echo "$process_Information" | xargs -r kill -9
            pkill -9 -f "$name2$|$name2[:/_]"
            #killall -9 "$name2" &>/dev/null
            #am kill "$name2" &>/dev/null
            echoRgb "殺死$name1進程"
        fi
	fi
}
# 備份 app 的 apk 檔 (含 split apk, 用 tar/zstd 打包)
Backup_apk() {
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
	apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
	apk_version2="$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
	if [[ $apk_version = $apk_version2 ]]; then
		[[ $(echo "$txt2" | sed -e '/^$/d' | cut -d' ' -f2 | awk -v pkg="$name2" '$1 == pkg {print $1}') = "" ]] && txt2="$txt2\n${Backup_folder##*/} $name2"
		unset xb
		let osj++
		result=0
		echoRgb "Apk版本無更新 跳過備份" "2"
	else
		if [[ $nobackup = false ]]; then
			if [[ $apk_version != "" ]]; then
				let osn++
				update_apk="$(echo "$name1 \"$name2\"")"
				update_apk2="$(echo "$update_apk\n$update_apk2")"
				echoRgb "版本:$apk_version>$apk_version2"
			else
				let osk++
				add_app="$(echo "$name1 \"$name2\"")"
				add_app2="$(echo "$add_app\n$add_app2")"
				echoRgb "版本:$apk_version2"
			fi
			unset Filesize
			Filesize="$(find "$apk_path2" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
			rm -rf "$Backup_folder/apk.tar"*
			partition_info "$Backup" "$name1 apk"
			if [[ $Skip != 1 ]]; then
    			#備份apk
    			echoRgb "$1"
    			echo "$apk_path" | sed -e '/^$/d' | while read -r; do
    				echoRgb "${REPLY##*/} $(size "$REPLY")"
    			done
    			(
    				cd "$apk_path2"
    				case $Compression_method in
    				tar | TAR | Tar) tar --checkpoint-action="ttyout=%T\r" -cf "$Backup_folder/apk.tar" *.apk ;;
    				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" -cf - *.apk | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/apk.tar.zst" ;;
    				esac
    			)
    			echo_log "備份$apk_number個Apk"
    			if [[ $result = 0 ]]; then
    			    Validation_file "$Backup_folder/apk.tar"*
    				if [[ $result = 0 ]]; then
    				    [[ $(echo "$txt2" | sed -e '/^$/d' | cut -d' ' -f2 | awk -v pkg="$name2" '$1 == pkg {print $1}') = "" ]] && txt2="$txt2\n${Backup_folder##*/} $name2"
                        [[ $apk_version != "" ]] && {
                        echoRgb "覆蓋app_details"
                        jq --arg apk_version "$apk_version2" --arg software "$name1" '.[$software].apk_version = $apk_version' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                        } || {
                        echoRgb "新增app_details"
                        extra_content="{
                          \"$name1\": {
                            \"PackageName\": \"$name2\",
                            \"apk_version\": \"$apk_version2\"
                          }
                        }"
                        jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                        }
    				else
    					rm -rf "$Backup_folder"
    				fi
    				if [[ $name2 = com.android.chrome ]]; then
    					#刪除所有舊apk ,保留一個最新apk進行備份
    					ReservedNum=1
    					FileNum="$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l)"
    					while [[ $FileNum -gt $ReservedNum ]]; do
    						OldFile="$(ls -rt /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)"
    						rm -rf "${OldFile%/*/*}" && echo "刪除文件:${OldFile%/*/*}"
    						let "FileNum--"
    					done
    					[[ -f $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null) && $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l) = 1 ]] && cp -r "$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)" "$Backup_folder/nmsl.apk"
    				fi
    			else
    				rm -rf "$Backup_folder"
    			fi
    	    fi
		else
			let osj++
			rm -rf "$Backup_folder"
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
# 備份 app 的 SSAID (應用識別碼)
# 用 classes.dex 透過 app_process 讀 /data/system/users/$user/settings_ssaid.xml
# 沒備份 SSAID 恢復後遊戲帳號會被當新裝置
Backup_ssaid() {
    Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
    ssaid="$(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info")"
    [[ $ssaid != null && $ssaid != "" ]] && echoRgb "SSAID:$ssaid"
    if [[ $ssaid != null && $ssaid != $Ssaid ]]; then
        echoRgb "備份ssaid"
        echoRgb "$Ssaid>$ssaid"
    	SSAID_apk="$(echo "$name1 \"$name2\"")"
        SSAID_apk2="$(echo "$SSAID_apk\n$SSAID_apk2")"
    	jq --arg entry "$name1" --arg new_value "$ssaid" '.[$entry].Ssaid |= $new_value' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    	echo_log "備份ssaid"
    fi
    [[ $ssaid = null ]] && ssaid=
}
# 備份 app 的 runtime permissions (運行時權限)
# 恢復時可一鍵還原所有授權, 不用再手動點
Backup_Permissions() {
    get_Permissions="$(jq -r '.[] | select(.permissions != null).permissions' "$app_details")"
    Get_Permissions="$(get_Permissions "$name2" | jq -nR '[inputs | select(. != "null" and length>0) | split(" ") | {(.[0]): (.[1:] | join(" "))}] | if length > 0 then add else empty end')"
    if [[ $Get_Permissions != "" && ($Get_Permissions = *true* || $Get_Permissions = *false*) ]]; then
        if [[ $get_Permissions = "" ]]; then
            echoRgb "備份權限"
            jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName].permissions |= $permissions' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
        	echo_log "備份權限"
        else
            if [[ $get_Permissions != "" && ($get_Permissions = *true* || $get_Permissions = *false*) ]]; then
        	    if [[ $get_Permissions != $Get_Permissions ]]; then
        	        echoRgb "權限變更"
        	        jq -n --argjson old "$get_Permissions" --argjson new "$Get_Permissions" '$new | to_entries | map(select(.key as $k | $old[$k] != null and $old[$k] != .value)) | .[].key' | sed 's/^/ /'
            	    jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName] |= . + {permissions: $permissions}' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
            	    echo_log "備份權限"
            	fi
        	fi
        fi
    else
        [[ $Get_Permissions != "" ]] && echoRgb "備份權限失敗$(get_Permissions "$name2")" "0"
    fi
}
#檢測數據位置進行備份
Backup_data() {
	data_path="$path/$1/$name2"
	MODDIR_NAME="${data_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	[[ -f $app_details ]] && Size="$(jq -r --arg entry "$1" '.[$entry] | select(.Size != null).Size' "$app_details" 2>/dev/null)"
	case $1 in
	user) data_path="$path2/$name2" ;;
	user_de) data_path="$path3/$name2" ;;
	data|obb) ;;
	*)
		data_path="$2"
		if [[ $1 != thanox ]]; then
			Compression_method1="$Compression_method"
			Compression_method=tar
		fi
		zsize=1
		zmediapath=1
		;;
	esac
	if [[ -d $data_path ]]; then
	    unset Filesize ssaid Get_Permissions result Permissions
        Filesize="$(find "$data_path" -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END {print s}')"
        [[ $Filesize != "" ]] && {
		if [[ $Size != $Filesize ]]; then
            case $1 in
            user)
                if [[ $(su "$(pm list packages -U --user "$user" </dev/null | awk -v pkg="$name2" -F'[ :]' '$2 == pkg {print $4}')" -c keystore_cli_v2 list | wc -l) -ge 2 ]]; then
                    echoRgb "$name1包含keystore 恢復可能閃退" "0"
                    jq --arg entry "$name1" '.[$entry].keystore |= "true"' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                else
                    jq --arg entry "$name1" '.[$entry].keystore |= "false"' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                fi
    		    Backup_ssaid
    			Backup_Permissions ;;
    	    esac
		    #停止應用
			case $1 in
			user|data|obb|user_de) kill_app ;;
			esac
			rm -rf "$Backup_folder/$1.tar"*
			partition_info "$Backup" "$1"
			if [[ $Skip != 1 ]]; then
    			echoRgb "備份$1數據"
    			# 判斷是否超過指定大小
                if [[ $Filesize2 != *"bytes"* ]]; then
                    if [[ $Filesize2 = *"KB"* ]]; then
                        if [[ $(echo "${Filesize2% KB}" | bc) > 1 ]]; then
                            Start_backup="true"
                        else
                            Start_backup="false"
                        fi
                    else
                        Start_backup="true"
                    fi
                else
                    Start_backup="false"
                fi
                if [[ $Start_backup = true ]]; then
        			case $1 in
        			user|user_de)
        				case $Compression_method in
        				tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null ;;
        				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" 2>/dev/null ;;
        				esac
        				;;
        			*)
            		    case $Compression_method in
            		    tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/QQ" --exclude="${data_path##*/}/Telegram" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" ;;
            			zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/QQ" --exclude="${data_path##*/}/Telegram" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
            			esac
        				;;
        			esac
        			echo_log "備份$1數據"
    			else
    			    echoRgb "$1數據 $Filesize2太小" "0" && result=1
    			fi
    			if [[ $result = 0 ]]; then
    			    Validation_file "$Backup_folder/$1.tar"*
    				if [[ $result = 0 ]]; then
    				    if [[ ! $Filesize -eq 0 ]]; then
                            size2="$(stat -c %s "$Backup_folder/$1.tar"*)"
                            rate="$(echo "scale=2; (1 - ($size2 / $Filesize)) * 100" | bc)"
                            echoRgb "壓縮率${rate}% 大小$(size "$size2")"
                        fi
    				    [[ ${Backup_folder##*/} = Media ]] && [[ $(sed -e '/^$/d' "$mediatxt" | grep -w "${REPLY##*/}.tar$" | head -1) = "" ]] && echo "$FILE_NAME" >> "$mediatxt"
    					if [[ $zsize != "" ]]; then
    					    extra_content="{
                              \"$1\": {
                                \"path\": \"$2\",
                                \"Size\": \"$Filesize\"
                              },
                              \"Backup time\": {
                                \"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
                              }
                            }"
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    					else
    					    extra_content="{
                              \"$1\": {
                                \"Size\": \"$Filesize\"
                              },
                              \"Backup time\": {
                                \"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
                              }
                            }"
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    					fi
    				else
    					rm -rf "$Backup_folder/$1".tar.*
    				fi
    			fi
    			[[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1"
    			unset Compression_method1
    		fi
		else
			[[ $Size != "" ]] && echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
		}
	else
		[[ -f $data_path ]] && echoRgb "$1是一個文件 不支持備份" "0"
	fi
}
# 恢復 app 的 data 資料 (解壓 tar.zst 到 /data/data/<pkg>/)
# 處理 selinux context、uid 綁定
Release_data() {
	tar_path="$1"
	X="$path2/$name2"
	MODDIR_NAME="${tar_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${tar_path##*/}"
	FILE_NAME2="${FILE_NAME%%.*}"
	case ${FILE_NAME##*.} in
	zst | tar)
		unset FILE_PATH Size Selinux_state
		[[ -f $app_details ]] && Size="$(jq -r --arg entry "$FILE_NAME2" '.[$entry] | select(.Size != null).Size' "$app_details" 2>/dev/null)"
		case $FILE_NAME2 in
		user)
		    if [[ -d $X ]]; then
		        [[ $(jq -r '.[] | select(.Ssaid != null).keystore' "$app_details") = true ]] && echoRgb "$name1存在keystore 恢復可能閃退" "0"
		        FILE_PATH="$path2"
		        Selinux_state="$(LS "$X" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)"
		    else
		        echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
		    fi ;;
		user_de)
		    X="$path3/$name2"
		    if [[ -d $X ]]; then
		        FILE_PATH="$path3"
		        Selinux_state="$(LS "$X" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)"
		    else
		        echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
		    fi ;;
		data) FILE_PATH="$path/data" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)" ;;
		obb) FILE_PATH="$path/obb" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)";;
		thanox) FILE_PATH="/data/system" && find "/data/system" -name "thanos"* -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
		*)
			if [[ $A != "" ]]; then
				if [[ ${MODDIR_NAME##*/} = Media ]]; then
				    FILE_PATH="$(jq -r --arg entry "${FILE_NAME2}" 'select(.[$entry].path != null).[$entry].path' "$app_details")"
					if [[ $FILE_PATH = "" ]]; then
						echoRgb "路徑獲取失敗" "0"
					else
						echoRgb "解壓路徑↓\n -$FILE_PATH" "2"
						FILE_PATH="${FILE_PATH%/*}"
						[[ ! -d $FILE_PATH ]] && mkdir -p "$FILE_PATH"
					fi
				fi
		    else
			    echoRgb "$tar_path名稱似乎有誤" "0"
			fi ;;
		esac
        echoRgb "恢復$FILE_NAME2數據 釋放$(size "$Size")" "3"
   		if [[ $FILE_PATH != "" ]]; then
            [[ ${MODDIR_NAME##*/} != Media ]] && rm -rf "$FILE_PATH/$name2"
		    case ${FILE_NAME##*.} in
			zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$tar_path" -C "$FILE_PATH" ;;
			tar) [[ ${MODDIR_NAME##*/} = Media ]] && tar --checkpoint-action="ttyout=%T\r" -axf "$tar_path" -C "$FILE_PATH" || tar --checkpoint-action="ttyout=%T\r" -amxf "$tar_path" -C "$FILE_PATH" ;;
			esac
		else
			Set_back_1
		fi
		echo_log "解壓縮$FILE_NAME"
		if [[ $result = 0 ]]; then
			case $FILE_NAME2 in
			user|data|obb|user_de)
			    G="$(pm list packages -U --user "$user" </dev/null | awk -v pkg="$name2" -F'[ :]' '$2 == pkg {print $4}')"
			    if [[ $G = "" ]]; then
			        G="$(dumpsys package "$name2" 2>/dev/null | awk -F'uid=' '{print $2}' | grep -Eo '[0-9]+' | head -n 1)"
				    [[ $(echo "$G" | grep -Eo '[0-9]+') = "" ]] && G="$(get_uid "$name2" 2>/dev/null)"
				fi
                G="$(echo "$G" | grep -Eo '[0-9]+')"
				if [[ $G != "" ]]; then
					if [[ -d $X ]]; then
					    case ${#G} in
					    5)
					        if [[ $user = 0 ]]; then
					            uid="$G:$G"
					        else
					            uid="$user$G:$user$G"
					        fi ;;
					    6|7|8|9|10)
					        uid="$G:$G" ;;
					    esac
                        case $FILE_NAME2 in
                        user|user_de)
                            case $FILE_NAME2 in
                            user) [[ $X = $path2/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
                            user_de) [[ $X = $path3/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
                            esac
                            if [[ $Validation_settings = true ]]; then
						        chown -hR "$uid" "$X/"
						        echo_log "設置用戶組$uid"
						        chcon -hR "$Selinux_state" "$X/" 2>/dev/null
						        echo_log "selinux上下文設置" "E"
						    else
						        echoRgb "路徑:$X出現錯誤"
						    fi ;;
						data|obb)
                            chown -hR "$uid" "$FILE_PATH/$name2/"
                            echo_log "設置用戶組$uid" "E"
                            chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>/dev/null
                            echo_log "selinux上下文設置" "E" ;;
					    esac
				    else
				        echoRgb "$FILE_NAME2路徑$X不存在" "0"
					fi
				else
                    echoRgb "uid獲取失敗" "0"
				fi
				;;
			thanox)
				restorecon -RF "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>/dev/null)/" 2>/dev/null
				echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
				;;
			esac
		fi
		;;
	*)
		echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
		Set_back_1
		;;
	esac
	rm -rf "$TMPDIR"/*
}
# 安裝 apk (含 split apk 處理), 自動繞過安裝驗證
installapk() {
	apkfile="$(find "$Backup_folder" -maxdepth 1 -name "apk.*" -type f 2>/dev/null)"
	if [[ $apkfile != "" ]]; then
		rm -rf "$TMPDIR"/*
		case ${apkfile##*.} in
		zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$apkfile" -C "$TMPDIR" ;;
		tar) tar --checkpoint-action="ttyout=%T\r" -xmpf "$apkfile" -C "$TMPDIR" ;;
		*)
			echoRgb "${apkfile##*/} 壓縮包不支持解壓縮" "0"
			Set_back_1
			;;
		esac
		echo_log "${apkfile##*/}解壓縮" && [[ -f $Backup_folder/nmsl.apk ]] && cp -r "$Backup_folder/nmsl.apk" "$TMPDIR"
	else
		echoRgb "你的Apk壓縮包離家出走了，可能備份後移動過程遺失了\n -解決辦法手動安裝Apk後再執行恢復腳本" "0"
	fi
	if [[ $result = 0 ]]; then
		case $(find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f 2>/dev/null | wc -l) in
		1)
			echoRgb "恢復普通apk" "2"
			INSTALL "$TMPDIR"/*.apk
			echo_log "Apk安裝"
			;;
		0)
			echoRgb "$TMPDIR中沒有apk" "0"
			;;
		*)
			echoRgb "恢復split apk" "2"
			b="$(create | grep -Eo '[0-9]+')"
			if [[ -f $TMPDIR/nmsl.apk ]]; then
				INSTALL "$TMPDIR/nmsl.apk"
				echo_log "nmsl.apk安裝"
			fi
			find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f | grep -v 'nmsl.apk' | while read -r apk; do
                pm install-write "$b" "${apk##*/}" "$apk" </dev/null >/dev/null
                echo_log "${apk##*/}安裝"
            done
			pm install-commit "$b" >/dev/null
			echo_log "split Apk安裝"
			;;
		esac
	fi
}
# 關閉 apk 安裝驗證 (verifier_verify_adb_installs)
# 避免 Play Protect / 系統驗證攔截批次安裝
disable_verify() {
	#禁用apk驗證
	settings put global verifier_verify_adb_installs 0 2>/dev/null
	#禁用安裝包驗證
	settings put global package_verifier_enable 0 2>/dev/null
	#未知來源
	settings put secure install_non_market_apps 1 2>/dev/null
	#關閉play安全校驗
	if [[ $(settings get global package_verifier_user_consent 2>/dev/null) != -1 ]]; then
		settings put global package_verifier_user_consent -1 2>/dev/null
		settings put global upload_apk_enable 0 2>/dev/null
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
	# 額外安全性攔截
    settings put global harmful_app_warning_on 0 2>/dev/null
    # 關閉應用的受限模式 (針對 Android 13/14 側載應用)
    settings put secure enhanced_confirmation_states 0 2>/dev/null
	# 設定檔案路徑
    FILE="/data/data/com.android.vending/shared_prefs/finsky.xml"
    if [[ -f $FILE ]]; then
        # 提取當前的 auto_update_enabled 值
        CURRENT_VALUE="$(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE")"
        if [[ $CURRENT_VALUE = true ]]; then
            sed -i '/<boolean name="auto_update_enabled" /s/value="true"/value="false"/' "$FILE"
            [[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "play自動更新已關閉" "3"
            echoRgb "殺死 Google Play 商店..."
            am force-stop com.android.vending
        else
            if [[ $CURRENT_VALUE = "" ]]; then
                sed -i '/<\/map>/i \    <boolean name="auto_update_enabled" value="false" />' "$FILE"
                [[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "auto_update_enabled已插入false,play自動更新已關閉" "3"
                echoRgb "殺死 Google Play 商店..."
                am force-stop com.android.vending
            else
                [[ $CURRENT_VALUE != false ]] && echoRgb "無法識別play auto_update_enabled當前$CURRENT_VALUE值" "0"
            fi
        fi
    fi
}
# 從 app 安裝資訊取得 app 名稱 / apk 路徑 / 版本等資料
# 用 classes.dex 透過 hidden API 拿到完整 PackageInfo
get_name(){
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	txt2="$MODDIR/mediaList.txt"
	if [[ $1 = Apkname ]]; then
		rm -rf "$txt" "$txt2"
		echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	fi
	rgb_a=118
	user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	starttime1="$(date -u "+%s")"
	i=1
	while read -r; do
		Folder="${REPLY%/*}"
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		unset PackageName NAME DUMPAPK ChineseName apk_version Ssaid dataSize userSize obbSize
		if [[ -f $Folder/app_details.json ]]; then
		    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$Folder/app_details.json" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$Folder/app_details.json")"
		    if [[ -f $Folder/Permissions ]]; then
		        unset Permissions
		        . "$Folder/Permissions"
		        jq --arg packageName "$ChineseName" --argjson permissions "$(echo "$Permissions" | jq -nR '[inputs | select(length>0) | split(" ") | {(.[0]): .[-1]}] | add')" '.[$packageName] |= . + {permissions: $permissions}' "$Folder/app_details.json" > "$TMPDIR/temp.json" && cp "$TMPDIR/temp.json" "$Folder/app_details.json" && rm "$Folder/Permissions" "$TMPDIR/temp.json" && echoRgb "更新$Folder/app_details.json"
		    fi
		else
		    if [[ -f $Folder/app_details ]]; then
		        . "$Folder/app_details" &>/dev/null
		        extra_content="{
                  \"$ChineseName\": {
                    \"PackageName\": \"$PackageName\",
                    \"apk_version\": \"$apk_version\",
                    \"Ssaid\": \"$Ssaid\"
                  },
                  \"data\": {
                    \"Size\": \"$dataSize\"
                  },
                  \"obb\": {
                    \"Size\": \"$obbSize\"
                  },
                  \"user\": {
                    \"Size\": \"$userSize\"
                  }
                }"
                echo "{\n}">"$Folder/app_details.json"
                jq --argjson new_content "$extra_content" '. += $new_content' "$Folder/app_details.json" > "$TMPDIR/temp.json" && cp "$TMPDIR/temp.json" "$Folder/app_details.json" && rm "$TMPDIR/temp.json" "$Folder/app_details"
            fi
		fi
		if [[ $PackageName = "" || $ChineseName = "" ]]; then
			echoRgb "${Folder##*/}包名獲取失敗，解壓縮獲取包名中..." "0"
			rm -rf "$TMPDIR"/*
			case ${REPLY##*.} in
			zst) tar -I zstd -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' ;;
			tar) tar -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' ;;
			*)
			    echoRgb "${REPLY##*/} 壓縮包不支持解壓縮" "0"
				Set_back_1
				;;
			esac
			echo_log "${REPLY##*/}解壓縮"
			if [[ $result = 0 ]]; then
				if [[ -f $TMPDIR/base.apk ]]; then
					DUMPAPK="$(appinfo3 "$TMPDIR/base.apk")"
					if [[ $DUMPAPK != "" ]]; then
						app=($DUMPAPK $DUMPAPK)
						PackageName="${app[1]}"
						ChineseName="${app[2]}"
						rm -rf "$TMPDIR"/*
					else
						echoRgb "appinfo輸出失敗" "0"
					fi
				fi
			fi
		fi
		if [[ $PackageName != "" && $ChineseName != "" ]]; then
		    if [[ $(echo "$Apk_info" | awk -v pkg="$PackageName" '$1 == pkg {print $1}') = "" ]]; then
		        echoRgb "$ChineseName已經不存在$user使用者中"
		        if [[ $delete_app = "" ]]; then
            		delete_app="$ChineseName $PackageName"
                else
                    delete_app="$delete_app\n$ChineseName $PackageName"
                fi      
    		fi
			case $1 in
			Apkname)
			    [[ -f $Folder/${PackageName}.sh ]] && rm -rf "$Folder/${PackageName}.sh"
		        [[ ! -f $Folder/recover.sh ]] && touch_shell "3" "$Folder/recover.sh"
			    [[ ! -f $Folder/backup.sh ]] && touch_shell "1" "$Folder/backup.sh"
				echoRgb "$i:$ChineseName $PackageName"
				if [[ $TMPTXT = "" ]]; then
        	        TMPTXT="#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market\n$ChineseName $PackageName"
        	    else
        	        TMPTXT="$TMPTXT\n$ChineseName $PackageName"
        	    fi
				let i++ ;;
			convert)
				if [[ ${Folder##*/} = $PackageName ]]; then
				    DIR_NAME="${Folder%/*}/$ChineseName"
				    echoRgb "${Folder##*/} > $ChineseName"
				else
				    DIR_NAME="${Folder%/*}/$PackageName"
				    echoRgb "${Folder##*/} > $PackageName"
				fi
                if [[ -d $DIR_NAME ]]; then
                    i=1
                    NEW_DIR_NAME="${DIR_NAME}_${i}"
                    while [[ -d $NEW_DIR_NAME ]]; do
                        i=$((i + 1))
                        NEW_DIR_NAME="${DIR_NAME}_${i}"
                    done
                    DIR_NAME="$NEW_DIR_NAME"
                fi
                mv "$Folder" "$DIR_NAME" ;;
			esac
		fi
		let rgb_a++
	done<<<"$(find "$MODDIR" -maxdepth 2 -name "apk.*" -type f 2>/dev/null | sort)"
	[[ $TMPTXT != "" ]] && echo "$TMPTXT">"$txt"
	if [[ -d $MODDIR/Media ]]; then
		echoRgb "存在媒體資料夾" "2"
		[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$txt2"
		find "$MODDIR/Media" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | while read -r; do
			echoRgb "${REPLY##*/}" && echo "${REPLY##*/}" >> "$txt2"
		done
		echoRgb "$txt2重新生成" "1"
	fi
	if [[ $delete_app != "" ]]; then
	    if [[ $(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
	        echoRgb "列出需要刪除的應用中....\n -$delete_app"
	        case $Lo in
	        0|1)
	            echoRgb "確認列表無誤後音量上刪除，音量下退出腳本編輯列表" "2"
		        get_version "刪除" "退出腳本" && Delete_App="$branch" ;;
		    2)
		        Enter_options "確認列表無誤後輸入1刪除，輸入0退出腳本編輯列表" "刪除" "退出腳本" && isBoolean "$parameter" "Delete_App" && Delete_App="$nsx" ;;
		    esac
		    if [[ $Delete_App = true ]]; then
		        echoRgb "警告 即將刪除未安裝應用資料夾，請再三確認後在執行" "0"
		        i=1
		        r="$(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }')"
		        while [[ $i -le $r ]]; do
		            name1="$(echo "$delete_app" | sed -e '/^$/d' | sed -n "${i}p" | cut -d' ' -f1)"
    		        name2="$(echo "$delete_app" | sed -e '/^$/d' | sed -n "${i}p" | cut -d' ' -f2)"
    		        Backup_folder="$MODDIR/$name1"
    		        [[ -d $Backup_folder ]] && rm -rf "$Backup_folder"
    		        echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$txt" 2>/dev/null)" >"$txt"
    		        let i++
    		    done
    		else
    		    exit 0
    	    fi
    	fi
    fi
    chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
    endtime 1
	exit 0
}
# 腳本自我檢測 (檢查工具完整性、權限、環境)
# 啟動時呼叫, 出問題會提示並退出
self_test() {
	if [[ $(dumpsys deviceidle get charging) = false && $(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+') -le 15 ]]; then
		echoRgb "電量$(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+')%太低且未充電\n -為防止備份檔案或是恢復因低電量強制關機導致檔案損毀\n -請連接充電器後備份" "0" && exit 2
	fi
}
# 驗證單一檔案的 sha256 校驗碼 (對照 tools 目錄內預存的雜湊)
Validation_file() {
	MODDIR_NAME="${1%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${1##*/}"
	echoRgb "校驗$FILE_NAME"
	case ${FILE_NAME##*.} in
	zst) zstd -t "$1" 2>/dev/null ;;
	tar) tar -tf "$1" &>/dev/null ;;
	esac
	echo_log "${FILE_NAME##*.}校驗"
}
# 檢查壓縮檔完整性 (zstd -t / tar -t)
# 主選單「壓縮檔完整性檢查」呼叫
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>/dev/null | sort)"
	i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | wc -l)"
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort | while read -r; do
		REPLY="${REPLY%/*}"
		echoRgb "校驗第$i/$r個資料夾 剩下$((r - i))個" "3"
		echoRgb "校驗:${REPLY##*/}"
		find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | sort | while read -r; do
			Validation_file "$REPLY"
			[[ $result != 0 ]] && echo "$REPLY">>"$error_log"
		done
		echoRgb "$((i * 100 / r))%"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n $(cat "$error_log")" || echoRgb "恭喜~~全數校驗通過" 
	rm -rf "$error_log"
}
Set_screen_pause_seconds () {
    if [[ $1 = on ]]; then
        #獲取系統設置的無操作息屏秒數
        if [[ $Get_dark_screen_seconds = "" ]]; then
	        Get_dark_screen_seconds="$(settings get system screen_off_timeout)"
	        #設置30分鐘後息屏
            settings put system screen_off_timeout 1800000
            echo_log "設置無操作息屏時間30分鐘"
        fi
        [[ $setDisplayPowerMode = true ]] && {
        setDisplay 0
        echo_log "設置螢幕狀態false"
        }
    elif [[ $1 = off ]]; then
        if [[ $Get_dark_screen_seconds != "" ]]; then
            settings put system screen_off_timeout "$Get_dark_screen_seconds"
            echo_log "設置無操作息屏時間為$Get_dark_screen_seconds"
            input keyevent 224
        fi
        [[ $setDisplayPowerMode = true ]] && {
        setDisplay 2
        echo_log "設置螢幕狀態true"
        }
    fi
}
restore_permissions () {
    echoRgb "恢復權限"
    appops reset --user "$user" "$name2" &>/dev/null
    true_permissions="$(jq -r 'to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("true")) | .key) | join(" ")' "$app_details")"
    false_permissions="$(jq -r 'to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("false")) | .key) | join(" ")' "$app_details")"
	Set_Ops_permissions="$(jq -r '.[] | select(.permissions != null).permissions | to_entries | map(.value | split(" ")) | map(select(.[1] != "-1")) | map(.[1:]) | flatten | join(" ")' "$app_details")"
	[[ $true_permissions != "" ]] && {
	Set_true_Permissions "$name2" "$true_permissions"
	[[ $? != 0 ]] && echo_log "設置允許權限"
	}
    [[ $false_permissions != "" ]] && {
    Set_false_Permissions "$name2" "$false_permissions"
    [[ $? != 0 ]] && echo_log "設置拒絕權限"
    }
    [[ $Set_Ops_permissions != "" ]] && {
    Set_Ops "$name2" "$Set_Ops_permissions"
    [[ $? != 0 ]] && echo_log "設置ops權限"
    }
}
# 取得當前正在後台運行的所有 app 列表
# 配合「後台應用忽略」設定, 跳過正在運行的 app 不備份
Background_application_list() {
    [[ $activity != false ]] && {
    if [[ $Background_apps_ignore = true || $1 = debug ]]; then
        unset Backstage
	    #獲取後台
	    Backstage="$(dumpsys activity activities | awk -v uid="$user" '/ActivityRecord\{/{split($4,a,"/"); user=$3; pkg=a[1]; if(user~/^u[0-9]+$/ && pkg!~/\//){sub(/^u/,"",user); if(uid=="" || user==uid) if(!seen[user","pkg]++) print pkg}}')"
	    if [[ $Backstage = "" ]]; then
            Backstage="$(am stack list | awk -v uid="$user" '/taskId/&&!/unknown/{split($2,a,"/"); pkg=a[1]; user="unknown"; for(i=1;i<=NF;i++) if($i~/^userId=/){split($i,b,"="); user=b[2]; break} if(uid==""||user==uid) if(!seen[pkg]++) print pkg}')"
            [[ $Backstage = "" ]] && {
            echoRgb "獲取當前後台應用失敗" "0" && unset Backstage
            }
        fi
    fi
    }
}
Background_application_list debug
pkgs="$(pm list packages --user "$user" | cut -f2 -d ':' | awk -v pkg="$(echo "$Backstage" | head -1)" '$1 == pkg {print $1}')"
if [[ $pkgs != "" ]]; then
    echoRgb "後台應用獲取成功($pkgs)" "1"
    [[ $(Process_Information "$pkgs") = "" ]] && echoRgb "應用pid獲取失敗" "0" || echoRgb "應用pid獲取成功$(Process_Information "$pkgs")" "1"
else
    echoRgb "後台應用獲取失敗" "0" activity=false
fi
unset Backstage
# 主備份函數 - 對 appList.txt 內所有 app 執行完整備份
# 流程: 讀清單 → 逐個 app → 備份 apk + data + user_de + obb → 備份 SSAID/權限
# 結尾備份 wifi、生成 start.sh、設置 REMOTE_TRIGGER=1 觸發遠端上傳
backup() {
	self_test
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	case $Lo in
	0)
		[[ $Backup_Mode != "" ]] && isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx" || {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		}
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
		        if [[ $blacklist_mode != "" ]]; then
		            isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		        else
        		    echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔\n -警告! " "2"
        		    get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
        		fi
            fi
        fi
		if [[ $Backup_Mode = true ]]; then
		    [[ $Backup_obb_data != "" ]] && isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx" || {
		    echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
		    get_version "備份" "不備份" && Backup_obb_data="$branch"
    		}
    		[[ $Backup_user_data != "" ]] && isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx" || {
    		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_user_data="$branch"
    		}
        else
            Backup_user_data="false"
            Backup_obb_data="false"
        fi
		[[ $backup_media != "" ]] && isBoolean "$backup_media" "backup_media" && backup_media="$nsx" || {
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
		}
		[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
		echoRgb "應用備份開始後關閉螢幕\n -音量上關閉，音量下不關閉" "2"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		}
		[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略備份\n -音量上忽略，音量下備份" "2"
		get_version "忽略" "備份" && Background_apps_ignore="$branch"
		} ;;
	1)
		[[ $Backup_Mode = "" ]] && {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		} || isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx"
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
    		    [[ $blacklist_mode = "" ]] && {
    		    echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔" "2"
    		    get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
		        } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
    		fi
    		[[ $Backup_obb_data = "" ]] && {
    		echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_obb_data="$branch"
    		} || isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
    		[[ $Backup_user_data = "" ]] && {
    		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_user_data="$branch"
    		} || isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
        fi
		[[ $backup_media = "" ]] && {
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
		} || isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
		[[ $setDisplayPowerMode = "" ]] && {
		echoRgb "應用備份開始後關閉螢幕\n -音量上關閉，音量下不關閉" "2"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		} || isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		[[ $Background_apps_ignore = "" ]] && {
		echoRgb "存在進程忽略備份\n -音量上忽略，音量下備份" "2"
		get_version "忽略" "備份" && Background_apps_ignore="$branch"
		} || isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
		;;
	2)
        [[ $Backup_Mode = "" ]] && {
        Enter_options "輸入1備份應用+數據，輸入0僅應用不包含數據" "應用+數據" "僅應用" && isBoolean "$parameter" "Backup_Mode" && Backup_Mode="$nsx"
        } || {
        isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx"
        }
		if [[ $Backup_Mode = true ]]; then
		    [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]] && {
		    [[ $blacklist_mode = "" ]] && {
		    Enter_options "選擇黑名單模式輸入1不備份，輸入0備份安裝檔" "不備份" "僅應用安裝檔" && isBoolean "$parameter" "blacklist_mode" && blacklist_mode="$nsx"
		    } || {
		    isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		    }
		    }
    		[[ $Backup_obb_data = "" ]] && {
    		Enter_options "是否備份外部數據 即比如原神的數據包\n -輸入1備份，輸入0不備份" "備份" "不備份" && isBoolean "$parameter" "Backup_obb_data" && Backup_obb_data="$nsx"
    		} || {
    		isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
    		}
    		[[ $Backup_user_data = "" ]] && {
    		Enter_options "是否備份使用者數據，輸入1備份，輸入0不備份" "備份" "不備份" && isBoolean "$parameter" "Backup_user_data" && Backup_user_data="$nsx"
    		} || {
    		isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
    		}
        fi
        [[ $backup_media = "" ]] && {
        Enter_options "全部應用備份結束後是否備份自定義目錄\n -輸入1備份，0不備份" "備份" "不備份" && isBoolean "$parameter" "backup_media" && backup_media="$nsx"
        } || {
        isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
        }
        [[ $setDisplayPowerMode = "" ]] && {
        Enter_options "應用備份開始後關閉螢幕\n -輸入1關閉，0不關閉" "關閉" "不關閉" && isBoolean "$parameter" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
        } || {
        isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
        }
        [[ $Background_apps_ignore = "" ]] && {
        Enter_options "存在進程忽略備份\n -輸入1不備份，0備份" "忽略" "備份" && isBoolean "$parameter" "Background_apps_ignore" && Background_apps_ignore="$nsx"
        } || {
        isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
        } ;;
    *)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
    esac
	i=1
	#數據目錄
	if [[ $list_location != "" ]]; then
	    if [[ ${list_location:0:1} = / ]]; then
	        txt="$list_location"
	    else
	        txt="$MODDIR/$list_location"
	    fi
	else
	    txt="$MODDIR/appList.txt"
	fi
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	txt_path="$txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來備份" "0" && exit 1
	TXT_NAME="${txt##*/}"
	case ${TXT_NAME##*.} in
	txt) ;;
	*) echoRgb "$txt不是腳本讀取格式" "0" && exit 2 ;;
	esac
	sort -u "$txt" -o "$txt" &>/dev/null
	data="$MODDIR"
	hx="本地"
	echoRgb "腳本受到內核機制影響 息屏後IO性能嚴重影響\n -請勿關閉終端或是息屏備份 如需終止腳本\n -請執行start.sh選擇終止腳本即可停止" "3"
	backup_path
	echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -音量鍵確認:$Lo\n -更新:$update\n -備份模式:$Backup_Mode\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -自定義目錄備份:$backup_media\n -存在進程忽略備份:$Background_apps_ignore\n -關閉螢幕:$setDisplayPowerMode"
	D="1"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	[[ ! -f ${0%/*}/app_details.json ]] && {
	echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
	while read -r ; do
	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
            app=($REPLY $REPLY)
    		if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	            if [[ $(echo "$Apk_info" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') != "" ]]; then
			        [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
    			    Tmplist="$Tmplist\n$REPLY"
    			else
                    echoRgb "$REPLY不存在系統，從列表中刪除" "0"
                fi
			fi
		else
		    Tmplist="$Tmplist\n$REPLY"
		fi
	done < "$txt"
	}
    [[ $Update_backup = true ]] && {
    echoRgb "檢查備份列表中已經更新應用" "3"
    while read -r apk; do
        Backup_folder="$Backup/$(echo "$apk" | cut -d':' -f1)"
        app_details="$Backup_folder/app_details.json"
        if [[ -d $Backup_folder ]]; then
            apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
            apk_version2="$(pm list packages --show-versioncode --user "$user" "$(echo "$apk" | cut -d':' -f2)" </dev/null | cut -f3 -d ':' | head -n 1)"
            [[ $apk_version != $apk_version2 ]] && {
            [[ $Tmplist2 = "" ]] && Tmplist2="${apk/:/ }" || Tmplist2="$Tmplist2\n${apk/:/ }"
            }
        fi
    done<<<"$(grep -Ev '^[#＃!]' "$txt" | awk '{print $1 ":" $2}')"
    }
    [[ $Tmplist != ""  ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
	if [[ $Tmplist2 != "" ]]; then
        txt="$(echo "$Tmplist2" | sort)"
    else
        [[ $Update_backup != "" ]] && echoRgb "應用目前無更新" "0" && exit 0
    fi
    if [[ ! -f $txt ]]; then
        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
    else
        txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
    fi
    r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
	[[ -f ${0%/*}/app_details.json ]] && r=1
	[[ $r = "" && ! -f ${0%/*}/app_details.json ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/start.sh" "0" && exit 1
	if [[ $Backup_Mode = true ]]; then
    	[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
    	[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
    fi
	[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
	txt2="$Backup/appList.txt"
	txt_path2="$txt2"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
	txt2="$(cat "$txt2")"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	if [[ -d $Backup/tools ]]; then
	    find "$Backup/tools" -maxdepth 1 -type f | while read -r; do
	        Tools_FILE_NAME="${REPLY##*/}"
	        if [[ -f $tools_path/$Tools_FILE_NAME ]]; then
	            filesha256="$(sha256sum "$tools_path/$Tools_FILE_NAME" 2>/dev/null | cut -d" " -f1)"
    	        filesha256_1="$(sha256sum "$REPLY" 2>/dev/null | cut -d" " -f1)"
    	        if [[ $filesha256 != $filesha256_1 ]]; then
    	            cp -r "$tools_path/$Tools_FILE_NAME" "$REPLY"
    	            echoRgb "更新$REPLY"
    	        fi
    	    fi
	    done
	fi
	filesize="$(find "$Backup" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
	Quantity=0
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	en=118
	osn=0; osj=0; osk=0
	#獲取已經開啟的無障礙
	var="$(settings get secure enabled_accessibility_services 2>/dev/null)"
	#獲取預設鍵盤
	keyboard="$(settings get secure default_input_method 2>/dev/null)"
    Set_screen_pause_seconds on
    [[ $txt != "" ]] && [[ $(echo "$txt" | cut -d' ' -f2 | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
	if [[ -f ${0%/*}/app_details.json ]]; then
	    ssaid_info="$(get_ssaid "$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")")"
	else
	    ssaid_info="$(get_ssaid "$(echo "$txt" | awk '{printf "%s ", $2}')")"
	fi
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	notification "101" "開始備份"
	# 保存本次備份實際使用的清單,供遠端上傳用 (純變數,不寫檔)
	# 此時 $txt 是過濾過註解後的字串內容
	[[ -n $remote_type && -n $txt ]] && REMOTE_APPLIST="$txt"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ ! -f ${0%/*}/app_details.json ]]; then
		    name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
        	name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
        else
            ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "${0%/*}/app_details.json" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")"
            name1="$ChineseName"
            name2="$PackageName"
        fi
		[[ $name2 = "" || $name1 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
		apk_path="$(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':')"
		apk_path2="$(echo "$apk_path" | head -1)"
		apk_path2="${apk_path2%/*}"
		if [[ -d $apk_path2 ]]; then
			echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
			echoRgb "備份 $name1" "2"
			notification "101" "備份第$i/$r個應用 剩下$((r - i))個
備份 $name1"
			unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version apk_version2  zsize zmediapath Size data_path Ssaid ssaid Permissions
			nobackup="false"
			Background_application_list
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略備份" "0" && nobackup="true"
			if [[ $Backup_Mode = true ]]; then
			    if [[ $name1 = !* || $name1 = ！* ]]; then
    				name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    				echoRgb "跳過備份所有數據" "0"
    				No_backupdata=1
    			fi
    			if [[ $(echo "$blacklist" | grep -w "^$name2$") = $name2 ]]; then
    			    if [[ $blacklist_mode = true ]]; then
    			        echoRgb "黑名單應用跳過備份" "0"
    			        nobackup="true"
    			    else
    				    echoRgb "黑名單應用跳過備份所有數據" "0"
    				fi
    				No_backupdata=1
    			fi
    	    fi
			Backup_folder="$Backup/$name1"
			app_details="$Backup_folder/app_details.json"
			if [[ -f $app_details ]]; then
				PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details")"
				[[ $PackageName != $name2 ]] && jq --arg name2 "$name2" 'walk(if type == "object" and .PackageName then .PackageName = $name2 else . end)' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
				echoRgb "上次備份時間$(jq -r --arg entry "Backup time" '.[$entry] | select(.date != null).date' "$app_details" 2>/dev/null)"
			fi
			[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
			starttime2="$(date -u "+%s")"
			[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			apk_number="$(echo "$apk_path" | wc -l)"
			if [[ $nobackup != true ]]; then
    			if [[ $apk_number = 1 ]]; then
    				Backup_apk "非Split Apk" "3"
    			else
    				Backup_apk "Split Apk支持備份" "3"
    			fi
    			if [[ $result = 0 && $No_backupdata = "" ]]; then
    				if [[ $Backup_Mode = true ]]; then
        				if [[ $Backup_obb_data = true ]]; then
        				    if [[ $name2 != bin.mt.plus ]]; then
        					    #備份data數據
        					    [[ $name1 = Nekogram ]] && rm -rf /data/media/0/Android/data/tw.nekomimi.nekogram/files/Telegram/Telegram\ {Video,Stories,Documents,Images}/{*,.*} 2>/dev/null
        					    Backup_data "data"
        					    #備份obb數據
        					    Backup_data "obb"
        					else
        					    echoRgb "$name1無法備份" "0"
        					fi
        				fi
        				#備份user數據
        				[[ $name2 != bin.mt.plus ]] && {
        				    [[ $Backup_user_data = true ]] && {
        				    Backup_data "user"
        				    Backup_data "user_de"
        				    }
        				}
        				[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>/dev/null)"
        		    fi
    			fi
    			[[ -f $Backup_folder/${name2}.sh ]] && rm -rf "$Backup_folder/${name2}.sh"
    		    [[ ! -f $Backup_folder/recover.sh ]] && touch_shell "3" "$Backup_folder/recover.sh"
    			[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "1" "$Backup_folder/backup.sh"
    			[[ ! -f $Backup_folder/upload.sh ]] && touch_shell "5" "$Backup_folder/upload.sh"
    		fi
			endtime 2 "$name1 備份" "3"
			lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
			echoRgb "完成$((i * 100 / r))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "3"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
		else
			echoRgb "$name1[$name2] 不在安裝列表，備份個寂寞？" "0"
		fi
		if [[ $i = $r ]]; then
			endtime 1 "應用備份" "3"
			#設置無障礙開關
			if [[ $var != "" ]]; then
				if [[ $var != null ]]; then
					settings put secure enabled_accessibility_services "$var" &>/dev/null 
					echo_log "設置無障礙"
					settings put secure accessibility_enabled 1 &>/dev/null
					echo_log "打開無障礙開關"
				fi
			fi
			#設置鍵盤
			if [[ $keyboard != "" ]]; then
				ime enable "$keyboard" &>/dev/null
				ime set "$keyboard" &>/dev/null
				settings put secure default_input_method "$keyboard" &>/dev/null
				echo_log "設置鍵盤$(appinfo2 "${keyboard%/*}" 2>/dev/null)"
			fi
			update_apk2="${update_apk2:="暫無更新"}"
			add_app2="${add_app2:="暫無更新"}"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2\n -包含SSAID的應用\n$SSAID_apk2" "3"
			notification "101" "app備份完成 $(endtime 1 "應用備份" "3")"
			[[ $txt2 != "" ]] && {
			echo "$txt2" | sort | sed '/^$/d'>"$txt_path2"
			}
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(echo "$Custom_path" | grep -Ev '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					notification "102" "Media備份開始"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
					[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
					app_details="$Backup_folder/app_details.json"
					[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
					mediatxt="$Backup/mediaList.txt"
					[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
					echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read -r; do
						echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
						notification "102" "備份第$A/$B個資料夾 剩下$((B - A))個"
						starttime2="$(date -u "+%s")"
						if [[ ${REPLY##*/} = adb ]]; then
						    if [[ $ksu != ksu ]]; then
			                    echoRgb "Magisk adb"
				                Backup_data "${REPLY##*/}" "$REPLY"
				            else
				                echoRgb "KernelSU adb不支持備份" "0"
 	                            Set_back_0
				            fi
						else
						    Backup_data "${REPLY##*/}" "$REPLY"
						fi
						endtime 2 "${REPLY##*/}備份" "1"
						echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2"
						rgb_d="$rgb_a"
						rgb_a=188
						echoRgb "_________________$(endtime 1 "已經")___________________"
						rgb_a="$rgb_d" && let A++
					done
					echoRgb "目錄↓↓↓\n -$Backup_folder"
					[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
					notification "102" "Media備份完成 $(endtime 1 "自定義備份")"
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		let i++ en++ nskg++
	done
	backup_wifi "$Backup/wifi"
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user"
	Calculate_size "$Backup"
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	notification "105" "備份完成 $(endtime 1 "批量備份開始到結束")"
	[[ -f $txt_path ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path"
	[[ -f $txt_path2 ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path2"
	REMOTE_TRIGGER=1
	exit
}
# 增量備份: 只備份版本號有更新的 app
# 對照 app_details.json 內舊版本, 沒變動的跳過
backup_update_apk() {
    Update_backup='true'
    backup
}
# 重新生成應用列表的 app 名稱欄位 (恢復模式選單用)
dumpname() {
	get_name "Apkname"
}
# 轉換 app 資料夾名稱 (舊格式 → 新格式)
convert() {
	get_name "convert"
}
# 對整個備份目錄做壓縮檔完整性檢查 (Check_archive 的批次入口)
check_file() {
	Check_archive "$MODDIR"
}
# 主恢復函數 - 安裝 apk + 恢復 data + 還原 SSAID/權限
# ssaid_mode=true 時只恢復含 SSAID 的 app
Restore() {
	self_test
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	if [[ ! -f ${0%/*}/app_details.json ]]; then
    	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/start.sh選擇終止腳本\n -否則腳本將繼續執行直到結束" "0"
    	echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/start.sh選擇轉換資料夾名稱"
    	txt="$MODDIR/appList.txt"
    	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來恢復" "0" && exit 2
	    sort -u "$txt" -o "$txt" 2>/dev/null
	    i=1
	    r="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	    [[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
    	Backup_folder2="$MODDIR/Media"
    	#校驗選填是否正確
    	case $Lo in
    	0)
        	[[ $recovery_mode != "" ]] && isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx" || {
        	echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
        	get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
        	}
        	[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
        	echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
        	get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
        	}
        	Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
        	if [[ $Get_user != $user ]]; then
        	    echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
        		get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
        	fi
        	if [[ -d $Backup_folder2 ]]; then
        	    [[ $media_recovery != "" ]] && isBoolean "$media_recovery" "media_recovery" && media_recovery="$nsx" || {
        		echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
        		get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
        		}
        	fi
        	[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
    		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
    		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
    		} ;;
		1)
    		echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
    	    get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
    	    echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
        	get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
    	    if [[ $Get_user != $user ]]; then
    	        echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
    		    get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
    	    fi
    	    echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
    	    get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
    	    echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		    get_version "忽略" "恢復" && Background_apps_ignore="$branch" ;;
		2)
		    [[ $recovery_mode = "" ]] && {
		    Enter_options "選擇應用恢復模式\n -輸入1僅恢復未安裝，0全恢復" "僅恢復未安裝" "全恢復" && isBoolean "$parameter" "recovery_mode" && recovery_mode="$nsx"
		    } || {
		    isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx"
		    }
		    [[ $setDisplayPowerMode = "" ]] && {
		    Enter_options "應用恢復時關閉螢幕\n -輸入1關閉，0不關閉" "關閉" "不關閉" && isBoolean "$parameter" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		    } || {
		    isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		    }
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
    	    [[ $Get_user != $user ]] && {
    	    [[ $recovery_mode2 = "" ]] && {
    	    Enter_options "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，輸入1繼續恢復，0不恢復並離開腳本" "恢復安裝" "離開腳本" && isBoolean "$parameter" "recovery_mode2" && recovery_mode2="$nsx"
    	    } || {
    	    isBoolean "$recovery_mode2" "recovery_mode2" && recovery_mode2="$nsx"
    	    }
    	    }
    	    [[ $media_recovery = "" ]] && {
    	    Enter_options "是否恢復多媒體\n -輸入1僅恢復，0不恢復" "恢復" "不恢復" && isBoolean "$parameter" "media_recovery" && media_recovery="$nsx"
    	    } || {
    	    isBoolean "$media_recovery" "media_recovery" && media_recovery="$nsx"
    	    }
    	    [[ $Background_apps_ignore = "" ]] && {
    	    Enter_options "存在進程忽略恢復\n -輸入1不恢復，0恢復" "忽略" "恢復" && isBoolean "$parameter" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } || {
    	    isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } ;;
		*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
		esac
    	[[ $recovery_mode2 = false ]] && exit 2
    	if [[ $recovery_mode = true && $ssaid_mode != true ]]; then
    		echoRgb "獲取未安裝應用中"
    		Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	if [[ $Apk_info != "" ]]; then
        	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	else
        	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	fi
        	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
    		while read -r ; do
                if [[ $(echo "$REPLY" | sed 's/^[ \t]*//') != \#* ]]; then
                    app=($REPLY $REPLY)
            		if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
        	            [[ $(echo "$Apk_info" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') = "" ]] && Tmplist="$Tmplist\n$REPLY"
                    fi
        		fi
        	done < "$txt"
    		if [[ $(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
    			echoRgb "獲取完成 預計安裝$(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }')個應用"
    			txt="$Tmplist"
    			case $Lo in
    			0|1)
    			    echoRgb "未安裝應用列表\n$txt\n確認無誤使用音量上繼續恢復，音量下退出腳本" "1"
    			    get_version "恢復安裝" "退出腳本" ;;
    			2)
    			    Enter_options "未安裝應用列表\n$txt\n-輸入1退出腳本，0恢復" "退出腳本" "恢復安裝" isBoolean "$parameter" "branch" && branch="$nsx" ;;
    			esac
    			[[ $branch = false ]] && exit
    		else
    			echoRgb "獲取完成 但備份內應用都已安裝....正在退出腳本" "0" && exit 0
    		fi
    	fi
    	if [[ $ssaid_mode = true ]]; then
    	     while read -r; do
    	        if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
            	    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$REPLY" | head -n 1)"
        		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$REPLY")"
        		    if [[ $ssaid_name = "" ]]; then
        		        ssaid_name="$ChineseName $PackageName"
        		    else
        		        ssaid_name="$ssaid_name\n$ChineseName $PackageName"
        		    fi
        		fi
            done<<<"$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort)"
            [[ $ssaid_name != "" ]] && txt="$ssaid_name"
        fi
        if [[ ! -f $txt ]]; then
	        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
	    else
	        txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
	    fi
	    r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
    	DX="批量恢復"
    else
        i=1
        r=1
        Backup_folder="$MODDIR"
	    app_details="$Backup_folder/app_details.json"
	    if [[ ! -f $app_details ]]; then
		    echoRgb "$app_details遺失，無法獲取包名" "0" && exit 1
	    else
		    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$app_details" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details")"
		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
	    fi
	    name1="$ChineseName"
	    name1="${name1:="${Backup_folder##*/}"}"
	    [[ $name1 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
	    name2="$PackageName"
	    [[ $name2 = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
	    DX="單獨恢復"
	    [[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
		}
    fi
	#開始循環$txt內的資料進行恢復
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	Set_screen_pause_seconds on
	en=118
	notification "105" "開始恢復app"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ ! -f ${0%/*}/app_details.json ]]; then
		    echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
		    notification "105" "恢復第$i/$r個應用 剩下$((r - i))個
恢復 $name1"
	        name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
	        name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
		    unset No_backupdata apk_version Permissions
		    if [[ $name1 = *! || $name1 = *！ ]]; then
			    name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    			echoRgb "跳過恢復$name1 所有數據" "0"
    			No_backupdata=1
    		fi
    		Backup_folder="$MODDIR/$name1"
    		if [[ -f "$Backup_folder/app_details.json" ]]; then
    		    app_details="$Backup_folder/app_details.json"
    		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
    		else
    		    echoRgb "$Backup_folder/app_details.json不存在" "0"
    		fi
    		[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
		fi
		if [[ -d $Backup_folder ]]; then
			echoRgb "恢復$name1" "2"
			Background_application_list
			restore="true"
		    [[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略恢復" "0" && restore="false"
			[[ $restore = true ]] && {
			starttime2="$(date -u "+%s")"
			if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') = "" ]]; then
				installapk
			else
		        [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]] && installapk && [[ $? = 0 ]] && echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
			fi
			if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') != "" ]]; then
				if [[ $No_backupdata = "" ]]; then
				    [[ $name2 != *mt* ]] && {
					kill_app
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read -r; do
						Release_data "$REPLY"
					done
					unset G
					restore_permissions
					Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
					if [[ $Ssaid != "" ]]; then
					    SSAID_Package="$(echo "$name1 $name2 $Ssaid")"
				        SSAID_Package2="$(echo "$SSAID_Package\n$SSAID_Package2")"
					    unset Ssaid
					fi
					}
				fi
			else
				[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
			fi
			endtime 2 "$name1恢復" "2" && echoRgb "完成$((i * 100 / r))%" "3"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
			}
		else
			echoRgb "$Backup_folder資料夾遺失，無法恢復" "0"
		fi
		if [[ $i = $r ]]; then
		    endtime 1 "應用恢復" "2"
		    [[ $SSAID_Package2 != "" ]] && {
		    echoRgb "開始恢復saaid" "0"
		    set_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s %s ", $2, $3}')"
		    ssaid_info="$(get_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s ", $2}')")"
		    echo "$SSAID_Package2" | while read -r; do
		        Ssaid="$(echo "$REPLY" | cut -d' ' -f3)"
		        name1="$(echo "$REPLY" | cut -d' ' -f1)"
		        name2="$(echo "$REPLY" | cut -d' ' -f2)"
		        if [[ $(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info") = $Ssaid ]]; then
		            echoRgb "$name1 SSAID恢復成功" "1"
		        else
		            echoRgb "$name1 SSAID恢復失敗" "0"
		        fi
			    unset Ssaid
			done
			echoRgb "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟" "0"
			notification "107" "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟"
			}
			notification "105" "app恢復完成 $(endtime 1 "應用恢復" "2")"
			[[ ! -f ${0%/*}/app_details.json ]] && {
			if [[ $media_recovery = true ]]; then
			    starttime1="$(date -u "+%s")"
			    app_details="$Backup_folder2/app_details.json"
			    txt="$MODDIR/mediaList.txt"
			    sort -u "$txt" -o "$txt" 2>/dev/null
			    A=1
	            B="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
                [[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
                notification "106" "Media恢復開始"
				while [[ $A -le $B ]]; do
		            name1="$(grep -Ev '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		            starttime2="$(date -u "+%s")"
		            echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		            Release_data "$Backup_folder2/$name1"
		            endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
                done
				endtime 1 "自定義恢復" "2"
				notification "106" "Media恢復完成 $(endtime 1 "Media恢復" "2")"
			fi
			recover_wifi "$MODDIR/wifi"
			}
		fi
		let i++ en++ nskg++
	done
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user"
	starttime1="$TIME"
	echoRgb "$DX完成" && endtime 1 "$DX開始到結束"
	notification "109" "恢復完成 $(endtime 1 "$DX開始到結束")"
	rm -rf "$TMPDIR"/*
}
# 恢復自定義資料夾 (Media 等)
Restore3() {
	self_test
	case $Lo in
	0|1)
	    echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -音量上繼續恢復自定義資料夾，音量下離開腳本" "2"
	    echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	    get_version "恢復自定義資料夾" "離開腳本" && [[ $branch = false ]] && exit 0 ;;
	2)
	    Enter_options "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -輸入1繼續恢復自定義資料夾，輸入0離開腳本" "恢復" "退出腳本" && isBoolean "$parameter" "branch" && branch="$nsx" && [[ $branch = false ]] && exit 0 ;;
	esac
	mediaDir="$MODDIR/Media"
	[[ -f "$mediaDir/app_details.json" ]] && app_details="$mediaDir/app_details.json"
	Backup_folder2="$mediaDir"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取媒體列表再來恢復" "0" && exit 2
	sort -u "$txt" -o "$txt" 2>/dev/null
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	echo_log() {
		if [[ $? = 0 ]]; then
			echoRgb "$1成功" "1" && result=0
		else
			echoRgb "$1恢復失敗，過世了" "0" && result=1
		fi
	}
	starttime1="$(date -u "+%s")"
	A=1
	B="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	Set_screen_pause_seconds on
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && exit 1
	notification "108" "Media恢復開始"
	while [[ $A -le $B ]]; do
		name1="$(grep -Ev '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	notification "108" "Media恢復完成 $(endtime 1 "Media恢復")"
}
# 僅恢復包含 SSAID 應用 (不含數據,只裝 apk + 還原 SSAID)
# 用於只想保留遊戲帳號識別、不要舊存檔的場景
Restore4() {
    if [[ $ssaid_mode_1 = true ]]; then
        while read -r; do
            if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
                ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$REPLY" | head -n 1)"
        	    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$REPLY")"
        	    if [[ $ssaid_name = "" ]]; then
        	        ssaid_name="$ChineseName $PackageName"
        	    else
        	        ssaid_name="$ssaid_name\n$ChineseName $PackageName"
        	    fi
        	fi
        done<<<"$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort)"
        [[ $ssaid_name != "" ]] && txt="$ssaid_name"
        i=1
        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
        r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
        while [[ $i -le $r ]]; do
            name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
    	    name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
    	    Backup_folder="$MODDIR/$name1"
    		if [[ -f "$Backup_folder/app_details.json" ]]; then
    		    app_details="$Backup_folder/app_details.json"
    		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
    		else
    		    echoRgb "$Backup_folder/app_details.json不存在" "0"
    		fi
        	[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
            if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') != "" ]]; then
    		    [[ $name2 != *mt* ]] && {
    			kill_app
    			Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
    			if [[ $Ssaid != "" ]]; then
    			    SSAID_Package="$(echo "$name1 $name2 $Ssaid")"
    		        SSAID_Package2="$(echo "$SSAID_Package\n$SSAID_Package2")"
    			    unset Ssaid
    			fi
    			}
    		fi
    		if [[ $i = $r ]]; then
                [[ $SSAID_Package2 != "" ]] && {
        	    echoRgb "開始恢復saaid" "0"
        	    set_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s %s ", $2, $3}')"
        	    ssaid_info="$(get_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s ", $2}')")"
        	    echo "$SSAID_Package2" | while read -r; do
        	        Ssaid="$(echo "$REPLY" | cut -d' ' -f3)"
        	        name1="$(echo "$REPLY" | cut -d' ' -f1)"
        	        name2="$(echo "$REPLY" | cut -d' ' -f2)"
        	        if [[ $(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info") = $Ssaid ]]; then
        	            echoRgb "$name1 SSAID恢復成功" "1"
        	        else
        	            echoRgb "$name1 SSAID恢復失敗" "0"
        	        fi
        		    unset Ssaid
        		done
        		echoRgb "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟" "0"
        		notification "107" "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟"
        		}
            fi
    		let i++
	    done
	fi
}
# 生成應用列表 (掃描所有已安裝 user app, 輸出到 appList.txt)
# 配合 blacklist/whitelist 過濾系統 app
Getlist() {
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內生成列表" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	case $Lo in
	0)
		[[ $blacklist_mode != "" ]] && isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx" || {
		echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
		get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
		} ;;
	1)
		if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
		    [[ $blacklist_mode = "" ]] && {
		    echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
		    get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
		    } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		fi ;;
	2)
	    [[ $blacklist_mode = "" ]] && {
	    Enter_options "選擇黑名單模式輸入1不輸出，輸入0輸出應用列表" "不輸出" "輸出應用列表" && isBoolean "$parameter" "blacklist_mode" && blacklist_mode="$nsx"
	    } || {
	    isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
	    } ;;
	*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
	esac
	txt="$TMPDIR/appList"
	[[ -f "$MODDIR/appList.txt" ]] && cat "$MODDIR/appList.txt" >"$txt"
	[[ ! -f $txt ]] && echo '#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）' >"$txt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	starttime1="$(date -u "+%s")"
	echoRgb "提示! 腳本默認會屏蔽預裝應用 如需備份請添加預裝應用白名單" "0"
	Apk_info="$(appinfo "system|user|xposed" "label|pkgName|flag" | grep -Ev 'ice.message|com.topjohnwu.magisk' | tr '/:' '_')"
	xposed_name="$(echo "$Apk_info" | awk '$3 == "xposed" {print $2}')"
	TARGET_PACKAGES="$(echo "$system" | paste -sd'|' - | sed 's/^|//')"
    Pre_installed_apps="$(echo "$Apk_info" | awk '$3 == "system" {print $1, $2}' | grep -Ew "$TARGET_PACKAGES")"
    Apk_info="$(echo "$(echo "$Apk_info" | awk '$3 != "system" {print $1, $2}')\n$Pre_installed_apps" | sort -u)"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	exit 2 ; } || Apk_info2="$(echo "$Apk_info" | cut -d' ' -f2)"
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	rb="0"
	Output_list() {
	    if [[ $(cat "$txt" | cut -f2 -d ' ' | grep -Ew "^${app_1[1]}$") != ${app_1[1]} ]]; then
	        [[ $REPLY2 = "" ]] && add_entry "${app_1[2]}" "${app_1[1]}" "$(grep -w "${app_1[2]}" "$txt")" || add_entry "${app_1[2]}" "${app_1[1]}" "$REPLY2"
	        case ${app_1[1]} in
			    *oneplus*|*miui*|*xiaomi*|*oppo*|*flyme*|*meizu*|com.android.soundrecorder|com.mfashiongallery.emag|com.mi.health|*coloros*|com.android.soundrecorder|com.duokan.phone.remotecontroller|com.android.calendar|com.android.deskclock|com.android.calendar|com.android.deskclock|com.google.android.safetycore|com.google.android.contactkeys|com.google.android.apps.messaging|com.google.android.calendar)
				    if [[ $(echo "$xposed_name" | grep -Ew "${app_1[1]}$") = ${app_1[1]} ]]; then
    				    echoRgb "$((i+1)):$app_name為Xposed模塊 進行添加" "0"
					    if [[ $REPLY2 = "" ]]; then
					        REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    else
					        REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    fi
					    let i++ rd++
				    else
					    if [[ $(echo "$whitelist" | grep -Ew "^${app_1[1]}$") = ${app_1[1]} ]]; then
					        if [[ $REPLY2 = "" ]]; then
					            REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					        else
					            REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					        fi
						    echoRgb "$((i+1)):$app_name ${app_1[1]}($rgb_a)"
						    let i++
					    else
						    echoRgb "$app_name 預裝應用 忽略輸出" "0"
						    if [[ $REPLY2 = "" ]]; then
    						    REPLY2="#$REPLY" && [[ $tmp = "" ]] && tmp="1"
						    else
						        REPLY2="$REPLY2\n#$REPLY" && [[ $tmp = "" ]] && tmp="1"
						    fi
						    let rc++
					    fi
				    fi
				    ;;
			    *)
				    if [[ $REPLY2 = "" ]]; then
					    REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					else
					    REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					fi
					if [[ $(echo "$xposed_name" | grep -Ew "${app_1[1]}$") = ${app_1[1]} ]]; then
			            echoRgb "$((i+1)):Xposed: $app_name ${app_1[1]}($rgb_a)"
			            let rd++
			        else
				        echoRgb "$((i+1)):$app_name ${app_1[1]}($rgb_a)"
				    fi
				    let i++
				    ;;
			esac
		else
	        let Q++
        fi
    }
    [[ $(echo "$blacklist" | grep -Ev '#|＃') != "" ]] && NZK=1
	echo "$Apk_info" | sed 's/[\/:()\[\]\-!]//g' | while read -r; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_1=($REPLY $REPLY)
		if [[ $NZK = 1 ]]; then
    		if [[ $(echo "$blacklist" | grep -Ew "^${app_1[1]}$") != ${app_1[1]} ]]; then
		        Output_list
		    else
		        if [[ $blacklist_mode = false ]]; then
		            Output_list
		            let rb++
		        else
		            echoRgb "${app_1[2]}黑名單應用 不輸出" "0"
		            let rb++
		        fi
		    fi
		else
		    Output_list
		fi
		if [[ $LR = $Apk_Quantity ]]; then
		    echo "$REPLY2">>"$txt"
			if [[ $(cat "$txt" | wc -l | awk '{print $1-2}') -lt $i ]]; then
				rm -rf "$txt"
				echoRgb "\n -輸出異常 請聯繫作者解決" "0"
				exit
			fi
			echoRgb "已經將預裝應用輸出至appList.txt並注釋# 需要備份則去掉#" "0"
			[[ $tmp != "" ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let rgb_a++ LR++
	done
	if [[ -f $txt ]]; then
	    while read -r ; do
    	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
                app=($REPLY $REPLY)
    		    if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	                if [[ $(echo "$Apk_info2" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') != "" ]]; then
			            [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
    			        Tmplist="$Tmplist\n$REPLY"
    			    else
                        echoRgb "$REPLY不存在系統，從列表中刪除" "0"
                    fi
                fi
            else
                Tmplist="$Tmplist\n$REPLY"
			fi
    	done < "$txt"
    	[[ $Tmplist != "" ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
    fi
	wait
	endtime 1
	cat "$txt">"$MODDIR/appList.txt" && rm "$txt"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$MODDIR/appList.txt"
	echoRgb "輸出包名結束 請查看$MODDIR/appList.txt"
}
# 備份自定義資料夾 (來自 Custom_path 設定)
# 例: Pictures / Download / DCIM / /data/adb 等
# 結尾設 REMOTE_UPLOAD_MEDIA=1 + REMOTE_TRIGGER=1
backup_media() {
	self_test
	backup_path
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(echo "$Custom_path" | grep -Ev '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
		[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
		[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
		app_details="$Backup_folder/app_details.json"
		[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
		filesize="$(find "$Backup_folder" -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END {print s}')"
		mediatxt="$Backup/mediaList.txt"
		[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
		Set_screen_pause_seconds on
		notification "109" "Media備份開始"
		echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read -r; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")" 
			if [[ ${REPLY##*/} = adb ]]; then
			    if [[ $ksu != ksu ]]; then
			        echoRgb "Magisk adb"
				    Backup_data "${REPLY##*/}" "$REPLY"
				fi
			else
			    Backup_data "${REPLY##*/}" "$REPLY"
			fi
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
		done
		Calculate_size "$Backup_folder"
		Set_screen_pause_seconds off
		[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
		endtime 1 "自定義備份"
		notification "109" "Media備份完成 $(endtime 1 "自定義備份")"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	REMOTE_TRIGGER=1
}
# 從 tools/Device_List 對照表查詢設備識別資訊 (處理器型號、RAM 規格等)
Device_List() {
    URL="https://raw.githubusercontent.com/KHwang9883/MobileModels/refs/heads/master/brands"
    rm -rf "$tools_path/Device_List"
    for i in $(echo "xiaomi\nxiaomi_en\nsamsung\nsamsung_global\nasus\nBlack_Shark\nBlack_Shark_en\ngoogle\nLenovo\nMEIZU\nMEIZU_en\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nOnePlus_en\nSony\nrealme\nrealme_en\nvivo\nvivo_en\noppo\noppo_en"); do
        echoRgb "獲取品牌$i"
        case $i in
        xiaomi) Brand_URL="$URL/xiaomi.md" ;;
        xiaomi_en) Brand_URL="$URL/xiaomi_en.md" ;;
        samsung) Brand_URL="$URL/samsung_cn.md" ;;
        samsung_global) Brand_URL="$URL/samsung_global_en.md" ;;
        asus) Brand_URL="$URL/asus.md" ;;
        Black_Shark) Brand_URL="$URL/blackshark.md" ;;
        Black_Shark_en) Brand_URL="$URL/blackshark_en.md" ;;
        google) Brand_URL="$URL/google.md" ;;
        Lenovo) Brand_URL="$URL/lenovo.md" ;;
        MEIZU) Brand_URL="$URL/meizu.md" ;;
        MEIZU_en) Brand_URL="$URL/meizu_en.md" ;;
        Motorola) Brand_URL="$URL/motorola.md" ;;
        Nokia) Brand_URL="$URL/nokia.md" ;;
        nothing) Brand_URL="$URL/nothing.md" ;;
        nubia) Brand_URL="$URL/nubia.md" ;;
        OnePlus) Brand_URL="$URL/oneplus.md" ;;
        OnePlus_en) Brand_URL="$URL/oneplus_en.md" ;;
        Sony) Brand_URL="$URL/sony_cn.md" ;;
        realme) Brand_URL="$URL/realme_cn.md" ;;
        realme_en) Brand_URL="$URL/realme_global_en.md" ;;
        vivo) Brand_URL="$URL/vivo_cn.md" ;;
        vivo_en) Brand_URL="$URL/vivo_global_en.md" ;;
        oppo) Brand_URL="$URL/oppo_cn.md" ;;
        oppo_en) Brand_URL="$URL/oppo_global_en.md" ;;
        esac
        if [[ ! -e $tools_path/Device_List ]]; then
            down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/'>"$tools_path/Device_List"
        else
            down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read -r; do
                unset model
                model="$(echo "$REPLY" | awk -F'"' '{print $2}')"
                if [[ $(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') != $model ]]; then
                    echo "$REPLY">>"$tools_path/Device_List"
                else
                    echo "$(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') = $model"
                fi
            done
        fi
    done
    if [[ -e $tools_path/Device_List ]]; then
        if [[ $(ls -l "$tools_path/Device_List" | awk '{print $5}') -gt 1 ]]; then
    		[[ $shell_language = zh-TW ]] && ts <"$tools_path/Device_List">temp && cp temp "$tools_path/Device_List" && rm temp
            echoRgb "已下載機型列表在$tools_path/Device_List"
        else
            echoRgb "下載機型失敗"
        fi
    else
        echoRgb "下載機型失敗"
    fi
}
# 主選單「備份WiFi」入口
# 建立備份目錄結構 + 複製 tools/ + 生成 start.sh + 備份 wifi.json
wifi() {
    backup_path
    [[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
    backup_wifi "$Backup/wifi"
    [[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
}
if [[ $0 = *backup.sh ]]; then
    start=backup
elif [[ $0 = *upload.sh ]]; then
    # upload.sh 位於 Backup_zstd_X/<app>/upload.sh
    # MODDIR 已被入口腳本設成 Backup_zstd_X
    # 取得 app 名 = upload.sh 所在的資料夾名
    _upload_app="${0%/*}"
    _upload_app="${_upload_app##*/}"
    start="single_upload \"$_upload_app\""
else
    [[ $0 = *recover.sh ]] && start=Restore
fi
if [[ $start != "" ]]; then
    case $(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}') in
    0)
        eval "$start" ;;
    1)
        {
        eval "$start"
        } & ;;
    esac
else
    if [[ -f $MODDIR/backup_settings.conf ]]; then
        steps=(
            "生成應用列表"
            "備份應用"
            "備份已更新應用"
            "備份自定義資料夾"
            "備份WiFi"
            "測試遠端連線"
            "單獨上傳當前備份"
            "列出遠端備份(產生 appList_network.txt)"
            "從遠端下載備份"
            "殺死運行中腳本"
        )
        commands=(
            "Getlist"
            "backup"
            "backup_update_apk"
            "backup_media"
            "wifi"
            "remote_test"
            "upload_current_backup"
            "remote_list_backups"
            "remote_download_backup"
            "echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
        )
    elif [[ -f $MODDIR/restore_settings.conf ]]; then
        steps=(
            "重新生成應用列表"
            "恢復備份"
            "僅恢復包含ssaid應用(含數據)"
            "僅恢復包含ssaid應用(不含數據)"
            "恢復自定義資料夾"
            "恢復wifi"
            "壓縮檔完整性檢查"
            "轉換文件夾名稱"
            "殺死運行中腳本"
        )
        commands=(
            "dumpname"        
            "Restore"
            "ssaid_mode=true && Restore"
            "ssaid_mode_1=true && Restore4"
            "Restore3"
            "recover_wifi \"$MODDIR/wifi\""
            "check_file"
            "convert"
            "echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
        )
    fi
    echoRgb "請選擇要執行的操作："
    for i in "${!steps[@]}"; do
        printf "%d) %s\n" "$((i+1))" "${steps[$i]}"
    done
    echo "x) 離開腳本"
    echo -n "請輸入選項編號: "
    read choice
    case $choice in
    x|X)
        echoRgb "已退出腳本" "0"
        exit 0 ;;
    [0-9]*)
        if (( choice >= 1 && choice <= ${#steps[@]} )); then
            index="$((choice - 1))"
            echo "執行：${steps[$index]}"
            background="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
            if [[ "$background" = "1" ]]; then
                eval "${commands[$index]}" &
            else
                eval "${commands[$index]}"
            fi
        else
            echoRgb "超出功能選項範圍（1-${#steps[@]}）" "0"
        fi
        ;;
    *)
        echoRgb "輸入錯誤，請重新輸入有效的數字或輸入 x 離開。" "0" ;;
    esac
fi
