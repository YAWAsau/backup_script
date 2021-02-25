#設置二進制命令目錄位置
filepath=/data/backup_script/bin
busybox="$filepath/busybox"
#補上遺失指令集
Add_path () {
    if [[ ! -e $filepath/$1 ]]; then
        if [[ -e $2/$1 ]]; then
            if [[ $3 == n ]]; then                
                if [[ -d $filepath ]]; then
                    [[ ! -e $filepath/$1 ]] && cp -r $2/$1 $filepath && chmod 0777 $filepath/$1
                else
                    mkdir -p $filepath
                    cp -r $2/$1 $filepath
                    chmod 0777 $filepath/$1
                fi
            else
                if [[ -d $filepath ]]; then
                    [[ ! -e $filepath/$1 ]] && ln -s $2/$1 $filepath
                else
                    mkdir -p $filepath
                    ln -s $2/$1 $filepath
                fi
            fi
        else 
            echo "$2/$1不存在 腳本所需的$1缺少"
            exit 1
        fi
    fi    
}

#設置命令和目錄位置及是否使用鏈接方式
Add_path "busybox" ${0%/*}/bin n
Add_path "7za" ${0%/*}/bin n
Add_path "pm" /system/bin y
Add_path "cmd" /system/bin y
Add_path "am" /system/bin y
#檢測busybox是否存在
if [[ -e $busybox ]]; then   
    echo "busybox path: $busybox"
    chmod 0777 $busybox
    for a in $($busybox --list) ; do
        if [[ -n $a ]]; then
            if [[ -d $filepath ]]; then
                [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"
            fi    
        fi    
    done
    #如果存在busybox 則創建私有目錄並且移動所需二進制後刪除當前$PATH
    unset PATH    
else 
    echo "錯誤 缺少$busybox"
    exit 1
fi
export PATH=$filepath
[[ ! $PATH == $filepath ]] && echo "環境變量位置錯誤" && exit 1