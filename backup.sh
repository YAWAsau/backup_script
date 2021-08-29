#!/system/bin/sh
MODDIR=${0%/*}
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo "$MODDIR" | grep -v 'mt') ]] && echo "我他媽骨灰給你揚了撒了TM不解壓縮？用毛線 憨批" && exit 1
[[ $MODDIR = /storage/emulated/0/Android/* ]] && echo "請勿在$MODDIR內備份" && exit 2
[[ ! -d $MODDIR/tools ]] && echo "$MODDIR/tools目錄遺失" && exit 1
# Load Settings Variables
md5path=$MODDIR
tools_path=$MODDIR/tools
. "$tools_path/bin.sh"
. "$MODDIR/backup_settings.conf"
isBoolean $Lo && Lo=$nsx
if [[ $Lo = false ]]; then
	isBoolean $C && C=$nsx
	isBoolean $B && B=$nsx
	isBoolean $path && path3=$nsx
else
	echoRgb "備份路徑位置為絕對位置或是當前環境位置
 音量上當前環境位置，音量下腳本絕對位置"
	get_version "當前環境位置" "腳本絕對位置" && path3=$branch
fi
i=1
Open_apps=$(dumpsys window | grep -w mCurrentFocus | egrep -oh "[^ ]*/[^//}]+" | cut -f 1 -d "/")
echoRgb "當前使用的備份程序:$(appinfo -o ands -pn "$Open_apps" 2>/dev/null)"
path=/sdcard/Android
path2=/data/user/0
if [[ $path3 = true ]]; then
	Backup=$PWD/Backup
	txt=$PWD/Apkname.txt
else
	Backup=$MODDIR/Backup
	txt=$MODDIR/Apkname.txt
fi
[[ ! -e $txt ]] && echo "$txt缺少" && exit 1
r=$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n '$=')
[[ -n $r ]] && h=$r
[[ -z $r ]] && echo "爬..Apkname.txt是空的備份個鬼" && exit 0
data=/data
hx="本地"
if [[ -d /proc/scsi/usb-storage ]]; then
	PU=$(ls /dev/block/vold | grep public)
	PT=$(cat /proc/mounts | grep "$PU" | awk '{print $2}')
	echoRgb "檢測到usb 是否在usb備份
 音量上是，音量下不是"
	get_version "USB備份" "本地備份"
	if $branch = true ]]; then
		Backup=$PT/Backup
		data=/dev/block/vold/$PU
		hx=USB
	fi
else
	echoRgb "沒有檢測到USB於本地備份"
fi
[[ ! -d $Backup ]] && mkdir "$Backup"
[[ ! -e $Backup/name.txt ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安" >"$Backup/name.txt"
[[ ! -d $Backup/tools ]] && mkdir -p "$Backup/tools" && cp -r "$MODDIR/tools"/* "$Backup/tools" && rm -rf "$Backup/tools"/restore*
[[ ! -e $Backup/還原備份.sh ]] && cp -r "$MODDIR/tools/restore" "$Backup/還原備份.sh"
filesize=$(du -ks "$Backup" | awk '{print $1}')
#調用二進制
Quantity=0
lz4 () {
	tar -cPpf - "$2" 2>/dev/null | pv -terb >"$Backup_folder/$1.tar.lz4"
}
zst () {
	tar -cPpf - "$2" 2>/dev/null | pv -terb | zstd -r -T0 -0 -q >"$Backup_folder/$1.tar.zst"
}
#顯示執行結果
echo_log() {
	if [[ $? = 0 ]]; then
		echoRgb "$1成功" "0" "1" && result=0
	else
		echoRgb "$1備份失敗，過世了" "0" "0" && result=1
	fi
}
#檢測數據位置進行備份
Backup_method() {
	if [[ $1 != user ]]; then
		lz4 "$name-$1" "$data_path"
		echo_log "備份$1數據"
		if [[ $result = 0 ]]; then
			echo "$(du -ks "$data_path" | awk '{print $1}')" >"$Size_file"
		else
			echoRgb "lz4遭遇打包失敗，使用zstd嘗試打包"
			zst "$name-$1" "$data_path"
			echo_log "備份$1數據"
			[[ $result = 0 ]] && echo "$(du -ks "$data_path" | awk '{print $1}')" >"$Size_file"
		fi
	else
		tar --exclude="cache/" --exclude="lib/" -cPpf - "$data_path" 2>/dev/null | pv -terb >"$Backup_folder/$name-user.tar.lz4"
		echo_log "備份$1數據"
		if [[ $result = 0 ]]; then
			echo $(du -ks "$data_path" | awk '{print $1}') >"$Size_file"
		else
			echoRgb "lz4遭遇打包失敗，使用zstd嘗試打包"
			tar --exclude="cache/" --exclude="lib/" -cPpf - "$data_path" 2>/dev/null | pv -terb | zstd -r -T0 -0 -q >"$Backup_folder/$name-user.tar.zst"
			echo_log "備份$1數據"
			[[ $result = 0 ]] && echo "$(du -ks "$data_path" | awk '{print $1}')" >"$Size_file"
		fi
	fi
}
Backup-data() {
	if [[ $1 = user ]]; then
		data_path=/data/user/0/$name
		Size_file=$Backup_folder/usersize.txt
	else
		data_path=$path/$1/$name
		Size_file=$Backup_folder/$1size.txt
	fi
	if [[ -d $data_path ]]; then
		if [[ ! -e $Size_file ]]; then
			Backup_method "$1"
		else
			if [[ $(cat "$Size_file") != $(du -ks "$data_path" | awk '{print $1}') ]]; then
				Backup_method "$1"
			else
				echoRgb "$1數據無發生變化 跳過備份"
			fi
		fi
	else
		echoRgb "$1數據不存在跳過備份"
	fi
}
#檢測apk狀態進行備份
Backup-apk() {
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir "$Backup_folder"
	#備份apk
	apk_path=$(pm path "$name" | cut -f2 -d ':')
	echoRgb "$1"
	xb=d
	[[ -z $(cat "$Backup/name.txt" | grep -v "#" | sed -e '/^$/d' | grep -w "$name" | head -1) ]] && echo "$name2 $name" >>"$Backup/name.txt"
	if [[ -e $Backup_folder/apk-version.txt ]]; then
		if [[ $(cat "$Backup_folder/apk-version.txt") = $(pm dump "$name" | grep -m 1 versionName | sed -n 's/.*=//p') ]]; then
			unset xb
			echoRgb "Apk版本無更新 跳過備份"
		fi
	fi
	[[ -n $xb ]] && {
		rm -rf "$Backup_folder"/*.apk
		if [[ $apk_number = 1 ]]; then
			cp -r "$apk_path" "$Backup_folder/"
		else
			pm path "$name" | cut -f2 -d ':' | while read aof; do
				cp -r "$aof" "$Backup_folder/"
			done
		fi
		echo_log "備份$apk_number個Apk"
		[[ $result = 0 ]] && echo "$(pm dump "$name" | grep -m 1 versionName | sed -n 's/.*=//p')" >"$Backup_folder/apk-version.txt" && echo "$name">"$Backup_folder/Package_name.txt"
	}
	if [[ $name = com.android.chrome ]]; then
		#刪除所有舊apk ,保留一個最新apk進行備份
		ReservedNum=1
		FileNum=$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l)
		while [[ $FileNum -gt $ReservedNum ]]; do
			OldFile=$(ls -rt /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)
			echoRgb "刪除文件:${OldFile%/*/*}"
			rm -rf "${OldFile%/*/*}"
			let "FileNum--"
		done
		if [[ -e $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null) && $(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | wc -l) = 1 ]]; then
			cp -r "$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)" "$Backup_folder/nmsl.apk"
			echo_log "備份com.google.android.trichromelibrary"
		fi
	fi
	D=1
}
[[ $Lo = true ]] && {
echoRgb "選擇是否只備份split apk(分割apk檔)
 如果你不知道這意味什麼請選擇音量下進行混合備份
 音量上是，音量下不是"
get_version "是" "不是，混合備份" && C=$branch
echoRgb "是否備份外部數據 即比如原神的數據包
 音量上備份，音量下不備份"
get_version "備份" "不備份" && B=$branch
}
bn=37
#開始循環$txt內的資料進行備份
#記錄開始時間
starttime1=$(date +"%Y-%m-%d %H:%M:%S")
{
while [[ $i -le $h ]]; do
	#let bn++
	#[[ $bn -ge 37 ]] && bn=31
	echoRgb "備份第$i個應用 總共$h個 剩下$((h-i))個應用"
	name=$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')
	name2=$(cat "$txt" | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')
	Backup_folder="$Backup/$name2($name)"
	[[ -z $name ]] && echoRgb "警告! name.txt軟件包名獲取失敗，可能修改有問題" "0" "0" && exit 1
	if [[ -n $(Package_names "$name") ]]; then
		starttime2=$(date +"%Y-%m-%d %H:%M:%S")
		echoRgb "備份$name2 ($name)"
		[[ $name = com.tencent.mobileqq ]] && echo "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份" || [[ $name = com.tencent.mm ]] && echo "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份"
		apk_number=$(pm path "$name" | cut -f2 -d ':' | wc -l)
		if [[ $apk_number = 1 ]]; then
			if [[ $C = false ]]; then
				[[ $name != $Open_apps ]] && am force-stop "$name"
				Backup-apk "非Split Apk"
			else
				echoRgb "非Split Apk跳過備份"
				unset D
			fi
		else
			[[ $name != $Open_apps ]] && am force-stop "$name"
			Backup-apk "Split Apk支持備份"
		fi
		if [[ -n $D ]]; then
			#複製Mt安裝包到外部資料夾方便恢複
			[[ ! -e $Backup_folder/恢復$name2.sh ]] && cp -r "$MODDIR/tools/restore2" "$Backup_folder/恢復$name2.sh"
			[[ $name = bin.mt.plus && -e $Backup_folder/base.apk ]] && cp -r "$Backup_folder/base.apk" "$Backup_folder.apk"
			if [[ $B = true ]]; then
				#備份data數據
				Backup-data data
				#備份obb數據
				Backup-data obb
			fi
			#備份user數據
			Backup-data user
			endtime 2 "$name2備份"
		fi
		echoRgb "完成$((i*100/h))% $hx$(df -h "$data" | awk 'END{print "剩餘:"$3"使用率:"$4}')"
	else
		echoRgb "$name2[$name]不在安裝列表，備份個寂寞？" "0" "0"
	fi
	echo
	lxj=$(df -h "$data" | awk 'END{print $4}' | sed 's/%//g')
	[[ $lxj -ge 95 ]] && echoRgb "$data空間不足,達到$lxj%" "0" "0" && exit 2
	let i++
done
#計算出備份大小跟差異性
filesizee=$(du -ks "$Backup" | awk '{print $1}')
dsize=$(($((filesizee - filesize)) / 1024))
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
endtime 1 "批量備份開始到結束"
exit 0
}&