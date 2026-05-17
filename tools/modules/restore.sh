Restore() {
	self_test
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	if [[ ! -f ${0%/*}/app_details.json ]]; then
    	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/start.sh選擇終止腳本\n -否則腳本將繼續執行直到結束" "0"
    	echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/start.sh選擇轉換資料夾名稱"
    	txt="$MODDIR/appList.txt"
    	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來恢復" "0" && exit 2
	    sort -u "$txt" -o "$txt" 2>/dev/null
	    i=1
	    r="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	    [[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
    	Backup_folder2="$MODDIR/Media"
    	#校驗選填是否正確
    	case $Lo in
    	0)
        	[[ $recovery_mode != "" ]] && isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx" || {
        	echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
        	get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
        	}
        	[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
        	echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
        	get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
        	}
        	Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
        	if [[ $Get_user != $user ]]; then
        	    echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
        		get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
        	fi
        	if [[ -d $Backup_folder2 ]]; then
        	    [[ $media_recovery != "" ]] && isBoolean "$media_recovery" "media_recovery" && media_recovery="$nsx" || {
        		echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
        		get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
        		}
        	fi
        	[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
    		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
    		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
    		} ;;
		1)
    		echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
    	    get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
    	    echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
        	get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
    	    if [[ $Get_user != $user ]]; then
    	        echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
    		    get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
    	    fi
    	    echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
    	    get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
    	    echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		    get_version "忽略" "恢復" && Background_apps_ignore="$branch" ;;
		2)
		    [[ $recovery_mode = "" ]] && {
		    Enter_options "選擇應用恢復模式\n -輸入1僅恢復未安裝，0全恢復" "僅恢復未安裝" "全恢復" && isBoolean "$parameter" "recovery_mode" && recovery_mode="$nsx"
		    } || {
		    isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx"
		    }
		    [[ $setDisplayPowerMode = "" ]] && {
		    Enter_options "應用恢復時關閉螢幕\n -輸入1關閉，0不關閉" "關閉" "不關閉" && isBoolean "$parameter" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		    } || {
		    isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		    }
    	    Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
    	    [[ $Get_user != $user ]] && {
    	    [[ $recovery_mode2 = "" ]] && {
    	    Enter_options "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，輸入1繼續恢復，0不恢復並離開腳本" "恢復安裝" "離開腳本" && isBoolean "$parameter" "recovery_mode2" && recovery_mode2="$nsx"
    	    } || {
    	    isBoolean "$recovery_mode2" "recovery_mode2" && recovery_mode2="$nsx"
    	    }
    	    }
    	    [[ $media_recovery = "" ]] && {
    	    Enter_options "是否恢復多媒體\n -輸入1僅恢復，0不恢復" "恢復" "不恢復" && isBoolean "$parameter" "media_recovery" && media_recovery="$nsx"
    	    } || {
    	    isBoolean "$media_recovery" "media_recovery" && media_recovery="$nsx"
    	    }
    	    [[ $Background_apps_ignore = "" ]] && {
    	    Enter_options "存在進程忽略恢復\n -輸入1不恢復，0恢復" "忽略" "恢復" && isBoolean "$parameter" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } || {
    	    isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
    	    } ;;
		*)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
		esac
    	[[ $recovery_mode2 = false ]] && exit 2
    	if [[ $recovery_mode = true && $ssaid_mode != true ]]; then
    		echoRgb "獲取未安裝應用中"
    		Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	if [[ $Apk_info != "" ]]; then
        	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	else
        	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
        	fi
        	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
    		while read -r ; do
                if [[ $(echo "$REPLY" | sed 's/^[ \t]*//') != \#* ]]; then
                    app=($REPLY $REPLY)
            		if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
        	            [[ $(echo "$Apk_info" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') = "" ]] && Tmplist="$Tmplist\n$REPLY"
                    fi
        		fi
        	done < "$txt"
    		if [[ $(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
    			echoRgb "獲取完成 預計安裝$(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }')個應用"
    			txt="$Tmplist"
    			case $Lo in
    			0|1)
    			    echoRgb "未安裝應用列表\n$txt\n確認無誤使用音量上繼續恢復，音量下退出腳本" "1"
    			    get_version "恢復安裝" "退出腳本" ;;
    			2)
    			    Enter_options "未安裝應用列表\n$txt\n-輸入1退出腳本，0恢復" "退出腳本" "恢復安裝" isBoolean "$parameter" "branch" && branch="$nsx" ;;
    			esac
    			[[ $branch = false ]] && exit
    		else
    			echoRgb "獲取完成 但備份內應用都已安裝....正在退出腳本" "0" && exit 0
    		fi
    	fi
    	if [[ $ssaid_mode = true ]]; then
    	     while read -r; do
    	        if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
            	    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$REPLY" | head -n 1)"
        		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$REPLY")"
        		    if [[ $ssaid_name = "" ]]; then
        		        ssaid_name="$ChineseName $PackageName"
        		    else
        		        ssaid_name="$ssaid_name\n$ChineseName $PackageName"
        		    fi
        		fi
            done<<<"$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort)"
            [[ $ssaid_name != "" ]] && txt="$ssaid_name"
        fi
        if [[ ! -f $txt ]]; then
	        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
	    else
	        txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
	    fi
	    r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
    	DX="批量恢復"
    else
        i=1
        r=1
        Backup_folder="$MODDIR"
	    app_details="$Backup_folder/app_details.json"
	    if [[ ! -f $app_details ]]; then
		    echoRgb "$app_details遺失，無法獲取包名" "0" && exit 1
	    else
		    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$app_details" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details")"
		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
	    fi
	    name1="$ChineseName"
	    name1="${name1:="${Backup_folder##*/}"}"
	    [[ $name1 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
	    name2="$PackageName"
	    [[ $name2 = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
	    DX="單獨恢復"
	    [[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
		}
    fi
	#開始循環$txt內的資料進行恢復
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	Set_screen_pause_seconds on
	en=118
	notification "105" "開始恢復app"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ ! -f ${0%/*}/app_details.json ]]; then
		    echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
		    notification "105" "恢復第$i/$r個應用 剩下$((r - i))個
恢復 $name1"
	        name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
	        name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
		    unset No_backupdata apk_version Permissions
		    if [[ $name1 = *! || $name1 = *！ ]]; then
			    name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    			echoRgb "跳過恢復$name1 所有數據" "0"
    			No_backupdata=1
    		fi
    		Backup_folder="$MODDIR/$name1"
    		if [[ -f "$Backup_folder/app_details.json" ]]; then
    		    app_details="$Backup_folder/app_details.json"
    		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
    		else
    		    echoRgb "$Backup_folder/app_details.json不存在" "0"
    		fi
    		[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
		fi
		if [[ -d $Backup_folder ]]; then
			echoRgb "恢復$name1" "2"
			Background_application_list
			restore="true"
		    [[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略恢復" "0" && restore="false"
			[[ $restore = true ]] && {
			starttime2="$(date -u "+%s")"
			if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') = "" ]]; then
				installapk
			else
		        [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]] && installapk && [[ $? = 0 ]] && echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
			fi
			if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') != "" ]]; then
				if [[ $No_backupdata = "" ]]; then
				    [[ $name2 != *mt* ]] && {
					kill_app
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read -r; do
						Release_data "$REPLY"
					done
					unset G
					restore_permissions
					Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
					if [[ $Ssaid != "" ]]; then
					    SSAID_Package="$(echo "$name1 $name2 $Ssaid")"
				        SSAID_Package2="$(echo "$SSAID_Package\n$SSAID_Package2")"
					    unset Ssaid
					fi
					}
				fi
			else
				[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
			fi
			endtime 2 "$name1恢復" "2" && echoRgb "完成$((i * 100 / r))%" "3"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
			}
		else
			echoRgb "$Backup_folder資料夾遺失，無法恢復" "0"
		fi
		if [[ $i = $r ]]; then
		    endtime 1 "應用恢復" "2"
		    [[ $SSAID_Package2 != "" ]] && {
		    echoRgb "開始恢復saaid" "0"
		    set_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s %s ", $2, $3}')"
		    ssaid_info="$(get_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s ", $2}')")"
		    echo "$SSAID_Package2" | while read -r; do
		        Ssaid="$(echo "$REPLY" | cut -d' ' -f3)"
		        name1="$(echo "$REPLY" | cut -d' ' -f1)"
		        name2="$(echo "$REPLY" | cut -d' ' -f2)"
		        if [[ $(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info") = $Ssaid ]]; then
		            echoRgb "$name1 SSAID恢復成功" "1"
		        else
		            echoRgb "$name1 SSAID恢復失敗" "0"
		        fi
			    unset Ssaid
			done
			echoRgb "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟" "0"
			notification "107" "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟"
			}
			notification "105" "app恢復完成 $(endtime 1 "應用恢復" "2")"
			[[ ! -f ${0%/*}/app_details.json ]] && {
			if [[ $media_recovery = true ]]; then
			    starttime1="$(date -u "+%s")"
			    app_details="$Backup_folder2/app_details.json"
			    txt="$MODDIR/mediaList.txt"
			    sort -u "$txt" -o "$txt" 2>/dev/null
			    A=1
	            B="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
                [[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
                notification "106" "Media恢復開始"
				while [[ $A -le $B ]]; do
		            name1="$(grep -Ev '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		            starttime2="$(date -u "+%s")"
		            echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		            Release_data "$Backup_folder2/$name1"
		            endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
                done
				endtime 1 "自定義恢復" "2"
				notification "106" "Media恢復完成 $(endtime 1 "Media恢復" "2")"
			fi
			recover_wifi "$MODDIR/wifi"
			}
		fi
		let i++ en++ nskg++
	done
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user"
	starttime1="$TIME"
	echoRgb "$DX完成" && endtime 1 "$DX開始到結束"
	notification "109" "恢復完成 $(endtime 1 "$DX開始到結束")"
	rm -rf "$TMPDIR"/*
}
Restore3() {
	self_test
	case $Lo in
	0|1)
	    echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -音量上繼續恢復自定義資料夾，音量下離開腳本" "2"
	    echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	    get_version "恢復自定義資料夾" "離開腳本" && [[ $branch = false ]] && exit 0 ;;
	2)
	    Enter_options "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -輸入1繼續恢復自定義資料夾，輸入0離開腳本" "恢復" "退出腳本" && isBoolean "$parameter" "branch" && branch="$nsx" && [[ $branch = false ]] && exit 0 ;;
	esac
	mediaDir="$MODDIR/Media"
	[[ -f "$mediaDir/app_details.json" ]] && app_details="$mediaDir/app_details.json"
	Backup_folder2="$mediaDir"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取媒體列表再來恢復" "0" && exit 2
	sort -u "$txt" -o "$txt" 2>/dev/null
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	echo_log() {
		if [[ $? = 0 ]]; then
			echoRgb "$1成功" "1" && result=0
		else
			echoRgb "$1恢復失敗，過世了" "0" && result=1
		fi
	}
	starttime1="$(date -u "+%s")"
	A=1
	B="$(grep -Ev '#|＃' "$txt" 2>/dev/null | awk 'NF != 0 { count++ } END { print count }')"
	Set_screen_pause_seconds on
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && exit 1
	notification "108" "Media恢復開始"
	while [[ $A -le $B ]]; do
		name1="$(grep -Ev '#|＃' "$txt" 2>/dev/null | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	notification "108" "Media恢復完成 $(endtime 1 "Media恢復")"
}
Restore4() {
    if [[ $ssaid_mode_1 = true ]]; then
        while read -r; do
            if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
                ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$REPLY" | head -n 1)"
        	    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$REPLY")"
        	    if [[ $ssaid_name = "" ]]; then
        	        ssaid_name="$ChineseName $PackageName"
        	    else
        	        ssaid_name="$ssaid_name\n$ChineseName $PackageName"
        	    fi
        	fi
        done<<<"$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort)"
        [[ $ssaid_name != "" ]] && txt="$ssaid_name"
        i=1
        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
        r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
        while [[ $i -le $r ]]; do
            name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
    	    name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
    	    Backup_folder="$MODDIR/$name1"
    		if [[ -f "$Backup_folder/app_details.json" ]]; then
    		    app_details="$Backup_folder/app_details.json"
    		    apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
    		else
    		    echoRgb "$Backup_folder/app_details.json不存在" "0"
    		fi
        	[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
            if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') != "" ]]; then
    		    [[ $name2 != *mt* ]] && {
    			kill_app
    			Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
    			if [[ $Ssaid != "" ]]; then
    			    SSAID_Package="$(echo "$name1 $name2 $Ssaid")"
    		        SSAID_Package2="$(echo "$SSAID_Package\n$SSAID_Package2")"
    			    unset Ssaid
    			fi
    			}
    		fi
    		if [[ $i = $r ]]; then
                [[ $SSAID_Package2 != "" ]] && {
        	    echoRgb "開始恢復saaid" "0"
        	    set_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s %s ", $2, $3}')"
        	    ssaid_info="$(get_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s ", $2}')")"
        	    echo "$SSAID_Package2" | while read -r; do
        	        Ssaid="$(echo "$REPLY" | cut -d' ' -f3)"
        	        name1="$(echo "$REPLY" | cut -d' ' -f1)"
        	        name2="$(echo "$REPLY" | cut -d' ' -f2)"
        	        if [[ $(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info") = $Ssaid ]]; then
        	            echoRgb "$name1 SSAID恢復成功" "1"
        	        else
        	            echoRgb "$name1 SSAID恢復失敗" "0"
        	        fi
        		    unset Ssaid
        		done
        		echoRgb "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟" "0"
        		notification "107" "SSAID恢復後必須重新開機套用,否則應用閃退,如果沒有應用恢復ssaid則無須重啟"
        		}
            fi
    		let i++
	    done
	fi
}
