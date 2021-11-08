#!/system/bin/sh
MODDIR="${0%/*}"
tools_path="$MODDIR/tools"
bin_path="$tools_path/bin"
script_path="$tools_path/script"
script="${0##*/}"
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ ! -d $tools_path ]] && echo "$tools_path目錄遺失" && exit 1
[[ ! -d $script_path ]] && echo "$script_path目錄遺失" && exit 1
[[ ! -d $tools_path/apk ]] && echo "$tools_path/apk目錄遺失" && exit 1
. "$bin_path/bin.sh"
. "$MODDIR/backup_settings.conf"
case $MODDIR in
/storage/emulated/0/Android/*|/data/media/0/Android/*|/sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
esac
case $Compression_method in
zstd|Zstd|ZSTD|tar|Tar|TAR|lz4|Lz4|LZ4) ;;
*) echoRgb "$Compression_method為不支持的壓縮算法" "0" &&  exit 2 ;;
esac
[[ ! -f $MODDIR/backup_settings.conf ]] && echoRgb "backup_settings.conf遺失" "0" && exit 1
if [[ $(pgrep -f "$script" | grep -v grep | wc -l) -ge 2 ]]; then
	echoRgb "檢測到進程殘留，請重新執行腳本 已銷毀進程" "0"
	pgrep -f "$script" | grep -v grep | while read i; do
		[[ $i != "" ]] && kill -9 " $i" >/dev/null
	done
fi
#效驗選填是否正確
isBoolean "$Lo" && Lo="$nsx"
if [[ $Lo = false ]]; then
	isBoolean "$Splist" && Splist="$nsx"
	isBoolean "$USBdefault" && USBdefault="$nsx"
	isBoolean "$Backup_obb_data" && Backup_obb_data="$nsx"
	isBoolean "$path" && path3="$nsx"
	isBoolean "$Backup_user_data" && Backup_user_data="$nsx"
	isBoolean "$backup_media" && backup_media="$nsx"
else
	echoRgb "備份路徑位置為絕對位置或是當前環境位置\n 音量上當前環境位置，音量下腳本絕對位置"
	get_version "當前環境位置" "腳本絕對位置" && path3="$branch"
fi
i=1
#數據目錄
path="/data/media/0/Android"
path2="/data/user/0"
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
if [[ $path3 = true ]]; then
	Backup="$PWD/Backup_$Compression_method"
	txt="$PWD/應用列表.txt"
else
	Backup="$MODDIR/Backup_$Compression_method"
	txt="$MODDIR/應用列表.txt"
fi
PU="$(ls /dev/block/vold | grep public)"
[[ ! -f $txt ]] && echoRgb "請執行\"生成應用列表.sh\"獲取應用列表再來備份" "0" && exit 1
r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
[[ $r = "" ]] && echoRgb "爬..應用列表.txt是空的或是包名被注釋了這樣備份個鬼" "0" && exit 1
data=/data
hx="本地"
echoRgb "壓縮方式:$Compression_method"
echoRgb "提示 腳本支持後台壓縮 可以直接離開腳本\n -或是關閉終端也能備份 如需終止腳本\n -請再次執行$script即可停止\n -備份結束將發送toast提示語" "2"
if [[ $PU != "" ]]; then
	[[ -f /proc/mounts ]] && PT="$(cat /proc/mounts | grep "$PU" | awk '{print $2}')"
	if [[ -d $PT ]]; then
		if [[ $(echo "$MODDIR" | grep -oE "^${PT}") != "" || $USBdefault = true ]]; then
			echoRgb "於隨身碟備份" "1"
			Backup="$PT/Backup_$Compression_method"
			data="/dev/block/vold/$PU"
			hx="USB"
		else
			echoRgb "檢測到隨身碟 是否在隨身碟備份\n -音量上是，音量下不是"
			get_version "選擇了隨身碟備份" "選擇了本地備份"
			if $branch = true ]]; then
				Backup="$PT/Backup_$Compression_method"
				data="/dev/block/vold/$PU"
				hx="USB"
			fi
		fi
	fi
else
	echoRgb "沒有檢測到隨身碟於本地備份" "1"
fi
[[ $Backup_user_data = false ]] && echoRgb "當前backup_settings.conf的\n -Backup_user_data為0將不備份user數據" "0"
[[ $Backup_obb_data = false ]] && echoRgb "當前backup_settings.conf的\n -Backup_obb_data為0將不備份外部數據" "0"
[[ ! -d $Backup ]] && mkdir -p "$Backup"
[[ ! -f $Backup/應用列表.txt ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$Backup/應用列表.txt"
[[ ! -f $Backup/本地一鍵更新腳本.sh ]] && cp -r "$MODDIR/本地一鍵更新腳本.sh" "$Backup"
[[ ! -f $Backup/recover.conf ]] && cp -r "$script_path/recover.conf" "$Backup"
[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup" && rm -rf "$Backup/tools/META-INF" "$Backup/tools/script"
[[ ! -f $Backup/還原備份.sh ]] && cp -r "$script_path/restore" "$Backup/還原備份.sh"
[[ ! -f $Backup/掃描資料夾名.sh ]] && cp -r "$script_path/Get_DirName" "$Backup/掃描資料夾名.sh"
filesize="$(du -ks "$Backup" | awk '{print $1}')"
#調用二進制
Quantity=0
#檢測apk狀態進行備份
Backup_apk() {
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ $(cat "$Backup/應用列表.txt" | grep -v "#" | sed -e '/^$/d' | awk '{print $2}' | grep -w "^${name2}$" | head -1) = "" ]] && echo "${Backup_folder##*/} $name2" >>"$Backup/應用列表.txt"
	if [[ $apk_version = $(dumpsys package "$name2" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1) ]]; then
		unset xb ; result=0
		echoRgb "Apk版本無更新 跳過備份"
	else
		[[ $lxj -ge 95 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
		rm -rf "$Backup_folder"/*.apk
		#備份apk
		echoRgb "$1"
		[[ $name1 != $Open_apps ]] && am force-stop "$name2"
		echo "$apk_path" | sed -e '/^$/d' | while read; do
			path="$REPLY"
			b_size="$(ls -l "$path" | awk '{print $5}')"
			k_size="$(awk 'BEGIN{printf "%.2f\n", "'$b_size'"/'1024'}')"
			m_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')"
			echoRgb "${path##*/} ${m_size}MB(${k_size}KB)" "2"
		done
		(cd "$apk_path2"
		case $Compression_method in
		tar|TAR|Tar) tar -cf "$Backup_folder/apk.tar" *.apk ;;
		lz4|LZ4|Lz4) tar -cf - *.apk | lz4 -1 >"$Backup_folder/apk.tar.lz4" ;;
		zstd|Zstd|ZSTD) tar -cf - *apk | zstd -r -T0 -6 -q >"$Backup_folder/apk.tar.zst" ;;
		esac)
		echo_log "備份$apk_number個Apk"
		if [[ $result = 0 ]]; then
			echo "apk_version=\"$(dumpsys package "$name2" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1)\"" >>"$app_details"
			[[ $PackageName = "" ]] && echo "PackageName=\"$name2\"" >>"$app_details"
			[[ $ChineseName = "" ]] && echo "ChineseName=\"$name1\"" >>"$app_details"
			[[ ! -f $Backup_folder/還原備份.sh ]] && cp -r "$script_path/restore2" "$Backup_folder/還原備份.sh"
			[[ ! -f $Backup_folder/recover.conf ]] && cp -r "$script_path/recover.conf" "$Backup_folder"
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
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
	unset ChineseName PackageName ; D=1
}
#檢測數據位置進行備份
Backup_data() {
	unset zsize
	case $1 in
	user) Size="$userSize" && data_path="$path2/$name2" ;;
	data) Size="$dataSize" && data_path="$path/$1/$name2" ;;
	obb) Size="$obbSize" && data_path="$path/$1/$name2" ;;
	*) [[ -f $app_details ]] && Size="$(cat "$app_details" | awk "/$1Size/"'{print $1}' | cut -f2 -d '=' | tail -n1 | sed 's/\"//g')" ; data_path="$2" ; Compression_method1="$Compression_method" ; Compression_method=tar ; zsize=1
	esac
	if [[ -d $data_path ]]; then
		if [[ $Size != $(du -ks "$data_path" | awk '{print $1}') ]]; then
			[[ $name1 != $Open_apps ]] && am force-stop "$name2"
			[[ $lxj -ge 95 ]] && echoRgb "$hx空間不足,達到$lxj%" "0" && exit 2
			echoRgb "備份$1數據" "2"
			case $1 in
			user)
				case $Compression_method in
				tar|Tar|TAR) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd|Zstd|ZSTD) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | zstd -r -T0 -6 -q >"$Backup_folder/$1.tar.zst" ;;
				lz4|Lz4|LZ4) tar --exclude="${data_path##*/}/.ota" --exclude="${data_path##*/}/cache" --exclude="${data_path##*/}/lib" -cpf - -C "${data_path%/*}" "${data_path##*/}" 2>/dev/null | pv | lz4 -1 >"$Backup_folder/$1.tar.lz4" ;;
				esac ;;
			*)
				case $Compression_method in
				tar|Tar|TAR) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd|Zstd|ZSTD) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv | zstd -r -T0 -6 -q >"$Backup_folder/$1.tar.zst" ;;
				lz4|Lz4|LZ4) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv | lz4 -1 >"$Backup_folder/$1.tar.lz4" ;;
				esac ; [[ $Compression_method1 != "" ]] && Compression_method="$Compression_method1" ; unset Compression_method1 ;;
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
			echoRgb "$1數據無發生變化 跳過備份"
		fi
	else
		echoRgb "$1數據不存在跳過備份"
	fi
}
[[ $Lo = true ]] && {
echoRgb "選擇是否只備份split apk(分割apk檔)\n 如果你不知道這意味什麼請選擇音量下進行混合備份\n 音量上是，音量下不是"
get_version "是" "不是，混合備份" && Splist="$branch"
echoRgb "是否備份外部數據 即比如原神的數據包\n 音量上備份，音量下不備份"
get_version "備份" "不備份" && Backup_obb_data="$branch"
echoRgb "是否備份使用者數據\n 音量上備份，音量下不備份"
get_version "備份" "不備份" && Backup_user_data="$branch"
echoRgb "全部應用備份結束後是否備份自定義目錄\n 音量上備份，音量下不備份"
get_version "備份" "不備份" && backup_media="$branch"
}
#開始循環$txt內的資料進行備份
#記錄開始時間
starttime1="$(date -u "+%s")"
TIME="$starttime1"
en=118
{
while [[ $i -le $r ]]; do
	[[ $en -ge 229 ]] && en=118
	name1="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
	name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
	[[ $name2 = "" ]] && echoRgb "警告! 應用列表.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
	apk_path="$(pm path "$name2" | cut -f2 -d ':')"
	apk_path2="$(echo "$apk_path" | head -1)" ; apk_path2="${apk_path2%/*}"
	if [[ -d $apk_path2 ]]; then
		echoRgb "備份第$i/$r個應用 剩下$((r-i))個"
		if [[ $name1 = *! || $name1 = *！ ]]; then
			name1="$(echo "$name1" | sed 's/!//g ; s/！//g')"
			echoRgb "跳過備份$name1 所有數據" "0"
			No_backupdata=1
		else
			[[ $No_backupdata != "" ]] && unset No_backupdata
		fi
		Backup_folder="$Backup/$name1"
		app_details="$Backup_folder/app_details"
		if [[ -f $app_details ]]; then
			. "$app_details"
			if [[ $PackageName != $name2 ]]; then
				unset userSize ChineseName PackageName apk_version
				Backup_folder="$Backup/${name1}[${name2}]"
				app_details="$Backup_folder/app_details"
				[[ -f $app_details ]] && . "$app_details"
			fi
		fi
		lxj="$(df -h "$data" | awk 'END{print $4}' | sed 's/%//g')"
		starttime2="$(date -u "+%s")"
		echoRgb "備份$name1 ($name2)"
		[[ $name2 = com.tencent.mobileqq ]] && echo "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份"
		[[ $name2 = com.tencent.mm ]] && echo "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份"
		apk_number="$(echo "$apk_path" | wc -l)"
		if [[ $apk_number = 1 ]]; then
			if [[ $Splist = false ]]; then
				Backup_apk "非Split Apk"
			else
				echoRgb "非Split Apk跳過備份" && unset D
			fi
		else
			Backup_apk "Split Apk支持備份"
		fi
		if [[ $D != ""  && $result = 0 && $No_backupdata = "" ]]; then
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
		endtime 2 "$name1備份"
		echoRgb "完成$((i*100/r))% $hx$(df -h "$data" | awk 'END{print "剩餘:"$3"使用率:"$4}')"
		echoRgb "____________________________________" "3"
	else
		echoRgb "$name1[$name2]不在安裝列表，備份個寂寞？" "0"
	fi
	if [[ $i = $r ]]; then
		endtime 1 "應用備份"
		if [[ $backup_media = true ]]; then
			A=1
			B="$(echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
			if [[ $B != "" ]]; then
				echoRgb "備份結束，備份多媒體"
				starttime1="$(date -u "+%s")"
				Backup_folder="$Backup/媒體"
				[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
				[[ ! -f $Backup_folder/恢復多媒體數據.sh ]] && cp -r "$script_path/restore3" "$Backup_folder/恢復多媒體數據.sh"
				app_details="$Backup_folder/app_details"
				[[ -f $app_details ]] && . "$app_details"
				echo "$Custom_path" | grep -v "#" | sed -e '/^$/d' | while read; do
					echoRgb "備份第$A/$B個資料夾 剩下$((B-A))個"
					starttime2="$(date -u "+%s")"
					Backup_data "${REPLY##*/}" "$REPLY"
					endtime 2 "${REPLY##*/}備份" && echoRgb "完成$((A*100/B))% $hx$(df -h "$data" | awk 'END{print "剩餘:"$3"使用率:"$4}')" && echoRgb "____________________________________" "3" && let A++
				done
				endtime 1 "自定義備份"
			else
				echoRgb "自定義路徑為空 無法備份" "0"
			fi
		fi
	fi
	let i++ en++ nskg++
done
echoRgb "你要備份跑路？祝你卡米9008" "2"
#計算出備份大小跟差異性
filesizee="$(du -ks "$Backup" | awk '{print $1}')"
dsize="$(($((filesizee - filesize)) / 1024))"
echoRgb "備份資料夾路徑:$Backup" "2"
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
}&