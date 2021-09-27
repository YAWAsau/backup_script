#!/system/bin/sh
MODDIR="${0%/*}"
test "$(id -u)" -ne 0 && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $MODDIR/tools ]] && echo " $MODDIR/tools目錄遺失" && exit 1
#鏈接腳本設置環境變量
md5path="$MODDIR"
tools_path="$MODDIR/tools"
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
		launcher_app="$(pm resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | grep '/' | cut -f1 -d '/')"
		for launcher_app in $launcher_app; do
			if [[ $launcher_app != "" && $launcher_app != "android" ]]; then
				if [[ $(pgrep -f "$launcher_app" | grep -v 'grep' | wc -l) -ge 1 ]]; then
					echo "$launcher_app"
				fi
			fi
		done
	fi
}
isBoolean "$path" && txtpath="$nsx"
[[ $txtpath = true ]] && txtpath="$PWD" || txtpath="$MODDIR"
[[ $backup_path != "" ]] && nametxt="$backup_path/Apkname.txt" || nametxt="$txtpath/Apkname.txt"
echoRgb " 請勿關閉腳本，等待提示結束"
i=1
bn=37
rm -rf "$MODDIR/tmp"
starttime1="$(date -u "+%s")"
appinfo -d " " -o ands,pn -pn $system $(get_launcher) -3 2>/dev/null | sort | sed 's/\///g' | while read name; do
	[[ $bn -ge 37 ]] && bn=31
	[[ ! -e $nametxt ]] && echo '#不需要備份的應用請在開頭注釋# 比如#酷安 xxxxxxxx
#不需要備份數據比如酷安! xxxxxxxx軟件名後方加一個驚嘆號即可 注意是軟件名不是包名' >"$nametxt"
	if [[ $(cat "$nametxt" | sed -e '/^$/d' | sed 's/!//g' | sed 's/！//g' | grep -w "$name") = ""   ]]; then
		echo "$name" >>"$nametxt" && xz=1 && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
		echoRgb "$i.$name"
	else
		unset xz
	fi
	[[ $xz != "" ]] && let i++ bn++
done
endtime 1
[[ ! -e $MODDIR/tmp ]] && echoRgb "無新增應用" || echoRgb " 輸出包名結束 請查看$nametxt"
rm -rf "$MODDIR/tmp"