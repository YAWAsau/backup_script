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
[[ -d $(magisk --path) ]] && export PATH="$(magisk --path)/.magisk/busybox:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin"
backup_version="V10 2021/10/10-10:59"
#設置二進制命令目錄位置
[[ $bin_path = "" ]] && echo "未正確指定bin.sh位置" && exit 2
bin_path="${bin_path/'/storage/emulated/'/'/data/media/'}"
chmod -R 777 "$bin_path"
Status_log="$MODDIR/執行狀態日誌.txt"
rm -rf "$Status_log"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
#排除自身
exclude="
busybox_path
bin.sh"
rm_busyPATH() {
	if [[ ! -d $filepath ]]; then
		mkdir -p "$filepath"
		[[ $? = 0 ]] && echo "設置busybox環境中"
	fi
	[[ ! -f $bin_path/busybox_path ]] && touch "$bin_path/busybox_path"
	if [[ $filepath != $(cat "$bin_path/busybox_path") ]]; then
		[[ -d $(cat "$bin_path/busybox_path") ]] && rm -rf "$(cat "$bin_path/busybox_path")"
		echo "$filepath">"$bin_path/busybox_path"
	fi
}
rm_busyPATH
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -d $bin_path ]]; then
	[[ ! -f $bin_path/busybox ]] && echo "$bin_path/busybox不存在" && exit 1
	find "$bin_path" -maxdepth 1 -type f | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read; do
		File_name="${REPLY##*/}"
		if [[ ! -f $filepath/$File_name ]]; then
			ln -fs "$REPLY" "$filepath"
			echo "$File_name > $filepath/$File_name"
		fi
		[[ ! -x $REPLY ]] && echo "$REPLY權限不可執行" && exit 1
	done
	rm_busyPATH
	"$busybox" --list | while read; do
		if [[ $REPLY != tar && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
else
	echo "遺失$bin_path"
	exit 1
fi
if [[ ! -f $busybox ]]; then
	echo "不存在$busybox ...."
	exit 1
fi
export PATH="$filepath:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin"
export TZ=Asia/Taipei
Open_apps="$(dumpsys window | grep -w mCurrentFocus | egrep -oh "[^ ]*/[^//}]+" | cut -f 1 -d "/")"

#下列為自定義函數
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
echoRgb() {
	#轉換echo顏色提高可讀性
	if [[ $2 != "" ]]; then
		if [[ $3 = 0 ]]; then
			echo -e "\e[38;5;196m -$1\e[0m"
		elif [[ $3 = 1 ]]; then
			echo -e "\e[38;5;82m -$1\e[0m"
		elif [[ $3 = 2 ]]; then
			echo -e "\e[38;5;87m -$1\e[0m"
		else
			echo -e "\e[38;5;196m $1 $2 $3 顏色控制項錯誤\e[0m"; exit 2
		fi
	else
		echo -e "\e[38;5;${bn}m -$1\e[0m"
	fi
	echo " -$1">>"$Status_log"
}
get_version() {
	while :; do
		version="$(getevent -qlc 1 | awk '{ print $3 }')"
		case $version in
		KEY_VOLUMEUP)
			branch=true
			echoRgb "$1"
			;;
		KEY_VOLUMEDOWN)
			branch=false
			echoRgb "$2"
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
		echoRgb "$MODDIR/backup_settings.conf $1填寫錯誤" "0" "0" && exit 2
	fi
}
bn=205
echoRgb "環境變數:$PATH\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -設備架構$abi\n -品牌:$(getprop ro.product.brand)\n -設備代號:$(getprop ro.product.device)\n -型號:$(getprop ro.product.model)\n -Android版本:$(getprop ro.build.version.release)\n -SDK:$(getprop ro.build.version.sdk)\n -終端:$(appinfo -o ands -pn "$Open_apps" 2>/dev/null)"
bn=195