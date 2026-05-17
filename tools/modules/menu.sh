Getlist() {
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內生成列表" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	case $Lo in
	0)
		[[ $blacklist_mode != "" ]] && isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx" || {
		echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
		get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
		} ;;
	1)
		if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
		    [[ $blacklist_mode = "" ]] && {
		    echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
		    get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
		    } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		fi ;;
	2)
	    [[ $blacklist_mode = "" ]] && {
	    Enter_options "選擇黑名單模式輸入1不輸出，輸入0輸出應用列表" "不輸出" "輸出應用列表" && isBoolean "$parameter" "blacklist_mode" && blacklist_mode="$nsx"
	    } || {
	    isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
	    } ;;
	*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
	esac
	txt="$TMPDIR/appList"
	[[ -f "$MODDIR/appList.txt" ]] && cat "$MODDIR/appList.txt" >"$txt"
	[[ ! -f $txt ]] && echo '#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）' >"$txt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	starttime1="$(date -u "+%s")"
	echoRgb "提示! 腳本默認會屏蔽預裝應用 如需備份請添加預裝應用白名單" "0"
	Apk_info="$(appinfo "system|user|xposed" "label|pkgName|flag" | grep -Ev 'ice.message|com.topjohnwu.magisk' | tr '/:' '_')"
	xposed_name="$(echo "$Apk_info" | awk '$3 == "xposed" {print $2}')"
	TARGET_PACKAGES="$(echo "$system" | paste -sd'|' - | sed 's/^|//')"
    Pre_installed_apps="$(echo "$Apk_info" | awk '$3 == "system" {print $1, $2}' | grep -Ew "$TARGET_PACKAGES")"
    Apk_info="$(echo "$(echo "$Apk_info" | awk '$3 != "system" {print $1, $2}')\n$Pre_installed_apps" | sort -u)"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	exit 2 ; } || Apk_info2="$(echo "$Apk_info" | cut -d' ' -f2)"
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	rb="0"
	Output_list() {
	    if [[ $(cat "$txt" | cut -f2 -d ' ' | grep -Ew "^${app_1[1]}$") != ${app_1[1]} ]]; then
	        [[ $REPLY2 = "" ]] && add_entry "${app_1[2]}" "${app_1[1]}" "$(grep -w "${app_1[2]}" "$txt")" || add_entry "${app_1[2]}" "${app_1[1]}" "$REPLY2"
	        case ${app_1[1]} in
			    *oneplus*|*miui*|*xiaomi*|*oppo*|*flyme*|*meizu*|com.android.soundrecorder|com.mfashiongallery.emag|com.mi.health|*coloros*|com.android.soundrecorder|com.duokan.phone.remotecontroller|com.android.calendar|com.android.deskclock|com.android.calendar|com.android.deskclock|com.google.android.safetycore|com.google.android.contactkeys|com.google.android.apps.messaging|com.google.android.calendar)
				    if [[ $(echo "$xposed_name" | grep -Ew "${app_1[1]}$") = ${app_1[1]} ]]; then
    				    echoRgb "$((i+1)):$app_name為Xposed模塊 進行添加" "0"
					    if [[ $REPLY2 = "" ]]; then
					        REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    else
					        REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					    fi
					    let i++ rd++
				    else
					    if [[ $(echo "$whitelist" | grep -Ew "^${app_1[1]}$") = ${app_1[1]} ]]; then
					        if [[ $REPLY2 = "" ]]; then
					            REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					        else
					            REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					        fi
						    echoRgb "$((i+1)):$app_name ${app_1[1]}($rgb_a)"
						    let i++
					    else
						    echoRgb "$app_name 預裝應用 忽略輸出" "0"
						    if [[ $REPLY2 = "" ]]; then
    						    REPLY2="#$REPLY" && [[ $tmp = "" ]] && tmp="1"
						    else
						        REPLY2="$REPLY2\n#$REPLY" && [[ $tmp = "" ]] && tmp="1"
						    fi
						    let rc++
					    fi
				    fi
				    ;;
			    *)
				    if [[ $REPLY2 = "" ]]; then
					    REPLY2="$REPLY" && [[ $tmp = "" ]] && tmp="1"
					else
					    REPLY2="$REPLY2\n$REPLY" && [[ $tmp = "" ]] && tmp="1"
					fi
					if [[ $(echo "$xposed_name" | grep -Ew "${app_1[1]}$") = ${app_1[1]} ]]; then
			            echoRgb "$((i+1)):Xposed: $app_name ${app_1[1]}($rgb_a)"
			            let rd++
			        else
				        echoRgb "$((i+1)):$app_name ${app_1[1]}($rgb_a)"
				    fi
				    let i++
				    ;;
			esac
		else
	        let Q++
        fi
    }
    [[ $(echo "$blacklist" | grep -Ev '#|＃') != "" ]] && NZK=1
	echo "$Apk_info" | sed 's/[\/:()\[\]\-!]//g' | while read -r; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_1=($REPLY $REPLY)
		if [[ $NZK = 1 ]]; then
    		if [[ $(echo "$blacklist" | grep -Ew "^${app_1[1]}$") != ${app_1[1]} ]]; then
		        Output_list
		    else
		        if [[ $blacklist_mode = false ]]; then
		            Output_list
		            let rb++
		        else
		            echoRgb "${app_1[2]}黑名單應用 不輸出" "0"
		            let rb++
		        fi
		    fi
		else
		    Output_list
		fi
		if [[ $LR = $Apk_Quantity ]]; then
		    echo "$REPLY2">>"$txt"
			if [[ $(cat "$txt" | wc -l | awk '{print $1-2}') -lt $i ]]; then
				rm -rf "$txt"
				echoRgb "\n -輸出異常 請聯繫作者解決" "0"
				exit
			fi
			echoRgb "已經將預裝應用輸出至appList.txt並注釋# 需要備份則去掉#" "0"
			[[ $tmp != "" ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let rgb_a++ LR++
	done
	if [[ -f $txt ]]; then
	    while read -r ; do
    	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
                app=($REPLY $REPLY)
    		    if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	                if [[ $(echo "$Apk_info2" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') != "" ]]; then
			            [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
    			        Tmplist="$Tmplist\n$REPLY"
    			    else
                        echoRgb "$REPLY不存在系統，從列表中刪除" "0"
                    fi
                fi
            else
                Tmplist="$Tmplist\n$REPLY"
			fi
    	done < "$txt"
    	[[ $Tmplist != "" ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
    fi
	wait
	endtime 1
	cat "$txt">"$MODDIR/appList.txt" && rm "$txt"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$MODDIR/appList.txt"
	echoRgb "輸出包名結束 請查看$MODDIR/appList.txt"
}
backup_media() {
	self_test
	backup_path
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(echo "$Custom_path" | grep -Ev '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
		[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
		[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
		app_details="$Backup_folder/app_details.json"
		[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
		filesize="$(find "$Backup_folder" -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END {print s}')"
		mediatxt="$Backup/mediaList.txt"
		[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
		Set_screen_pause_seconds on
		notification "109" "Media備份開始"
		echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read -r; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")" 
			if [[ ${REPLY##*/} = adb ]]; then
			    if [[ $ksu != ksu ]]; then
			        echoRgb "Magisk adb"
				    Backup_data "${REPLY##*/}" "$REPLY"
				fi
			else
			    Backup_data "${REPLY##*/}" "$REPLY"
			fi
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
		done
		Calculate_size "$Backup_folder"
		Set_screen_pause_seconds off
		[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
		endtime 1 "自定義備份"
		notification "109" "Media備份完成 $(endtime 1 "自定義備份")"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
}
Device_List() {
    URL="https://raw.githubusercontent.com/KHwang9883/MobileModels/refs/heads/master/brands"
    rm -rf "$tools_path/Device_List"
    for i in $(echo "xiaomi\nxiaomi_en\nsamsung\nsamsung_global\nasus\nBlack_Shark\nBlack_Shark_en\ngoogle\nLenovo\nMEIZU\nMEIZU_en\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nOnePlus_en\nSony\nrealme\nrealme_en\nvivo\nvivo_en\noppo\noppo_en"); do
        echoRgb "獲取品牌$i"
        case $i in
        xiaomi) Brand_URL="$URL/xiaomi.md" ;;
        xiaomi_en) Brand_URL="$URL/xiaomi_en.md" ;;
        samsung) Brand_URL="$URL/samsung_cn.md" ;;
        samsung_global) Brand_URL="$URL/samsung_global_en.md" ;;
        asus) Brand_URL="$URL/asus.md" ;;
        Black_Shark) Brand_URL="$URL/blackshark.md" ;;
        Black_Shark_en) Brand_URL="$URL/blackshark_en.md" ;;
        google) Brand_URL="$URL/google.md" ;;
        Lenovo) Brand_URL="$URL/lenovo.md" ;;
        MEIZU) Brand_URL="$URL/meizu.md" ;;
        MEIZU_en) Brand_URL="$URL/meizu_en.md" ;;
        Motorola) Brand_URL="$URL/motorola.md" ;;
        Nokia) Brand_URL="$URL/nokia.md" ;;
        nothing) Brand_URL="$URL/nothing.md" ;;
        nubia) Brand_URL="$URL/nubia.md" ;;
        OnePlus) Brand_URL="$URL/oneplus.md" ;;
        OnePlus_en) Brand_URL="$URL/oneplus_en.md" ;;
        Sony) Brand_URL="$URL/sony_cn.md" ;;
        realme) Brand_URL="$URL/realme_cn.md" ;;
        realme_en) Brand_URL="$URL/realme_global_en.md" ;;
        vivo) Brand_URL="$URL/vivo_cn.md" ;;
        vivo_en) Brand_URL="$URL/vivo_global_en.md" ;;
        oppo) Brand_URL="$URL/oppo_cn.md" ;;
        oppo_en) Brand_URL="$URL/oppo_global_en.md" ;;
        esac
        if [[ ! -e $tools_path/Device_List ]]; then
            down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/'>"$tools_path/Device_List"
        else
            down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read -r; do
                unset model
                model="$(echo "$REPLY" | awk -F'"' '{print $2}')"
                if [[ $(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') != $model ]]; then
                    echo "$REPLY">>"$tools_path/Device_List"
                else
                    echo "$(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') = $model"
                fi
            done
        fi
    done
    if [[ -e $tools_path/Device_List ]]; then
        if [[ $(ls -l "$tools_path/Device_List" | awk '{print $5}') -gt 1 ]]; then
    		[[ $shell_language = zh-TW ]] && ts <"$tools_path/Device_List">temp && cp temp "$tools_path/Device_List" && rm temp
            echoRgb "已下載機型列表在$tools_path/Device_List"
        else
            echoRgb "下載機型失敗"
        fi
    else
        echoRgb "下載機型失敗"
    fi
}
wifi() {
    backup_path
    [[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
    backup_wifi "$Backup/wifi"
    [[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
}
if [[ $0 = *backup.sh ]]; then
	start=backup
elif [[ $0 = *upload.sh ]]; then
	_upload_app="${0%/*}"
	_upload_app="${_upload_app##*/}"
	start="single_upload \"$_upload_app\""
else
	[[ $0 = *recover.sh ]] && start=Restore
fi
if [[ $start != "" ]]; then
    case $(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}') in
    0)
        eval "$start" ;;
    1)
        {
        eval "$start"
        } & ;;
    esac
else
	# 緩存不變的設定值 (避免每輪重複讀取)
	background="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
	# 定義選單 (配置不會在執行中變化)
    if [[ -f $MODDIR/backup_settings.conf ]]; then
        steps=(
            "生成應用列表"
            "備份應用"
            "備份已更新應用"
            "備份自定義資料夾"
            "備份WiFi"
            "測試遠端連線"
            "單獨上傳當前備份"
            "列出遠端備份(產生 appList_network.txt)"
            "從遠端下載備份"
            "殺死運行中腳本"
        )
        commands=(
            "Getlist"
            "backup"
            "backup_update_apk"
            "backup_media"
            "wifi"
            "remote_test"
            "upload_current_backup"
            "remote_list_backups"
            "remote_download_backup"
            "echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
        )
    elif [[ -f $MODDIR/restore_settings.conf ]]; then
        steps=(
            "重新生成應用列表"
            "恢復備份"
            "僅恢復包含ssaid應用(含數據)"
            "僅恢復包含ssaid應用(不含數據)"
            "恢復自定義資料夾"
            "恢復wifi"
            "壓縮檔完整性檢查"
            "轉換文件夾名稱"
            "殺死運行中腳本"
        )
        commands=(
            "dumpname"        
            "Restore"
            "ssaid_mode=true && Restore"
            "ssaid_mode_1=true && Restore4"
            "Restore3"
            "recover_wifi \"$MODDIR/wifi\""
            "check_file"
            "convert"
            "echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
        )
    fi
	while true; do
		clear
		echoRgb "請選擇要執行的操作："
		for i in "${!steps[@]}"; do
			printf "%d) %s\n" "$((i+1))" "${steps[$i]}"
		done
		echo "x) 離開腳本"
		echo -n "請輸入選項編號: "
		read choice
		case $choice in
		x|X)
			echoRgb "已退出腳本" "0"
			exit 0 ;;
		[0-9]*)
			if (( choice >= 1 && choice <= ${#steps[@]} )); then
				index="$((choice - 1))"
				echo "執行：${steps[$index]}"
				if [[ $index -eq $((${#commands[@]} - 1)) ]]; then
					# 殺死腳本: exit 正常終止進程
					eval "${commands[$index]}"
				else
					if [[ "$background" = "1" ]]; then
						eval "${commands[$index]}" &
					else
						eval "${commands[$index]}"
						# 備份類操作完成後自動觸發遠端上傳
						if [[ -n $remote_type ]]; then
							case "${commands[$index]}" in
							backup|backup_update_apk|backup_media)
								upload_current_backup ;;
							esac
						fi
					fi
				fi
			else
				echoRgb "超出功能選項範圍（1-${#steps[@]}）" "0"
			fi
			;;
		*)
			echoRgb "輸入錯誤，請重新輸入有效的數字或輸入 x 離開。" "0" ;;
		esac
	done
fi
