if [ -f "${0%/*}/tools/bin/tools" ]; then
	MODDIR="${0%/*}"
	operate="Getlist"
	. "${0%/*}/tools/bin/tools"
else
	echo "${0%/*}/tools/bin/tools遺失"
fi