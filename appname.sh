#!/system/bin/sh
MODDIR=${0%/*}
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo $MODDIR | grep -v 'mt') ]] && echo "草泥馬不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $MODDIR/tools ]] && echo "$MODDIR/tools目錄遺失" && exit 1
#鏈接腳本設置環境變量
md5path="$MODDIR"
tools_path=$MODDIR/tools
. $tools_path/bin.sh
system="
com.android.launcher3
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"

echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >$MODDIR/Apkname.txt
echo "請勿關閉腳本，等待提示結束"
#刪除遺留，防止上次意外中斷腳本殘留的打印包名文件
[[ -e $MODDIR/tools/tmp ]] && rm -rf $MODDIR/tools/tmp
i=1
bn=37
#echo -n ""> $MODDIR/Apkname.txt
appinfo -d " " -o ands,pn -pn $system -3 | sort | while read name; do
	[[ $bn -ge 37 ]] && bn=31
	echoRgb "$i.$name"
	[[ -z $(cat $MODDIR/Apkname.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name" >>$MODDIR/Apkname.txt
	let i++
	let bn++
done
echo "輸出包名結束 請查看$MODDIR/Apkname.txt"
