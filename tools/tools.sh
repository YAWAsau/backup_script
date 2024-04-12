#!/system/bin/sh
[[ -d /data/cache ]] && set -x 2> /data/cache/debug_output.log
shell_language="zh-TW"
MODDIR="$MODDIR"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
Compression_rate=3
script="${0##*/}"
backup_version="V15.9.0"
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
update_backup_settings_conf() {
    echo "#音量鍵選擇總開關 是否在每次執行備份腳本時使用音量鍵詢問備份需求
#1開啟音量鍵選擇 (如選項已設置，則跳過該選項提示)
#0關閉音量鍵選擇 (如選項未設置，則強制使用音量鍵選擇)
Lo="${Lo:-0}"

#腳本語言設置 留空則自動識別系統語言環境並翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#自定義備份文件輸出位置 支持相對路徑(留空則默認當前路徑)
Output_path=\""$Output_path"\"

#自定義applist.txt位置 支持相對路徑(留空則默認當前路徑)
list_location=\""$list_location"\"

#自動更新腳本(留空強制音量鍵選擇)
#1開啟 0關閉
update="${update:-1}"

#自定義屏蔽外部掛載點 例：OTG 虛擬SD等 多個掛載點請使用 | 區隔
#屏蔽後不會提示音量鍵選擇，不影響Output_path指定外置存儲位置
mount_point=\""${mount_point:-rannki|0000-1}"\"

#使用者(如0 999等用戶，如存在多個用戶留空強制音量鍵選擇，無多個用戶則默認用戶0不詢問)
user="$user"

#備份模式
#1包含數據+安裝包，0僅包安裝包
#此選項設置1時Backup_obb_data，Backup_user_data，blacklist_mode將可設置 0時Backup_user_data，Backup_obb_data，blacklist_mode選項不生效
#此外設置0時將同時忽略appList.txt的!與任何黑名單設置（包括黑名單列表）
Backup_Mode=1

#是否備份使用者數據 (1備份 0不備份 留空強制音量鍵選擇)
Backup_user_data="${Backup_user_data:-1}"

#是否備份外部數據 例：原神的數據包(1備份 0不備份 留空強制音量鍵選擇)
Backup_obb_data="${Backup_obb_data:-1}"

#是否在應用數據備份完成後備份自定義目錄
#1開啟 0關閉
backup_media="${backup_media:-0}"

#假設你遇到列表輸出異常問題請將此設為1
debug_list="${debug_list:-0}"

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

#需要在備份完成後啟動應用
am_start=\""${am_start:-
com.digibites.accubattery
com.dede.nativetools
}"\"

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
    echo "#音量鍵選擇總開關 是否在每次執行恢復腳本時使用音量鍵詢問恢復需求
#1開啟音量鍵選擇（如選項已設置，則跳過該選項提示）
#0關閉音量鍵選擇（如選項未設置，則強制使用音量鍵選擇）
Lo="${Lo:-0}"

#腳本語言設置 為空自動針對當前系統語言環境自動翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#自動更新腳本(留空強制音量鍵選擇)
update="${update:-1}"

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
[[ ! -f $tools_path/zstd ]] && echo "$tools_path/zstd遺失"
[[ ! -f $tools_path/tar ]] && echo "$tools_path/tar遺失"
[[ ! -f $tools_path/classes.dex ]] && echo "$tools_path/classes.dex遺失"
[[ ! -f $tools_path/classes2.dex ]] && echo "$tools_path/classes2.dex遺失"
if [[ ! -f $conf_path ]]; then
    case $operate in
    backup_media|backup|Getlist|Restore2|check_file|convert|Restore3|dumpname)
        if [[ $conf_path != *Backup_* ]]; then
            update_backup_settings_conf>"$conf_path"
            echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
        else
            if [[ $conf_path = *Backup_* ]]; then
                update_Restore_settings_conf>"$conf_path"
                echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
            else
                echo "$conf_path配置遺失" && exit 1
            fi
        fi ;;
    *)
        if [[ -f $MODDIR/backup_settings.conf ]]; then
            conf_path="$MODDIR/backup_settings.conf"
        else
            [[ -f $MODDIR/restore_settings.conf ]] && conf_path="$MODDIR/restore_settings.conf"
        fi
    esac
fi
[[ ! -f $conf_path ]] && echo "$conf_path遺失" && exit 2
. "$conf_path" &>/dev/null
if [[ $Shell_LANG != "" ]]; then
    case $Shell_LANG in
    1) LANG="CN" ;;
    0) LANG="TW" ;;
    *) echo "$conf_path Shell_LANG=$Shell_LANG 設置錯誤 正確1or0" && exit 2 ;;
    esac
fi
[[ $LANG = "" ]] && LANG="$(getprop "persist.sys.locale")"
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
[ "$rgb_a" = "" ] && rgb_a=214
if [ "$(whoami)" != root ]; then
	echoRgb "你是憨批？不給Root用你媽 爬" "0"
	exit 1
fi
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
id=
if [[ $id != "" && -d /data/user/0/com.tencent.mobileqq/files/aladdin_configs/$id ]]; then
	exit 2
fi
PATH="/sbin/.magisk/busybox:/sbin/.magisk:/sbin:/data/adb/ksu/bin:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin:/data/data/Han.GJK/files/usr/busybox"
if [[ -d $(magisk --path 2>/dev/null) ]]; then
	PATH="$(magisk --path 2>/dev/null)/.magisk/busybox:$PATH"
else
	[[ $(ksud -V 2>/dev/null) = "" ]] && echo "Magisk busybox Path does not exist"
fi
export PATH="$PATH"
#tools_path="${tools_path/'/storage/emulated/'/'/data/media/'}"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$tools_path/busybox"
#排除自身
exclude="
update
soc.json
busybox_path
Device_List"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echoRgb "設置busybox環境中"
fi
[[ ! -f $tools_path/busybox_path ]] && touch "$tools_path/busybox_path"
if [[ $filepath != $(cat "$tools_path/busybox_path") ]]; then
	[[ -d $(cat "$tools_path/busybox_path") ]] && rm -rf "$(cat "$tools_path/busybox_path")"
	echoRgb "$filepath" >"$tools_path/busybox_path"
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
		if [[ $REPLY != tar && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
fi
[[ ! -f $filepath/zstd ]] && echoRgb "$filepath缺少zstd" && exit 2
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
export CLASSPATH="$tools_path/classes.dex:$tools_path/classes2.dex"
zstd_sha256sum="55cc57a3d079dd90e74d972c705c4f9389dd00a7175de148e21000eab01f7ed9"
tar_sha256sum="3c605b1e9eb8283555225dcad4a3bf1777ae39c5f19a2c8b8943140fd7555814"
classesdex_sha256sum="09d0058763157b97d6ea2bf74bd7ec53089a9ddb496f089a159ea0027007bb94"
classesdex2_sha256sum="e78b33af047464c225b171da0da3e46fb2932b798ff4cd26de75a1649b5e30d5"
[[ $(sha256sum "$tools_path/zstd" | cut -d" " -f1) != $zstd_sha256sum ]] && echoRgb "zstd效驗失敗" "0" && exit 2
[[ $(sha256sum "$tools_path/tar" | cut -d" " -f1) != $tar_sha256sum ]] && echoRgb "tar效驗失敗" "0" && exit 2
[[ $(sha256sum "$tools_path/classes.dex" | cut -d" " -f1) != $classesdex_sha256sum ]] && echoRgb "classes.dex效驗失敗" "0" && exit 2
[[ $(sha256sum "$tools_path/classes2.dex" | cut -d" " -f1) != $classesdex2_sha256sum ]] && echoRgb "classes2.dex效驗失敗" "0" && exit 2
TMPDIR="/data/local/tmp"
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
if [[ $(which toybox | egrep -o "system") != system ]]; then
	echoRgb "系統變量中沒有找到toybox" "0"
	exit 1
fi
#下列為自定義函數
alias appinfo="app_process /system/bin --nice-name=appinfo han.core.order.AppInfo $@"
alias down="app_process /system/bin --nice-name=down han.core.order.Down $@"
alias PayloadDumper="app_process /system/bin --nice-name=payload-dumper han.core.order.payload.PayloadDumper $@"
case $LANG in
*CN* | *cn*)
    alias ts="app_process /system/bin --nice-name=appinfo han.core.order.ChineseConverter -s $@" ;;
*)
    alias ts="app_process /system/bin --nice-name=appinfo han.core.order.ChineseConverter -t $@" ;;
esac
alias LS="toybox ls -Zd"
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
	[[ $duration != "" ]] && echoRgb "$2用時:$duration" || echoRgb "$2用時:0秒"
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
		sleep 0.5
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
	{
	#process_name Tar
	#process_name pv
	#process_name Zstd
	if [[ -e $TMPDIR/scriptTMP ]]; then
		scriptname="$(cat "$TMPDIR/scriptTMP")"
		echoRgb "腳本殘留進程，將殺死後退出腳本，請重新執行一次\n -殺死$scriptname" "0"
		rm -rf "$TMPDIR/scriptTMP"
		process_name "$scriptname"
		exit
	fi
	} &
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
        cat "$tools_path/soc.json" | jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' &>/dev/null
        if [[ $? = 0 ]]; then
          DEVICE_NAME="$(cat "$tools_path/soc.json" | jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' 2>/dev/null)"
          cat "$tools_path/soc.json" | jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' &>/dev/null
          if [[ $? = 0 ]]; then
            RAMINFO="$(cat "$tools_path/soc.json" | jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' 2>/dev/null)"
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
echoRgb "腳本路徑:$MODDIR\n -已開機:$(Show_boottime)\n -執行時間:$(date +"%Y-%m-%d %H:%M:%S")\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -管理器:$Manager_version\n -品牌:$(getprop ro.product.brand 2>/dev/null)\n -型號:$Device_name($(getprop ro.product.device 2>/dev/null))\n -閃存顆粒:$UFS_MODEL($ROM_TYPE)\n -$DEVICE_NAME\n -$RAMINFO\n -Android版本:$(getprop ro.build.version.release 2>/dev/null) SDK:$(getprop ro.build.version.sdk 2>/dev/null)\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
case $MODDIR in
*Backup_*)
    if [[ -f $MODDIR/app_details ]]; then
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
case $LANG in
*TW* | *tw* | *HK*)
    echoRgb "系統語言環境:繁體中文"
	Script_target_language="zh-TW" ;;
*CN* | *cn*)
    echoRgb "系統語言環境:簡體中文"
	Script_target_language="zh-CN" ;;
esac
case $operate in
backup|Restore|Restore2|Getlist|backup_media)
    if [[ $backup_mode = "" ]]; then
        if [[ $user = "" ]]; then
    	    user_id="$(appinfo -listUsers)"
    	    if [[ $user_id != "" && $(appinfo -listUsers | wc -l) -gt 1 ]]; then
    		    echo "$user_id" | while read ; do
    			    [[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
    		    done
    	        echoRgb "設備存在多用戶,選擇操作目標用戶"
    	        if [[ $(echo "$user_id" | wc -l) = 2 ]]; then
    	            user1="$(echo "$user_id" | sed -n '1p')"
    	            user2="$(echo "$user_id" | sed -n '2p')"
    	            echoRgb "音量上選擇用戶:$user1，音量下選擇用戶:$user2" "2"
    		        Select_user="true"
    		        get_version "$user1" "$user2" && user="$branch"
    		        unset Select_user
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
            user_id="$(appinfo -listUsers)"
    	    if [[ $user_id != "" && $(appinfo -listUsers | wc -l) -gt 1 ]]; then
    		    echo "$user_id" | while read ; do
    			    [[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
    		    done
    		else
    		    echoRgb "主用戶:$user_id" "2" 
    	    fi
    	fi
    else
        user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')"
    fi
	path="/data/media/$user/Android"
    path2="/data/user/$user"
	[[ ! -d $path2 ]] && echoRgb "$user分區不存在，請將上方提示的用戶id按照需求填入\n -$conf_path配置項user=,一次只能填寫一個" "0" && exit 2
	echoRgb "當前操作為用戶$user"
	export USER_ID="$user" ;;
esac
#因接收USER_ID環境變量問題故將函數放在此處
alias get_ssaid="app_process /system/bin com.xayah.dex.SsaidUtil get $USER_ID $@"
alias set_ssaid="app_process /system/bin com.xayah.dex.SsaidUtil set $USER_ID $@"
alias get_uid="app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageUid $USER_ID $@"
alias get_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil getRuntimePermissions $USER_ID $@"
alias Set_true_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil grantRuntimePermission $USER_ID $@"
alias Set_false_Permissions="app_process /system/bin com.xayah.dex.HiddenApiUtil revokeRuntimePermission $USER_ID $@"
find_tools_path="$(find "$path_hierarchy"/* -maxdepth 1 -name "tools" -type d ! -path "$path_hierarchy/tools")"
Rename_script () {
    [[ $HT = "" ]] && HT=0 
	find "$path_hierarchy" -maxdepth 3 -name "*.sh" -type f -not -name "tools.sh" | sort | while read ; do
        Script_type="$(grep -o 'operate="[^"]*"' "$REPLY" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"' | head -1)"
        MODDIR_NAME="${REPLY%/*}"
        FILE_NAME="${REPLY##*/}"
        case $Script_type in
        backup|Getlist|backup_media|Restore|dumpname|check_file|convert|Restore3|Restore2)
            if [[ -f ${REPLY%/*}/app_details ]]; then
	            if [[ $FILE_NAME = backup.sh ]]; then
                    touch_shell "$Script_type" "$REPLY" "backup_mode" "backup_mode=\"1\""
                else
                    touch_shell "$Script_type" "$REPLY"
                fi
            else
                if [[ -d ${REPLY%/*}/tools ]]; then
                    touch_shell "$Script_type" "$REPLY"
	                if [[ $Script_target_language != $shell_language ]]; then
	                    [[ $HT = 0 && $K = "" ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
	                    ts -f "$REPLY" -o "$REPLY"
	                    echo_log "$REPLY翻譯"
	                    mv "$REPLY" "$MODDIR_NAME/$(ts "$FILE_NAME")"
	                fi
	            fi
	            let HT++
            fi ;;
        kill_script)
            if [[ $Script_target_language != $shell_language ]]; then
                [[ $HT = 0 && $K = "" ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
	            ts -f "$REPLY" -o "$REPLY"
	            echo_log "$REPLY翻譯"
	            mv "$REPLY" "$MODDIR_NAME/$(ts "$FILE_NAME")"
	            let HT++
	        fi ;;
        esac
	done
	unset HT
}
touch_shell () {
    unset conf_path MODDIR_Path
    MODDIR_Path='${0%/*}'
    MODDIR_NAME2="${2%/*}"
	MODDIR_NAME2="${MODDIR_NAME2##*/}"
    conf_path='${0%/*}/backup_settings.conf'
    case $1 in
    Restore2)
        MODDIR_Path='${0%/*/*}'
        conf_path='${0%/*/*}/restore_settings.conf' ;;
    backup)
        if [[ $3 = backup_mode ]]; then
            MODDIR_Path='${0%/*/*/*}'
            conf_path='${0%/*/*/*}/backup_settings.conf'
        fi ;;
    Restore|convert|dumpname|Restore3|check_file) conf_path='${0%/*}/restore_settings.conf' ;;
    esac
    if [[ $4 != "" ]]; then
        [[ $Output_path = "" ]] && echo "if [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then\n    MODDIR=\"$MODDIR_Path\"\n    . \"\${0%/*}/app_details\" &>/dev/null\n    operate=\"$1\"\n    $4\n    conf_path=\"$conf_path\"\n    . \"$MODDIR_Path/tools/tools.sh\" | tee \"\${0%/*}/log.txt\"\nelse\n    echo \"$MODDIR_Path/tools/tools.sh遺失\"\nfi" >"$2"
    else
        echo "[ \"\$(echo \"\${0%/*}\" | grep -o 'bin.mt.plus/temp')\" != \"\" ] && echo \"你媽沒告訴你腳本要解壓縮嗎？傻逼玩兒\" && exit 2\nif [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then\n    MODDIR=\"\${0%/*}\"\n    operate=\"$1\"\n    conf_path=\"$conf_path\"\n    . \"$MODDIR_Path/tools/tools.sh\" | tee \"\$MODDIR/log.txt\"\nelse\n    echo \"$MODDIR_Path/tools/tools.sh遺失\"\nfi" >"$2"
    fi
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
				        shell_language="$(grep -o 'shell_language="[^"]*"' "$MODDIR/tools.sh" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"' | head -1)"
					    case $MODDIR in
					    *Backup_*)
						    if [[ -f $MODDIR/app_details ]]; then
                                echoRgb "請在${MODDIR%/*}更新腳本" "0"
                                rm -rf "$MODDIR/tools.sh"
                                exit 2
                            fi ;;
					    esac
					    echoRgb "從$zipFile更新"
					    if [[ -d $path_hierarchy/tools ]]; then
					        cp -r "$path_hierarchy/tools" "$TMPDIR"
					        mv "$zipFile" "$path_hierarchy"
					        zipFile="$path_hierarchy/${zipFile##*/}"
					        rm -rf "$path_hierarchy/tools"
					        unzip -o "$zipFile" tools/* -d "$path_hierarchy" | sed 's/inflating/釋放/g ; s/creating/創建/g ; s/Archive/解壓縮/g'
					        echo_log "解壓縮${zipFile##*/}"
					        if [[ $result = 0 ]]; then
                                if [[ $shell_language != $Script_target_language ]]; then
                                    echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
                                    ts -f "$path_hierarchy/tools/Device_List" -o "$path_hierarchy/tools/Device_List"
                                    echo_log "$path_hierarchy/tools/Device_List翻譯"
					                ts -f "$path_hierarchy/tools/tools.sh" -o "$path_hierarchy/tools/tools.sh" && sed -i "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$path_hierarchy/tools/tools.sh"
                                    echo_log "$path_hierarchy/tools/tools.sh翻譯"
                                    HT=1
                                fi
                                update_backup_settings_conf>"$path_hierarchy/backup_settings.conf"
                                ts -f "$path_hierarchy/backup_settings.conf" -o "$path_hierarchy/backup_settings.conf"
                                echo_log "$path_hierarchy/backup_settings.conf"
                                if [[ -d $find_tools_path && $find_tools_path != $path_hierarchy/tools ]]; then
                                    rm -rf "$find_tools_path"
                                    cp -r "$path_hierarchy/tools" "${find_tools_path%/*}"
                                    update_Restore_settings_conf>"${find_tools_path%/*}/restore_settings.conf"
                                    ts -f "${find_tools_path%/*}/restore_settings.conf" -o "${find_tools_path%/*}/restore_settings.conf"
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
						        cp -r "$TMPDIR/tools" "$MODDIR"
					        fi
					        rm -rf "$TMPDIR"/* "$zipFile" "$MODDIR/tools.sh"
					        echoRgb "更新完成 請重新執行腳本" "2"
					        exit
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
zipFile2="$(ls -t "$MODDIR"/*.zip 2>/dev/null | head -1)"
if [[ $zipFile2 != "" ]]; then
    PayloadDumper -o "$MODDIR/ROM" "$zipFile2"
    exit
fi
        
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
case $operate in
Getlist|Restore2|Restore3|dumpname|check_file|backup_media|convert|Device_List) ;;
*) isBoolean "$Lo" "Lo" && Lo="$nsx" ;;
esac
cdn=2
#settings get system system_locales
Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
if [[ $path_hierarchy != "" && $Script_target_language != ""  ]]; then
	K=1
	J="$(find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | wc -l)"
	find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | while read ; do
	    unset shell_language
	    shell_language="$(grep -o 'shell_language="[^"]*"' "$REPLY" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"' | head -1)"
	    case $shell_language in
	    zh-CN|zh-TW)
	        if [[ $Script_target_language != $shell_language ]]; then
	            [[ $K = 1 ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
	            ts -f "$REPLY" -o "$REPLY"
	            if [[ $? = 0 ]]; then
	                touch "$TMPDIR/0"
	                echo_log "$REPLY翻譯"
	                MODDIR="${0%/*}"
                    if [[ $REPLY != *Backup_* ]]; then
                        update_backup_settings_conf>"${REPLY%/*/*}/backup_settings.conf"
                        ts -f "${REPLY%/*/*}/backup_settings.conf" -o "${REPLY%/*/*}/backup_settings.conf"
                        echo_log "${REPLY%/*/*}/backup_settings.conf翻譯"
                    else
                        if [[ $REPLY = *Backup_* ]]; then
                            update_Restore_settings_conf>"${REPLY%/*/*}/restore_settings.conf"
                            ts -f "${REPLY%/*/*}/restore_settings.conf" -o "${REPLY%/*/*}/restore_settings.conf"
                            echo_log "${REPLY%/*/*}/restore_settings.conf翻譯"
                        fi
                    fi
	                sed -i "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$REPLY"
	                ts -f "${REPLY%/*}/Device_List" -o "${REPLY%/*}/Device_List"
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
#效驗選填是否正確
Lo="$(echo "$Lo" | sed 's/true/1/g ; s/false/0/g')"
isBoolean "$Lo" "Lo" && Lo="$nsx"
if [[ $Lo = false ]]; then
	[[ $update != "" ]] && isBoolean "$update" "update" && update="$nsx" || {
	echoRgb "自動更新腳本?\n -音量上更新，下不更新"
    get_version "更新" "不更新" && update="$branch"
    }
else
    [[ $update = "" ]] && {
    echoRgb "自動更新腳本?\n -音量上更新，下不更新"
	get_version "更新" "不更新" && update="$branch"
	} || isBoolean "$update" "update" && update="$nsx"
fi
[[ $update = true ]] && json="$(down -s -L "$Language" 2>/dev/null)" || echoRgb "自動更新被關閉" "0"
if [[ $json != "" ]]; then
	tag="$(echo "$json" | sed -r -n 's/.*"tag_name": *"(.*)".*/\1/p')"
	if [[ $tag != "" && $backup_version != $tag ]]; then
		if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$tag" | tr -d "a-zA-Z")") -eq 0 ]]; then
			download="$(echo "$json" | sed -r -n 's/.*"browser_download_url": *"(.*.zip)".*/\1/p')"
			case $cdn in
			1) zip_url="http://huge.cf/download/?huge-url=$download" ;;
			2) zip_url="https://github.moeyy.xyz/$download" ;;
			3) zip_url="https://gh.api.99988866.xyz/$download" ;;
			4) zip_url="https://github.lx164.workers.dev/$download" ;;
			5) zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download" ;;
			6) zip_url="https://github.moeyy.xyz/$download" ;;
			esac
			if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$download" | tr -d "a-zA-Z")") -eq 0 ]]; then
				echoRgb "發現新版本:$tag"
				if [[ $update = true ]]; then
				    echoRgb "更新日誌:\n$(down -s -L "$Language" | jq -r '.body' 2>/dev/null)"
					echoRgb "是否更新腳本？\n -音量上更新，音量下不更新" "2"
					get_version "更新" "不更新" && choose="$branch"
					if [[ $choose = true ]]; then
					    echoRgb "下載中.....耐心等待 如果下載失敗請掛飛機"
						starttime1="$(date -u "+%s")"
						down -s -L -o "$MODDIR/update.zip" "$zip_url" &
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
Lo="$(echo "$Lo" | sed 's/true/1/g ; s/false/0/g')"
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
	    if [[ $backup_mode = "" ]]; then
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
			echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
			get_version "選擇了隨身碟備份" "選擇了本地備份"
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
	filesizee="$(du -s "$1" | awk '{print $1}')"
	if [[ $(expr "$filesize" \> "$filesizee") -eq 0 ]]; then
	    NJK="增加"
        dsize="$(($((filesizee -filesize)) / 1024))"
    else
        NJK="減少"
        dsize="$(($((filesize-filesizee)) / 1024))"
    fi
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(du -ksh "$1" | awk '{print $1}')"
	if [[ $dsize -gt 0 ]]; then
		if [[ $((dsize / 1000)) -gt 0 ]]; then
			NJL="本次備份$NJK: $((dsize / 1000))gb"
		else
			NJL="本次備份$NJK: ${dsize}mb"
		fi
	else
		NJL="本次備份$NJK: $(($((filesizee - filesize)) * 1000 / 1024))kb"
	fi
	echoRgb "$NJL"
}
size () {
    varr="$(echo "$1" | bc 2>/dev/null)"
    if [[ $varr != $1 ]]; then
        b_size="$(ls -l "$1" 2>/dev/null | awk '{print $5}')"
    else
        b_size="$1"
    fi
	k_size="$(awk 'BEGIN{printf "%.2f\n", "'$b_size'"/'1024'}')"
	m_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')"
    if [[ $(expr "$m_size" \> 1) -eq 0 ]]; then
        echo "${k_size}KB"
    else
        [[ $(echo "$m_size" | cut -d '.' -f1) -lt 1024 ]] && echo "${m_size}MB" || echo "$(awk 'BEGIN{printf "%.2f\n", "'$m_size'"/'1024'}')GB"
    fi
}
#分區佔用信息
partition_info() {
	Occupation_status="$(df "${1%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1)}')"
	echo " -$2字節:$Filesize 剩餘字節:$Occupation_status"
	[[ $Filesize -gt $Occupation_status ]] && echoRgb "$2備份大小將超出rom可用大小" "0" && exit 2
	Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
kill_app() {
    if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
        [[ $Pause_Freeze = "" ]] && Pause_Freeze="0"
        if [[ $Pause_Freeze = 0 ]]; then
            if [[ $(dumpsys activity processes | grep "packageList" | cut -d '{' -f2 | cut -d '}' -f1 | egrep -w "^$name2$" | sed -n '1p') = $name2 ]]; then
                killall -9 "$name2" &>/dev/null
                am force-stop --user "$user" "$name2" &>/dev/null
                am kill "$name2" &>/dev/null
                echoRgb "殺死$name1進程"
            fi
            pm suspend --user "$user" "$name2" 2>/dev/null | sed "s/Package $name2/ -應用:$name1/g ; s/new suspended state: true/暫停狀態:凍結/g"
	    fi
	    Pause_Freeze="1"
	fi
}
Set_service() {
    if [[ $Pause_Freeze = 1 ]]; then
        pm unsuspend --user "$user" "$name2" 2>/dev/null | sed "s/Package $name2/ -應用:$name1/g ; s/new suspended state: false/暫停狀態:解凍/g"
        Pause_Freeze="0"
    fi
}
restore_freeze() {
    appinfo -o pn -p | while read ; do
        pm unsuspend --user "$user" "$REPLY" 2>/dev/null | sed "s/Package $name2/ -應用:$name1/g ; s/new suspended state: false/暫停狀態:解凍/g"
    done
}
get_variables() {
    awk "/$1/"'{print $1}' "$2" | cut -f2 -d '=' | tail -n1 | sed 's/\"//g'
}
Backup_apk() {
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	apk_version2="$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
	apk_version3="$(dumpsys package "$name2" 2>/dev/null | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1)"
	if [[ $apk_version = $apk_version2 ]]; then
		[[ $(sed -e '/^$/d' "$txt2" | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
		unset xb
		let osj++
		result=0
		echoRgb "Apk版本無更新 跳過備份" "2"
	else
		if [[ $nobackup != true ]]; then
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
			Filesize="$(du -s "$apk_path2" | awk '{print $1}')"
			partition_info "$Backup" "$name1 apk"
			#備份apk
			echoRgb "$1"
			echo "$apk_path" | sed -e '/^$/d' | while read; do
				echoRgb "${REPLY##*/} $(size "$REPLY")"
			done
			(
				cd "$apk_path2"
				case $Compression_method in
				tar | TAR | Tar) tar --checkpoint-action="ttyout=%T\r" -cf "$Backup_folder/apk.tar" *.apk ;;
				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" -cf - *.apk | zstd --ultra -"$Compression_rate" -T0 -q --priority=rt >"$Backup_folder/apk.tar.zst" ;;
				esac
			)
			echo_log "備份$apk_number個Apk"
			if [[ $result = 0 ]]; then
			    Validation_file "$Backup_folder/apk.tar"*
				if [[ $result = 0 ]]; then
					[[ $(sed -e '/^$/d' "$txt2" 2>/dev/null | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
					if [[ $apk_version = "" ]]; then
						echo "apk_version=\"$apk_version2\"" >>"$app_details"
					else
						echo "$(sed "s/${apk_version}/${apk_version2}/g" "$app_details")">"$app_details"
					fi
					if [[ $versionName = "" ]]; then
						echo "versionName=\"$apk_version3\"" >>"$app_details"
					else
						echo "$(sed "s/${versionName}/${apk_version3}/g" "$app_details")">"$app_details"
					fi
					[[ $PackageName = "" ]] && echo "PackageName=\"$name2\"" >>"$app_details"
					[[ $ChineseName = "" ]] && echo "ChineseName=\"$name1\"" >>"$app_details"
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
		else
			let osj++
			rm -rf "$Backup_folder"
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
#檢測數據位置進行備份
Backup_data() {
	data_path="$path/$1/$name2"
	MODDIR_NAME="${data_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	case $1 in
	user) Size="$userSize" && data_path="$path2/$name2" ;;
	data) Size="$dataSize" ;;
	obb) Size="$obbSize" ;;
	*)
		if [[ -f $app_details ]]; then
		    Size="$(get_variables "$1Size" "$app_details")"
		    mediapath="$(get_variables "$1mediapath" "$app_details")"
		fi
		data_path="$2"
		if [[ $1 != storage-isolation && $1 != thanox ]]; then
			Compression_method1="$Compression_method"
			Compression_method=tar
		fi
		zsize=1
		zmediapath=1
		;;
	esac
	if [[ -d $data_path ]]; then
	    unset Filesize m_size k_size get_size ssaid Get_Permissions
        Filesize="$(du -s "$data_path" | awk '{print $1}')"
        k_size="$(awk 'BEGIN{printf "%.2f\n", "'$Filesize'"'*1024'/'1024'}')"
	    m_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')"
        if [[ $(expr "$m_size" \> 1) -eq 0 ]]; then
            get_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')KB"
        else
            [[ $(echo "$m_size" | cut -d '.' -f1) -lt 1000 ]] && get_size="${m_size}MB" || get_size="$(awk 'BEGIN{printf "%.2f\n", "'$m_size'"/'1024'}')GB"
        fi
        case $1 in
		user)
		    ssaid="$(get_ssaid "$name2")"
			if [[ $ssaid != null && $ssaid != $Ssaid ]]; then
			    if [[ $Ssaid != "" ]]; then
				    echo "$(sed "s/$Ssaid/$ssaid/g" "$app_details")">"$app_details"
				else
					echo "Ssaid=\"$ssaid\"" >>"$app_details"
				fi
				SSAID_apk="$(echo "$name1 \"$name2\"")"
				SSAID_apk2="$(echo "$SSAID_apk\n$SSAID_apk2")"
				echo_log "備份ssaid"
			fi
			Get_Permissions="$(get_Permissions "$name2")"
			if [[ $Get_Permissions != "" ]]; then
    			if [[ $Permissions = "" ]]; then
    			    echo "Permissions=\"$Get_Permissions\"">"$app_Permissions"
    			    echo_log "備份權限"
    			else
    			   [[ $Permissions != $Get_Permissions ]] && echo "Permissions=\"$Get_Permissions\"">"$app_Permissions" && echo_log "備份權限"
    			fi
    	    fi ;;
		esac
		if [[ $Size != $Filesize ]]; then
		    #停止應用
			case $1 in
			user|data|obb) kill_app ;;
			esac
			partition_info "$Backup" "$1"
			echoRgb "備份$1數據($get_size)"
			case $1 in
			user)
				case $Compression_method in
				tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null ;;
				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -"$Compression_rate" -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" 2>/dev/null ;;
				esac
				;;
			*)
				case $Compression_method in
				tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" ;;
				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -"$Compression_rate" -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
				esac
				;;
			esac
			echo_log "備份$1數據"
			if [[ $result = 0 ]]; then
			    Validation_file "$Backup_folder/$1.tar"*
				if [[ $result = 0 ]]; then
				    [[ ${Backup_folder##*/} = Media ]] && [[ $(sed -e '/^$/d' "$mediatxt" | grep -w "${REPLY##*/}.tar$" | head -1) = "" ]] && echo "$FILE_NAME" >> "$mediatxt"
					if [[ $zsize != "" ]]; then
						if [[ $Size != "" ]]; then
							echo "$(sed "s/$Size/$Filesize/g" "$app_details")">"$app_details"
						else
							echo "#$1Size=\"$Filesize\"" >>"$app_details"
						fi
					else
						if [[ $Size != "" ]]; then
							echo "$(sed "s/$Size/$Filesize/g" "$app_details")">"$app_details"
						else
							echo "$1Size=\"$Filesize\"" >>"$app_details"
						fi
					fi
				    if [[ $zmediapath != "" ]]; then
						if [[ $mediapath = "" ]]; then
							echo "#$1mediapath=\"$2\"" >>"$app_details"
						fi
					fi
				else
					rm -rf "$Backup_folder/$1".tar.*
				fi
			fi
			[[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1"
			unset Compression_method1
		else
			echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
	else
		[[ -f $data_path ]] && echoRgb "$1是一個文件 不支持備份" "0" || echoRgb "$1數據不存在跳過備份" "2"
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
		case $FILE_NAME2 in
		user) 
		    if [[ -d $X ]]; then
		        FILE_PATH="$path2"
		        Size="$userSize"
		        Selinux_state="$(LS "$X" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)"
		    else
		        echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
		    fi;;
		data) FILE_PATH="$path/data" Size="$dataSize" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)";;
		obb) FILE_PATH="$path/obb" Size="$obbSize" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)";;
		thanox) FILE_PATH="/data/system" Size="$(get_variables "${FILE_NAME2}Size" "$app_details")" && find "/data/system" -name "thanos*" -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
		storage-isolation) FILE_PATH="/data/adb" Size="$(get_variables "${FILE_NAME2}Size" "$app_details")" ;;
		*)
			if [[ $A != "" ]]; then
				if [[ ${MODDIR_NAME##*/} = Media ]]; then
				    FILE_PATH="$(get_variables "${FILE_NAME2}mediapath" "$app_details")"
					if [[ $FILE_PATH = "" ]]; then
						echoRgb "路徑獲取失敗" "0"
					else
						echoRgb "解壓路徑↓\n -$FILE_PATH" "2"
						FILE_PATH="${FILE_PATH%/*}"
						Size="$(get_variables "${FILE_NAME2}Size" "$app_details")"
						[[ ! -d $FILE_PATH ]] && mkdir -p "$FILE_PATH"
					fi
				fi
		    else
			    echoRgb "$tar_path名稱似乎有誤" "0"
			fi ;;
		esac
        echoRgb "恢復$FILE_NAME2數據 釋放$(size "$(awk 'BEGIN{printf "%.2f\n", "'$Size'"*'1024'}')")" "3"
   		if [[ $FILE_PATH != "" ]]; then
            [[ ${MODDIR_NAME##*/} != Media ]] && rm -rf "$FILE_PATH/$name2"
		    case ${FILE_NAME##*.} in
			zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$tar_path" -C "$FILE_PATH" ;;
			tar) [[ ${MODDIR_NAME##*/} = Media ]] && tar --checkpoint-action="ttyout=%T\r" -axf "$tar_path" -C "$FILE_PATH" || tar --checkpoint-action="ttyout=%T\r" -amxf "$tar_path" -C "$FILE_PATH" ;;
			esac
		else
			Set_back_1
		fi
		echo_log "解壓縮${FILE_NAME##*.}"
		if [[ $result = 0 ]]; then
			case $FILE_NAME2 in
			user|data|obb)
			    if [[ $G = "" ]]; then
		            if [[ $(get_uid "$name2" 2>/dev/null) != "" ]]; then
				        G="$(get_uid "$name2" 2>/dev/null)"
				    else
					    G="$(dumpsys package "$name2" 2>/dev/null | awk -F'uid=' '{print $2}' | egrep -o '[0-9]+' | head -n 1)"
					    [[ $(echo "$G" | egrep -o '[0-9]+') = "" ]] && G="$(pm list packages -U --user "$user" | egrep -w "$name2" | awk -F'uid:' '{print $2}' | awk '{print $1}' | head -n 1)"
				    fi
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
                        if [[ $FILE_NAME2 = user ]]; then
						    echoRgb "路徑:$X"
						    chown -hR "$uid" "$X/"
						    echo_log "設置用戶組:$(ls -ld "$X" | awk '{print $3,$4}'),shell in :$uid"
						    chcon -hR "$Selinux_state" "$X/" 2>/dev/null
						    echo_log "selinux上下文設置"
					    elif [[ $FILE_NAME2 = data || $FILE_NAME2 = obb ]]; then
                            chown -hR "$uid" "$FILE_PATH/$name2/"
                            chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>/dev/null
					    fi
				    else
				        echoRgb "路徑$X不存在" "0"
					fi
				else
                    echoRgb "uid獲取失敗" "0"
				fi
				;;
			thanox)
				restorecon -RF "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d 2>/dev/null)/" 2>/dev/null
				echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
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
			find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f 2>/dev/null | grep -v 'nmsl.apk' | while read; do
				pm install-write "$b" "${REPLY##*/}" "$REPLY" &>/dev/null
				echo_log "${REPLY##*/}安裝"
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
	#關閉play安全效驗
	if [[ $(settings get global package_verifier_user_consent 2>/dev/null) != -1 ]]; then
		settings put global package_verifier_user_consent -1 2>/dev/null
		settings put global upload_apk_enable 0 2>/dev/null
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
}
get_name(){
	txt="$MODDIR/appList.txt"
	txt2="$MODDIR/mediaList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	if [[ $1 = Apkname ]]; then
		rm -rf "$txt" "$txt2"
		echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	fi
	rgb_a=118
	find "$MODDIR" -maxdepth 2 -name "apk.*" -type f 2>/dev/null | sort | while read; do
		Folder="${REPLY%/*}"
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		unset PackageName NAME DUMPAPK ChineseName
		[[ -f $Folder/app_details ]] && . "$Folder/app_details" &>/dev/null
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
					DUMPAPK="$(appinfo -d " " -o anwb,pn -f "$TMPDIR/base.apk")"
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
			case $1 in
			Apkname)
			    [[ -f $Folder/${PackageName}.sh ]] && rm -rf "$Folder/${PackageName}.sh"
		        [[ ! -f $Folder/recover.sh ]] && touch_shell "Restore2" "$Folder/recover.sh"
			    [[ ! -f $Folder/backup.sh ]] && touch_shell "backup" "$Folder/backup.sh" "backup_mode" "backup_mode=\"1\""
				echoRgb "$ChineseName $PackageName" && echo "$ChineseName $PackageName" >>"$txt" ;; 
			convert)
				if [[ ${Folder##*/} = $PackageName ]]; then
					mv "$Folder" "${Folder%/*}/$ChineseName" && echoRgb "${Folder##*/} > $ChineseName"
				else
					mv "$Folder" "${Folder%/*}/$PackageName" && echoRgb "${Folder##*/} > $PackageName"
				fi ;;
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
	echoRgb "效驗$FILE_NAME"
	case ${FILE_NAME##*.} in
	zst) zstd -t "$1" 2>/dev/null ;;
	tar) tar -tf "$1" &>/dev/null ;;
	esac
	echo_log "效驗"
}
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>/dev/null | sort)"
	i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details" -type f 2>/dev/null | wc -l)"
	find "$MODDIR" -maxdepth 2 -name "app_details" -type f 2>/dev/null | sort | while read; do
		REPLY="${REPLY%/*}"
		echoRgb "效驗第$i/$r個資料夾 剩下$((r - i))個" "3"
		echoRgb "效驗:${REPLY##*/}"
		find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | sort | while read; do
			Validation_file "$REPLY"
			[[ $result != 0 ]] && echo "$REPLY">>"$error_log"
		done
		echoRgb "$((i * 100 / r))%"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n $(cat "$error_log")" || echoRgb "恭喜~~全數效驗通過" 
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
    elif [[ $1 = off ]]; then
        if [[ $Get_dark_screen_seconds != "" ]]; then
            settings put system screen_off_timeout "$Get_dark_screen_seconds"
            echo_log "設置無操作息屏時間為$Get_dark_screen_seconds"
        fi
    fi
}
restore_permissions () {
    echoRgb "恢復權限"
    appops reset --user "$user" "$name2" &>/dev/null
	[[ $(echo "$Permissions" | grep "true$") != "" ]] && Set_true_Permissions "$name2" "$(echo "$Permissions" | grep "true$" | sed 's/ true$//' | xargs)" &>/dev/null
    [[ $(echo "$Permissions" | grep "false$") != "" ]] && Set_false_Permissions "$name2" "$(echo "$Permissions" | grep "false$" | sed 's/ false$//' | xargs)" &>/dev/null
}
case $operate in
backup)
	kill_Serve
	self_test
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	#效驗選填是否正確
	isBoolean "$Lo" "Lo" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		[[ $Backup_Mode != "" ]] && isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx" || {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		}
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -v "#" | wc -l) -gt 0 ]]; then
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
	else
		[[ $Backup_Mode = "" ]] && {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		} || isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx"
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -v "#" | wc -l) -gt 0 ]]; then
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
	fi
	i=1
	#數據目錄
	if [[ $list_location != "" ]]; then
	    if [[ ${list_location:0:1} = / ]]; then
	        txt="$list_location"
	    else
	        txt="$MODDIR/$list_location"
	        echoRgb "$txt"
	    fi
	else
	    txt="$MODDIR/appList.txt"
	fi
	#txt="${txt/'/storage/emulated/'/'/data/media/'}"
	[[ ! -f $txt ]] && echoRgb "請執行\"生成應用列表.sh\"獲取應用列表再來備份" "0" && exit 1
	TXT_NAME="${txt##*/}"
	case ${TXT_NAME##*.} in
	txt) ;;
	*) echoRgb "$txt不是腳本讀取格式" "0" && exit 2 ;;
	esac
	sort -u "$txt" -o "$txt" &>/dev/null
	data="$MODDIR"
	hx="本地"
	echoRgb "腳本受到內核機制影響 息屏後IO性能嚴重影響\n -請勿關閉終端或是息屏備份 如需終止腳本\n -請執行終止腳本.sh即可停止" "3"
	backup_path
	echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -音量鍵確認:$Lo\n -更新:$update\n -備份模式:$Backup_Mode\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -自定義目錄備份:$backup_media\n"
	D="1"
	C="$(sed -e '/^$/d' "$txt" 2>/dev/null | sed -n '$=')"
	[[ $user = 0 ]] && Apk_info="$(appinfo -sort-i -o pn -pn $system -3 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)" || Apk_info="$(appinfo -sort-i -o pn -pn $system $(pm list packages -3 --user "$user" | cut -f2 -d ':') 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	[[ $Apk_info = "" ]] && echoRgb "appinfo輸出失敗" "0" && exit 2
	[[ $backup_mode = "" ]] && {
	echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
	while [[ $D -le $C ]]; do
        name1="$(sed -e '/^$/d' "$txt" 2>/dev/null | sed -n "${D}p" | awk '{print $1}')"
		name2="$(sed -e '/^$/d' "$txt" 2>/dev/null | sed -n "${D}p" | awk '{print $2}')"
		if [[ $name1 != "" && $name2 != "" ]]; then
	        if [[ $(echo "$Apk_info" | egrep -w "^$name2$") != "" ]]; then
			    [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
			    Tmplist="$Tmplist\n$name1 $name2"
			else
                case $name1 in
                *不需要*) ;;
                *) 
                    echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$txt" 2>/dev/null)" >"$txt"
                    echoRgb "$name1 $name2不存在系統，從列表中刪除" "0" ;;
                esac
			fi
	        let D++
		fi
	done
	}
	[[ $Tmplist != ""  ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
	r="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n '$=')"
	[[ $backup_mode != "" ]] && r=1
	[[ $r = "" && $backup_mode = "" ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/生成應用列表.sh" "0" && exit 1
	if [[ $Backup_Mode = true ]]; then
    	[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
    	[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
    fi
	[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
	txt2="$Backup/appList.txt"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/恢復備份.sh ]] && touch_shell "Restore" "$Backup/恢復備份.sh"
	[[ ! -f $Backup/終止腳本.sh ]] && cp -r "$MODDIR/終止腳本.sh" "$Backup/終止腳本.sh"
	[[ ! -f $Backup/重新生成應用列表.sh ]] && touch_shell "dumpname" "$Backup/重新生成應用列表.sh"
	[[ ! -f $Backup/轉換資料夾名稱.sh ]] && touch_shell  "convert" "$Backup/轉換資料夾名稱.sh"
	[[ ! -f $Backup/壓縮檔完整性檢查.sh ]] && touch_shell "check_file" "$Backup/壓縮檔完整性檢查.sh"
	[[ ! -d $Backup/modules ]] && mkdir -p "$Backup/modules" && echoRgb "$Backup/modules已創建成功\n -請按需要自行放置需要恢復時刷入的模塊在內將自動批量刷入" "1"
	[[ -d $Backup/Media ]] && touch_shell "Restore3" "$Backup/恢復自定義資料夾.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	if [[ -d $Backup/tools ]]; then
	    find "$Backup/tools" -maxdepth 1 -type f | while read; do
	        Tools_FILE_NAME="${REPLY##*/}"
	        filesha256="$(sha256sum "$tools_path/$Tools_FILE_NAME" | cut -d" " -f1)"
	        filesha256_1="$(sha256sum "$REPLY" | cut -d" " -f1)"
	        if [[ $filesha256 != $filesha256_1 ]]; then
	            cp -r "$tools_path/$Tools_FILE_NAME" "$REPLY"
	            echoRgb "更新$REPLY"
	        fi
	    done
	fi
	filesize="$(du -s "$Backup" | awk '{print $1}')"
	Quantity=0
	restore_freeze
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	en=118
	echo "$script">"$TMPDIR/scriptTMP" && echo "$script">"$TMPDIR/scriptTMP"
	osn=0; osj=0; osk=0
	#獲取已經開啟的無障礙
	var="$(settings get secure enabled_accessibility_services 2>/dev/null)"
	#獲取預設鍵盤
	keyboard="$(settings get secure default_input_method 2>/dev/null)"
    Set_screen_pause_seconds on
	[[ $(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
	{
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ $backup_mode = "" ]]; then
    		name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
    		name2="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
        else
            name1="$ChineseName"
            name2="$PackageName"
        fi
		[[ $name2 = "" || $name1 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
		apk_path="$(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':')"
		apk_path2="$(echo "$apk_path" | head -1)"
		apk_path2="${apk_path2%/*}"
		if [[ -d $apk_path2 ]]; then
			echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
			echoRgb "備份 $name1 \"$name2\"" "2"
			unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version versionName apk_version2 apk_version3 zsize zmediapath Size data_path userSize dataSize obbSize Ssaid Permissions
			if [[ $Backup_Mode = true ]]; then
			    if [[ $name1 = !* || $name1 = ！* ]]; then
    				name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    				echoRgb "跳過備份所有數據" "0"
    				No_backupdata=1
    			fi
    			if [[ $(echo "$blacklist" | grep -w "$name2") = $name2 ]]; then
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
			app_details="$Backup_folder/app_details"
			app_Permissions="$Backup_folder/Permissions"
			if [[ -f $app_details ]]; then
				. "$app_details" &>/dev/null
				[[ -f $app_Permissions ]] && . "$app_Permissions"
				if [[ $PackageName != $name2 ]]; then
					unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version versionName apk_version2 apk_version3 zsize  zmediapath Size data_path userSize dataSize obbSize Ssaid Permissions
					Backup_folder="$Backup/${name1}[${name2}]"
					app_details="$Backup_folder/app_details"
					app_Permissions="$Backup_folder/Permissions"
					[[ -f $app_details ]] && . "$app_details" &>/dev/null
					[[ -f $app_Permissions ]] && . "$app_Permissions"
				fi
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
        					#備份data數據
        					Backup_data "data"
        					#備份obb數據
        					Backup_data "obb"
        				fi
        				#備份user數據
        				[[ $Backup_user_data = true ]] && Backup_data "user"
        				[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d 2>/dev/null)"
        				[[ $name2 = moe.shizuku.redirectstorage ]] && Backup_data "storage-isolation" "/data/adb/storage-isolation"
        				Set_service
        		    fi
    			fi
    			[[ -f $Backup_folder/${name2}.sh ]] && rm -rf "$Backup_folder/${name2}.sh"
    		    [[ ! -f $Backup_folder/recover.sh ]] && touch_shell "Restore2" "$Backup_folder/recover.sh"
    			[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "backup" "$Backup_folder/backup.sh" "backup_mode" "backup_mode=\"1\""
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
				echo_log "設置鍵盤$(appinfo -d "(" -ed ")" -o anwb,pn -pn "${keyboard%/*}" 2>/dev/null)"
			fi
			[[ $update_apk2 = "" ]] && update_apk2="暫無更新"
			[[ $add_app2 = "" ]] && add_app2="暫無更新"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2\n -包含SSAID的應用\n$SSAID_apk2" "3"
			echo "$(sort "$txt2" | sed -e '/^$/d')" >"$txt2"
			if [[ $backup_media = true && $backup_mode = "" ]]; then
				A=1
				B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					[[ ! -f $Backup/恢復自定義資料夾.sh ]] && touch_shell "Restore3" "$Backup/恢復自定義資料夾.sh"
					[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
					app_details="$Backup_folder/app_details"
					[[ -f $app_details ]] && . "$app_details" &>/dev/null || touch "$app_details"
					mediatxt="$Backup/mediaList.txt"
					[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
					echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed 's/\/$//' | while read; do
						echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
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
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		let i++ en++ nskg++
	done
	#打開應用
	i=1
	am_start="$(echo "$am_start" | xargs | sed 's/ /\n/g')"
	if [[ $backup_mode = "" ]]; then
    	while [[ $i -le $r ]]; do
    		unset pkg name1
    		pkg="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
    		name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
    		if [[ $(echo "$am_start" | egrep -wo "$pkg") = $pkg ]]; then
    			am start -n "$(appinfo -o sa -pn "$pkg" 2>/dev/null)" &>/dev/null
    			echo_log "啟動$name1"
    		fi
    		let i++
    	done
    else
        if [[ $(echo "$am_start" | egrep -wo "$PackageName") = $PackageName ]]; then
            am start -n "$(appinfo -o sa -pn "$PackageName" 2>/dev/null)" &>/dev/null
            echo_log "啟動$name1"
        fi
    fi
	Set_screen_pause_seconds off
	restore_freeze
	rm -rf "$TMPDIR/scriptTMP"
	Calculate_size "$Backup"
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	} &
	wait && exit
	;;
dumpname)
	get_name "Apkname"
	;;
convert)
	get_name "convert"
	;;
check_file)
	Check_archive "$MODDIR"
	;;
Restore|Restore2)
	kill_Serve
	self_test
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	if [[ $operate = Restore ]]; then
    	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/終止腳本.sh\n -否則腳本將繼續執行直到結束" "0"
    	echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/轉換資料夾名稱.sh"
    	txt="$MODDIR/appList.txt"
    	[[ ! -f $txt ]] && echoRgb "請執行\"重新生成應用列表.sh\"獲取應用列表再來恢復" "0" && exit 2
	    sort -u "$txt" -o "$txt" 2>/dev/null
	    i=1
	    r="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n '$=')"
	    [[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行\"重新生成應用列表.sh\"獲取應用列表再來恢復" "0" && exit 1
    	Backup_folder2="$MODDIR/Media"
    	Backup_folder3="$MODDIR/modules"
    	#效驗選填是否正確
    	isBoolean "$Lo" "Lo" && Lo="$nsx"
    	echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
    	get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
    	Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | egrep -o '[0-9]+')"
    	if [[ $Get_user != $user ]]; then
    	    echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同\n -音量上繼續恢復，下不恢復並離開腳本"
    		get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
    	fi
    	if [[ -d $Backup_folder2 ]]; then
    		echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
    		get_version "恢復媒體數據" "跳過恢復媒體數據"
    		media_recovery="$branch"
    		A=1
    		B="$(find "$Backup_folder2" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | wc -l)"
    	fi
    	if [[ -d $Backup_folder3 && $(find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | wc -l) != 0 ]]; then
    		echoRgb "是否刷入Magisk模塊\n -音量上刷入，音量下不刷入" "2"
    		get_version "刷入模塊" "跳過刷入模塊"
    		modules_recovery="$branch"
    	fi
    	[[ $recovery_mode2 = false ]] && exit 2
    	if [[ $recovery_mode = true ]]; then
    		echoRgb "獲取未安裝應用中"
    		TXT="$MODDIR/TEMP.txt"
    		while [[ $i -le $r ]]; do
    			name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
    			name2="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
    			if [[ $(pm list packages --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':') = "" ]]; then
    				echo "$name1 $name2">>"$TXT"
    			fi
    			let i++
    		done
    		i=1
    		sort -u "$TXT" -o "$TXT" 2>/dev/null
    		r="$(grep -v "#" "$TXT" 2>/dev/null | sed -e '/^$/d' | sed -n '$=')"
    		if [[ $r != "" ]]; then
    			echoRgb "獲取完成 預計安裝$r個應用"
    			txt="$TXT"
    		else
    			echoRgb "獲取完成 但備份內應用都已安裝....正在退出腳本" "0" && exit 0
    		fi
    	fi
    	DX="批量恢復"
    else
        i=1
        r=1
        Backup_folder="$MODDIR"
	    app_details="$Backup_folder/app_details"
	    app_Permissions="$Backup_folder/Permissions"
	    if [[ ! -f $app_details ]]; then
		    echoRgb "$app_details遺失，無法獲取包名" "0" && exit 1
	    else
		    . "$app_details" &>/dev/null
		    [[ -f $app_Permissions ]] && . "$app_Permissions" &>/dev/null
	    fi
	    name1="$ChineseName"
	    [[ $name1 = "" ]] && name1="${Backup_folder##*/}"
	    [[ $name1 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
	    name2="$PackageName"
	    [[ $name2 = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
	    DX="單獨恢復"
    fi
	#開始循環$txt內的資料進行恢復
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	Set_screen_pause_seconds on
	en=118
	echo "$script">"$TMPDIR/scriptTMP"
	{
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ $operate = Restore ]]; then
		    echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
		    name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
		    name2="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
		    unset No_backupdata apk_version Permissions
		    if [[ $name1 = *! || $name1 = *！ ]]; then
			    name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    			echoRgb "跳過恢復$name1 所有數據" "0"
    			No_backupdata=1
    		fi
    		Backup_folder="$MODDIR/$name1"
    		[[ -f "$Backup_folder/app_details" ]] && app_details="$Backup_folder/app_details" . "$Backup_folder/app_details" &>/dev/null
    		app_Permissions="$Backup_folder/Permissions"
    		[[ -f $app_Permissions ]] && . "$app_Permissions" &>/dev/null
    		[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
		fi
		if [[ -d $Backup_folder ]]; then
			echoRgb "恢復$name1 ($name2)" "2"
			starttime2="$(date -u "+%s")"
			if [[ $(pm path --user "$user" "$name2" 2>/dev/null) = "" ]]; then
				installapk
			else
		        [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]] && installapk && [[ $? = 0 ]] && echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
			fi
			if [[ $(pm path --user "$user" "$name2" 2>/dev/null) != "" ]]; then
				if [[ $No_backupdata = "" ]]; then
					kill_app
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read; do
						Release_data "$REPLY"
					done
					unset G
					Set_service
					restore_permissions
					if [[ $Ssaid != "" ]]; then
					    if [[ $(get_ssaid "$name2") != $Ssaid ]]; then
					        set_ssaid "$name2" "$Ssaid"
					        if [[ $(get_ssaid "$name2") = $Ssaid ]]; then
					            echoRgb "SSAID恢復成功" "1"
					            SSAID_Package="$(echo "$name1 \"$name2\"")"
				                SSAID_Package2="$(echo "$SSAID_Package\n$SSAID_Package2")"
					        else
					            echoRgb "SSAID恢復失敗" "0"
					            SSAID_Package1="$(echo "$name1 \"$name2\"")"
				                SSAID_Package3="$(echo "$SSAID_Package1\n$SSAID_Package3")"
					        fi
					    fi
					    unset Ssaid
					fi
				fi
			else
				[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
			fi
			endtime 2 "$name1恢復" "2" && echoRgb "完成$((i * 100 / r))%" "3"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
		else
			echoRgb "$Backup_folder資料夾遺失，無法恢復" "0"
		fi
		if [[ $i = $r && $operate != Restore2 ]]; then
		    endtime 1 "應用恢復" "2"
		    echoRgb "\n -下列為已設置SSAID應用\n$SSAID_Package2\n -下列為設置SSAID失敗應用....\n$SSAID_Package3" "3"
			if [[ $media_recovery = true ]]; then
			    starttime1="$(date -u "+%s")"
			    app_details="$Backup_folder2/app_details"
			    txt="$MODDIR/mediaList.txt"
			    sort -u "$txt" -o "$txt" 2>/dev/null
			    A=1
	            B="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n '$=')"
                [[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行\"重新生成應用列表.sh\"獲取列表再來恢復" "0" && B=0
				while [[ $A -le $B ]]; do
		            name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		            starttime2="$(date -u "+%s")"
		            echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		            Release_data "$Backup_folder2/$name1"
		            endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
                done
				endtime 1 "自定義恢復" "2"
			fi
			if [[ $modules_recovery = true ]]; then
			    A=1
		        B="$(find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | wc -l)"
		        starttime1="$(date -u "+%s")"
		        find "$Backup_folder3" -maxdepth 1 -name "*.zip*" -type f 2>/dev/null | while read; do
					starttime2="$(date -u "+%s")"
					echoRgb "刷入第$A/$B個模塊 剩下$((B - A))個" "3"
					echoRgb "刷入${REPLY##*/}" "2"
					magisk --install-module "$REPLY"
					endtime 2 "${REPLY##*/}刷入" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
				done
				endtime 1 "刷入模塊" "2"
			fi
		fi
		let i++ en++ nskg++
	done
	restore_freeze
	rm -rf "$TMPDIR/scriptTMP" "$TXT"
	Set_screen_pause_seconds off
	starttime1="$TIME"
	echoRgb "$DX完成" && endtime 1 "$DX開始到結束" && [[ $SSAID_Package2 != "" ]] && echoRgb "SSAID恢復後必須重啟套用,如發現應用閃退請重新開機" "0"
	rm -rf "$TMPDIR"/*
	} &
	wait && exit
	;;
Restore3)
	kill_Serve
	self_test
	echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -音量上繼續恢復自定義資料夾，音量下離開腳本" "2"
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊終止腳本.sh,否則腳本將繼續執行直到結束" "0"
	get_version "恢復自定義資料夾" "離開腳本" && [[ "$branch" = false ]] && exit 0
	mediaDir="$MODDIR/Media"
	[[ -f "$mediaDir/app_details" ]] && app_details="$mediaDir/app_details" &>/dev/null
	Backup_folder2="$mediaDir"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行\"重新生成應用列表.sh\"獲取媒體列表再來恢復" "0" && exit 2
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
	B="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n '$=')"
	Set_screen_pause_seconds off
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行\"重新生成應用列表.sh\"獲取列表再來恢復" "0" && exit 1
	echo "$script">"$TMPDIR/scriptTMP"
	{
	while [[ $A -le $B ]]; do
		name1="$(grep -v "#" "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	rm -rf "$TMPDIR/scriptTMP"
	} &
	;;
Getlist)
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內生成列表" "0" && exit 2 ;;
	esac
	#效驗選填是否正確
	isBoolean "$debug_list" "debug_list" && debug_list="$nsx"
	isBoolean "$Lo" "Lo" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		[[ $blacklist_mode != "" ]] && isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx" || {
		echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔" "2"
		get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
		}
	else
		if [[ $(echo "$blacklist" | grep -v "#" | wc -l) -gt 0 ]]; then
		    [[ $blacklist_mode = "" ]] && {
		    echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔" "2"
		    get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
		    } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		fi
	fi
	txtpath="$MODDIR"
	[[ $debug_list = true ]] && txtpath="${txtpath/'/storage/emulated/'/'/data/media/'}"
	nametxt="$txtpath/appList.txt"
	[[ ! -f $nametxt ]] && echo '#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）' >"$nametxt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	starttime1="$(date -u "+%s")"
	echoRgb "提示! 腳本默認會屏蔽預裝應用 如需備份請添加預裝應用白名單" "0"
	xposed_name="$(appinfo -o pn -xm)"
	Apk_info="$(appinfo -sort-i -d " " -o addXpTag:'Xposed: ',anwb,pn -pn $system -3 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	appinfo -sort-i -d " " -o addXpTag:'Xposed: ',anwb,pn -pn $system -3 | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u
	exit 2 ; } || Apk_info="$(echo "$Apk_info" | sed 's/Xposed: //g')" && Apk_info2="$(echo "$Apk_info" | awk '{print $2}')"
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	rb="0"
	Output_list() {
	    if [[ $(cat "$nametxt" | cut -f2 -d ' ' | egrep -w "^${app_1[1]}$") != ${app_1[1]} ]]; then
	        case ${app_1[1]} in
			    *oneplus* | *miui* | *xiaomi* | *oppo* | *flyme* | *meizu* | com.android.soundrecorder | com.mfashiongallery.emag | com.mi.health | *coloros*)
				    if [[ $(echo "$xposed_name" | egrep -w "${app_1[1]}$") = ${app_1[1]} ]]; then
    				    echoRgb "${app_1[2]}為Xposed模塊 進行添加" "0"
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
						    echoRgb "$REPLY($rgb_a)"
						    let i++
					    else
						    echoRgb "${app_1[2]} 預裝應用 忽略輸出" "0"
						    let rc++
					    fi
				    fi
				    ;;
			    *)
			        if [[ $(echo "$xposed_name" | egrep -w "${app_1[1]}$") = ${app_1[1]} ]]; then
			            echoRgb "Xposed: $REPLY($rgb_a)"
			            let rd++
			        else
				        echoRgb "$REPLY($rgb_a)"
				    fi
				    if [[ $REPLY2 = "" ]]; then
					    REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					else
					    REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					fi
				    let i++
				    ;;
			esac
		else
	        let Q++
        fi
    }
	echo "$Apk_info" | sed 's/\///g ; s/\://g ; s/(//g ; s/)//g ; s/\[//g ; s/\]//g ; s/\-//g ; s/!//g' | while read; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_1=($REPLY $REPLY)
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
		if [[ $LR = $Apk_Quantity ]]; then
		    echo "$REPLY2">>"$nametxt"
			if [[ $(cat "$nametxt" | wc -l | awk '{print $1-2}') -lt $i ]]; then
				rm -rf "$nametxt"
				echoRgb "\n -輸出異常 請將$conf_path中的debug_list=\"0\"改為1或是重新執行本腳本" "0"
				exit
			fi
			[[ $tmp != "" ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let rgb_a++ LR++
	done
	if [[ -f $nametxt ]]; then
		D="1"
		C="$(sed -e '/^$/d' "$nametxt" | sed -n '$=')"
		while [[ $D -le $C ]]; do
			name1="$(sed -e '/^$/d' "$nametxt" | sed -n "${D}p" | awk '{print $1}')"
			name2="$(sed -e '/^$/d' "$nametxt" | sed -n "${D}p" | awk '{print $2}')"
			if [[ $name1 != "" && $name2 != "" ]]; then
			    if [[ $(echo "$Apk_info2" | egrep -w "^$name2$") != "" ]]; then
			        [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
			        Tmplist="$Tmplist\n$name1 $name2"
			    else
                    case $name1 in
                    *不需要*) ;;
                    *) echoRgb "$name1 $name2不存在系統，從列表中刪除" "0" ;;
                    esac
			    fi
			    let D++
			fi
		done
		[[ $Tmplist != "" ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$nametxt"
	fi
	wait
	endtime 1
	echoRgb "輸出包名結束 請查看$nametxt"
	;;
backup_media)
	kill_Serve
	self_test
	backup_path
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊終止腳本.sh,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		[[ ! -f $Backup/恢復自定義資料夾.sh ]] && touch_shell "Restore3" "$Backup/恢復自定義資料夾.sh"
		[[ ! -f $Backup/重新生成應用列表.sh ]] && touch_shell "dumpname" "$Backup/重新生成應用列表.sh"
		[[ ! -f $Backup/轉換資料夾名稱.sh ]] && touch_shell  "convert" "$Backup/轉換資料夾名稱.sh"
		[[ ! -f $Backup/壓縮檔完整性檢查.sh ]] && touch_shell "check_file" "$Backup/壓縮檔完整性檢查.sh"
		[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
		[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
		app_details="$Backup_folder/app_details"
		filesize="$(du -s "$Backup_folder" | awk '{print $1}')"
		[[ -f $app_details ]] && . "$app_details" &>/dev/null || touch "$app_details"
		mediatxt="$Backup/mediaList.txt"
		[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
		echo "$script">"$TMPDIR/scriptTMP"
		Set_screen_pause_seconds on
		{
		echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed 's/\/$//' | while read; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
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
			echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
		done
		} &
		wait
		Calculate_size "$Backup_folder"
		Set_screen_pause_seconds off
		endtime 1 "自定義備份"
		rm -rf "$TMPDIR/scriptTMP"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	;;
Device_List)
    URL="https://khwang9883.github.io/MobileModels/brands"
    rm -rf "$tools_path/Device_List"
    for i in $(echo "xiaomi\nsamsung\nasus\nBlack_Shark\ngoogle\nLenovo\nMEIZU\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nSony"); do
        echoRgb "獲取品牌$i"
        case $i in
        xiaomi) Brand_URL="$URL/xiaomi.html" ;;
        samsung) Brand_URL="$URL/samsung_cn.html" ;;
        asus) Brand_URL="$URL/asus.html" ;;
        Black_Shark) Brand_URL="$URL/blackshark.html" ;;
        google) Brand_URL="$URL/google.html" ;;
        Lenovo) Brand_URL="$URL/lenovo.html" ;;
        MEIZU) Brand_URL="$URL/meizu.html" ;;
        Motorola) Brand_URL="$URL/motorola.html" ;;
        Nokia) Brand_URL="$URL/nokia.html" ;;
        nothing) Brand_URL="$URL/nothing.html" ;;
        nubia) Brand_URL="$URL/nubia.html" ;;
        OnePlus) Brand_URL="$URL/oneplus.html" ;;
        Sony) Brand_URL="$URL/sony_cn.html" ;;
        esac
        down -s -L "$Brand_URL" | sed -n 's/.*<code class="language-plaintext highlighter-rouge">\([^<]*\)<\/code>: \(.*\)<\/p>.*/\1\n\2/p' | sed 's/\(.*\)/"\1"/' | sed 'N;s/\n/ /'>>"$tools_path/Device_List"
    done
    if [[ -e $tools_path/Device_List ]]; then
        if [[ $(ls -l "$tools_path/Device_List" | awk '{print $5}') -gt 1 ]]; then
    		[[ $shell_language = zh-TW ]] && ts -f "$tools_path/Device_List" -o "$tools_path/Device_List"
            echoRgb "已下載機型列表在$tools_path/Device_List"
        else
            echoRgb "下載機型失敗"
        fi
    else
        echoRgb "下載機型失敗"
    fi ;;
esac
