MODDIR="${0%/*}"
#鏈接腳本設置環境變量
tools_path="$MODDIR/tools"
bin_path="$tools_path/bin"
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $tools_path ]] && echo " $tools_path目錄遺失" && exit 1
. "$bin_path/bin.sh"
zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
if [[ $zippath != "" ]]; then
	case $(echo "$zippath" | wc -l) in
	1)
		echoRgb "從$zippath更新" ;;
	*)
		echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)" "0" && exit 1 ;;
	esac
else
	echoRgb "從GitHub更新"
	down -s -A s "https://api.github.com/repos/YAWAsau/backup_script/releases/latest" | jq -r '.tag_name'>"$bin_path/tag" ; tag="$(cat "$bin_path/tag" 2>/dev/null)"
	if [[ $backup_version != $(down -s -A s "https://api.github.com/repos/YAWAsau/backup_script/releases/latest" | jq -r '.tag_name') ]]; then
		down -o "$MODDIR/$tag.zip" "https://gh.api.99988866.xyz/$(down -s -A s "https://api.github.com/repos/YAWAsau/backup_script/releases/latest" | sed -r -n 's/.*"browser_download_url": *"(.*.zip)".*/\1/p')"
		echo_log "下載$tag.zip"
		if [[ $result = 0 ]]; then
			zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
		else
			echoRgb "請手動將備份腳本壓縮包放置在\n -$MODDIR後再次執行腳本進行更新" "0" && exit 2
		fi
	else
		echoRgb "本地版本:$backup_version 線上版本:$tag 版本一致無須更新" && exit
	fi
fi
[[ $(unzip -l "$zippath" | awk '{print $4}' | grep -oE "^backup_settings.conf$") = "" ]] && echoRgb "${zippath##*/}並非指定的備份zip" "0" && exit 2
unzip -o "$zippath" -d "$MODDIR"
echo_log "解壓縮${zippath##*/}"
if [[ $result = 0 ]]; then
	case $MODDIR in
	*Backup_*)
		echoRgb "更新當前${MODDIR##*/}目錄下恢復相關腳本+tools目錄"
		cp -r "$tools_path/script/Get_DirName" "$MODDIR/掃描資料夾名.sh"
		cp -r "$tools_path/script/restore" "$MODDIR/還原備份.sh"
		[[ -d $MODDIR/媒體 ]] && cp -r "$tools_path/script/restore3" "$MODDIR/媒體/恢復多媒體數據.sh"
		find "$MODDIR" -maxdepth 1 -type d | sort | while read; do
			if [[ -f $REPLY/app_details ]]; then
				unset PackageName
				. "$REPLY/app_details"
				[[ $PackageName != "" ]] && cp -r "$tools_path/script/restore2" "$REPLY/還原備份.sh"
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
					cp -r "$MODDIR/本地一鍵更新腳本.sh" "$backup_path/本地一鍵更新腳本.sh"
					[[ -d $backup_path/媒體 ]] && cp -r "$tools_path/script/restore3" "$backup_path/媒體/恢復多媒體數據.sh"
					find "$MODDIR" -maxdepth 2 -type d | sort | while read; do
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
	esac
fi
find "$MODDIR" -maxdepth 1 -name "*.zip" -type f -exec rm -rf {} \;