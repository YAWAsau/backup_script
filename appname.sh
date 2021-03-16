#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不给Root用你妈 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥马不解压缩？用毛缐 憨批" && exit 1
[[ ! -d ${0%/*}/tools ]] && echo "${0%/*}/tools目录遗失" && exit 1
#链接脚本设置环境变量
. ${0%/*}/tools/bin.sh
#设置命令和目录位置及是否使用链接方式
tools_path=${0%/*}/tools
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
Add_path "pm" y $system_path
Add_path "cmd" y $system_path 
Add_path "am" y $system_path 
echo "环境变数: $PATH"

#转换echo颜色提高可读性
echoRgb () {
    if [[ -n $2 ]]; then
        if [[ $3 == 1 ]]; then
            echo -e "\e[1;32m $1\e[0m"
        else
            echo -e "\e[1;31m $1\e[0m"
        fi
    else
        echo -e "\e[1;${bn}m $1\e[0m"
    fi
}
name=$(pm list packages -3 | sed 's/package://g' | grep -v 'xiaomi' | grep -v 'miui')
sys=$(pm list packages -s | egrep 'com.android.chrome|com.google.android.inputmethod.latin|com.digibites.accubattery' | sed 's/package://g')
echo "#不需要恢復还原的应用请在开头注释# 比如#xxxxxxxx 酷安">${0%/*}/Apkname.txt
echo "请勿关闭脚本，等待提示结束"
i=0
bn=37
for name in $name $sys; do    
    [[ $bn -ge 37 ]] && bn=31
    #获取apk中文名称         
    Appname1=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label-zh-CN" | head -1 | sed "s/.*:\'//g" | sed "s/\'//g" | sed 's/ //g')                                
    Appname2=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label-zh-TW:" | sed 's/application-label-zh-TW://g' | sed "s/\'//g" | sed 's/ //g')
    #获取apk默认名称
    Appname3=$(aapt dump badging $(pm path "$name" | cut -f2 -d ':') | grep -w "application-label:" | sed 's/application-label://g' | sed "s/\'//g" | sed 's/ //g')
    [[ ! $(echo $Appname1 | wc -l) == 0  ]] && Appname=$Appname1
    [[ -z $Appname ]] && Appname=$Appname2
    [[ -z $Appname ]] && Appname=$Appname3
    [[ -z $Appname ]] && Appname=$name    
    echoRgb "$i.$Appname"    
    [[ -z $(cat ${0%/*}/Apkname.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$Appname $name">>${0%/*}/tools/tmp
    let i++
    let bn++
done

echo "如果执行中出现AndroidManifest.xml:XX: error: ERROR 代表dump名称错误 以使用包名替代，不影响备份"
echo "整理排列中........"
sort ${0%/*}/tools/tmp | while read o;do
    echo $o>>${0%/*}/Apkname.txt
done
rm -rf ${0%/*}/tools/tmp
echo "输出包名结束 请查看${0%/*}/Apkname.txt"
