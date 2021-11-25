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
backup_version="V12.1.1"
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
tag
json
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
		filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echo "busybox sha256不一致 重新創立環境中"
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
echo_log() {
	if [[ $? = 0 ]]; then
		echoRgb "$1成功" "1" ; result=0
	else
		echoRgb "$1失敗，過世了" "0" ; Print "$1失敗，過世了" ; result=1
	fi
}
LANG="$(getprop "persist.sys.locale")"
if [[ $LANG != "" ]]; then
	case $LANG in
	*-TW|*-tw)
		echoRgb "系統語系:繁體中文"
		Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest" ;;
	*-CN|*-cn)
		echoRgb "系統語系:簡體中文"
		Language="https://api.github.com/repos/Petit-Abba/backup_script_zh-CN/releases/latest" ;;
	* )
		echoRgb "$LANG不支持 默認簡體中文" "0"
		Language="https://api.github.com/repos/Petit-Abba/backup_script_zh-CN/releases/latest" ;;
	esac
else
	echoRgb "獲取系統語系失敗 默認簡體中文" "0"
	Language="https://api.github.com/repos/Petit-Abba/backup_script_zh-CN/releases/latest"
fi
down -s -L "$Language" 2>/dev/null >"$bin_path/json"
Open_apps="$(appinfo -o ands -ta c)"
bn=147
echoRgb "\n --------------歡迎使用⚡️🤟🐂纸備份--------------\n -當前腳本執行路徑:$MODDIR\n -busybox路徑:$(which busybox)\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -設備架構$abi\n -品牌:$(getprop ro.product.brand)\n -設備代號:$(getprop ro.product.device)\n -型號:$(getprop ro.product.model)\n -Android版本:$(getprop ro.build.version.release)\n -SDK:$(getprop ro.build.version.sdk)\n -終端:$Open_apps"
bn=195
if [[ $script != "" && $(pgrep -f "$script" | grep -v grep | wc -l) -ge 2 ]]; then
	echoRgb "檢測到進程殘留，請重新執行腳本 已銷毀進程" "0"
	pgrep -f "$script" | grep -v grep | while read i; do
		[[ $i != "" ]] && kill -9 " $i" >/dev/null
	done
fi
if [[ $(pm path ice.message) = "" ]]; then
	echoRgb "未安裝toast 開始安裝" "0"
	cp -r "${bin_path%/*}/apk"/*.apk "$TMPDIR" && pm install --user 0 -r "$TMPDIR"/*.apk &>/dev/null && rm -rf "$TMPDIR"/* 
	[[ $? = 0 ]] && echoRgb "安裝toast成功" "1" || echoRgb "安裝toast失敗" "0"
fi
zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
#sed -r -n 's/.*"browser_download_url": *"(.*)".*/\1/p'
#sed -r -n 's/.*"browser_download_url": *"(.*-linux64\..*\.so\.bz2)".*/\1/p'
if [[ -f $bin_path/json && $(cat "$bin_path/json") != "" ]]; then
	tag="$(cat "$bin_path/json" | jq -r '.tag_name')"
	download="$(cat "$bin_path/json" | sed -r -n 's/.*"browser_download_url": *"(.*.zip)".*/\1/p')"
	if [[ $tag != "" ]]; then
		if [[ $backup_version != $tag ]]; then
			echoRgb "發現新版本 從GitHub更新 版本:$tag\n -更新日誌:\n$(cat "$bin_path/json" | jq -r '.body')"
			down -s -L -o "$MODDIR/$tag.zip" "https://gh.api.99988866.xyz/$download"
			echo_log "下載${download##*/}"
			if [[ $result = 0 ]]; then
				zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
				GitHub="true"
			else
				echoRgb "請手動將備份腳本壓縮包放置在\n -$MODDIR後再次執行腳本進行更新" "0"
			fi
		else
			echoRgb "本地版本:$backup_version 線上版本:$tag 版本一致無須更新"
		fi
	fi
	rm -rf "$bin_path/json"
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
			unzip -o "$zippath" -d "$MODDIR"
			echo_log "解壓縮${zippath##*/}"
			if [[ $result = 0 ]]; then
				case $MODDIR in
				*Backup_*)
					if [[ -f $MODDIR/app_details ]]; then
						mv "$MODDIR/tools" "${MODDIR%/*}"
						echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+外部tools目錄"
						cp -r "$tools_path/script/Get_DirName" "${MODDIR%/*}/掃描資料夾名.sh"
						cp -r "$tools_path/script/restore" "${MODDIR%/*}/還原備份.sh"
						[[ -d ${MODDIR%/}/媒體 ]] && cp -r "$tools_path/script/restore3" "${MODDIR%/*}/媒體/恢復多媒體數據.sh"
						. "$MODDIR/app_details"
						if [[ $PackageName != "" ]]; then
							cp -r "$tools_path/script/restore2" "$MODDIR/還原備份.sh"
						else
							cp -r "$tools_path/script/restore3" "${MODDIR%/*}/媒體/恢復多媒體數據.sh"
						fi
						if [[ -d ${MODDIR%/*/*}/tools && -f ${MODDIR%/*/*}/備份應用.sh ]]; then
							echoRgb "更新${MODDIR%/*/*}/tools與備份相關腳本"
							rm -rf "${MODDIR%/*/*}/tools"
							find "${MODDIR%/*/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
							mv "$MODDIR/backup_settings.conf" "$MODDIR/備份應用.sh" "$MODDIR/生成應用列表.sh" "${MODDIR%/*/*}"
							cp -r "$tools_path" "${MODDIR%/*/*}"
						fi
					else
						echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+tools目錄"
						cp -r "$tools_path/script/Get_DirName" "$MODDIR/掃描資料夾名.sh"
						cp -r "$tools_path/script/restore" "$MODDIR/還原備份.sh"
						[[ -d $MODDIR/媒體 ]] && cp -r "$tools_path/script/restore3" "$MODDIR/媒體/恢復多媒體數據.sh"
						find "$MODDIR" -maxdepth 1 -type d | sort | while read; do
							if [[ -f $REPLY/app_details ]]; then
								unset PackageName
								. "$REPLY/app_details"
								[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/還原備份.sh"
							fi
						done
						if [[ -d ${MODDIR%/*}/tools && -f ${MODDIR%/*}/備份應用.sh ]]; then
							echoRgb "更新${MODDIR%/*}/tools與備份相關腳本"
							rm -rf "${MODDIR%/*}/tools"
							find "${MODDIR%/*}" -maxdepth 1 -name "*.sh" -type f -exec rm -rf {} \;
							mv "$MODDIR/backup_settings.conf" "$MODDIR/備份應用.sh" "$MODDIR/生成應用列表.sh" "${MODDIR%/*}"
							cp -r "$tools_path" "${MODDIR%/*}"
						fi
					fi
					rm -rf "$tools_path/script" "$MODDIR/backup_settings.conf" "$MODDIR/備份應用.sh" "$MODDIR/生成應用列表.sh" ;;
				*)
					if [[ $(find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d) != "" ]]; then
						find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d | while read backup_path; do
							if [[ -d $backup_path && $backup_path != $MODDIR ]]; then
								echoRgb "更新當前目錄下備份相關腳本&tools目錄+${backup_path##*/}內tools目錄+恢復腳本+tools"
								cp -r "$tools_path" "$backup_path" && rm -rf "$backup_path/tools/bin/zip" "$backup_path/tools/script"
								cp -r "$tools_path/script/restore" "$backup_path/還原備份.sh"
								cp -r "$tools_path/script/Get_DirName" "$backup_path/掃描資料夾名.sh"
								[[ -d $backup_path/媒體 ]] && cp -r "$tools_path/script/restore3" "$backup_path/媒體/恢復多媒體數據.sh"
								find "$MODDIR" -maxdepth 2 -type d | sort | while read; do
									if [[ -f $REPLY/app_details ]]; then
										unset PackageName
										. "$REPLY/app_details"
										[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/還原備份.sh"
									fi
								done
							fi
						done
					else
						echoRgb "更新當前${MODDIR##*/}目錄下備份相關腳本+tools目錄"
					fi ;;
				esac
			else
				cp -r "$TMPDIR/tools" "$MODDIR"
			fi
			rm -rf "$TMPDIR"/*
			find "$MODDIR" -maxdepth 1 -name "*.zip" -type f -exec rm -rf {} \;
			echoRgb "更新完成 請重新執行腳本" "2" && exit
		fi ;;
	*)
		echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zippath" "0" && exit 1 ;;
	esac
fi