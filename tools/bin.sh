abi=$(getprop ro.product.cpu.abi)
case $abi in
arm64*) 
	;;
*)
	echo "-未知的架構: $abi"
	exit 1
	;;
esac
[[ $(getprop ro.build.version.release) -le 8 ]] && echo "設備Android版本過低 請升級至Android 9+" && exit 1
#設置二進制命令目錄位置
[[ -z $tools_path ]] && echo "未正確指定bin.sh位置" && exit 2
filepath=/data/backup_tools
#排除自身
exclude="
restore
md5tmp
md5check
restore2
busybox_path
bin.sh"
rm_busyPATH() {
	if [[ ! -d $filepath ]]; then
		mkdir -p "$filepath"
		[[ $? = 0 ]] && echo "設置busybox環境中"
	fi
	[[ ! -e $tools_path/busybox_path ]] && touch "$tools_path/busybox_path"
	if [[ $filepath != $(cat "$tools_path/busybox_path") ]]; then
		if [[ -d $(cat "$tools_path/busybox_path") ]]; then
			rm -rf "$(cat "$tools_path/busybox_path")"
			echo "$filepath">"$tools_path/busybox_path"
		else
			echo "$filepath">"$tools_path/busybox_path"
		fi
	fi
}
rm_busyPATH
if [[ -d $tools_path ]]; then
	[[ ! -e $tools_path/busybox ]] && echo "$tools_path/busybox不存在" && exit 1
	busybox=$filepath/busybox
	if [[ -e $busybox ]]; then
		filemd5=$(md5sum "$busybox" | cut -d" " -f1)
		filemd5_1=$(md5sum "$tools_path/busybox" | cut -d" " -f1)
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
					case $a in
					tar|date) ;;
					*)
						[[ ! -e $filepath/$a ]] && ln -s "$busybox" "$filepath/$a"
					;;
					esac
				done
				echo "busybox設置完成"
			fi
		else
			"$busybox" --list | while read a; do
				case $a in
				tar|date) ;;
				*)
					[[ ! -e $filepath/$a ]] && ln -s "$busybox" "$filepath/$a" && echo "$a > $filepath/$a"
					;;
				esac
			done
			filemd5=$(md5sum "$filepath/$i" | cut -d" " -f1)
			filemd5_1=$(md5sum "$tools_path/$i" | cut -d" " -f1)
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
export PATH=$filepath:$PATH
echo "驗證環境中 請稍後"
ls -a "$tools_path" | sed -r '/^\.{1,2}$/d' | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read i; do
	[[ ! -d $tools_path/$i ]] && {
	[[ $(which "$i" | wc -l) != 1 ]] && echo "$i不存在環境中"
	}
done
Open_apps=$(dumpsys window | grep -w mCurrentFocus | egrep -oh "[^ ]*/[^//}]+" | cut -f 1 -d "/")

#下列為自定義函數
endtime() {
	#計算總體切換時長耗費
	case $1 in
	1) starttime=$starttime1 ;;
	2) starttime=$starttime2 ;;
	esac
	endtime=$(date "+%Y-%m-%d %H:%M:%S")
	duration=$(echo $(($(date +%s -d "${endtime}") - $(date +%s -d "${starttime}"))) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
	[[ -n $duration ]] && echoRgb "$2用時:$duration" || echoRgb "$2用時:0秒"
}
echoRgb() {
	#轉換echo顏色提高可讀性
	if [[ -n $2 ]]; then
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
Package_names() {
	[[ -n $1 ]] && t1=$1
	t2=$(appinfo -o pn -pn "$t1" 2>/dev/null | head -1)
	[[ -n $t2 ]] && [[ $t2 = $1 ]] && echo "$t2"
}
get_version() {
	while :; do
		version=$(getevent -qlc 1 | awk '{ print $3 }')
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
	nsx=$1
	if [[ $1 = 1 ]];then
		nsx=true
	elif [[ $1 = 0 ]];then
		nsx=false
	else
		echoRgb "$MODDIR/backup_settings.conf $1填寫錯誤" && exit 2
	fi
}
bn=36
echoRgb "-環境變數: $PATH
 -busybox版本:$(busybox | head -1 | awk '{print $2}')
 -appinfo版本:$(appinfo --version)
 -設備架構$abi
 -品牌:$(getprop ro.product.brand)
 -設備代號:$(getprop ro.product.device)
 -型號:$(getprop ro.product.model)
 -Android版本:$(getprop ro.build.version.release)
 -SDK:$(getprop ro.build.version.sdk)
 -終端:$(appinfo -o ands -pn "$Open_apps" 2>/dev/null)
 -下列為本工具項目銘謝貢獻名單(排名不分先後)
 -臭批老k提供部分與驗證函數思路(kmou424)
 -屑老方提供自動更新腳本方案(雄氏老方)
 -依心所言&情非得已c提供appinfo替代aapt作為更高效的dump包名
 -胖子老陳(雨季騷年)"