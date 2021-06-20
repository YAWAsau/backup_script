#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不给Root用你妈 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥马不解压缩？用毛缐 憨批" && exit 1
[[ ! -d ${0%/*}/tools ]] && echo "${0%/*}/tools目录遗失" && exit 1
#链接脚本设置环境变量
. ${0%/*}/tools/bin.sh
system="
com.android.launcher3
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"
name=$(appinfo -o an,pn -d ⎈ -n $system -3 | sed 's/ //g' | sed 's/⎈/ /g')
echo "#不需要恢復还原的应用请在开头注释# 比如#xxxxxxxx 酷安" >${0%/*}/Apkname.txt
echo "请勿关闭脚本，等待提示结束"
#删除遗留，防止上次意外中断脚本残留的打印包名文件
[[ -e ${0%/*}/tools/tmp ]] && rm -rf ${0%/*}/tools/tmp
echoRgb() {
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
i=1
bn=37
echo "$name" | while read name; do
	[[ $bn -ge 37 ]] && bn=31
	echoRgb "$i.$name"
	[[ -z $(cat ${0%/*}/Apkname.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name" >>${0%/*}/tools/tmp
	let i++
	let bn++
done
#dump_name "$g"
echo "如果执行中出现AndroidManifest.xml:XX: error: ERROR 代表dump名称错误 以使用包名替代，不影响备份"
echo "整理排列中........"
sort ${0%/*}/tools/tmp | while read o; do
	echo $o >>${0%/*}/Apkname.txt
done
rm -rf ${0%/*}/tools/tmp
echo "输出包名结束 请查看${0%/*}/Apkname.txt"