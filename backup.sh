#!/system/bin/sh
[[ $(id -u) -ne 0 ]] && echo "你是憨批？不给Root用你妈 爬" && exit 1
[[ -z $(echo ${0%/*} | grep -v 'mt') ]] && echo "草泥马不解压缩？用毛缐 憨批" && exit 1
[[ ! -d ${0%/*}/tools ]] && echo "${0%/*}/tools目录遗失" && exit 1
# Load Settings Variables
tools_path=${0%/*}/tools
. ${0%/*}/tools/bin.sh
#设置命令和目录位置及是否使用链接方式
Add_path

Add_path "pv"
echo "环境变数: $PATH"
nowversion=" 86uevjik6"


gitsh="https://raw.githubusercontent.com/YAWAsau/backup_script/master/backup.sh"
giteesh="https://cdn.jsdelivr.net/gh/YAWAsau/backup_script@master/backup.sh"
if [[ -n $(curl -s "$gitsh" | awk '/nowversion=/{print $2}' | sed 's/"//g' | sed 's/\-s//g' | sed 's/\[//g') ]]; then
    Onlineversion=$(curl -s "$gitsh" | awk '/nowversion=/{print $2}' | sed 's/"//g' | sed 's/\-s//g' | sed 's/\[//g')
    if [[ ! $(echo $nowversion | sed 's/ //g') == $Onlineversion ]]; then
        echo "本地版本与远端版本不同 下载覆盖中"
        curl -s "$gitsh">${0%/*}/backup.sh
        if [[ $? -eq 0 ]]; then
            curl -s https://raw.githubusercontent.com/YAWAsau/backup_script/master/Update/log
            echo
            echo
            echo "- 新版本已下载完毕，请退出重新运行backup.sh"
            exit
        fi
    else
        echo "无须更新已是最新版本"
    fi
else
    echo "从GitHub获取更新下载失败 转换尝试cdn下载"
    if [[ -n $(curl -s "$giteesh" | awk '/nowversion=/{print $2}' | sed 's/"//g' | sed 's/\-s//g' | sed 's/\[//g') ]]; then
        Onlineversion=$(curl -s "$giteesh" | awk '/nowversion=/{print $2}' | sed 's/"//g' | sed 's/\-s//g' | sed 's/\[//g')
        if [[ ! $(echo $nowversion | sed 's/ //g') == $Onlineversion ]]; then
            echo "本地版本与远端版本不同 下载覆盖中"
            curl -s "$giteesh">${0%/*}/backup.sh
            if [[ $? -eq 0 ]]; then
                curl -s https://cdn.jsdelivr.net/gh/YAWAsau/backup_script@master/Update/log
                echo
                echo
                echo "- 新版本已下载完毕，请退出重新运行backup.sh"
                exit
            fi
        else
            echo "无须更新已是最新版本"
        fi
    else
        echo "联网更新脚本失败，请自行关注作者酷安"
        echo "落叶凄凉TEL"
    fi
fi
i=1
txt="${0%/*}/Apkname.txt"
[[ ! -e $txt ]] && echo "$txt缺少" && exit 1
r=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n '$=')
[[ -n $r ]] && h=$r
[[ -z $r ]] && echo "爬..Apkname.txt是空的备份个鬼" && exit 0
path="/sdcard/Android"
path2="/data/user/0"
Backup="${0%/*}/Backup"
[[ ! -d $Backup ]] && mkdir "$Backup"
filesize=$(du -k -s $Backup | awk '{print $1}')
[[ ! -e $Backup/name.txt ]] && echo "#不需要恢復还原的应用请在开头注释# 比如#xxxxxxxx 酷安" >$Backup/name.txt
#调用二进制
Quantity=0
lz4() {
	tar -cf - "$2" 2>/dev/null | pv -terb >"$1.tar.lz4"
}
#Everything is Ok#z 2>&1
#转换echo颜色提高可读性
echoRgb() {
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
#显示执行结果
echo_log() {
	if [[ $? == 0 ]]; then
		echoRgb "$1成功" "0" "1"
		result=0
	else
		echoRgb "$1备份失败，过世了" "0" "0"
		result=1
	fi
}
#计算结束时间
endtime() {
	#计算总体切换时长耗费
	case $1 in
	1) starttime=$starttime1 ;;
	2) starttime=$starttime2 ;;
	esac
	endtime=$(date "+%Y-%m-%d %H:%M:%S")
	duration=$(echo $(($(date +%s -d "${endtime}") - $(date +%s -d "${starttime}"))) | awk '{t=split("60 秒 60 分 24 时 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
	[[ -n $duration ]] && echoRgb "$2用时:$duration" || echoRgb "$2用时:0秒"
}

set -e
get_version() {
	local version
	local branch
	while :; do
		version="$(getevent -qlc 1 | awk '{ print $3 }')"
		case "$version" in
		KEY_VOLUMEUP)
			branch="yes"
			;;
		KEY_VOLUMEDOWN)
			branch="no"
			;;
		*)
			continue
			;;
		esac
		echo $branch
		break
	done
}
#检测数据位置进行备份
Backup-data() {
	if [[ -d $path/$1/$name ]]; then
		if [[ ! -e $Backup/$name/$1size.txt ]]; then
			echoRgb "发现${name2} $path/$1/数据开始备份"
			lz4 "$name-$1" $path/$1/$name
			echo_log "备份$name2 $path/$1"
			[[ $result == 0 ]] && echo $(du -k -s $path/$1/$name | awk '{print $1}') >$Backup/$name/$1size.txt
		else
			if [[ ! $(cat $Backup/$name/$1size.txt) == $(du -k -s $path/$1/$name | awk '{print $1}') ]]; then
				echoRgb "发现${name2} $path/$1/数据开始备份"
				lz4 "$name-$1" $path/$1/$name
				echo_log "备份$name2 $path/$1"
				[[ $result == 0 ]] && echo $(du -k -s $path/$1/$name | awk '{print $1}') >$Backup/$name/$1size.txt
			else
				echoRgb "$name2 $1数据无发生变化 跳过备份"
			fi
		fi
	else
		echoRgb "$path/$1 不存在跳过备份"
	fi
}
#检测apk状态进行备份
Backup-apk() {
	#创建APP备份文件夹
	[[ ! -d $Backup/$name ]] && mkdir "$Backup/$name"
	cd $Backup/$name
	#备份apk
	echoRgb "[ 开始备份${name2} APK ]"
	if [[ $name == com.android.chrome ]]; then
		#删除所有旧apk ,保留一个最新apk进行备份
		ReservedNum=1
		FileDir=/data/app/*/com.google.android.trichromelibrary_*/base.apk
		FileNum=$(ls -l $FileDir | grep ^- | wc -l)
		while [[ $FileNum -gt $ReservedNum ]]; do
			OldFile=$(ls -rt $FileDir | head -1)
			echoRgb "删除文件:"$OldFile
			rm -rf $OldFile
			let "FileNum--"
		done
		ls $FileDir | while read t; do
			if [[ -e $t ]]; then
				echoRgb "备份额外的com.google.android.trichromelibrary"
				cp -r "$t" "$Backup/$name/nmsl.apk"
				echo_log "备份Apk"
			fi
		done
	fi
	if [[ ! -e $Backup/$name/apk-version.txt ]]; then
		[[ -z $(cat $Backup/name.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name2  $name" >>$Backup/name.txt
		echoRgb "$1"
		echoRgb "发现$(pm path "$name" | cut -f2 -d ':' | wc -l)个Apk"
		cp -r $(pm path "$name" | cut -f2 -d ':') "$Backup/$name"
		echo_log "备份Apk"
		[[ $result == 0 ]] && echo $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p') >$Backup/$name/apk-version.txt
	else
		if [[ ! $(cat $Backup/$name/apk-version.txt) == $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p') ]]; then
			[[ -z $(cat $Backup/name.txt | grep -v "#" | sed -e '/^$/d' | grep -w "$name") ]] && echo "$name2  $name" >>$Backup/name.txt
			echoRgb "$1"
			echoRgb "发现$(pm path "$name" | cut -f2 -d ':' | wc -l)个Apk"
			cp -r $(pm path "$name" | cut -f2 -d ':') "$Backup/$name"
			echo_log "备份Apk"
			[[ $result == 0 ]] && echo $(pm dump $name | grep -m 1 versionName | sed -n 's/.*=//p') >$Backup/$name/apk-version.txt
		else
			echoRgb "$name2 Apk版本无更新 跳过备份"
		fi
	fi
}
echoRgb "选择是否只备份split apk(分割apk档)"
echoRgb "如果你不知道这意味什么请选择音量下进行混合备份"
echoRgb "音量上是，音量下不是"
if [[ $(get_version) == yes ]]; then
	C=yes
else
	C=no
fi
[[ $C == yes ]] && echoRgb "是" || echoRgb "不是，混合备份"
sleep 1.5
echoRgb "是否备份外部数据 即比如原神的数据包"
echoRgb "音量上备份，音量下不备份"
if [[ $(get_version) == yes ]]; then
	B=yes
else
	B=no
fi
[[ $B == yes ]] && echoRgb "備份" || echoRgb "不备份"
bn=37
#开始循环$txt内的资料进行备份
#记录开始时间
starttime1=$(date +"%Y-%m-%d %H:%M:%S")

while [[ $i -le $h ]]; do
	#let bn++
	#[[ $bn -ge 37 ]] && bn=31
	echoRgb "备份第$i个应用 总共$h个 剩下$(($h - $i))个应用"
	name=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $2}')
	name2=$(cat $txt | grep -v "#" | sed -e '/^$/d' | sed -n "${i}p" | awk '{print $1}')		
	[[ -z $name ]] && echoRgb "警告! name.txt软件包名获取失败，可能修改有问题" "0" "0" && exit 1    
	pkg=$(pm list packages | grep -w "$name" | sed 's/package://g')
	if [[ -n $pkg ]]; then
	    starttime2=$(date +"%Y-%m-%d %H:%M:%S")
	    echoRgb "备份$name2 ($name)"
		[[ $pkg == com.tencent.mobileqq ]] && echo "QQ可能恢復备份失败或是丢失聊天记录，请自行用你信赖的软件备份" || [[ $pkg == com.tencent.mm ]] && echo "WX可能恢復备份失败或是丢失聊天记录，请自行用你信赖的软件备份"
		[[ ! -d $Backup/tools ]] && mkdir -p $Backup/tools && cp -r ${0%/*}/tools/pv $Backup/tools
		[[ ! -e $Backup/还原备份.sh ]] && cp -r ${0%/*}/tools/restore $Backup/还原备份.sh
		[[ ! -e $Backup/tools/bin.sh ]] && cp -r ${0%/*}/tools/bin.sh $Backup/tools
		[[ ! -e $Backup/tools/busybox-* ]] && cp -r ${0%/*}/tools/busybox-* $Backup/tools
		#停止软件
		[[ ! $name == bin.mt.plus && ! $name == com.termux && ! $name == com.mixplorer.silver ]] && am force-stop $name
		if [[ $(pm path "$name" | cut -f2 -d ':' | wc -l) == 1 ]]; then
			if [[ $C == no ]]; then
				Backup-apk "$name2为非Split Apk"
				D=1
			else
				echoRgb "$name2为非Split Apk跳过备份"
				D=
			fi			
		else
			Backup-apk "$name2为Split Apk支持备份"
			D=1			
		fi
        #复制Mt or termux安装包到外部资料夹方便恢复
        if [[ $name == bin.mt.plus || $name == com.termux || $name == com.mixplorer.silver ]]; then           
             if [[ -e $Backup/$name/base.apk ]]; then                
                cp -r "$Backup/$name/base.apk" "$Backup/$name.apk"                
            fi
        fi
		if [[ $B == yes && -n $D ]]; then
			echoRgb "[ 开始备份${name2} Sdcard数据 ]"
			#备份data数据
			Backup-data data
			#备份obb数据
			Backup-data obb
		fi
		#备份user数据
		if [[ -d /data/user/0/$name && -n $D ]]; then
			echoRgb "[ 开始备份${name2} user数据 ]"
			if [[ ! -e $Backup/$name/usersize.txt ]]; then
				tar -cpf - "/data/user/0/$name" --exclude=$name/cache --exclude=$name/lib 2>/dev/null | pv -terb >"$name-user.tar.lz4"
				echo_log "备份user数据/data/user/0/$name"
				[[ $result == 0 ]] && echo $(du -k -s /data/user/0/$name | awk '{print $1}') >$Backup/$name/usersize.txt
			else
				if [[ ! $(cat $Backup/$name/usersize.txt) == $(du -k -s /data/user/0/$name | awk '{print $1}') ]]; then
					tar -cpf - "/data/user/0/$name" --exclude=$name/cache --exclude=$name/lib 2>/dev/null | pv -terb >"$name-user.tar.lz4"
					echo_log "备份user数据/data/user/0/$name"
					[[ $result == 0 ]] && echo $(du -k -s /data/user/0/$name | awk '{print $1}') >$Backup/$name/usersize.txt
				else
					echoRgb "$name2 user数据无发生变化 跳过备份"
				fi
			fi
		fi
        endtime 2 "$name2备份"
    else
        echoRgb "$name2不在安装列表，备份个寂寞？" "0" "0"
	fi		
	echo
	let i++
done
#计算出备份大小跟差异性
filesizee=$(du -k -s $Backup | awk '{print $1}')
dsize=$(($((filesizee - filesize)) / 1024))
echoRgb "备份资料夹路径:$Backup"
echoRgb "备份资料夹总体大小$(du -k -s -h $Backup | awk '{print $1}')"
if [[ $dsize -gt 0 ]]; then
	if [[ $((dsize / 1024)) -gt 0 ]]; then
		echoRgb "本次备份: $((dsize / 1024))gb"
	else
		echoRgb "本次备份: ${dsize}mb"
	fi
else
	echoRgb "本次备份: $(($((filesizee - filesize)) * 1000 / 1024))kb"
fi
echoRgb "批量备份完成"
endtime 1 "批量备份开始到结束"
exit 0