if [ -f "${0%/*}/tools/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="Device_List"
	. "${0%/*}/tools/tools.sh" | tee "$MODDIR/log.txt"
else
	[[ $(echo "${0%/*}" | grep -o 'bin.mt.plus/temp') != "" ]] && echo "你妈没告诉你脚本要解压缩吗？傻逼玩儿" && exit 2
	echo "${0%/*}/tools/tools.sh遗失"
fi