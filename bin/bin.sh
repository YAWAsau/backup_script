#設置二進制命令目錄位置
filepath=/data/backup_script/bin

busybox_file () {
    busybox="$filepath/busybox"
    if [[ -e $busybox ]]; then
        for a in $($busybox --list) ; do
            if [[ -n $a ]]; then
                if [[ -d $filepath ]]; then
                    [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"
                fi    
            fi    
        done
        #如果存在busybox 則創建私有目錄並且移動所需二進制後刪除當前$PATH
        export PATH=$filepath    
    else 
        echo "錯誤 缺少$busybox"
        exit 1
    fi
    [[ ! $PATH == $filepath ]] && echo "環境變量位置錯誤" && exit 1
    echo "環境變數: $PATH"
}

#補上遺失指令集
Add_path () {
    if [[ ! -e $filepath/$1 ]]; then
        if [[ -e $2/$1 ]]; then
            if [[ $3 == n ]]; then                
                if [[ -d $filepath ]]; then
                    cp -r $2/$1 $filepath
                    chmod 0777 $filepath/$1
                    busybox_file
                else
                    mkdir -p $filepath
                    cp -r $2/$1 $filepath
                    chmod 0777 $filepath/$1
                    busybox_file
                fi
            else
                if [[ -d $filepath ]]; then
                    ln -s $2/$1 $filepath
                else
                    mkdir -p $filepath
                    ln -s $2/$1 $filepath
                fi
            fi
        else 
            echo "$2/$1不存在 腳本所需的$1缺少"
            exit 1
        fi
    else
        [[ $filepath/$1 == $filepath/busybox ]] && busybox_file
    fi    
}