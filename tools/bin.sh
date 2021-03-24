abi=$(getprop ro.product.cpu.abi)
case $abi in
arm64*) echo "設備架構$abi" ;;
*)
	echo "未知的架構: $abi"
	exit 1
	;;
esac
version=v7
#設置二進制命令目錄位置
filepath=/data/backup_tools
busybox="$filepath/busybox"
if [[ -e $busybox ]]; then
	filesize=$(ls -l $busybox | awk '{print $5}')
	filesize2=$(ls -l $tools_path/busybox-arm64 | awk '{print $5}')
	if [[ ! $filesize == $filesize2 ]]; then
		echo "busybox大小不一致 重新創立環境中"
		rm -rf $filepath
	fi
fi

#補上遺失指令集
Add_path() {
	#工具絕對位置
	if [[ -e $busybox ]]; then
		if [[ ! -e $filepath/$1 ]]; then
		    if [[ -e $tools_path/$1 ]]; then
                if [[ $1 == aapt ]]; then
                    cp -r $tools_path/aapt* $filepath
                    chmod 0777 $filepath/aapt*
                fi
    			cp -r $tools_path/$1 $filepath
    			chmod 0777 $filepath/$1
  			else
				echo "$tools_path/$1不存在 腳本所需的$1缺少"
				exit 1
			fi
		fi
		[[ ! -e $filepath/$1 ]] && echo "錯誤: $filepath/$1不存在" && exit 1
		export PATH=$filepath:$PATH
	else
		echo "不存在$busybox 设置环境中...."
		if [[ -e $tools_path/busybox-arm64 ]]; then
			[[ ! -d $filepath ]] && mkdir -p $filepath
			cp -r $tools_path/busybox-arm64 $busybox
			chmod 0777 $busybox
			for a in $($busybox --list); do
				if [[ -n $a ]]; then
					[[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"
				fi
			done
			export PATH=$PATH:$filepath	
		else
			echo "錯誤 缺少$tools_path/busybox-arm64"
			exit 1
		fi
	fi
}