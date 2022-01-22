test "$(whoami)" != root && echo "你是憨批？不給Root用你媽 爬" && exit 1
abi="$(getprop ro.product.cpu.abi)"
case $abi in
arm64*)
	[[ $(getprop ro.build.version.sdk) -lt 28 ]] && echo "設備Android $(getprop ro.build.version.release)版本過低 請升級至Android 9+" && exit 1
	;;
*)
	echo "-未知的架構: $abi"
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
backup_version="V13.8"
#設置二進制命令目錄位置
[[ $bin_path = "" ]] && echo "未正確指定bin.sh位置" && exit 2
#bin_path="${bin_path/'/storage/emulated/'/'/data/media/'}"
Status_log="$MODDIR/Log.txt"
rm -rf "$Status_log"
filepath="/data/backup_tools"
if [[ $APP_ENV = 1 ]]; then
	filepath="/data/user/0/com.xayah.databackup/backup_tools"
fi
busybox="$filepath/busybox"
busybox2="$bin_path/busybox"
#排除自身
exclude="
update
busybox_path
update
bin.sh"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echo "設置busybox環境中"
fi
[[ ! -f $bin_path/busybox_path ]] && touch "$bin_path/busybox_path"
if [[ $filepath != $(cat "$bin_path/busybox_path") ]]; then
	[[ -d $(cat "$bin_path/busybox_path") ]] && rm -rf "$(cat "$bin_path/busybox_path")"
	echo "$filepath" >"$bin_path/busybox_path"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -d $bin_path ]]; then
	if [[ -f $busybox && -f $busybox2 ]]; then
		filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echo "busybox sha256不一致 重新創立環境中"
			rm -rf "$filepath"/*
		fi
	fi
	find "$bin_path" -maxdepth 1 ! -path "$bin_path/tools" -type f | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read; do
		File_name="${REPLY##*/}"
		if [[ ! -f $filepath/$File_name ]]; then
			cp -r "$REPLY" "$filepath"
			chmod 0777 "$filepath/$File_name"
			echo "$File_name > $filepath/$File_name"
		else
			filesha256="$(sha256sum "$filepath/$File_name" | cut -d" " -f1)"
			filesha256_1="$(sha256sum "$bin_path/$File_name" | cut -d" " -f1)"
			if [[ $filesha256 != $filesha256_1 ]]; then
				echo "$File_name sha256不一致 重新創建"
				cp -r "$REPLY" "$filepath"
				chmod 0777 "$filepath/$File_name"
				echo "$File_name > $filepath/$File_name"
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
	echo "遺失$bin_path"
	exit 1
fi
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
TMPDIR="/data/local/tmp"
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
if [[ $(which busybox) = "" ]]; then
	echo "環境變量中沒有找到busybox 請在tools/bin內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...."
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
nskg=1
Print() {
	notify "$nskg" "backup-$(date '+%T')" "$1" bs
}
echoRgb() {
	#轉換echo顏色提高可讀性
	if [[ $2 = 0 ]]; then
		echo -e "\e[38;5;197m -$1\e[0m"
	elif [[ $2 = 1 ]]; then
		echo -e "\e[38;5;121m -$1\e[0m"
	elif [[ $2 = 2 ]]; then
		echo -e "\e[38;5;223m -$1\e[0m"
	elif [[ $2 = 3 ]]; then
		echo -e "\e[38;5;220m -$1\e[0m"
	else
		echo -e "\e[38;5;${bn}m -$1\e[0m"
	fi
	echo " -$(date '+%T') $1" >>"$Status_log"
}
bn=1
l=300 
debug() {
	while [[ $bn -le $l ]]; do
		echoRgb "色號$bn\n  -當前腳本執行路徑:/data/user/0/com.xayah.databackup/scripts
		 -busybox路徑:/data/user/0/com.xayah.databackup/backup_tools/busybox
		 -busybox版本:v1.34.1-osm0sis
		 -appinfo版本:2021-12-08（84） "
		let bn++
	done
}
# debug
get_version() {
	while :; do
		version="$(getevent -qlc 1 | awk '{ print $3 }')"
		case $version in
		KEY_VOLUMEUP)
			branch=true
			echoRgb "$1" "1"
			;;
		KEY_VOLUMEDOWN)
			branch=false
			echoRgb "$2" "0"
			;;
		*)
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
		echoRgb "$MODDIR/backup_settings.conf $2=$1填寫錯誤，正確值1or0" "0" && exit 2
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
ykj() {
	# uptime
	awk -F '.' '{run_days=$1 / 86400;run_hour=($1 % 86400)/3600;run_minute=($1 % 3600)/60;run_second=$1 % 60;printf("%d天%d时%d分%d秒",run_days,run_hour,run_minute,run_second)}' /proc/uptime
}
[[ -f /sys/block/sda/size ]] && ROM_TYPE="UFS" || ROM_TYPE="eMMC"
if [[ -f /proc/scsi/scsi ]]; then
	UFS_MODEL="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $2}')"
	Particles="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $4}')"
else
	UFS_MODEL="unknown"
fi
#-閃存類型:$ROM_TYPE
#-閃存顆粒:$UFS_MODEL $Particles
Open_apps="$(appinfo -d "(" -ed ")" -o ands,pn -ta c)"
Open_apps2="$(echo "$Open_apps" | cut -f2 -d '(' | sed 's/)//g')"
bn=214
echoRgb "\n --------------###############--------------\n -當前腳本執行路徑:$MODDIR\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -Magisk版本:$(cat "/data/adb/magisk/util_functions.sh" 2>/dev/null | grep "MAGISK_VER_CODE" | cut -f2 -d '=')\n -設備架構:$abi\n -品牌:$(getprop ro.product.brand 2>/dev/null)\n -設備代號:$(getprop ro.product.device 2>/dev/null)\n -型號:$(getprop ro.product.model 2>/dev/null)-$(getprop ro.serialno 2>/dev/null)\n -RAM:$(cat /proc/meminfo 2>/dev/null | head -n 1 | awk '{print $2/1000"MB"}' 2>/dev/null)\n -閃存類型:$ROM_TYPE\n -閃存顆粒:$UFS_MODEL $Particles\n -Android版本:$(getprop ro.build.version.release 2>/dev/null)\n -SDK:$(getprop ro.build.version.sdk 2>/dev/null)\n -終端:$Open_apps"
bn=117
if [[ $(pm path ice.message) = "" ]]; then
	echoRgb "未安裝toast 開始安裝" "0"
	cp -r "${bin_path%/*}/apk"/*.apk "$TMPDIR" && pm install --user 0 -r "$TMPDIR"/*.apk &>/dev/null && rm -rf "$TMPDIR"/*
	[[ $? = 0 ]] && echoRgb "安裝toast成功" "1" || echoRgb "安裝toast失敗" "0"
fi
#sed -r -n 's/.*"tag_name": *"(.*)".*/\1/p'
#sed -r -n 's/.*"browser_download_url": *"(.*-linux64\..*\.so\.bz2)".*/\1/p'
cdn=2
download_zip() {
	case $cdn in
	1)
		zip_url="http://huge.cf/download/?huge-url=$download"
		NJ="huge.cf"
		;;
	2)
		zip_url="https://ghproxy.com/$download"
		NJ="ghproxy.com"
		;;
	3)
		zip_url="https://gh.api.99988866.xyz/$download"
		NJ="gh.api.99988866.xyz"
		;;
	4)
		zip_url="https://github.lx164.workers.dev/$download"
		NJ="github.lx164.workers.dev"
		;;
	5)
		zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download"
		NJ="shrill-pond-3e81.hunsh.workers.dev"
		;;
	esac
	echoRgb "中轉供應商:${NJ}\n -Download_url:$zip_url"
	curl -O "$zip_url" || down -s -L -o "$MODDIR/${download##*/}" "$zip_url"
	echo_log "下載${download##*/}"
}
if [[ -e $bin_path/update ]]; then
	#settings get system system_locales
	LANG="$(getprop "persist.sys.locale")"
	zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
	echoRgb "檢查更新中 請稍後......."
	Language="https://api.github.com/repos/Petit-Abba/backup_script_zh-CN/releases/latest"
	if [[ $LANG != "" ]]; then
		case $LANG in
		*-TW | *-tw)
			echoRgb "系統語系:繁體中文"
			Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
			;;
		*-CN | *-cn)
			echoRgb "系統語系:簡體中文"
			;;
		*)
			echoRgb "$LANG不支持 默認簡體中文" "0"
			;;
		esac
	else
		echoRgb "獲取系統語系失敗 默認簡體中文" "0"
	fi
	dns="8.8.8.8"
	#dns="223.5.5.5,223.6.6.6"
	# Curl uses boringssl - first appeared in Marshmallow - don't try using ssl in older android versions
	#flag="https://dns.alidns.com/dns-query"
	[[ $(getprop ro.build.version.sdk) -lt 23 ]] && alias curl="curl -kL --dns-servers $dns$flag" || alias curl="curl -L --dns-servers $dns$flag"
	echoRgb "DNS:$dns"
	json="$(curl "$Language" 2>/dev/null)"
	if [[ $json != "" ]]; then
		echoRgb "使用curl"
	else
		json="$(down -s -L "$Language" 2>/dev/null)"
		[[ $json != "" ]] && echoRgb "使用down"
	fi
	if [[ $json != "" ]]; then
		tag="$(echo "$json" | sed -r -n 's/.*"tag_name": *"(.*)".*/\1/p')"
		if [[ $backup_version != $tag ]]; then
			echoRgb "發現新版本 從GitHub更新 版本:$tag\n -更新日誌:\n$(curl "https://api.github.com/repos/YAWAsau/backup_script/releases/latest" 2>/dev/null | sed -r -n 's/.*"body": *"(.*)".*/\1/p' || down -s -L "https://api.github.com/repos/YAWAsau/backup_script/releases/latest" 2>/dev/null | sed -r -n 's/.*"body": *"(.*)".*/\1/p')"
			download="$(echo "$json" | sed -r -n 's/.*"browser_download_url": *"(.*.zip)".*/\1/p')"
			download_zip
			if [[ $result = 0 ]]; then
				echoRgb "update $backup_version > $tag"
				zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
				GitHub="true"
			else
				echoRgb "嘗試更換cdn直到下載成功"
				unset result
				n=0
				while [[ $result != 0 && n != 6 ]]; do
					let cdn++ n++
					download_zip
					sleep 0.5
				done
				echoRgb "如果還是下載失敗請手動將備份腳本壓縮包放置在\n -$MODDIR後再次執行腳本進行本地更新" "0"
			fi
		else
			echoRgb "本地版本:$backup_version 線上版本:$tag 版本一致無須更新"
		fi
	else
		echoRgb "更新獲取失敗" "0"
	fi
else
	echoRgb "自動更新未開啟" "0"
fi
if [[ $zippath != "" ]]; then
	case $(echo "$zippath" | wc -l) in
	1)
		[[ $GitHub != true ]] && echoRgb "從$zippath更新"
		if [[ $(unzip -l "$zippath" | awk '{print $4}' | grep -oE "^backup_settings.conf$") = "" ]]; then
			echoRgb "${zippath##*/}並非指定的備份zip，請刪除後重新放置\n -何謂更新zip? 就是GitHub release頁面下載的zip" "0"
		else
			cp -r "$tools_path" "$TMPDIR" && rm -rf "$tools_path"
			find "$MODDIR" -maxdepth 3 -name "*.sh" -type f -exec rm -rf {} \;
			unzip -o "$zippath" -x "backup_settings.conf" -d "$MODDIR"
			echo_log "解壓縮${zippath##*/}"
			if [[ $result = 0 ]]; then
				case $MODDIR in
				*Backup_*)
					if [[ -f $MODDIR/app_details ]]; then
						mv "$MODDIR/tools" "${MODDIR%/*}"
						echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+外部tools目錄"
						cp -r "$tools_path/script/Get_DirName" "${MODDIR%/*}/DumpName.sh"
						cp -r "$tools_path/script/restore" "${MODDIR%/*}/Restorebackup.sh"
						[[ -d ${MODDIR%/}/Media ]] && cp -r "$tools_path/script/restore3" "${MODDIR%/*}/Media/恢復多媒體數據.sh"
						. "$MODDIR/app_details"
						if [[ $PackageName != "" ]]; then
							cp -r "$tools_path/script/restore2" "$MODDIR/Restorebackup.sh"
						else
							cp -r "$tools_path/script/restore3" "${MODDIR%/*}/Media/恢復多媒體數據.sh"
						fi
						if [[ -d ${MODDIR%/*/*}/tools && -f ${MODDIR%/*/*}/backup.sh ]]; then
							echoRgb "更新${MODDIR%/*/*}/tools與備份相關腳本"
							rm -rf "${MODDIR%/*/*}/tools"
							find "${MODDIR%/*/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
							mv "$MODDIR/backup_settings.conf" "$MODDIR/backup.sh" "$MODDIR/Getlist.sh" "${MODDIR%/*/*}"
							cp -r "$tools_path" "${MODDIR%/*/*}"
						fi
					else
						echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+tools目錄"
						cp -r "$tools_path/script/Get_DirName" "$MODDIR/DumpName.sh"
						cp -r "$tools_path/script/restore" "$MODDIR/Restorebackup.sh"
						[[ -d $MODDIR/Media ]] && cp -r "$tools_path/script/restore3" "$MODDIR/Media/恢復多媒體數據.sh"
						find "$MODDIR" -maxdepth 1 -type d | sort | while read; do
							if [[ -f $REPLY/app_details ]]; then
								unset PackageName
								. "$REPLY/app_details"
								[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/Restorebackup.sh"
							fi
						done
						if [[ -d ${MODDIR%/*}/tools && -f ${MODDIR%/*}/backup.sh ]]; then
							echoRgb "更新${MODDIR%/*}/tools與備份相關腳本"
							rm -rf "${MODDIR%/*}/tools"
							find "${MODDIR%/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
							mv "$MODDIR/backup_settings.conf" "$MODDIR/backup.sh" "$MODDIR/Getlist.sh" "${MODDIR%/*}"
							cp -r "$tools_path" "${MODDIR%/*}"
						fi
					fi
					rm -rf "$tools_path/script" "$MODDIR/backup_settings.conf" "$MODDIR/backup.sh" "$MODDIR/Getlist.sh"
					;;
				*)
					if [[ $(find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d) != "" ]]; then
						find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d | while read backup_path; do
							if [[ -d $backup_path && $backup_path != $MODDIR ]]; then
								echoRgb "更新當前目錄下備份相關腳本&tools目錄+${backup_path##*/}內tools目錄+恢復腳本+tools"
								rm -rf "$backup_path/tools"
								cp -r "$tools_path" "$backup_path" && rm -rf "$backup_path/tools/bin/zip" "$backup_path/tools/script"
								cp -r "$tools_path/script/restore" "$backup_path/Restorebackup.sh"
								cp -r "$tools_path/script/Get_DirName" "$backup_path/DumpName.sh"
								[[ -d $backup_path/Media ]] && cp -r "$tools_path/script/restore3" "$backup_path/Media/恢復多媒體數據.sh"
								find "$MODDIR" -maxdepth 2 -type d | sort | while read; do
									if [[ -f $REPLY/app_details ]]; then
										unset PackageName
										. "$REPLY/app_details"
										[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/Restorebackup.sh"
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
			find "$MODDIR" -maxdepth 1 -name "*.zip" -type f -exec rm -rf {} \;
			echoRgb "更新完成 請重新執行腳本" "2" && exit
		fi
		;;
	*)
		echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zippath" "0" && exit 1
		;;
	esac
fi