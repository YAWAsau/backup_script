#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥馬不解壓縮？用毛線 憨批" && exit 1
filepath=/data/adb/busybox/bin
#檢測是否存在Magisk busybox
if [[ -e /data/adb/magisk/busybox.bin ]]; then
    if [[ ! -d $filepath ]]; then
        mkdir -p $filepath
        cp -r /data/adb/magisk/busybox.bin $filepath 
        mv $filepath/busybox.bin $filepath/busybox
        busybox="$filepath/busybox"   
    else
        if [[ -e $filepath/busybox.bin ]]; then
            mv $filepath/busybox.bin $filepath/busybox
        fi
        busybox="$filepath/busybox"
    fi
else
    if [[ -e /data/adb/magisk/busybox ]]; then
        if [[ ! -d $filepath ]]; then
            mkdir -p $filepath
            cp -r /data/adb/magisk/busybox $filepath
            busybox="$filepath/busybox"
        else
            busybox="$filepath/busybox"
        fi
    else
        echo "沒有發現Magisk busybox"
    fi
fi
if [[ -e $busybox ]]; then   
    echo "busybox path: $busybox"
    chmod 0777 $busybox
    echo "發現Magisk Busybox....正在替換環境變量為Busybox防止簡陋的toybox缺少重要命令"
    for a in $($busybox --list) ; do
        if [[ -n $a ]]; then
            if [[ -d $filepath ]]; then
                [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"
            fi    
        fi    
    done
    unset PATH    
fi
#安装aapt
#補上遺失指令集
Add_path () {
    if [[ ! -e $filepath/$1 ]]; then
        if [[ -e $2/$1 ]]; then
            if [[ $3 == y ]]; then                
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

Add_path "zip" ${0%/*}/bin y
Add_path "aapt" ${0%/*}/bin y
Add_path "pm" /system/bin n
Add_path "cmd" /system/bin n
export PATH=$PATH:/data/adb/busybox/bin  
name=$(pm list packages -3 | sed 's/package://g' | grep -v 'xiaomi' | grep -v 'miui')
sys=$(pm list packages | egrep 'com.android.chrome|com.google.android.inputmethod.latin|com.digibites.accubattery' | sed 's/package://g')
echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安">${0%/*}/Apkname.txt
echo "請勿關閉腳本，等待提示結束"
for name in $name $sys; do
   #获取apk中文名称                                 
   Appname1=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label-zh-CN" | head -1 | sed "s/.*:\'//g" | sed "s/\'//g")
   Appname2=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label-zh-TW:" | sed 's/application-label-zh-TW://g' | sed "s/\'//g")
   #获取apk默认名称
   Appname3=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label:" | sed 's/application-label://g' | sed "s/\'//g")
   [[ $(echo $Appname1 | wc -l) -eq 1 ]] && Appname=$(echo $Appname1 | sed 's/ //g')
   [[ -z $Appname ]] && Appname=$(echo $Appname2 | sed 's/ //g')
   [[ -z $Appname ]] && Appname=$(echo $Appname3 | sed 's/ //g')
   [[ -z $Appname ]] && Appname=$name
   [[ -z $(cat ${0%/*}/Apkname.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$Appname $name">>${0%/*}/Apkname.txt
done
echo "如果執行中出現AndroidManifest.xml:XX: error: ERROR 代表dump名稱錯誤 以使用包名替代，不影響備份"
echo "輸出包名結束 請查看${0%/*}/Apkname.txt"