#!/system/bin/sh
MODDIR="${0%/*}"
#鏈接腳本設置環境變量
tools_path="$MODDIR/tools"
bin_path="$tools_path/bin"
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $tools_path ]] && echo " $tools_path目錄遺失" && exit 1
[[ ! -f $MODDIR/backup_settings.conf ]] && echo "backup_settings.conf遺失" && exit 1
. "$bin_path/bin.sh"
. "$MODDIR/backup_settings.conf"
system="
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"
# 获取默认桌面
launcher_app="$(pm resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | grep '/' | cut -f1 -d '/')"
for launcher_app in $launcher_app; do
	[[ $launcher_app != "android" ]] && [[ $(pgrep -f "$launcher_app" | grep -v 'grep' | wc -l) -ge 1 ]] && launcher_app="$launcher_app"
done
isBoolean "$path" && txtpath="$nsx"
[[ $txtpath = true ]] && txtpath="$PWD" || txtpath="$MODDIR"
nametxt="$txtpath/應用列表.txt"
[[ ! -e $nametxt ]] && echo '#不需要備份的應用請在開頭注釋# 比如#酷安 xxxxxxxx\n#不需要備份數據比如酷安! xxxxxxxx應用名後方加一個驚嘆號即可 注意是應用名不是包名' >"$nametxt"
echo >>"$nametxt"
echoRgb "請勿關閉腳本，等待提示結束"
i=1
bn=118
rm -rf "$MODDIR/tmp"
starttime1="$(date -u "+%s")"
appinfo -sort-i -d " " -o ands,pn -pn $system $launcher_app -3 2>/dev/null | sed 's/\///g ; s/\://g ; s/(//g ; s/)//g ; s/\[//g ; s/\]//g ; s/\-//g' | grep -v 'ice.message' | while read; do
	[[ $bn -ge 229 ]] && bn=118
	app_1=($REPLY $REPLY)
	if [[ $(cat "$nametxt" | grep -oE "${app_1[1]}$") = "" ]]; then
		case ${app_1[1]} in
		oneplus|miui|xiaomi|oppo|flyme|meizu|com.android.soundrecorder|com.mfashiongallery.emag|com.mi.health)
			echoRgb "$REPLY 可能是廠商自帶應用 比對中....." "0"
			if [[ $(appinfo -sort-i -d " " -o ands,pn -xm | grep -w "$REPLY") = $REPLY ]]; then
				echoRgb "為Xposed模塊 進行添加" "1"
				echo "$REPLY" >>"$nametxt" && xz=1 && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
				echoRgb "$i.$REPLY"
			else
				echoRgb "非Xposed模塊 忽略輸出" "0"
			fi
			;;
		*)
			echo "$REPLY" >>"$nametxt" && xz=1 && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
			echoRgb "$i.$REPLY"
			;;
		esac
	else
		unset xz
	fi
	[[ $xz != "" ]] && let i++ bn++
done
[[ -f $nametxt ]] && (sed -ie '/^$/d' "$nametxt" && rm -rf "$MODDIR/應用列表.txte") || (echoRgb "$nametxt生成失敗" "0" && exit 2)
endtime 1
[[ ! -e $MODDIR/tmp ]] && echoRgb "無新增應用" || echoRgb "輸出包名結束 請查看$nametxt"
rm -rf "$MODDIR/tmp"