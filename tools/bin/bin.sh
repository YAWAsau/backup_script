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
	[[ $Status_log != "" ]] && echo " -$(date '+%T') $1" >>"$Status_log"
}
[ "$rgb_a" = "" ] && rgb_a=214
if [ "$(whoami)" != root ]; then
	echoRgb "你是憨批？不給Root用你媽 爬" "0"
	exit 1
fi
abi="$(getprop ro.product.cpu.abi)"
case $abi in
arm64*)
	if [[ $(getprop ro.build.version.sdk) -lt 26 ]]; then
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
PATH="/sbin/.magisk/busybox:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/data/Han.GJZS/files/usr/busybox:/data/data/Han.GJZS/files/usr/bin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
if [[ -d $(magisk --path 2>/dev/null) ]]; then
	PATH="$(magisk --path)/.magisk/busybox:$PATH"
else
	echo "Magisk busybox Path does not exist"
fi
export PATH="$PATH"
backup_version="V15.5.4"
#設置二進制命令目錄位置
if [[ $bin_path = "" ]]; then
	echoRgb "未正確指定bin.sh位置" "0"
	exit 2
fi
#bin_path="${bin_path/'/storage/emulated/'/'/data/media/'}"
Status_log="$MODDIR/Log.txt"
rm -rf "$Status_log"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$bin_path/busybox"
#排除自身
exclude="
update
busybox_path
bin.sh"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echoRgb "設置busybox環境中"
fi
[[ ! -f $bin_path/busybox_path ]] && touch "$bin_path/busybox_path"
if [[ $filepath != $(cat "$bin_path/busybox_path") ]]; then
	[[ -d $(cat "$bin_path/busybox_path") ]] && rm -rf "$(cat "$bin_path/busybox_path")"
	echoRgb "$filepath" >"$bin_path/busybox_path"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -d $bin_path ]]; then
	if [[ -f $busybox && -f $busybox2 ]]; then
		filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echoRgb "busybox sha256不一致 重新創立環境中"
			rm -rf "$filepath"/*
		fi
	fi
	find "$bin_path" -maxdepth 1 ! -path "$bin_path/tools.sh" -type f | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read; do
		File_name="${REPLY##*/}"
		if [[ ! -f $filepath/$File_name ]]; then
			cp -r "$REPLY" "$filepath"
			chmod 0777 "$filepath/$File_name"
			echoRgb "$File_name > $filepath/$File_name"
		else
			filesha256="$(sha256sum "$filepath/$File_name" | cut -d" " -f1)"
			filesha256_1="$(sha256sum "$bin_path/$File_name" | cut -d" " -f1)"
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
else
	echoRgb "遺失$bin_path" "0"
	exit 1
fi
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
TMPDIR="/data/local/tmp"
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools/bin內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
#下列為自定義函數
Set_back() {
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
stopscript() {
	if [[ -f $TMPDIR/STOP_script ]]; then
		echoRgb "停止腳本"
		longToast "停止腳本"
		Print "腳本被終止-停止腳本"
		rm -rf "$TMPDIR/STOP_script"
		exit
	fi
}
nskg=1
Print() {
	a=$(echo "backup-$(date '+%T')" | sed 's#/#{xiegang}#g')
	b=$(echo "$1" | sed 's#/#{xiegang}#g')
	content query --uri content://ice.message/notify/"$nskg<|>$a<|>$b<|>bs" >/dev/null 2>&1
}
longToast() {
	content query --uri content://ice.message/long/"$*" >/dev/null 2>&1
}
get_version() {
	while :; do
		keycheck
		case $? in
		42)
			branch=true
			echoRgb "$1" "1"
			;;
		41)
			branch=false
			echoRgb "$2" "0"
			;;
		*)
			echoRgb "keycheck錯誤" "0"
			continue
			;;
		esac
		sleep 1.2
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
		echoRgb "$MODDIR_NAME/backup_settings.conf $2=$1填寫錯誤，正確值1or0" "0"
		exit 2
	fi
}
echo_log() {
	if [[ $? = 0 ]]; then
		echoRgb "$1成功" "1"
		result=0
	else
		echoRgb "$1失敗，過世了" "0"
		Print "$1失敗，過世了"
		result=1
	fi
}
process_name() {
	pgrep -f "$1" | while read; do
		kill -KILL "$REPLY" 2>/dev/null
	done
}
kill_Serve() {
	{
	script="${0##*/}"
	if [[ $script != "" ]]; then
		process_name tar
		process_name pv
	fi
	} &
	wait
}
ykj() {
	# uptime
	awk -F '.' '{run_days=$1 / 86400;run_hour=($1 % 86400)/3600;run_minute=($1 % 3600)/60;run_second=$1 % 60;printf("%d天%d时%d分%d秒",run_days,run_hour,run_minute,run_second)}' /proc/uptime
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
Open_apps="$(appinfo -d "(" -ed ")" -o ands,pn -ta c 2>/dev/null)"
Open_apps2="$(echo "$Open_apps" | cut -f2 -d '(' | sed 's/)//g')"
raminfo="$(awk '($1 == "MemTotal:"){print $2/1000"MB"}' /proc/meminfo 2>/dev/null)"
echoRgb "---------------------SpeedBackup---------------------"
echoRgb "-當前腳本執行路徑:$MODDIR\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -Magisk版本:$(cat "/data/adb/magisk/util_functions.sh" 2>/dev/null | grep "MAGISK_VER_CODE" | cut -f2 -d '=')\n -設備架構:$abi\n -品牌:$(getprop ro.product.brand 2>/dev/null)\n -設備代號:$(getprop ro.product.device 2>/dev/null)\n -型號:$(getprop ro.product.model 2>/dev/null)\n -RAM:$raminfo\n -閃存類型:$ROM_TYPE\n -閃存顆粒:$UFS_MODEL\n -Android版本:$(getprop ro.build.version.release 2>/dev/null) SDK:$(getprop ro.build.version.sdk 2>/dev/null)\n -終端:$Open_apps\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
update_script() {
	[[ $zipFile = "" ]] && zipFile="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)"
	if [[ $zipFile != "" ]]; then
		case $(echo "$zipFile" | wc -l) in
		1)
			echoRgb "從$zipFile更新"
			if [[ $(unzip -l "$zipFile" | awk '{print $4}' | grep -oE "^backup_settings.conf$") = "" ]]; then
				echoRgb "${zipFile##*/}並非指定的備份zip，請刪除後重新放置\n -何謂更新zip? 就是GitHub release頁面下載的zip" "0"
			else
				cp -r "$tools_path" "$TMPDIR" && rm -rf "$tools_path"
				find "$MODDIR" -maxdepth 3 -name "*.sh" -type f -exec rm -rf {} \;
				unzip -o "$zipFile" -x "backup_settings.conf" -d "$MODDIR"
				echo_log "解壓縮${zipFile##*/}"
				if [[ $result = 0 ]]; then
					case $MODDIR in
					*Backup_*)
						if [[ -f $MODDIR/app_details ]]; then
							mv "$MODDIR/tools" "${MODDIR%/*}"
							echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+外部tools目錄與腳本"
							cp -r "$tools_path/script/Get_DirName" "${MODDIR%/*}/重新生成應用列表.sh"
							cp -r "$tools_path/script/convert" "${MODDIR%/*}/轉換資料夾名稱.sh"
							cp -r "$tools_path/script/check_file" "${MODDIR%/*}/壓縮檔完整性檢查.sh"
							cp -r "$tools_path/script/restore" "${MODDIR%/*}/恢復備份.sh"
							cp -r "$MODDIR/終止腳本.sh" "${MODDIR%/*}/終止腳本.sh"
							[[ -d ${MODDIR%/*}/Media ]] && cp -r "$tools_path/script/restore3" "${MODDIR%/*}/恢復自定義資料夾.sh"
							find "${MODDIR%/*}" -maxdepth 1 -type d | sort | while read; do
								if [[ -f $REPLY/app_details ]]; then
									unset PackageName
									. "$REPLY/app_details" &>/dev/null
									if [[ $PackageName != "" ]]; then
										cp -r "$tools_path/script/restore2" "$REPLY/$PackageName.sh"
									else
										if [[ ${REPLY##*/} != Media ]]; then
											NAME="${REPLY##*/}"
											NAME="${NAME%%.*}"
											[[ $NAME != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/$NAME.sh"
										fi
									fi
								fi
							done
							if [[ -d ${MODDIR%/*/*}/tools && -f ${MODDIR%/*/*}/備份應用.sh ]]; then
								echoRgb "更新${MODDIR%/*/*}/tools與備份相關腳本"
								rm -rf "${MODDIR%/*/*}/tools"
								find "${MODDIR%/*/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
								mv "$MODDIR/備份應用.sh" "$MODDIR/生成應用列表.sh" "$MODDIR/備份自定義資料夾.sh" "$MODDIR/終止腳本.sh" "${MODDIR%/*/*}"
								cp -r "$tools_path" "${MODDIR%/*/*}"
							fi
							rm -rf "$MODDIR/終止腳本.sh"
						else
							echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+tools目錄"
							cp -r "$tools_path/script/Get_DirName" "$MODDIR/重新生成應用列表.sh"
							cp -r "$tools_path/script/convert" "$MODDIR/轉換資料夾名稱.sh"
							cp -r "$tools_path/script/check_file" "$MODDIR/壓縮檔完整性檢查.sh"
							cp -r "$tools_path/script/restore" "$MODDIR/恢復備份.sh"
							[[ -d $MODDIR/Media ]] && cp -r "$tools_path/script/restore3" "$MODDIR/恢復自定義資料夾.sh"
							find "$MODDIR" -maxdepth 1 -type d | sort | while read; do
								if [[ -f $REPLY/app_details ]]; then
									unset PackageName
									. "$REPLY/app_details" &>/dev/null
									if [[ $PackageName != "" ]]; then
										cp -r "$tools_path/script/restore2" "$REPLY/$PackageName.sh"
									else
										if [[ ${REPLY##*/} != Media ]]; then
											NAME="${REPLY##*/}"
											NAME="${NAME%%.*}"
											[[ $NAME != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/$NAME.sh"
										fi
									fi
								fi
							done
							if [[ -d ${MODDIR%/*}/tools && -f ${MODDIR%/*}/備份應用.sh ]]; then
								echoRgb "更新${MODDIR%/*}/tools與備份相關腳本"
								rm -rf "${MODDIR%/*}/tools"
								find "${MODDIR%/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
								cp -r "$MODDIR/備份應用.sh" "$MODDIR/終止腳本.sh" "$MODDIR/生成應用列表.sh" "$MODDIR/備份自定義資料夾.sh" "${MODDIR%/*}"
								cp -r "$tools_path" "${MODDIR%/*}"
							fi
						fi
						rm -rf "$MODDIR/備份自定義資料夾.sh" "$MODDIR/生成應用列表.sh" "$MODDIR/備份應用.sh" "$tools_path/script"
						;;
					*)
						if [[ $(find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d) != "" ]]; then
							find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d | while read backup_path; do
								if [[ -d $backup_path && $backup_path != $MODDIR ]]; then
									echoRgb "更新當前目錄下備份相關腳本&tools目錄+${backup_path##*/}內tools目錄+恢復腳本+tools"
									rm -rf "$backup_path/tools"
									cp -r "$tools_path" "$backup_path" && rm -rf "$backup_path/tools/bin/zip" "$backup_path/tools/script"
									cp -r "$tools_path/script/restore" "$backup_path/恢復備份.sh"
									cp -r "$tools_path/script/Get_DirName" "$backup_path/重新生成應用列表.sh"
									cp -r "$tools_path/script/convert" "$backup_path/轉換資料夾名稱.sh"
									cp -r "$tools_path/script/check_file" "$backup_path/壓縮檔完整性檢查.sh"
									cp -r "$MODDIR/終止腳本.sh" "$backup_path/終止腳本.sh"
									[[ -d $backup_path/Media ]] && cp -r "$tools_path/script/restore3" "$backup_path/恢復自定義資料夾.sh"
									find "$MODDIR" -maxdepth 2 -type d | sort | while read; do
										if [[ -f $REPLY/app_details ]]; then
											unset PackageName
											. "$REPLY/app_details" &>/dev/null
											if [[ $PackageName != "" ]]; then
												cp -r "$tools_path/script/restore2" "$REPLY/$PackageName.sh"
											else
												if [[ ${REPLY##*/} != Media ]]; then
													NAME="${REPLY##*/}"
													NAME="${NAME%%.*}"
													[[ $NAME != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/$NAME.sh"
												fi
											fi
										fi
									done
								fi
							done
						else
							echoRgb "更新當前${MODDIR##*/}目錄下備份相關腳本+tools目錄"
						fi
						;;
					esac
				else
					cp -r "$TMPDIR/tools" "$MODDIR"
				fi
				rm -rf "$TMPDIR"/*
				rm -rf "$zipFile"
				echoRgb "更新完成 請重新執行腳本" "2"
				exit
			fi
			;;
		*)
			echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zipFile" "0"
			exit 1
			;;
		esac
	fi
	unset NAME
}
update_script