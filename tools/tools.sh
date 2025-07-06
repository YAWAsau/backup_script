#!/system/bin/sh
if [ "$(whoami)" != root ]; then
	echo "你是憨批？不給Root用你媽 爬"
	exit 1
fi
[[ -d /data/cache ]] && set -x 2> /data/cache/debug_output.log
shell_language="zh-TW"
MODDIR="$MODDIR"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
script="${0##*/}"
backup_version="202504261629"
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
update_backup_settings_conf() {
    echo "#0關閉音量鍵選擇 (如選項未設置，則強制使用音量鍵選擇)
#1開啟音量鍵選擇 (如選項已設置，則跳過該選項提示)
#2使用鍵盤輸入，適用於無音量鍵可用設備選擇 (如選項未設置，則強制使用鍵盤輸入)
Lo="${Lo:-0}"

#後台執行腳本
0不能關閉當前終端，有壓縮速率
1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
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

#執行start.sh時輸出用於recovery救援的卡刷包？
#1輸出 0不輸出
recovery_flash="${recovery_flash:-0}"

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
0不能關閉當前終端，有壓縮速率
1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
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

#恢復Magisk模塊
modules_recovery="${modules_recovery:-0}"

#恢復資料夾
media_recovery="${media_recovery:-0}"

#存在進程忽略恢復(1忽略0恢復)
Background_apps_ignore="${Background_apps_ignore:-0}"

#使用者(如0 999等用戶，留空如存在多個用戶強制音量鍵選擇，無多用戶則默認0不詢問)
user=

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
if [[ ! -f $conf_path ]]; then
    if [[ $conf_path != *restore_settings.conf && $conf_path = *backup_settings.conf ]]; then
        update_backup_settings_conf>"$conf_path"
        echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
    else
        if [[ $conf_path = *restore_settings.conf && $conf_path != *backup_settings.conf ]]; then
            update_Restore_settings_conf>"$conf_path"
            echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
        else
            echo "$conf_path配置遺失" && exit 1
        fi
    fi
fi
[[ ! -f $conf_path ]] && echo "$conf_path遺失" && exit 2
. "$conf_path" &>/dev/null
if [[ $conf_path != *restore_settings.conf && $conf_path = *backup_settings.conf ]]; then
    update_backup_settings_conf>"$conf_path"
else
    if [[ $conf_path = *restore_settings.conf && $conf_path != *backup_settings.conf ]]; then
        update_Restore_settings_conf>"$conf_path"
    else
        echo "$conf_path配置遺失" && exit 1
    fi
fi
LANG="${LANG:="$(getprop "persist.sys.locale")"}"
echoRgb() {
	#轉換echo顏色提高可讀性
	if [[ $2 = 0 ]]; then
		echo -e "\e[38;5;197m -$1\e[0m"
	elif [[ $2 = 1 ]]; then
		echo -e "\e[38;5;121m -$1\e[0m"
	elif [[ $2 = 2 ]]; then
		echo -e "\e[38;5;${rgb_c}m -$1\e[0m"
	elif [[ $2 = 3 ]]; then
		echo -e "\e[38;5;${rgb_b}m -$1\e[0m"
	else
		echo -e "\e[38;5;${rgb_a}m -$1\e[0m"
	fi
}
rgb_a="${rgb_a:=214}"
abi="$(getprop ro.product.cpu.abi)"
case $abi in
arm64*)
	if [[ $(getprop ro.build.version.sdk) -lt 24 ]]; then
		echoRgb "設備Android $(getprop ro.build.version.release)版本過低 請升級至Android 8+" "0"
		exit 1
	else
		case $(getprop ro.build.version.sdk) in
		26|27|28)
			echoRgb "設備Android $(getprop ro.build.version.release)版本偏低，無法確定腳本能正確的使用" "0"
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
PATH="/data/adb/ksu/bin:/sbin/.magisk/busybox:/sbin/.magisk:/sbin:/data/adb/ksu/bin:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
if [[ -d $(magisk --path 2>/dev/null) ]]; then
	PATH="$(magisk --path 2>/dev/null)/.magisk/busybox:$PATH"
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
update-binary
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
find "$tools_path" -maxdepth 1 ! -path "$tools_path/tools.sh" -type f | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read; do
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
	"$busybox" --list | while read; do
		if [[ $REPLY != tar && $REPLY != bc && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
fi
[[ ! -f $filepath/zstd ]] && echoRgb "$filepath缺少zstd" && exit 2
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
export CLASSPATH="$tools_path/classes.dex"
quit=0
while read -r file expected_hash; do
  if [[ -f $tools_path/$file ]]; then
    computed_hash="$(sha256sum "$tools_path/$file" | awk '{print $1}')"
    if [[ $computed_hash = $expected_hash ]]; then
      echoRgb "✅ $file: 驗證通過"
    else
      echoRgb "❌ $tools_path/$file: SHA-256 不一致"
      quit=2
      break
    fi
  else
    echoRgb "⚠️ 檔案 $tools_path/$file 不存在"
    quit=1
    break
  fi
done <<< "$(cat <<EOF
zstd ab32aecb389c3ba5c1f7ab05d5eb6a861bad80261fd14ef9a8f4c283ac48c22c
tar 3c605b1e9eb8283555225dcad4a3bf1777ae39c5f19a2c8b8943140fd7555814
classes.dex 3d9372ac4a922808974bed039ca152d5741215976bedb20653e6e65e4bdcb37f
bc b15d730591f6fb52af59284b87d939c5bea204f944405a3518224d8df788dc15
busybox 4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651
find 7fa812e58aafa29679cf8b50fc617ecf9fec2cfb2e06ea491e0a2d6bf79b903b
jq 4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5
keycheck 50645ee0e0d2a7d64fb4a1286446df7a4445f3d11aefd49eeeb88515b314c363
cmd 08da8ac23b6e99788fd3ce6c19c7b5a083b2ad48be35963a48d01d6ee7f3bb6d
zip d9015b3c5d3376a4f9f2d204afd2aeaa4a86fd0174da1be090e41622e73be0ec
EOF)"
if [[ $background_execution = 1 || $setDisplayPowerMode = 1 ]]; then
    alias notification="app_process /system/bin com.xayah.dex.NotificationUtil notify -t 'SpeedBackup' "$@""
else
    alias notification="&>/dev/null"
fi
if [[ $quit -ne 0 ]]; then
  exit "$quit"
fi
sleep 1 && clear
TMPDIR="/data/local/tmp"
if [[ ! -e $TMPDIR/scriptTMP ]]; then
    rm -rf "$TMPDIR"/*
fi
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
chmod 771 "$TMPDIR"
chown '2000:2000' "$TMPDIR"
if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
if [[ $(which toybox | egrep -o "system") != system ]]; then
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
Set_back_0() {
	return 0
}
Set_back_1() {
	return 1
}
endtime() {
	#計算總體切換時長耗費
	case $1 in
	1) starttime="$starttime1" ;;
	2) starttime="$starttime2" ;;
	esac
	endtime="$(date -u "+%s")"
	duration="$(echo $((endtime - starttime)) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')"
	[[ $duration != "" ]] && echo " -$2用時:$duration" || echo " -$2用時:0秒"
}
nskg=1
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
isBoolean() {
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
echo_log() {
	if [[ $? = 0 ]]; then
		echoRgb "$1成功" "1"
		result=0
		Set_back_0
	else
		echoRgb "$1失敗，過世了" "0"
		notification "$RANDOM" "$name1: $1失敗，過世"
		result=1
		Set_back_1
	fi
}
process_name() {
	pgrep -f "$1" | while read; do
		kill -KILL "$REPLY" 2>/dev/null
	done
}
kill_Serve() {
	if [[ -f $TMPDIR/scriptTMP ]]; then
		scriptname="$(cat "$TMPDIR/scriptTMP")"
		echoRgb "腳本殘留進程，將殺死後退出腳本，請重新執行一次\n -殺死$scriptname" "0"
		rm -rf "$TMPDIR/scriptTMP"
		process_name "$scriptname"
		exit
	fi
	wait
}
Show_boottime() {
	awk -F '.' '{run_days=$1 / 86400;run_hour=($1 % 86400)/3600;run_minute=($1 % 3600)/60;run_second=$1 % 60;printf("%d天%d時%d分%d秒",run_days,run_hour,run_minute,run_second)}' /proc/uptime 2>/dev/null
}
[[ -f /sys/block/sda/size ]] && ROM_TYPE="UFS" || ROM_TYPE="eMMC"
if [[ -f /proc/scsi/scsi ]]; then
	UFS_MODEL="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $2,$4}')"
else
	if [[ $(cat "/sys/class/block/sda/device/inquiry" 2>/dev/null) != "" ]]; then
		UFS_MODEL="$(cat "/sys/class/block/sda/device/inquiry")"
	else
		UFS_MODEL="unknown"
	fi
fi
[[ $(egrep -w "$(getprop ro.product.model 2>/dev/null)" "$tools_path/Device_List" | awk -F'"' '{print $4}') != "" ]] && Device_name="$(egrep -w "$(getprop ro.product.model 2>/dev/null)" "$tools_path/Device_List" | awk -F'"' '{print $4}' | head -1)" || Device_name="$(getprop ro.product.model 2>/dev/null)"
if [[ $(su -v 2>/dev/null) != "" ]]; then
    Manager_version="$(su -v 2>/dev/null)"
    [[ $Manager_version = *KernelSU* ]] && ksu="ksu"
    [[ $ksu = "" ]] && [[ -d /data/adb/ksu ]] && ksu="ksu"
else
    if [[ -d /data/adb/ksu ]]; then
        Manager_version=KernelSU
        ksu="ksu"
    fi
fi
Socname="$(getprop ro.soc.model)"
if [[ $Socname != "" ]]; then
    if [[ -f $tools_path/soc.json ]]; then
        jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' "$tools_path/soc.json" &>/dev/null
        if [[ $? = 0 ]]; then
          DEVICE_NAME="$(jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' "$tools_path/soc.json" 2>/dev/null)"
          jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' "$tools_path/soc.json" &>/dev/null
          if [[ $? = 0 ]]; then
            RAMINFO="$(jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' "$tools_path/soc.json" 2>/dev/null)"
          else
            RAMINFO="RAM:null"
          fi
        else
            DEVICE_NAME="處理器:null"
            RAMINFO="RAM:null"
        fi
    else
        DEVICE_NAME="處理器:null"
        RAMINFO="RAM:null"
    fi
else
    DEVICE_NAME="處理器:null"
    RAMINFO="RAM:null"
fi
echoRgb "---------------------SpeedBackup---------------------"
echoRgb "腳本路徑:$MODDIR\n -已開機:$(Show_boottime)\n -執行時間:$(date +"%Y-%m-%d %H:%M:%S")\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -腳本版本:$backup_version\n -管理器:$Manager_version\n -品牌:$(getprop ro.product.brand 2>/dev/null)\n -型號:$Device_name($(getprop ro.product.device 2>/dev/null))\n -閃存顆粒:$UFS_MODEL($ROM_TYPE)\n -$DEVICE_NAME\n -$RAMINFO\n -Android版本:$(getprop ro.build.version.release 2>/dev/null) SDK:$(getprop ro.build.version.sdk 2>/dev/null)\n -內核:$(uname -r)\n -Selinux狀態:$([[ $(getenforce) = Permissive ]] && echo "寬容" || echo "嚴格")\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
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
    echoRgb "系統語言環境:繁體中文"
	Script_target_language="zh-TW" ;;
*CN* | *cn*)
    echoRgb "系統語言環境:簡體中文"
	Script_target_language="zh-CN" ;;
esac
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
add_entry() {
    app_name="$1"
    package_name="$2"
    # 檢查是否已經存在同樣的應用名稱
    if [[ $(echo "$3" | awk '{print $1}' | grep -w "^$app_name$") = $app_name ]]; then
        if [[ $(echo "$3" | awk '{print $2}' | grep -w "^$package_name$") != $package_name ]]; then
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
		    echo "$user_id" | while read ; do
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
		    echo "$user_id" | while read ; do
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
Rename_script () {
    HT="${HT:=0}"
	find "$path_hierarchy" -maxdepth 3 -name "*.sh" -type f -not -name "tools.sh" | sort | while read ; do
        MODDIR_NAME="${REPLY%/*}"
        FILE_NAME="${REPLY##*/}"
        if [[ -f ${REPLY%/*}/app_details.json || -f ${REPLY%/*}/app_details ]]; then
            if [[ $FILE_NAME = backup.sh ]]; then
                touch_shell "1" "$REPLY"
            else
                touch_shell "3" "$REPLY"
            fi
        else
            [[ -d ${REPLY%/*}/tools ]] && touch_shell "0" "$REPLY"
            let HT++
        fi
	done
	unset HT
}
touch_shell () {
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
    esac
    [[ $Output_path = "" ]] && echo "#!/system/bin/sh
if [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then
    MODDIR=\"$MODDIR_Path1\"
    conf_path=\"$conf_path\"
    [ ! -f \"$conf_path\" ] && . \"$MODDIR_Path/tools/tools.sh\"
else
    echo \"$MODDIR_Path/tools/tools.sh遺失\"
fi
. \"$MODDIR_Path/tools/tools.sh\" | tee \"\${0%/*}/log.txt\""> "$2"
}
update_script() {
	[[ $zipFile = "" ]] && zipFile="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)"
	if [[ $zipFile != "" ]]; then
		case $(echo "$zipFile" | wc -l) in
		1)
			if [[ $(unzip -l "$zipFile" | awk '{print $4}' | egrep -o "^backup_settings.conf$") != "" ]]; then
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
                                if [[ -d $find_tools_path && $find_tools_path != $path_hierarchy/tools ]]; then
                                    rm -rf "$find_tools_path"
                                    cp -r "$path_hierarchy/tools" "${find_tools_path%/*}"
                                    update_Restore_settings_conf>"${find_tools_path%/*}/restore_settings.conf"
                                    ts <"${find_tools_path%/*}/restore_settings.conf">temp && cp temp "${find_tools_path%/*}/restore_settings.conf" && rm temp
                                    echo_log "${find_tools_path%/*}/restore_settings.conf翻譯"
							    fi
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
if [[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | egrep -wo "^backup_settings.conf$") != "" ]]; then
    update_script
else
    zipFile="$(ls -t /storage/emulated/0/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv/*.zip 2>/dev/null | head -1)"
    [[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | egrep -wo "^backup_settings.conf$") != "" ]] && update_script
fi
if [[ $(getprop ro.build.version.sdk) -lt 30 ]]; then
	alias INSTALL="pm install --user $user -r -t &>/dev/null"
	alias create="pm install-create --user $user -t 2>/dev/null"
else
    if [[ $(getprop ro.build.version.sdk) -gt 33 ]]; then
	    alias INSTALL="pm install -r --bypass-low-target-sdk-block -i com.android.vending --user $user -t &>/dev/null"
        alias create="pm install-create -i com.android.vending --bypass-low-target-sdk-block --user $user -t 2>/dev/null"
    else
        alias INSTALL="pm install -r -i com.android.vending --user $user -t &>/dev/null"
        alias create="pm install-create -i com.android.vending --user $user -t 2>/dev/null"
    fi
fi
#settings get system system_locales
Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
if [[ $path_hierarchy != "" && $Script_target_language != ""  ]]; then
	K=1
	J="$(find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | wc -l)"
	find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | while read ; do
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
    [[ -e $TMPDIR/0 ]] && rm -rf "$TMPDIR/0" && echoRgb "轉換腳本完成，退出腳本重新執行即可使用" && exit 2
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
    json="$(down "$Language" 2>/dev/null)"
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
				    echoRgb "$(ts "更新日誌:\n$(down "$Language" | jq -r '.body' 2>/dev/null)")"
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
	PU=$(mount | awk '$3 ~ "/mnt/media_rw/[^/]+$" {print $3, $5}' | egrep -v "$mount_point")
	OTGPATH="$(echo "$PU" | awk '{print $1}')"
	OTGFormat="$(echo "$PU" | awk '{print $2}')"
	if [[ -d $OTGPATH ]]; then
		if [[ $(echo "$MODDIR" | egrep -o "^${OTGPATH}") != "" ]]; then
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
	if [[ $(echo "$Backup" | egrep -o "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
}
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(find "$1" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
    if [[ $(echo "$filesizee > $filesize" | bc) -eq 1 ]]; then
        NJL="本次備份增加 $(size "$(echo "scale=2; $filesizee - $filesize" | bc)")"
    elif [[ $(echo "$filesizee < $filesize" | bc) -eq 1 ]]; then
        NJL="本次備份減少 $(size "$(echo "scale=2; $filesize - $filesizee" | bc)")"
    else
        NJL="文件大小未改變"
    fi
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(size "$filesizee")"
	echoRgb "$NJL"
}
size() {
    local b_size get_size
    varr="$(echo "$1" | bc 2>/dev/null)"
    if [[ $varr != $1 ]]; then
        b_size="$(ls -l "$1" 2>/dev/null | awk '{print $5}')"
    else
        b_size="$1"
    fi
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
	[[ $Filesize != "" ]] && [[ $(echo "$Filesize > $Occupation_status" | bc) -eq 1 ]] && echoRgb "$2備份大小將超出rom可用大小" "0" && Skip=1
	Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
kill_app() {
    if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
        if [[ $(dumpsys activity processes | grep "packageList" | cut -d '{' -f2 | cut -d '}' -f1 | egrep -w "^$name2$" | sed -n '1p') = $name2 ]]; then
            pkill -9 -f "$name2$|$name2[:/_]"
            killall -9 "$name2" &>/dev/null
            am force-stop --user "$user" "$name2" &>/dev/null
            am kill "$name2" &>/dev/null
            echoRgb "殺死$name1進程"
        fi
	fi
}
Backup_apk() {
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
	apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
	apk_version2="$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
	if [[ $apk_version = $apk_version2 ]]; then
		[[ $(sed -e '/^$/d' "$txt2" | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
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
    			echo "$apk_path" | sed -e '/^$/d' | while read; do
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
    					[[ $(sed -e '/^$/d' "$txt2" 2>/dev/null | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
                        [[ $apk_version != "" ]] && {
                        echoRgb "覆蓋app_details"
                        jq --arg apk_version "$apk_version2" --arg software "$name1" '.[$software].apk_version = $apk_version' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
                        } || {
                        echoRgb "新增app_details"
                        extra_content="{
                          \"$name1\": {
                            \"PackageName\": \"$name2\",
                            \"apk_version\": \"$apk_version2\"
                          }
                        }"
                        jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
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
    						rm -rf "${OldFile%/*/*}" && echoRgb "刪除文件:${OldFile%/*/*}"
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
Backup_ssaid() {
    Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
    ssaid="$(get_ssaid "$name2")"
    [[ $ssaid != null ]] && echoRgb "SSAID:$ssaid"
    if [[ $ssaid != null && $ssaid != $Ssaid ]]; then
        echoRgb "$Ssaid>$ssaid"
    	SSAID_apk="$(echo "$name1 \"$name2\"")"
        SSAID_apk2="$(echo "$SSAID_apk\n$SSAID_apk2")"
    	jq --arg entry "$name1" --arg new_value "$ssaid" '.[$entry].Ssaid |= $new_value' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
    	echo_log "備份ssaid"
    fi
    [[ $ssaid = null ]] && ssaid=
}
Backup_Permissions() {
    get_Permissions="$(jq -r '.[] | select(.permissions != null).permissions' "$app_details")"
    Get_Permissions="$(get_Permissions "$name2" | jq -nR '[inputs | select(length>0) | split(" ") | {(.[0]): (.[1:] | join(" "))}] | add')"
    if [[ $Get_Permissions != "" && ($Get_Permissions = *true* || $Get_Permissions = *false*) ]]; then
        if [[ $get_Permissions = "" ]]; then
            jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName].permissions |= $permissions' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
        	echo_log "備份權限"
        else
            if [[ $get_Permissions != "" && ($get_Permissions == *true* || $get_Permissions == *false*) ]]; then
        	    [[ $get_Permissions != $Get_Permissions ]] && jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName] |= . + {permissions: $permissions}' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json && echo_log "備份權限" "備份"
        	fi
        fi
    else
        echoRgb "備份權限失敗$(get_Permissions "$name2")" "0"
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
		if [[ $1 != storage-isolation && $1 != thanox && $1 != NoActive ]]; then
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
                if [[ $(su "$(get_uid "$name2" 2>/dev/null)" -c keystore_cli_v2 list | wc -l) -ge 2 ]]; then
                    echoRgb "$name1包含keystore 恢復可能閃退" "0"
                    jq --arg entry "$name1" '.[$entry].keystore |= "true"' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
                else
                    jq --arg entry "$name1" '.[$entry].keystore |= "false"' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
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
                [[ $Start_backup = true ]] && {
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
    			} || {
    			echoRgb "$1數據 $Filesize2太小" "0" && result=1
    			}
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
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
    					else
    					    extra_content="{
                              \"$1\": {
                                \"Size\": \"$Filesize\"
                              },
                              \"Backup time\": {
                                \"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
                              }
                            }"
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
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
		NoActive) FILE_PATH="/data/system" && find "/data/system" -name "NoActive_"* -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
		storage-isolation) FILE_PATH="/data/adb" ;;
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
			    G="$(get_uid "$name2" 2>/dev/null)"
			    if [[ $G = "" ]]; then
				    G="$(dumpsys package "$name2" 2>/dev/null | awk -F'uid=' '{print $2}' | egrep -o '[0-9]+' | head -n 1)"
				    [[ $(echo "$G" | egrep -o '[0-9]+') = "" ]] && G="$(pm list packages -U --user "$user" | egrep -w "$name2" | awk -F'uid:' '{print $2}' | awk '{print $1}' | head -n 1)"
				fi
                G="$(echo "$G" | egrep -o '[0-9]+')"
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
						        echo_log "selinux上下文設置"
						    else
						        echoRgb "路徑:$X出現錯誤"
						    fi ;;
						data|obb)
                            chown -hR "$uid" "$FILE_PATH/$name2/"
                            chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>/dev/null ;;
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
		    NoActive)
				restorecon -RF "$(find "/data/system" -name "NoActive_"* -maxdepth 1 -type d 2>/dev/null)/" 2>/dev/null
				echo_log "selinux上下文設置"
				;;
			storage-isolation)
				restorecon -RF "/data/adb/storage-isolation/" 2>/dev/null
				echo_log "selinux上下文設置"
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
			b="$(create 2>/dev/null | egrep -o '[0-9]+')"
			if [[ -f $TMPDIR/nmsl.apk ]]; then
				INSTALL "$TMPDIR/nmsl.apk"
				echo_log "nmsl.apk安裝"
			fi
			apks=($(find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f | grep -v 'nmsl.apk'))
            for apk in "${apks[@]}"; do
                pm install-write "$b" "${apk##*/}" "$apk" &>/dev/null
                echo_log "${apk##*/}安裝"
            done
			pm install-commit "$b" &>/dev/null
			echo_log "split Apk安裝"
			;;
		esac
	fi
}
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
get_name(){
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	txt2="$MODDIR/mediaList.txt"
	txt3="$MODDIR/temp.txt"
	if [[ $1 = Apkname ]]; then
		rm -rf "$txt" "$txt2"
		echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	fi
	rgb_a=118
	user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')"
	[[ ! -f $txt3 ]] && {
	Apk_info="$(pm list packages -u --user "$user" | cut -f2 -d ':' | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	starttime1="$(date -u "+%s")"
	i=1
	find "$MODDIR" -maxdepth 2 -name "apk.*" -type f 2>/dev/null | sort | while read; do
		Folder="${REPLY%/*}"
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		unset PackageName NAME DUMPAPK ChineseName apk_version Ssaid dataSize userSize obbSize
		if [[ -f $Folder/app_details.json ]]; then
		    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$Folder/app_details.json" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$Folder/app_details.json")"
		    if [[ -f $Folder/Permissions ]]; then
		        unset Permissions
		        . "$Folder/Permissions"
		        jq --arg packageName "$ChineseName" --argjson permissions "$(echo "$Permissions" | jq -nR '[inputs | select(length>0) | split(" ") | {(.[0]): .[-1]}] | add')" '.[$packageName] |= . + {permissions: $permissions}' "$Folder/app_details.json" > temp.json && cp temp.json "$Folder/app_details.json" && rm -rf "$Folder/Permissions" temp.json && echoRgb "更新$Folder/app_details.json"
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
                jq --argjson new_content "$extra_content" '. += $new_content' "$Folder/app_details.json" > temp.json && cp temp.json "$Folder/app_details.json" && rm -rf temp.json "$Folder/app_details"
            fi
		fi
		[[ ! -f $txt ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market" >"$txt"
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
		    if [[ $(echo "$Apk_info" | egrep -o "$PackageName") = "" ]]; then
		        echoRgb "$ChineseName已經不存在$user使用者中"
    	        echo "$ChineseName $PackageName">>"$txt3"
    		fi
			case $1 in
			Apkname)
			    [[ -f $Folder/${PackageName}.sh ]] && rm -rf "$Folder/${PackageName}.sh"
		        [[ ! -f $Folder/recover.sh ]] && touch_shell "3" "$Folder/recover.sh"
			    [[ ! -f $Folder/backup.sh ]] && touch_shell "1" "$Folder/backup.sh"
				echoRgb "$i:$ChineseName $PackageName" && echo "$ChineseName $PackageName" >>"$txt"
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
	done
	if [[ -d $MODDIR/Media ]]; then
		echoRgb "存在媒體資料夾" "2"
		[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$txt2"
		find "$MODDIR/Media" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | while read; do
			echoRgb "${REPLY##*/}" && echo "${REPLY##*/}" >> "$txt2"
		done
		echoRgb "$txt2重新生成" "1"
	fi
	}
	if [[ -f $txt3 ]]; then
	    if [[ $(egrep -v '#|＃' "$txt3" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
	        echoRgb "列出需要刪除的應用中....\n -$(cat "$txt3")"
	        case $Lo in
	        0|1)
	            echoRgb "確認列表無誤後音量上刪除，音量下退出腳本編輯列表" "2"
		        get_version "刪除" "退出腳本" && Delete_App="$branch" ;;
		    2)
		        Enter_options "確認列表無誤後輸入1刪除，輸入0退出腳本編輯列表" "刪除" "退出腳本" && isBoolean "$parameter" "Delete_App" && Delete_App="$nsx" ;;
		    esac
		    if [[ $Delete_App = true ]]; then
		        i=1
		        r="$(egrep -v '#|＃' "$txt3" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
		        while [[ $i -le $r ]]; do
		            name1="$(egrep -v '#|＃' "$txt3" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
    		        name2="$(egrep -v '#|＃' "$txt3" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
    		        Backup_folder="$MODDIR/$name1"
    		        [[ -d $Backup_folder ]] && rm -rf "$Backup_folder"
    		        echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$txt" 2>/dev/null)" >"$txt"
    		        let i++
    		    done
    		    rm -rf "$txt3"
    		else
    		    rm -rf "$txt3"
    		    exit 0
    	    fi
    	else
    	    rm -rf "$txt3"
    	fi
    fi
    endtime 1
	exit 0
}
self_test() {
	if [[ $(dumpsys deviceidle get charging) = false && $(dumpsys battery | awk '/level/{print $2}' | egrep -o '[0-9]+') -le 15 ]]; then
		echoRgb "電量$(dumpsys battery | awk '/level/{print $2}' | egrep -o '[0-9]+')%太低且未充電\n -為防止備份檔案或是恢復因低電量強制關機導致檔案損毀\n -請連接充電器後備份" "0" && exit 2
	fi
}
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
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>/dev/null | sort)"
	i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | wc -l)"
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort | while read; do
		REPLY="${REPLY%/*}"
		echoRgb "校驗第$i/$r個資料夾 剩下$((r - i))個" "3"
		echoRgb "校驗:${REPLY##*/}"
		find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | sort | while read; do
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
Background_application_list() {
    if [[ $Background_apps_ignore = true ]]; then
        unset Backstage apk_path3
	    #獲取後台
	    if [[ $(dumpsys activity activities | awk -F 'packageName=' '/packageName=/{split($2, a, " "); print a[1]}' | sort | uniq) != "" ]]; then
		    apk_path3="$(echo "$(pm path --user "$user" "$(dumpsys activity activities | awk -F 'packageName=' '/packageName=/{split($2, a, " "); print a[1]}' | sort | uniq | head -1)" 2>/dev/null | cut -f2 -d ':')" | head -1)"
            if [[ -d ${apk_path3%/*} ]]; then
                Backstage="$(dumpsys activity activities | awk -F 'packageName=' '/packageName=/{split($2, a, " "); print a[1]}' | sort | uniq)"
            else
                if [[ $(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}') != "" ]]; then
		            apk_path3="$(echo "$(pm path --user "$user" "$(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}' | head -1)" 2>/dev/null | cut -f2 -d ':')" | head -1)"
                    [[ -d ${apk_path3%/*} ]] && Backstage="$(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}')"
                fi
            fi
        else
            if [[ $(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}') != "" ]]; then
		        apk_path3="$(echo "$(pm path --user "$user" "$(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}' | head -1)" 2>/dev/null | cut -f2 -d ':')" | head -1)"
                [[ -d ${apk_path3%/*} ]] && Backstage="$(am stack list | awk '/taskId/&&!/unknown/{split($2, a, "/"); print a[1]}')"
            fi
        fi
        [[ ! -d ${apk_path3%/*} ]] && {
        echoRgb "獲取當前後台應用失敗" "0" && unset Backstage
        }
    fi
}
backup() {
	kill_Serve
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
		    if [[ $(echo "$blacklist" | egrep -v '#|＃' | wc -l) -gt 0 ]]; then
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
		    if [[ $(echo "$blacklist" | egrep -v '#|＃' | wc -l) -gt 0 ]]; then
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
		    [[ $(echo "$blacklist" | egrep -v '#|＃' | wc -l) -gt 0 ]] && {
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
	Apk_info="$(pm list packages -u --user "$user" | cut -f2 -d ':' | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	[[ ! -f ${0%/*}/app_details.json ]] && {
	echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
	i1=1
	r1="$(cat "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	while read -r ; do
	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
            app=($REPLY $REPLY)
    		if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	            if [[ $(echo "$Apk_info" | egrep -o "${app[1]}") != "" ]]; then
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
	apks=($(cat "$txt" | grep -Ev '^[#＃!]' | awk '{print $1 ":" $2}'))
    [[ $Update_backup = true ]] && {
    echoRgb "檢查備份列表中已經更新應用" "3"
    for apk in "${apks[@]}"; do
        Backup_folder="$Backup/$(echo "$apk" | cut -d':' -f1)"
        app_details="$Backup_folder/app_details.json"
        if [[ -d $Backup_folder ]]; then
            apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
            apk_version2="$(pm list packages --show-versioncode --user "$user" "$(echo "$apk" | cut -d':' -f2)" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
            [[ $apk_version != $apk_version2 ]] && {
            [[ $Tmplist2 = "" ]] && Tmplist2="${apk/:/ }" || Tmplist2="$Tmplist2\n${apk/:/ }"
            }
        fi
    done
    }
    [[ $Tmplist != ""  ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
	if [[ $Tmplist2 != "" ]]; then
	    if [[ $Update_backup != "" ]]; then
    	    cat "$txt">"${txt%/*}/txt2"
    	    echo "$Tmplist2" | sed -e '/^$/d' | sort>"$txt"
    	fi
    else
        [[ $Update_backup != "" ]] && echoRgb "應用目前無更新" "0" && exit 0
    fi
	r="$(egrep -v '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	[[ -f ${0%/*}/app_details.json ]] && r=1
	[[ $r = "" && ! -f ${0%/*}/app_details.json ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/start.sh" "0" && exit 1
	if [[ $Backup_Mode = true ]]; then
    	[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
    	[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
    fi
	[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
	txt2="$Backup/appList.txt"
	txt2="${txt2/'/storage/emulated/'/'/data/media/'}"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -d $Backup/modules ]] && mkdir -p "$Backup/modules" && echoRgb "$Backup/modules已創建成功\n -請按需要自行放置需要恢復時刷入的模塊在內將自動批量刷入" "1"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	if [[ -d $Backup/tools ]]; then
	    find "$Backup/tools" -maxdepth 1 -type f | while read; do
	        Tools_FILE_NAME="${REPLY##*/}"
	        filesha256="$(sha256sum "$tools_path/$Tools_FILE_NAME" 2>/dev/null | cut -d" " -f1)"
	        filesha256_1="$(sha256sum "$REPLY" 2>/dev/null | cut -d" " -f1)"
	        if [[ $filesha256 != $filesha256_1 ]]; then
	            cp -r "$tools_path/$Tools_FILE_NAME" "$REPLY"
	            echoRgb "更新$REPLY"
	        fi
	    done
	fi
	filesize="$(find "$Backup" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
	Quantity=0
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	en=118
	echo "$script">"$TMPDIR/scriptTMP"
	osn=0; osj=0; osk=0
	#獲取已經開啟的無障礙
	var="$(settings get secure enabled_accessibility_services 2>/dev/null)"
	#獲取預設鍵盤
	keyboard="$(settings get secure default_input_method 2>/dev/null)"
    Set_screen_pause_seconds on
	[[ $(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
	{
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	notification "101" "開始備份"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ ! -f ${0%/*}/app_details.json ]]; then
    		name1="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
    		name2="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
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
			[[ $Backstage != "" && $(echo "$Backstage" | egrep -w "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略備份" "0" && nobackup="true"
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
				[[ $PackageName != $name2 ]] && jq --arg name2 "$name2" 'walk(if type == "object" and .PackageName then .PackageName = $name2 else . end)' "$app_details" > temp.json && cp temp.json "$app_details" && rm -rf temp.json
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
        				[[ $name2 = cn.myflv.noactive ]] && Backup_data "NoActive" "$(find "/data/system" -name "NoActive_"* -maxdepth 1 -type d 2>/dev/null)"
        				[[ $name2 = moe.shizuku.redirectstorage ]] && Backup_data "storage-isolation" "/data/adb/storage-isolation"
        		    fi
    			fi
    			[[ -f $Backup_folder/${name2}.sh ]] && rm -rf "$Backup_folder/${name2}.sh"
    		    [[ ! -f $Backup_folder/recover.sh ]] && touch_shell "3" "$Backup_folder/recover.sh"
    			[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "1" "$Backup_folder/backup.sh"
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
			sort "$txt2" | sed '/^$/d' >"${txt2}.tmp" && mv "${txt2}.tmp" "$txt2"
			[[ -e ${txt%/*}/txt2 ]] && cat "${txt%/*}/txt2">"$txt" && rm -rf "${txt%/*}/txt2"
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(echo "$Custom_path" | egrep -v '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
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
					echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read; do
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
					notification "102" "Media備份完成 $(endtime 1 "自定義備份")"
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		let i++ en++ nskg++
	done
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user"
	rm -rf "$TMPDIR/scriptTMP"
	Calculate_size "$Backup"
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	notification "105" "備份完成 $(endtime 1 "批量備份開始到結束")"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt2"
	} &
	wait && exit
}
backup_update_apk() {
    Update_backup='true'
    backup
}
dumpname() {
	get_name "Apkname"
}
convert() {
	get_name "convert"
}
check_file() {
	Check_archive "$MODDIR"
}
Restore() {
	kill_Serve
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
	    r="$(egrep -v '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	    [[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
    	Backup_folder2="$MODDIR/Media"
    	Backup_folder3="$MODDIR/modules"
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
        	Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | egrep -o '[0-9]+')"
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
        	if [[ -d $Backup_folder3 && $(find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | wc -l) != 0 ]]; then
        	    [[ $modules_recovery != "" ]] && isBoolean "$modules_recovery" "modules_recovery" && modules_recovery="$nsx" || {
        		echoRgb "是否刷入Magisk模塊\n -音量上刷入，音量下不刷入" "2"
        		get_version "刷入模塊" "跳過刷入模塊" && modules_recovery="$branch"
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
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | egrep -o '[0-9]+')"
    	    if [[ $Get_user != $user ]]; then
    	        echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
    		    get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
    	    fi
    	    echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
    	    get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
    	    echoRgb "是否刷入Magisk模塊\n -音量上刷入，音量下不刷入" "2"
    	    get_version "刷入模塊" "跳過刷入模塊" && modules_recovery="$branch"
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
		    isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx"
		    }
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | egrep -o '[0-9]+')"
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
    	    [[ $modules_recovery = "" ]] && {
    	    Enter_options "是否刷入Magisk模塊\n -輸入1刷入 0不刷入" "刷入模塊" "跳過刷入模塊" && isBoolean "$parameter" "modules_recovery" && modules_recovery="$nsx"
    	    } || {
    	    isBoolean "$modules_recovery" "modules_recovery" && modules_recovery="$nsx"
    	    }
    	    [[ $Background_apps_ignore = "" ]] && {
    	    Enter_options "存在進程忽略恢復\n -輸入1不恢復，0恢復" "忽略" "恢復" && isBoolean "$parameter" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } || {
    	    isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } ;;
		*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
		esac
    	[[ $recovery_mode2 = false ]] && exit 2
    	if [[ $recovery_mode = true ]]; then
    		echoRgb "獲取未安裝應用中"
    		Apk_info="$(pm list packages -u --user "$user" | cut -f2 -d ':' | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	if [[ $Apk_info != "" ]]; then
        	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	else
        	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	fi
        	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
    		while read -r ; do
                if [[ $(echo "$REPLY" | sed 's/^[ \t]*//') != \#* ]]; then
                    app=($REPLY $REPLY)
            		[[ ${app[1]} != "" && ${app[2]} != "" ]] && {
        	        [[ $(echo "$Apk_info" | egrep -o "${app[1]}") = "" ]] && Tmplist="$Tmplist\n$REPLY"
                    }
        		fi
        	done < "$txt"
    		r="$(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }')"
    		if [[ $r != "" ]]; then
    			echoRgb "獲取完成 預計安裝$r個應用"
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
	echo "$script">"$TMPDIR/scriptTMP"
	notification "105" "開始恢復app"
	{
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ ! -f ${0%/*}/app_details.json ]]; then
		    echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
		    notification "105" "恢復第$i/$r個應用 剩下$((r - i))個
恢復 $name1"
		    if [[ ! -f $txt ]]; then
		        [[ $(echo "$txt") != "" ]] && {
		        name1="$(echo "$txt" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
		        name2="$(echo "$txt" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
		        }
		    else
		        name1="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
		        name2="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
		    fi
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
		    [[ $Backstage != "" && $(echo "$Backstage" | egrep -w "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略恢復" "0" && restore="false"
			[[ $restore = true ]] && {
			starttime2="$(date -u "+%s")"
			if [[ $(pm path --user "$user" "$name2" 2>/dev/null) = "" ]]; then
				installapk
			else
		        [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]] && installapk && [[ $? = 0 ]] && echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
			fi
			if [[ $(pm path --user "$user" "$name2" 2>/dev/null) != "" ]]; then
				if [[ $No_backupdata = "" ]]; then
				    [[ $name2 != *mt* ]] && {
					kill_app
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read; do
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
		    echo "$SSAID_Package2" | while read; do
		        Ssaid="$(echo "$REPLY" | awk '{print $3}')"
		        name1="$(echo "$REPLY" | awk '{print $1}')"
		        name2="$(echo "$REPLY" | awk '{print $2}')"
			        set_ssaid "$name2" "$Ssaid"
			        if [[ $(get_ssaid "$name2") = $Ssaid ]]; then
			            echoRgb "$name1 SSAID恢復成功" "1"
			            SSAID_Package0="$(echo "$name1 \"$name2\"")"
		                SSAID_Package1="$(echo "$SSAID_Package0\n$SSAID_Package1")"
			        else
			            echoRgb "$name1 SSAID恢復失敗" "0"
			            SSAID_Package3="$(echo "$name1 \"$name2\"")"
		                SSAID_Package4="$(echo "$SSAID_Package3\n$SSAID_Package4")"
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
	            B="$(egrep -v '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
                [[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
                notification "106" "Media恢復開始"
				while [[ $A -le $B ]]; do
		            name1="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		            starttime2="$(date -u "+%s")"
		            echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		            Release_data "$Backup_folder2/$name1"
		            endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
                done
				endtime 1 "自定義恢復" "2"
				notification "106" "Media恢復完成 $(endtime 1 "Media恢復" "2")"
			fi
			if [[ $modules_recovery = true ]]; then
			    A=1
		        B="$(find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | wc -l)"
		        starttime1="$(date -u "+%s")"
		        notification "108" "Module恢復開始"
		        find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | while read; do
					starttime2="$(date -u "+%s")"
					echoRgb "刷入第$A/$B個模塊 剩下$((B - A))個" "3"
					echoRgb "刷入${REPLY##*/}" "2"
					[[ $ksu != ksu ]] && magisk --install-module "$REPLY" || ksud module install "$REPLY"
					endtime 2 "${REPLY##*/}刷入" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
				done
				endtime 1 "刷入模塊" "2"
				notification "108" "Module恢復完成 $(endtime 1 "Module恢復" "2")"
			fi
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
	} &
	wait && exit
}
Restore3() {
	kill_Serve
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
	B="$(egrep -v '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	Set_screen_pause_seconds on
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && exit 1
	echo "$script">"$TMPDIR/scriptTMP"
	notification "108" "Media恢復開始"
	{
	while [[ $A -le $B ]]; do
		name1="$(egrep -v '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	notification "108" "Media恢復完成 $(endtime 1 "Media恢復")"
	rm -rf "$TMPDIR/scriptTMP"
	} &
}
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
		}
		[[ $recovery_flash != "" ]] && isBoolean "$recovery_flash" "recovery_flash" && recovery_flash="$nsx" || {
		echoRgb "輸出用於recovery救援的卡刷包？\n -音量上輸出，音量下不輸出" "2"
		get_version "輸出" "不輸出" && recovery_flash="$branch"
		} ;;
	1)
		if [[ $(echo "$blacklist" | egrep -v '#|＃' | wc -l) -gt 0 ]]; then
		    [[ $blacklist_mode = "" ]] && {
		    echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
		    get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
		    } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		fi
	    [[ $recovery_flash = "" ]] && {
	    echoRgb "輸出用於recovery救援的卡刷包？\n -音量上輸出，音量下不輸出" "2"
	    get_version "輸出" "不輸出" && recovery_flash="$branch"
	    } || isBoolean "$recovery_flash" "recovery_flash" && recovery_flash="$nsx" ;;
	2)
	    [[ $blacklist_mode = "" ]] && {
	    Enter_options "選擇黑名單模式輸入1不輸出，輸入0輸出應用列表" "不輸出" "輸出應用列表" && isBoolean "$parameter" "blacklist_mode" && blacklist_mode="$nsx"
	    } || {
	    isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
	    }
	    [[ $recovery_flash = "" ]] && {
	    Enter_options "填寫1輸出用於recovery救援的卡刷包，填寫0不輸出" "輸出" "不輸出" && isBoolean "$parameter" "recovery_flash" && recovery_flash="$nsx"
	    } || {
	    isBoolean "$recovery_flash" "recovery_flash" && recovery_flash="$nsx"
	    } ;;
	*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
	esac
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	[[ ! -f $txt ]] && echo '#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）' >"$txt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	starttime1="$(date -u "+%s")"
	echoRgb "提示! 腳本默認會屏蔽預裝應用 如需備份請添加預裝應用白名單" "0"
	Apk_info="$(appinfo "system|user|xposed" "label|pkgName|flag" | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	xposed_name="$(echo "$Apk_info" | awk '$3 == "xposed" {print $2}')"
	TARGET_PACKAGES="$(echo "$system" | paste -sd'|' - | sed 's/^|//')"
    Pre_installed_apps="$(echo "$Apk_info" | awk '$3 == "system" {print $1, $2}' | egrep -w "$TARGET_PACKAGES")"
    Apk_info="$(echo "$(echo "$Apk_info" | awk '$3 != "system" {print $1, $2}')\n$Pre_installed_apps")"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	exit 2 ; } || Apk_info2="$(echo "$Apk_info" | awk '{print $2}')"
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	rb="0"
	Output_list() {
	    if [[ $(cat "$txt" | cut -f2 -d ' ' | egrep -w "^${app_1[1]}$") != ${app_1[1]} ]]; then
	        [[ $REPLY2 = "" ]] && add_entry "${app_1[2]}" "${app_1[1]}" "$(cat "$txt" | grep -w "${app_1[2]}")" || add_entry "${app_1[2]}" "${app_1[1]}" "$REPLY2"
	        case ${app_1[1]} in
			    *oneplus*|*miui*|*xiaomi*|*oppo*|*flyme*|*meizu*|com.android.soundrecorder|com.mfashiongallery.emag|com.mi.health|*coloros*|com.android.soundrecorder|com.duokan.phone.remotecontroller|com.android.calendar|com.android.deskclock|com.android.calendar|com.android.deskclock|com.google.android.safetycore|com.google.android.contactkeys|com.google.android.apps.messaging|com.google.android.calendar)
				    if [[ $(echo "$xposed_name" | egrep -w "${app_1[1]}$") = ${app_1[1]} ]]; then
    				    echoRgb "$((i+1)):$app_name為Xposed模塊 進行添加" "0"
					    if [[ $REPLY2 = "" ]]; then
					        REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    else
					        REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    fi
					    let i++ rd++
				    else
					    if [[ $(echo "$whitelist" | egrep -w "^${app_1[1]}$") = ${app_1[1]} ]]; then
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
					if [[ $(echo "$xposed_name" | egrep -w "${app_1[1]}$") = ${app_1[1]} ]]; then
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
    [[ $(echo "$blacklist" | egrep -v '#|＃') != "" ]] && NZK=1
	echo "$Apk_info" | sed 's/[\/:()\[\]\-!]//g' | while read; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_1=($REPLY $REPLY)
		if [[ $NZK = 1 ]]; then
    		if [[ $(echo "$blacklist" | egrep -w "^${app_1[1]}$") != ${app_1[1]} ]]; then
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
				echoRgb "\n -輸出異常 請將$conf_path中的debug_list=\"0\"改為1或是重新執行本腳本" "0"
				exit
			fi
			echoRgb "已經將預裝應用輸出至appList.txt並注釋# 需要備份則去掉#" "0"
			[[ $tmp != "" ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let rgb_a++ LR++
	done
	if [[ -f $txt ]]; then
	    rm -rf "$TMPDIR"/*
	    while read -r ; do
    	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
                app=($REPLY $REPLY)
    		    if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	                if [[ $(echo "$Apk_info2" | egrep -o "${app[1]}") != "" ]]; then
			            [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
    			        Tmplist="$Tmplist\n$REPLY"
    			        [[ $recovery_flash = true ]] && {
    			        apk_path="$(pm path --user "$user" "${app[1]}" 2>/dev/null | cut -f2 -d ':')"
                		apk_path2="$(echo "$apk_path" | head -1)"
                		apk_path2="${apk_path2%/*}"
    			        echo "${app[2]} ${app[1]} $apk_path2" >>"$TMPDIR/appList.txt"
    			        }
    			    else
                        echoRgb "$REPLY不存在系統，從列表中刪除" "0"
                    fi
                fi
            else
                Tmplist="$Tmplist\n$REPLY"
			fi
    	done < "$txt"
    	[[ $Tmplist != "" ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
        if [[ $recovery_flash = true ]]; then
        	if [[ -f $tools_path/update-binary && -f $TMPDIR/appList.txt ]]; then
        		echoRgb "輸出用於recovery的備份卡刷包" ; rm -rf "$MODDIR/recovery卡刷備份.zip"
        	    touch_shell "2" "$TMPDIR/start.sh"
                touch_shell "3" "$TMPDIR/recover.sh"
                update_Restore_settings_conf>"$TMPDIR/restore_settings.conf"
                mkdir -p "$TMPDIR/META-INF/com/google/android" && cp "$tools_path/update-binary" "$TMPDIR/META-INF/com/google/android"
        		tar -cpf - -C "${tools_path%/*}" "${tools_path##*/}" | tar --delete "tools/zip" | tar --recursive-unlink -xmpf - -C "$TMPDIR/"
        		(cd "$TMPDIR" && zip -r "recovery卡刷備份.zip" * -x 'scriptTMP')
        		echo_log "打包卡刷包"
        		[[ $result = 0 ]] && (mv "$TMPDIR/recovery卡刷備份.zip" "$MODDIR" && rm -rf "$TMPDIR"/* ; echoRgb "輸出:$MODDIR/recovery卡刷備份.zip" "2")
        	else
        		[[ ! -f $tools_path/update-binaryechoRgb ]] && echoRgb "update-binary卡刷腳本遺失" "0" || [[ ! -f $TMPDIR/appList.txt ]] && echoRgb "$TMPDIR/appList.txt 不存在" "0"
        	fi
        fi
    fi
	wait
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
	endtime 1
	echoRgb "輸出包名結束 請查看$txt"
}
backup_media() {
	kill_Serve
	self_test
	backup_path
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(echo "$Custom_path" | egrep -v '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
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
		echo "$script">"$TMPDIR/scriptTMP"
		Set_screen_pause_seconds on
		notification "109" "Media備份開始"
		{
		echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read; do
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
		} &
		wait
		Calculate_size "$Backup_folder"
		Set_screen_pause_seconds off
		endtime 1 "自定義備份"
		notification "109" "Media備份完成 $(endtime 1 "自定義備份")"
		rm -rf "$TMPDIR/scriptTMP"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
}
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
            down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read ; do
                unset model
                model="$(echo "$REPLY" | awk -F'"' '{print $2}')"
                if [[ $(egrep -w "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') != $model ]]; then
                    echo "$REPLY">>"$tools_path/Device_List"
                else
                    echo "$(egrep -w "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') = $model"
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
if [[ $0 = *backup.sh ]]; then
    start=backup
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
        echoRgb "音量鍵上下選擇對應功能，上鍵選擇下鍵跳過"
        steps=(
            "生成應用列表"
            "備份應用"
            "備份已更新應用"
            "備份自定義資料夾"
            "殺死運行中腳本"
        )
        commands=(
            "Getlist"
            "backup"
            "backup_update_apk"
            "backup_media"
            "echoRgb "等待腳本停止中，請稍後....." ; kill_Serve && echoRgb "腳本終止" ;exit"
        )
    else
        if [[ -f $MODDIR/restore_settings.conf ]]; then
            echoRgb "音量鍵上下選擇對應功能，上鍵選擇下鍵跳過"
            steps=(
                "恢復備份"
                "恢復自定義資料夾"
                "重新生成應用列表"
                "壓縮檔完整性檢查"
                "轉換文件夾名稱"
                "殺死運行中腳本"
            )
            commands=(
                "Restore"
                "Restore3"
                "dumpname"
                "check_file"
                "convert"
                "echo "等待腳本停止中，請稍後....." ; kill_Serve && echoRgb "腳本終止" ;exit"
            )
        fi
    fi
    # 開始循環提示
    for i in "${!steps[@]}"; do
        while true; do
            echoRgb "是否執行：${steps[$i]}？"
            get_version "執行${steps[$i]}" "略過${steps[$i]}" && Select_Result="$branch"
            case $Select_Result in
            true)
                case $(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}') in
                0)
                    eval "${commands[$i]}" ;;
                1)
                    {
                    eval "${commands[$i]}"
                    } & ;;
                esac
                exit 0
                ;;
            false)
                break
                ;;
            esac
        done
    done
fi