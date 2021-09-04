MODDIR=${0%/*}
if [[ -e $MODDIR/appname.sh ]]; then
	sh "$MODDIR/appname.sh" twrp
else
	echo "$MODDIR/appname.sh遺失"
fi
exit 0