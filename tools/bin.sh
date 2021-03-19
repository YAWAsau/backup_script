

abi=$(getprop ro.product.cpu.abi)
case $abi in
arm64*) echo "设备架构$abi" ;;    
*) echo "未知的架构: $abi"; exit 1 ;;
esac
#补上遗失指令集
Add_path () {
    #设置二进制命令目录位置
    filepath=/data/backup_tools
    busybox="$filepath/busybox"
    if [[ -e $busybox ]]; then
        if [[ ! $(du -k -s $busybox | awk '{print $1}') == $(du -k -s $tools_path/busybox-arm64 | awk '{print $1}') ]]; then
            rm -rf $filepath
            echo "busybox大小不一致，已删除并且重新设置"
        fi
    fi   
    #工具绝对位置  
    if [[ -e $busybox ]]; then        
        if [[ ! -e $filepath/$1 ]]; then
            if [[ $2 == n ]]; then             
                if [[ -e $tools_path/$1 ]]; then                   
                    cp -r $tools_path/$1 $filepath
                    chmod 0777 $filepath/$1                                           
                else 
                    echo "$tools_path/$1不存在 脚本所需的$1缺少"
                    exit 1
                fi
            else
                if [[ -e $3/$1 ]]; then
                    ln -s $3/$1 $filepath
                else
                    echo "错误: $3/$1不存在"
                    exit 1
                fi                      
            fi        
        fi    
        [[ ! -e $filepath/$1 ]] && echo "错误: $filepath/$1不存在" && exit 1
        export PATH=$filepath
        [[ ! $PATH == $filepath ]] && echo "环境变量位置错误" && exit 1        
    else        
        echo "不存在$busybox 设置环境中...."
        if [[ -e $tools_path/busybox-arm64 ]]; then
            [[ ! -d $filepath ]] && mkdir -p $filepath
            cp -r $tools_path/busybox-arm64 $busybox
            chmod 0777 $busybox
            for a in $($busybox --list) ; do
                if [[ -n $a ]]; then                    
                    [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"                    
                fi    
            done
            export PATH=$filepath
            [[ ! $PATH == $filepath ]] && echo "环境变量位置错误" && exit 1        
        else
            echo "错误 缺少$tools_path/busybox-arm64"
            exit 1
        fi
    fi        
}