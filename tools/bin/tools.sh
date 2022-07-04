#!/system/bin/sh
MODDIR="$MODDIR"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
if [[ ! -d $tools_path ]]; then
	tools_path="${MODDIR%/*}/tools"
	[[ ! -d $tools_path ]] && echo "$tools_path二進制目錄遺失" && EXIT="true"
fi
bin_path="$tools_path/bin"
script_path="$tools_path/script"
[[ ! -d $tools_path/apk ]] && echo "$tools_path/apk目錄遺失" && EXIT="true"
if [[ ! -d $bin_path ]]; then
	bin_path="${MODDIR%/*}/tools/bin"
	[[ ! -d $bin_path ]] && echo "$bin_path關鍵目錄遺失" && EXIT="true"
fi
[[ ! -f $bin_path/bin.sh ]] && echo "$bin_path/bin.sh關鍵腳本遺失" && EXIT="true"
[[ $conf_path != "" ]] && conf_path="$conf_path" || conf_path="$MODDIR/backup_settings.conf"
[[ ! -f $conf_path ]] && echo "$conf_path配置遺失" && EXIT="true"
[[ $EXIT = true ]] && exit 1
. "$conf_path"
. "$bin_path/bin.sh"
[[ $user = "" ]] && user=0
path="/data/media/$user/Android"
path2="/data/user/$user"
zipFile="$(ls -t /storage/emulated/0/Download/*.zip 2>/dev/null | head -1)"
[[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | egrep -wo "^backup_settings.conf$") != "" ]] && update_script
if [[ $(getprop ro.build.version.sdk) -lt 30 ]]; then
	alias INSTALL="pm install --user $user -r -t"
	alias create="pm install-create --user $user -t"
else
	alias INSTALL="pm install -i com.android.vending --user $user -r -t"
	alias create="pm install-create -i com.android.vending --user $user -t"
fi
case $operate in
backup|Restore|Restore2|Getlist)
	user_id="$(ls -1 "/data/user" 2>/dev/null)"
	if [[ $user_id != "" ]]; then
		echo "$user_id" | while read ; do
			[[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
		done
	fi
	[[ ! -d $path2 ]] && echoRgb "$user分區不存在，請將上方提示的用戶id按照需求填入\n -$MODDIR_NAME/backup_settings.conf配置項user=,一次只能填寫一個" "0" && exit 2
	echoRgb "當前操作為用戶$user"
	if [[ $operate != Getlist && $operate != Restore2 ]]; then
		isBoolean "$Lo" "Lo" && Lo="$nsx"
		if [[ $Lo = false ]]; then
			isBoolean "$toast_info" "toast_info" && toast_info="$nsx"
		else
			echoRgb "備份完成或是遭遇異常發送toast與狀態欄通知？\n -音量上提示，音量下靜默備份" "2"
			get_version "提示" "靜默備份" && toast_info="$branch"
		fi
		if [[ $toast_info = true ]]; then
			pm enable "ice.message" &>/dev/null
			if [[ $(pm path --user "$user" ice.message 2>/dev/null) = "" ]]; then
				echoRgb "未安裝toast 開始安裝" "0"
				cp -r "${bin_path%/*}/apk"/*.apk "$TMPDIR" && INSTALL "$TMPDIR"/*.apk &>/dev/null && rm -rf "$TMPDIR"/*
				[[ $? = 0 ]] && echoRgb "安裝toast成功" "1" || echoRgb "安裝toast失敗" "0"
			fi
		else
			pm disable "ice.message" &>/dev/null
		fi
	fi
	;;
esac
cdn=2
#settings get system system_locales
LANG="$(getprop "persist.sys.locale")"
echoRgb "檢查更新中 請稍後......."
Language="https://api.github.com/repos/Petit-Abba/backup_script_zh-CN/releases/latest"
if [[ $LANG != "" ]]; then
	case $LANG in
	*-TW | *-tw)
		echoRgb "系統語系:繁體中文"
		Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
		;;
	*-CN | *-cn)
		echoRgb "系統語系:簡體中文"
		;;
	*)
		echoRgb "$LANG不支持 默認簡體中文" "0"
		;;
	esac
else
	echoRgb "獲取系統語系失敗 默認簡體中文" "0"
fi
dns="8.8.8.8"
[[ $(getprop ro.build.version.sdk) -lt 23 ]] && alias curl="curl -kL --dns-servers $dns$flag" || alias curl="curl -L --dns-servers $dns$flag"
#效驗選填是否正確
Lo="$(echo "$Lo" | sed 's/true/1/g ; s/false/0/g')"
isBoolean "$Lo" "Lo" && Lo="$nsx"
if [[ $Lo = false ]]; then
	isBoolean "$update" "update" && update="$nsx"
	isBoolean "$update_behavior" "update_behavior" && update_behavior="$nsx"
else
	echoRgb "自動更新腳本?\n -音量上更新，下不更新"
	get_version "更新" "不更新" && update="$branch"
fi
if [[ $update = true ]]; then
	json="$(curl "$Language" 2>/dev/null)"
	if [[ $json != "" ]]; then
		echoRgb "使用curl"
	else
		json="$(down -s -L "$Language" 2>/dev/null)"
		[[ $json != "" ]] && echoRgb "使用down"
	fi
	[[ $json = "" ]] && echoRgb "更新獲取失敗" "0"
else
	echoRgb "自動更新被關閉" "0"
fi
if [[ $json != "" ]]; then
	tag="$(echo "$json" | sed -r -n 's/.*"tag_name": *"(.*)".*/\1/p')"
	#echo "$json" | grep body|cut -f4 -d "\""
	if [[ $tag != "" && $backup_version != $tag ]]; then
		if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$tag" | tr -d "a-zA-Z")") -eq 0 ]]; then
			download="$(echo "$json" | sed -r -n 's/.*"browser_download_url": *"(.*.zip)".*/\1/p')"
			case $cdn in
			1)
				zip_url="http://huge.cf/download/?huge-url=$download"
				NJ="huge.cf"
				;;
			2)
				zip_url="https://ghproxy.com/$download"
				NJ="ghproxy.com"
				;;
			3)
				zip_url="https://gh.api.99988866.xyz/$download"
				NJ="gh.api.99988866.xyz"
				;;
			4)
				zip_url="https://github.lx164.workers.dev/$download"
				NJ="github.lx164.workers.dev"
				;;
			5)
				zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download"
				NJ="shrill-pond-3e81.hunsh.workers.dev"
				;;
			esac
			if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$download" | tr -d "a-zA-Z")") -eq 0 ]]; then
				echoRgb "發現新版本:$tag"
				if [[ $update = true ]]; then
					echo "$json" | sed 's/\"body\": \"/body=\"/g'>"$TMPDIR/updateinfo" && . "$TMPDIR/updateinfo" &>/dev/null ; [[ $body != "" ]] && echoRgb "更新日誌:\n$body" && rm -rf "$TMPDIR/updateinfo"
					echoRgb "是否更新腳本？\n -音量上更新，音量下不更新" "2"
					get_version "更新" "不更新" && choose="$branch"
					if [[ $choose = true ]]; then
						if [[ $Lo = true ]]; then
							echoRgb "更新方式\n -音量上跳轉瀏覽器，下複製"
							get_version "跳轉" "複製" && update_behavior="$branch"
						fi
						if [[ $update_behavior = true ]]; then
							am start -a android.intent.action.VIEW -d "$zip_url" 2>/dev/null
							echo_log "跳轉瀏覽器"
							if [[ $result = 0 ]]; then
								echoRgb "等待下載中.....請儘速點擊下載 否則腳本將等待10秒後自動退出"
								zipFile="$(ls -t /storage/emulated/0/Download/*.zip 2>/dev/null | head -1)"
								seconds=1
								while [[ $(unzip -l "$zipFile" 2>/dev/null | awk '{print $4}' | egrep -wo "^backup_settings.conf$") = "" ]]; do
									zipFile="$(ls -t /storage/emulated/0/Download/*.zip 2>/dev/null | head -1)"
									echoRgb "$seconds秒"
									[[ $seconds = 10 ]] && exit 2
									sleep 1 && let seconds++
								done
								update_script
							fi
						else
							echoRgb "更新腳本步驟如下\n -1.將剪貼簿內的連結用瀏覽器下載\n -2.將zip壓縮包完整不解壓縮放在$MODDIR\n -3.在$MODDIR目錄隨便執行一個腳本\n -4.假設沒有提示錯誤重新進入腳本如版本號發生變化則更新成功" "2"
							starttime1="$(date -u "+%s")"
							xtext "$zip_url" 
							echo_log "複製連結到剪裁版"
							endtime 1
						fi
						exit 0
					fi
				else
					echoRgb "$MODDIR_NAME/backup_settings.conf內update選項為0忽略更新僅提示更新" "0"
				fi
			fi
		fi
	fi
fi
Lo="$(echo "$Lo" | sed 's/true/1/g ; s/false/0/g')"
backup_path() {
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		Backup="$Output_path/Backup_${Compression_method}_$user"
		outshow="使用自定義目錄"
	else
		Backup="$MODDIR/Backup_${Compression_method}_$user"
		outshow="使用當前路徑作為備份目錄"
	fi
	PU="$(ls /dev/block/vold 2>/dev/null | grep -w 'public')"
	if [[ $PU != "" ]]; then
		[[ -f /proc/mounts ]] && PT="$(cat /proc/mounts | grep -w "$PU" | awk '{print $2}')"
		if [[ -d $PT ]]; then
			if [[ $(echo "$MODDIR" | egrep -o "^${PT}") != "" || $USBdefault = true ]]; then
				hx="true"
			else
				echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
				get_version "選擇了隨身碟備份" "選擇了本地備份"
				[[ $branch = true ]] && hx="$branch"
			fi
			if [[ $hx = true ]]; then
				Backup="$PT/Backup_${Compression_method}_$user"
				data="/dev/block/vold/$PU"
				mountinfo="$(df -T "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')"
				case $mountinfo in
				fuseblk | exfat | NTFS | ext4 | f2fs)
					outshow="於隨身碟備份" && hx=usb
					;;
				*)
					echoRgb "隨身碟檔案系統$mountinfo不支持超過單檔4GB\n -請格式化為exfat" "0"
					exit 1
					;;
				esac
			fi
		fi
	else
		echoRgb "沒有檢測到隨身碟於本地備份" "0"
	fi
	#分區詳細
	if [[ $(echo "$Backup" | egrep -o "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | sed 's/G//g' | awk 'END{print "總共:"$1"G已用:"$2"G剩餘:"$3"G使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
}
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(du -ks "$1" | awk '{print $1}')"
	dsize="$(($((filesizee - filesize)) / 1024))"
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(du -ksh "$1" | awk '{print $1}')"
	if [[ $dsize -gt 0 ]]; then
		if [[ $((dsize / 1024)) -gt 0 ]]; then
			echoRgb "本次備份: $((dsize / 1024))gb"
		else
			echoRgb "本次備份: ${dsize}mb"
		fi
	else
		echoRgb "本次備份: $(($((filesizee - filesize)) * 1000 / 1024))kb"
	fi
}
#分區佔用信息
partition_info() {
	stopscript
	Occupation_status="$(df -h "${1%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
	lxj="$(echo "$Occupation_status" | awk '{print $2}' | sed 's/%//g')"
	[[ $lxj -ge 97 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
}
Backup_apk() {
	#檢測apk狀態進行備份
	stopscript
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	apk_version2="$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)"
	apk_version3="$(dumpsys package "$name2" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1)"
	if [[ $apk_version = $apk_version2 ]]; then
		[[ $(cat "$txt2" | grep -v "#" | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
		unset xb
		let osj++
		result=0
		echoRgb "Apk版本無更新 跳過備份" "2"
	else
		case $name2 in
		com.google.android.youtube)
			[[ -d /data/adb/Vanced ]] && nobackup="true"
			;;
		com.google.android.apps.youtube.music)
			[[ -d /data/adb/Music ]] && nobackup="true"
			;;
		esac
		if [[ $nobackup != true ]]; then
			let osn++
			if [[ $apk_version != "" ]]; then
				echoRgb "版本:$apk_version>$apk_version2"
			else
				echoRgb "版本:$apk_version2"
			fi
			partition_info "$Backup"
			#備份apk
			echoRgb "$1"
			[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
			echo "$apk_path" | sed -e '/^$/d' | while read; do
				path="$REPLY"
				b_size="$(ls -l "$path" | awk '{print $5}')"
				k_size="$(awk 'BEGIN{printf "%.2f\n", "'$b_size'"/'1024'}')"
				m_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')"
				echoRgb "${path##*/} ${m_size}MB(${k_size}KB)"
			done
			(
				cd "$apk_path2"
				case $Compression_method in
				tar | TAR | Tar) tar -cf - *.apk | pv > "$Backup_folder/apk.tar" ;;
				lz4 | LZ4 | Lz4) tar -cf - *.apk | pv | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/apk.tar.lz4" ;;
				zstd | Zstd | ZSTD) tar -cf - *.apk | pv | zstd -r -T0 --ultra -1 -q --priority=rt >"$Backup_folder/apk.tar.zst" ;;
				esac
			)
			echo_log "備份$apk_number個Apk"
			if [[ $result = 0 ]]; then
				case $Compression_method in
				tar | Tar | TAR) Validation_file "$Backup_folder/apk.tar" ;;
				zstd | Zstd | ZSTD) Validation_file "$Backup_folder/apk.tar.zst" ;;
				lz4 | Lz4 | LZ4) Validation_file "$Backup_folder/apk.tar.lz4" ;;
				esac
				if [[ $result = 0 ]]; then
					[[ $(cat "$txt2" | grep -v "#" | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$txt2"
					if [[ $apk_version = "" ]]; then
						echo "apk_version=\"$apk_version2\"" >>"$app_details"
					else
						echo "$(cat "$app_details" | sed "s/${apk_version}/${apk_version2}/g")">"$app_details"
					fi
					if [[ $versionName = "" ]]; then
						echo "versionName=\"$apk_version3\"" >>"$app_details"
					else
						echo "$(cat "$app_details" | sed "s/${versionName}/${apk_version3}/g")">"$app_details"
					fi
					[[ $PackageName = "" ]] && echo "PackageName=\"$name2\"" >>"$app_details"
					[[ $ChineseName = "" ]] && echo "ChineseName=\"$name1\"" >>"$app_details"
					[[ ! -f $Backup_folder/$name2.sh ]] && cp -r "$script_path/restore2" "$Backup_folder/$name2.sh"
				else
					rm -rf "$Backup_folder"
				fi
				if [[ $name2 = com.android.chrome ]]; then
					#刪除所有舊apk ,保留一個最新apk進行備份
					ReservedNum=1
					FileNum="$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l)"
					while [[ $FileNum -gt $ReservedNum ]]; do
						OldFile="$(ls -rt /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)"
						rm -rf "${OldFile%/*/*}" && echoRgb "刪除文件:${OldFile%/*/*}"
						let "FileNum--"
					done
					[[ -f $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null) && $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l) = 1 ]] && cp -r "$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)" "$Backup_folder/nmsl.apk"
				fi
			else
				rm -rf "$Backup_folder"
			fi
		else
			let osj++
			echoRgb "$name1不支持備份 需要使用vanced安裝" "0" && rm -rf "$Backup_folder"
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
#檢測數據位置進行備份
Backup_data() {
	unset zsize Size data_path && data_path="$path/$1/$name2"
	stopscript
	case $1 in
	user) Size="$userSize" && data_path="$path2/$name2" ;;
	data) Size="$dataSize" ;;
	obb) Size="$obbSize" ;;
	*)
		[[ -f $app_details ]] && Size="$(cat "$app_details" | awk "/$1Size/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')"
		data_path="$2"
		if [[ $1 != storage-isolation && $1 != thanox ]]; then
			Compression_method1="$Compression_method"
			Compression_method=tar
		fi
		zsize=1
		;;
	esac
	if [[ -d $data_path ]]; then
		if [[ $Size != $(du -ks "$data_path" | awk '{print $1}') ]]; then
			partition_info "$Backup"
			[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
			echoRgb "備份$1數據"
			case $1 in
			user)
				let osx++
				case $Compression_method in
				tar | Tar | TAR) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd | Zstd | ZSTD) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
				lz4 | Lz4 | LZ4) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" --exclude="${data_path##*/}/code_cache" --exclude="${data_path##*/}/no_backup" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/$1.tar.lz4" ;;
				esac
				;;
			*)
				case $1 in
				data) let osb++ ;;
				obb) let osg++ ;;
				esac
				case $Compression_method in
				tar | Tar | TAR) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd | Zstd | ZSTD) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
				lz4 | Lz4 | LZ4) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/$1.tar.lz4" ;;
				esac
				;;
			esac
			echo_log "備份$1數據"
			if [[ $result = 0 ]]; then
				case $Compression_method in
				tar | Tar | TAR) Validation_file "$Backup_folder/$1.tar" ;;
				zstd | Zstd | ZSTD) Validation_file "$Backup_folder/$1.tar.zst" ;;
				lz4 | Lz4 | LZ4) Validation_file "$Backup_folder/$1.tar.lz4" ;;
				esac
				if [[ $result = 0 ]]; then
					if [[ $zsize != "" ]]; then
						[[ $2 != $(cat "$app_details" | awk "/$1path/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g') ]] && echo "#$1path=\"$2\"" >>"$app_details"
						if [[ $Size != "" ]]; then
							echo "$(cat "$app_details" | sed "s/$Size/$(du -ks "$data_path" | awk '{print $1}')/g")">"$app_details"
						else
							echo "#$1Size=\"$(du -ks "$data_path" | awk '{print $1}')\"" >>"$app_details"
						fi
					else
						if [[ $Size != "" ]]; then
							echo "$(cat "$app_details" | sed "s/$Size/$(du -ks "$data_path" | awk '{print $1}')/g")">"$app_details"
						else
							echo "$1Size=\"$(du -ks "$data_path" | awk '{print $1}')\"" >>"$app_details"
						fi
					fi
				fi
			fi
			[[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1"
			unset Compression_method1
		else
			echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
	else
		if [[ -f $data_path ]]; then
			echoRgb "$1是一個文件 不支持備份" "0"
		else
			case $1 in
			user) let osz++ ;;
			data) let osd++ ;;
			obb) let ose++ ;;
			esac
			echoRgb "$1數據不存在跳過備份" "2"
		fi
	fi
	partition_info "$Backup"
}
Release_data() {
	stopscript
	tar_path="$1"
	X="$path2/$name2"
	MODDIR_NAME="${tar_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${tar_path##*/}"
	FILE_NAME2="${FILE_NAME%%.*}"
	echoRgb "恢復$FILE_NAME2數據" "3"
	unset FILE_PATH
	case $FILE_NAME2 in
	user) [[ -d $X ]] && FILE_PATH="$path2" || echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0" ;;
	data) FILE_PATH="$path/data" ;;
	obb) FILE_PATH="$path/obb" ;;
	thanox)	FILE_PATH="/data/system" && find "/data/system" -name "thanos*" -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
	storage-isolation)	FILE_PATH="/data/adb" ;;
	*)
		if [[ $A != "" ]]; then
			app_details="$Backup_folder2/app_details"
			if [[ -f $app_details ]]; then
				FILE_PATH="$(cat "$app_details" | awk "/${FILE_NAME2}path/"'{print $1}' | cut -f2 -d '=' | sed 's/\"//g')"
				[[ $FILE_PATH = "" ]] && echoRgb "解壓路徑獲取失敗" "0" || echoRgb "解壓路徑↓\n -$FILE_PATH" "2"
				FILE_PATH="${FILE_PATH%/*}"
			fi
		fi
	esac
	if [[ $FILE_PATH != "" ]]; then
		case ${FILE_NAME##*.} in
		lz4 | zst) pv "$tar_path" | tar --recursive-unlink -I zstd -xmpf - -C "$FILE_PATH" ;;
		tar) [[ ${MODDIR_NAME##*/} = Media ]] && pv "$tar_path" | tar --recursive-unlink -xpf - -C "$FILE_PATH" || pv "$tar_path" | tar --recursive-unlink -xmpf - -C "$FILE_PATH" ;;
		*)
			echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
			Set_back
			;;
		esac
	else
		Set_back
	fi
	echo_log "$FILE_NAME 解壓縮($FILE_NAME2)"
	if [[ $result = 0 ]]; then
		case $FILE_NAME2 in
		user)
			if [[ -d $X ]]; then
				if [[ -f /config/sdcardfs/$name2/appid ]]; then
					G="$(cat "/config/sdcardfs/$name2/appid")"
				else
					G="$(dumpsys package "$name2" | grep -w 'userId' | head -1)"
				fi
				G="$(echo "$G" | egrep -o '[0-9]+')"
				if [[ $G != "" ]]; then
					echoRgb "路徑:$X"
					Path_details="$(stat -c "%A/%a %U/%G" "$X")"
					[[ $user = 0 ]] && chown -hR "$G:$G" "$X/" || chown -hR "$user$G:$user$G" "$X/"
					echo_log "設置用戶組:$(echo "$Path_details" | awk '{print $2}')"
					restorecon -RFD "$X/" 2>/dev/null
					echo_log "selinux上下文設置"
				else
					echoRgb "uid獲取失敗" "0"
				fi
			else
				echoRgb "路徑$X不存在" "0"
			fi
			;;
		data | obb)
			[[ -d $path/$FILE_NAME2/$name2 ]] && chmod -R 0777 "$path/$FILE_NAME2/$name2"
			;;
		thanox)
			restorecon -RF "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d 2>/dev/null)/" 2>/dev/null
			echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
			;;
		storage-isolation)
			restorecon -RF "/data/adb/storage-isolation/" 2>/dev/null
			echo_log "selinux上下文設置"
			;;
		esac
	fi
}
installapk() {
	stopscript
	apkfile="$(find "$Backup_folder" -maxdepth 1 -name "apk.*" -type f 2>/dev/null)"
	if [[ $apkfile != "" ]]; then
		rm -rf "$TMPDIR"/*
		case ${apkfile##*.} in
		lz4 | zst) pv "$apkfile" | tar -I zstd -xmpf - -C "$TMPDIR" ;;
		tar) pv "$apkfile" | tar -xmpf - -C "$TMPDIR" ;;
		*)
			echoRgb "${apkfile##*/} 壓縮包不支持解壓縮" "0"
			Set_back
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
			INSTALL "$TMPDIR"/*.apk &>/dev/null
			echo_log "Apk安裝"
			;;
		0)
			echoRgb "$TMPDIR中沒有apk" "0"
			;;
		*)
			echoRgb "恢復split apk" "2"
			b="$(create 2>/dev/null | egrep -o '[0-9]+')"
			if [[ -f $TMPDIR/nmsl.apk ]]; then
				INSTALL "$TMPDIR/nmsl.apk" &>/dev/null
				echo_log "nmsl.apk安裝"
			fi
			find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f 2>/dev/null | grep -v 'nmsl.apk' | while read; do
				pm install-write "$b" "${REPLY##*/}" "$REPLY" &>/dev/null
				echo_log "${REPLY##*/}安裝"
			done
			pm install-commit "$b" &>/dev/null
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
	#關閉play安全效驗
	if [[ $(settings get global package_verifier_user_consent 2>/dev/null) != -1 ]]; then
		settings put global package_verifier_user_consent -1 2>/dev/null
		settings put global upload_apk_enable 0 2>/dev/null
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
}
get_name(){
	txt="$MODDIR/appList.txt"
	txt2="$MODDIR/mediaList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	[[ $1 = Apkname ]] && rm -rf *.txt && echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	rgb_a=118
	find "$MODDIR" -maxdepth 1 -type d 2>/dev/null | sort | while read; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		if [[ -f $REPLY/app_details ]]; then
			if [[ ${REPLY##*/} = Media && $1 = Apkname ]]; then
				echoRgb "存在媒體資料夾" "2"
				[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$txt2"
				find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | while read; do
					echoRgb "${REPLY##*/}" && echo "${REPLY##*/}" >> "$txt2"
				done
				echoRgb "$txt2重新生成" "1"
			else
				unset PackageName NAME DUMPAPK ChineseName
				. "$REPLY/app_details" &>/dev/null
				[[ ! -f $txt && $1 = Apkname ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$txt"
				if [[ $PackageName = "" || $ChineseName = "" ]]; then
					if [[ ${REPLY##*/} != Media ]]; then
						echoRgb "${REPLY##*/}包名獲取失敗，解壓縮獲取包名中..." "0"
						compressed_file="$(find "$REPLY" -maxdepth 1 -name "apk.*" -type f 2>/dev/null)"
						if [[ $compressed_file != "" ]]; then
							rm -rf "$TMPDIR"/*
							case ${compressed_file##*.} in
							lz4 | zst) pv "$compressed_file" | tar -I zstd -xmpf - -C "$TMPDIR"  --wildcards --no-anchored 'base.apk' ;;
							tar) pv "$compressed_file" | tar -xmpf - -C "$TMPDIR"  --wildcards --no-anchored 'base.apk' ;;
							*)
								echoRgb "${compressed_file##*/} 壓縮包不支持解壓縮" "0"
								Set_back
								;;
							esac
							echo_log "${compressed_file##*/}解壓縮"
							if [[ $result = 0 ]]; then
								if [[ -f $TMPDIR/base.apk ]]; then
									DUMPAPK="$(appinfo -sort-i -d " " -o ands,pn -f "$TMPDIR/base.apk")"
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
					fi
				fi
				if [[ $PackageName != "" && $ChineseName != "" ]]; then
					case $1 in
					Apkname)
						echoRgb "$ChineseName $PackageName" && echo "$ChineseName $PackageName" >>"$txt" ;; 
					convert)
						if [[ ${REPLY##*/} = $PackageName ]]; then
							mv "$REPLY" "${REPLY%/*}/$ChineseName" && echoRgb "${REPLY##*/} > $ChineseName"
						else
							mv "$REPLY" "${REPLY%/*}/$PackageName" && echoRgb "${REPLY##*/} > $PackageName"
						fi ;;
					esac
				fi
			fi
		fi
		let rgb_a++
	done
	[[ $1 = Apkname ]] && sort -u "$txt" -o "$txt" 2>/dev/null && echoRgb "$txt重新生成" "1"
	exit 0
}
Validation_file() {
	MODDIR_NAME="${1%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${1##*/}"
	case ${FILE_NAME##*.} in
	lz4 | zst) zstd -t "$1" &>/dev/null ;;
	tar) tar -tf "$1" &>/dev/null ;;
	esac
	echo_log "效驗$MODDIR_NAME/$FILE_NAME"
}
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>/dev/null | sort)"
	i=1
	r="$(echo "$FIND_PATH" | wc -l)"
	while [[ $i -le $r ]]; do
		unset REPLY
		REPLY="$(echo "$FIND_PATH" | sed -n "${i}p")"
		Validation_file "$REPLY"
		[[ $result != 0 ]] && echo "效驗失敗:$MODDIR_NAME/$1">>"$error_log"
		echoRgb "$i/$r個剩$((r - i))個 $((i * 100 / r))%"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n$(cat "$error_log")" || echoRgb "恭喜~~全數效驗通過" 
	rm -rf "$error_log"
}
case $operate in
backup)
	kill_Serve
	[[ ! -d $script_path ]] && echo "$script_path腳本目錄遺失" && exit 2
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR | lz4 | Lz4 | LZ4) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	#效驗選填是否正確
	isBoolean "$Lo" "Lo" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$delete_folder" "delete_folder" && delete_folder="$nsx"
		isBoolean "$USBdefault" "USBdefault" && USBdefault="$nsx"
		isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
		isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
		isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
	else
		echoRgb "檢查目錄是否存在已卸載應用?\n -音量上檢查，下不檢查"
		get_version "檢查" "不檢查" && delete_folder="$branch"
		echoRgb "存在usb隨身碟是否默認使用隨身碟?\n -音量上默認，下進行詢問"
		get_version "默認" "詢問" && USBdefault="$branch"
		echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_obb_data="$branch"
		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_user_data="$branch"
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
	fi
	i=1
	#數據目錄
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	[[ ! -f $txt ]] && echoRgb "請執行\"生成應用列表.sh\"獲取應用列表再來備份" "0" && exit 1
	sort -u "$txt" -o "$txt" 2>/dev/null
	data="$MODDIR"
	hx="本地"
	echoRgb "壓縮方式:$Compression_method"
	echoRgb "提示 腳本支持後台壓縮 可以直接離開腳本\n -或是關閉終端也能備份 如需終止腳本\n -請執行終止腳本.sh即可停止\n -備份結束將發送toast提示語" "3"
	backup_path
	echoRgb "配置詳細:\n -音量鍵確認:$Lo\n -Toast:$toast_info\n -更新:$update\n -已卸載應用檢查:$delete_folder\n -默認使用usb:$USBdefault\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -自定義目錄備份:$backup_media"
	D="1"
	C="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	if [[ $delete_folder = true ]]; then
		if [[ -d $Backup ]]; then
			if [[ $1 = "" ]]; then
				find "$Backup" -maxdepth 1 -type d 2>/dev/null | sort | while read; do
					if [[ -f $REPLY/app_details ]]; then
						unset PackageName
						. "$REPLY/app_details" &>/dev/null
						if [[ $PackageName != "" && $(pm path --user "$user" "$PackageName" 2>/dev/null | cut -f2 -d ':') = "" ]]; then
							echoRgb "檢查到已卸載應用\n -音量上刪除資料夾，下移動到其他處"
							get_version "刪除" "移動到其他處" && operate="$branch"
							if [[ $operate = true ]]; then
								rm -rf "$REPLY"
								echoRgb "${REPLY##*/}不存在系統 刪除資料夾" "0"
							else
								if [[ ! -d $Backup/被卸載的應用 ]]; then
									mkdir -p "$Backup/被卸載的應用" && mv "$REPLY" "$Backup/被卸載的應用/"
								else
									mv "$REPLY" "$Backup/被卸載的應用/"
								fi
								[[ ! -d $Backup/被卸載的應用/tools ]] && cp -r "$tools_path" "$Backup/被卸載的應用" && rm -rf "$Backup/被卸載的應用/tools/bin/zip" "$Backup/被卸載的應用/tools/script"
								[[ ! -f $Backup/被卸載的應用/恢復備份.sh ]] && cp -r "$script_path/restore" "$Backup/被卸載的應用/恢復備份.sh"
								[[ ! -f $Backup/被卸載的應用/重新生成應用列表.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/被卸載的應用/重新生成應用列表.sh"
								[[ ! -f $Backup/被卸載的應用/轉換資料夾名稱.sh ]] && cp -r "$script_path/convert" "$Backup/被卸載的應用/轉換資料夾名稱.sh"
								[[ ! -f $Backup/被卸載的應用/壓縮檔完整性檢查.sh ]] && cp -r "$script_path/check_file" "$Backup/被卸載的應用/壓縮檔完整性檢查.sh"
								[[ ! -f $Backup/被卸載的應用/終止腳本.sh ]] && cp -r "$MODDIR/終止腳本.sh" "$Backup/被卸載的應用/終止腳本.sh"
								[[ ! -f $Backup/被卸載的應用/backup_settings.conf ]] && echo "#1開啟0關閉\n\n#是否在每次執行恢復腳本時使用音量鍵詢問如下需求\n#如果是那下面兩項項設置就被忽略，改為音量鍵選擇\nLo=$Lo\n\n#備份與恢復遭遇異常或是結束後發送通知(toast與狀態欄提示)\ntoast_info=$toast_info\n\n#腳本檢測更新後進行更新?\nupdate=$update\n\n#檢測到更新後的行為(1跳轉瀏覽器 0不跳轉瀏覽器，但是複製連結到剪裁版)\nupdate_behavior=$update_behavior\n#主色\nrgb_a=$rgb_a\n#輔色\nrgb_b=$rgb_b\nrgb_c=$rgb_c">"$Backup/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/被卸載的應用/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/被卸載的應用/backup_settings.conf"
								txt2="$Backup/被卸載的應用/appList.txt"
								[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安">"$txt2"
								echo "${REPLY##*/} $PackageName">>"$txt2"
								echo "$(sed -e "s/${REPLY##*/} $PackageName//g ; /^$/d" "$Backup/appList.txt")" >"$Backup/appList.txt"
								echoRgb "${REPLY##*/}不存在系統 已移動到$Backup/被卸載的應用" "0"
							fi
						fi
					fi
				done
			fi
		fi
	fi
	if [[ $1 = "" ]]; then
		echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
		while [[ $D -le $C ]]; do
			name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${D}p" | awk '{print $1}')"
			name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${D}p" | awk '{print $2}')"
			if [[ $name2 != "" && $(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':') = "" ]]; then
				echoRgb "$name1不存在系統，從列表中刪除" "0"
				echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$txt")" >"$txt"
			fi
			let D++
		done
		echo "$(sed -e '/^$/d' "$txt")" >"$txt"
	fi
	r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $1 != "" ]] && r=1
	[[ $r = "" ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/生成應用列表.sh" "0" && exit 1
	[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
	[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
	[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
	[[ ! -d $Backup ]] && mkdir -p "$Backup"
	txt2="$Backup/appList.txt"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安">"$txt2"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup" && rm -rf "$Backup/tools/bin/zip" "$Backup/tools/script"
	[[ ! -f $Backup/恢復備份.sh ]] && cp -r "$script_path/restore" "$Backup/恢復備份.sh"
	[[ ! -f $Backup/終止腳本.sh ]] && cp -r "$MODDIR/終止腳本.sh" "$Backup/終止腳本.sh"
	[[ ! -f $Backup/重新生成應用列表.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/重新生成應用列表.sh"
	[[ ! -f $Backup/轉換資料夾名稱.sh ]] && cp -r "$script_path/convert" "$Backup/轉換資料夾名稱.sh"
	[[ ! -f $Backup/壓縮檔完整性檢查.sh ]] && cp -r "$script_path/check_file" "$Backup/壓縮檔完整性檢查.sh"
	[[ -d $Backup/Media ]] && cp -r "$script_path/restore3" "$Backup/恢復自定義資料夾.sh"
	[[ ! -f $Backup/backup_settings.conf ]] && echo "#1開啟0關閉\n\n#是否在每次執行恢復腳本時使用音量鍵詢問如下需求\n#如果是那下面兩項項設置就被忽略，改為音量鍵選擇\nLo=$Lo\n\n#備份與恢復遭遇異常或是結束後發送通知(toast與狀態欄提示)\ntoast_info=$toast_info\n\n#使用者\nuser=\n\n#腳本檢測更新後進行更新?\nupdate=$update\n\n#檢測到更新後的行為(1跳轉瀏覽器 0不跳轉瀏覽器，但是複製連結到剪裁版)\nupdate_behavior=$update_behavior\n#主色\nrgb_a=$rgb_a\n#輔色\nrgb_b=$rgb_b\nrgb_c=$rgb_c">"$Backup/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/backup_settings.conf"
	filesha256="$(sha256sum "$bin_path/tools.sh" | cut -d" " -f1)"
	filesha256_1="$(sha256sum "$Backup/tools/bin/tools.sh" | cut -d" " -f1)"
	[[ $filesha256 != $filesha256_1 ]] && cp -r "$bin_path/tools.sh" "$Backup/tools/bin/tools.sh"
	filesize="$(du -ks "$Backup" | awk '{print $1}')"
	Quantity=0
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	en=118
	{
		osn=0; osx=0; osb=0; osg=0; osz=0; osd=0; ose=0; osj=0
		#獲取已經開啟的無障礙
		var="$(settings get secure enabled_accessibility_services)"
		#獲取預設鍵盤
		keyboard="$(settings get secure default_input_method)"
		[[ $(cat "$txt" | grep -v "#" | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
		while [[ $i -le $r ]]; do
			stopscript
			[[ $en -ge 229 ]] && en=118
			unset name1 name2 apk_path apk_path2
			if [[ $1 != "" ]]; then
				name1="$(appinfo -sort-i -d " " -o ands -pn "$1")"
				name2="$1"
			else
				name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
				name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
			fi
			[[ $name2 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
			apk_path="$(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':')"
			apk_path2="$(echo "$apk_path" | head -1)"
			apk_path2="${apk_path2%/*}"
			if [[ -d $apk_path2 ]]; then
				echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
				echoRgb "備份$name1 ($name2)" "2"
				unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version versionName apk_version2 apk_version3 userSize dataSize obbSize
				if [[ $name1 = *! || $name1 = *！ ]]; then
					name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
					echoRgb "跳過備份所有數據" "0"
					No_backupdata=1
				fi
				if [[ $(echo "$blacklist" | grep -w "$name2") = $name2 ]]; then
					echoRgb "黑名單應用跳過備份所有數據" "0"
					No_backupdata=1
				fi
				Backup_folder="$Backup/$name1"
				app_details="$Backup_folder/app_details"
				if [[ -f $app_details ]]; then
					. "$app_details" &>/dev/null
					if [[ $PackageName != $name2 ]]; then
						unset Backup_folder userSize ChineseName PackageName apk_version versionName apk_version2 apk_version3 result userSize dataSize obbSize
						Backup_folder="$Backup/${name1}[${name2}]"
						app_details="$Backup_folder/app_details"
						[[ -f $app_details ]] && . "$app_details" &>/dev/null
					fi
				fi
				[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
				starttime2="$(date -u "+%s")"
				[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
				[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
				apk_number="$(echo "$apk_path" | wc -l)"
				if [[ $apk_number = 1 ]]; then
					Backup_apk "非Split Apk" "3"
				else
					Backup_apk "Split Apk支持備份" "3"
				fi
				if [[ $result = 0 && $No_backupdata = "" && $nobackup != true ]]; then
					if [[ $Backup_obb_data = true ]]; then
						#備份data數據
						Backup_data "data"
						#備份obb數據
						Backup_data "obb"
					fi
					#備份user數據
					[[ $Backup_user_data = true ]] && Backup_data "user"
					[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d 2>/dev/null)"
					[[ $name2 = moe.shizuku.redirectstorage ]] && Backup_data "storage-isolation" "/data/adb/storage-isolation"
				fi
				endtime 2 "$name1備份" "3"
				Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
				lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
				echoRgb "完成$((i * 100 / r))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "3"
				rgb_d="$rgb_a"
				rgb_a=188
				echoRgb "_________________$(endtime 1 "已經")___________________"
				rgb_a="$rgb_d"
			else
				echoRgb "$name1[$name2]不在安裝列表，備份個寂寞？" "0"
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
					echo_log "設置鍵盤$(appinfo -d "(" -ed ")" -o ands,pn -pn "${keyboard%/*}" 2>/dev/null)"
				fi
				echoRgb "\n -已更新的apk=\"$osn\"\n -apk版本號無變化=\"$osj\"\n -user數據已備份=\"$osx\"\n -data數據已備份=\"$osb\"\n -obb數據已備份=\"$osg\"\n -user數據不存在=\"$osz\"\n -obb數據不存在=\"$osd\"\n -obb數據不存在=\"$ose\"" "3"
				echo "$(sort "$txt2" | sed -e '/^$/d')" >"$txt2"
				if [[ $backup_media = true ]]; then
					A=1
					B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
					if [[ $B != "" ]]; then
						echoRgb "備份結束，備份多媒體" "1"
						starttime1="$(date -u "+%s")"
						Backup_folder="$Backup/Media"
						[[ ! -f $Backup/恢復自定義資料夾.sh ]] && cp -r "$script_path/restore3" "$Backup/恢復自定義資料夾.sh"
						[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
						app_details="$Backup_folder/app_details"
						[[ -f $app_details ]] && . "$app_details" &>/dev/null
						mediatxt="$Backup/mediaList.txt"
						[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$mediatxt"
						echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | while read; do
							stopscript
							echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
							starttime2="$(date -u "+%s")"
							Backup_data "${REPLY##*/}" "$REPLY"
							[[ $result = 0 ]] && [[ $(cat "$mediatxt" | grep -v "#" | sed -e '/^$/d' | grep -w "^${REPLY##*/}.tar$" | head -1) = "" ]] && echo "${REPLY##*/}.tar" >> "$mediatxt"
							endtime 2 "${REPLY##*/}備份" "1"
							echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2"
							rgb_d="$rgb_a"
							rgb_a=188
							echoRgb "_________________$(endtime 1 "已經")___________________"
							rgb_a="$rgb_d" && let A++
						done
						echoRgb "目錄↓↓↓\n -$Backup_folder"
						endtime 1 "自定義備份"
					else
						echoRgb "自定義路徑為空 無法備份" "0"
					fi
				fi
			fi
			let i++ en++ nskg++
		done
		rm -rf "$TMPDIR/scriptTMP"
		Calculate_size "$Backup"
		echoRgb "批量備份完成"
		starttime1="$TIME"
		endtime 1 "批量備份開始到結束"
		longToast "批量備份完成"
		Print "批量備份完成 執行過程請查看$Status_log"
		#打開應用
		i=1
		am_start="$(echo "$am_start" | head -n 4 | xargs | sed 's/ /\|/g')"
		while [[ $i -le $r ]]; do
			unset pkg name1
			pkg="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
			name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
			if [[ $(echo "$pkg" | egrep -wo "^$am_start$") = $pkg ]]; then
				am start -n "$(appinfo -sort-i -d "/" -o pn,sa -pn "$pkg" 2>/dev/null)" &>/dev/null
				echo_log "啟動$name1"
			fi
			let i++
		done
		exit 0
	} &
	wait && exit
	;;
dumpname)
	get_name "Apkname"
	;;
convert)
	get_name "convert"
	;;
check_file)
	Check_archive "$MODDIR"
	;;
Restore)
	kill_Serve
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/終止腳本.sh\n -否則腳本將繼續執行直到結束" "0"
	echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/轉換資料夾名稱.sh"
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	i=1
	txt="$MODDIR/appList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行\"重新生成應用列表.sh\"獲取應用列表再來恢復" "0" && exit 2
	sort -u "$txt" -o "$txt" 2>/dev/null
	r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行\"重新生成應用列表.sh\"獲取應用列表再來恢復" "0" && exit 1
	[[ $(which restorecon) = "" ]] && echoRgb "restorecon命令不存在" "0" && exit 1
	#開始循環$txt內的資料進行恢複
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	en=118
	{
		while [[ $i -le $r ]]; do
			stopscript
			[[ $en -ge 229 ]] && en=118
			echoRgb "恢複第$i/$r個應用 剩下$((r - i))個" "3"
			name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
			name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
			unset No_backupdata apk_version
			if [[ $name1 = *! || $name1 = *！ ]]; then
				name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
				echoRgb "跳過恢復$name1 所有數據" "0"
				No_backupdata=1
			fi
			Backup_folder="$MODDIR/$name1"
			Backup_folder2="$MODDIR/Media"
			[[ -f "$Backup_folder/app_details" ]] && . "$Backup_folder/app_details" &>/dev/null
			[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
			if [[ -d $Backup_folder ]]; then
				echoRgb "恢複$name1 ($name2)" "2"
				starttime2="$(date -u "+%s")"
				if [[ $(pm path --user "$user" "$name2" 2>/dev/null) = "" ]]; then
					installapk
				else
					if [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]]; then
						installapk
						echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
					fi
				fi
				if [[ $(pm path --user "$user" "$name2" 2>/dev/null) != "" ]]; then
					if [[ $No_backupdata = "" ]]; then
						#停止應用
						[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
						find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read; do
							Release_data "$REPLY"
						done
					fi
				else
					[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
				fi
				endtime 2 "$name1恢複" "2" && echoRgb "完成$((i * 100 / r))%" "3"
				rgb_d="$rgb_a"
				rgb_a=188
				echoRgb "_________________$(endtime 1 "已經")___________________"
				rgb_a="$rgb_d"
			else
				echoRgb "$Backup_folder資料夾遺失，無法恢複" "0"
			fi
			if [[ $i = $r ]]; then
				endtime 1 "應用恢復" "2"
				if [[ -d $Backup_folder2 ]]; then
					Print "是否恢復多媒體數據 音量上恢復，音量下不恢復"
					echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
					get_version "恢復媒體數據" "跳過恢復媒體數據"
					starttime1="$(date -u "+%s")"
					A=1
					B="$(find "$Backup_folder2" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | wc -l)"
					if [[ $branch = true ]]; then
						find "$Backup_folder2" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | while read; do
							starttime2="$(date -u "+%s")"
							echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
							Release_data "$REPLY"
							endtime 2 "$FILE_NAME2恢複" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
						done
						endtime 1 "自定義恢復" "2"
					fi
				fi
			fi
			let i++ en++ nskg++
		done
		rm -rf "$TMPDIR/scriptTMP"
		starttime1="$TIME"
		echoRgb "批量恢複完成" && endtime 1 "批量恢複開始到結束" && echoRgb "如發現應用閃退請重新開機"
		longToast "批量恢復完成"
		Print "批量恢復完成 執行過程請查看$Status_log" && rm -rf "$TMPDIR"/*
	} &
	wait && exit
	;;
Restore2)
	kill_Serve
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	[[ $(which restorecon) = "" ]] && echoRgb "restorecon命令不存在" "0" && exit 1
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	{
		Backup_folder="$MODDIR"
		if [[ ! -f $Backup_folder/app_details ]]; then
			echoRgb "$Backup_folder/app_details遺失，無法獲取包名" "0" && exit 1
		else
			. "$Backup_folder/app_details" &>/dev/null
		fi
		name1="$ChineseName"
		[[ $name1 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
		name2="$PackageName"
		if [[ $name2 = "" ]]; then
			Script_path="$(find "$MODDIR" -maxdepth 1 -name "*.sh*" -type f 2>/dev/null)"
			name2="$(echo "${Script_path##*/}" | sed 's/.sh//g')"
		fi
		[[ $name2 = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
		echoRgb "恢複$name1 ($name2)" "2"
		starttime2="$(date -u "+%s")"
		if [[ $(pm path --user "$user" "$name2" 2>/dev/null) = "" ]]; then
			installapk
		else
			apk_version="$(echo "$apk_version" | head -n 1)"
			if [[ $apk_version -gt $(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1) ]]; then
				installapk
				echoRgb "版本提升$(pm list packages --show-versioncode --user "$user" "$name2" 2>/dev/null | cut -f3 -d ':' | head -n 1)>$apk_version" "1"
			fi
		fi
		if [[ $(pm path --user "$user" "$name2" 2>/dev/null) != "" ]]; then
			#停止應用
			[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
			find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read; do
				Release_data "$REPLY"
			done
		else
			echoRgb "$name1沒有安裝無法恢復數據" "0"
		fi
		endtime 1 "恢複開始到結束" && echoRgb "如發現應用閃退請重新開機" && rm -rf "$TMPDIR"/*
		rm -rf "$TMPDIR/scriptTMP"
	} &
	wait && exit
	;;
Restore3)
	kill_Serve
	echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -音量上繼續恢復自定義資料夾，音量下離開腳本" "2"
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊終止腳本.sh,否則腳本將繼續執行直到結束" "0"
	get_version "恢復自定義資料夾" "離開腳本" && [[ "$branch" = false ]] && exit 0
	mediaDir="$MODDIR/Media"
	Backup_folder2="$mediaDir"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行\"重新生成應用列表.sh\"獲取媒體列表再來恢復" "0" && exit 2
	sort -u "$txt" -o "$txt" 2>/dev/null
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	echo_log() {
		if [[ $? = 0 ]]; then
			echoRgb "$1成功" "1" && result=0
		else
			echoRgb "$1恢複失敗，過世了" "0" && result=1
		fi
	}
	starttime1="$(date -u "+%s")"
	A=1
	B="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行\"重新生成應用列表.sh\"獲取列表再來恢復" "0" && exit 1
	while [[ $A -le $B ]]; do
		stopscript
		name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${A}p" | awk '{print $1}')"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢複" "2" && echoRgb "完成$((A * 100 / B))%" "3" && echoRgb "____________________________________" && let A++
	done
	endtime 1 "恢複結束"
	rm -rf "$TMPDIR/scriptTMP"
	;;
Getlist)
	#效驗選填是否正確
	isBoolean "$Lo" "Lo" && Lo="$nsx"
	isBoolean "$debug_list" "debug_list" && debug_list="$nsx"
	txtpath="$MODDIR"
	[[ $debug_list = true ]] && txtpath="${txtpath/'/storage/emulated/'/'/data/media/'}"
	nametxt="$txtpath/appList.txt"
	[[ ! -e $nametxt ]] && echo '#不需要備份的應用請在開頭注釋# 比如#酷安 xxxxxxxx\n#不需要備份數據比如酷安! xxxxxxxx應用名後方加一個驚嘆號即可 注意是應用名不是包名' >"$nametxt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	rm -rf "$MODDIR/tmp"
	starttime1="$(date -u "+%s")"
	echoRgb "提示!因為系統自帶app(位於data分區或是可卸載預裝應用)備份恢復可能存在問題\n -所以不會輸出..但是檢測為Xposed類型包名將輸出\n -如果提示不是Xposed但他就是Xposed可能為此應用元數據不符合規範導致" "0"
	xposed_name="$(appinfo -o pn -xm)"
	[[ $user = 0 ]] && Apk_info="$(appinfo -sort-i -d " " -o ands,pn -pn $system -3 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)" || Apk_info="$(appinfo -sort-i -d " " -o ands,pn -pn $system $(pm list packages -3 --user "$user" | cut -f2 -d ':') 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	[[ $Apk_info = "" ]] && echoRgb "appinfo輸出失敗" "0" && exit 2
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	echo "$Apk_info" | sed 's/\///g ; s/\://g ; s/(//g ; s/)//g ; s/\[//g ; s/\]//g ; s/\-//g ; s/!//g' | while read; do
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_1=($REPLY $REPLY)
		if [[ $(cat "$nametxt" | cut -f2 -d ' ' | egrep -w "^${app_1[1]}$") != ${app_1[1]} ]]; then
			case ${app_1[1]} in
			*oneplus* | *miui* | *xiaomi* | *oppo* | *flyme* | *meizu* | com.android.soundrecorder | com.mfashiongallery.emag | com.mi.health | *coloros*)
				if [[ $(echo "$xposed_name" | egrep -w "${app_1[1]}$") = ${app_1[1]} ]]; then
					echoRgb "${app_1[2]}為Xposed模塊 進行添加" "0"
					echo "$REPLY" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
					let i++ rd++
				else
					if [[ $(echo "$whitelist" | egrep -w "^${app_1[1]}$") = ${app_1[1]} ]]; then
						echo "$REPLY" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
						echoRgb "$REPLY($rgb_a)"
						let i++
					else
						echoRgb "${app_1[2]}非Xposed模塊 忽略輸出" "0"
						let rc++
					fi
				fi
				;;
			*)
				echo "$REPLY" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
				echoRgb "$REPLY($rgb_a)"
				let i++
				;;
			esac
		else
			let Q++
		fi
		if [[ $LR = $Apk_Quantity ]]; then
			if [[ $(cat "$nametxt" | wc -l | awk '{print $1-2}') -lt $i ]]; then
				rm -rf "$nametxt" "$MODDIR/tmp"
				echoRgb "\n -輸出異常 請將$MODDIR_NAME/backup_settings.conf中的debug_list=\"0\"改為1或是重新執行本腳本" "0"
				exit
			fi
			[[ -e $MODDIR/tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let rgb_a++ LR++
	done
	if [[ -f $nametxt ]]; then
		D="1"
		C="$(cat "$nametxt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
		while [[ $D -le $C ]]; do
			name1="$(cat "$nametxt" | grep -v "#" | sed -e '/^$/d' | sed -n "${D}p" | awk '{print $1}')"
			name2="$(cat "$nametxt" | grep -v "#" | sed -e '/^$/d' | sed -n "${D}p" | awk '{print $2}')"
			{
			if [[ $name2 != "" && $(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':') = "" ]]; then
				echoRgb "$name1 $name2不存在系統，從列表中刪除" "0"
				echo "$(sed -e "s/$name1 $name2//g ; /^$/d" "$nametxt")" >"$nametxt"
			fi
			} &
			let D++
		done
		echo "$(sort "$nametxt" | sed -e '/^$/d')" >"$nametxt"
	fi
	wait
	endtime 1
	[[ ! -e $MODDIR/tmp ]] && echoRgb "無新增應用" || echoRgb "輸出包名結束 請查看$nametxt"
	rm -rf "$MODDIR/tmp"
	;;
backup_media)
	kill_Serve
	backup_path
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊終止腳本.sh,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		[[ ! -f $Backup/恢復自定義資料夾.sh ]] && cp -r "$script_path/restore3" "$Backup/恢復自定義資料夾.sh"
		[[ ! -f $Backup/重新生成應用列表.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/重新生成應用列表.sh"
		[[ ! -f $Backup/轉換資料夾名稱.sh ]] && cp -r "$script_path/convert" "$Backup/轉換資料夾名稱.sh"
		[[ ! -f $Backup/壓縮檔完整性檢查.sh ]] && cp -r "$script_path/check_file" "$Backup/壓縮檔完整性檢查.sh"
		[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup" && rm -rf "$Backup/tools/bin/zip" "$Backup/tools/script"
		[[ ! -f $Backup/backup_settings.conf ]] && echo "#1開啟0關閉\n\n#是否在每次執行恢復腳本時使用音量鍵詢問如下需求\n#如果是那下面兩項項設置就被忽略，改為音量鍵選擇\nLo=$Lo\n\n#備份與恢復遭遇異常或是結束後發送通知(toast與狀態欄提示)\ntoast_info=$toast_info\n\n#腳本檢測更新後進行更新?\nupdate=$update\n\n#檢測到更新後的行為(1跳轉瀏覽器 0不跳轉瀏覽器，但是複製連結到剪裁版)\nupdate_behavior=$update_behavior">"$Backup/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/backup_settings.conf"
		app_details="$Backup_folder/app_details"
		filesize="$(du -ks "$Backup_folder" | awk '{print $1}')"
		[[ -f $app_details ]] && . "$app_details" &>/dev/null || touch "$app_details"
		mediatxt="$Backup/mediaList.txt"
		[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$mediatxt"
		echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | while read; do
			stopscript
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")" 
			[[ ${REPLY: -1} = / ]] && REPLY="${REPLY%?}"
			Backup_data "${REPLY##*/}" "$REPLY"
			[[ $result = 0 ]] && [[ $(cat "$mediatxt" | grep -v "#" | sed -e '/^$/d' | grep -w "^${REPLY##*/}.tar$" | head -1) = "" ]] && echo "${REPLY##*/}.tar" >> "$mediatxt"
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
		done
		Calculate_size "$Backup_folder"
		echoRgb "目錄↓↓↓\n -$Backup_folder"
		endtime 1 "自定義備份"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	;;
esac