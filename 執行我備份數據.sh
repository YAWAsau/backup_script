#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不給Root用你媽 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥馬不解壓縮？用毛線 憨批" && exit 1
#是否備份外部數據
sdcard_data=1
#記錄開始時間
starttime1=$(date +"%Y-%m-%d %H:%M:%S")
#設置腳本busybox目錄位置
filepath=/data/adb/busybox/bin
#檢測是否存在Magisk busybox
if [[ -e /data/adb/magisk/busybox.bin ]]; then
    if [[ ! -d $filepath ]]; then
        mkdir -p $filepath
        cp -r /data/adb/magisk/busybox.bin $filepath 
        mv $filepath/busybox.bin $filepath/busybox
        busybox="$filepath/busybox"   
    else
        if [[ -e $filepath/busybox.bin ]]; then
            mv $filepath/busybox.bin $filepath/busybox
        fi
        busybox="$filepath/busybox"
    fi
else
    if [[ -e /data/adb/magisk/busybox ]]; then
        if [[ ! -d $filepath ]]; then
            mkdir -p $filepath
            cp -r /data/adb/magisk/busybox $filepath
            busybox="$filepath/busybox"
        else
            busybox="$filepath/busybox"
        fi
    else
        echo "沒有發現Magisk busybox"
    fi
fi
if [[ -e $busybox ]]; then   
    echo "busybox path: $busybox"
    chmod 0777 $busybox
    echo "發現Magisk Busybox....正在替換環境變量為Busybox防止簡陋的toybox缺少重要命令"
    for a in $($busybox --list) ; do
        if [[ -n $a ]]; then
            if [[ -d $filepath ]]; then
                [[ ! -e $filepath/$a ]] && ln -s $busybox "$filepath/$a"
            fi    
        fi    
    done
    unset PATH    
fi

#補上遺失指令集
Add_path () {
    if [[ ! -e $filepath/$1 ]]; then
        if [[ -e $2/$1 ]]; then
            if [[ $3 == y ]]; then                
                if [[ -d $filepath ]]; then
                    [[ ! -e $filepath/$1 ]] && cp -r $2/$1 $filepath && chmod 0777 $filepath/$1
                else
                    mkdir -p $filepath
                    cp -r $2/$1 $filepath
                    chmod 0777 $filepath/$1
                fi
            else
                if [[ -d $filepath ]]; then
                    [[ ! -e $filepath/$1 ]] && ln -s $2/$1 $filepath
                else
                    mkdir -p $filepath
                    ln -s $2/$1 $filepath
                fi
            fi
        else 
            echo "$2/$1不存在 腳本所需的$1缺少"
            exit 1
        fi
    fi    
}
#設置命令位置
Add_path "zip" ${0%/*}/bin y
Add_path "pm" /system/bin n
Add_path "cmd" /system/bin n
Add_path "am" /system/bin n
export PATH=$PATH:/data/adb/busybox/bin    
i=1
txt="${0%/*}/Apkname.txt"
[[ ! -e $txt ]] && echo "$txt缺少" && exit 1
[[ ! -d ${0%/*}/bin ]] && echo "${0%/*}/bin目錄遺失" && exit 1
r=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n '$=')
[[ -n $r ]] && h=$r
[[ -z $r ]] && echo "爬..Apkname.txt是空的備份個鬼" && exit 0
path="/sdcard/Android"
path2="/data/user/0"
Backup="${0%/*}/Backup"
[[ ! -d $Backup ]] && mkdir "$Backup"
filesize=$(du -k -s $Backup | awk '{print $1}')
[[ ! -e $Backup/name.txt ]] && echo "#不需要恢復還原的應用請在開頭注釋# 比如#xxxxxxxx 酷安">$Backup/name.txt
#調用二進制
Quantity=0
7z () {
    7za a -t7z $1.7z $2 -mx=$Quantity -r -ms >/dev/null 2>&1
    #7za a -t7z $1.7z $2 -mx=$Quantity -r -m0=LZMA:d=21 -ms -mmt>/dev/null 2>&1
}
Zip () {
    zip -r -$Quantity $1.zip $2>/dev/null 2>&1 	
}	

#Everything is Ok>/dev/null 2>&1
#轉換echo顏色提高可讀性
echoRgb () {
    if [[ -n $2 ]]; then
        if [[ $3 == 1 ]]; then
            echo -e "\e[1;32m $1\e[0m"
        else
            echo -e "\e[1;31m $1\e[0m"
        fi
    else
        echo -e "\e[1;${bn}m $1\e[0m"
    fi
}
#顯示執行結果
echo_log() {
	if [[ $? == 0 ]]; then
		echoRgb "$1成功" "0" "1"
		result=0
	else
		echoRgb "$1備份失敗，過世了" "0" "0"
		result=1
	fi
}
#計算結束時間
endtime () {
    #計算總體切換時長耗費
    case $1 in
    1) starttime=$starttime1 ;;
    2) starttime=$starttime2 ;;
    esac
    endtime=$(date "+%Y-%m-%d %H:%M:%S")
    duration=$(echo $((Sleep_time + $(date +%s -d "${endtime}") - $(date +%s -d "${starttime}"))) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
    [[ -n $duration ]] && echoRgb "$2用時:$duration" || echoRgb "$2用時:0秒"
}
#檢測數據位置進行備份
Backup-data () {
    if [[ -d $path/$1/$name && $sdcard_data == 1 ]]; then
        if [[ ! -e $Backup/$name/$1size.txt ]]; then
            echoRgb "發現${name2} $path/$1/數據開始備份"
            #7z "$name-$1" $path/$1/$name       
             Zip "$name-$1" $path/$1/$name                       
             echo_log "備份$name2 $path/$1"
             [[ $result == 0 ]] && echo $(du -k -s $path/$1/$name | awk '{print $1}')>$Backup/$name/$1size.txt 
        else
             if [[ ! $(cat $Backup/$name/$1size.txt) == $(du -k -s $path/$1/$name | awk '{print $1}') ]];then
                 echoRgb "發現${name2} $path/$1/數據開始備份"
                 #7z "$name-$1" $path/$1/$name       
                 Zip "$name-$1" $path/$1/$name                       
                 echo_log "備份$name2 $path/$1"
                 [[ $result == 0 ]] && echo $(du -k -s $path/$1/$name | awk '{print $1}')>$Backup/$name/$1size.txt 
             else
                 echoRgb "$name2 $1數據無發生變化 跳過備份"
             fi
        fi
    else
        [[ $sdcard_data == 1 ]] && echoRgb "$path/$1 不存在跳過備份"
    fi
}
#檢測apk狀態進行備份
Backup-apk () {
    if [[ ! -e $Backup/$name/apk-version.txt ]]; then
        echoRgb "$1"
        echoRgb "發現$(pm path "$name" | cut -f2 -d ':' | wc -l)個Apk"
        cp -r $(pm path "$name" | cut -f2 -d ':') "$Backup/$name"
        echo_log "備份Apk"
        [[ $result == 0 ]] && echo $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p')>$Backup/$name/apk-version.txt
    else
        if [[ ! $(cat $Backup/$name/apk-version.txt) == $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p') ]];then    			 
            echoRgb "$1"
            echoRgb "發現$(pm path "$name" | cut -f2 -d ':' | wc -l)個Apk"
            cp -r $(pm path "$name" | cut -f2 -d ':') "$Backup/$name"
            echo_log "備份Apk"
            [[ $result == 0 ]] && echo $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p')>$Backup/$name/apk-version.txt
        else
            echoRgb "$name2 Apk版本無更新 跳過備份"
        fi 
    fi 
}

bn=37
#開始循環$txt內的資料進行備份
while [[ $i -le $h ]]; do
    #let bn++
    #[[ $bn -ge 37 ]] && bn=31
	echoRgb "備份第$i個應用 總共$h個 剩下$(($h - $i))個應用"
	name=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')
	name2=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')
	echoRgb "備份$name2"
	starttime2=$(date +"%Y-%m-%d %H:%M:%S")
	if [[ -n $name ]]; then
		if [[ -n $(pm list packages | grep -w "$name" | sed 's/package://g') ]]; then
            pkg=$(pm list packages | grep -w "$name" | sed 's/package://g')
		    [[ $pkg == com.tencent.mobileqq ]] && echo "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份" || [[ $pkg == com.tencent.mm ]] && echo "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的軟件備份"
			[[ ! -d $Backup/bin ]] && mkdir -p $Backup/bin && cp -f ${0%/*}/bin/7za $Backup/bin
			cd $Backup
			cp -r ${0%/*}/bin/restore $Backup
			mv restore 還原備份.sh
			#停止軟件
			[[ ! $name == bin.mt.plus && ! $name == com.termux ]] && am force-stop $name
			[[ -z $(cat $Backup/name.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name2  $name" >>$Backup/name.txt
			#[[ ! -d $Backup/$name ]] && echo "$name2  $name" >>$Backup/name.txt
			#创建APP备份文件夹
			[[ ! -d $name ]] && mkdir "$name" 
			cd "$name"			
			#备份apk
			echoRgb "[ 開始備份${name2} APK ]"
			case $(pm path "$name" | cut -f2 -d ':' | wc -l) in
            1)
                Backup-apk "$name2為非Split Apk" ;;
			*)			    
                Backup-apk "$name2為Split Apk支持備份" ;;
            esac	
			[[ $sdcard_data == 1 ]] && echoRgb "[ 開始備份${name2} Sdcard數據 ]"
			#备份data数据
            Backup-data data
			#备份obb数据
            Backup-data obb
            echoRgb "[ 開始備份${name2} user數據 ]"
			#备份user数据
			if [[ -d /data/user/0/$name ]]; then
                if [[ ! -e $Backup/$name/usersize.txt ]]; then
			        #7za a -t7z "$name-user.7z" /data/user/0/$name -xr!$name/lib -xr!$name/cache -xr!$name/code_cache -mx=$Quantity -r -ms -mmt>/dev/null 2>&1
    			    #zip -r -$Quantity "$name-user.zip" /data/user/0/$name -x "/data/user/0/$name/lib/*" -x "/data/user/0/$name/cache/*" -x "/data/user/0/$name/code_cache/*" >/dev/null 2>&1
    			     zip -r -$Quantity "$name-user.zip" /data/user/0/$name -x "/data/user/0/$name/lib/*" -x "/data/user/0/$name/cache/*">/dev/null 2>&1
    			    echo_log "備份user數據/data/user/0/$name"
    			    [[ $result == 0 ]] && echo $(du -k -s /data/user/0/$name | awk '{print $1}')>$Backup/$name/usersize.txt    
    			else
                    if [[ ! $(cat $Backup/$name/usersize.txt) == $(du -k -s /data/user/0/$name | awk '{print $1}') ]];then
        			    #zip -r -$Quantity "$name-user.zip" /data/user/0/$name -x "/data/user/0/$name/lib/*" -x "/data/user/0/$name/cache/*" -x "/data/user/0/$name/code_cache/*" >/dev/null 2>&1
        			    zip -r -$Quantity "$name-user.zip" /data/user/0/$name -x "/data/user/0/$name/lib/*" -x "/data/user/0/$name/cache/*">/dev/null 2>&1
        			    echo_log "備份user數據/data/user/0/$name"
        			    [[ $result == 0 ]] && echo $(du -k -s /data/user/0/$name | awk '{print $1}')>$Backup/$name/usersize.txt    
        			else
                        echoRgb "$name2 user數據無發生變化 跳過備份"
                    fi
    			fi        						                        
			fi
		fi
        endtime 2 "$name2備份"
		echo
	fi    
	let i++
done
#計算出備份大小跟差異性
filesizee=$(du -k -s $Backup | awk '{print $1}')
dsize=$(($((filesizee-filesize))/1024))
echoRgb "備份資料夾路徑:$Backup"
echoRgb "備份資料夾總體大小$(du -k -s -h $Backup | awk '{print $1}')"
if [[ $dsize -gt 0 ]]; then
    if [[ $((dsize/1024)) -gt 0 ]]; then
        echoRgb "本次備份: $((dsize/1024))gb"
    else
        echoRgb "本次備份: ${dsize}mb"
    fi
else
    echoRgb "本次備份: $(($((filesizee-filesize))*1000/1024))kb"
fi
echoRgb "批量備份完成"
endtime 1 "批量備份開始到結束"