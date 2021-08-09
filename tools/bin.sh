abi=$(getprop ro.product.cpu.abi)
case $abi in
arm64*) 
	;;
*)
	echo "-未知的架構: $abi"
	exit 1
	;;
esac

#設置二進制命令目錄位置
[[ -z $tools_path ]] && echo "未正確指定bin.sh位置" && exit 2
filepath=/data/backup_tools
#排除自身
exclude="
restore
busybox_path
bin.sh"
MD5() {
	file_path=$(find $md5path -name "$1" -maxdepth 2 -type f)
	if [[ -f $file_path ]]; then
		if [[ ! $(echo $file_path | xargs md5sum | cut -d" " -f1) = $2 ]]; then
			echo "$1文件被更改或是損毀"
			exit 1
		fi
	fi
}
rm_busyPATH() {
if [[ ! -d $filepath ]]; then
	mkdir -p $filepath
	echo "設置busybox環境中"
else
	[[ ! -e $tools_path/busybox_path ]] && touch $tools_path/busybox_path
	if [[ ! $filepath = $(cat $tools_path/busybox_path) ]]; then
		if [[ -d $(cat $tools_path/busybox_path) ]]; then
			rm -rf "$(cat $tools_path/busybox_path)"
			echo "$filepath">$tools_path/busybox_path
		else
			echo "$filepath">$tools_path/busybox_path
		fi
	fi
fi
}
rm_busyPATH
if [[ -d $tools_path ]]; then
	[[ ! -e $tools_path/busybox ]] && echo "$tools_path/busybox不存在" && exit 1
	busybox="$filepath/busybox"
	if [[ -e $busybox ]]; then
		filemd5=$(md5sum $busybox | cut -d" " -f1)
		filemd5_1=$(md5sum $tools_path/busybox | cut -d" " -f1)
		if [[ ! $filemd5 = $filemd5_1 ]]; then
			echo "busybox md5不一致 重新創立環境中"
			rm -rf $filepath
			[[ ! -d $filepath ]] && mkdir -p $filepath && echo "設置busybox環境中"
			rm_busyPATH
		fi
	fi
	ls -a $tools_path | sed -r '/^\.{1,2}$/d' | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read i; do
		if [[ ! -e $filepath/$i ]]; then
			echo "$i > $filepath/$i"
			cp -r $tools_path/$i $filepath
			chmod 0777 $filepath/$i
			if [[ $i = busybox ]]; then
				rm_busyPATH
				$busybox --list | while read a; do
					case $a in
					date|tar) ;;
					*)
						if [[ ! -e $filepath/$a ]]; then
							ln -s $busybox "$filepath/$a"
						fi
					;;
					esac
				done
				echo "busybox設置完成"
			fi
		else
			filemd5=$(md5sum $filepath/$i | cut -d" " -f1)
			filemd5_1=$(md5sum $tools_path/$i | cut -d" " -f1)
			if [[ ! $filemd5 = $filemd5_1 ]]; then
				echo "$i md5不一致 重新創建"
				echo "$i > $filepath/$i"
				rm -rf $filepath/$i
				cp -r $tools_path/$i $filepath
				chmod 0777 $filepath/$i
			fi
		fi
	done
else
	echo "遺失$tools_path"
	exit 1
fi
#工具絕對位置
[[ ! -e $busybox ]] && {
echo "不存在$busybox ...."
exit 1
}
export PATH=$filepath:$PATH
echo "-環境變數: $PATH"
echo "-version:$(busybox | head -1 | awk '{print $2}')"
echo "-設備架構$abi"
echo "-品牌:$(getprop ro.product.brand)"
echo "-設備代號:$(getprop ro.product.device)"
echo "-型號:$(getprop ro.product.model)"
echo "-Android版本:$(getprop ro.build.version.release)"
echo "-SDK:$(getprop ro.build.version.sdk)"
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
		if [[ $3 = 1 ]]; then
			echo -e "\e[1;32m $1\e[0m"
		else
			echo -e "\e[1;31m $1\e[0m"
		fi
	else
		echo -e "\e[1;${bn}m $1\e[0m"
	fi
}
Package_names() {
	[[ -n $1 ]] && t1="$1"
	t2=$(appinfo -o pn -pn $t1 2>/dev/null | head -1)
	[[ -n $t2 ]] && [[ $t2 = $1 ]] && echo $t2
}