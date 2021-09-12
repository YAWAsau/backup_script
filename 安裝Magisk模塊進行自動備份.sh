MODDIR="${0%/*}"
Magisk=true
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $MODDIR/tools ]] && echo "$MODDIR/tools目錄遺失" && exit 1
[[ ! -d $MODDIR/Magisk_Module ]] && echo "$MODDIR/Magisk_Module目錄遺失" && exit 1
tools_path="$MODDIR/tools"
. "$tools_path/bin.sh"
#開始安裝Magisk模塊
magisk_Module_path="/data/adb/modules/backup"
#備份資料夾路徑
backup_path=/data/media/0/Android/backup_script
[[ ! -d ${magisk_Module_path%/*} ]] && echoRgb "沒有安裝Magisk或是裝了Magisk Lite" "0" "0"
if [[ ! -d $magisk_Module_path ]]; then
	echoRgb "不存在Magisk模塊 正在創建"
	mkdir -p "$magisk_Module_path" && cp -r "$MODDIR/Magisk_Module" "$magisk_Module_path/recovery" && cp -r "$MODDIR/tools" "$magisk_Module_path/recovery" && cp -r "$magisk_Module_path/recovery/tools/Magisk_backup" "$magisk_Module_path/backup2.sh"
	mkdir -p "$magisk_Module_path/cron.d" && mkdir -p "$backup_path"
	tail -n +60 "$0" >"$magisk_Module_path/backup.sh"
	unset PATH
	sh "$magisk_Module_path/backup.sh" &
	unset PATH
	. $MODDIR/appname.sh
	echoRgb "請編輯$nametxt中需要自動備份的軟件(不包含卡刷包備份)"
else
	echoRgb "滾你媽的 已經裝過了別再裝了 傻逼" "0" "0" && exit 2
fi
echo 'id=backup
name=數據備份
version=8.8.9
versionCode=1
author=落葉淒涼(高雄佬) 
description=自動生成卡刷包並於間隔一小時監控第三方軟件數量進行卡刷包生成服務，防止突然不能開機時丟失軟件 生成的卡刷包必須進入recovery刷入進行備份 凌晨3點進行總體數據備份'>"$magisk_Module_path/module.prop"

echo '#!/system/bin/sh
#2020/10/10
wait_start=1
until [[ $(getprop sys.boot_completed) -eq 1 && $(dumpsys window policy | grep "mInputRestricted" | cut -d= -f2) = false ]]; do
	sleep 1
	[[ $wait_start -ge 180 ]] && exit 1
	let wait_start++
done
MODDIR=${0%/*}'>"$magisk_Module_path/service.sh"
echo "alias busybox=$filepath/busybox">>"$magisk_Module_path/service.sh"
echo 'chmod -R 777 "$MODDIR"
busybox crond -c "$MODDIR/cron.d"
if [[ $(pgrep -f "backup/cron.d" | grep -v grep | wc -l) -ge 1 ]]; then
	echo "$(date '+%T') backup: backup cron.d啟動成功">>/data/media/0/Android/backup_script/卡刷包生成資訊.txt
fi
'>>"$magisk_Module_path/service.sh"
echo "0 */1 * * * $filepath/bash $magisk_Module_path/backup.sh
0 03 * * * $filepath/bash $magisk_Module_path/backup2.sh">"$magisk_Module_path/cron.d/root"
sh "$magisk_Module_path/service.sh"

echo '#是否備份外部數據 即比如原神的數據包(1備份0不備份)
B=0

#壓縮算法(可用lz4 zstd tar tar為僅打包 有什麼好用的壓縮算法請聯繫我
#lz4壓縮最快，但是壓縮率略差 zstd擁有良好的壓縮率與速度 當然慢於lz4
Compression_method=zstd'>/data/media/0/Android/backup_script/backup_settings.conf
exit
#!/system/bin/sh
#2020/10/10
MODDIR=${0%/*}
tools_path="$MODDIR/recovery/tools"
. "$tools_path/bin.sh"
zip_out="/data/media/0/Android/backup_script"
system="
com.google.android.apps.messaging
com.digibites.accubattery
com.google.android.inputmethod.latin
com.android.chrome"
log() {
	echo "$(date '+%T') $1: $2" >>"$zip_out/卡刷包生成資訊.txt"
}
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
touch_backup() {
	appinfo -d " " -o pn -pn $system $(get_launcher) -3 | wc -l >$MODDIR/Quantity
	nametxt="$MODDIR/recovery/script/Apkname.txt"
	appinfo -d " " -o ands,pn -pn $system $(get_launcher) -3 2>/dev/null | sort | while read name; do
		apkpath="$(pm path "$(echo "$name" | awk '{print $2}')" | cut -f2 -d ':' | head -1)"
		[[ ! -e $nametxt ]] && echo "#不需要備份的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$nametxt"
		if [[ $(cat "$nametxt" | sed -e '/^$/d' | grep -w "$name") = "" ]]; then
			echo "$name ${apkpath%/*}" >>"$nametxt"
		fi
	done
	if [[ -e $MODDIR/recovery/META-INF/com/google/android/update-binary ]]; then
		cd "$MODDIR/recovery"
		if [[ -e $nametxt ]]; then
			zip -r "recovery備份.zip" "META-INF" "tools" "script" -x "tools/lz4" -x "tools/toast" -x "tools/apk/*" -x "tools/zip" -x "tools/busybox_path" -x "tools/Magisk_backup" -x "tools/bash"
			[[ ! -d $zip_out ]] && mkdir -p "$zip_out"
			mv "$MODDIR/recovery/recovery備份.zip" "$zip_out" 
			echoRgb "輸出:$zip_out"
		fi
	fi
}
[[ ! -f $MODDIR/Quantity ]] && touch_backup && log "backup" "首次生成備份卡刷包 輸出:$zip_out"
apk_quantity="$(cat "$MODDIR/Quantity")"
if [[ $(appinfo -d " " -o pn -pn $system $(get_launcher) -3 | wc -l) != $apk_quantity ]]; then
	touch_backup && log "backup" "軟件$apk_quantity>$(cat "$MODDIR/Quantity")發生變化 生成卡刷包 輸出:$zip_out"
else
	log "backup" "軟件數量無變化"
fi