#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥馬不解壓縮？用毛線 憨批" && exit 1
#關連腳本設置環境變量
bin="${0%/*}/tools/bin.sh"
if [[ -e $bin ]]; then
    . $bin 
else
    echo "$bin遺失"
    exit 1
fi
#設置命令和目錄位置及是否使用鏈接方式
Add_path
if [[ -d /system/bin ]]; then
    system_path=/system/bin 
else
    if [[ -d /system/xbin ]]; then
        system_path=/system/xbin 
    fi
fi
Add_path "7za" n
Add_path "aapt" n
Add_path "zip" n
Add_path "pm" y $system_path
Add_path "cmd" y $system_path 
Add_path "am" y $system_path 
echo "環境變數: $PATH"

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