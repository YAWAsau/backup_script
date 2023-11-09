if [ -f "${0%/*}/tools/bin/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="backup"
	. "${0%/*}/tools/bin/tools.sh" | tee "$MODDIR/log.txt" 
else
	[[ $(echo "${0%/*}" | grep -o 'bin.mt.plus/temp') != "" ]] && echo "你媽沒告訴你腳本要解壓縮嗎？傻逼玩兒" && exit 2
	echo "${0%/*}/tools/bin/tools.sh遺失"
fi