#!/system/bin/sh
MODDIR="${0%/*}"
script="${0##*/}"
[[ $(echo "$MODDIR" | grep -v 'mt') = "" ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ $MODDIR = /data/media/0/Android/* ]] && echo "請勿在$MODDIR內備份" && exit 2
[[ ! -d $MODDIR/tools ]] && echo "$MODDIR/tools目錄遺失" && exit 1
[[ ! -f $MODDIR/backup_settings.conf ]] && echo "backup_settings.conf遺失" && exit 1
tools_path="$MODDIR/tools"
. "$tools_path/bin.sh"
. "$MODDIR/backup_settings.conf"
if [[ $(pgrep -f "$script" | grep -v grep | wc -l) -ge 2 ]]; then
	echoRgb "檢測到進程殘留，請重新執行腳本 已銷毀進程" "0" "0"
	pgrep -f "$script" | grep -v grep | while read i; do
		[[ $i != "" ]] && kill -9 " $i" >/dev/null
	done
fi
isBoolean "$Lo" && Lo="$nsx"
if [[ $Lo = false ]]; then
	isBoolean "$Splist" && Splist="$nsx"
	isBoolean "$Backup_obb_data" && Backup_obb_data="$nsx"
	isBoolean "$path" && path3="$nsx"
	isBoolean "$Backup_user_data" && Backup_user_data="$nsx"
	isBoolean "$backup_media" && backup_media="$nsx"
else
	echoRgb "備份路徑位置為絕對位置或是當前環境位置
 音量上當前環境位置，音量下腳本絕對位置"
	get_version "當前環境位置" "腳本絕對位置" && path3="$branch"
fi
i=1
path="/data/media/0/Android"
path2="/data/data"
if [[ $path3 = true ]]; then
	Backup="$PWD/Backup_$Compression_method"
	txt="$PWD/Apkname.txt"
else
	Backup="$MODDIR/Backup_$Compression_method"
	txt="$MODDIR/Apkname.txt"
fi
PU="$(ls /dev/block/vold | grep public 2>/dev/null)"
[[ ! -e $txt ]] && echoRgb "請執行appname.sh獲取軟件列表再來備份" "0" "0" && exit 1
r="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')"
[[ $r = "" ]] && echoRgb "爬..Apkname.txt是空的或是包名被注釋了這樣備份個鬼" "0" "0" && exit 1
data=/data
hx="本地"
if [[ $(pm path y.u.k) = "" ]]; then
	echoRgb "未安裝toast 開始安裝" "0" "0"
	if [[ $(getenforce) != Permissive ]]; then
		cp -r "$MODDIR/tools/apk"/*.apk /data/local/tmp && pm install -r /data/local/tmp/*.apk >/dev/null 2>&1 && rm -rf /data/local/tmp/* 
		[[ $? = 0 ]] && echoRgb "安裝toast成功" "0" "1" || echoRgb "安裝toast失敗" "0" "0"
	fi
fi
echoRgb "-壓縮方式:$Compression_method"
echoRgb "-提示 腳本支持後台壓縮 可以直接離開腳本
 -或是關閉終端也能備份 如需終止腳本
 -請再次執行$script即可停止
 -備份結束將發送toast提示語" "0" "2"
if [[ -d /proc/scsi/usb-storage || $PU != "" ]]; then
	PT="$(cat /proc/mounts | grep "$PU" | awk '{print $2}')"
	echoRgb "檢測到usb 是否在usb備份
 音量上是，音量下不是"
	get_version "USB備份" "本地備份"
	if $branch = true ]]; then
		Backup="$PT/Backup_$Compression_method"
		data="/dev/block/vold/$PU"
		hx="USB"
	fi
else
	echoRgb "沒有檢測到USB於本地備份"
fi
[[ $Backup_user_data = false ]] && echoRgb "警告當前backup_settings.conf的Backup_user_data為0將不備份user數據" "0" "0"
[[ $Backup_obb_data = false ]] && echoRgb "警告當前backup_settings.conf的Backup_obb_data為0將不備份外部數據" "0" "0"
[[ ! -d $Backup ]] && mkdir "$Backup"
[[ ! -e $Backup/name.txt ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$Backup/name.txt"
[[ ! -d $Backup/tools ]] && cp -r "$MODDIR/tools" "$Backup" && rm -rf "$Backup/tools"/restore* && rm -rf "$Backup/tools/apk" && rm -rf "$Backup/tools/toast" && rm -rf "$Backup/tools/appinfo*"
[[ ! -e $Backup/還原備份.sh ]] && cp -r "$MODDIR/tools/restore" "$Backup/還原備份.sh"
filesize="$(du -ks "$Backup" | awk '{print $1}')"
#調用二進制
Quantity=0
#顯示執行結果
echo_log() {
	if [[ $? = 0 ]]; then
		echoRgb "$1成功" "0" "1" && result=0
	else
		echoRgb "$1備份失敗，過世了" "0" "0" && result=1 && let ERROR++
	fi
}
#檢測apk狀態進行備份
Backup_apk() {
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir "$Backup_folder"
	[[ $(cat "$Backup/name.txt" | sed -e '/^$/d' | grep -w "$name" | head -1) = "" ]] && echo "$name2 $name" >>"$Backup/name.txt"
	if [[ $apk_version = $(dumpsys package "$name" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1) ]]; then
		unset xb && result=0
		echoRgb "Apk版本無更新 跳過備份"
	else
		[[ $lxj -ge 95 ]] && echoRgb "$data空間不足,達到$lxj%" "0" "0" && exit 2
		rm -rf "$Backup_folder"/*.apk
		#備份apk
		echoRgb "$1"
		[[ $name != $Open_apps ]] && am force-stop "$name"
		echo "$apk_path" | sed -e '/^$/d' | while read j; do
			path="$j"
			b_size="$(ls -l "$path" | awk '{print $5}')"
			k_size="$(awk 'BEGIN{printf "%.2f\n", "'$b_size'"/'1024'}')"
			m_size="$(awk 'BEGIN{printf "%.2f\n", "'$k_size'"/'1024'}')"
			echoRgb "${path##*/} ${m_size}MB(${k_size}KB)" "0" "2"
		done
		apk_path="$(echo "$apk_path" | head -1)"
		cp -r "${apk_path%/*}"/*.apk "$Backup_folder/"
		echo_log "備份$apk_number個Apk"
		if [[ $result = 0 ]]; then
			echo "apk_version=$(dumpsys package "$name" | awk '/versionName=/{print $1}' | cut -f2 -d '=' | head -1)" >>"$app_details"
			[[ $PackageName = "" ]] && echo "PackageName=$name">>"$app_details"
		fi
	fi
	[[ $name = bin.mt.plus && -e $Backup_folder/base.apk ]] && cp -r "$Backup_folder/base.apk" "$Backup_folder.apk"
	if [[ $name = com.android.chrome ]]; then
		#刪除所有舊apk ,保留一個最新apk進行備份
		ReservedNum=1
		FileNum="$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l)"
		while [[ $FileNum -gt $ReservedNum ]]; do
			OldFile="$(ls -rt /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)"
			echoRgb "刪除文件:${OldFile%/*/*}"
			rm -rf "${OldFile%/*/*}"
			let "FileNum--"
		done
		[[ -e $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null) && $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l) = 1 ]] && cp -r "$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)" "$Backup_folder/nmsl.apk"
	fi
	unset PackageName ; D=1
}
#檢測數據位置進行備份
Backup_data() {
	unset  zsize
	case $1 in
	user) Size="$userSize" && data_path="$path2/$name" ;;
	data) Size="$dataSize" && data_path="$path/$1/$name" ;;
	obb) Size="$obbSize" && data_path="$path/$1/$name" ;;
	*) [[ -e $app_details ]] && Size="$(cat "$app_details" | awk "/$1Size/"'{print $1}' | cut -f2 -d '=' | tail -n1)" ; data_path="$2" && Compression_method=tar && zsize=1 ;;
	esac
	if [[ -d $data_path ]]; then
		if [[ $Size != $(du -ks "$data_path" | awk '{print $1}') ]]; then
			[[ $lxj -ge 95 ]] && echoRgb "$data空間不足,達到$lxj%" "0" "0" && exit 2
			cd "${data_path%/*}"
			echoRgb "備份$1數據" "0" "2"
			case $1 in
			user)
				#data_path="${data_path##*/}"
				case $Compression_method in
				tar|Tar|TAR) tar --exclude="$data_path/.ota" --exclude="$data_path/cache" --exclude="$data_path/lib" -cPpf - "$data_path" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd|Zstd|ZSTD) tar --exclude="$data_path/.ota" --exclude="$data_path/cache" --exclude="$data_path/lib" -cPpf - "$data_path" 2>/dev/null | pv | zstd -r -T0 -6 -q >"$Backup_folder/$1.tar.zst" ;;
				lz4|Lz4|LZ4) tar --exclude="$data_path/.ota" --exclude="$data_path/cache" --exclude="$data_path/lib" -cPpf - "$data_path" 2>/dev/null | pv | lz4 -1 >"$Backup_folder/$1.tar.lz4" ;;
				*) echoRgb "你個憨批$Compression_method是什麼勾八" "0" "0" && rm -rf "$Backup" && exit 2 ;;
				esac ;;
			*)
				case $Compression_method in
				tar|Tar|TAR) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv >"$Backup_folder/$1.tar" ;;
				zstd|Zstd|ZSTD) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv | zstd -r -T0 -6 -q >"$Backup_folder/$1.tar.zst" ;;
				lz4|Lz4|LZ4) tar --exclude="Backup_"* -cPpf - "$data_path" 2>/dev/null | pv | lz4 -1 >"$Backup_folder/$1.tar.lz4" ;;
				*) echoRgb "你個憨批$Compression_method是什麼勾八" "0" "0" && rm -rf "$Backup" && exit 2 ;;
				esac ;;
			esac
			echo_log "備份$1數據"
			if [[ $result = 0 ]]; then
				if [[ $zsize != "" ]]; then
					echo "#$1Size=$(du -ks "$data_path" | awk '{print $1}')" >>"$app_details"
				else
					echo "$1Size=$(du -ks "$data_path" | awk '{print $1}')" >>"$app_details"
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
echoRgb "選擇是否只備份split apk(分割apk檔)
 如果你不知道這意味什麼請選擇音量下進行混合備份
 音量上是，音量下不是"
get_version "是" "不是，混合備份" && Splist="$branch"
echoRgb "是否備份外部數據 即比如原神的數據包
 音量上備份，音量下不備份"
get_version "備份" "不備份" && Backup_obb_data="$branch"
echoRgb "是否備份使用者數據 
 音量上備份，音量下不備份"
get_version "備份" "不備份" && Backup_user_data="$branch"
echoRgb "全部軟件備份結束後是否備份媒體數據(DCIM|Music|Pictures)
 音量上備份，音量下不備份"
get_version "備份" "不備份" && backup_media="$branch"
}
bn=37
#開始循環$txt內的資料進行備份
#記錄開始時間
starttime1="$(date -u "+%s")"
TIME="$starttime1"
#記錄error次數起點
ERROR=1
{
while [[ $i -le $r ]]; do
	echoRgb "備份第$i個應用 總共$r個 剩下$((r-i))個應用"
	name="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')"
	name2="$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')"
	lxj="$(df -h "$data" | awk 'END{print $4}' | sed 's/%//g')"
	if [[ $name2 = *! || $name2 = *！ ]]; then
		name2="$(echo "$name2" | sed 's/!//g ; s/！//g')"
		echoRgb "跳過備份$name2 所有數據" "0" "0"
		No_backupdata=1
	else
		[[ $No_backupdata != "" ]] && unset No_backupdata
	fi
	Backup_folder="$Backup/$name2($name)"
	app_details="$Backup_folder/app_details"
	[[ -e $app_details ]] && . "$app_details"
	[[ $name = "" ]] && echoRgb "警告! name.txt軟件包名獲取失敗，可能修改有問題" "0" "0" && exit 1
	Get_apklist="$(pm list packages | grep -w "$name" | cut -f2 -d ':')"
	if [[ $Get_apklist != "" && $Get_apklist = $name ]]; then
		starttime2="$(date -u "+%s")"
		echoRgb "備份$name2 ($name)"
		apk_path="$(pm path "$name" | cut -f2 -d ':')"
		[[ $name = com.tencent.mobileqq ]] && echo "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份"
		[[ $name = com.tencent.mm ]] && echo "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份"
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
			[[ ! -e $Backup_folder/恢復$name2.sh ]] && cp -r "$MODDIR/tools/restore2" "$Backup_folder/恢復$name2.sh"
			if [[ $Backup_obb_data = true ]]; then
				#備份data數據
				Backup_data "data"
				#備份obb數據
				Backup_data "obb"
			fi
			#備份user數據
			[[ $Backup_user_data = true ]] && Backup_data "user"
		fi
		endtime 2 "$name2備份"
		echoRgb "完成$((i*100/r))% $hx$(df -h "$data" | awk 'END{print "剩餘:"$3"使用率:"$4}')"
	else
		echoRgb "$name2[$name]不在安裝列表，備份個寂寞？" "0" "0"
	fi
	echo
	if [[ $i = $r ]]; then
		endtime 1 "應用備份"
		starttime1="$(date -u "+%s")"
		if [[ $backup_media = true ]]; then
			echoRgb "備份結束，備份多媒體"
			Backup_folder="$Backup/媒體"
			A=1
			B="$(echo "$Custom_path" | sed -e '/^$/d' | sed -n '$=')"
			[[ ! -d $Backup_folder ]] && mkdir "$Backup_folder"
			[[ ! -e $Backup_folder/恢復多媒體數據.sh ]] && cp -r "$MODDIR/tools/restore3" "$Backup_folder/恢復多媒體數據.sh"
			app_details="$Backup_folder/app_details"
			[[ -e $app_details ]] && . "$app_details"
			echo "$Custom_path" | sed -e '/^$/d' | while read k; do
				echoRgb "備份第$A個資料夾 總共$B個 剩下$((B-A))個"
				Backup_data "${k##*/}" "$k"
				echoRgb "完成$((A*100/B))% $hx$(df -h "$data" | awk 'END{print "剩餘:"$3"使用率:"$4}')" && let A++
			done
			endtime 1 "自定義備份"
		fi
	fi
	if [[ $ERROR -ge 5 ]]; then
		echoRgb "錯誤次數達到上限 環境已重設" "0" "0" && rm -rf "$filepath"
		echoRgb "請重新執行腳本" "0" "0" && exit
	fi
	let i++
done

echoRgb "你要備份跑路？祝你卡米9008" "0" "2"
#計算出備份大小跟差異性
filesizee="$(du -ks "$Backup" | awk '{print $1}')"
dsize="$(($((filesizee - filesize)) / 1024))"
echoRgb "備份資料夾路徑:$Backup"
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
[[ $(pm path y.u.k) != "" ]] && toast "批量備份完成"
starttime1="$TIME"
endtime 1 "批量備份開始到結束"
exit 0
}&