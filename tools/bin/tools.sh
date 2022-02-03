#!/system/bin/sh
#MODDIR="${0%/*}"
MODDIR="$MODDIR"
tools_path="$MODDIR/tools"
path="/data/media/0/Android"
path2="/data/data"
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
[[ ! -f $conf_path ]] && echo "backup_settings.conf配置遺失" && EXIT="true"
[[ $EXIT = true ]] && exit 1
. "$bin_path/bin.sh"
. "$conf_path"
update_script() {
	cdn=2
	#settings get system system_locales
	LANG="$(getprop "persist.sys.locale")"
	zippath="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f)"
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
	json="$(curl "$Language" 2>/dev/null)"
	if [[ $json != "" ]]; then
		echoRgb "使用curl"
	else
		json="$(down -s -L "$Language" 2>/dev/null)"
		[[ $json != "" ]] && echoRgb "使用down"
	fi
	if [[ $json != "" ]]; then
		tag="$(echo "$json" | sed -r -n 's/.*"tag_name": *"(.*)".*/\1/p')"
		if [[ $backup_version != $tag ]]; then
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
						isBoolean "$update_behavior" "update_behavior" && update_behavior="$nsx"
						if [[ $update_behavior = true ]]; then
							echoRgb "更新腳本步驟如下\n -1.將跳轉時下載的zip壓縮包完整不解壓縮放在$MODDIR\n -2.在$MODDIR目錄隨便執行一個腳本\n -3.假設沒有提示錯誤重新進入腳本如版本號發生變化則更新成功" "2"
							am start -a android.intent.action.VIEW -d "$zip_url"
							echo_log "跳轉瀏覽器"
						else
							echoRgb "更新腳本步驟如下\n -1.將剪貼簿內的連結用瀏覽器下載\n -2.將zip壓縮包完整不解壓縮放在$MODDIR\n -3.在$MODDIR目錄隨便執行一個腳本\n -4.假設沒有提示錯誤重新進入腳本如版本號發生變化則更新成功" "2"
							starttime1="$(date -u "+%s")"
							xtext "$zip_url" 
							echo_log "複製連結到剪裁版"
							endtime 1
						fi
						exit 0
					else
						echoRgb "backup_settings.conf內update選項為0忽略更新僅提示更新" "0"
					fi
				fi
			fi
		fi
	else
		echoRgb "更新獲取失敗" "0"
	fi
}
case $operate in
backup)
	script="${0##*/}"
	if [[ $script != "" ]]; then
		for x in zstd tar pv lz4; do
			pgrep -f "$x" | while read; do
				kill -KILL "$REPLY" >/dev/null
			done
		done
	fi
	[[ ! -d $script_path ]] && echo "$script_path腳本目錄遺失" && exit 2
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR | lz4 | Lz4 | LZ4) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
		isBoolean "$Splist" "Splist" && Splist="$nsx"
		isBoolean "$toast_info" "toast_info" && toast_info="$nsx"
		isBoolean "$USBdefault" "USBdefault" && USBdefault="$nsx"
		isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx"
		isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx"
		isBoolean "$backup_media" "backup_media" && backup_media="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
		echoRgb "備份完成或是遭遇異常發送toast與狀態欄通知？\n -音量上提示，音量下靜默備份" "2"
		get_version "提示" "靜默備份" && toast_info="$branch"
		echoRgb "選擇是否只備份split apk(分割apk檔)\n -如果你不知道這意味什麼請選擇音量下進行混合備份\n -音量上僅備份split apk，音量下混合備份" "2"
		get_version "是" "不是，混合備份" && Splist="$branch"
		echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_obb_data="$branch"
		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_user_data="$branch"
		echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && backup_media="$branch"
	fi
	update_script
	i=1
	#數據目錄
	path="/data/media/0/Android"
	path2="/data/user/0"
	txt="$MODDIR/appList.txt"
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	PU="$(ls /dev/block/vold | grep public)"
	if [[ ! -f $txt ]]; then
		echoRgb "請執行\"Getlist.sh\"獲取應用列表再來備份" "0" && exit 1
	else
		cat "$txt" | grep -v "#" | while read; do
			name=($REPLY $REPLY $REPLY)
			if [[ $REPLY != "" && ${name[1]} != "" && $(pm path "${name[1]}" | cut -f2 -d ':') = "" ]]; then
				echoRgb "${name[3]}不存在系統，從列表中刪除" "0"
				echo "$(sed -e "s/$REPLY//g ; /^$/d" "$txt")" >"$txt"
			fi
		done
		echo "$(sed -e '/^$/d' "$txt")" >"$txt"
		if [[ -f $MODDIR/systemList.txt ]]; then
			cat "$txt" >"$TMPDIR/applist" && cat "$MODDIR/systemList.txt" >>"$TMPDIR/applist"
			[[ -f $TMPDIR/applist ]] && txt="$TMPDIR/applist"
			echoRgb "列表內包含系統應用 針對系統應用僅備份數據不備份apk" "2"
		else
			echoRgb "僅第三方應用" "2"
		fi
	fi
	r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $r = "" ]] && echoRgb "爬..appList.txt是空的或是包名被注釋了這樣備份個鬼" "0" && exit 1
	data="$MODDIR"
	hx="本地"
	echoRgb "壓縮方式:$Compression_method" "1"
	echoRgb "提示 腳本支持後台壓縮 可以直接離開腳本\n -或是關閉終端也能備份 如需終止腳本\n -請再次執行$script即可停止\n -備份結束將發送toast提示語" "1"
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		Backup="$Output_path/Backup_$Compression_method"
		outshow="使用自定義目錄"
	else
		if [[ $APP_ENV = 1 ]]; then
			Backup="/storage/emulated/0/Backup_$Compression_method"
			outshow="沒有設定備份目錄 使用默認路徑"
		else
			Backup="$MODDIR/Backup_$Compression_method"
			outshow="使用當前路徑作為備份目錄"
		fi
	fi
	if [[ $PU != "" ]]; then
		[[ -f /proc/mounts ]] && PT="$(cat /proc/mounts | grep "$PU" | awk '{print $2}')"
		if [[ -d $PT ]]; then
			if [[ $(echo "$MODDIR" | grep -oE "^${PT}") != "" || $USBdefault = true ]]; then
				hx="USB"
			else
				echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
				get_version "選擇了隨身碟備份" "選擇了本地備份"
				[[ $branch = true ]] && hx="USB"
			fi
			if [[ $hx = USB ]]; then
				Backup="$PT/Backup_$Compression_method"
				data="/dev/block/vold/$PU"
				mountinfo="$(df -T "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')"
				case $mountinfo in
				vfat | fuseblk | exfat | NTFS | ext4 | f2fs)
					outshow="於隨身碟備份"
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
	rm -rf "$Backup/STOP"
	#分區詳細
	if [[ $(echo "$Backup" | egrep -o "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | sed 's/G//g' | awk 'END{print "總共:"$1"G已用:"$2"G剩餘:"$3"G使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
	[[ $Backup_user_data = false ]] && echoRgb "當前backup_settings.conf的\n -Backup_user_data為0將不備份user數據" "0"
	[[ $Backup_obb_data = false ]] && echoRgb "當前backup_settings.conf的\n -Backup_obb_data為0將不備份外部數據" "0"
	[[ $backup_media = false ]] && echoRgb "當前backup_settings.conf的\n -backup_media為0將不備份自定義資料夾" "0"
	[[ ! -d $Backup ]] && mkdir -p "$Backup"
	txt2="$Backup/appList.txt"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安">"$txt2"
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup" && rm -rf "$Backup/tools/bin/zip" "$Backup/tools/script"
	[[ ! -f $Backup/Restorebackup.sh ]] && cp -r "$script_path/restore" "$Backup/Restorebackup.sh"
	[[ ! -f $Backup/DumpName.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/DumpName.sh"
	[[ ! -f $Backup/backup_settings.conf ]] && echo "#1開啟0關閉\n\n#是否在每次執行恢復腳本時使用音量鍵詢問如下需求\n#如果是那下面兩項項設置就被忽略，改為音量鍵選擇\nLo=$Lo\n\n#備份與恢復遭遇異常或是結束後發送通知(toast與狀態欄提示)\ntoast_info=$toast_info\n\n#腳本檢測更新後進行跳轉瀏覽器或是複製連結?\nupdate=$update\n\n#檢測到更新後的行為(1跳轉瀏覽器 0不跳轉瀏覽器，但是複製連結到剪裁版)\nupdate_behavior=$update_behavior">"$Backup/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/backup_settings.conf"
	filesize="$(du -ks "$Backup" | awk '{print $1}')"
	Quantity=0
	#分區佔用信息
	partition_info() {
		Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
		lxj="$(echo "$Occupation_status" | awk '{print $2}' | sed 's/%//g')"
	}
	#檢測apk狀態進行備份
	Backup_apk() {
		#創建APP備份文件夾
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		if [[ $apk_version = $(dumpsys package "$name2" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1) ]]; then
			unset xb
			result=0
			echoRgb "Apk版本無更新 跳過備份" "2"
		else
			if [[ $name3 != system ]]; then
				case $name2 in
				com.google.android.youtube)
					[[ -d /data/adb/Vanced ]] && nobackup="true"
					;;
				com.google.android.apps.youtube.music)
					[[ -d /data/adb/Music ]] && nobackup="true"
					;;
				esac
				if [[ $nobackup != true ]]; then
					[[ $(cat "$txt2" | grep -v "#" | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2 $name3" >>"$txt2"
					partition_info
					[[ $lxj -ge 95 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
					rm -rf "$Backup_folder"/*.apk
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
						tar | TAR | Tar) tar -cf "$Backup_folder/apk.tar" *.apk ;;
						lz4 | LZ4 | Lz4) tar -cf - *.apk | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/apk.tar.lz4" ;;
						zstd | Zstd | ZSTD) tar -cf - *apk | zstd -r -T0 --ultra -6 -q --priority=rt >"$Backup_folder/apk.tar.zst" ;;
						esac
					)
					echo_log "備份$apk_number個Apk"
					if [[ $result = 0 ]]; then
						#pm list packages --show-versioncode "$name2"
						echo "apk_version=\"$(dumpsys package "$name2" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1)\"" >>"$app_details"
						[[ $PackageName = "" ]] && echo "PackageName=\"$name2\"" >>"$app_details"
						[[ $ChineseName = "" ]] && echo "ChineseName=\"$name1\"" >>"$app_details"
						[[ $type = "" ]] && echo "type=\"$name3\"" >>"$app_details"
						[[ ! -f $Backup_folder/Restorebackup.sh ]] && cp -r "$script_path/restore2" "$Backup_folder/Restorebackup.sh"
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
					echoRgb "$name不支持備份 需要使用vanced安裝" "0" && rm -rf "$Backup_folder"
				fi
			else
				echoRgb "$name2為系統應用不備份apk" "3" && result="0"
				[[ $PackageName = "" ]] && echo "PackageName=\"$name2\"" >>"$app_details"
				[[ $ChineseName = "" ]] && echo "ChineseName=\"$name1\"" >>"$app_details"
				[[ $type = "" ]] && echo "type=\"$name3\"" >>"$app_details"
				[[ ! -f $Backup_folder/Restorebackup.sh ]] && cp -r "$script_path/restore2" "$Backup_folder/Restorebackup.sh"
			fi
		fi
		[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
		D=1
	}
	#檢測數據位置進行備份
	Backup_data() {
		unset zsize
		case $1 in
		user) Size="$userSize" && data_path="$path2/$name2" ;;
		data) Size="$dataSize" && data_path="$path/$1/$name2" ;;
		obb) Size="$obbSize" && data_path="$path/$1/$name2" ;;
		*)
			[[ -f $app_details ]] && Size="$(cat "$app_details" | awk "/$1Size/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')"
			data_path="$2"
			Compression_method1="$Compression_method"
			Compression_method=tar
			zsize=1
			;;
		esac
		if [[ -d $data_path ]]; then
			if [[ $Size != $(du -ks "$data_path" | awk '{print $1}') ]]; then
				partition_info
				[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
				[[ $lxj -ge 95 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
				echoRgb "備份$1數據"
				case $1 in
				user)
					case $Compression_method in
					tar | Tar | TAR) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
					zstd | Zstd | ZSTD) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -6 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
					lz4 | Lz4 | LZ4) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/$1.tar.lz4" ;;
					esac
					;;
				*)
					case $Compression_method in
					tar | Tar | TAR) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cPpf - "$data_path" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
					zstd | Zstd | ZSTD) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cPpf - "$data_path" 2>/dev/null | pv | zstd -r -T0 --ultra -6 -q --priority=rt >"$Backup_folder/$1.tar.zst" ;;
					lz4 | Lz4 | LZ4) tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cPpf - "$data_path" 2>/dev/null | pv | zstd -r -T0 --ultra -1 -q --priority=rt --format=lz4 >"$Backup_folder/$1.tar.lz4" ;;
					esac
					[[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1"
					unset Compression_method1
					;;
				esac
				echo_log "備份$1數據"
				if [[ $result = 0 ]]; then
					if [[ $zsize != "" ]]; then
						echo "#$1Size=\"$(du -ks "$data_path" | awk '{print $1}')\"" >>"$app_details"
						[[ $2 != $(cat "$app_details" | awk "/$1path/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g') ]] && echo "#$1path=\"$2\"" >>"$app_details"
					else
						echo "$1Size=\"$(du -ks "$data_path" | awk '{print $1}')\"" >>"$app_details"
					fi
				fi
			else
				echoRgb "$1數據無發生變化 跳過備份" "2"
			fi
		else
			if [[ -f $data_path ]]; then
				echoRgb "$1是一個文件 不支持備份" "0"
			else
				echoRgb "$1數據不存在跳過備份" "2"
			fi
		fi
		partition_info
	}
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	en=118
	{
		while [[ $i -le $r ]]; do
			[[ $en -ge 229 ]] && en=118
			unset name1 name2 apk_path apk_path2 result
			name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
			name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
			name3="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $3}')"
			[[ $name2 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
			apk_path="$(pm path "$name2" | cut -f2 -d ':')"
			apk_path2="$(echo "$apk_path" | head -1)"
			apk_path2="${apk_path2%/*}"
			if [[ -d $apk_path2 ]]; then
				echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
				unset ChineseName PackageName nobackup No_backupdata result type
				if [[ $name1 = *! || $name1 = *！ ]]; then
					name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
					echoRgb "跳過備份$name1 所有數據" "0"
					No_backupdata=1
				fi
				Backup_folder="$Backup/$name1"
				app_details="$Backup_folder/app_details"
				if [[ -f $app_details ]]; then
					. "$app_details"
					if [[ $PackageName != $name2 ]]; then
						unset userSize ChineseName PackageName apk_version type result
						Backup_folder="$Backup/${name1}[${name2}]"
						app_details="$Backup_folder/app_details"
						[[ -f $app_details ]] && . "$app_details"
					fi
				fi
				[[ -f $Backup/STOP ]] && echoRgb "離開腳本" "0" && exit 1
				[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
				starttime2="$(date -u "+%s")"
				echoRgb "備份$name1 ($name2)"
				[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
				[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
				apk_number="$(echo "$apk_path" | wc -l)"
				if [[ $apk_number = 1 ]]; then
					if [[ $Splist = false ]]; then
						Backup_apk "非Split Apk" "3"
					else
						echoRgb "非Split Apk跳過備份" "0" && unset D
					fi
				else
					Backup_apk "Split Apk支持備份" "3"
				fi
				if [[ $D != "" && $result = 0 && $No_backupdata = "" && $nobackup != true ]]; then
					if [[ $Backup_obb_data = true ]]; then
						#備份data數據
						Backup_data "data"
						#備份obb數據
						Backup_data "obb"
					fi
					#備份user數據
					[[ $Backup_user_data = true ]] && Backup_data "user"
					[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d)"
				fi
				endtime 2 "$name1備份" "3"
				Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
				lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
				echoRgb "完成$((i * 100 / r))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "3"
				echoRgb "____________________________________"
			else
				echoRgb "$name1[$name2]不在安裝列表，備份個寂寞？" "0"
			fi
			if [[ $i = $r ]]; then
				endtime 1 "應用備份" "3"
				if [[ $backup_media = true ]]; then
					A=1
					B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
					if [[ $B != "" ]]; then
						echoRgb "備份結束，備份多媒體" "1"
						starttime1="$(date -u "+%s")"
						Backup_folder="$Backup/Media"
						[[ ! -f $Backup/Restoremedia.sh ]] && cp -r "$script_path/restore3" "$Backup/Restoremedia.sh"
						[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
						app_details="$Backup_folder/app_details"
						[[ -f $app_details ]] && . "$app_details"
						mediatxt="$Backup/mediaList.txt"
						[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$mediatxt"
						echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | while read; do
							echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
							starttime2="$(date -u "+%s")"
							Backup_data "${REPLY##*/}" "$REPLY"
							[[ $result = 0 ]] && [[ $(cat "$mediatxt" | grep -v "#" | sed -e '/^$/d' | grep -w "^${REPLY##*/}.tar$" | head -1) = "" ]] && echo "${REPLY##*/}.tar" >> "$mediatxt"
							endtime 2 "${REPLY##*/}備份" "1"
							echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
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
		echoRgb "你要備份跑路？祝你卡米9008"
		#計算出備份大小跟差異性
		filesizee="$(du -ks "$Backup" | awk '{print $1}')"
		dsize="$(($((filesizee - filesize)) / 1024))"
		echoRgb "備份資料夾路徑↓↓↓\n -$Backup"
		echoRgb "備份資料夾總體大小$(du -ksh "$Backup" | awk '{print $1}')"
		if [[ $dsize -gt 0 ]]; then
			if [[ $((dsize / 1024)) -gt 0 ]]; then
				echoRgb "本次備份: $((dsize / 1024))gb"
			else
				echoRgb "本次備份: ${dsize}mb"
			fi
		else
			echoRgb "本次備份: $(($((filesizee - filesize)) * 1000 / 1024))kb"
		fi
		echoRgb "批量備份完成"
		starttime1="$TIME"
		endtime 1 "批量備份開始到結束"
		longToast "批量備份完成"
		Print "批量備份完成 執行過程請查看$Status_log"
		exit 0
	} &
	wait && exit
	;;
dumpname)
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
	fi
	update_script
	txt="$MODDIR/appList.txt"
	txt2="$MODDIR/mediaList.txt"
	rm -rf *.txt
	txt="${txt/'/storage/emulated/'/'/data/media/'}"
	echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	find "$MODDIR" -maxdepth 1 -type d | sort | while read; do
		if [[ -f $REPLY/app_details ]]; then
			if [[ ${REPLY##*/} = Media ]]; then
				echoRgb "存在媒體資料夾" "2"
				[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$txt2"
				find "$REPLY" -maxdepth 1 -name "*.tar*" -type f | while read; do
					echo "${REPLY##*/}" >> "$txt2"
				done
				echoRgb "$txt2重新生成" "1"
			fi
			unset PackageName
			. "$REPLY/app_details"
			if [[ $PackageName != "" ]]; then
				[[ ! -f $txt ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$txt"
				echo "${REPLY##*/} $PackageName $type" >>"$txt"
			fi
		fi
	done
	echoRgb "$txt重新生成" "1"
	;;
Restore)
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
		isBoolean "$toast_info" "toast_info" && toast_info="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
		echoRgb "備份完成或是遭遇異常發送toast與狀態欄通知？\n -音量上提示，音量下靜默備份" "2"
		get_version "提示" "靜默備份" && toast_info="$branch"
	fi
	update_script
	#禁用apk驗證
	settings put global verifier_verify_adb_installs 0
	#禁用安裝包驗證
	settings put global package_verifier_enable 0
	#關閉play安全效驗
	if [[ $(settings get global package_verifier_user_consent) != "" && $(settings get global package_verifier_user_consent) != -1 ]]; then
		settings put global package_verifier_user_consent -1
		settings put global upload_apk_enable 0
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	i=1
	txt="$MODDIR/appList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行\"DumpName.sh\"獲取應用列表再來恢復" "0" && exit 2
	r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行\"DumpName.sh\"獲取應用列表再來恢復" "0" && exit 1
	[[ $(which restorecon) = "" ]] && echoRgb "restorecon命令不存在" "0" && exit 1
	#顯示執行結果
	Release_data() {
		tar_path="$1"
		X="$path2/$name2"
		FILE_NAME="${tar_path##*/}"
		FILE_NAME2="${FILE_NAME%%.*}"
		echoRgb "恢復$FILE_NAME2數據" "3"
		case $FILE_NAME2 in
		user)
			if [[ -d $X ]]; then
				case ${FILE_NAME##*.} in
				lz4 | zst) pv "$tar_path" | tar --recursive-unlink -I zstd -xmpf - -C "$path2" ;;
				tar) pv "$tar_path" | tar --recursive-unlink -xmpf - -C "$path2" ;;
				*)
					echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
					Set_back
					;;
				esac
			else
				echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
				Set_back
			fi
			;;
		data | obb)
			case ${FILE_NAME##*.} in
			lz4 | zst) pv "$tar_path" | tar --recursive-unlink -I zstd -xmPpf - ;;
			tar) pv "$tar_path" | tar --recursive-unlink -xmPpf - ;;
			*)
				echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
				Set_back
				;;
			esac
			;;
		*)
			[[ $FILE_NAME2 = thanox ]] && rm -rf "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d)"
			case ${FILE_NAME##*.} in
			lz4 | zst) pv "$tar_path" | tar -I zstd -xmPpf - ;;
			tar) pv "$tar_path" | tar -xPpf - ;;
			*)
				echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
				Set_back
				;;
			esac
			;;
		esac
		echo_log "$FILE_NAME 解壓縮($FILE_NAME2)"
		if [[ $result = 0 ]]; then
			if [[ $A != "" ]]; then
				app_details="$Backup_folder2/app_details"
				[[ -f $app_details ]] && echoRgb "解壓路徑↓\n -$(cat "$app_details" | awk "/${FILE_NAME2}path/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')" "2" || echoRgb "已經成功解壓縮 但是解壓路徑獲取失敗" "0"
			fi
			case $FILE_NAME2 in
			user)
				if [[ -d $X ]]; then
					if [[ -f /config/sdcardfs/$name2/appid ]]; then
						G="$(cat "/config/sdcardfs/$name2/appid")"
					else
						G="$(dumpsys package "$name2" | awk '/userId=/{print $1}' | cut -f2 -d '=' | head -1)"
					fi
					G="$(echo "$G" | egrep -o '[0-9]+')"
					if [[ $G != "" ]]; then
						echoRgb "路徑:$X"
						Path_details="$(stat -c "%A/%a %U/%G" "$X")"
						chown -hR "$G:$G" "$X/"
						echo_log "設置用戶組:$(echo "$Path_details" | awk '{print $2}')"
						restorecon -RF "$X/" >/dev/null 2>&1
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
				restorecon -RF "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d)/" >/dev/null 2>&1
				echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
				;;
			esac
		fi
	}
	#開始循環$txt內的資料進行恢複
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	en=118
	{
		while [[ $i -le $r ]]; do
			[[ $en -ge 229 ]] && en=118
			echoRgb "恢複第$i/$r個應用 剩下$((r - i))個" "3"
			name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
			name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
			name3="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $3}')"
			unset No_backupdata
			if [[ $name1 = *! || $name1 = *！ ]]; then
				name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
				echoRgb "跳過恢復$name1 所有數據" "0"
				No_backupdata=1
			fi
			Backup_folder="$MODDIR/$name1"
			Backup_folder2="$MODDIR/Media"
			[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
			if [[ -d $Backup_folder ]]; then
				echoRgb "恢複$name1 ($name2)"
				starttime2="$(date -u "+%s")"
				if [[ $name3 != system ]]; then
					if [[ $(pm path "$name2") = "" ]]; then
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
								pm install -i com.android.vending --user 0 -r "$TMPDIR"/*.apk >/dev/null 2>&1
								echo_log "Apk安裝"
								;;
							0)
								echoRgb "$TMPDIR中沒有apk" "0"
								;;
							*)
								echoRgb "恢復split apk" "2"
								b="$(pm install-create -i -i com.android.vending --user 0 | grep -E -o '[0-9]+')"
								if [[ -f $TMPDIR/nmsl.apk ]]; then
									pm install -i com.android.vending --user 0 -r "$TMPDIR/nmsl.apk" >/dev/null 2>&1
									echo_log "nmsl.apk安裝"
								fi
								find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f | grep -v 'nmsl.apk' | while read; do
									pm install-write "$b" "${REPLY##*/}" "$REPLY" >/dev/null 2>&1
									echo_log "${REPLY##*/}安裝"
								done
								pm install-commit "$b" >/dev/null 2>&1
								echo_log "split Apk安裝"
								;;
							esac
						fi
					else
						echoRgb "存在當前系統中略過安裝Apk" "2"
					fi
				else
					echoRgb "$name2是系統應用" "3"
				fi
				if [[ $No_backupdata = "" ]]; then
					if [[ $(pm path "$name2") != "" ]]; then
						#停止應用
						[[ $name2 != $Open_apps2 ]] && am force-stop "$name2"
						find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f | sort | while read; do
							Release_data "$REPLY"
						done
					else
						echoRgb "$name1沒有安裝無法恢復數據" "0"
					fi
				fi
				endtime 2 "$name1恢複" "2" && echoRgb "完成$((i * 100 / r))%" "3" && echoRgb "____________________________________"
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
					B="$(find "$Backup_folder2" -maxdepth 1 -name "*.tar*" -type f | wc -l)"
					if [[ $branch = true ]]; then
						find "$Backup_folder2" -maxdepth 1 -name "*.tar*" -type f | while read; do
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
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
		isBoolean "$toast_info" "toast_info" && toast_info="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
		echoRgb "備份完成或是遭遇異常發送toast與狀態欄通知？\n -音量上提示，音量下靜默備份" "2"
		get_version "提示" "靜默備份" && toast_info="$branch"
	fi
	update_script
	#禁用apk驗證
	settings put global verifier_verify_adb_installs 0
	#禁用安裝包驗證
	settings put global package_verifier_enable 0
	#關閉play安全效驗
	if [[ $(settings get global package_verifier_user_consent) != "" && $(settings get global package_verifier_user_consent) != -1 ]]; then
		settings put global package_verifier_user_consent -1
		settings put global upload_apk_enable 0
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	[[ $(which restorecon) = "" ]] && echoRgb "restorecon命令不存在" "0" && exit 1
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	{
		Backup_folder="$MODDIR"
		if [[ ! -f $Backup_folder/app_details ]]; then
			echoRgb "$Backup_folder/app_details遺失，無法獲取包名" "0" && exit 1
		else
			. "$Backup_folder/app_details"
		fi
		name="$PackageName"
		[[ $name = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
		name2="$ChineseName"
		[[ $name2 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
		name3="$type"
		[[ $name3 = "" ]] && echoRgb "應用類型獲取失敗" "0" && exit 2
		echoRgb "恢複$name2 ($name)" "3"
		starttime2="$(date -u "+%s")"
		if [[ $name3 != "" ]]; then
			if [[ $(pm path "$name") = "" ]]; then
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
						pm install -i com.android.vending --user 0 -r "$TMPDIR"/*.apk >/dev/null 2>&1
						echo_log "Apk安裝"
						;;
					0)
						echoRgb "$TMPDIR中沒有apk" "0"
						;;
					*)
						echoRgb "恢復split apk" "2"
						b="$(pm install-create -i com.android.vending --user 0 | egrep -o '[0-9]+')"
						if [[ -f $TMPDIR/nmsl.apk ]]; then
							pm install --user 0 -r "$TMPDIR/nmsl.apk" >/dev/null 2>&1
							echo_log "nmsl.apk安裝"
						fi
						find "$TMPDIR" -maxdepth 1 -name "*.apk" -type f | grep -v 'nmsl.apk' | while read; do
							pm install-write "$b" "${REPLY##*/}" "$REPLY" >/dev/null 2>&1
							echo_log "${REPLY##*/}安裝"
						done
						pm install-commit "$b" >/dev/null 2>&1
						echo_log "split Apk安裝"
						;;
					esac
				fi
			else
				echoRgb "存在當前系統中略過安裝Apk" "2"
			fi
		else
			echoRgb "$name2是系統應用" "3"
		fi
		if [[ $(pm path "$name") != "" ]]; then
			#停止應用
			[[ $name != $Open_apps2 ]] && am force-stop "$name"
			find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f | sort | while read; do
				tar_path="$REPLY"
				X="$path2/$name"
				FILE_NAME="${tar_path##*/}"
				FILE_NAME2="${FILE_NAME%%.*}"
				echoRgb "恢復$FILE_NAME2數據" "3"
				if [[ $FILE_NAME2 = user ]]; then
					if [[ -d $X ]]; then
						case ${FILE_NAME##*.} in
						lz4 | zst) pv "$tar_path" | tar --recursive-unlink -I zstd -xmpf - -C "$path2" ;;
						tar) pv "$tar_path" | tar --recursive-unlink -xmpf - -C "$path2" ;;
						*)
							echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
							Set_back
							;;
						esac
					else
						echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
						Set_back
					fi
				else
					[[ $FILE_NAME2 = thanox ]] && rm -rf "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d)"
					case ${FILE_NAME##*.} in
					lz4 | zst) pv "$tar_path" | tar --recursive-unlink -I zstd -xmPpf - ;;
					tar) pv "$tar_path" | tar --recursive-unlink -xmPpf - ;;
					*)
						echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
						Set_back
						;;
					esac
				fi
				echo_log "$FILE_NAME 解壓縮($FILE_NAME2)"
				if [[ $result = 0 ]]; then
					case $FILE_NAME2 in
					user)
						if [[ -d $X ]]; then
							if [[ -f /config/sdcardfs/$name/appid ]]; then
								G="$(cat "/config/sdcardfs/$name/appid")"
							else
								G="$(dumpsys package "$name" | awk '/userId=/{print $1}' | cut -f2 -d '=' | head -1)"
							fi
							G="$(echo "$G" | egrep -o '[0-9]+')"
							if [[ $G != "" ]]; then
								echoRgb "路徑:$X"
								Path_details="$(stat -c "%A/%a %U/%G" "$X")"
								chown -hR "$G:$G" "$X/"
								echo_log "設置用戶組:$(echo "$Path_details" | awk '{print $2}')"
								restorecon -RF "$X/" >/dev/null 2>&1
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
						restorecon -RF "$(find "/data/system" -name "thanos*" -maxdepth 1 -type d)/" >/dev/null 2>&1
						echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
						;;
					esac
				fi
			done
		else
			echoRgb "$name2沒有安裝無法恢復數據" "0"
		fi
		endtime 1 "恢複開始到結束" && echoRgb "如發現應用閃退請重新開機" && rm -rf "$TMPDIR"/*
		rm -rf "$TMPDIR/scriptTMP"
	} &
	wait && exit
	;;
Restore3)
	echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了\n -音量上繼續恢復自定義資料夾，音量下離開腳本" "2"
	get_version "恢復自定義資料夾" "離開腳本" && [[ "$branch" = false ]] && exit 0
	mediaDir="$MODDIR/Media"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行\"DumpName.sh\"獲取媒體列表再來恢復" "0" && exit 2
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
		isBoolean "$toast_info" "toast_info" && toast_info="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
		echoRgb "備份完成或是遭遇異常發送toast與狀態欄通知？\n -音量上提示，音量下靜默備份" "2"
		get_version "提示" "靜默備份" && toast_info="$branch"
	fi
	update_script
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	echo_log() {
		if [[ $? = 0 ]]; then
			echoRgb "$1成功" "1" && result=0
		else
			echoRgb "$1恢複失敗，過世了" "0" && result=1
		fi
	}
	Release_data() {
		tar_path="$1"
		if [[ -f $tar_path ]]; then
			FILE_NAME="${tar_path##*/}"
			FILE_NAME2="${FILE_NAME%%.*}"
			echoRgb "恢復$FILE_NAME2數據" "3"
			if [[ ${FILE_NAME##*.} = tar ]]; then
				pv "$1" | tar -xPpf -
			else
				echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
				Set_back
			fi
			echo_log "$FILE_NAME 解壓縮($FILE_NAME2)"
			app_details="$mediaDir/app_details"
			[[ $result = 0 ]] && [[ -f $app_details ]] && echoRgb "解壓路徑↓\n -$(cat "$app_details" | awk "/${FILE_NAME2}path/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')" "2"
		else
			echoRgb "$tar_path壓縮包不存在" "0"
		fi
	}
	starttime1="$(date -u "+%s")"
	A=1
	B="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行\"DumpName.sh\"獲取列表再來恢復" "0" && exit 1
	while [[ $A -le $B ]]; do
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
	#白名單
	whitelist="com.xiaomi.xmsf
com.xiaomi.xiaoailite
com.duokan.phone.remotecontroller
com.miui.weather2
com.milink.service
com.android.soundrecorder
com.miui.virtualsim
com.xiaomi.vipaccount
com.miui.fm
com.xiaomi.shop
com.xiaomi.smarthome
com.miui.notes
com.mi.health
com.xiaomi.router
com.xiaomi.mico
dev.miuiicons.pedroz"
	system="
com.google.android.apps.messaging
com.google.android.inputmethod.latin
com.android.chrome"
	# 获取默认桌面
	launcher_app="$(pm resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | grep '/' | cut -f1 -d '/')"
	for launcher_app in $launcher_app; do
		[[ $launcher_app != "android" ]] && [[ $(pgrep -f "$launcher_app" | grep -v 'grep' | wc -l) -ge 1 ]] && launcher_app="$launcher_app"
	done
	txtpath="$MODDIR"
	#txtpath="${txtpath/'/storage/emulated/'/'/data/media/'}"
	nametxt="$txtpath/appList.txt"
	[[ ! -e $nametxt ]] && echo '#不需要備份的應用請在開頭注釋# 比如#酷安 xxxxxxxx\n#不需要備份數據比如酷安! xxxxxxxx應用名後方加一個驚嘆號即可 注意是應用名不是包名' >"$nametxt"
	echo >>"$nametxt"
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
		isBoolean "$system_name" "system_name" && system_name="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
		echoRgb "列出系統應用？\n -音量上列出，音量下不列出" "2"
		get_version "列出" "不列出" && system_name="$branch"
	fi
	update_script
	echoRgb "請勿關閉腳本，等待提示結束"
	bn=118
	rm -rf "$MODDIR/tmp"
	starttime1="$(date -u "+%s")"
	echoRgb "提示!因為系統自帶app(位於data分區或是可卸載預裝應用)備份恢復可能存在問題\n -所以不會輸出..但是檢測為Xposed類型包名將輸出\n -如果提示不是Xposed但他就是Xposed可能為此應用元數據不符合規範導致" "0"
	xposed_name="$(appinfo -o pn -xm)"
	Apk_info="$(appinfo -sort-i -d " " -o ands,pn -pn $system $launcher_app -3 2>/dev/null | egrep -v 'ice.message|com.topjohnwu.magisk' | sort -u)"
	Apk_Quantity="$(echo "$Apk_info" | wc -l)"
	LR="1"
	if [[ $system_name = true ]]; then
		echoRgb "第三方+系統應用\n -列出系統應用....." "2"
		echoRgb "警告!系統應用將不備份apk僅備份數據\n -請勿跨系統恢復防止出現問題，原生系統則不受此限制\n -另外腳本會自動檢測系統應用是否存在，否則不進行數據恢復" "0"
		nametxt2="$txtpath/systemList.txt"
		Apk_info2="$(appinfo -sort-i -d " " -o ands,pn -s 2>/dev/null | egrep -v "$(echo $system | sed 's/ /\|/g')")"
		Apk_Quantity2="$(echo "$Apk_info2" | wc -l)"
		i="0"
		Q="0"
		echo "$Apk_info2" | sed 's/\///g ; s/\://g ; s/(//g ; s/)//g ; s/\[//g ; s/\]//g ; s/\-//g ; s/!//g' | while read; do
			[[ $bn -ge 229 ]] && bn=118
			app_1=($REPLY $REPLY)
			if [[ $(cat "$nametxt2" 2>/dev/null | cut -f2 -d ' ' | egrep "^${app_1[1]}$") != ${app_1[1]} ]]; then
				echo "$REPLY system" >>"$nametxt2" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
				echoRgb "$REPLY($bn)"
				let i++
			else
				let Q++
			fi
			[[ $LR = $Apk_Quantity2 ]] && [[ -e $MODDIR/tmp ]] && echoRgb "\n -系統apk數量=\"$Apk_Quantity2\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\"" && LR="1"
			let bn++ LR++
		done
	else
		echoRgb "僅第三方" "2" && rm -rf "$txtpath/systemList.txt"
	fi
	echoRgb "列出第三方應用......." "2"
	i="0"
	rc="0"
	rd="0"
	Q="0"
	echo "$Apk_info" | sed 's/\///g ; s/\://g ; s/(//g ; s/)//g ; s/\[//g ; s/\]//g ; s/\-//g ; s/!//g' | while read; do
		[[ $bn -ge 229 ]] && bn=118
		app_1=($REPLY $REPLY)
		if [[ $(cat "$nametxt" | cut -f2 -d ' ' | egrep "^${app_1[1]}$") != ${app_1[1]} ]]; then
			case ${app_1[1]} in
			*oneplus* | *miui* | *xiaomi* | *oppo* | *flyme* | *meizu* | com.android.soundrecorder | com.mfashiongallery.emag | com.mi.health | *coloros*)
				if [[ $(echo "$xposed_name" | grep -w "${app_1[1]}") = ${app_1[1]} ]]; then
					echoRgb "${app_1[2]}為Xposed模塊 進行添加" "0"
					echo "$REPLY user" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
					let i++ rd++
				else
					if [[ $(echo "$whitelist" | egrep -w "^${app_1[1]}$") = ${app_1[1]} ]]; then
						echo "$REPLY user" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
						echoRgb "$REPLY($bn)"
						let i++
					else
						echoRgb "${app_1[2]}非Xposed模塊 忽略輸出" "0"
						let rc++
					fi
				fi
				;;
			*)
				echo "$REPLY user" >>"$nametxt" && [[ ! -e $MODDIR/tmp ]] && touch "$MODDIR/tmp"
				echoRgb "$REPLY($bn)"
				let i++
				;;
			esac
		else
			let Q++
		fi
		if [[ $LR = $Apk_Quantity ]]; then
			[[ -e $MODDIR/tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -存在列表中=\"$Q\"\n -輸出=\"$i\""
		fi
		let bn++ LR++
	done
	if [[ -f $nametxt ]]; then
		cat "$nametxt" | grep -v "#" | while read; do
			name=($REPLY $REPLY)
			{
				if [[ $REPLY != "" && $(pm path "${name[1]}" | cut -f2 -d ':') = "" ]]; then
					echoRgb "${name[2]}不存在系統，從列表中刪除"
					echo "$(sed -e "s/$REPLY//g ; /^$/d" "$nametxt")" >"$nametxt"
				fi
			} &
		done
		echo "$(sort "$nametxt" | sed -e '/^$/d')" >"$nametxt"
	fi
	wait
	endtime 1
	[[ ! -e $MODDIR/tmp ]] && echoRgb "無新增應用" || echoRgb "輸出包名結束 請查看$nametxt"
	rm -rf "$MODDIR/tmp"
	;;
backup_media)
	{
		script="${0##*/}"
		if [[ $script != "" ]]; then
			pgrep -f "tar" | while read; do
				kill -KILL " $REPLY" >/dev/null
			done
		fi
	} &
	PU="$(ls /dev/block/vold | grep public)"
	#效驗選填是否正確
	isBoolean "$Lo" "LO" && Lo="$nsx"
	if [[ $Lo = false ]]; then
		isBoolean "$update" "update" && update="$nsx"
	else
		echoRgb "如果檢測到更新後跳轉瀏覽器下載?\n -音量上跳轉，下不跳轉"
		get_version "跳轉" "不跳轉" && update="$branch"
	fi
	update_script
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		Backup="$Output_path/Backup_$Compression_method"
		outshow="使用自定義目錄"
	else
		if [[ $APP_ENV = 1 ]]; then
			Backup="/storage/emulated/0/Backup_$Compression_method"
			outshow="沒有設定備份目錄 使用默認路徑"
		else
			Backup="$MODDIR/Backup_$Compression_method"
			outshow="使用當前路徑作為備份目錄"
		fi
	fi
	if [[ $PU != "" ]]; then
		[[ -f /proc/mounts ]] && PT="$(cat /proc/mounts | grep "$PU" | awk '{print $2}')"
		if [[ -d $PT ]]; then
			if [[ $(echo "$MODDIR" | grep -oE "^${PT}") != "" || $USBdefault = true ]]; then
				hx="USB"
			else
				echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是" "2"
				get_version "選擇了隨身碟備份" "選擇了本地備份"
				[[ $branch = true ]] && hx="USB"
			fi
			if [[ $hx = USB ]]; then
				Backup="$PT/Backup_$Compression_method"
				data="/dev/block/vold/$PU"
				mountinfo="$(df -T "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')"
				case $mountinfo in
				vfat | fuseblk | exfat | NTFS | ext4 | f2fs)
					outshow="於隨身碟備份"
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
	rm -rf "$Backup/STOP"
	#分區詳細
	if [[ $(echo "$Backup" | egrep -o "^/storage/emulated") != "" ]]; then
		Backup_path="/data"
	else
		Backup_path="${Backup%/*}"
	fi
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | sed 's/G//g' | awk 'END{print "總共:"$1"G已用:"$2"G剩餘:"$3"G使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
	#分區佔用信息
	partition_info() {
		Occupation_status="$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
		lxj="$(echo "$Occupation_status" | awk '{print $2}' | sed 's/%//g')"
	}
	Backup_data() {
		unset zsize
		[[ -f $app_details ]] && Size="$(cat "$app_details" | awk "/$1Size/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')"
		data_path="$2"
		if [[ -d $data_path ]]; then
			if [[ $Size != $(du -ks "$data_path" | awk '{print $1}') ]]; then
				partition_info
				[[ $lxj -ge 95 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
				echoRgb "備份$1數據"
				tar --exclude="Backup_"* --exclude="${data_path##*/}/cache" -cPpf - "$data_path" 2>/dev/null | pv >"$Backup_folder/$1.tar"
				echo_log "備份$1數據"
				if [[ $result = 0 ]]; then
					echo "#$1Size=\"$(du -ks "$data_path" | awk '{print $1}')\"" >>"$app_details"
					[[ $2 != $(cat "$app_details" | awk "/$1path/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g') ]] && echo "#$1path=\"$2\"" >>"$app_details"
				fi
			else
				echoRgb "$1數據無發生變化 跳過備份" "2"
			fi
		else
			if [[ -f $data_path ]]; then
				echoRgb "$1是一個文件 不支持備份" "0"
			else
				echoRgb "$1數據不存在跳過備份" "2"
			fi
		fi
		partition_info
	}
	A=1
	B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
		[[ ! -f $Backup/Restoremedia.sh ]] && cp -r "$script_path/restore3" "$Backup/Restoremedia.sh"
		[[ ! -f $Backup/DumpName.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/DumpName.sh"
		[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup" && rm -rf "$Backup/tools/bin/zip" "$Backup/tools/script"
		[[ ! -f $Backup/backup_settings.conf ]] && echo "#1開啟0關閉\n\n#是否在每次執行恢復腳本時使用音量鍵詢問如下需求\n#如果是那下面兩項項設置就被忽略，改為音量鍵選擇\nLo=$Lo\n\n#備份與恢復遭遇異常或是結束後發送通知(toast與狀態欄提示)\ntoast_info=$toast_info\n\n#腳本檢測更新後進行跳轉瀏覽器或是複製連結?\nupdate=$update\n\n#檢測到更新後的行為(1跳轉瀏覽器 0不跳轉瀏覽器，但是複製連結到剪裁版)\nupdate_behavior=$update_behavior">"$Backup/backup_settings.conf" && echo "$(sed 's/true/1/g ; s/false/0/g' "$Backup/backup_settings.conf")">"$Backup/backup_settings.conf"
		app_details="$Backup_folder/app_details"
		[[ -f $app_details ]] && . "$app_details"
		mediatxt="$Backup/mediaList.txt"
		[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭注釋# 比如#媒體" > "$mediatxt"
		echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | while read; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")" 
			[[ ${REPLY: -1} = / ]] && REPLY="${REPLY%?}"
			Backup_data "${REPLY##*/}" "$REPLY"
			[[ $result = 0 ]] && [[ $(cat "$mediatxt" | grep -v "#" | sed -e '/^$/d' | grep -w "^${REPLY##*/}.tar$" | head -1) = "" ]] && echo "${REPLY##*/}.tar" >> "$mediatxt"
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$((A * 100 / B))% $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')" "2" && echoRgb "____________________________________" && let A++
		done
		echoRgb "目錄↓↓↓\n -$Backup_folder"
		endtime 1 "自定義備份"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	;;
esac
