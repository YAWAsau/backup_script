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
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"
get_launcher() {
	if [[ $(getprop ro.build.version.sdk) -gt 27 ]]; then
		# 获取默认桌面
		launcher_app=$(pm resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | grep '/' | cut -f1 -d '/')
		for launcher_app in $launcher_app; do
			if [[ $launcher_app != "" && $launcher_app != "android" ]]; then
				if [[ $(pgrep -f "$launcher_app" | grep -v 'grep' | wc -l) -ge 1 ]]; then
					echo "$launcher_app" && Dk=1
				else
					Dk=0
				fi
			fi
		done
	fi
}
isBoolean $path && txtpath=$nsx
[[ $txtpath = true ]] && txtpath=$PWD || txtpath=$MODDIR
echoRgb " 請勿關閉腳本，等待提示結束"
#刪除遺留，防止上次意外中斷腳本殘留的打印包名文件
[[ -e $MODDIR/tools/tmp ]] && rm -rf "$MODDIR"/tools/tmp
i=1
bn=37
#rm -rf "$MODDIR/Apkname.txt"
starttime1=$(date +"%Y-%m-%d %H:%M:%S")
appinfo -d " " -o ands,pn -pn $system $(get_launcher) -3 2>/dev/null | sort | while read name; do
	[[ $bn -ge 37 ]] && bn=31
	if [[ $1 = twrp ]]; then
		app_2=$(echo $name | awk '{print $2}')
		apkpath=$(pm path "$app_2" | cut -f2 -d ':' | head -1)
		nametxt=$MODDIR/recovery.txt
		[[ ! -e $nametxt ]] && echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$nametxt"
		if [[ -z $(cat "$nametxt" | sed -e '/^$/d' | grep -w "$name") ]]; then
			echo "$name ${apkpath%/*}" >>"$nametxt" && xz=1
			echoRgb "$i.$name"
		else
			unset xz
		fi
	else
		nametxt=$txtpath/Apkname.txt
		[[ ! -e $nametxt ]] && echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$nametxt"
		if [[ -z $(cat "$nametxt" | sed -e '/^$/d' | grep -w "$name") ]]; then
			echo "$name" >>"$nametxt" && xz=1
			echoRgb "$i.$name"
		else
			unset xz
		fi
	fi
	[[ -n $xz ]] && let i++
	let bn++
done
endtime 1
if [[ $1 = twrp ]]; then
	echoRgb " 輸出包名結束 請編輯$MODDIR/recovery.txt確認無法開機時需要備份應用"
	[[ ! -d $MODDIR/recovery/tools ]] && mkdir -p "$MODDIR/recovery/tools"
		rm -rf "$MODDIR/recovery/tools"/*
		cp -r "$MODDIR/tools"/* "$MODDIR/recovery/tools"
		rm -rf "$MODDIR/recovery/tools/busybox_path"
		rm -rf "$MODDIR/recovery/tools/zip"
		rm -rf "$MODDIR/recovery/tools/apk"
		rm -rf "$MODDIR/recovery/tools/toast"
else
	echoRgb " 輸出包名結束 請查看$txtpath/Apkname.txt"
fi
exit 0
