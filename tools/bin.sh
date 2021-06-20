abi=$(getprop ro.product.cpu.abi)
case $abi in
arm64*) echo "設備架構$abi" ;;
*)
	echo "未知的架構: $abi"
	exit 1
	;;
esac

#設置二進制命令目錄位置
[[ -z $tools_path ]] && tools_path=${0%/*}/tools
#filepath=/data/aosp_tools
filepath=/data/backup_tools
#排除自身
exclude="
busybox_path
bin.sh"
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
		filesize=$(ls -l $busybox | awk '{print $5}')
		filesize2=$(ls -l $tools_path/busybox | awk '{print $5}')
		if [[ ! $filesize = $filesize2 ]]; then
			echo "busybox大小不一致 重新創立環境中"
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
				for a in $($busybox --list); do
					case $a in
					date|tar|restore|busybox_path) ;;
					*)
						if [[ ! -e $filepath/$a ]]; then
							echo "$a > $filepath/$a"
							ln -s $busybox "$filepath/$a"
						fi
					;;
					esac
				done
			fi
		fi
	done
else
	echo "遺失$tools_path"
	exit 1
fi
#工具絕對位置
if [[ -e $busybox ]]; then
	export PATH=$filepath:$PATH
	echo "环境变数: $PATH"
	echo "version:$(busybox | head -1)"
else
	echo "不存在$busybox ...."
	exit 1
fi