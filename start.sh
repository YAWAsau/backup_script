#!/system/bin/sh
if [ -f "${0%/*}/tools/tools.sh" ]; then
    MODDIR="${0%/*}"
    conf_path="${0%/*}/backup_settings.conf"
    [ ! -f "${0%/*}/backup_settings.conf" ] && . "${0%/*}/tools/tools.sh"
else
    echo "${0%/*}/tools/tools.sh遺失"
fi
mkdir -p "${0%/*}/log" 2>/dev/null
logfile="${0%/*}/log/log_$(date +%Y-%m-%d_%H-%M).txt"
. "${0%/*}/tools/tools.sh" | tee "$logfile"
sed -i "$(printf 's/\[[0-9;]*m//g')" "$logfile"
