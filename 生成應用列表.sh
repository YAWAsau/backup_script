if [ -f "${0%/*}/tools/tools.sh" ]; then
    MODDIR="${0%/*}"
    operate="Getlist"
    conf_path="${0%/*}/backup_settings.conf"
    . "${0%/*}/tools/tools.sh" | tee "$MODDIR/log.txt"
else
    echo "${0%/*}/tools/tools.sh遺失"
fi
