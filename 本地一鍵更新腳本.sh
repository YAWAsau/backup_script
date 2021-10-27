MODDIR="${0%/*}"
#鏈接腳本設置環境變量
tools_path="$MODDIR/tools"
bin_path="$tools_path/bin"
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $tools_path ]] && echo " $tools_path目錄遺失" && exit 1
. "$bin_path/bin.sh"
[[ $(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f) = "" ]] && echoRgb "警告 未找到任何zip 請將下載的備份腳本.zip\n -放入當前目錄中\n -當前路徑$MODDIR" "0"
find "$MODDIR" -maxdepth 1 -name "*.zip" -type f | while read; do
	if [[ $(unzip -l "$REPLY" | awk '{print $4}' | grep -oE "^backup_settings.conf$") != "" ]]; then
		unzip -o "$REPLY" -d "$MODDIR" && (
		echoRgb "解壓縮${REPLY##*/}成功" "1"
		case $MODDIR in
		*Backup_*)
			echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+tools目錄"
			cp -r "$tools_path/script/Get_DirName" "$MODDIR/掃描資料夾名.sh" && cp -r "$tools_path/script/restore" "$MODDIR/還原備份.sh"
			find "$MODDIR" -maxdepth 1 -type d | sort | sed 's/\[/ /g ; s/\]//g' | while read; do
				if [[ -f $REPLY/app_details ]]; then
					unset PackageName
					. "$REPLY/app_details"
					if [[ $PackageName != "" ]]; then
						cp -r "$tools_path/script/restore2" "$REPLY/還原備份.sh"
					fi
				fi
			done
			rm -rf "$tools_path/script" "$tools_path/META-INF" "$tools_path/bin/zip" "$MODDIR/backup_settings.conf" "$MODDIR/備份應用.sh" "$MODDIR/生成應用列表.sh" ;;
		*)
			if [[ $(find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d) != "" ]]; then
				find "$MODDIR" -maxdepth 1 -name "Backup_*" -type d | while read backup_path; do
					if [[ -d $backup_path && $backup_path != $MODDIR ]]; then
						echoRgb "更新當前目錄下備份相關腳本&tools目錄+${backup_path##*/}內tools目錄+恢復腳本+tools"
						cp -r "$tools_path" "$backup_path" && rm -rf "$backup_path/tools/bin/zip" "$backup_path/tools/META-INF" "$backup_path/tools/script"
						cp -r "$tools_path/script/restore" "$backup_path/還原備份.sh"
						cp -r "$tools_path/script/Get_DirName" "$backup_path/掃描資料夾名.sh"
						find "$MODDIR" -maxdepth 2 -type d | sort | sed 's/\[/ /g ; s/\]//g' | while read; do
							if [[ -f $REPLY/app_details ]]; then
								unset PackageName
								. "$REPLY/app_details"
								[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/還原備份.sh"
							fi
						done
					fi
				done
			else
				echoRgb "更新當前${MODDIR##*/}目錄下備份相關腳本+tools目錄"
			fi ;;
		esac) || (echoRgb "解壓縮${REPLY##*/}失敗" "0" && exit 2)
	else
		echoRgb "${REPLY##*/}並非指定的備份zip" "0"
	fi
done