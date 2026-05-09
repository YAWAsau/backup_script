#!/system/bin/sh
if [ ! -f "${0%/*}/tools/tools.sh" ]; then
	echo "${0%/*}/tools/tools.sh遺失"
	exit 1
fi

MODDIR="${0%/*}"
conf_path="${0%/*}/backup_settings.conf"

# 若配置文件不存在，啟動腳本自動生成默認配置後退出
if [ ! -f "$conf_path" ]; then
	. "${0%/*}/tools/tools.sh"
	exit 0
fi

. "${0%/*}/tools/tools.sh" | tee "${0%/*}/log_$(date +%Y-%m-%d_%H-%M).txt"
