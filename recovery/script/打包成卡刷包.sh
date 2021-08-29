MODDIR=${0%/*}
[[ ! -d ${MODDIR%/*}/tools ]] && echo "${MODDIR%/*}/tools目錄遺失" && exit 1
tools_path=${MODDIR%/*/*}/tools
. "$tools_path/bin.sh"
[[ -e ${MODDIR%/*/*}/recovery備份.zip ]] && rm -rf "${MODDIR%/*/*}/recovery備份.zip"
cd "${MODDIR%/*/*}/recovery"
zip -r "recovery備份.zip" "META-INF" "tools" "script" -x "script/打包成卡刷包.sh"
mv "${MODDIR%/*}/recovery備份.zip" "${MODDIR%/*/*}"
echoRgb "卡刷包路徑:${MODDIR%/*/*}/recovery備份.zip"