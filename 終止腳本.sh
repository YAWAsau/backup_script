if [ -f "${0%/*}/tools/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="kill_script"
	conf_path="${0%/*}/backup_settings.conf"
	. "$MODDIR/tools/tools.sh"
	echoRgb "等待腳本停止中，請稍後....."
	kill_Serve && echoRgb "腳本終止"
	exit
else
	[[ $(echo "${0%/*}" | grep -o 'bin.mt.plus/temp') != "" ]] && echo "你媽沒告訴你腳本要解壓縮嗎？傻逼玩兒" && exit 2
	echo "${0%/*}/tools/tools.sh遺失"
fi
