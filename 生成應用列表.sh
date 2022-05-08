if [ -f "${0%/*}/tools/bin/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="Getlist"
	. "${0%/*}/tools/bin/tools.sh"
else
	echo "${0%/*}/tools/bin/tools.sh遗失"
fi