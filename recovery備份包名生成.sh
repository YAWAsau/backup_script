MODDIR=${0%/*}
[[ $(id -u) -ne 0 ]] && echo " 你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo "$MODDIR" | grep -v 'mt') ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
if [[ -e $MODDIR/appname.sh ]]; then
	sh "$MODDIR/appname.sh" twrp
	if [[ ! -d $MODDIR/recovery/tools ]]; then
		mkdir -p "$MODDIR/recovery/tools"
		cp -r "$MODDIR/tools"/* "$MODDIR/recovery/tools"
		rm -rf "$MODDIR/recovery/tools/busybox_path"
		rm -rf "$MODDIR/recovery/tools/zip"
	fi
else
	echoRgb "$MODDIR/appname.sh遺失"
fi
exit 0