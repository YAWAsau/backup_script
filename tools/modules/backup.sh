backup_path() {
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		if [[ ${Output_path:0:1} != / ]]; then
		    Directory_type="相對路徑"
		    Backup="$MODDIR/$Output_path/Backup_${Compression_method}_$user"
		else
		    Directory_type="絕對路徑"
		    Backup="$Output_path/Backup_${Compression_method}_$user"
		fi
		outshow="使用自定義目錄($Directory_type)"
	else
	    Backup="$MODDIR/Backup_${Compression_method}_$user"
	    if [[ ! -f ${0%/*}/app_details.json ]]; then
		    outshow="使用當前路徑作為備份目錄"
		else
		    [[ -d $Backup ]] && outshow="使用上層路徑作為備份目錄" || echoRgb "$Backup目錄不存在" "0"
		fi
	fi
	PU="$(mount | awk '$3 ~ "/mnt/media_rw/[^/]+$" {print $3, $5}' | grep -Ev "$mount_point")"
	OTGPATH="$(echo "$PU" | cut -d' ' -f1)"
	OTGFormat="$(echo "$PU" | cut -d' ' -f2)"
	if [[ -d $OTGPATH ]]; then
		if [[ $(echo "$MODDIR" | grep -Eo "^${OTGPATH}") != "" ]]; then
			hx="true"
			Backup="$MODDIR/Backup_${Compression_method}_$user"
		else
		    case $Lo in
		    0|1)
			    echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
			    get_version "選擇了隨身碟備份" "選擇了本地備份" ;;
			2)
			    Enter_options "檢測到隨身碟，輸入1使用隨身碟備份 0本地備份" "選擇了隨身碟備份" "本地備份" && isBoolean "$parameter" "branch" && branch="$nsx" ;;
			esac
			[[ $branch = true ]] && hx="$branch"
			[[ $hx = true ]] && Backup="$OTGPATH/Backup_${Compression_method}_$user"
		fi
		if [[ $hx = true ]]; then
			if [[ $OTGFormat = vfat ]]; then
				echoRgb "隨身碟檔案系統$OTGFormat不支持超過單檔4GB\n -請格式化為exfat" "0"
				exit 
		    fi
		    outshow="於隨身碟備份" && hx=usb
		fi
	fi
	[[ ! -d $Backup ]] && mkdir -p "$Backup"
	#分區詳細
	if [[ $(echo "$Backup" | grep -Eo "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
	remote_setup
}
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(find "$1" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
    if [[ $filesizee -gt $filesize ]]; then
        NJL="本次備份增加 $(size "$(echo "scale=2; $filesizee - $filesize" | bc)")"
    elif [[ $filesizee -lt $filesize ]]; then
        NJL="本次備份減少 $(size "$(echo "scale=2; $filesize - $filesizee" | bc)")"
    else
        NJL="文件大小未改變"
    fi
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(size "$filesizee")"
	echoRgb "$NJL"
}
size() {
    local b_size get_size
    case $1 in
    *[!0-9]*)
        b_size="$(ls -l "$1" 2>/dev/null | awk '{print $5}')" ;;
    *)
        b_size="$1" ;;
    esac
    if [[ $b_size -eq 0 ]]; then
	    get_size="0 bytes"
    elif [[ $(echo "$b_size < 1024" | bc) -eq 1 ]]; then
        get_size="${b_size} bytes"
    elif [[ $(echo "$b_size < 1048576" | bc) -eq 1 ]]; then
        get_size="$(echo "scale=2; $b_size / 1024" | bc) KB"
    elif [[ $(echo "$b_size < 1073741824" | bc) -eq 1 ]]; then
        get_size="$(echo "scale=2; $b_size / 1048576" | bc) MB"
    else
        get_size="$(echo "scale=2; $b_size / 1073741824" | bc) GB"
    fi
    echo "$get_size"
}
#分區佔用信息
partition_info() {
    unset Skip
	Occupation_status="$(df -B1 "${1%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1)}')"
	Filesize2="$(size "$Filesize")"
	echo " -$2大小:$Filesize2 剩餘大小:$(size "$Occupation_status")"
	if [[ -n $Filesize ]]; then
        if awk -v a="$Filesize" -v b="$Occupation_status" 'BEGIN{exit !(a+0 > b+0)}'; then
            echoRgb "$2備份大小將超出rom可用大小" "0"
            Skip=1
        fi
    fi
	Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
Process_Information() {
    dumpsys activity processes | awk -v key="$1" -v user="$user" 'function getUserFromUid(uid){return int(uid/100000)} /^ *user #[0-9]+ uid=/ {if($0 ~ /ISOLATED uid=[0-9]+/){uid="";pid="";pkg="";next} if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)){print pid}} uid="";pid="";pkg=""; if($0 ~ /uid=/ && uid==""){tmp=$0; sub(/^.*uid=/,"",tmp); sub(/ .*/,"",tmp); uid=tmp}} /packageList=\{/ {tmp=$0; sub(/^.*packageList=\{/,"",tmp); sub(/\}.*/,"",tmp); pkg=tmp} /pid=/ {tmp=$0; sub(/^.*pid=/,"",tmp); sub(/ .*/,"",tmp); pid=tmp} END {if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)){print pid}}}'
}
kill_app() {
    process_Information="$(Process_Information "$name2")"
    if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
        if [[ $process_Information != "" ]]; then
            am force-stop --user "$user" "$name2" &>/dev/null
            echo "$process_Information" | xargs -r kill -9
            pkill -9 -f "$name2$|$name2[:/_]"
            #killall -9 "$name2" &>/dev/null
            #am kill "$name2" &>/dev/null
            echoRgb "殺死$name1進程"
        fi
	fi
}
Backup_apk() {
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
	apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
	apk_version2="$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
	if [[ $apk_version = $apk_version2 ]]; then
		[[ $(echo "$txt2" | sed -e '/^$/d' | cut -d' ' -f2 | awk -v pkg="$name2" '$1 == pkg {print $1}') = "" ]] && txt2="$txt2\n${Backup_folder##*/} $name2"
		unset xb
		let osj++
		result=0
		echoRgb "Apk版本無更新 跳過備份" "2"
	else
		if [[ $nobackup = false ]]; then
			if [[ $apk_version != "" ]]; then
				let osn++
				update_apk="$(echo "$name1 \"$name2\"")"
				update_apk2="$(echo "$update_apk\n$update_apk2")"
				echoRgb "版本:$apk_version>$apk_version2"
			else
				let osk++
				add_app="$(echo "$name1 \"$name2\"")"
				add_app2="$(echo "$add_app\n$add_app2")"
				echoRgb "版本:$apk_version2"
			fi
			unset Filesize
			Filesize="$(find "$apk_path2" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
			rm -rf "$Backup_folder/apk.tar"*
			partition_info "$Backup" "$name1 apk"
			if [[ $Skip != 1 ]]; then
    			#備份apk
    			echoRgb "$1"
    			echo "$apk_path" | sed -e '/^$/d' | while read -r; do
    				echoRgb "${REPLY##*/} $(size "$REPLY")"
    			done
    			(
    				cd "$apk_path2"
    				case $Compression_method in
    				tar | TAR | Tar) tar --checkpoint-action="ttyout=%T\r" -cf "$Backup_folder/apk.tar" *.apk ;;
    				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" -cf - *.apk | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/apk.tar.zst" ;;
    				esac
    			)
    			echo_log "備份$apk_number個Apk"
    			if [[ $result = 0 ]]; then
    			    Validation_file "$Backup_folder/apk.tar"*
    				if [[ $result = 0 ]]; then
    				    [[ $(echo "$txt2" | sed -e '/^$/d' | cut -d' ' -f2 | awk -v pkg="$name2" '$1 == pkg {print $1}') = "" ]] && txt2="$txt2\n${Backup_folder##*/} $name2"
                        [[ $apk_version != "" ]] && {
                        echoRgb "覆蓋app_details"
                        jq --arg apk_version "$apk_version2" --arg software "$name1" '.[$software].apk_version = $apk_version' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                        } || {
                        echoRgb "新增app_details"
                        extra_content="{
                          \"$name1\": {
                            \"PackageName\": \"$name2\",
                            \"apk_version\": \"$apk_version2\"
                          }
                        }"
                        jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                        }
    				else
    					rm -rf "$Backup_folder"
    				fi
    				if [[ $name2 = com.android.chrome ]]; then
    					#刪除所有舊apk ,保留一個最新apk進行備份
    					ReservedNum=1
    					FileNum="$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l)"
    					while [[ $FileNum -gt $ReservedNum ]]; do
    						OldFile="$(ls -rt /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)"
    						rm -rf "${OldFile%/*/*}" && echo "刪除文件:${OldFile%/*/*}"
    						let "FileNum--"
    					done
    					[[ -f $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null) && $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l) = 1 ]] && cp -r "$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)" "$Backup_folder/nmsl.apk"
    				fi
    			else
    				rm -rf "$Backup_folder"
    			fi
    	    fi
		else
			let osj++
			rm -rf "$Backup_folder"
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
Backup_ssaid() {
    Ssaid="$(jq -r '.[] | select(.Ssaid != null).Ssaid' "$app_details")"
    ssaid="$(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info")"
    [[ $ssaid != null && $ssaid != "" ]] && echoRgb "SSAID:$ssaid"
    if [[ $ssaid != null && $ssaid != $Ssaid ]]; then
        echoRgb "備份ssaid"
        echoRgb "$Ssaid>$ssaid"
    	SSAID_apk="$(echo "$name1 \"$name2\"")"
        SSAID_apk2="$(echo "$SSAID_apk\n$SSAID_apk2")"
    	jq --arg entry "$name1" --arg new_value "$ssaid" '.[$entry].Ssaid |= $new_value' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    	echo_log "備份ssaid"
    fi
    [[ $ssaid = null ]] && ssaid=
}
Backup_Permissions() {
    get_Permissions="$(jq -r '.[] | select(.permissions != null).permissions' "$app_details")"
    Get_Permissions="$(get_Permissions "$name2" | jq -nR '[inputs | select(. != "null" and length>0) | split(" ") | {(.[0]): (.[1:] | join(" "))}] | if length > 0 then add else empty end')"
    if [[ $Get_Permissions != "" && ($Get_Permissions = *true* || $Get_Permissions = *false*) ]]; then
        if [[ $get_Permissions = "" ]]; then
            echoRgb "備份權限"
            jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName].permissions |= $permissions' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
        	echo_log "備份權限"
        else
            if [[ $get_Permissions != "" && ($get_Permissions = *true* || $get_Permissions = *false*) ]]; then
        	    if [[ $get_Permissions != $Get_Permissions ]]; then
        	        echoRgb "權限變更"
        	        jq -n --argjson old "$get_Permissions" --argjson new "$Get_Permissions" '$new | to_entries | map(select(.key as $k | $old[$k] != null and $old[$k] != .value)) | .[].key' | sed 's/^/ /'
            	    jq --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName] |= . + {permissions: $permissions}' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
            	    echo_log "備份權限"
            	fi
        	fi
        fi
    else
        [[ $Get_Permissions != "" ]] && echoRgb "備份權限失敗$(get_Permissions "$name2")" "0"
    fi
}
#檢測數據位置進行備份
Backup_data() {
	data_path="$path/$1/$name2"
	MODDIR_NAME="${data_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	[[ -f $app_details ]] && Size="$(jq -r --arg entry "$1" '.[$entry] | select(.Size != null).Size' "$app_details" 2>/dev/null)"
	case $1 in
	user) data_path="$path2/$name2" ;;
	user_de) data_path="$path3/$name2" ;;
	data|obb) ;;
	*)
		data_path="$2"
		if [[ $1 != thanox ]]; then
			Compression_method1="$Compression_method"
			Compression_method=tar
		fi
		zsize=1
		zmediapath=1
		;;
	esac
	if [[ -d $data_path ]]; then
	    unset Filesize ssaid Get_Permissions result Permissions
        Filesize="$(find "$data_path" -type f -printf "%s\n" 2>/dev/null | awk '{s+=$1} END {print s}')"
        [[ $Filesize != "" ]] && {
		if [[ $Size != $Filesize ]]; then
            case $1 in
            user)
                if [[ $(su "$(pm list packages -U --user "$user" </dev/null | awk -v pkg="$name2" -F'[ :]' '$2 == pkg {print $4}')" -c keystore_cli_v2 list | wc -l) -ge 2 ]]; then
                    echoRgb "$name1包含keystore 恢復可能閃退" "0"
                    jq --arg entry "$name1" '.[$entry].keystore |= "true"' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                else
                    jq --arg entry "$name1" '.[$entry].keystore |= "false"' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
                fi
    		    Backup_ssaid
    			Backup_Permissions ;;
    	    esac
		    #停止應用
			case $1 in
			user|data|obb|user_de) kill_app ;;
			esac
			rm -rf "$Backup_folder/$1.tar"*
			partition_info "$Backup" "$1"
			if [[ $Skip != 1 ]]; then
    			echoRgb "備份$1數據"
    			# 判斷是否超過指定大小
                if [[ $Filesize2 != *"bytes"* ]]; then
                    if [[ $Filesize2 = *"KB"* ]]; then
                        if [[ $(echo "${Filesize2% KB}" | bc) > 1 ]]; then
                            Start_backup="true"
                        else
                            Start_backup="false"
                        fi
                    else
                        Start_backup="true"
                    fi
                else
                    Start_backup="false"
                fi
                if [[ $Start_backup = true ]]; then
        			case $1 in
        			user|user_de)
        				case $Compression_method in
        				tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null ;;
        				zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" 2>/dev/null ;;
        				esac
        				;;
        			*)
            		    case $Compression_method in
            		    tar | Tar | TAR) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/QQ" --exclude="${data_path##*/}/Telegram" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf "$Backup_folder/$1.tar" -C "${data_path%/*}" "${data_path##*/}" ;;
            			zstd | Zstd | ZSTD) tar --checkpoint-action="ttyout=%T\r" --exclude="Backup_"* --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/QQ" --exclude="${data_path##*/}/Telegram" --exclude="${data_path##*/}"/.* --warning=no-file-changed -cpf - -C "${data_path%/*}" "${data_path##*/}" | zstd --ultra -3 -T0 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
            			esac
        				;;
        			esac
        			echo_log "備份$1數據"
    			else
    			    echoRgb "$1數據 $Filesize2太小" "0" && result=1
    			fi
    			if [[ $result = 0 ]]; then
    			    Validation_file "$Backup_folder/$1.tar"*
    				if [[ $result = 0 ]]; then
    				    if [[ ! $Filesize -eq 0 ]]; then
                            size2="$(stat -c %s "$Backup_folder/$1.tar"*)"
                            rate="$(echo "scale=2; (1 - ($size2 / $Filesize)) * 100" | bc)"
                            echoRgb "壓縮率${rate}% 大小$(size "$size2")"
                        fi
    				    [[ ${Backup_folder##*/} = Media ]] && [[ $(sed -e '/^$/d' "$mediatxt" | grep -w "${REPLY##*/}.tar$" | head -1) = "" ]] && echo "$FILE_NAME" >> "$mediatxt"
    					if [[ $zsize != "" ]]; then
    					    extra_content="{
                              \"$1\": {
                                \"path\": \"$2\",
                                \"Size\": \"$Filesize\"
                              },
                              \"Backup time\": {
                                \"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
                              }
                            }"
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    					else
    					    extra_content="{
                              \"$1\": {
                                \"Size\": \"$Filesize\"
                              },
                              \"Backup time\": {
                                \"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
                              }
                            }"
                            jq --argjson new_content "$extra_content" '. += $new_content' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
    					fi
    				else
    					rm -rf "$Backup_folder/$1".tar.*
    				fi
    			fi
    			[[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1"
    			unset Compression_method1
    		fi
		else
			[[ $Size != "" ]] && echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
		}
	else
		[[ -f $data_path ]] && echoRgb "$1是一個文件 不支持備份" "0"
	fi
}
Release_data() {
	tar_path="$1"
	X="$path2/$name2"
	MODDIR_NAME="${tar_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${tar_path##*/}"
	FILE_NAME2="${FILE_NAME%%.*}"
	case ${FILE_NAME##*.} in
	zst | tar)
		unset FILE_PATH Size Selinux_state
		[[ -f $app_details ]] && Size="$(jq -r --arg entry "$FILE_NAME2" '.[$entry] | select(.Size != null).Size' "$app_details" 2>/dev/null)"
		case $FILE_NAME2 in
		user)
		    if [[ -d $X ]]; then
		        [[ $(jq -r '.[] | select(.Ssaid != null).keystore' "$app_details") = true ]] && echoRgb "$name1存在keystore 恢復可能閃退" "0"
		        FILE_PATH="$path2"
		        Selinux_state="$(LS "$X" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)"
		    else
		        echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
		    fi ;;
		user_de)
		    X="$path3/$name2"
		    if [[ -d $X ]]; then
		        FILE_PATH="$path3"
		        Selinux_state="$(LS "$X" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)"
		    else
		        echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
		    fi ;;
		data) FILE_PATH="$path/data" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)" ;;
		obb) FILE_PATH="$path/obb" Selinux_state="$(LS "$FILE_PATH" | awk 'NF>1{print $1}' | sed -e "s/system_data_file/app_data_file/g" 2>/dev/null)";;
		thanox) FILE_PATH="/data/system" && find "/data/system" -name "thanos"* -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
		*)
			if [[ $A != "" ]]; then
				if [[ ${MODDIR_NAME##*/} = Media ]]; then
				    FILE_PATH="$(jq -r --arg entry "${FILE_NAME2}" 'select(.[$entry].path != null).[$entry].path' "$app_details")"
					if [[ $FILE_PATH = "" ]]; then
						echoRgb "路徑獲取失敗" "0"
					else
						echoRgb "解壓路徑↓\n -$FILE_PATH" "2"
						FILE_PATH="${FILE_PATH%/*}"
						[[ ! -d $FILE_PATH ]] && mkdir -p "$FILE_PATH"
					fi
				fi
		    else
			    echoRgb "$tar_path名稱似乎有誤" "0"
			fi ;;
		esac
        echoRgb "恢復$FILE_NAME2數據 釋放$(size "$Size")" "3"
   		if [[ $FILE_PATH != "" ]]; then
            [[ ${MODDIR_NAME##*/} != Media ]] && rm -rf "$FILE_PATH/$name2"
		    case ${FILE_NAME##*.} in
			zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$tar_path" -C "$FILE_PATH" ;;
			tar) [[ ${MODDIR_NAME##*/} = Media ]] && tar --checkpoint-action="ttyout=%T\r" -axf "$tar_path" -C "$FILE_PATH" || tar --checkpoint-action="ttyout=%T\r" -amxf "$tar_path" -C "$FILE_PATH" ;;
			esac
		else
			Set_back_1
		fi
		echo_log "解壓縮$FILE_NAME"
		if [[ $result = 0 ]]; then
			case $FILE_NAME2 in
			user|data|obb|user_de)
			    G="$(pm list packages -U --user "$user" </dev/null | awk -v pkg="$name2" -F'[ :]' '$2 == pkg {print $4}')"
			    if [[ $G = "" ]]; then
			        G="$(dumpsys package "$name2" 2>/dev/null | awk -F'uid=' '{print $2}' | grep -Eo '[0-9]+' | head -n 1)"
				    [[ $(echo "$G" | grep -Eo '[0-9]+') = "" ]] && G="$(get_uid "$name2" 2>/dev/null)"
				fi
                G="$(echo "$G" | grep -Eo '[0-9]+')"
				if [[ $G != "" ]]; then
					if [[ -d $X ]]; then
					    case ${#G} in
					    5)
					        if [[ $user = 0 ]]; then
					            uid="$G:$G"
					        else
					            uid="$user$G:$user$G"
					        fi ;;
					    6|7|8|9|10)
					        uid="$G:$G" ;;
					    esac
                        case $FILE_NAME2 in
                        user|user_de)
                            case $FILE_NAME2 in
                            user) [[ $X = $path2/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
                            user_de) [[ $X = $path3/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
                            esac
                            if [[ $Validation_settings = true ]]; then
						        chown -hR "$uid" "$X/"
						        echo_log "設置用戶組$uid"
						        chcon -hR "$Selinux_state" "$X/" 2>/dev/null
						        echo_log "selinux上下文設置" "E"
						    else
						        echoRgb "路徑:$X出現錯誤"
						    fi ;;
						data|obb)
                            chown -hR "$uid" "$FILE_PATH/$name2/"
                            echo_log "設置用戶組$uid" "E"
                            chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>/dev/null
                            echo_log "selinux上下文設置" "E" ;;
					    esac
				    else
				        echoRgb "$FILE_NAME2路徑$X不存在" "0"
					fi
				else
                    echoRgb "uid獲取失敗" "0"
				fi
				;;
			thanox)
				restorecon -RF "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>/dev/null)/" 2>/dev/null
				echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
				;;
			esac
		fi
		;;
	*)
		echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
		Set_back_1
		;;
	esac
	rm -rf "$TMPDIR"/*
}
installapk() {
	apkfile="$(find "$Backup_folder" -maxdepth 1 -name "apk.*" -type f 2>/dev/null)"
	if [[ $apkfile != "" ]]; then
		rm -rf "$TMPDIR"/*
		case ${apkfile##*.} in
		zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$apkfile" -C "$TMPDIR" ;;
		tar) tar --checkpoint-action="ttyout=%T\r" -xmpf "$apkfile" -C "$TMPDIR" ;;
		*)
			echoRgb "${apkfile##*/} 壓縮包不支持解壓縮" "0"
			Set_back_1
			;;
		esac
		echo_log "${apkfile##*/}解壓縮" && [[ -f $Backup_folder/nmsl.apk ]] && cp -r "$Backup_folder/nmsl.apk" "$TMPDIR"
	else
		echoRgb "你的Apk壓縮包離家出走了，可能備份後移動過程遺失了\n -解決辦法手動安裝Apk後再執行恢復腳本" "0"
	fi
	if [[ $result = 0 ]]; then
		case $(find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f 2>/dev/null | wc -l) in
		1)
			echoRgb "恢復普通apk" "2"
			INSTALL "$TMPDIR"/*.apk
			echo_log "Apk安裝"
			;;
		0)
			echoRgb "$TMPDIR中沒有apk" "0"
			;;
		*)
			echoRgb "恢復split apk" "2"
			b="$(create | grep -Eo '[0-9]+')"
			if [[ -f $TMPDIR/nmsl.apk ]]; then
				INSTALL "$TMPDIR/nmsl.apk"
				echo_log "nmsl.apk安裝"
			fi
			find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f | grep -v 'nmsl.apk' | while read -r apk; do
                pm install-write "$b" "${apk##*/}" "$apk" </dev/null >/dev/null
                echo_log "${apk##*/}安裝"
            done
			pm install-commit "$b" >/dev/null
			echo_log "split Apk安裝"
			;;
		esac
	fi
}
disable_verify() {
	#禁用apk驗證
	settings put global verifier_verify_adb_installs 0 2>/dev/null
	#禁用安裝包驗證
	settings put global package_verifier_enable 0 2>/dev/null
	#未知來源
	settings put secure install_non_market_apps 1 2>/dev/null
	#關閉play安全校驗
	if [[ $(settings get global package_verifier_user_consent 2>/dev/null) != -1 ]]; then
		settings put global package_verifier_user_consent -1 2>/dev/null
		settings put global upload_apk_enable 0 2>/dev/null
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
	# 額外安全性攔截
    settings put global harmful_app_warning_on 0 2>/dev/null
    # 關閉應用的受限模式 (針對 Android 13/14 側載應用)
    settings put secure enhanced_confirmation_states 0 2>/dev/null
	# 設定檔案路徑
    FILE="/data/data/com.android.vending/shared_prefs/finsky.xml"
    if [[ -f $FILE ]]; then
        # 提取當前的 auto_update_enabled 值
        CURRENT_VALUE="$(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE")"
        if [[ $CURRENT_VALUE = true ]]; then
            sed -i '/<boolean name="auto_update_enabled" /s/value="true"/value="false"/' "$FILE"
            [[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "play自動更新已關閉" "3"
            echoRgb "殺死 Google Play 商店..."
            am force-stop com.android.vending
        else
            if [[ $CURRENT_VALUE = "" ]]; then
                sed -i '/<\/map>/i \    <boolean name="auto_update_enabled" value="false" />' "$FILE"
                [[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "auto_update_enabled已插入false,play自動更新已關閉" "3"
                echoRgb "殺死 Google Play 商店..."
                am force-stop com.android.vending
            else
                [[ $CURRENT_VALUE != false ]] && echoRgb "無法識別play auto_update_enabled當前$CURRENT_VALUE值" "0"
            fi
        fi
    fi
}
get_name(){
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	txt2="$MODDIR/mediaList.txt"
	if [[ $1 = Apkname ]]; then
		rm -rf "$txt" "$txt2"
		echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	fi
	rgb_a=118
	user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	starttime1="$(date -u "+%s")"
	i=1
	while read -r; do
		Folder="${REPLY%/*}"
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		unset PackageName NAME DUMPAPK ChineseName apk_version Ssaid dataSize userSize obbSize
		if [[ -f $Folder/app_details.json ]]; then
		    ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "$Folder/app_details.json" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$Folder/app_details.json")"
		    if [[ -f $Folder/Permissions ]]; then
		        unset Permissions
		        . "$Folder/Permissions"
		        jq --arg packageName "$ChineseName" --argjson permissions "$(echo "$Permissions" | jq -nR '[inputs | select(length>0) | split(" ") | {(.[0]): .[-1]}] | add')" '.[$packageName] |= . + {permissions: $permissions}' "$Folder/app_details.json" > "$TMPDIR/temp.json" && cp "$TMPDIR/temp.json" "$Folder/app_details.json" && rm "$Folder/Permissions" "$TMPDIR/temp.json" && echoRgb "更新$Folder/app_details.json"
		    fi
		else
		    if [[ -f $Folder/app_details ]]; then
		        . "$Folder/app_details" &>/dev/null
		        extra_content="{
                  \"$ChineseName\": {
                    \"PackageName\": \"$PackageName\",
                    \"apk_version\": \"$apk_version\",
                    \"Ssaid\": \"$Ssaid\"
                  },
                  \"data\": {
                    \"Size\": \"$dataSize\"
                  },
                  \"obb\": {
                    \"Size\": \"$obbSize\"
                  },
                  \"user\": {
                    \"Size\": \"$userSize\"
                  }
                }"
                echo "{\n}">"$Folder/app_details.json"
                jq --argjson new_content "$extra_content" '. += $new_content' "$Folder/app_details.json" > "$TMPDIR/temp.json" && cp "$TMPDIR/temp.json" "$Folder/app_details.json" && rm "$TMPDIR/temp.json" "$Folder/app_details"
            fi
		fi
		if [[ $PackageName = "" || $ChineseName = "" ]]; then
			echoRgb "${Folder##*/}包名獲取失敗，解壓縮獲取包名中..." "0"
			rm -rf "$TMPDIR"/*
			case ${REPLY##*.} in
			zst) tar -I zstd -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' ;;
			tar) tar -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' ;;
			*)
			    echoRgb "${REPLY##*/} 壓縮包不支持解壓縮" "0"
				Set_back_1
				;;
			esac
			echo_log "${REPLY##*/}解壓縮"
			if [[ $result = 0 ]]; then
				if [[ -f $TMPDIR/base.apk ]]; then
					DUMPAPK="$(appinfo3 "$TMPDIR/base.apk")"
					if [[ $DUMPAPK != "" ]]; then
						app=($DUMPAPK $DUMPAPK)
						PackageName="${app[1]}"
						ChineseName="${app[2]}"
						rm -rf "$TMPDIR"/*
					else
						echoRgb "appinfo輸出失敗" "0"
					fi
				fi
			fi
		fi
		if [[ $PackageName != "" && $ChineseName != "" ]]; then
		    if [[ $(echo "$Apk_info" | awk -v pkg="$PackageName" '$1 == pkg {print $1}') = "" ]]; then
		        echoRgb "$ChineseName已經不存在$user使用者中"
		        if [[ $delete_app = "" ]]; then
            		delete_app="$ChineseName $PackageName"
                else
                    delete_app="$delete_app\n$ChineseName $PackageName"
                fi      
    		fi
			case $1 in
			Apkname)
			    [[ -f $Folder/${PackageName}.sh ]] && rm -rf "$Folder/${PackageName}.sh"
		        [[ ! -f $Folder/recover.sh ]] && touch_shell "3" "$Folder/recover.sh"
			    [[ ! -f $Folder/backup.sh ]] && touch_shell "1" "$Folder/backup.sh"
				echoRgb "$i:$ChineseName $PackageName"
				if [[ $TMPTXT = "" ]]; then
        	        TMPTXT="#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market\n$ChineseName $PackageName"
        	    else
        	        TMPTXT="$TMPTXT\n$ChineseName $PackageName"
        	    fi
				let i++ ;;
			convert)
				if [[ ${Folder##*/} = $PackageName ]]; then
				    DIR_NAME="${Folder%/*}/$ChineseName"
				    echoRgb "${Folder##*/} > $ChineseName"
				else
				    DIR_NAME="${Folder%/*}/$PackageName"
				    echoRgb "${Folder##*/} > $PackageName"
				fi
                if [[ -d $DIR_NAME ]]; then
                    i=1
                    NEW_DIR_NAME="${DIR_NAME}_${i}"
                    while [[ -d $NEW_DIR_NAME ]]; do
                        i=$((i + 1))
                        NEW_DIR_NAME="${DIR_NAME}_${i}"
                    done
                    DIR_NAME="$NEW_DIR_NAME"
                fi
                mv "$Folder" "$DIR_NAME" ;;
			esac
		fi
		let rgb_a++
	done<<<"$(find "$MODDIR" -maxdepth 2 -name "apk.*" -type f 2>/dev/null | sort)"
	[[ $TMPTXT != "" ]] && echo "$TMPTXT">"$txt"
	if [[ -d $MODDIR/Media ]]; then
		echoRgb "存在媒體資料夾" "2"
		[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$txt2"
		find "$MODDIR/Media" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | while read -r; do
			echoRgb "${REPLY##*/}" && echo "${REPLY##*/}" >> "$txt2"
		done
		echoRgb "$txt2重新生成" "1"
	fi
	if [[ $delete_app != "" ]]; then
	    if [[ $(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
	        echoRgb "列出需要刪除的應用中....\n -$delete_app"
	        case $Lo in
	        0|1)
	            echoRgb "確認列表無誤後音量上刪除，音量下退出腳本編輯列表" "2"
		        get_version "刪除" "退出腳本" && Delete_App="$branch" ;;
		    2)
		        Enter_options "確認列表無誤後輸入1刪除，輸入0退出腳本編輯列表" "刪除" "退出腳本" && isBoolean "$parameter" "Delete_App" && Delete_App="$nsx" ;;
		    esac
		    if [[ $Delete_App = true ]]; then
		        echoRgb "警告 即將刪除未安裝應用資料夾，請再三確認後在執行" "0"
		        i=1
		        r="$(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }')"
		        while [[ $i -le $r ]]; do
		            name1="$(echo "$delete_app" | sed -e '/^$/d' | sed -n "${i}p" | cut -d' ' -f1)"
    		        name2="$(echo "$delete_app" | sed -e '/^$/d' | sed -n "${i}p" | cut -d' ' -f2)"
    		        Backup_folder="$MODDIR/$name1"
    		        [[ -d $Backup_folder ]] && rm -rf "$Backup_folder"
    		        echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$txt" 2>/dev/null)" >"$txt"
    		        let i++
    		    done
    		else
    		    exit 0
    	    fi
    	fi
    fi
    chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
    endtime 1
	exit 0
}
self_test() {
	if [[ $(dumpsys deviceidle get charging) = false && $(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+') -le 15 ]]; then
		echoRgb "電量$(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+')%太低且未充電\n -為防止備份檔案或是恢復因低電量強制關機導致檔案損毀\n -請連接充電器後備份" "0" && exit 2
	fi
}
Validation_file() {
	MODDIR_NAME="${1%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${1##*/}"
	echoRgb "校驗$FILE_NAME"
	case ${FILE_NAME##*.} in
	zst) zstd -t "$1" 2>/dev/null ;;
	tar) tar -tf "$1" &>/dev/null ;;
	esac
	echo_log "${FILE_NAME##*.}校驗"
}
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>/dev/null | sort)"
	i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | wc -l)"
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort | while read -r; do
		REPLY="${REPLY%/*}"
		echoRgb "校驗第$i/$r個資料夾 剩下$((r - i))個" "3"
		echoRgb "校驗:${REPLY##*/}"
		find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | sort | while read -r; do
			Validation_file "$REPLY"
			[[ $result != 0 ]] && echo "$REPLY">>"$error_log"
		done
		echoRgb "$((i * 100 / r))%"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n $(cat "$error_log")" || echoRgb "恭喜~~全數校驗通過" 
	rm -rf "$error_log"
}
Set_screen_pause_seconds () {
    if [[ $1 = on ]]; then
        #獲取系統設置的無操作息屏秒數
        if [[ $Get_dark_screen_seconds = "" ]]; then
	        Get_dark_screen_seconds="$(settings get system screen_off_timeout)"
	        #設置30分鐘後息屏
            settings put system screen_off_timeout 1800000
            echo_log "設置無操作息屏時間30分鐘"
        fi
        [[ $setDisplayPowerMode = true ]] && {
        setDisplay 0
        echo_log "設置螢幕狀態false"
        }
    elif [[ $1 = off ]]; then
        if [[ $Get_dark_screen_seconds != "" ]]; then
            settings put system screen_off_timeout "$Get_dark_screen_seconds"
            echo_log "設置無操作息屏時間為$Get_dark_screen_seconds"
            input keyevent 224
        fi
        [[ $setDisplayPowerMode = true ]] && {
        setDisplay 2
        echo_log "設置螢幕狀態true"
        }
    fi
}
restore_permissions () {
    echoRgb "恢復權限"
    appops reset --user "$user" "$name2" &>/dev/null
    true_permissions="$(jq -r 'to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("true")) | .key) | join(" ")' "$app_details")"
    false_permissions="$(jq -r 'to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("false")) | .key) | join(" ")' "$app_details")"
	Set_Ops_permissions="$(jq -r '.[] | select(.permissions != null).permissions | to_entries | map(.value | split(" ")) | map(select(.[1] != "-1")) | map(.[1:]) | flatten | join(" ")' "$app_details")"
	[[ $true_permissions != "" ]] && {
	Set_true_Permissions "$name2" "$true_permissions"
	[[ $? != 0 ]] && echo_log "設置允許權限"
	}
    [[ $false_permissions != "" ]] && {
    Set_false_Permissions "$name2" "$false_permissions"
    [[ $? != 0 ]] && echo_log "設置拒絕權限"
    }
    [[ $Set_Ops_permissions != "" ]] && {
    Set_Ops "$name2" "$Set_Ops_permissions"
    [[ $? != 0 ]] && echo_log "設置ops權限"
    }
}
Background_application_list() {
    [[ $activity != false ]] && {
    if [[ $Background_apps_ignore = true || $1 = debug ]]; then
        unset Backstage
	    #獲取後台
	    Backstage="$(dumpsys activity activities | awk -v uid="$user" '/ActivityRecord\{/{split($4,a,"/"); user=$3; pkg=a[1]; if(user~/^u[0-9]+$/ && pkg!~/\//){sub(/^u/,"",user); if(uid=="" || user==uid) if(!seen[user","pkg]++) print pkg}}')"
	    if [[ $Backstage = "" ]]; then
            Backstage="$(am stack list | awk -v uid="$user" '/taskId/&&!/unknown/{split($2,a,"/"); pkg=a[1]; user="unknown"; for(i=1;i<=NF;i++) if($i~/^userId=/){split($i,b,"="); user=b[2]; break} if(uid==""||user==uid) if(!seen[pkg]++) print pkg}')"
            [[ $Backstage = "" ]] && {
            echoRgb "獲取當前後台應用失敗" "0" && unset Backstage
            }
        fi
    fi
    }
}
Background_application_list debug
pkgs="$(pm list packages --user "$user" | cut -f2 -d ':' | awk -v pkg="$(echo "$Backstage" | head -1)" '$1 == pkg {print $1}')"
if [[ $pkgs != "" ]]; then
    echoRgb "後台應用獲取成功($pkgs)" "1"
    [[ $(Process_Information "$pkgs") = "" ]] && echoRgb "應用pid獲取失敗" "0" || echoRgb "應用pid獲取成功$(Process_Information "$pkgs")" "1"
else
    echoRgb "後台應用獲取失敗" "0" activity=false
fi
unset Backstage
backup() {
	self_test
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	case $Lo in
	0)
		[[ $Backup_Mode != "" ]] && isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx" || {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		}
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
		        if [[ $blacklist_mode != "" ]]; then
		            isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		        else
        		    echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔\n -警告! " "2"
        		    get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
        		fi
            fi
        fi
		if [[ $Backup_Mode = true ]]; then
		    [[ $Backup_obb_data != "" ]] && isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx" || {
		    echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
		    get_version "備份" "不備份" && Backup_obb_data="$branch"
    		}
    		[[ $Backup_user_data != "" ]] && isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx" || {
    		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_user_data="$branch"
    		}
        else
            Backup_user_data="false"
            Backup_obb_data="false"
        fi
		[[ $backup_media != "" ]] && isBoolean "$backup_media" "backup_media" && backup_media="$nsx" || {
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
		}
		[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
		echoRgb "應用備份開始後關閉螢幕\n -音量上關閉，音量下不關閉" "2"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		}
		[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略備份\n -音量上忽略，音量下備份" "2"
		get_version "忽略" "備份" && Background_apps_ignore="$branch"
		} ;;
	1)
		[[ $Backup_Mode = "" ]] && {
		echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
		get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
		} || isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx"
		if [[ $Backup_Mode = true ]]; then
		    if [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]]; then
    		    [[ $blacklist_mode = "" ]] && {
    		    echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔" "2"
    		    get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
		        } || isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
    		fi
    		[[ $Backup_obb_data = "" ]] && {
    		echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_obb_data="$branch"
    		} || isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
    		[[ $Backup_user_data = "" ]] && {
    		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
    		get_version "備份" "不備份" && Backup_user_data="$branch"
    		} || isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
        fi
		[[ $backup_media = "" ]] && {
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
		} || isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
		[[ $setDisplayPowerMode = "" ]] && {
		echoRgb "應用備份開始後關閉螢幕\n -音量上關閉，音量下不關閉" "2"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		} || isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
		[[ $Background_apps_ignore = "" ]] && {
		echoRgb "存在進程忽略備份\n -音量上忽略，音量下備份" "2"
		get_version "忽略" "備份" && Background_apps_ignore="$branch"
		} || isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
		;;
	2)
        [[ $Backup_Mode = "" ]] && {
        Enter_options "輸入1備份應用+數據，輸入0僅應用不包含數據" "應用+數據" "僅應用" && isBoolean "$parameter" "Backup_Mode" && Backup_Mode="$nsx"
        } || {
        isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx"
        }
		if [[ $Backup_Mode = true ]]; then
		    [[ $(echo "$blacklist" | grep -Ev '#|＃' | wc -l) -gt 0 ]] && {
		    [[ $blacklist_mode = "" ]] && {
		    Enter_options "選擇黑名單模式輸入1不備份，輸入0備份安裝檔" "不備份" "僅應用安裝檔" && isBoolean "$parameter" "blacklist_mode" && blacklist_mode="$nsx"
		    } || {
		    isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
		    }
		    }
    		[[ $Backup_obb_data = "" ]] && {
    		Enter_options "是否備份外部數據 即比如原神的數據包\n -輸入1備份，輸入0不備份" "備份" "不備份" && isBoolean "$parameter" "Backup_obb_data" && Backup_obb_data="$nsx"
    		} || {
    		isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
    		}
    		[[ $Backup_user_data = "" ]] && {
    		Enter_options "是否備份使用者數據，輸入1備份，輸入0不備份" "備份" "不備份" && isBoolean "$parameter" "Backup_user_data" && Backup_user_data="$nsx"
    		} || {
    		isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
    		}
        fi
        [[ $backup_media = "" ]] && {
        Enter_options "全部應用備份結束後是否備份自定義目錄\n -輸入1備份，0不備份" "備份" "不備份" && isBoolean "$parameter" "backup_media" && backup_media="$nsx"
        } || {
        isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
        }
        [[ $setDisplayPowerMode = "" ]] && {
        Enter_options "應用備份開始後關閉螢幕\n -輸入1關閉，0不關閉" "關閉" "不關閉" && isBoolean "$parameter" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
        } || {
        isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx"
        }
        [[ $Background_apps_ignore = "" ]] && {
        Enter_options "存在進程忽略備份\n -輸入1不備份，0備份" "忽略" "備份" && isBoolean "$parameter" "Background_apps_ignore" && Background_apps_ignore="$nsx"
        } || {
        isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx"
        } ;;
    *)  echoRgb "$conf_path Lo=$Lo填寫錯誤，正確值0 1 2" "0" && exit 2 ;;
    esac
	i=1
	#數據目錄
	if [[ $list_location != "" ]]; then
	    if [[ ${list_location:0:1} = / ]]; then
	        txt="$list_location"
	    else
	        txt="$MODDIR/$list_location"
	    fi
	else
	    txt="$MODDIR/appList.txt"
	fi
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	txt_path="$txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來備份" "0" && exit 1
	TXT_NAME="${txt##*/}"
	case ${TXT_NAME##*.} in
	txt) ;;
	*) echoRgb "$txt不是腳本讀取格式" "0" && exit 2 ;;
	esac
	sort -u "$txt" -o "$txt" &>/dev/null
	data="$MODDIR"
	hx="本地"
	echoRgb "腳本受到內核機制影響 息屏後IO性能嚴重影響\n -請勿關閉終端或是息屏備份 如需終止腳本\n -請執行start.sh選擇終止腳本即可停止" "3"
	backup_path
	echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -音量鍵確認:$Lo\n -更新:$update\n -備份模式:$Backup_Mode\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -自定義目錄備份:$backup_media\n -存在進程忽略備份:$Background_apps_ignore\n -關閉螢幕:$setDisplayPowerMode"
	D="1"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
	    [[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
	    Apk_info="$(appinfo "user|system" "pkgName" 2>/dev/null | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	[[ ! -f ${0%/*}/app_details.json ]] && {
	echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
	while read -r ; do
	    if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
            app=($REPLY $REPLY)
    		if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
	            if [[ $(echo "$Apk_info" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') != "" ]]; then
			        [[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
    			    Tmplist="$Tmplist\n$REPLY"
    			else
                    echoRgb "$REPLY不存在系統，從列表中刪除" "0"
                fi
			fi
		else
		    Tmplist="$Tmplist\n$REPLY"
		fi
	done < "$txt"
	}
    [[ $Update_backup = true ]] && {
    echoRgb "檢查備份列表中已經更新應用" "3"
    while read -r apk; do
        Backup_folder="$Backup/$(echo "$apk" | cut -d':' -f1)"
        app_details="$Backup_folder/app_details.json"
        if [[ -d $Backup_folder ]]; then
            apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
            apk_version2="$(pm list packages --show-versioncode --user "$user" "$(echo "$apk" | cut -d':' -f2)" </dev/null | cut -f3 -d ':' | head -n 1)"
            [[ $apk_version != $apk_version2 ]] && {
            [[ $Tmplist2 = "" ]] && Tmplist2="${apk/:/ }" || Tmplist2="$Tmplist2\n${apk/:/ }"
            }
        fi
    done<<<"$(grep -Ev '^[#＃!]' "$txt" | awk '{print $1 ":" $2}')"
    }
    [[ $Tmplist != ""  ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
	if [[ $Tmplist2 != "" ]]; then
        txt="$(echo "$Tmplist2" | sort)"
    else
        [[ $Update_backup != "" ]] && echoRgb "應用目前無更新" "0" && exit 0
    fi
    if [[ ! -f $txt ]]; then
        [[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
    else
        txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
    fi
    r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
	[[ -f ${0%/*}/app_details.json ]] && r=1
	[[ $r = "" && ! -f ${0%/*}/app_details.json ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/start.sh" "0" && exit 1
	if [[ $Backup_Mode = true ]]; then
    	[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
    	[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
    fi
	[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
	txt2="$Backup/appList.txt"
	txt_path2="$txt2"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
	txt2="$(cat "$txt2")"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	if [[ -d $Backup/tools ]]; then
	    find "$Backup/tools" -maxdepth 1 -type f | while read -r; do
	        Tools_FILE_NAME="${REPLY##*/}"
	        if [[ -f $tools_path/$Tools_FILE_NAME ]]; then
	            filesha256="$(sha256sum "$tools_path/$Tools_FILE_NAME" 2>/dev/null | cut -d" " -f1)"
    	        filesha256_1="$(sha256sum "$REPLY" 2>/dev/null | cut -d" " -f1)"
    	        if [[ $filesha256 != $filesha256_1 ]]; then
    	            cp -r "$tools_path/$Tools_FILE_NAME" "$REPLY"
    	            echoRgb "更新$REPLY"
    	        fi
    	    fi
	    done
	fi
	filesize="$(find "$Backup" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')"
	Quantity=0
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	en=118
	osn=0; osj=0; osk=0
	#獲取已經開啟的無障礙
	var="$(settings get secure enabled_accessibility_services 2>/dev/null)"
	#獲取預設鍵盤
	keyboard="$(settings get secure default_input_method 2>/dev/null)"
    Set_screen_pause_seconds on
    [[ $txt != "" ]] && [[ $(echo "$txt" | cut -d' ' -f2 | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
	if [[ -f ${0%/*}/app_details.json ]]; then
	    ssaid_info="$(get_ssaid "$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")")"
	else
	    ssaid_info="$(get_ssaid "$(echo "$txt" | awk '{printf "%s ", $2}')")"
	fi
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	notification "101" "開始備份"
	# 保存本次備份實際使用的清單,供遠端上傳用 (純變數,不寫檔)
	# 此時 $txt 是過濾過註解後的字串內容
	[[ -n $remote_type && -n $txt ]] && REMOTE_APPLIST="$txt"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ ! -f ${0%/*}/app_details.json ]]; then
		    name1="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f1)"
        	name2="$(echo "$txt" | sed -n "${i}p" | cut -d' ' -f2)"
        else
            ChineseName="$(jq -r 'to_entries[] | select(.key != null).key' "${0%/*}/app_details.json" | head -n 1)"
		    PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")"
            name1="$ChineseName"
            name2="$PackageName"
        fi
		[[ $name2 = "" || $name1 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
		apk_path="$(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':')"
		apk_path2="$(echo "$apk_path" | head -1)"
		apk_path2="${apk_path2%/*}"
		if [[ -d $apk_path2 ]]; then
			echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
			echoRgb "備份 $name1" "2"
			notification "101" "備份第$i/$r個應用 剩下$((r - i))個
備份 $name1"
			unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version apk_version2  zsize zmediapath Size data_path Ssaid ssaid Permissions
			nobackup="false"
			Background_application_list
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略備份" "0" && nobackup="true"
			if [[ $Backup_Mode = true ]]; then
			    if [[ $name1 = !* || $name1 = ！* ]]; then
    				name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
    				echoRgb "跳過備份所有數據" "0"
    				No_backupdata=1
    			fi
    			if [[ $(echo "$blacklist" | grep -w "^$name2$") = $name2 ]]; then
    			    if [[ $blacklist_mode = true ]]; then
    			        echoRgb "黑名單應用跳過備份" "0"
    			        nobackup="true"
    			    else
    				    echoRgb "黑名單應用跳過備份所有數據" "0"
    				fi
    				No_backupdata=1
    			fi
    	    fi
			Backup_folder="$Backup/$name1"
			app_details="$Backup_folder/app_details.json"
			if [[ -f $app_details ]]; then
				PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details")"
				[[ $PackageName != $name2 ]] && jq --arg name2 "$name2" 'walk(if type == "object" and .PackageName then .PackageName = $name2 else . end)' "$app_details" > "$TMPDIR/temp.json" && cat "$TMPDIR/temp.json" > "$app_details" && rm "$TMPDIR/temp.json"
				echoRgb "上次備份時間$(jq -r --arg entry "Backup time" '.[$entry] | select(.date != null).date' "$app_details" 2>/dev/null)"
			fi
			[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
			starttime2="$(date -u "+%s")"
			[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			apk_number="$(echo "$apk_path" | wc -l)"
			if [[ $nobackup != true ]]; then
    			if [[ $apk_number = 1 ]]; then
    				Backup_apk "非Split Apk" "3"
    			else
    				Backup_apk "Split Apk支持備份" "3"
    			fi
    			if [[ $result = 0 && $No_backupdata = "" ]]; then
    				if [[ $Backup_Mode = true ]]; then
        				if [[ $Backup_obb_data = true ]]; then
        				    if [[ $name2 != bin.mt.plus ]]; then
        					    #備份data數據
        					    [[ $name1 = Nekogram ]] && rm -rf /data/media/0/Android/data/tw.nekomimi.nekogram/files/Telegram/Telegram\ {Video,Stories,Documents,Images}/{*,.*} 2>/dev/null
        					    Backup_data "data"
        					    #備份obb數據
        					    Backup_data "obb"
        					else
        					    echoRgb "$name1無法備份" "0"
        					fi
        				fi
        				#備份user數據
        				[[ $name2 != bin.mt.plus ]] && {
        				    [[ $Backup_user_data = true ]] && {
        				    Backup_data "user"
        				    Backup_data "user_de"
        				    }
        				}
        				[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>/dev/null)"
        		    fi
    			fi
    			[[ -f $Backup_folder/${name2}.sh ]] && rm -rf "$Backup_folder/${name2}.sh"
    		    [[ ! -f $Backup_folder/recover.sh ]] && touch_shell "3" "$Backup_folder/recover.sh"
    			[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "1" "$Backup_folder/backup.sh"
    		fi
			endtime 2 "$name1 備份" "3"
			lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
			echoRgb "完成$((i * 100 / r))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "3"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
		else
			echoRgb "$name1[$name2] 不在安裝列表，備份個寂寞？" "0"
		fi
		if [[ $i = $r ]]; then
			endtime 1 "應用備份" "3"
			#設置無障礙開關
			if [[ $var != "" ]]; then
				if [[ $var != null ]]; then
					settings put secure enabled_accessibility_services "$var" &>/dev/null 
					echo_log "設置無障礙"
					settings put secure accessibility_enabled 1 &>/dev/null
					echo_log "打開無障礙開關"
				fi
			fi
			#設置鍵盤
			if [[ $keyboard != "" ]]; then
				ime enable "$keyboard" &>/dev/null
				ime set "$keyboard" &>/dev/null
				settings put secure default_input_method "$keyboard" &>/dev/null
				echo_log "設置鍵盤$(appinfo2 "${keyboard%/*}" 2>/dev/null)"
			fi
			update_apk2="${update_apk2:="暫無更新"}"
			add_app2="${add_app2:="暫無更新"}"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2\n -包含SSAID的應用\n$SSAID_apk2" "3"
			notification "101" "app備份完成 $(endtime 1 "應用備份" "3")"
			[[ $txt2 != "" ]] && {
			echo "$txt2" | sort | sed '/^$/d'>"$txt_path2"
			}
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(echo "$Custom_path" | grep -Ev '#|＃' | awk 'NF != 0 { count++ } END { print count }')"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					notification "102" "Media備份開始"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
					[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
					app_details="$Backup_folder/app_details.json"
					[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
					mediatxt="$Backup/mediaList.txt"
					[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
					echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' | while read -r; do
						echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
						notification "102" "備份第$A/$B個資料夾 剩下$((B - A))個"
						starttime2="$(date -u "+%s")"
						if [[ ${REPLY##*/} = adb ]]; then
						    if [[ $ksu != ksu ]]; then
			                    echoRgb "Magisk adb"
				                Backup_data "${REPLY##*/}" "$REPLY"
				            else
				                echoRgb "KernelSU adb不支持備份" "0"
 	                            Set_back_0
				            fi
						else
						    Backup_data "${REPLY##*/}" "$REPLY"
						fi
						endtime 2 "${REPLY##*/}備份" "1"
						echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2"
						rgb_d="$rgb_a"
						rgb_a=188
						echoRgb "_________________$(endtime 1 "已經")___________________"
						rgb_a="$rgb_d" && let A++
					done
					echoRgb "目錄↓↓↓\n -$Backup_folder"
					[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
					notification "102" "Media備份完成 $(endtime 1 "自定義備份")"
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		let i++ en++ nskg++
	done
	backup_wifi "$Backup/wifi"
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user"
	Calculate_size "$Backup"
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	notification "105" "備份完成 $(endtime 1 "批量備份開始到結束")"
	[[ -f $txt_path ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path"
	[[ -f $txt_path2 ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path2"
	exit
}
backup_update_apk() {
    Update_backup='true'
    backup
}
dumpname() {
	get_name "Apkname"
}
convert() {
	get_name "convert"
}
check_file() {
	Check_archive "$MODDIR"
}
