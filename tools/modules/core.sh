rgb_a="${rgb_a:=214}"
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
    trap "rm -rf '$LOCK_DIR'" EXIT
}
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
