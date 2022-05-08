if [ -f "${0%/*}/tools/bin/bin.sh" ]; then
	MODDIR="${0%/*}"
	bin_path="$MODDIR/tools/bin"
	[[ $(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null) ]] && echo "警告！此腳本不能拿來更新腳本" && exit 2
	. "$MODDIR/tools/bin/bin.sh"
	touch "$TMPDIR/STOP_script"
	echoRgb "等待腳本停止中，請稍後....."
	{
	while [[ -f $TMPDIR/STOP_script ]]; do
		sleep 1
	done
	} &
	wait && echoRgb "已經停止" "1"
	exit
else
	echo "$MODDIR/tools/bin/bin.sh遗失"
fi