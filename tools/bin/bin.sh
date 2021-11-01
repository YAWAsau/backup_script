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
#if [[ -d /data/user/0/com.tencent.mobileqq/files/aladdin_configs/964103426 ]]; then
#	echo "爬 不給你用臭批阿巴" && exit 2
#fi
PATH="/sbin/.magisk/busybox:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:/data/data/Han.GJZS/files/usr/busybox:/data/data/Han.GJZS/files/usr/bin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
if [[ -d $(magisk --path 2>/dev/null) ]]; then
	PATH="$(magisk --path)/.magisk/busybox:$PATH"
else
	echo "Magisk busybox Path does not exist"
fi ; export PATH="$PATH"
backup_version="V10.7 2021/10/27-20:07"
#設置二進制命令目錄位置
[[ $bin_path = "" ]] && echo "未正確指定bin.sh位置" && exit 2
#bin_path="${bin_path/'/storage/emulated/'/'/data/media/'}"
Status_log="$MODDIR/執行狀態日誌.txt"
rm -rf "$Status_log"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$bin_path/busybox"
#排除自身
exclude="
busybox_path
bin.sh"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echo "設置busybox環境中"
fi
[[ ! -f $bin_path/busybox_path ]] && touch "$bin_path/busybox_path"
if [[ $filepath != $(cat "$bin_path/busybox_path") ]]; then
	[[ -d $(cat "$bin_path/busybox_path") ]] && rm -rf "$(cat "$bin_path/busybox_path")"
	echo "$filepath">"$bin_path/busybox_path"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -d $bin_path ]]; then
	if [[ -f $busybox && -f $busybox2 ]]; then
		filemd5="$(md5sum "$busybox" | cut -d" " -f1)"
		filemd5_1="$(md5sum "$busybox2" | cut -d" " -f1)"
		if [[ $filemd5 != $filemd5_1 ]]; then
			echo "busybox md5不一致 重新創立環境中"
			rm -rf "$filepath"/*
		fi
	fi
	find "$bin_path" -maxdepth 1 -type f | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read; do
		File_name="${REPLY##*/}"
		if [[ ! -f $filepath/$File_name ]]; then
			cp -r "$REPLY" "$filepath"
			chmod 0777 "$filepath/$File_name"
			echo "$File_name > $filepath/$File_name"
		else
			filemd5="$(md5sum "$filepath/$File_name" | cut -d" " -f1)"
			filemd5_1="$(md5sum "$bin_path/$File_name" | cut -d" " -f1)"
			if [[ $filemd5 != $filemd5_1 ]]; then
				echo "$File_name md5不一致 重新創建"
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
if [[ $(which busybox) = "" ]]; then
	echo "環境變量中沒有找到busybox 請在tools/bin內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...."
	exit 1
fi
Open_apps="$(dumpsys window | grep -w mCurrentFocus | egrep -oh "[^ ]*/[^//}]+" | cut -f 1 -d "/")"
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
Print() {
	notify "1" "backup-$(date '+%T')" "$1" bs
}
echoRgb() {
	#轉換echo顏色提高可讀性
	if [[ $2 = 0 ]]; then
		echo -e "\e[38;5;196m -$1\e[0m"
	elif [[ $2 = 1 ]]; then
		echo -e "\e[38;5;82m -$1\e[0m"
	elif [[ $2 = 2 ]]; then
		echo -e "\e[38;5;87m -$1\e[0m"
	elif [[ $2 = 3 ]]; then
		echo -e "\e[38;5;${en}m -$1\e[0m"
	else
		echo -e "\e[38;5;${bn}m -$1\e[0m"
	fi
	echo " -$(date '+%T') $1">>"$Status_log"
}
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
	if [[ $1 = 1 ]];then
		nsx=true
	elif [[ $1 = 0 ]];then
		nsx=false
	else
		echoRgb "$MODDIR/backup_settings.conf $1填寫錯誤" "0" && exit 2
	fi
}
bn=147
echoRgb "\n --------------歡迎使用⚡️🤟🐂纸備份--------------\n -當前腳本執行路徑:$MODDIR\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -設備架構$abi\n -品牌:$(getprop ro.product.brand)\n -設備代號:$(getprop ro.product.device)\n -型號:$(getprop ro.product.model)\n -Android版本:$(getprop ro.build.version.release)\n -SDK:$(getprop ro.build.version.sdk)\n -終端:$(appinfo -o ands -pn "$Open_apps" 2>/dev/null)"
bn=195
if [[ $(pm path ice.message) = "" ]]; then
	echoRgb "未安裝toast 開始安裝" "0"
	cp -r "${bin_path%/*}/apk"/*.apk "$TMPDIR" && pm install --user 0 -r "$TMPDIR"/*.apk &>/dev/null && rm -rf "$TMPDIR"/* 
	[[ $? = 0 ]] && echoRgb "安裝toast成功" "1" || echoRgb "安裝toast失敗" "0"
fi