if [ -f "${0%/*}/tools/bin/tools.sh" ]; then
	MODDIR="${0%/*}"
	operate="backup_media"
	{
		. "${0%/*}/tools/bin/tools.sh" | tee "$MODDIR/log.txt"
	} &
else
	echo "${0%/*}/tools/bin/tools.sh遗失"
fi