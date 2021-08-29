#!/system/bin/sh
MODDIR=${0%/*}
[[ $(id -u) -ne 0 ]] && echo " 你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo "$MODDIR" | grep -v 'mt') ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $MODDIR/tools ]] && echo " $MODDIR/tools目錄遺失" && exit 1
#鏈接腳本設置環境變量
md5path="$MODDIR"
tools_path=$MODDIR/tools
. "$tools_path/bin.sh"
. "$MODDIR/backup_settings.conf"
system="
com.android.launcher3
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"
isBoolean $path && txtpath=$nsx
[[ $txtpath = true ]] && txtpath=$PWD || txtpath=$MODDIR
echoRgb " 請勿關閉腳本，等待提示結束"
#刪除遺留，防止上次意外中斷腳本殘留的打印包名文件
[[ -e $MODDIR/tools/tmp ]] && rm -rf "$MODDIR"/tools/tmp
i=1
bn=37
#echo -n ""> $MODDIR/Apkname.txt
starttime1=$(date +"%Y-%m-%d %H:%M:%S")
appinfo -d " " -o ands,pn -pn "$system" -3 2>/dev/null | sort | while read name; do
	app_1=$(echo $name | awk '{print $1}')
	app_2=$(echo $name | awk '{print $2}')
	[[ $bn -ge 37 ]] && bn=31
	echoRgb "$i.$name"
	if [[ $1 = twrp ]]; then
		apkpath=$(pm path "$app_2" | cut -f2 -d ':' | head -1)
		nametxt=$MODDIR/recovery.txt
		[[ ! -e $nametxt ]] && echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$nametxt"
		[[ -z $(cat "$nametxt" | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name ${apkpath%/*}" >>"$nametxt"
	else
		nametxt=$txtpath/Apkname.txt
		[[ ! -e $nametxt ]] && echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$nametxt"
		[[ -z $(cat "$nametxt" | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name" >>"$nametxt"
	fi
	let i++
	let bn++
done
endtime 1
[[ $1 = twrp ]] && echoRgb " 輸出包名結束 請編輯$MODDIR/recovery.txt確認無法開機時需要備份應用" || echoRgb " 輸出包名結束 請查看$txtpath/Apkname.txt"
exit 0
