if [ -f "${0%/*}/tools/bin/tools.sh" ]; then
	MODDIR="${0%/*}"
	[[ $(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null) ]] && echo "警告！此腳本不能拿來更新腳本" && exit 2
	. "$MODDIR/tools/bin/tools.sh"
	echoRgb "等待腳本停止中，請稍後....."
	kill_Serve && echoRgb "腳本終止"
	exit
else
	echo "$MODDIR/tools/bin/tools.sh遗失"
fi