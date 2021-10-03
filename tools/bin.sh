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
backup_version="9.6Releases 2021/10/2-19:09"
#設置二進制命令目錄位置
[[ $tools_path = "" ]] && echo "未正確指定bin.sh位置" && exit 2
filepath="/data/backup_tools"
#排除自身
exclude="
restore
restore2
restore3
掃描資料夾名.sh
busybox_path
bin.sh"
rm_busyPATH() {
	if [[ ! -d $filepath ]]; then
		mkdir -p "$filepath"
		[[ $? = 0 ]] && echo "設置busybox環境中"
	fi
	[[ ! -e $tools_path/busybox_path ]] && touch "$tools_path/busybox_path"
	if [[ $filepath != $(cat "$tools_path/busybox_path") ]]; then
		[[ -d $(cat "$tools_path/busybox_path") ]] && rm -rf "$(cat "$tools_path/busybox_path")"
		echo "$filepath">"$tools_path/busybox_path"
	fi
}
rm_busyPATH
if [[ -d $tools_path ]]; then
	[[ ! -e $tools_path/busybox ]] && echo "$tools_path/busybox不存在" && exit 1
	busybox="$filepath/busybox"
	if [[ -e $busybox ]]; then
		filemd5="$(md5sum "$busybox" | cut -d" " -f1)"
		filemd5_1="$(md5sum "$tools_path/busybox" | cut -d" " -f1)"
		if [[ $filemd5 != $filemd5_1 ]]; then
			echo "busybox md5不一致 重新創立環境中"
			rm -rf "$filepath" && rm_busyPATH
		fi
	fi
	ls -a "$tools_path" | sed -r '/^\.{1,2}$/d' | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read i; do
		[[ ! -d $tools_path/$i ]] && {
		if [[ ! -e $filepath/$i ]]; then
			cp -r "$tools_path/$i" "$filepath"
			chmod 0777 "$filepath/$i"
			echo "$i > $filepath/$i"
			if [[ $i = busybox ]]; then
				rm_busyPATH
				"$busybox" --list | while read a; do
					[[ $a != tar && ! -e $filepath/$a ]] && ln -s "$busybox" "$filepath/$a"
				done
				echo "busybox設置完成"
			fi
		else
			"$busybox" --list | while read a; do
				[[ $a != tar && ! -e $filepath/$a ]] && ln -s "$busybox" "$filepath/$a" && echo "$a > $filepath/$a"
			done
			filemd5="$(md5sum "$filepath/$i" | cut -d" " -f1)"
			filemd5_1="$(md5sum "$tools_path/$i" | cut -d" " -f1)"
			if [[ $filemd5 != $filemd5_1 ]]; then
				echo "$i md5不一致 重新創建"
				rm -rf "$filepath/$i"
				cp -r "$tools_path/$i" "$filepath"
				chmod 0777 "$filepath/$i"
				echo "$i > $filepath/$i"
			fi
		fi
		}
	done
else
	echo "遺失$tools_path"
	exit 1
fi

#工具絕對位置
if [[ ! -e $busybox ]]; then
	echo "不存在$busybox ...."
	exit 1
fi
export PATH="$filepath:/system_ext/bin:/system/bin:/system/xbin:/vendor/bin:/vendor/xbin"
unset LD_LIBRARY_PATH LD_PRELOAD
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
			echo -e "\e[1;31m $1\e[0m"
		elif [[ $3 = 1 ]]; then
			echo -e "\e[1;32m $1\e[0m"
		elif [[ $3 = 2 ]]; then
			echo -e "\e[1;33m $1\e[0m"
		else
			echo "$1 $2 $3 顏色控制項錯誤"; exit 2
		fi
	else
		echo -e "\e[1;${bn}m $1\e[0m"
	fi
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
		echoRgb "$MODDIR/backup_settings.conf $1填寫錯誤" && exit 2
	fi
}
bn=36
echoRgb "-環境變數: $PATH\n -busybox版本:$(busybox | head -1 | awk '{print $2}')\n -appinfo版本:$(appinfo --version)\n -腳本版本:$backup_version\n -設備架構$abi\n -品牌:$(getprop ro.product.brand)\n -設備代號:$(getprop ro.product.device)\n -型號:$(getprop ro.product.model)\n -Android版本:$(getprop ro.build.version.release)\n -SDK:$(getprop ro.build.version.sdk)\n -終端:$(appinfo -o ands -pn "$Open_apps" 2>/dev/null)"