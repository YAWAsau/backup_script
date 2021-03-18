
#補上遺失指令集
Add_path () {
    #設置二進制命令目錄位置
    filepath=/data/backup_tools
    busybox="$filepath/busybox"
    #工具絕對位置  
    if [[ -e $busybox ]]; then        
        if [[ ! -e $filepath/$1 ]]; then
            if [[ $2 == n ]]; then             
                if [[ -e $tools_path/$1 ]]; then                   
                    cp -r $tools_path/$1 $filepath
                    chmod 0777 $filepath/$1                                           
                else 
                    echo "$tools_path/$1不存在 腳本所需的$1缺少"
                    exit 1
                fi
            else
                if [[ -e $3/$1 ]]; then
                    ln -s $3/$1 $filepath
                else
                    echo "錯誤: $3/$1不存在"
                    exit 1
                fi                      
            fi        
        fi    
        [[ ! -e $filepath/$1 ]] && echo "錯誤: $filepath/$1不存在" && exit 1
        export PATH=$filepath
        [[ ! $PATH == $filepath ]] && echo "環境變量位置錯誤" && exit 1        
    else
        #判斷是否存在Magisk busybox 則優先使用，如沒有使用腳本自身busybox
        if [[ -e /data/adb/magisk/busybox ]]; then    
            echo "存在Magisk busybox path:/data/adb/magisk/busybox"
            echo "優先使用 佈置環境中....."
            [[ ! -d $filepath ]] && mkdir -p $filepath
            cp -r /data/adb/magisk/busybox $busybox
            chmod 0777 $busybox
            for a in $($busybox --list) ; do
                if [[ -n $a ]]; then                    
                    [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"                    
                fi    
            done
            export PATH=$filepath
            [[ ! $PATH == $filepath ]] && echo "環境變量位置錯誤" && exit 1         
        else
            if [[ -e $tools_path/busybox ]]; then
                echo "不存在Magisk busybox"
                echo "使用$tools_path/busybox 佈置環境中....."
                [[ ! -d $filepath ]] && mkdir -p $filepath
                cp -r $tools_path/busybox $busybox
                chmod 0777 $busybox
                for a in $($busybox --list) ; do
                    if [[ -n $a ]]; then                    
                        [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"                    
                    fi    
                done
                export PATH=$filepath
                [[ ! $PATH == $filepath ]] && echo "環境變量位置錯誤" && exit 1        
            else
                echo "錯誤 缺少$tools_path/busybox"
                exit 1
            fi
        fi
    fi        
}