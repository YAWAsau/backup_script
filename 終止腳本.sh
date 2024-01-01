if [ -f "${0%/*}/tools/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="kill_script"
	[[ $(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null) ]] && echo "警告！此腳本不能拿來更新腳本" && exit 2
	. "$MODDIR/tools/tools.sh"
	echoRgb "等待腳本停止中，請稍後....."
	kill_Serve && echoRgb "腳本終止"
	exit
else
	[[ $(echo "${0%/*}" | grep -o 'bin.mt.plus/temp') != "" ]] && echo "你媽沒告訴你腳本要解壓縮嗎？傻逼玩兒" && exit 2
	echo "${0%/*}/tools/tools.sh遺失"
fi