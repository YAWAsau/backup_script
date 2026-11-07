#!/system/bin/sh
# Direct web editor; reuse this folder's start.sh profile and safety checks.
_web_file="$0"
case "$_web_file" in */*) ;; *) _web_file="$(command -v "$_web_file" 2>/dev/null)" ;; esac
_web_dir="${_web_file%/*}"
[ "$_web_dir" = "$_web_file" ] && _web_dir=.
_web_dir="$(cd "$_web_dir" 2>/dev/null && pwd -P)" || exit 127
if [ -z "$_web_dir" ] || [ ! -f "$_web_dir/start.sh" ]; then
    echo "SpeedBackup: start.sh is missing from this folder."
    exit 127
fi
export SPEEDBACKUP_WEBUI_ONLY=1
exec /system/bin/sh "$_web_dir/start.sh"
