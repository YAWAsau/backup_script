MODDIR=${0%/*}
[[ -z $(echo "$MODDIR" | grep -v 'mt') ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $MODDIR/tools ]] && echo "$MODDIR/tools目錄遺失" && exit 1
tools_path=$MODDIR/tools
. "$tools_path/bin.sh"
[[ ! -e $MODDIR/recovery.txt ]] && echoRgb "打包你媽呢？沒有recovery.txt 請執行recovery備份包名生成.sh" "0" "0" && exit 1 || mv "$MODDIR/recovery.txt" "$MODDIR/recovery/script/Apkname.txt"
[[ ! -e $MODDIR/recovery/META-INF/com/google/android/update-binary ]] && echoRgb "update-binary不存在打包失敗" "0" "0" && exit 1
[[ ! -d $MODDIR/recovery/tools ]] && echoRgb "$MODDIR/recovery/tools不存在打包失敗" "0" "0" && exit 2
[[ -e $MODDIR/recovery備份.zip ]] && rm -rf "$MODDIR/recovery備份.zip"
cd "$MODDIR/recovery"
zip -r "recovery備份.zip" "META-INF" "tools" "script"
mv "$MODDIR/recovery/recovery備份.zip" "$MODDIR"
echoRgb "卡刷包路徑:$MODDIR/recovery備份.zip"