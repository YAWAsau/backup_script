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
filepath=/data/backup_tools
#排除自身
exclude="
restore
bin.sh"
[[ ! -d $filepath ]] && mkdir -p $filepath && echo "設置busybox環境中"

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
		fi
    fi
    ls -a $tools_path | sed -r '/^\.{1,2}$/d' | egrep -v "$(echo $exclude | sed 's/ /\|/g')" | while read i; do
        if [[ ! $i = busybox ]]; then
            if [[ ! -e $filepath/$i ]]; then     
                echo "$i > $filepath/$i"
                cp -r $tools_path/$i $filepath
                chmod 0777 $filepath/$i
            fi
        else
            if [[ ! -e $filepath/$i ]]; then 
                cp -r $tools_path/$i $filepath
                chmod 0777 $filepath/$i
                echo "$i > $filepath/$i"
            fi
            for a in $($busybox --list); do
                case $a in
                tar) ;;
                *)
    			    if [[ ! -e $filepath/$a ]]; then
    			        echo "$a > $filepath/$a"
    			        ln -s $busybox "$filepath/$a"
    				fi
                    ;;
    			esac
    	    done
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