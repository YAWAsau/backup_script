#!/system/bin/sh
# ============================================================
# SpeedBackup tools.sh
# ============================================================
# 區塊索引:
#   L30   ── conf 模板函數 (backup_settings / restore_settings)
#   L286  ── 基礎工具函數 (echoRgb / jq_inplace / size / ...)
#   L841  ── 遠端功能函數 (upload / download / smb / webdav)
#   L2750 ── 系統初始化 (環境檢測 / 路徑 / 用戶 / 語言)
#   L3266 ── 備份路徑 / 預掃 / app_details
#   L3567 ── 備份核心函數 (Backup_apk / Backup_data / ...)
#   L4509 ── backup() 主函數
#   L5139 ── Restore() 主函數
#   L5576 ── Getlist / Check_json / backup_media / wifi
#   L5926 ── 主選單入口
# ============================================================
if [ "$(whoami)" != root ]; then
	echo "你是憨批？不給Root用你媽 爬"
	exit 1
fi
_dex_debug=0
[[ -d /data/cache ]] && set -x 2> /data/cache/debug_output.log
shell_language="zh-TW"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
script="${0##*/}"
backup_version="202606201257"
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
# 產生 backup_settings.conf 的內容模板 (寫到 stdout)
# 透過重定向到檔案來生成或更新備份設定檔
update_backup_settings_conf() {
	echo "#低電量提示 (電量≤15%且未充電時的行為)
#1低電量強制拒絕操作  2無需提示繼續執行  留空音量鍵選擇 (音量上=無視風險繼續操作, 音量下=退出)
low_battery_mode="${low_battery_mode:-}"

#輸入方式 (1=改用鍵盤輸入確認  留空/其他=音量鍵選擇)
keyboard_input="${keyboard_input:-}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#腳本語言設置 留空則自動識別系統語言環境並翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#備份開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#自定義備份文件輸出位置 支持相對路徑(留空則默認當前路徑)
Output_path=\""$Output_path"\"

#自定義備份目錄後綴(留空則不添加後綴)
#支持日期時間變量：%yyyymmdd %hhmmss %yyyymmddhhmmss %yyyy %mm %dd
#例：_daily  → Backup_zstd_0_daily
#例：_%yyyymmdd  → Backup_zstd_0_20260522
Backup_suffix=\""$Backup_suffix"\"

#自定義applist.txt位置 支持相對路徑(留空則默認當前路徑)
list_location=\""$list_location"\"

#自動更新腳本(留空強制選擇)
#1開啟 0關閉
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#自定義屏蔽外部掛載點 例：OTG 虛擬SD等 多個掛載點請使用 | 區隔
#屏蔽後不會提示音量鍵選擇，不影響Output_path指定外置存儲位置
mount_point=\""${mount_point:-rannki|0000-1}"\"

#使用者(如0 999等用戶，如存在多個用戶留空強制選擇，無多個用戶則默認用戶0不詢問)
user="$user"

#備份模式
#1包含數據+安裝包，0僅包安裝包
#此選項設置1時Backup_obb_data，Backup_user_data，blacklist_mode將可設置 0時Backup_user_data，Backup_obb_data，blacklist_mode選項不生效
#此外設置0時將同時忽略appList.txt的!與任何黑名單設置（包括黑名單列表）
Backup_Mode="${Backup_Mode:-1}"

#是否備份使用者數據 (1備份 0不備份 留空強制選擇)
Backup_user_data="${Backup_user_data:-1}"

#是否備份外部數據 例：原神的數據包(1備份 0不備份 留空強制選擇)
Backup_obb_data="${Backup_obb_data:-1}"

#是否在應用數據備份完成後備份自定義目錄
#1開啟 0關閉
backup_media="${backup_media:-0}"

#存在進程忽略備份(1忽略0備份)
Background_apps_ignore="${Background_apps_ignore:-0}"

#添加自定義備份路徑 例：Download DCIM等文件夾 請使用絕對路徑，請勿刪除\"\"
Custom_path=\""$Custom_path"\"

#黑名單模式(1完全忽略，不備份  0僅備份安裝包，注意！此選項Backup_Mode=1時黑名單模式才能使用)
blacklist_mode="${blacklist_mode:-0}"

#備份黑名單（備份策略由「黑名單模式」控制，此處只作為黑名單應用列表）
blacklist=\""${blacklist:-
#com.esunbank
#com.chailease.tw.app.android.ccfappcust}"\"

#位於data的預裝應用白名單 例：相冊 錄音機 天氣 計算器等(默認屏蔽備份預裝應用，如需備份請添加預裝應用白名單)
whitelist=\""${whitelist:-
com.xiaomi.xmsf
com.xiaomi.xiaoailite
com.xiaomi.hm.health
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
com.xiaomi.router
com.xiaomi.mico
dev.miuiicons.pedroz}"\"

#可被備份的系統應用白名單(默認屏蔽備份系統應用，如需備份請添加系統應用白名單)
system=\""${system:-
com.google.android.calendar
com.google.android.gm
com.google.android.googlequicksearchbox
com.google.android.tts
com.google.android.apps.maps
com.google.android.apps.messaging
com.google.android.inputmethod.latin
com.instagram.android
com.facebook.orca
sh.siava.AOSPMods
com.facebook.katana
com.android.chrome}"\"

#壓縮算法(可用zstd tar，tar為僅打包 有什麼好用的壓縮算法請聯系我
#zstd擁有良好的壓縮率與速度
Compression_method=${Compression_method:-zstd}

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"

#遠程備份類型 (留空不啟用)
#推薦 webdav (穩定)
#smb 支援 SMB2/SMB3 (本腳本拒絕 SMB1/CIFS, 會自動協商到伺服器支援的最高版本)
remote_type="${remote_type:-}"
# 保存原始值, 供連線失敗後 (如中途開 WiFi) 重新檢測用
_remote_type_orig="$remote_type"

#遠程地址 (兩種協議分開設定, 切換 remote_type 免重輸)
#SMB例:    smb://192.168.1.100/backup/
smb_url="${smb_url:-}"
#認證用戶名
smb_remote_user="${smb_remote_user:-}"
#認證密碼
smb_remote_pass=\""$smb_remote_pass"\"
#WebDAV例: http://192.168.1.100:8080/dav/
webdav_url="${webdav_url:-}"
#認證用戶名
webdav_remote_user="${webdav_remote_user:-}"
#認證密碼
webdav_remote_pass=\""$webdav_remote_pass"\"

#流式上傳 (邊壓邊傳, 不佔本機空間)
#1 開啟流式: 數據直接壓縮→管道傳到遠端, 本機不留 tar (省空間, 全量上傳, 不做本機校驗/增量)
#0 關閉(預設): 先壓到本機→校驗→再上傳 (保留本機檔案, 支援增量)
#支援 smb / webdav 兩種 remote_type
remote_stream="${remote_stream:-0}"

#流式上傳除錯 (1=失敗時印出 smbclient/curl 的具體錯誤, 用於排查流式失敗原因)
_stream_debug="${_stream_debug:-0}"
_INCREMENTAL_DEBUG="${_INCREMENTAL_DEBUG:-0}"

#遠程備份完成後是否保留本地檔案
#1保留本地檔案(上傳後不刪除) 0上傳成功後刪除本地檔案
remote_keep_local="${remote_keep_local:-0}"

#邊備份邊上傳 (每備份完一個應用立即上傳，然後刪除本機檔案再備份下一個，以節省本機空間)
#1 開啟 0 關閉
#開啟後：每個應用備份完成 → 立即上傳遠端 → 上傳成功後刪除本機檔案 → 繼續備份下一個
#關閉後：先備份所有應用 → 全部備份完再統一上傳
remote_upload_per_app="${remote_upload_per_app:-0}"

#log 目錄大小上限 (單位 MB), 達到上限會在啟動時自動清空 log/
#留空或設 0 = 關閉自動清理
log_max_size_mb="${log_max_size_mb:-}"
" | sed '
	/^Custom_path/ s/ /\n/g;
	/^blacklist/ s/ /\n/g;
	/^whitelist/ s/ /\n/g;
	/^system/ s/ /\n/g;
	/^am_start/ s/ /\n/g;
	s/true/1/g;
	s/false/0/g'
}
# 產生 restore_settings.conf 的內容模板 (寫到 stdout)
# 備份完成時呼叫此函數寫入備份目錄,讓恢復端有獨立的設定檔
update_Restore_settings_conf() {
	echo "#低電量提示 (電量≤15%且未充電時的行為)
#1低電量強制拒絕操作  2無需提示繼續執行  留空音量鍵選擇 (音量上=無視風險繼續操作, 音量下=退出)
low_battery_mode="${low_battery_mode:-}"

#輸入方式 (1=改用鍵盤輸入確認  留空/其他=音量鍵選擇)
keyboard_input="${keyboard_input:-}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#恢復開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#腳本語言設置 為空自動針對當前系統語言環境自動翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#自動更新腳本(留空強制選擇)
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#恢復模式(1恢復未安裝應用 0全恢復)
recovery_mode="${recovery_mode:-0}"

#恢復資料夾
media_recovery="${media_recovery:-0}"

#存在進程忽略恢復(1忽略0恢復)
Background_apps_ignore="${Background_apps_ignore:-0}"

#使用者(如0 999等用戶，留空如存在多個用戶強制音量鍵選擇，無多用戶則默認0不詢問)
user="$user"

#log 目錄大小上限 (單位 MB), 達到上限會在啟動時自動清空 log/
#留空或設 0 = 關閉自動清理
log_max_size_mb="${log_max_size_mb:-}"

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"" | sed 's/true/1/g ; s/false/0/g'
}
if [[ ! -d $tools_path ]]; then
	tools_path="${MODDIR%/*}/tools"
	[[ ! -d $tools_path ]] && echo "$tools_path二進制目錄遺失" && EXIT="true"
fi
# 根據當前 conf_path 判斷類型,觸發對應模板重新寫入
# 用於腳本版本升級時自動補齊新增的設定欄位
_update_conf() {
	case $conf_path in
	*backup_settings.conf)  update_backup_settings_conf>"$conf_path" ;;
	*restore_settings.conf) update_Restore_settings_conf>"$conf_path" ;;
	*) echo "$conf_path配置遺失" && exit 1 ;;
	esac
}
if [[ ! -f $conf_path ]]; then
	_update_conf
	echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
fi
. "$conf_path" &>/dev/null
_update_conf
# 依 remote_type 取對應遠端位址/帳密 (smb_*/webdav_* 由 conf 設定)
case $remote_type in
smb) remote_url="$smb_url"; remote_user="$smb_remote_user"; remote_pass="$smb_remote_pass" ;;
webdav) remote_url="$webdav_url"; remote_user="$webdav_remote_user"; remote_pass="$webdav_remote_pass" ;;
*) remote_url=""; remote_user=""; remote_pass="" ;;
esac
case $Shell_LANG in
1) SCRIPT_LANG="CN" ;;
0) SCRIPT_LANG="TW" ;;
*)
	_l="$(settings get system system_locales 2>/dev/null | head -1)"
	[[ -z $_l || $_l = null ]] && _l="$(getprop persist.sys.locale)"
	case $_l in
	zh-Hant*|zh_Hant*|zh-TW*|zh-HK*|zh-MO*) SCRIPT_LANG="TW" ;;
	zh-Hans*|zh_Hans*|zh-CN*|zh-SG*|zh*)    SCRIPT_LANG="CN" ;;
	esac
	;;
esac
# ======================================================
# 基礎工具函數
# ======================================================
# 帶色彩輸出, 用法: echoRgb "訊息" [色碼]
# 色碼:
#   0 = 紅色 (197)    - 錯誤/警告
#   1 = 亮綠 (121)    - 成功
#   2 = rgb_c (213)   - 強調/變數值 (粉紅, 預設)
#   3 = rgb_b (51)    - 提示/進度 (亮青, 預設)
#   其他/省略 = rgb_a (220) - 一般資訊 (亮黃, 預設)
# rgb_a/b/c 可在 conf 自訂, 全部都是 256 色 ANSI 編號
echoRgb() {
	local color
	case $2 in
	0) color=197 ;;
	1) color=121 ;;
	2) color=$rgb_c ;;
	3) color=$rgb_b ;;
	*) color=$rgb_a ;;
	esac
	echo -e "\e[38;5;${color}m -$1\e[0m"
}

# JSON 原地更新 helper (取代 jq...>tmp...cat>...rm 模式)
# 用法: jq_inplace <檔案> <jq 表達式> [額外參數...]
# 例: jq_inplace "$app_details" --arg k "key" '.[$k] = "value"'
# 注意: 用 cat 寫回而不是 mv, 因為 Android 跨檔案系統 mv 會嘗試 setfilecon
# (sdcard 不支援會印 "Operation not supported on transport endpoint" 錯誤)
jq_inplace() {
	local file="$1"; shift
	local tmp="$TMPDIR/.jq_$$"
	if jq "$@" "$file" > "$tmp"; then
		cat "$tmp" > "$file"
		rm -f "$tmp"
	else
		rm -f "$tmp"
		return 1
	fi
}

# 計算目錄總大小 (bytes), 純文件字節和 (對應電腦端「大小」)
# 用法: calc_dir_size <目錄路徑>
# 依功能類型顯示相關 conf 設定
# 遠端狀態片段 (供備份類附加顯示); 有啟用才顯示細節
remote_conf_line() {
	if [[ -n $remote_type ]]; then
		if [[ $remote_stream = 1 ]]; then
			echo "\n -遠端上傳:$remote_type ($remote_url)\n -流式上傳:開啟 (不佔本機)"
		else
			echo "\n -遠端上傳:$remote_type ($remote_url)\n -保留本地檔:$remote_keep_local"
		fi
	else
		echo "\n -遠端上傳:未啟用"
	fi
}
show_conf() {
	case $1 in
	backup)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -更新:$update\n -備份模式:$Backup_Mode\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -黑名單模式:$blacklist_mode\n -黑名單:$(awk '!/[#＃]/ && NF' <<< "$blacklist" | grep -c . 2>/dev/null)個\n -白名單:$(awk '!/[#＃]/ && NF' <<< "$whitelist" | grep -c . 2>/dev/null)個\n -自定義目錄備份:$backup_media\n -存在進程忽略備份:$Background_apps_ignore\n -關閉螢幕:$setDisplayPowerMode$(remote_conf_line)" ;;
	media)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -自定義路徑:$Custom_path\n -關閉螢幕:$setDisplayPowerMode$(remote_conf_line)" ;;
	wifi)
		echoRgb "配置詳細:\n -關閉螢幕:$setDisplayPowerMode$(remote_conf_line)" ;;
	remote)
		echoRgb "配置詳細:\n -遠端類型:${remote_type:-未設定}\n -遠端位址:${remote_url:-未設定}\n -保留本地檔:$remote_keep_local" ;;
	restore)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -關閉螢幕:$setDisplayPowerMode" ;;
	esac
}
calc_dir_size() {
	# 純文件字節總和 (對應電腦端「大小」, 不含目錄項佔用); 單一 find 進程
	find "$1" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1}END{print s+0}'
}

# 查預掃的目錄大小表 (.dir_sizes, 由 prepare_dir_size_map 並行算好)
# 用法: _dir_size <pkg> <type> <目錄路徑>  — 表中有則秒回, 無則現算(兜底)
_dir_size() {
	local _p="$1" _t="$2" _path="$3" _vn
	_DIR_SIZE_RET=""
	# 零 fork 組變量名 (內建展開轉義)
	_vn="_sz_${_p//[!a-zA-Z0-9]/_}_${_t//[!a-zA-Z0-9]/_}"
	# 防呆: 變量名只含合法字元才 eval (避免殘留 . 等造成 bad substitution); 否則現算
	case $_vn in
		*[!a-zA-Z0-9_]*) ;;  # 含非法字元 → 跳過查表, 走 fallback
		*) eval "_DIR_SIZE_RET=\${$_vn:-}" 2>/dev/null ;;
	esac
	[[ -n $_DIR_SIZE_RET ]] && return
	_DIR_SIZE_RET="$(calc_dir_size "$_path")"
}
# 把 .dir_sizes 一次載入成動態變量 _sz_<pkg轉義>_<type>=size (取代每次 fork awk, 手機 fork 成本高)
load_dir_size_map() {
	[[ ! -f $TMPDIR/.dir_sizes ]] && return
	local _pk _ty _sz _vn
	while IFS=$'\t' read -r _pk _ty _sz; do
		[[ -z $_pk ]] && continue
		_vn="_sz_${_pk//[!a-zA-Z0-9]/_}_$_ty"
		eval "$_vn=\$_sz"
	done < "$TMPDIR/.dir_sizes"
}
# 將 $name1 寫入 .changed_apps (去重, 避免重複記錄)
_mark_changed() {
	awk -v n="$name1" 'BEGIN{f=0} $0==n{f=1;exit} END{if(!f)print n}' \
		"$TMPDIR/.changed_apps" 2>/dev/null >> "$TMPDIR/.changed_apps"
}
# 通用: 把 pkg<TAB>value 表載入成動態變量 <prefix>_<pkg轉義>=value (零 fork 查詢)
# 用法: load_kv_map <檔案> <變量前綴>
load_kv_map() {
	[[ ! -f $1 ]] && return
	local _pk _val _vn _pfx="$2"
	while IFS=$'\t' read -r _pk _val; do
		[[ -z $_pk ]] && continue
		_vn="${_pfx}_${_pk//[!a-zA-Z0-9]/_}"
		eval "$_vn=\$_val"
	done < "$1"
}
# 通用查詢: _kv_get <變量前綴> <pkg>  → 印出值 (零 fork)
_kv_get() {
	local _vn="$1_${2//[!a-zA-Z0-9]/_}" _v
	eval "_v=\${$_vn}"
	echo "$_v"
}

# 壓縮 helper (取代散落各處的 tar/zstd case 分支)
# 用法 1 (目錄打包): tar_compress_dir <輸出檔基礎名> <切到目錄> <要打包名> [tar 額外參數...]
#   例: tar_compress_dir "$folder/user" "${dp%/*}" "${dp##*/}" --exclude=cache
# 用法 2 (glob 打包): tar_compress_glob <輸出檔基礎名> <切到目錄> <glob 模式>
#   例: tar_compress_glob "$folder/apk" "$apk_path2" "*.apk"
# 自動依 $Compression_method 決定輸出 .tar 還是 .tar.zst
# 若呼叫前設了局部變數 _comp_override, 優先使用它 (取代暫時修改全域 Compression_method 再復原的舊做法)
tar_compress_dir() {
	local out_base="$1" cd_to="$2" pack_name="$3"
	shift 3
	local _comp="${_comp_override:-$Compression_method}"
	# 流式模式 (remote_stream=1): 直接管道到遠端, 不寫本機 (省空間)
	# _STREAM_DEST 由呼叫端設為遠端目標目錄 (相對遠端根)
	if [[ $remote_stream = 1 && -n $_STREAM_DEST ]]; then
		echoRgb "流式傳輸中 (邊壓邊傳, 不佔本機)..." "3" >&2
		local _rb="$_STREAM_DEST/${out_base##*/}"
		[[ ! -d ${out_base%/*} ]] && mkdir -p "${out_base%/*}" 2>/dev/null
		case $_comp in
		tar|Tar|TAR)
			tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
				"$@" -cpf - -C "$cd_to" "$pack_name" | _stream_upload "$_rb.tar"
			;;
		zstd|Zstd|ZSTD)
			tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
				"$@" -cpf - -C "$cd_to" "$pack_name" | \
				zstd --ultra -3 -T0 -q --priority=rt | _stream_upload "$_rb.tar.zst"
			;;
		esac
		result=$?
		if [[ $result != 0 ]]; then
			echoRgb "流式上傳失敗 ($_rb) 遠端可能未寫入完整, 建議重試" "0" >&2
			echo "${_rb%%/*}" >> "$TMPDIR/.stream_failed"
		else
			_manifest_add "$_rb"
		fi
		return $result
	fi
	case $_comp in
	tar|Tar|TAR)
		tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
			"$@" -cpf "$out_base.tar" -C "$cd_to" "$pack_name"
		;;
	zstd|Zstd|ZSTD)
		tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
			"$@" -cpf - -C "$cd_to" "$pack_name" | \
			zstd --ultra -3 -T0 -q --priority=rt > "$out_base.tar.zst"
		;;
	esac
	result=$?
	chmod 0777 "$out_base.tar" "$out_base.tar.zst" 2>/dev/null
	[[ $result = 0 ]] && _manifest_add "${out_base#$Backup/}"
	return $result
}
# 記錄本次成功備份的檔案 (相對路徑不含副檔名, 例 1DM+/apk), 供結尾計數核驗
_manifest_add() {
	[[ -z $1 ]] && return
	if ! awk -v p="$1" '$0==p{f=1} END{exit !f}' "$TMPDIR/.backup_manifest" 2>/dev/null; then
		echo "$1" >> "$TMPDIR/.backup_manifest"
	fi
}

# json 健全度檢查: 檢查 app_details.json 是否含必要欄位
# 用法: _json_health_check <json路徑> <app顯示名>
# 必要欄位 (缺即視為異常, 會影響恢復/識別): PackageName, apk_version
# permissions/notification_settings/battery_opt/battery_settings/Ssaid 不是每個app都一定會產生 (取決於該app是否申請過runtime權限/
# 是否曾查到電池策略/是否使用裝置識別碼), 缺不代表異常, 單獨歸入弱提示
# 結果: 異常訊息 append 到 $TMPDIR/.json_health_issues, 弱提示 append 到 $TMPDIR/.json_health_hints
_json_health_check() {
	local _file="$1" _name="$2" _pkg _ver _has_perm _has_batt _has_notify _has_ssaid _issues="" _hints=""
	[[ ! -s $_file ]] && { echo "$_name: app_details.json 不存在或為空" >> "$TMPDIR/.json_health_issues"; return; }
	if ! jq -e . "$_file" >/dev/null 2>&1; then
		echo "$_name: json 格式損壞 (無法解析)" >> "$TMPDIR/.json_health_issues"
		return
	fi
	_pkg="$(jq -r 'try ([.[] | objects | select(.PackageName != null).PackageName] | .[0]) catch "" // ""' "$_file" 2>/dev/null)"
	_ver="$(jq -r 'try ([.[] | objects | select(.apk_version != null).apk_version] | .[0]) catch "" // ""' "$_file" 2>/dev/null)"
	_has_perm="$(jq -r 'try ([.[] | objects | select(.permissions != null)] | length) catch 0' "$_file" 2>/dev/null)"
	_has_batt="$(jq -r 'try ([.[] | objects | select(.battery_opt != null or .battery_settings != null)] | length) catch 0' "$_file" 2>/dev/null)"
	_has_notify="$(jq -r 'try ([.[] | objects | select(.notification_settings != null)] | length) catch 0' "$_file" 2>/dev/null)"
	_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_file" 2>/dev/null)"
	[[ -z $_pkg ]] && _issues="$_issues 缺PackageName"
	[[ -z $_ver ]] && _issues="$_issues 缺apk_version"
	# 新增欄位型態檢查：有欄位但不是 object，恢復端會讀取異常，視為嚴重問題
	if ! jq -e 'try all(.[] | objects | select(.permissions != null); (.permissions | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues permissions非object"
	fi
	if ! jq -e 'try all(.[] | objects | select(.notification_settings != null); (.notification_settings | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues notification_settings非object"
	fi
	if ! jq -e 'try all(.[] | objects | select(.battery_settings != null); (.battery_settings | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues battery_settings非object"
	fi
	# notification_settings key 格式檢查：只允許 NOTIFY_APP / NOTIFY_CHANNEL / NOTIFY_GROUP
	local _bad_notify_keys
	_bad_notify_keys="$(jq -r '
		try [
			.[] | objects | select(.notification_settings != null)
			| .notification_settings
			| to_entries[]
			| select((.key | startswith("NOTIFY_APP:") or startswith("NOTIFY_CHANNEL:") or startswith("NOTIFY_GROUP:")) | not)
			| .key
		] | unique | join(",") catch ""
	' "$_file" 2>/dev/null)"
	[[ -n $_bad_notify_keys ]] && _issues="$_issues notification_settings未知key($_bad_notify_keys)"
	# battery_settings key/value 格式檢查
	# 合法 key:
	#   BATTERY:RUN_IN_BACKGROUND        "63 0 allow" 或 "0" 或 "allow"
	#   BATTERY:RUN_ANY_IN_BACKGROUND    "70 0 allow" 或 "0" 或 "allow"
	#   BATTERY:deviceidle_whitelist     true/false
	local _bad_batt_keys _bad_batt_vals
	_bad_batt_keys="$(jq -r '
		try [
			.[] | objects | select(.battery_settings != null)
			| .battery_settings
			| to_entries[]
			| select((.key == "BATTERY:RUN_IN_BACKGROUND" or .key == "BATTERY:RUN_ANY_IN_BACKGROUND" or .key == "BATTERY:deviceidle_whitelist" or .key == "BATTERY:idle_whitelist" or .key == "BATTERY:doze_whitelist") | not)
			| .key
		] | unique | join(",") catch ""
	' "$_file" 2>/dev/null)"
	[[ -n $_bad_batt_keys ]] && _issues="$_issues battery_settings未知key($_bad_batt_keys)"
	_bad_batt_vals="$(jq -r '
		def batt_mode_ok:
			(type == "string") and
			(
				test("^[0-9]+( [0-9]+ [A-Za-z_]+)?$") or
				test("^(allow|allowed|ignore|ignored|deny|denied|errored|default|foreground|true|false)$"; "i")
			);
		try [
			.[] | objects | select(.battery_settings != null)
			| .battery_settings
			| to_entries[]
			| select(
				if (.key == "BATTERY:deviceidle_whitelist" or .key == "BATTERY:idle_whitelist" or .key == "BATTERY:doze_whitelist") then
					((.value | tostring) | test("^(true|false)$"; "i") | not)
				elif (.key == "BATTERY:RUN_IN_BACKGROUND" or .key == "BATTERY:RUN_ANY_IN_BACKGROUND") then
					((.value | tostring) | batt_mode_ok | not)
				else
					false
				end
			)
			| "\(.key)=\(.value)"
		] | unique | join(",") catch ""
	' "$_file" 2>/dev/null)"
	[[ -n $_bad_batt_vals ]] && _issues="$_issues battery_settings值異常($_bad_batt_vals)"
	[[ -n $_issues ]] && echo "$_name:$_issues" >> "$TMPDIR/.json_health_issues"
	# 弱提示: 不視為異常，只是告知該欄位沒有紀錄
	[[ ${_has_perm:-0} -eq 0 ]] && _hints="$_hints 無permissions"
	[[ ${_has_notify:-0} -eq 0 ]] && _hints="$_hints 無notification_settings"
	[[ ${_has_batt:-0} -eq 0 ]] && _hints="$_hints 無battery_opt/battery_settings"
	[[ ${_has_ssaid:-0} -eq 0 ]] && _hints="$_hints 無Ssaid"
	[[ -n $_hints ]] && echo "$_name:$_hints" >> "$TMPDIR/.json_health_hints"
}
# 彙整顯示 json 健全度檢查結果 (呼叫端在所有 _json_health_check 跑完後呼叫一次)
_json_health_report() {
	local _has_hints=0
	[[ -s $TMPDIR/.json_health_hints ]] && _has_hints=1
	if [[ -s $TMPDIR/.json_health_issues || $_has_hints = 1 ]]; then
		echoRgb "—————— JSON健全度檢查 ——————" "3"
	fi
	if [[ -s $TMPDIR/.json_health_issues ]]; then
		local _cnt
		_cnt="$(grep -vc '^$' "$TMPDIR/.json_health_issues" 2>/dev/null)"
		echoRgb "⚠️ 發現 $_cnt 個app的app_details.json缺少必要欄位:" "0"
		while read -r _line; do
			[[ -n $_line ]] && echoRgb "$_line" "0"
		done < "$TMPDIR/.json_health_issues"
		echoRgb "上述app建議重新執行一次備份以補全資訊" "0"
		rm -f "$TMPDIR/.json_health_issues"
	fi
	if [[ $_has_hints = 1 ]]; then
		local _hcnt
		_hcnt="$(grep -vc '^$' "$TMPDIR/.json_health_hints" 2>/dev/null)"
		echoRgb "$_hcnt 個app有部分次要欄位未紀錄 (可能該app本來就沒有, 非異常):" "2"
		while read -r _hline; do
			[[ -n $_hline ]] && echoRgb "$_hline" "2"
		done < "$TMPDIR/.json_health_hints"
		rm -f "$TMPDIR/.json_health_hints"
	fi
}

# 最終檔案計數核驗: 本次備份的檔案逐一確認存在 (本地 [[ -f ]] / 遠端流式下載驗證), 顯示數量
verify_backup_manifest() {
	[[ ! -s $TMPDIR/.backup_manifest ]] && return
	local _mf="$TMPDIR/.backup_manifest" _ext _expect _found=0 _miss=""
	case $Compression_method in
	zstd|Zstd|ZSTD) _ext=".tar.zst" ;;
	*) _ext=".tar" ;;
	esac
	_expect="$(grep -vc '^$' "$_mf")"
	echoRgb "—————— 最終檔案計數核驗 ——————" "3"
	local _remote_chk=0
	if [[ $remote_stream = 1 ]]; then
		_remote_chk=1
	elif [[ -n $remote_type && $remote_keep_local != true ]]; then
		_remote_chk=1
	fi
	if [[ $_remote_chk = 1 ]]; then
		# 遠端核驗: 重抓一次遠端列表 (單連線), 逐項比對存在性
		echoRgb "核驗遠端檔案 (單次列表)..." "3"
		local _vlist="$TMPDIR/.verify_files"
		remote_list_files "$(get_backup_dirname)" > "$_vlist" 2>/dev/null
		local _rel _head
		while read -r _rel; do
			[[ -z $_rel ]] && continue
			if ! awk -v a="$_rel$_ext" -v b="$_rel.tar" '$0==a||$0==b{f=1;exit} END{exit !f}' "$_vlist" 2>/dev/null; then
				# 列表沒找到: 單檔下載開頭再確認一次 (smbclient 列表對中文名轉碼毀名, 避免誤報)
				_head="$(_stream_download "$(get_backup_dirname)/$_rel$_ext" 2>/dev/null | head -c 60)"
				case $_head in
				""|*NT_STATUS*) _miss="$_miss$_rel$_ext\n" ;;
				esac
			fi
		done <<EOF3
$(cat "$_mf")
EOF3
		_miss="$(echo -e "$_miss" | grep -v '^$')"
		rm -f "$_vlist"
	else
		# 本地核驗
		local _rel
		while read -r _rel; do
			[[ -z $_rel ]] && continue
			if [[ ! -f $Backup/$_rel.tar.zst && ! -f $Backup/$_rel.tar ]]; then
				_miss="$_miss$_rel$_ext\n"
			fi
		done <<EOF3
$(cat "$_mf")
EOF3
		_miss="$(echo -e "$_miss" | grep -v '^$')"
	fi
	local _misscnt
	_misscnt="$(echo "$_miss" | grep -vc '^$')"
	_found=$((_expect - _misscnt))
	if [[ $_misscnt -eq 0 ]]; then
		echoRgb "✅ 應有 $_expect 個檔案, 實際存在 $_expect 個" "1"
	else
		echoRgb "⚠️ 應有 $_expect 個檔案, 實際存在 $_found 個, 缺失 $_misscnt 個:" "0"
		echo "$_miss" | while read -r _m; do [[ -n $_m ]] && echoRgb "$_m" "0"; done
	fi
	rm -f "$_mf"
}

tar_compress_glob() {
	local out_base="$1" cd_to="$2" pattern="$3"
	# 第4參數可選: 覆寫本次使用的壓縮方式 (不傳則用全域 Compression_method)
	# 讓呼叫端可以針對單次打包指定方式, 不需要暫時修改全域變數再復原
	local _comp="${4:-$Compression_method}"
	# 流式模式
	if [[ $remote_stream = 1 && -n $_STREAM_DEST ]]; then
		echoRgb "流式傳輸中 (邊壓邊傳, 不佔本機)..." "3" >&2
		local _rb="$_STREAM_DEST/${out_base##*/}"
		[[ ! -d ${out_base%/*} ]] && mkdir -p "${out_base%/*}" 2>/dev/null
		(
			cd "$cd_to" || return 1
			case $_comp in
			tar|Tar|TAR)
				tar --checkpoint-action="ttyout=%T\r" -cf - $pattern | _stream_upload "$_rb.tar"
				;;
			zstd|Zstd|ZSTD)
				tar --checkpoint-action="ttyout=%T\r" -cf - $pattern | \
					zstd --ultra -3 -T0 -q --priority=rt | _stream_upload "$_rb.tar.zst"
				;;
			esac
		)
		result=$?
		if [[ $result != 0 ]]; then
			echoRgb "流式上傳失敗 ($_rb) 遠端可能未寫入完整, 建議重試" "0" >&2
			echo "${_rb%%/*}" >> "$TMPDIR/.stream_failed"
		else
			_manifest_add "$_rb"
		fi
		return $result
	fi
	(
		cd "$cd_to" || return 1
		case $_comp in
		tar|Tar|TAR)
			tar --checkpoint-action="ttyout=%T\r" -cf "$out_base.tar" $pattern
			;;
		zstd|Zstd|ZSTD)
			tar --checkpoint-action="ttyout=%T\r" -cf - $pattern | \
				zstd --ultra -3 -T0 -q --priority=rt > "$out_base.tar.zst"
			;;
		esac
	)
	result=$?
	chmod 0777 "$out_base.tar" "$out_base.tar.zst" 2>/dev/null
	[[ $result = 0 ]] && _manifest_add "${out_base#$Backup/}"
	return $result
}

rgb_a="${rgb_a:=220}"
abi="$(getprop ro.product.cpu.abi)"
sdk="$(getprop ro.build.version.sdk)"
release="$(getprop ro.build.version.release)"
case $abi in
arm64*)
	if [[ $sdk -lt 24 ]]; then
		echoRgb "設備Android ${release}版本過低 請升級至Android 8+" "0"
		exit 1
	else
		case $sdk in
		26|27|28)
			echoRgb "設備Android ${release}版本偏低，無法確定腳本能正確的使用" "0"
			;;
		esac
	fi
	;;
*)
	echoRgb "未知的架構: $abi" "0"
	exit 1
	;;
esac
get_mv="$(which mv)"
PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:/sbin/.magisk/busybox:/sbin/.magisk:/sbin:/system_ext/bin:/vendor/bin:/vendor/xbin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
# 先查 magisk 二進制是否存在, 避免直接呼叫導致 libc 雜訊 (小米系統 vendor 屬性權限警告)
if command -v magisk >/dev/null 2>&1; then
	_magisk_path="$(magisk --path 2>/dev/null)"
	if [[ -d $_magisk_path ]]; then
		PATH="$_magisk_path/.magisk/busybox:$PATH"
	fi
elif ! command -v ksud >/dev/null 2>&1; then
	echo "Magisk busybox Path does not exist"
fi
export PATH="$PATH"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$tools_path/busybox"
#排除自身
exclude="
update
soc.json
classes.dex
Device_List"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echoRgb "設置busybox環境中"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -f $busybox && -f $busybox2 ]]; then
	filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
	filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
	if [[ $filesha256 != $filesha256_1 ]]; then
		echoRgb "busybox sha256不一致 重新創立環境中"
		rm -rf "$filepath"/*
	fi
fi
find "$tools_path" -maxdepth 1 ! -path "$tools_path/tools.sh" -type f | grep -Ev "$(echo $exclude | sed 's/ /\|/g')" | while read -r; do
	File_name="${REPLY##*/}"
	if [[ ! -f $filepath/$File_name ]]; then
		cp -r "$REPLY" "$filepath"
		chmod 0777 "$filepath/$File_name"
		echoRgb "$File_name > $filepath/$File_name"
	else
		filesha256="$(sha256sum "$filepath/$File_name" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$tools_path/$File_name" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echoRgb "$File_name sha256不一致 重新創建"
			cp -r "$REPLY" "$filepath"
			chmod 0777 "$filepath/$File_name"
			echoRgb "$File_name > $filepath/$File_name"
		fi
	fi
done
if [[ -f $busybox ]]; then
	"$busybox" --list | while read -r; do
		if [[ $REPLY != tar && $REPLY != bc && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
fi
[[ ! -f $filepath/zstd ]] && echoRgb "$filepath缺少zstd" && exit 2
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei
ln -fs "$tools_path/classes.dex" "$filepath/classes.dex"
export CLASSPATH="$filepath/classes.dex"
quit=0
while read -r file expected_hash; do
	if [[ -f $tools_path/$file ]]; then
		computed_hash="$(sha256sum "$tools_path/$file" | awk '{print $1}')"
		if [[ $computed_hash = $expected_hash ]]; then
			echoRgb "✅ $file: 驗證通過"
		else
			echoRgb "❌ $tools_path/$file: SHA-256 不一致\n -\"$computed_hash\""
			# smbclient/curl 不一致 → 只是不能用遠端, 不致命
			case $file in
			smbclient|curl) ;;
			*) quit=2; break ;;
			esac
		fi
	else
		# smbclient/curl 缺失 → 只是不能用遠端, 不致命
		case $file in
		smbclient)
			echoRgb "⚠️ 檔案 $tools_path/$file 不存在 (僅影響 SMB 遠端備份)" "0"
			;;
		curl)
			echoRgb "⚠️ 檔案 $tools_path/$file 不存在 (僅影響 WebDAV 遠端備份)" "0"
			;;
		*)
			echoRgb "⚠️ 檔案 $tools_path/$file 不存在"
			quit=1
			break
			;;
		esac
	fi
done <<EOF
zstd 9ef4b54148699c9874cfd45aaf38e5cc950e5d168afdcf2edf58a2463f5561ed
tar 882639ac310a7eb4052c68c21cea02633307700f9cc8c7c469c2dd18d734a112
classes.dex 14a6dc6a60a56595a1cec2227f5fb7aa14f6d034990b3081749145f01ac38ccd
busybox 4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651
find 7fa812e58aafa29679cf8b50fc617ecf9fec2cfb2e06ea491e0a2d6bf79b903b
jq 6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
keycheck 50645ee0e0d2a7d64fb4a1286446df7a4445f3d11aefd49eeeb88515b314c363
cmd 08da8ac23b6e99788fd3ce6c19c7b5a083b2ad48be35963a48d01d6ee7f3bb6d
smbclient 0fe8aa0abcf2ab81387d25dfb4a47369925e475bcf0c32acc9846753775ec35e
curl c78079c0239f0a6c44aa7e9180f97d4c3d175495d1ccf565a8854abd15f68b60
EOF

# log 目錄超過上限就清空 (避免長期累積佔空間)
# 上限由 conf 的 log_max_size_mb 控制 (預設 2MB, 0=關閉)
# 清理範圍:
#   - ${logfile%/*}/                                 (主腳本)
#   - $MODDIR/Backup_*/log/                        (備份模式)
#   - $MODDIR/Backup_*/*/log/                      (子目錄)
#   - ${logfile%/*}/ (恢復模式, MODDIR 是 Backup_zstd_X)
cleanup_log_if_oversize() {
	# conf 沒設置 (空值) 也不清, 只有明確設正整數才啟用
	local max="$log_max_size_mb"
	[[ -z $max || $max = 0 ]] && return 0
	case $max in
	*[!0-9]*) return 0 ;;  # 非純數字直接跳過
	esac
	local max_kb=$((max * 1024))
	local d size_kb
	for d in "$MODDIR/log" "$MODDIR"/Backup_*/log "$MODDIR"/Backup_*/*/log; do
		[[ ! -d $d ]] && continue
		[[ -z $(ls -A "$d" 2>/dev/null) ]] && continue
		size_kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
		if [[ ${size_kb:-0} -ge $max_kb ]]; then
			rm -rf "$d"/*
			echoRgb "log 目錄 $d 超過 ${max}MB, 已清空" "3"
		fi
	done
}

# 打印 tools 目錄內所有二進制版本到 log/tools_version.log
# 啟動時跑一次, 方便除錯時知道用戶用什麼版本工具
print_tools_version() {
	local _ver_log="${logfile%/*}/tools_version.log"
	mkdir -p "${logfile%/*}" 2>/dev/null
	{
		echo "===== Tools version on $(date '+%Y-%m-%d %H:%M:%S') ====="
		echo "abi=$abi sdk=$sdk release=$release"
		echo ""
		# zstd
		which zstd >/dev/null 2>&1 && {
			echo "[zstd]"
			zstd --version 2>&1 | head -2
			echo ""
		}
		# tar
		which tar >/dev/null 2>&1 && {
			echo "[tar]"
			tar --version 2>&1 | head -2
			echo ""
		}
		# busybox
		which busybox >/dev/null 2>&1 && {
			echo "[busybox]"
			busybox 2>&1 | head -1
			echo ""
		}
		# jq
		which jq >/dev/null 2>&1 && {
			echo "[jq]"
			jq --version 2>&1
			echo ""
		}
		# find
		which find >/dev/null 2>&1 && {
			echo "[find]"
			find --version 2>&1 | head -1
			echo ""
		}
		# curl
		which curl >/dev/null 2>&1 && {
			echo "[curl]"
			curl --version 2>&1 | head -3
			echo ""
		}
		# smbclient
		which smbclient >/dev/null 2>&1 && {
			echo "[smbclient]"
			smbclient --version 2>&1 | head -1
			echo ""
		}
		# keycheck (沒 --version, 記 sha256)
		which keycheck >/dev/null 2>&1 && {
			echo "[keycheck]"
			echo "sha256: $(sha256sum "$(which keycheck)" 2>/dev/null | awk '{print $1}')"
			echo ""
		}
		# classes.dex
		[[ -f $tools_path/classes.dex ]] && {
			echo "[classes.dex]"
			echo "sha256: $(sha256sum "$tools_path/classes.dex" 2>/dev/null | awk '{print $1}')"
			echo ""
			echo "[HiddenApiUtil]"
			CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil --version 2>&1
			echo ""
		}
		# script 自己版本
		echo "[backup_script]"
		echo "backup_version=$backup_version"
	} > "$_ver_log" 2>&1
	echoRgb "工具版本已記錄: $_ver_log" "2"
}

get_dex_version_line() {
	[[ ! -f $tools_path/classes.dex ]] && { echo "未找到classes.dex"; return 0; }
	local _dex_ver
	_dex_ver="$(CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil --version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
	[[ -n $_dex_ver ]] && echo "$_dex_ver" || echo "無法取得"
}

show_dex_version() {
	[[ ! -f $tools_path/classes.dex ]] && return 0
	local _dex_ver
	_dex_ver="$(CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil --version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
	if [[ -n $_dex_ver ]]; then
		echoRgb "dex版本: $_dex_ver" "3"
	else
		echoRgb "dex版本: 無法取得，可能 classes.dex 尚未包含 --version" "0"
	fi
}

if [[ $background_execution = 1 || $setDisplayPowerMode = 1 ]]; then
	notification() { app_process /system/bin com.xayah.dex.NotificationUtil notify -t 'SpeedBackup' "$@"; }
else
	notification() { :; }
fi
if [[ $quit -ne 0 ]]; then
exit "$quit"
fi
cleanup_log_if_oversize
print_tools_version
# Logo
echo -e "\e[38;5;51m"
cat <<'LOGO'
░██████╗██████╗░███████╗███████╗██████╗░
██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗
╚█████╗░██████╔╝█████╗░░█████╗░░██║░░██║
░╚═══██╗██╔═══╝░██╔══╝░░██╔══╝░░██║░░██║
██████╔╝██║░░░░░███████╗███████╗██████╔╝
╚═════╝░╚═╝░░░░░╚══════╝╚══════╝╚═════╝░
██████╗░░█████╗░░█████╗░██╗░░██╗██╗░░░██╗██████╗░
██╔══██╗██╔══██╗██╔══██╗██║░██╔╝██║░░░██║██╔══██╗
██████╦╝███████║██║░░╚═╝█████═╝░██║░░░██║██████╔╝
██╔══██╗██╔══██║██║░░██╗██╔═██╗░██║░░░██║██╔═══╝░
██████╦╝██║░░██║╚█████╔╝██║░╚██╗╚██████╔╝██║░░░░░
╚═════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚═════╝░╚═╝░░░░░
LOGO
echo -e "\e[38;5;213m        » RESTORE // SYNC «\e[0m"
sleep 1 && clear
TMPDIR="/data/local/tmp"
case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
chmod 771 "$TMPDIR"
chown '2000:2000' "$TMPDIR"

# DNS 解析: 解決部分 ARM curl 二進位檔域名解析失敗 (尤其網盤 WebDAV)
# 用法: _dns_resolve "host.example.com" → 輸出 IP 或空字串
# 快取放在 $TMPDIR/.dns_cache, 格式: <host><TAB><ip>
_dns_resolve() {
	local host="$1"
	# 若已是 IP 直接返回
	case $host in
	*[!0-9.]*) ;;
	*) echo "$host"; return 0 ;;
	esac
	# 查快取 (mksh 兼容: 用檔案而非 here-string)
	if [[ -f $TMPDIR/.dns_cache ]]; then
		local _cached
		_cached=$(awk -v h="$host" -F'\t' '$1 == h {print $2; exit}' "$TMPDIR/.dns_cache" 2>/dev/null)
		[[ -n $_cached ]] && { echo "$_cached"; return 0; }
	fi
	# 解析: 依可用工具 fallback
	local ip=""
	if command -v nslookup >/dev/null 2>&1; then
		ip=$(nslookup "$host" 2>/dev/null | awk '/^(Address|Name):/ {if (NR>1 && $0 ~ /^Address/) {print $NF; exit}}')
		# 備援: 抓任何 IPv4
		[[ -z $ip ]] && ip=$(nslookup "$host" 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | tail -1)
	fi
	if [[ -z $ip ]] && command -v ping >/dev/null 2>&1; then
		ip=$(ping -c 1 -W 1 "$host" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1)
	fi
	# 寫入快取
	[[ -n $ip ]] && printf '%s\t%s\n' "$host" "$ip" >> "$TMPDIR/.dns_cache"
	echo "$ip"
}

# 覆蓋 curl: 自動透過 --resolve 繞過內建 DNS (解決 ARM curl 二進制解析失敗)
# 對 URL 內的域名先解析成 IP, 再傳 --resolve <host>:<port>:<ip> 給 curl
# 只處理 URL 參數中的域名, 純 IP 跳過
curl() {
	# mksh 不支援 args=(), 改用暫存檔記錄
	local extra_resolve="" _arg _rest _hp _host _port _ip
	for _arg in "$@"; do
		case $_arg in
		http://*|https://*|ftp://*)
			# 解出 host:port
			_rest="${_arg#*://}"
			_hp="${_rest%%/*}"
			_host="${_hp%%:*}"
			_port="${_hp#*:}"
			[[ $_port = $_hp ]] && {
				case $_arg in
				http://*)  _port=80 ;;
				https://*) _port=443 ;;
				ftp://*)   _port=21 ;;
				esac
			}
			# 僅對域名 (非純 IP) 處理
			case $_host in
			*[!0-9.]*) ;;          # 含非數字/點 → 是域名
			*) continue ;;          # 純 IP → 跳過
			esac
			_ip=$(_dns_resolve "$_host")
			if [[ -n $_ip && $_ip != "$_host" ]]; then
				extra_resolve="$extra_resolve --resolve $_host:$_port:$_ip"
			fi
			;;
		esac
	done
	# 用 command curl 避免遞迴, 加上預先解析的 resolve 參數
	if [[ -n $extra_resolve ]]; then
		command curl $extra_resolve "$@"
	else
		command curl "$@"
	fi
}

if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
if [[ $(which toybox | grep -Eo "system") != system ]]; then
	echoRgb "系統變量中沒有找到toybox" "0"
	exit 1
fi
#下列為自定義函數
alias down="app_process /system/bin com.xayah.dex.HttpUtil get $@"
case $SCRIPT_LANG in
*CN* | *cn*)
	alias ts="app_process /system/bin com.xayah.dex.CCUtil t2s $@" ;;
*)
	alias ts="app_process /system/bin com.xayah.dex.CCUtil s2t $@" ;;
esac
alias LS="toybox ls -Zd"
alias mv="$get_mv"
# 給 trap / 流程控制用的 return 函數
# Set_back_0 永遠回 0 (成功), Set_back_1 永遠回 1 (失敗)
Set_back_0() {
	return 0
}
Set_back_1() {
	return 1
}
# 計算並輸出某段流程的耗時
# 用法: endtime <計時編號> <名稱>
# 計時編號: 1=讀 starttime1, 2=讀 starttime2 (需先在外面 set 變數)
# 輸出格式: " -<名稱>用時:X天X時X分X秒"
endtime() {
	case $1 in
	1) starttime="$starttime1" ;;
	2) starttime="$starttime2" ;;
	esac
	endtime="$(date -u "+%s")"
	duration="$(echo $((endtime - starttime)) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')"
	[[ $duration != "" ]] && echo " -$2用時:$duration" || echo " -$2用時:0秒"
}
nskg=1
# 從 GitHub Release API 取得腳本最新版本號
# 透過 CDN (ghfast / cloudflare worker) 加速避免被牆
get_version() {
	# keyboard_input=1 時改用鍵盤輸入 (輸入1=$1, 0=$2), 否則維持音量鍵
	if [[ $keyboard_input = 1 ]]; then
		echoRgb "請輸入選項: 1=$1  0=$2" "2"
		unset _kv_option
		while true; do
			if [[ -n $_kv_option ]]; then
				case $_kv_option in
				1)
					[[ $Select_user = true ]] && branch="$1" || branch=true
					echoRgb "$1" "1"
					break ;;
				0)
					[[ $Select_user = true ]] && branch="$2" || branch=false
					echoRgb "$2" "0"
					break ;;
				*)
					echoRgb "$_kv_option參數錯誤 只能是0或1" "0"
					unset _kv_option ;;
				esac
			else
				read _kv_option
			fi
		done
		return
	fi
	while :; do
		keycheck
		case $? in
		42)
			[[ $Select_user = true ]] && branch="$1" || branch=true
			echoRgb "$1" "1"
			;;
		41)
			[[ $Select_user = true ]] && branch="$2" || branch=false
			echoRgb "$2" "0"
			;;
		*)
			echoRgb "keycheck錯誤" "0"
			continue
			;;
		esac
		sleep 0.3
		break
	done
}
# 權限全名 → 中文名稱對照 (用於權限變更顯示更易讀)
# 用法: _perm_cn android.permission.CAMERA → 相機權限 (查不到則回傳原始全名)
_perm_cn() {
	case $1 in
	android.permission.READ_EXTERNAL_STORAGE) echo "讀取外部存儲" ;;
	android.permission.WRITE_EXTERNAL_STORAGE) echo "寫入外部存儲" ;;
	android.permission.CAMERA) echo "相機權限" ;;
	android.permission.RECORD_AUDIO) echo "麥克風權限" ;;
	android.permission.ACCESS_FINE_LOCATION) echo "精確定位" ;;
	android.permission.ACCESS_COARSE_LOCATION) echo "粗略定位" ;;
	android.permission.ACCESS_MEDIA_LOCATION) echo "媒體位置訪問" ;;
	android.permission.READ_PHONE_STATE) echo "讀取手機狀態" ;;
	android.permission.CALL_PHONE) echo "直接撥打電話" ;;
	android.permission.READ_CONTACTS) echo "讀取聯絡人" ;;
	android.permission.WRITE_CONTACTS) echo "寫入聯絡人" ;;
	android.permission.READ_CALL_LOG) echo "讀取通話記錄" ;;
	android.permission.WRITE_CALL_LOG) echo "寫入通話記錄" ;;
	android.permission.SEND_SMS) echo "發送短信" ;;
	android.permission.READ_SMS) echo "讀取短信" ;;
	android.permission.READ_MEDIA_IMAGES) echo "讀取圖片" ;;
	android.permission.READ_MEDIA_VIDEO) echo "讀取視頻" ;;
	android.permission.READ_MEDIA_AUDIO) echo "讀取音頻" ;;
	android.permission.READ_MEDIA_VISUAL_USER_SELECTED) echo "讀取用戶選擇的媒體" ;;
	android.permission.READ_CALENDAR) echo "讀取日曆" ;;
	android.permission.WRITE_CALENDAR) echo "寫入日曆" ;;
	android.permission.BODY_SENSORS) echo "身體傳感器" ;;
	android.permission.ACTIVITY_RECOGNITION) echo "活動識別" ;;
	android.permission.GET_ACCOUNTS) echo "獲取帳戶列表" ;;
	android.permission.MANAGE_ACCOUNTS) echo "管理帳戶" ;;
	android.permission.USE_CREDENTIALS) echo "使用憑據" ;;
	android.permission.AUTHENTICATE_ACCOUNTS) echo "驗證帳戶" ;;
	android.permission.SYSTEM_ALERT_WINDOW) echo "懸浮窗權限" ;;
	android.permission.WRITE_SETTINGS) echo "寫入系統設置" ;;
	android.permission.REQUEST_INSTALL_PACKAGES) echo "安裝應用" ;;
	android.permission.QUERY_ALL_PACKAGES) echo "查詢所有應用" ;;
	android.permission.READ_PRIVILEGED_PHONE_STATE) echo "讀取特權手機狀態" ;;
	android.permission.BLUETOOTH) echo "使用藍牙" ;;
	android.permission.BLUETOOTH_ADMIN) echo "藍牙管理" ;;
	android.permission.BLUETOOTH_CONNECT) echo "藍牙連接" ;;
	android.permission.BLUETOOTH_SCAN) echo "藍牙掃描" ;;
	android.permission.BLUETOOTH_ADVERTISE) echo "藍牙廣播" ;;
	android.permission.INTERNET) echo "訪問網絡" ;;
	android.permission.ACCESS_NETWORK_STATE) echo "查看網絡狀態" ;;
	android.permission.ACCESS_WIFI_STATE) echo "查看WiFi狀態" ;;
	android.permission.CHANGE_WIFI_STATE) echo "修改WiFi狀態" ;;
	android.permission.CHANGE_NETWORK_STATE) echo "修改網絡狀態" ;;
	android.permission.CHANGE_WIFI_MULTICAST_STATE) echo "修改WiFi多播狀態" ;;
	android.permission.POST_NOTIFICATIONS) echo "發送通知" ;;
	android.permission.RECEIVE_BOOT_COMPLETED) echo "開機啟動" ;;
	android.permission.RECEIVE_USER_PRESENT) echo "用戶解鎖設備" ;;
	android.permission.WAKE_LOCK) echo "保持喚醒" ;;
	android.permission.VIBRATE) echo "振動權限" ;;
	android.permission.FLASHLIGHT) echo "手電筒" ;;
	android.permission.DISABLE_KEYGUARD) echo "禁用鎖屏" ;;
	android.permission.EXPAND_STATUS_BAR) echo "展開狀態欄" ;;
	android.permission.MODIFY_AUDIO_SETTINGS) echo "修改音頻設置" ;;
	android.permission.USE_FINGERPRINT) echo "使用指紋" ;;
	android.permission.USE_BIOMETRIC) echo "使用生物識別" ;;
	android.permission.USE_FACERECOGNITION) echo "使用面部識別" ;;
	android.permission.BIND_NFC_SERVICE) echo "NFC服務綁定" ;;
	android.permission.BIND_NOTIFICATION_LISTENER_SERVICE) echo "通知監聽服務綁定" ;;
	android.permission.BIND_QUICK_ACCESS_WALLET_SERVICE) echo "快捷錢包服務綁定" ;;
	android.permission.BIND_ACCESSIBILITY_SERVICE) echo "無障礙服務綁定" ;;
	android.permission.BIND_WALLPAPER) echo "壁紙服務綁定" ;;
	android.permission.FOREGROUND_SERVICE) echo "前台服務" ;;
	android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) echo "忽略電池優化" ;;
	android.permission.SCHEDULE_EXACT_ALARM) echo "精確鬧鐘" ;;
	android.permission.GET_TASKS) echo "獲取任務" ;;
	android.permission.REORDER_TASKS) echo "重新排序任務" ;;
	android.permission.BROADCAST_STICKY) echo "粘性廣播" ;;
	android.permission.DUMP) echo "系統信息轉儲" ;;
	android.permission.NFC) echo "NFC權限" ;;
	android.permission.SMARTCARD) echo "智能卡權限" ;;
	# ---- Android 13 新增 ----
	android.permission.NEARBY_WIFI_DEVICES) echo "鄰近WiFi設備" ;;
	# ---- Android 11+ 儲存全部管理 ----
	android.permission.MANAGE_EXTERNAL_STORAGE) echo "管理所有檔案" ;;
	# ---- 短信補充 ----
	android.permission.WRITE_SMS) echo "寫入短信" ;;
	android.permission.RECEIVE_SMS) echo "接收短信" ;;
	android.permission.RECEIVE_MMS) echo "接收彩信" ;;
	android.permission.RECEIVE_WAP_PUSH) echo "接收WAP推送" ;;
	android.permission.READ_CELL_BROADCASTS) echo "讀取緊急廣播" ;;
	# ---- 電話補充 ----
	android.permission.READ_PHONE_NUMBERS) echo "讀取電話號碼" ;;
	android.permission.ANSWER_PHONE_CALLS) echo "接聽電話" ;;
	android.permission.PROCESS_OUTGOING_CALLS) echo "處理撥出電話" ;;
	android.permission.ADD_VOICEMAIL) echo "新增語音信箱" ;;
	android.permission.USE_SIP) echo "使用SIP通話" ;;
	android.permission.ACCEPT_HANDOVER) echo "接管通話" ;;
	# ---- 位置補充 ----
	android.permission.ACCESS_BACKGROUND_LOCATION) echo "背景定位" ;;
	# ---- 通知補充 ----
	android.permission.USE_FULL_SCREEN_INTENT) echo "全螢幕通知" ;;
	android.permission.ACCESS_NOTIFICATION_POLICY) echo "勿擾模式存取" ;;
	android:picture_in_picture) echo "子母畫面" ;;
	android:system_alert_window) echo "懸浮窗權限(AppOps)" ;;
	android:use_full_screen_intent) echo "全螢幕通知(AppOps)" ;;
	android:write_settings) echo "寫入系統設置(AppOps)" ;;
	android:request_install_packages) echo "安裝未知應用(AppOps)" ;;
	android:get_usage_stats) echo "使用情況存取(AppOps)" ;;
	android:manage_external_storage) echo "管理所有檔案(AppOps)" ;;
	android:schedule_exact_alarm) echo "精確鬧鐘(AppOps)" ;;
	android:access_notification_policy) echo "勿擾模式存取(AppOps)" ;;

	# ---- AppOps 額外名稱對照 ----
	android:coarse_location) echo "粗略定位(AppOps)" ;;
	android:fine_location) echo "精確定位(AppOps)" ;;
	android:gps) echo "GPS定位(AppOps)" ;;
	android:vibrate) echo "振動(AppOps)" ;;
	android:read_contacts) echo "讀取聯絡人(AppOps)" ;;
	android:write_contacts) echo "寫入聯絡人(AppOps)" ;;
	android:read_call_log) echo "讀取通話記錄(AppOps)" ;;
	android:write_call_log) echo "寫入通話記錄(AppOps)" ;;
	android:read_calendar) echo "讀取日曆(AppOps)" ;;
	android:write_calendar) echo "寫入日曆(AppOps)" ;;
	android:wifi_scan) echo "WiFi掃描(AppOps)" ;;
	android:post_notification) echo "發送通知(AppOps)" ;;
	android:neighboring_cells) echo "鄰近基地台(AppOps)" ;;
	android:call_phone) echo "直接撥打電話(AppOps)" ;;
	android:read_sms) echo "讀取短信(AppOps)" ;;
	android:write_sms) echo "寫入短信(AppOps)" ;;
	android:receive_sms) echo "接收短信(AppOps)" ;;
	android:receive_emergency_broadcast) echo "接收緊急廣播(AppOps)" ;;
	android:receive_mms) echo "接收彩信(AppOps)" ;;
	android:receive_wap_push) echo "接收WAP推送(AppOps)" ;;
	android:send_sms) echo "發送短信(AppOps)" ;;
	android:read_icc_sms) echo "讀取SIM短信(AppOps)" ;;
	android:write_icc_sms) echo "寫入SIM短信(AppOps)" ;;
	android:access_notifications) echo "通知存取(AppOps)" ;;
	android:camera) echo "相機(AppOps)" ;;
	android:record_audio) echo "麥克風(AppOps)" ;;
	android:play_audio) echo "播放音訊(AppOps)" ;;
	android:read_clipboard) echo "讀取剪貼板(AppOps)" ;;
	android:write_clipboard) echo "寫入剪貼板(AppOps)" ;;
	android:take_media_buttons) echo "接收媒體按鍵(AppOps)" ;;
	android:take_audio_focus) echo "取得音訊焦點(AppOps)" ;;
	android:audio_master_volume) echo "主音量控制(AppOps)" ;;
	android:audio_voice_volume) echo "通話音量控制(AppOps)" ;;
	android:audio_ring_volume) echo "鈴聲音量控制(AppOps)" ;;
	android:audio_media_volume) echo "媒體音量控制(AppOps)" ;;
	android:audio_alarm_volume) echo "鬧鐘音量控制(AppOps)" ;;
	android:audio_notification_volume) echo "通知音量控制(AppOps)" ;;
	android:audio_bluetooth_volume) echo "藍牙音量控制(AppOps)" ;;
	android:wake_lock) echo "保持喚醒(AppOps)" ;;
	android:monitor_location) echo "監控定位(AppOps)" ;;
	android:monitor_high_power_location) echo "高功耗定位監控(AppOps)" ;;
	android:mute_microphone) echo "靜音麥克風(AppOps)" ;;
	android:toast_window) echo "Toast視窗(AppOps)" ;;
	android:project_media) echo "媒體投放/投影(AppOps)" ;;
	android:activate_vpn) echo "啟用VPN(AppOps)" ;;
	android:write_wallpaper) echo "修改壁紙(AppOps)" ;;
	android:assist_structure) echo "輔助結構存取(AppOps)" ;;
	android:assist_screenshot) echo "輔助截圖存取(AppOps)" ;;
	android:read_phone_state) echo "讀取手機狀態(AppOps)" ;;
	android:add_voicemail) echo "新增語音信箱(AppOps)" ;;
	android:use_sip) echo "使用SIP通話(AppOps)" ;;
	android:process_outgoing_calls) echo "處理撥出電話(AppOps)" ;;
	android:use_fingerprint) echo "使用指紋(AppOps)" ;;
	android:body_sensors) echo "身體傳感器(AppOps)" ;;
	android:read_cell_broadcasts) echo "讀取緊急廣播(AppOps)" ;;
	android:mock_location) echo "模擬位置(AppOps)" ;;
	android:read_external_storage) echo "讀取外部存儲(AppOps)" ;;
	android:write_external_storage) echo "寫入外部存儲(AppOps)" ;;
	android:turn_screen_on) echo "喚醒螢幕(AppOps)" ;;
	android:get_accounts) echo "獲取帳戶列表(AppOps)" ;;
	android:run_in_background) echo "背景執行(AppOps)" ;;
	android:audio_accessibility_volume) echo "無障礙音量控制(AppOps)" ;;
	android:read_phone_numbers) echo "讀取電話號碼(AppOps)" ;;
	android:instant_app_start_foreground) echo "即時應用啟動前台服務(AppOps)" ;;
	android:answer_phone_calls) echo "接聽電話(AppOps)" ;;
	android:run_any_in_background) echo "任意背景執行(AppOps)" ;;
	android:change_wifi_state) echo "修改WiFi狀態(AppOps)" ;;
	android:request_delete_packages) echo "刪除應用(AppOps)" ;;
	android:bind_accessibility_service) echo "綁定無障礙服務(AppOps)" ;;
	android:accept_handover) echo "接管通話(AppOps)" ;;
	android:manage_ipsec_tunnels) echo "管理IPSec通道(AppOps)" ;;
	android:start_foreground) echo "啟動前台服務(AppOps)" ;;
	android:bluetooth_scan) echo "藍牙掃描(AppOps)" ;;
	android:use_biometric) echo "使用生物識別(AppOps)" ;;
	android:activity_recognition) echo "活動識別(AppOps)" ;;
	android:sms_financial_transactions) echo "金融短信交易(AppOps)" ;;
	android:read_media_audio) echo "讀取音頻(AppOps)" ;;
	android:write_media_audio) echo "寫入音頻(AppOps)" ;;
	android:read_media_video) echo "讀取視頻(AppOps)" ;;
	android:write_media_video) echo "寫入視頻(AppOps)" ;;
	android:read_media_images) echo "讀取圖片(AppOps)" ;;
	android:write_media_images) echo "寫入圖片(AppOps)" ;;
	android:legacy_storage) echo "舊版儲存模式(AppOps)" ;;
	android:access_accessibility) echo "無障礙存取(AppOps)" ;;
	android:read_device_identifiers) echo "讀取裝置識別碼(AppOps)" ;;
	android:access_media_location) echo "媒體位置存取(AppOps)" ;;
	android:query_all_packages) echo "查詢所有應用(AppOps)" ;;
	android:interact_across_profiles) echo "跨設定檔互動(AppOps)" ;;
	android:activate_platform_vpn) echo "啟用平台VPN(AppOps)" ;;
	android:loader_usage_stats) echo "載入器使用情況(AppOps)" ;;
	android:auto_revoke_permissions_if_unused) echo "未使用自動撤銷權限(AppOps)" ;;
	android:auto_revoke_managed_by_installer) echo "安裝器管理自動撤銷(AppOps)" ;;
	android:no_isolated_storage) echo "停用隔離儲存(AppOps)" ;;
	android:phone_call_microphone) echo "通話麥克風(AppOps)" ;;
	android:phone_call_camera) echo "通話相機(AppOps)" ;;
	android:record_audio_hotword) echo "熱詞錄音(AppOps)" ;;
	android:manage_ongoing_calls) echo "管理進行中通話(AppOps)" ;;
	android:manage_credentials) echo "管理憑證(AppOps)" ;;
	android:use_icc_auth_with_device_identifier) echo "SIM認證使用裝置識別碼(AppOps)" ;;
	android:record_audio_output) echo "錄製系統音訊輸出(AppOps)" ;;
	android:fine_location_source) echo "精確定位來源(AppOps)" ;;
	android:coarse_location_source) echo "粗略定位來源(AppOps)" ;;
	android:manage_media) echo "管理媒體(AppOps)" ;;
	android:bluetooth_connect) echo "藍牙連接(AppOps)" ;;
	android:uwb_ranging) echo "超寬頻測距(AppOps)" ;;
	android:activity_recognition_source) echo "活動識別來源(AppOps)" ;;
	android:bluetooth_advertise) echo "藍牙廣播(AppOps)" ;;
	android:record_incoming_phone_audio) echo "錄製來電音訊(AppOps)" ;;
	android:nearby_wifi_devices) echo "鄰近WiFi設備(AppOps)" ;;
	android:establish_vpn_service) echo "建立VPN服務(AppOps)" ;;
	android:establish_vpn_manager) echo "建立VPN管理器(AppOps)" ;;
	android:access_restricted_settings) echo "存取受限設定(AppOps)" ;;
	android:receive_soundtrigger_audio) echo "接收聲音觸發音訊(AppOps)" ;;
	android:receive_explicit_user_interaction_audio) echo "接收明確互動音訊(AppOps)" ;;
	android:run_user_initiated_jobs) echo "執行使用者發起工作(AppOps)" ;;
	android:read_media_visual_user_selected) echo "讀取使用者選擇媒體(AppOps)" ;;
	android:system_exempt_from_suspension) echo "系統豁免暫停(AppOps)" ;;
	android:system_exempt_from_dismissible_notifications) echo "系統豁免可清除通知(AppOps)" ;;
	android:read_write_health_data) echo "讀寫健康資料(AppOps)" ;;
	android:foreground_service_special_use) echo "前台服務特殊用途(AppOps)" ;;
	android:camera_sandboxed) echo "沙盒相機(AppOps)" ;;
	android:record_audio_sandboxed) echo "沙盒錄音(AppOps)" ;;
	android:receive_sandbox_trigger_audio) echo "接收沙盒觸發音訊(AppOps)" ;;
	android:system_exempt_from_power_restrictions) echo "系統豁免電源限制(AppOps)" ;;
	android:system_exempt_from_hibernation) echo "系統豁免休眠(AppOps)" ;;
	android:system_exempt_from_activity_bg_start_restriction) echo "系統豁免背景啟動限制(AppOps)" ;;
	android:capture_consentless_bugreport_on_userdebug_build) echo "擷取無同意錯誤報告(AppOps)" ;;
	# ---- 系統/背景執行補充 ----
	android.permission.RUN_IN_BACKGROUND) echo "在背景執行" ;;
	android.permission.RUN_ANY_IN_BACKGROUND) echo "任意背景執行" ;;
	android.permission.START_FOREGROUND) echo "啟動前台服務" ;;
	android.permission.FOREGROUND_SERVICE_LOCATION) echo "前台服務-定位" ;;
	android.permission.FOREGROUND_SERVICE_CAMERA) echo "前台服務-相機" ;;
	android.permission.FOREGROUND_SERVICE_MICROPHONE) echo "前台服務-麥克風" ;;
	android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK) echo "前台服務-媒體播放" ;;
	android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION) echo "前台服務-畫面錄製" ;;
	android.permission.FOREGROUND_SERVICE_PHONE_CALL) echo "前台服務-通話" ;;
	android.permission.FOREGROUND_SERVICE_DATA_SYNC) echo "前台服務-數據同步" ;;
	android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE) echo "前台服務-連接設備" ;;
	android.permission.FOREGROUND_SERVICE_HEALTH) echo "前台服務-健康" ;;
	android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING) echo "前台服務-遠程消息" ;;
	android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED) echo "前台服務-系統豁免" ;;
	android.permission.FOREGROUND_SERVICE_SPECIAL_USE) echo "前台服務-特殊用途" ;;
	android.permission.REQUEST_DELETE_PACKAGES) echo "刪除應用" ;;
	android.permission.PACKAGE_USAGE_STATS) echo "使用情況存取" ;;
	android.permission.GET_USAGE_STATS) echo "獲取使用情況統計" ;;
	android.permission.READ_CLIPBOARD) echo "讀取剪貼板" ;;
	android.permission.WRITE_CLIPBOARD) echo "寫入剪貼板" ;;
	android.permission.MUTE_MICROPHONE) echo "靜音麥克風" ;;
	android.permission.LEGACY_STORAGE) echo "舊版儲存模式" ;;
	android.permission.HIGH_SAMPLING_RATE_SENSORS) echo "高採樣率傳感器" ;;
	android.permission.UWB_RANGING) echo "超寬頻測距" ;;
	android.permission.BIND_VPN_SERVICE) echo "VPN服務綁定" ;;
	android.permission.INTERACT_ACROSS_USERS) echo "跨用戶互動" ;;
	android.permission.MANAGE_OWN_CALLS) echo "管理自有通話" ;;
	android.permission.CALL_COMPANION_APP) echo "車機配對通話" ;;
	# ---- Android 16 健康權限 (health.* 命名空間, 取代舊版 BODY_SENSORS) ----
	android.permission.health.READ_HEART_RATE) echo "讀取心率" ;;
	android.permission.health.READ_STEPS) echo "讀取步數" ;;
	android.permission.health.READ_SLEEP) echo "讀取睡眠數據" ;;
	android.permission.health.READ_OXYGEN_SATURATION) echo "讀取血氧" ;;
	android.permission.health.READ_BODY_TEMPERATURE) echo "讀取體溫" ;;
	android.permission.health.READ_BLOOD_PRESSURE) echo "讀取血壓" ;;
	android.permission.health.READ_BLOOD_GLUCOSE) echo "讀取血糖" ;;
	android.permission.health.READ_EXERCISE) echo "讀取運動記錄" ;;
	android.permission.health.READ_NUTRITION) echo "讀取營養記錄" ;;
	android.permission.health.READ_WEIGHT) echo "讀取體重" ;;
	android.permission.health.READ_MEDICAL_DATA_IMMUNIZATION) echo "讀取疫苗醫療記錄" ;;
	android.permission.health.WRITE_MEDICAL_DATA) echo "寫入醫療記錄" ;;
	android:op_*) echo "未知AppOps(${1#android:op_})" ;;
	*) echo "$1" ;;
	esac
}
# 規範化布林值,將 1/true/yes 等變成 true,其他變成 false
# 用於 conf 讀進來的開關項統一格式
isBoolean() {
	nsx="$1"
	case $1 in
	1|true|True|TRUE)
		nsx=true ;;
	0|false|False|FALSE)
		nsx=false ;;
	*)
		echoRgb "$conf_path $2=$1填寫錯誤，正確值1or0" "0"
		exit 2 ;;
	esac
}
# 根據上一條命令的退出碼輸出成功/失敗訊息
# 用法: echo_log "操作名稱" [skip_success_msg]
# 第二個參數非空時, 成功不輸出訊息 (只設變數)
echo_log() {
	if [[ $? = 0 ]]; then
		[[ $2 = "" ]] && echoRgb "$1成功" "1"
		result=0
		Set_back_0
	else
		echoRgb "$1失敗，過世了" "0"
		notification "$RANDOM" "$name1: $1失敗，過世"
		result=1
		Set_back_1
	fi
}
# 殺死先前殘留的腳本進程,並設置 lock 防止重複執行
# trap EXIT 會清 lock 並觸發 remote_cleanup (若有遠端設定)
kill_Serve() {
	local LOCK_DIR="/data/.backup_lock"
	local MY_PID="$$"
	# 使用 mkdir 作為原子鎖操作，避免 TOCTOU 競態條件
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		if [[ -f $LOCK_DIR/pid ]]; then
			OLD_PID="$(cat "$LOCK_DIR/pid")"
			if kill -0 "$OLD_PID" 2>/dev/null; then
				echo "發現先前的備份程序 (PID=$OLD_PID)，將其終止"
				# 單次 ps 快照 + awk 一次算出待殺清單: 舊程序整棵子孫樹 + 殘留 start.sh/tools.sh (排除自己祖先鏈)
				local _kp _psbin="/system/bin/ps"
				[[ -x $_psbin ]] || _psbin="ps"
				# self 整條祖先鏈 + 自己的子孫樹 一律保護 (避免殺到自己 / 自己起的 ps 子進程)
				for _kp in $($_psbin -e -o pid=,ppid=,args= 2>/dev/null | awk -v root="$OLD_PID" -v self="$$" -v me="$MY_PID" '
					{ ppid[$1]=$2; cmd[$1]=$0 }
					END {
						# 保護: self 與 MY_PID 的祖先鏈
						for (start_pid in ppid) {}
						split(self" "me, seeds, " ")
						for (k in seeds) { p=seeds[k]; while (p>1 && (p in ppid)) { safe[p]=1; p=ppid[p] } safe[seeds[k]]=1 }
						# 保護: self/me 的子孫樹
						sm[self]=1; sm[me]=1; ch=1
						while (ch) { ch=0; for (x in ppid) if (!(x in sm) && (ppid[x] in sm)) { sm[x]=1; ch=1 } }
						for (x in sm) safe[x]=1
						# 待殺: 舊程序子孫樹 + 殘留 start.sh/tools.sh, 扣除保護集
						mark[root]=1; ch=1
						while (ch) { ch=0; for (x in ppid) if (!(x in mark) && (ppid[x] in mark)) { mark[x]=1; ch=1 } }
						for (x in cmd) if (cmd[x] ~ /start\.sh|tools\.sh/) mark[x]=1
						for (x in mark) if (!(x in safe)) print x
					}'); do
					kill -KILL "$_kp" 2>/dev/null
				done
				echo "結束自身，避免重複執行"
				exit 1
			else
				echo "發現 lock 但程序已不存在，視為殘留 lock"
				rm -rf "$LOCK_DIR"
				mkdir "$LOCK_DIR" 2>/dev/null || exit 1
			fi
		else
			rm -rf "$LOCK_DIR"
			mkdir "$LOCK_DIR" 2>/dev/null || exit 1
		fi
	fi
	echo "$MY_PID" > "$LOCK_DIR/pid"
	
# 安全清理暫存檔：避免 TMPDIR 異常時誤刪
_cleanup_tmp_files() {
	case "$TMPDIR" in
	""|"/")
		echoRgb "TMPDIR異常，跳過暫存清理: $TMPDIR" "0" 2>/dev/null
		return 0
		;;
	esac
	rm -f \
		"$TMPDIR/.pkg_uid" \
		"$TMPDIR/.pkg_ver" \
		"$TMPDIR/.pkg_perms" \
		"$TMPDIR/.pkg_notify" \
		"$TMPDIR/.pkg_battery" \
		"$TMPDIR/.pkg_installer" \
		"$TMPDIR/.battery_wl" \
		"$TMPDIR/.installed_pkgs" \
		"$TMPDIR/.smb_scan_results" \
		"$TMPDIR/.backup_done" \
		"$TMPDIR/.update_apks" \
		"$TMPDIR/.add_apks" \
		"$TMPDIR/.ssaid_apks" \
		"$TMPDIR/.batch_grant" \
		"$TMPDIR/.batch_revoke" \
		"$TMPDIR/.batch_ops" \
		"$TMPDIR/.batch_opsreset" \
		"$TMPDIR/.batch_notify" \
		"$TMPDIR/.batch_battery" \
		"$TMPDIR/.restore_ssaid" \
		"$TMPDIR/.perm_expect" \
		"$TMPDIR/.perm_actual" \
		"$TMPDIR/.ops_expect" \
		"$TMPDIR/.ops_actual" \
		"$TMPDIR/.notify_expect" \
		"$TMPDIR/.notify_actual" \
		"$TMPDIR/.notify_mismatch" \
		"$TMPDIR/.notify_pending" \
		"$TMPDIR/.battery_expect" \
		"$TMPDIR/.battery_actual" \
		"$TMPDIR/.dir_sizes" \
		"$TMPDIR/.changed_apps" \
		"$TMPDIR/.backup_manifest" \
		"$TMPDIR/.json_health_issues" \
		"$TMPDIR/.json_health_hints" \
		"$TMPDIR/.dns_cache" \
		"$TMPDIR/.stream_failed" \
		"$TMPDIR/.remote_scripts" \
		"$TMPDIR/.remote_files" \
		"$TMPDIR/.dex_call_log" \
		"$TMPDIR/.stream_restore_list" \
		"$TMPDIR/.json_fetch" \
		"$TMPDIR/.verify_files" \
		"$TMPDIR/.listver_changed" \
		2>/dev/null
	rm -rf \
		"$TMPDIR/.remote_json" \
		"$TMPDIR"/.remote_app_details_* \
		2>/dev/null
}

trap "rm -rf \"$LOCK_DIR\" 2>/dev/null; _cleanup_tmp_files; remote_cleanup" EXIT
}
kill_Serve
# ======================================================
# 遠端功能函數 (upload / download / smb / webdav)
# ======================================================
# 預連線測試 (避免後續操作卡住)
# 用法: remote_precheck <host> <port>
# 三層 fallback: nc → /dev/tcp → curl, 失敗會寫 log/remote_precheck.log
remote_precheck() {
	local host="$1" port="$2"
	[[ -z $host ]] && { echoRgb "remote_precheck: host為空" "0"; return 1; }
	local dbg="${logfile:+${logfile%/*}/}remote_precheck.log"
	[[ -z $logfile ]] && dbg="$TMPDIR/remote_precheck.log"
	mkdir -p "${dbg%/*}" 2>/dev/null
	{
		echo "===== precheck $(date '+%Y-%m-%d %H:%M:%S') ====="
		echo "host=$host port=$port"
	} >> "$dbg"
	# 1. nc
	if command -v nc >/dev/null 2>&1; then
		nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && {
			echo "[OK] nc passed" >> "$dbg"
			return 0
		}
		echo "[FAIL] nc -z -w 3 $host $port → 失敗" >> "$dbg"
	fi
	# 2. /dev/tcp
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 sh -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1 && {
			echo "[OK] /dev/tcp passed" >> "$dbg"
			return 0
		}
		echo "[FAIL] timeout 3 /dev/tcp/$host/$port → 失敗" >> "$dbg"
	fi
	# 3. curl --connect-timeout (對 https 通常更可靠, 也能用 --resolve)
	if command -v curl >/dev/null 2>&1; then
		# 構造 url; 不知 https/http 直接試 telnet 風格
		local _scheme=http
		[[ $port = 443 || $port = 30 ]] && _scheme=https
		local curl_err
		curl_err=$(curl -sS --connect-timeout 3 -o /dev/null -w '%{http_code}' "$_scheme://$host:$port/" 2>&1)
		case $curl_err in
		[0-9][0-9][0-9])
			echo "[OK] curl returned HTTP $curl_err" >> "$dbg"
			return 0 ;;
		*)
			echo "[FAIL] curl err: $curl_err" >> "$dbg"
			;;
		esac
	fi
	echoRgb "連線失敗詳情: $dbg" "3"
	return 1
}

# 寫入遠端上傳 log (帶時間戳)
# 用法: remote_log "訊息"
remote_log() {
	[[ -z $MODDIR ]] && return
	local _up_log="${logfile%/*}/remote_upload.log"
	mkdir -p "${logfile%/*}" 2>/dev/null
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$_up_log"
}

# 上傳結束時統一輸出總結並決定是否刪本地
# 參數: $1=協議名 $2=成功清單檔 $3=失敗清單檔
upload_summary() {
	local proto="$1" ok_list="$2" fail_list="$3"
	local ok_count=0 fail_count=0
	[[ -f $ok_list ]] && ok_count="$(wc -l < "$ok_list" 2>/dev/null)"
	[[ -f $fail_list ]] && fail_count="$(wc -l < "$fail_list" 2>/dev/null)"
	ok_count=${ok_count:-0}
	fail_count=${fail_count:-0}
	# 計算總耗時
	local elapsed_str=""
	if [[ -n $UPLOAD_START_TS ]]; then
		local elapsed=$(( $(date +%s) - UPLOAD_START_TS ))
		elapsed_str=" 用時${elapsed}秒"
	fi
	echoRgb "_______________________________________" "2"
	echoRgb "$proto 上傳完成: 成功 $ok_count / 失敗 $fail_count${elapsed_str}" "3"
	remote_log "$proto 上傳結束: 成功 $ok_count / 失敗 $fail_count${elapsed_str}"
	if [[ $fail_count -gt 0 ]]; then
		echoRgb "失敗清單(已記錄到 ${logfile%/*}/remote_upload.log):" "0"
		local n=0
		while read -r line && [[ $n -lt 5 ]]; do
			echoRgb "$line" "0"
			let n++
		done < "$fail_list"
		[[ $fail_count -gt 5 ]] && echoRgb "...還有 $((fail_count - 5)) 個,請看 log" "0"
	fi
	# 刪本地檔案的策略: remote_keep_local=true 或 1 永遠保留
	# 否則: 必須「全部成功」才刪除所有上傳過的檔案
	case $remote_keep_local in
	1|true|True|TRUE)
		echoRgb "remote_keep_local=$remote_keep_local 本地檔案保留" "3"
		;;
	*)
		if [[ $fail_count -eq 0 && $ok_count -gt 0 ]]; then
			echoRgb "全部上傳成功,清除本地已上傳檔案 (保留 tools/ 跟入口腳本)" "1"
			while read -r f; do
				[[ -z $f ]] && continue
				# 保留: tools/ 目錄下檔案 / start.sh / backup.sh / recover.sh / upload.sh
				case $f in
				*/tools/*) continue ;;
				esac
				case ${f##*/} in
				start.sh|backup.sh|recover.sh|upload.sh) continue ;;
				esac
				rm -f "$f"
			done < "$ok_list"
		elif [[ $fail_count -gt 0 ]]; then
			echoRgb "部分上傳失敗,本地檔案全部保留 (含已上傳的)" "0"
			remote_log "部分失敗,本地檔案全部保留"
		fi
		;;
	esac
	rm -f "$ok_list" "$fail_list" 2>/dev/null
	unset UPLOAD_START_TS
	[[ $fail_count -eq 0 ]]
}

# URL 編碼 (處理 UTF-8 多 byte, 保留 / 不編碼以保持路徑結構)
# 用法: url_encode_path <string>
url_encode_path() {
	local s="$1"
	# 用 od 把每個 byte 印成 hex, awk 處理 hex 字串轉換
	# 避免 strtonum (busybox awk 不支援)
	printf '%s' "$s" | od -An -tx1 -v | tr -s ' \n' ' ' | awk '
	BEGIN {
		# 建立 hex → dec 對照表
		for (i=0; i<10; i++) hex2int[sprintf("%d",i)] = i
		hex2int["a"]=10; hex2int["b"]=11; hex2int["c"]=12
		hex2int["d"]=13; hex2int["e"]=14; hex2int["f"]=15
	}
	{
		n = split($0, a, " ")
		for (i=1; i<=n; i++) {
			h = a[i]
			if (h == "") continue
			# 把兩個 hex 字元轉成 dec
			val = hex2int[substr(h,1,1)] * 16 + hex2int[substr(h,2,1)]
			# 不編碼: A-Z a-z 0-9 - _ . ~ /
			if ((val>=48 && val<=57) || (val>=65 && val<=90) || (val>=97 && val<=122) \
				|| val==45 || val==95 || val==46 || val==126 || val==47) {
				printf "%c", val
			} else {
				printf "%%%s", toupper(h)
			}
		}
	}'
}

# URL 解碼 (處理 %XX, 含 UTF-8 多 byte)
url_decode_path() {
	local s="$1"
	local converted
	converted=$(echo "$s" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
	printf '%b' "$converted"
}

# 計算速度顯示字串
# 用法: speed_calc <總bytes> <用時秒數>
# 輸出: "1.23 GB/s" 或 "8.5 MB/s" 或 "512 KB/s" 或 "" (時間=0時)
speed_calc() {
	local bytes="$1" secs="$2"
	[[ -z $bytes || -z $secs ]] && return
	[[ $secs -le 0 ]] && return
	# 依速率(bytes/secs)分級, awk 一次處理 (無 32-bit 溢位, 四捨五入)
	awk -v b="$bytes" -v s="$secs" 'BEGIN{
		r=b/s
		if(r>=1073741824) printf "%.2f GB/s", r/1073741824
		else if(r>=1048576) printf "%.2f MB/s", r/1048576
		else if(r>=1024) printf "%.1f KB/s", r/1024
		else if(r>0) printf "%d B/s", r
	}'
}

# 計算清單檔案總大小 (bytes)
list_total_size() {
	local list="$1"
	[[ ! -f $list ]] && { echo 0; return; }
	# 一次批量 stat (xargs 分批) 取代逐行 fork, 大量檔案時快很多; 精確位元組
	tr '\n' '\0' < "$list" | xargs -0 -r stat -c%s 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

# 收集本次需要上傳的清單 (而非整個Backup)
# 結果寫入 $1 指定的list_file
# 範圍由以下變數控制 (在各備份入口設定,只反映「本次執行」):
#   REMOTE_APPLIST    : 字串,本次備份的 app 清單 (跟 $txt 同格式)
#   REMOTE_UPLOAD_MEDIA=1 : 本次有跑 Media 備份, 要上傳 $Backup/Media
#   REMOTE_UPLOAD_WIFI=1  : 本次有跑 wifi 備份, 要上傳 $Backup/wifi
# app 上傳條件:
#   1. 該行未被 #/＃/! 註解
#   2. $Backup/$name1 目錄存在
#   3. 目錄內至少有一個有效檔案
remote_collect_targets() {
	local list_file="$1"
	local tmp_collect="$TMPDIR/.rcollect"
	: > "$list_file"
	# 全目錄模式: 上傳整個 Backup 下所有檔案 (排除 log/), 不依清單
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		[[ $REMOTE_QUIET != 1 ]] && echoRgb "全目錄模式: 收集整個備份目錄" "2"
		find "$Backup" -type f -not -path "$Backup/log/*" >> "$list_file" 2>/dev/null
		rm -f "$tmp_collect" 2>/dev/null
		return 0
	fi
	# 如果設置了 REMOTE_SKIP_APPDATA，跳過應用數據上傳
	if [[ $REMOTE_SKIP_APPDATA != 1 && -n $REMOTE_APPLIST ]]; then
		[[ $REMOTE_QUIET != 1 ]] && echoRgb "讀取本次備份名單" "2"
		echo "$REMOTE_APPLIST" | grep -Ev '^[[:space:]]*[#＃!]|^[[:space:]]*$' | while read -r line; do
			local name1="${line%% *}"
			[[ -z $name1 ]] && continue
			local full="$Backup/$name1"
			[[ -d $full ]] || continue
			if [[ $REMOTE_APPDETAILS_SKIP = 1 ]]; then
				find "$full" -type f ! -name "app_details.json" > "$tmp_collect" 2>/dev/null
			else
				find "$full" -type f  > "$tmp_collect" 2>/dev/null
			fi
			[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
		done
	fi
	if [[ $REMOTE_UPLOAD_MEDIA = 1 && -d $Backup/Media ]]; then
		find "$Backup/Media" -type f  > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $Backup/wifi ]]; then
		find "$Backup/wifi" -type f  > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	# 固定附加: tools/ 資料夾、start.sh、restore_settings.conf、appList.txt、mediaList.txt
	# 只要 list_file 已經有內容(代表本次有東西要上傳)就一併帶上,讓遠端目錄能獨立還原
	# REMOTE_SKIP_FIXED=1 時跳過 (逐應用上傳模式，避免重複上傳)
	# REMOTE_SKIP_APPDATA=1 時也需要上傳依賴文件
	if [[ ($REMOTE_SKIP_APPDATA = 1 || -s $list_file) && $REMOTE_SKIP_FIXED != 1 ]]; then
		[[ -d $Backup/tools ]] && find "$Backup/tools" -type f >> "$list_file" 2>/dev/null
		[[ -f $Backup/start.sh ]] && echo "$Backup/start.sh" >> "$list_file"
		[[ -f $Backup/restore_settings.conf ]] && echo "$Backup/restore_settings.conf" >> "$list_file"
		[[ -f $Backup/appList.txt ]] && echo "$Backup/appList.txt" >> "$list_file"
		[[ -f $Backup/mediaList.txt ]] && echo "$Backup/mediaList.txt" >> "$list_file"
		[[ -f "$Backup/MT管理器.apk" ]] && echo "$Backup/MT管理器.apk" >> "$list_file"
	fi
	rm -f "$tmp_collect" 2>/dev/null
}
# 掃描核心: 找出區網內所有開放 445 的主機, 寫入 $TMPDIR/.smb_scan_results (一行一 IP, 已排序)
# 成功(有結果) return 0; 無結果或無法掃描 return 1. 供 scan_smb / smb_autodetect_url 複用
_smb_scan_hosts() {
	local my_ip
	my_ip="$(ip route get 1 2>/dev/null | awk '{print $7; exit}')"
	[[ -z $my_ip ]] && my_ip="$(ifconfig 2>/dev/null | grep -m1 'inet addr:192' | awk '{print $2}' | cut -d: -f2)"
	[[ -z $my_ip ]] && { echoRgb "無法取得本機 IP" "0"; return 1; }
	SMB_SCAN_SUBNET="${my_ip%.*}"
	if ! command -v nc >/dev/null 2>&1; then
		echoRgb "未找到 nc 命令,無法掃描" "0"; return 1
	fi
	echoRgb "本機 IP: $my_ip" "2"
	echoRgb "掃描 $SMB_SCAN_SUBNET.0/24 上的 SMB 主機 (445 port)..." "3"
	local results="$TMPDIR/.smb_scan_results"; : > "$results"
	local i pids=""
	for i in $(seq 1 254); do
		( nc -z -w 1 "$SMB_SCAN_SUBNET.$i" 445 >/dev/null 2>&1 && echo "$SMB_SCAN_SUBNET.$i" >> "$results" ) &
		pids="$pids $!"
		if [[ $((i % 50)) -eq 0 ]]; then
			wait $pids 2>/dev/null; pids=""
			printf '\r -掃描 %d/254 %s' "$i" "$(progress_bar $((i * 100 / 254)))" >&2
		fi
	done
	wait $pids 2>/dev/null
	printf '\r -掃描 254/254 %s\n' "$(progress_bar 100)" >&2
	[[ ! -s $results ]] && return 1
	sort -t. -k4 -n "$results" -o "$results"
	return 0
}

# 自動偵測區網 SMB 並設定 remote_url (取第一台有可用共享的主機)
# 不論 remote_stream/remote_user/remote_pass 是否填寫都會探測
smb_autodetect_url() {
	_smb_scan_hosts || return 1
	local _auth
	if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
	local target share
	while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		share="$(command smbclient -L "//$target" $_auth -t 5 -s /dev/null -m SMB3 2>/dev/null \
			| awk '/Disk/ && $1!~/\$$/ {print $1; exit}')"
		if [[ -n $share ]]; then
			remote_url="smb://$target/$share"
			rm -f "$TMPDIR/.smb_scan_results"
			return 0
		fi
		echoRgb "$target 無可用共享 (或需認證)" "2"
	done < "$TMPDIR/.smb_scan_results"
	rm -f "$TMPDIR/.smb_scan_results"
	return 1
}

# 掃描區網內所有開放 SMB (445 port) 的主機 (菜單功能: 顯示所有主機與共享)
scan_smb() {
	if ! _smb_scan_hosts; then
		echoRgb "未發現 SMB 主機" "0"
		rm -f "$TMPDIR/.smb_scan_results"
		return 1
	fi
	echoRgb "------- 掃描完成 -------" "3"
	local _auth
	if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
	while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		# 查主機名 (有 nmblookup 才查)
		if command -v nmblookup >/dev/null 2>&1; then
			local hn
			hn="$(nmblookup -A "$target" 2>/dev/null | awk 'NR==2{print $1}' | tr -d '<>\t ')"
			[[ -n $hn ]] && echoRgb "主機名: $hn" "2"
		fi
		# 列 share — 用 awk 不用 grep,避開 busybox grep regex 限制
		command smbclient -L "//$target" $_auth -t 3 -s /dev/null -m SMB3 2>/dev/null \
			| awk '/Disk/ {print "  共享: "$1}' \
			| while read -r line; do echoRgb "$line" "2"; done
	done < "$TMPDIR/.smb_scan_results"
	rm -f "$TMPDIR/.smb_scan_results"
}
# SMB 上傳實作 (使用 smbclient)
# 流程: 解析 URL → 預檢 → 收集檔案 → 按目錄分組 → 每組一次 smbclient 批次傳輸
# 跟 upload_remote 的差別: SMB 用獨立的 smbclient 二進制, 不走 curl
upload_smb() {
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "使用: $filepath/smbclient" "2"
	# 解析 smb://server/share/remotepath
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	rem_path="${rem_path}/${backup_subdir}"
	# 拆出 host 和 port (從 share 反推)
	local _hp="${share#//}"; _hp="${_hp%%/*}"
	local host="${_hp%%:*}"
	local port="${_hp#*:}"
	[[ $port = $_hp ]] && port=445
	echoRgb "SMB: $share (路徑: ${rem_path:-/})" "2"
	# 連線預檢
	if ! remote_precheck "$host" "$port"; then
		echoRgb "SMB伺服器無法連線: $host:$port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	local list_file="$TMPDIR/.slist"
	local ok_list="$TMPDIR/.sok"
	local fail_list="$TMPDIR/.sfail"
	: > "$ok_list"; : > "$fail_list"
	remote_collect_targets "$list_file"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>/dev/null
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "準備上傳 $total 個檔案" "3"
	if [[ $REMOTE_QUIET != 1 ]]; then
		local _up_bytes
		_up_bytes="$(list_total_size "$list_file")"
		echoRgb "本次上傳總大小: $(size "$_up_bytes") (位元組:$_up_bytes)" "3"
	fi
	remote_log "SMB 開始: $share, 共 $total 檔"
	# smbclient 共用參數:
	#   -t 10           : 命令 timeout 秒數
	#   -s /dev/null    : 跳過讀取 smb.conf (避免手動編譯版找不到 conf 噴警告)
	#   -p <port>       : 指定 SMB 端口 (預設 445, 由 remote_parse_endpoint 設定)
	#   -m SMB3         : client max protocol = SMB3, 表示最高用到 SMB3.1.1
	#                     min 維持 smbclient 預設 (SMB2_02), 故拒絕 SMB1 但允許協商到 SMB2.x ~ SMB3.x
	local SMB_OPTS="-t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	# 收集所有需要建立的目錄
	local mkdir_script="$TMPDIR/.smb_mkdir"
	: > "$mkdir_script"
	{
		while read -r f; do
			local d="${f#$Backup/}"
			d="${d%/*}"
			[[ -n $d && $d != "${f#$Backup/}" ]] && echo "${rem_path:+$rem_path/}$d"
		done < "$list_file"
	} | sort -u | while read -r d; do
		# 對每層路徑都產生 mkdir 命令
		# 注意: smbclient 內部命令不認 shell 引號, 不能加 '' 或 ""
		local cur=""
		local OLDIFS="$IFS"
		IFS='/'
		set -- $d
		IFS="$OLDIFS"
		for seg; do
			[[ -z $seg ]] && continue
			cur="$cur/$seg"
			echo "mkdir $cur" >> "$mkdir_script"
		done
	done
	# 一次連線執行所有 mkdir (比每個目錄重新連快很多)
	if [[ -s $mkdir_script ]]; then
		echo "exit" >> "$mkdir_script"
		smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS < "$mkdir_script" 2>&1 \
			| grep -Ev '^Domain=|^OS=|NT_STATUS_OBJECT_NAME_COLLISION|^Try "help"|^dos charset|^Can.t load' >&2
	fi
	rm -f "$mkdir_script" 2>/dev/null
	# 按目錄分組上傳 (同一目錄的所有檔案,一次連線傳完)
	# 先依遠端目錄分組
	local group_dir="$TMPDIR/.smb_groups"
	mkdir -p "$group_dir" && rm -f "$group_dir"/*
	while read -r f; do
		[[ -z $f ]] && continue
		local rel="${f#$Backup/}"
		local file_dir="$(dirname "$rel")"
		local rem_dir="$rem_path"
		[[ $file_dir != . ]] && rem_dir="${rem_dir:+$rem_dir/}$file_dir"
		[[ -z $rem_dir ]] && rem_dir="/"
		# 用 base64 或 hash 當分組 key,避免路徑裡的 / 影響檔名
		local key="$(echo "$rem_dir|$(dirname "$f")" | md5sum 2>/dev/null | cut -c1-12)"
		[[ -z $key ]] && key="$(echo "$rem_dir|$(dirname "$f")" | cksum | cut -d' ' -f1)"
		local gf="$group_dir/$key"
		[[ ! -f $gf ]] && {
			echo "$rem_dir" > "$gf.meta"
			echo "$(dirname "$f")" >> "$gf.meta"
		}
		echo "$f" >> "$gf"
	done < "$list_file"
	# 對每個分組執行批次上傳
	local idx=0
	# 算總目錄數 (用於進度計算; 不含 wifi, wifi 不參與百分比)
	local total_dirs done_dirs=0
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local rem_dir_check
		rem_dir_check="$(sed -n 1p "$gf.meta")"
		# wifi 目錄不算進總數
		[[ $rem_dir_check = */wifi || $rem_dir_check = wifi || $rem_dir_check = */wifi/* ]] && continue
		let total_dirs++
	done
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local meta="$gf.meta"
		local rem_dir local_dir
		rem_dir="$(sed -n 1p "$meta")"
		local_dir="$(sed -n 2p "$meta")"
		local file_count
		file_count="$(wc -l < "$gf")"
		# 判斷是否為 wifi (不計入進度)
		local is_wifi=0
		[[ $rem_dir = */wifi || $rem_dir = wifi || $rem_dir = */wifi/* ]] && is_wifi=1
		echoRgb "上傳目錄 $rem_dir ($file_count 檔)" "3"
		local dir_start
		dir_start=$(date +%s)
		# 建立 smbclient batch script
		local batch="$TMPDIR/.smb_batch"
		echo "cd $rem_dir" > "$batch"
		echo "lcd $local_dir" >> "$batch"
		while read -r f; do
			local fname="$(basename "$f")"
			echo "put $fname" >> "$batch"
		done < "$gf"
		echo "exit" >> "$batch"
		# 跑 batch, 解析每個 put 的結果
		local smb_out
		smb_out="$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS < "$batch" 2>&1)"
		# 對應每個檔案的成功/失敗
		while read -r f; do
			let idx++
			local rel="${f#$Backup/}"
			local fname="$(basename "$f")"
			if echo "$smb_out" | grep -F "$fname" | grep -qE 'NT_STATUS|does not exist|ERR'; then
				echo "$rel" >> "$fail_list"
				echoRgb "[$idx/$total] ✗ $rel" "0"
				remote_log "FAIL SMB $rel"
			else
				echo "$f" >> "$ok_list"
				echoRgb "[$idx/$total] ✓ $rel" "1"
			fi
		done < "$gf"
		rm -f "$batch"
		# 此目錄完成,印整體進度 (wifi 不算)
		if [[ $is_wifi = 0 && $total_dirs -gt 0 ]]; then
			let done_dirs++
			local dir_speed=""
			local dir_bytes
			dir_bytes=$(list_total_size "$gf")
			local dir_elapsed=$(( $(date +%s) - dir_start ))
			local sp
			sp=$(speed_calc "$dir_bytes" "$dir_elapsed")
			[[ -n $sp ]] && dir_speed=" ($sp)"
			echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
		fi
	done
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則上傳 app_details.json
	if [[ -n $REMOTE_APPDETAILS_FILE && -f $REMOTE_APPDETAILS_FILE ]]; then
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_dir="$(dirname "$REMOTE_APPDETAILS_FILE")"
			local _ad_fname="$(basename "$REMOTE_APPDETAILS_FILE")"
			local _ad_smb_out
			_ad_smb_out="$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
				-D "${rem_path:+$rem_path/}$backup_subdir/$(dirname "$_ad_rel")" \
				-c "lcd $_ad_dir; put $_ad_fname; exit" 2>&1)"
			if echo "$_ad_smb_out" | grep -F "$_ad_fname" | grep -qE 'NT_STATUS|does not exist|ERR'; then
				echo "$_ad_rel" >> "$fail_list"
				echoRgb "[$idx/$idx] ✗ $_ad_rel" "0"
				remote_log "FAIL SMB $_ad_rel"
			else
				echo "$REMOTE_APPDETAILS_FILE" >> "$ok_list"
				echoRgb "[$idx/$idx] ✓ $_ad_rel" "1"
			fi
		else
			echoRgb "其他文件上傳失敗,跳過 app_details.json" "0"
		fi
	fi
	rm -rf "$group_dir" 2>/dev/null
	rm -f "$list_file" 2>/dev/null
	upload_summary "SMB" "$ok_list" "$fail_list"
}

# 遠端上傳分派器 + WebDAV 實作
# $1=協議名 (webdav/smb), smb 會轉派給 upload_smb
# WebDAV: 用 curl 逐檔 PUT, 預先 MKCOL 建好目錄結構
upload_remote() {
	local proto="$1"
	[[ $proto = smb ]] && { upload_smb; return $?; }
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	local base_url
	case $proto in
	webdav)
		base_url="${remote_url%/}"
		[[ $base_url != http://* && $base_url != https://* ]] && { echoRgb "WebDAV地址格式錯誤: $remote_url" "0"; return 1; }
		;;
	*) echoRgb "未支援的協議: $proto" "0"; return 1 ;;
	esac
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	base_url="$base_url/$backup_subdir"
	# 連線預檢: 從 base_url 解出 host:port
	local _hp="${base_url#*://}"
	_hp="${_hp%%/*}"
	local _host="${_hp%%:*}"
	local _port="${_hp#*:}"
	if [[ $_port = $_hp ]]; then
		[[ $base_url = https://* ]] && _port=443 || _port=80
	fi
	if ! remote_precheck "$_host" "$_port"; then
		echoRgb "$proto伺服器無法連線: $_host:$_port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "使用: $filepath/curl" "2"
	local list_file="$TMPDIR/.rlist"
	local ok_list="$TMPDIR/.rok"
	local fail_list="$TMPDIR/.rfail"
	: > "$ok_list"; : > "$fail_list"
	[[ -z $Backup ]] && { echoRgb "Backup路徑為空" "0"; return 1; }
	remote_collect_targets "$list_file"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>/dev/null
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "準備上傳 $total 個檔案" "3"
	if [[ $REMOTE_QUIET != 1 ]]; then
		local _up_bytes
		_up_bytes="$(list_total_size "$list_file")"
		echoRgb "本次上傳總大小: $(size "$_up_bytes") (位元組:$_up_bytes)" "3"
	fi
	remote_log "$proto 開始: $base_url, 共 $total 檔"
	# WebDAV: 先建初始目錄 (Backup_zstd_X 自己)
	curl -sS -L --http1.1 -X MKCOL -u "$remote_user:$remote_pass" "$base_url" >/dev/null 2>&1
	# WebDAV: 創建遠程子目錄 (MKCOL)
	while read -r f; do
		local d="${f#$Backup/}"
		d="${d%/*}"
		[[ -n $d && $d != "${f#$Backup/}" ]] && echo "$d"
	done < "$list_file" | sort -u | while read -r d; do
		local enc_d="$(url_encode_path "$d")"
		local cur="$base_url"
		local IFS='/'
		set -- $enc_d
		for seg; do
			cur="$cur/$seg"
			curl -sS -L --http1.1 -X MKCOL -u "$remote_user:$remote_pass" "$cur" >/dev/null 2>&1
		done
	done
	# 預掃總目錄數 (排除 wifi, 不計入百分比)
	local total_dirs done_dirs=0 last_dir="" cur_top_dir=""
	local dir_start=0 dir_bytes_accum=0
	while read -r f; do
		local top="${f#$Backup/}"
		top="${top%%/*}"
		[[ $top = wifi ]] && continue
		echo "$top"
	done < "$list_file" | sort -u | while read -r d; do echo "$d"; done > "$TMPDIR/.dirs_count"
	total_dirs="$(wc -l < "$TMPDIR/.dirs_count" 2>/dev/null)"
	rm -f "$TMPDIR/.dirs_count"
	# 上傳檔案
	local idx=0
	while read -r f; do
		[[ -z $f ]] && continue
		let idx++
		local rel="${f#$Backup/}"
		local cur_top="${rel%%/*}"
		# 判斷是「目錄內檔案」還是「根目錄檔案」
		# rel 含 / → 目錄內檔案, cur_top 是目錄名
		# rel 不含 / → 根目錄檔案, cur_top 是檔案名本身
		local is_root_file=0
		[[ $rel = "$cur_top" ]] && is_root_file=1
		# 目錄切換時印上一個目錄的進度
		if [[ -n $last_dir && $cur_top != "$last_dir" ]]; then
			if [[ $last_dir != wifi && $total_dirs -gt 0 ]]; then
				let done_dirs++
				local dir_speed=""
				local dir_elapsed=$(( $(date +%s) - dir_start ))
				local sp
				sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
				[[ -n $sp ]] && dir_speed=" ($sp)"
				echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
			fi
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		elif [[ -z $last_dir ]]; then
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		fi
		last_dir="$cur_top"
		# 累計這個目錄已上傳的 bytes
		local _sz
		_sz=$(stat -c%s "$f" 2>/dev/null)
		dir_bytes_accum=$(( dir_bytes_accum + ${_sz:-0} ))
		local target_url
		if [[ $proto = webdav ]]; then
			local enc_rel="$(url_encode_path "$rel")"
			target_url="$base_url/$enc_rel"
		else
			target_url="$base_url/$rel"
		fi
		local http_code curl_exit
		# 顯示上傳百分比: curl -# 進度 → awk 過濾只留百分比 → 同行刷新
		local _sz_human
		_sz_human=$(awk "BEGIN{s=${_sz:-0};if(s>=1073741824)printf\"%.2fGB\",s/1073741824;else if(s>=1048576)printf\"%.1fMB\",s/1048576;else if(s>=1024)printf\"%.0fKB\",s/1024;else printf\"%dB\",s}")
		curl -# -S -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
			-T "$f" -u "$remote_user:$remote_pass" -w '%{http_code}' \
			-o /dev/null "$target_url" 2>&1 > "$TMPDIR/.curl_http" | \
			awk -v idx="$idx" -v total="$total" -v rel="$rel" -v sz="$_sz_human" '
			BEGIN{RS="\r"}
			/[0-9]+%/{
				match($0,/[0-9]+\.?[0-9]*%/)
				pct=substr($0,RSTART,RLENGTH)
				for(i=1;i<=NF;i++) if(index($i,"/s")) spd=$i
				printf "\r\033[38;5;51m [%d/%d] %s (%s) %s",idx,total,rel,sz,pct
				if(spd!="") printf " %s",spd
				printf "\033[0m "
				fflush()
			}' > /dev/tty
		curl_exit=$?
		http_code="$(cat "$TMPDIR/.curl_http" 2>/dev/null)"
		rm -f "$TMPDIR/.curl_http"
		printf "\r\033[K" > /dev/tty
		# http_code 2xx 視為成功
		case $http_code in
		2*)
			echo "$f" >> "$ok_list"
			echoRgb "[$idx/$total] ✓ $rel" "1"
			;;
		*)
			echo "$rel  (HTTP $http_code)" >> "$fail_list"
			echoRgb "[$idx/$total] ✗ $rel (HTTP $http_code)" "0"
			remote_log "FAIL $proto $rel HTTP=$http_code curl_exit=$curl_exit"
			;;
		esac
	done < "$list_file"
	# 最後一個目錄(非wifi)的進度
	if [[ -n $last_dir && $last_dir != wifi && $total_dirs -gt 0 ]]; then
		let done_dirs++
		local dir_speed=""
		local dir_elapsed=$(( $(date +%s) - dir_start ))
		local sp
		sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
		[[ -n $sp ]] && dir_speed=" ($sp)"
		echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
	fi
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則上傳 app_details.json
	if [[ -n $REMOTE_APPDETAILS_FILE && -f $REMOTE_APPDETAILS_FILE ]]; then
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_url="$base_url/$(url_encode_path "$_ad_rel")"
			local _ad_http
			_ad_http="$(curl -sS -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
				-T "$REMOTE_APPDETAILS_FILE" -u "$remote_user:$remote_pass" -w '%{http_code}' \
				-o /dev/null "$_ad_url" 2>/dev/null)"
			case $_ad_http in
			2*)
				echo "$REMOTE_APPDETAILS_FILE" >> "$ok_list"
				echoRgb "[$idx/$idx] ✓ $_ad_rel" "1"
				;;
			*)
				echo "$_ad_rel  (HTTP $_ad_http)" >> "$fail_list"
				echoRgb "[$idx/$idx] ✗ $_ad_rel (HTTP $_ad_http)" "0"
				remote_log "FAIL $proto $_ad_rel HTTP=$_ad_http"
				;;
			esac
		else
			echoRgb "其他文件上傳失敗,跳過 app_details.json" "0"
		fi
	fi
	rm -f "$list_file" 2>/dev/null
	upload_summary "$proto" "$ok_list" "$fail_list"
}


# 從 remote_url 解析出 host 和 port (依 remote_type)
# 結果寫到全域變數 REMOTE_HOST 和 REMOTE_PORT
remote_parse_endpoint() {
	REMOTE_HOST=""; REMOTE_PORT=""
	case $remote_type in
	smb)
		local u="${remote_url#smb://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"; [[ $REMOTE_PORT = $u ]] && REMOTE_PORT=445
		;;
	webdav)
		local u="${remote_url#*://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"
		if [[ $REMOTE_PORT = $u ]]; then [[ $remote_url = https://* ]] && REMOTE_PORT=443 || REMOTE_PORT=80; fi
		;;
	esac
}
# 計算遠端某路徑 (相對遠端根) 下所有檔案總大小 (bytes), 對齊本地 calc_dir_size 的純檔案字節統計
# 用法: remote_dir_size "Backup_zstd_0/iQIYI"  或  "Backup_zstd_0"
# 依 remote_type 分發 smbclient(recurse ls) / curl(PROPFIND)
# 一次列出遠端 $1 (相對 share/url 的子目錄) 下所有檔案的相對路徑 (相對 $1), 一行一個
# SMB 用 recurse ls 單連線; WebDAV 用 PROPFIND Depth:infinity 解析 href
remote_list_files() {
	local _path="$1"
	case $remote_type in
	smb)
		local _auth
		if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse ls: 目錄標頭是相對 share 根的完整路徑; 用前綴過濾,
		# cd 失敗 (目錄不存在) 時 smbclient 停留根目錄, 不會混入他處檔案
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "recurse ON; prompt OFF; cd \"$_p\"; ls" 2>/dev/null \
			| awk -v pref="$_pref/" '
				/^\\/ { dir=$0; sub(/^\\/,"",dir); gsub(/\\/,"/",dir); next }
				{
					for (i=2; i<=NF; i++) {
						if ($i ~ /^[AHSRN]+$/ && $(i+1) ~ /^[0-9]+$/) {
							name=$1
							for (j=2; j<i; j++) name=name" "$j
							if (dir=="") { print name }
							else {
								full=dir"/"name
								if (index(full, pref)==1) print substr(full, length(pref)+1)
							}
							break
						}
					}
				}'
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="-u $remote_user:$remote_pass"
		local _wurl="${remote_url%/}/$_path"
		# href 解碼後去掉 base 前綴, 過濾目錄 (以 / 結尾)
		curl -fsS $_wauth -X PROPFIND -H "Depth: infinity" "$_wurl/" 2>/dev/null \
			| sed 's/</\n</g' | sed -n 's|<[^>]*href[^>]*>\([^<]*\).*|\1|p' \
			| awk -v base="$_path" '
				BEGIN { for (i=0;i<256;i++) hex[sprintf("%02X",i)]=sprintf("%c",i) }
				function urldec(s,  out,k,h) {
					out=""
					while ((k=index(s,"%"))>0) {
						h=toupper(substr(s,k+1,2))
						if (h in hex) { out=out substr(s,1,k-1) hex[h]; s=substr(s,k+3) }
						else { out=out substr(s,1,k); s=substr(s,k+1) }
					}
					return out s
				}
				{
					$0=urldec($0)
					if ($0 ~ /\/$/) next
					idx=index($0, base"/")
					if (idx==0) next
					print substr($0, idx+length(base)+1)
				}'
		;;
	esac
}

remote_dir_size() {
	local _path="$1"
	case $remote_type in
	smb)
		local _auth
		if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse on + ls 累加檔案大小; 用目錄標頭前綴過濾,
		# cd 失敗 (目錄不存在) 時不會把整個 share 根算進來
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "recurse ON; prompt OFF; cd \"$_p\"; ls" 2>/dev/null \
			| awk -v pref="$_pref" '
				/^\\/ { dir=$0; sub(/^\\/,"",dir); gsub(/\\/,"/",dir); ok=(index(dir,pref)==1); next }
				ok || dir=="" {
					for (i=2; i<=NF; i++) {
						if ($i ~ /^[AHSRN]+$/ && $(i+1) ~ /^[0-9]+$/) { s += $(i+1); break }
					}
				}
				END { print s+0 }'
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="-u $remote_user:$remote_pass"
		local _wurl="${remote_url%/}/$_path"
		# PROPFIND Depth: infinity 遞迴, 抓所有 getcontentlength 數值累加
		curl -fsS $_wauth -X PROPFIND -H "Depth: infinity" "$_wurl" 2>/dev/null \
			| sed 's/</\n</g' \
			| sed -n 's|.*getcontentlength[^>]*>\([0-9]\{1,\}\).*|\1|p' \
			| awk '{s+=$1} END{print s+0}'
		;;
	*)
		echo 0
		;;
	esac
}

# 流式模式: 上傳恢復必要的基礎設施到遠端 (tools/ 目錄、start.sh、restore_settings.conf)
# 讓遠端備份能獨立恢復 (功能8 檢查這些, 功能10 流式恢復需要)
# tools/ 較大(數十 MB 二進制), 遠端已有就跳過; start.sh/conf 小, 每次重傳確保最新
stream_upload_infra() {
	local _stage="$TMPDIR/.stream_stage/.infra"
	mkdir -p "$_stage" 2>/dev/null
	# 1. start.sh (恢復模式入口, touch_shell "2")
	touch_shell "2" "$_stage/start.sh"
	_stream_upload "start.sh" < "$_stage/start.sh" && echoRgb "start.sh 已上傳遠端" "1" || echoRgb "start.sh 上傳失敗" "0"
	# 2. restore_settings.conf
	update_Restore_settings_conf > "$_stage/restore_settings.conf"
	_stream_upload "restore_settings.conf" < "$_stage/restore_settings.conf" && echoRgb "restore_settings.conf 已上傳遠端" "1" || echoRgb "restore_settings.conf 上傳失敗" "0"
	# 3. appList.txt (功能8/恢復需要應用清單)
	if [[ -f $MODDIR/appList.txt ]]; then
		_stream_upload "appList.txt" < "$MODDIR/appList.txt" && echoRgb "appList.txt 已上傳遠端" "1" || echoRgb "appList.txt 上傳失敗" "0"
	fi
	# 3b. MT管理器.apk (恢復時安裝用, 對齊非流式上傳清單)
	if [[ -f $Backup/MT管理器.apk ]]; then
		_stream_upload "MT管理器.apk" < "$Backup/MT管理器.apk" && echoRgb "MT管理器.apk 已上傳遠端" "1" || echoRgb "MT管理器.apk 上傳失敗" "0"
	fi
	# 4. tools/ 目錄: 遠端已有就跳過. 下載 tools/tools.sh 開頭, 必須是真 shell 腳本 (#!) 才算存在
	# (smbclient get 不存在檔可能輸出錯誤訊息到 stdout, 故須驗證內容是腳本而非錯誤)
	local _toolschk
	_toolschk="$(_stream_download "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}/tools/tools.sh" 2>/dev/null | head -c 30)"
	case $_toolschk in
	'#!'*|*'system/bin'*)
		echoRgb "遠端已有 tools/ (跳過, 省流量)" "2" ;;
	*)
		echoRgb "遠端缺 tools/, 上傳工具目錄 (首次, 約數十 MB)..." "3"
		local _tf _rel
		find "$MODDIR/tools" -type f 2>/dev/null | while read -r _tf; do
			_rel="tools/${_tf#$MODDIR/tools/}"
			_stream_upload "$_rel" < "$_tf"
		done
		echoRgb "tools/ 已上傳遠端" "1"
		;;
	esac
	rm -rf "$_stage" 2>/dev/null
}

# 通用流式上傳: 從 stdin 讀資料, 上傳到遠端 (相對遠端根的) 路徑
# 依 remote_type 分發到 smbclient / curl(webdav) / ssh
# 用法: <資料來源> | _stream_upload "相對路徑/file.tar.zst"
# 回傳: 0=成功
_stream_upload() {
	local _rel="$1"
	# 加上備份子目錄前綴 (Backup_zstd_X), 與 remote_download_single_file 路徑一致, 確保增量比對找得到
	# 用快取值 (_BACKUP_DIRNAME_CACHED, 在 backup()/backup_media() 開頭固定一次) 而非即時呼叫,
	# 因為 Backup_data() 內部對非 user/data/obb/user_de/media 類型資料 (如自訂資料夾) 會暫時
	# 把全域 Compression_method 改成 tar 再復原, 若流式上傳剛好在這段窗口期觸發, 即時呼叫
	# get_backup_dirname() 會拿到被污染的值, 導致上傳到錯誤的子資料夾 (如 Backup_tar_0 而非 Backup_zstd_0)
	local _subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_rel="$_subdir/$_rel"
	case $remote_type in
	smb)
		# SMB 流式: 用 cd 切目錄 (對齊既有成功的 upload_smb, -D 會吃掉路徑字元) + put - 從 stdin
		local _auth
		if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _smbpath="$SMB_REM_PATH/$_rel"; _smbpath="${_smbpath#/}"
		local _smbdir="${_smbpath%/*}" _file="${_smbpath##*/}"
		# 1. 先逐層建目錄 (smbclient 內部路徑用反斜線)
		if [[ $_smbdir != $_smbpath ]]; then
			local _mk="" _cur="" _seg _OLDIFS="$IFS"
			IFS='/'; set -- $_smbdir; IFS="$_OLDIFS"
			for _seg; do
				[[ -z $_seg ]] && continue
				if [[ -z $_cur ]]; then _cur="$_seg"; else _cur="$_cur\\$_seg"; fi
				# smbclient stdin 餵命令必須一行一條 (分號在 stdin 模式不是分隔符),
				# 故字串內嵌真換行 (下一行的 " 是字串收尾, 非贅字)
				_mk="${_mk}mkdir \"$_cur\"
"
			done
			printf '%sexit\n' "$_mk" | command smbclient "$SMB_SHARE" $_auth $SMB_OPTS >/dev/null 2>&1
		fi
		# 2. 流式 put -: 用 -c 傳命令 (不佔 stdin!), stdin 留給 put - 讀管道資料
		#    (之前用 printf|smbclient 喂命令會佔住 stdin, 導致 put - 讀不到資料寫出 0KB)
		local _cddir="${_smbdir//\//\\}"
		local _out
		_out="$(command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; put - \"$_file\"" 2>&1)"
		# smbclient 退出碼不可靠, 改看輸出有無錯誤關鍵字
		local _rc=0
		echo "$_out" | grep -qE 'NT_STATUS|does not exist|ERRbadpath|Server (stopped|exited)|Connection.*refused|tree connect failed' && _rc=1
		if [[ $_rc != 0 ]]; then
			echoRgb "[SMB流式失敗] dir=$_cddir file=$_file" "0" >&2
			echo "$_out" | sed 's/^/  /' >&2
		fi
		return $_rc
		;;
	webdav)
		# WebDAV: 先 MKCOL 逐層建父目錄 (rclone serve 不會自動建), 再 curl -T - 上傳
		local _wbase="${remote_url%/}"
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="-u $remote_user:$remote_pass"
		# 逐層建目錄
		local _wdir="${_rel%/*}"
		if [[ $_wdir != $_rel ]]; then
			local _IFS_old="$IFS"; IFS='/'; local _wp="" _wseg
			for _wseg in $_wdir; do
				_wp="$_wp$_wseg/"
				curl -fsS $_wauth -X MKCOL "$_wbase/${_wp%/}" >/dev/null 2>&1
			done
			IFS="$_IFS_old"
		fi
		local _httpcode
		_httpcode="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 30 --speed-time 300 --speed-limit 512 $_wauth -T - "$_wbase/$_rel" 2>"$TMPDIR/.stream_err")"
		local _rc=$?
		[[ $_rc = 0 && $_httpcode -ge 400 ]] && _rc=22
		if [[ $_rc != 0 ]]; then
			echoRgb "[WebDAV流式失敗 rc=$_rc http=$_httpcode] url=$_wbase/$_rel" "0" >&2
			sed 's/^/  /' "$TMPDIR/.stream_err" 2>/dev/null >&2
		fi
		rm -f "$TMPDIR/.stream_err"
		return $_rc
		;;
	*)
		return 1
		;;
	esac
}

# 通用流式下載: 把遠端 (相對遠端根的) 路徑檔案輸出到 stdout
# 依 remote_type 分發 smbclient(get -) / curl. 配合管道解壓: _stream_download "路徑" | zstd -d | tar -x
_stream_download() {
	local _rel="$1"
	case $remote_type in
	smb)
		local _auth
		if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _smbpath="$SMB_REM_PATH/$_rel"; _smbpath="${_smbpath#/}"
		local _smbdir="${_smbpath%/*}" _file="${_smbpath##*/}"
		local _cddir="${_smbdir//\//\\}"
		# get "檔" - : 輸出到 stdout (smbclient 狀態訊息走 stderr, 丟棄)
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; get \"$_file\" -" 2>/dev/null
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="-u $remote_user:$remote_pass"
		curl -fsS --connect-timeout 30 --speed-time 300 --speed-limit 512 $_wauth "${remote_url%/}/$_rel" 2>/dev/null
		;;
	*)
		return 1
		;;
	esac
}

# 解析 SMB URL 並設定 SMB_SHARE / SMB_REM_PATH 全域變數
# SMB_SHARE     = //server/share_name (smbclient -L 用)
# SMB_REM_PATH  = /sub/path (空字串代表 share 根目錄, 不含結尾斜線)
# 重複的 SMB URL 解析邏輯抽出 (原本有 4 個地方各自解析)
remote_parse_smb_url() {
	local url="${remote_url#smb://}"; url="${url%/}"
	local server="${url%%/*}"
	local after_server="${url#$server/}"
	local share_name="${after_server%%/*}"
	# after_server 去掉 share_name 後可能是 "" 或 "/path/..."
	# 直接用結果, 不再前綴 "/", 否則 "/path" 會變 "//path"
	local rem_path="${after_server#$share_name}"
	rem_path="${rem_path%/}"
	[[ $rem_path = / ]] && rem_path=""
	SMB_SHARE="//$server/$share_name"
	SMB_REM_PATH="$rem_path"
}

# 從遠端下載單個文件 (用於備份前對比 app_details.json)
# 用法: remote_download_single_file <遠端相對路徑> <本地目標路徑>
# 回傳: 0=成功, 1=失敗
remote_download_single_file() {
	local remote_rel="$1" local_dest="$2"
	[[ -z $remote_type || -z $remote_url ]] && return 1
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	case $remote_type in
	webdav)
		local base_url="${remote_url%/}/$backup_subdir"
		local enc_rel="$(url_encode_path "$remote_rel")"
		local target_url="$base_url/$enc_rel"
		if [[ -n $remote_user ]]; then
			curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
				-o "$local_dest" "$target_url" 2>/dev/null
		else
			curl -sS -L --http1.1 --connect-timeout 10 \
				-o "$local_dest" "$target_url" 2>/dev/null
		fi
		[[ -s $local_dest ]]
		;;
	smb)
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local base="${rem_path:+$rem_path/}$backup_subdir"
		local dir_part="${remote_rel%/*}"
		local file_part="${remote_rel##*/}"
		local smb_dest="$(mktemp -d "$TMPDIR/.smb_dl_XXXXXX" 2>/dev/null)"
		[[ -z $smb_dest ]] && smb_dest="$TMPDIR/.smb_dl_$$_$RANDOM"
		mkdir -p "$smb_dest" 2>/dev/null
		smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
			-D "$base/$dir_part" \
			-c "lcd $smb_dest; get $file_part; exit" >/dev/null 2>&1
		if [[ -f "$smb_dest/$file_part" ]]; then
			mv "$smb_dest/$file_part" "$local_dest"
			rm -rf "$smb_dest"
			return 0
		else
			rm -rf "$smb_dest"
			return 1
		fi
		;;
	*)
		return 1
		;;
	esac
}

# 過濾 smbclient 輸出的雜訊行 (Try help / dos charset / OS= 等橫幅文字)
# 用法: smb_filter_noise <輸入字串>
smb_filter_noise() {
	echo "$1" | grep -Ev '^Try "help"|^dos charset|^Can.t load|^Domain=|^OS=|^directory_create_or_exist:|^$'
}

# 判斷目錄是否含任何檔案 (非空)
# 用法: dir_has_files <目錄路徑>
# 回傳: 0=有檔案, 1=空目錄或不存在
dir_has_files() {
	[[ -d $1 ]] || return 1
	[[ -n $(find "$1" -type f -print -quit 2>/dev/null) ]]
}

# 啟動時的遠端設定初始化
# 規範化 remote_keep_local 值, 驗證 remote_type, TCP 預檢
# 失敗時清空 remote_type 停用上傳但保留本地備份
remote_setup() {
	# 若之前連線失敗清空了 remote_type, 用原始值恢復以重新檢測 (支援中途開 WiFi 後重試)
	[[ -z $remote_type && -n $_remote_type_orig ]] && remote_type="$_remote_type_orig"
	[[ -z $remote_type ]] && return
	# 規範化 remote_keep_local 成 true/false
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	echoRgb "遠程備份: $remote_type -> $remote_url" "3"
	case $remote_type in
	webdav|smb)
		;;
	*) echoRgb "未知遠程類型: $remote_type (可選: webdav/smb)" "0"; remote_type=""; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "遠端位址未設置 (請設 smb_url 或 webdav_url)，停用遠端上傳" "0"; remote_type=""; return 1; }
	# conf 防呆: 檢查 URL 格式跟協議匹配
	case $remote_type in
	webdav)
		case $remote_url in
		http://*|https://*) ;;
		smb://*)
			echoRgb "remote_type=webdav 但 remote_url 是 smb:// 開頭" "0"
			echoRgb "請改成 http:// 或 https:// 開頭, 或把 remote_type 改成 smb" "3"
			remote_type=""; return 1 ;;
		*)
			echoRgb "remote_url 必須以 http:// 或 https:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			remote_type=""; return 1 ;;
		esac
		;;
	smb)
		case $remote_url in
		smb://*) ;;
		http://*|https://*)
			echoRgb "remote_type=smb 但 remote_url 是 http(s):// 開頭" "0"
			echoRgb "請改成 smb:// 開頭, 或把 remote_type 改成 webdav" "3"
			remote_type=""; return 1 ;;
		"")
			# 未填地址: 自動掃描區網 SMB 並填入第一台的第一個共享
			echoRgb "remote_url 未填, 自動掃描區網 SMB..." "3"
			if smb_autodetect_url; then
				echoRgb "自動填入: $remote_url" "1"
			else
				echoRgb "自動掃描未找到可用 SMB, 請手動填 remote_url" "0"
				remote_type=""; return 1
			fi
			;;
		*)
			echoRgb "remote_url 必須以 smb:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			remote_type=""; return 1 ;;
		esac
		;;
	esac
	# 帳密為空提醒 (非致命, 可能是匿名認證)
	[[ -z $remote_user ]] && echoRgb "remote_user 未設定 (將以匿名嘗試連線)" "0"
	# 事前連線測試: 從各協議解出 host:port 做快速 TCP 探測
	remote_parse_endpoint
	# 流式模式需要 SMB_SHARE/SMB_REM_PATH (平時在 upload 函數才解析, 流式不走那裡, 故這裡先解析)
	[[ $remote_stream = 1 && $remote_type = smb ]] && remote_parse_smb_url
	# 端口跟協議不一致警告 (常見錯誤: https 配 80 或 http 配 443)
	if [[ $remote_type = webdav ]]; then
		case "$remote_url:$REMOTE_PORT" in
		https://*:80)
			echoRgb "警告: HTTPS 通常用 443, 你設 80 (可能應改用 http://)" "0" ;;
		http://*:443)
			echoRgb "警告: HTTP 通常用 80, 你設 443 (可能應改用 https://)" "0" ;;
		esac
	fi
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線測試通過 ($REMOTE_HOST:$REMOTE_PORT)" "1"
		if [[ $remote_stream = 1 ]]; then
			echoRgb "流式上傳模式 (邊壓邊傳, 不佔本機空間)" "3"
			# WebDAV 流式需伺服器支援 chunked PUT (Synology 等 Apache WebDAV 常不支援, 回 411)
			if [[ $remote_type = webdav ]]; then
				local _wauth_t=""
				[[ -n $remote_user ]] && _wauth_t="-u $remote_user:$remote_pass"
				if ! echo "chunked_test" | curl -fsS -o /dev/null --connect-timeout 15 $_wauth_t -T - "${remote_url%/}/.stream_chunk_test" 2>/dev/null; then
					echoRgb "此 WebDAV 伺服器不支援串流上傳 (chunked PUT, 如 Synology 內建 WebDAV)" "0"
					echoRgb "流式模式無法使用, 請改用 SMB 或 rclone serve webdav, 或設 remote_stream=0" "3"
					exit 1
				fi
				curl -fsS $_wauth_t -X DELETE "${remote_url%/}/.stream_chunk_test" >/dev/null 2>&1
			fi
		elif [[ $remote_keep_local = true ]]; then
			echoRgb "備份完成後將自動上傳到遠端 (保留本地檔案)" "3"
		else
			echoRgb "備份完成後將自動上傳到遠端 (上傳成功後刪除本地檔案)" "3"
		fi
	else
		echoRgb "遠端連線測試失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		echoRgb "可能原因: 未開WiFi/位址錯誤/伺服器未啟動/協議端口不匹配" "0"
		echoRgb "本次將停用遠端上傳，備份僅保留在本地" "0"
		remote_type=""
	fi
}

# 獨立的測試遠端入口 (給選單用)
# 1. 顯示 conf 設定
# 2. TCP 預檢
# 3. 嘗試認證 + list 遠端目錄
# 不會實際上傳任何東西
# 單獨上傳某個 app 的備份 (給子目錄 upload.sh 用)
# 假設呼叫時 Backup 是備份根目錄 (Backup_zstd_X)
# $1 = app 名 (子目錄名)
single_upload() {
	local app_name="$1"
	[[ -z $app_name ]] && { echoRgb "single_upload: 缺少 app 名" "0"; return 1; }
	[[ -z $Backup ]] && Backup="$MODDIR"
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && { echoRgb "找不到目錄: $target" "0"; return 1; }
	dir_has_files "$target" || { echoRgb "$app_name 目錄為空,沒有東西可上傳" "0"; return 1; }
	# 重置範圍 flag, 只標記這一個
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	case $app_name in
	Media) REMOTE_UPLOAD_MEDIA=1 ;;
	wifi) REMOTE_UPLOAD_WIFI=1 ;;
	*) REMOTE_APPLIST="$app_name" ;;
	esac
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	echoRgb "—————— 單獨上傳: $app_name ——————" "3"
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 邊備份邊上傳：每備份完一個應用後立即上傳並刪除本機檔案
# $1 = 應用名 (目錄名)
# 依賴 global: remote_type, remote_keep_local, Backup
per_app_upload_and_cleanup() {
	local app_name="$1"
	[[ -z $app_name ]] && return 1
	[[ -z $Backup ]] && return 1
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && return 0
	dir_has_files "$target" || return 0
	[[ -z $remote_type ]] && return 1
	# 合併遠端 app_details.json 到本地，避免丢失遠端已有的字段
	local local_app_details="$target/app_details.json"
	local remote_app_details="$TMPDIR/.remote_app_details_merge_$$"
	local remote_rel="${app_name}/app_details.json"
	if [[ -f $local_app_details ]] && remote_download_single_file "$remote_rel" "$remote_app_details" 2>/dev/null; then
		[[ -s $remote_app_details ]] && {
			# 合併遠端數據到本地（本地數據優先，但保留遠端已有的字段）
			local merged="$TMPDIR/.merged_app_details_$$"
			jq -s '.[0] * .[1]' "$remote_app_details" "$local_app_details" > "$merged" 2>/dev/null && mv "$merged" "$local_app_details"
			rm -f "$merged"
		}
	fi
	rm -f "$remote_app_details"
	# 設定上傳範圍：只上傳這一個 app, 跳過 tools/ 等固定項避免重複上傳
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則由上傳函數自動處理
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	REMOTE_APPLIST="$app_name"
	REMOTE_SKIP_FIXED=1
	REMOTE_APPDETAILS_SKIP=1
	REMOTE_QUIET=1
	REMOTE_TRIGGER=1
	REMOTE_APPDETAILS_FILE="$Backup/$app_name/app_details.json"
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 清除標記
	unset REMOTE_TRIGGER REMOTE_SKIP_FIXED REMOTE_APPLIST REMOTE_APPDETAILS_SKIP REMOTE_QUIET REMOTE_APPDETAILS_FILE
}

# 主選單觸發: 讀 appList.txt + Custom_path, 直接上傳對應目錄
# 不互動,等同於跑完整備份後的自動上傳,但不重新備份
upload_current_backup() {
	backup_path
	[[ ! -d $Backup ]] && { echoRgb "本地備份目錄不存在: $Backup" "0"; return 1; }
	echoRgb "本地備份: $Backup" "2"
	show_conf remote
	# remote_setup 連線失敗或未設定時會清空 remote_type → 直接終止, 不再詢問
	# 用 remote_url 區分: 有設 URL 但 type 被清空 = 連線失敗; 沒設 URL = 未設定
	if [[ -z $remote_type ]]; then
		if [[ -n $remote_url ]]; then
			echoRgb "遠端連線失敗 (請檢查 WiFi/伺服器), 無法上傳" "0"
		else
			echoRgb "未設定遠端, 無法上傳" "0"
		fi
		return 1
	fi
	# 選擇上傳模式: 1=按清單(appList) 2=整個目錄
	unset REMOTE_FULL_DIR
	unset _up_mode
	if ! ask_yn "上傳模式" "按清單上傳" "上傳整個Backup目錄"; then
		REMOTE_FULL_DIR=1
	fi
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		echoRgb "已選擇: 上傳整個 Backup 目錄 (排除 log)" "2"
	else
		# 讀 appList.txt (跟備份用同一個解析邏輯)
		local applist=""
		if [[ -n $list_location ]]; then
			if [[ ${list_location:0:1} = / ]]; then
				[[ -f $list_location ]] && applist="$list_location"
			else
				[[ -f $MODDIR/$list_location ]] && applist="$MODDIR/$list_location"
			fi
		fi
		[[ -z $applist && -f $MODDIR/appList.txt ]] && applist="$MODDIR/appList.txt"
		# 組裝 REMOTE_APPLIST (跟 backup() 用同一個變數,讓 collect_targets 認得)
		unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
		if [[ -n $applist ]]; then
			REMOTE_APPLIST="$(cat "$applist")"
			local app_count
			app_count=$(echo "$REMOTE_APPLIST" | grep -cEv '^[[:space:]]*[#＃!]|^[[:space:]]*$')
			echoRgb "讀取 $applist (有效 $app_count 個 app)" "2"
		else
			echoRgb "找不到 appList.txt" "0"
		fi
		# 讀 Custom_path: 有設就帶上 Media
		if [[ -n $Custom_path ]]; then
			if dir_has_files "$Backup/Media"; then
				REMOTE_UPLOAD_MEDIA=1
				echoRgb "Custom_path 已設, 將上傳 Media" "2"
			fi
		fi
		# wifi 目錄存在就一併上傳
		if dir_has_files "$Backup/wifi"; then
			REMOTE_UPLOAD_WIFI=1
			echoRgb "wifi 目錄存在, 將上傳 wifi" "2"
		fi
		if [[ -z $REMOTE_APPLIST && $REMOTE_UPLOAD_MEDIA != 1 && $REMOTE_UPLOAD_WIFI != 1 ]]; then
			echoRgb "沒有可上傳項目 (appList 為空, Custom_path 未設, 無 wifi)" "0"
			return 1
		fi
	fi
	# 上傳前統計大小並確認
	local _pre_list="$TMPDIR/.precheck_list" _pre_bytes
	remote_collect_targets "$_pre_list"
	if [[ ! -s $_pre_list ]]; then
		echoRgb "沒有可上傳的檔案" "0"; rm -f "$_pre_list" 2>/dev/null; return 1
	fi
	local _pre_count="$(wc -l < "$_pre_list")"
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		# 全目錄模式: 用 du 算整個目錄 (跟備份時 Calculate_size 同源), 減去 log
		local _all _log
		# 純文件字節, 排除根目錄 log (整體 - log, 兩者同算法相減精確)
		local _all _log
		_all="$(calc_dir_size "$Backup")"
		_log="$(calc_dir_size "$Backup/log" 2>/dev/null)"
		_pre_bytes=$(awk -v a="${_all:-0}" -v l="${_log:-0}" 'BEGIN{print a-l}')
	else
		_pre_bytes="$(list_total_size "$_pre_list")"
	fi
	echoRgb "本次上傳: $_pre_count 個檔案, 總大小 $(size "$_pre_bytes") (位元組:$_pre_bytes)" "3"
	rm -f "$_pre_list" 2>/dev/null
	if ! ask_yn "確認上傳?" "確認上傳" "取消"; then
		echoRgb "已取消上傳" "1"; return 0
	fi
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 測試遠端連線完整性 (主選單第 6 項)
# 三層測試: TCP 預檢 → 認證 → 路徑訪問
# 每層失敗都有具體錯誤訊息 (帳密錯/路徑不存在/分享不存在等)
remote_test() {
	echoRgb "============== 遠端連線測試 ==============" "3"
	show_conf remote
	if [[ -z $remote_type ]]; then
		echoRgb "remote_type 未設定" "0"
		echoRgb "請編輯 $conf_path 設定 remote_type/remote_url/remote_user/remote_pass" "3"
		return 1
	fi
	echoRgb "類型: $remote_type" "2"
	echoRgb "位址: $remote_url" "2"
	echoRgb "帳號: ${remote_user:-(未設)}" "2"
	[[ -n $remote_pass ]] && echoRgb "密碼: ********" "2" || echoRgb "密碼: (未設)" "2"
	echoRgb "保留本地: ${remote_keep_local:-0}" "2"
	case $remote_type in
	webdav|smb) ;;
	*) echoRgb "未知 remote_type: $remote_type (可選: webdav/smb)" "0"; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url 未設置" "0"; return 1; }
	# 協議與 URL 一致性檢查
	case $remote_type in
	webdav)
		case $remote_url in
		http://*|https://*) ;;
		smb://*)
			echoRgb "remote_type=webdav 但 remote_url 是 smb:// 開頭" "0"
			echoRgb "請改 remote_type=smb, 或把 remote_url 改成 http(s)://" "3"
			return 1 ;;
		*://*)
			echoRgb "remote_url 協議 (${remote_url%%://*}://) 不被 webdav 支援" "0"
			echoRgb "WebDAV 只支援 http:// 或 https://" "3"
			return 1 ;;
		*)
			echoRgb "remote_url 必須以 http:// 或 https:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			return 1 ;;
		esac ;;
	smb)
		case $remote_url in
		smb://*) ;;
		http://*|https://*)
			echoRgb "remote_type=smb 但 remote_url 是 http(s):// 開頭" "0"
			echoRgb "請改 remote_type=webdav, 或把 remote_url 改成 smb://" "3"
			return 1 ;;
		*://*)
			echoRgb "remote_url 協議 (${remote_url%%://*}://) 不被 smb 支援" "0"
			echoRgb "SMB 只支援 smb://" "3"
			return 1 ;;
		*)
			echoRgb "remote_url 必須以 smb:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			return 1 ;;
		esac ;;
	esac
	scan_smb
	# 第一關: TCP 預檢
	remote_parse_endpoint
	echoRgb "—————— TCP 連線測試 ——————" "3"
	echoRgb "目標: $REMOTE_HOST:$REMOTE_PORT" "2"
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "TCP 連線通過" "1"
	else
		echoRgb "TCP 連線失敗" "0"
		echoRgb "可能原因:" "0"
		echoRgb "WiFi 未開啟或不在同網段" "0"
		echoRgb "伺服器 IP / port 寫錯" "0"
		echoRgb "伺服器未啟動 / 防火牆阻擋" "0"
		return 1
	fi
	# 第二關: 認證 + 列目錄
	echoRgb "—————— 認證與列目錄測試 ——————" "3"
	case $remote_type in
	smb)
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local out
		out="$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
			-c "cd ${rem_path:-/}; ls; exit" 2>&1)"
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_LOGON_FAILURE'; then
			echoRgb "認證失敗 (帳號或密碼錯誤)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_ACCESS_DENIED'; then
			echoRgb "存取被拒 (帳號權限不足)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_BAD_NETWORK_NAME'; then
			echoRgb "share 名稱錯誤: $share_name (請檢查伺服器是否有此分享)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端路徑不存在: $rem_path (將在首次上傳時建立)" "3"
		elif echo "$out" | grep -qE 'NT_STATUS_(CONNECTION_REFUSED|IO_TIMEOUT|HOST_UNREACHABLE)'; then
			echoRgb "網路不通 (伺服器無回應)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_UNSUCCESSFUL'; then
			echoRgb "SMB 連線失敗 (NT_STATUS_UNSUCCESSFUL)" "0"
			echoRgb "常見原因: 端口錯誤 / SMB 協議版本不相容 / 伺服器拒絕" "3"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "SMB 錯誤:" "0"
			echo "$out" | head -5
			return 1
		else
			echoRgb "認證通過, share 可存取" "1"
			echoRgb "遠端路徑 $remote_url 可存取" "1"
			# 抓實際協商出的 SMB 協議版本
			# 不同 Samba 版本輸出格式不同, 先把 debug 輸出存檔再多路徑抓取
			local _dbg="$TMPDIR/.smb_dbg_$$"
			smbclient "$share" -U "$remote_user%$remote_pass" -t 5 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 -d 5 \
				-c 'exit' >"$_dbg" 2>&1
			local _proto
			# 試多種關鍵字 (依不同 Samba 版本)
			_proto="$(grep -oiE 'protocol negotiation: server.*\[(SMB[0-9_]+|NT[0-9]*)\]|Selected protocol \[?(SMB[0-9_]+|NT[0-9]*)|Negotiated dialect \[?(SMB[0-9_]+|NT[0-9]*)|protocol \[(SMB[0-9_]+|NT[0-9]*)\] negotiated|dialect.*(SMB[0-9_]+|NT[0-9]*)' "$_dbg" | grep -oE '(SMB[0-9_]+|NT[0-9]*)' | head -1)"
			if [[ -n $_proto ]]; then
				echoRgb "協議版本: $_proto" "1"
			else
				# fallback: 抓出所有看似協議版本的字串
				_proto="$(grep -oiE 'SMB[123]_[0-9]{2}' "$_dbg" | sort -u | tail -1)"
				[[ -n $_proto ]] && echoRgb "協議版本: $_proto (推測)" "1"
				# 若仍抓不到, 保留 debug 輸出供排查
				[[ -z $_proto ]] && {
					echoRgb "無法解析協議版本, debug 輸出留在: $_dbg" "2"
					return 0
				}
			fi
			rm -f "$_dbg"
		fi
		;;
	webdav)
		local base_url="${remote_url%/}"
		local code curl_err
		# stderr 寫到檔案, 別污染 http_code
		code="$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 0" -w '%{http_code}' -o /dev/null "$base_url" 2>"$TMPDIR/.curl_test_err")"
		curl_err="$(cat "$TMPDIR/.curl_test_err" 2>/dev/null)"
		rm -f "$TMPDIR/.curl_test_err"
		case $code in
		2*|207) echoRgb "WebDAV 認證通過 (HTTP $code)" "1" ;;
		401) echoRgb "認證失敗 (HTTP 401, 帳號或密碼錯誤)" "0"; return 1 ;;
		403) echoRgb "權限不足 (HTTP 403)" "0"; return 1 ;;
		404) echoRgb "路徑不存在 (HTTP 404)" "0"; return 1 ;;
		405) echoRgb "方法不允許 (HTTP 405, 此 URL 可能不是 WebDAV 端點)" "0"; return 1 ;;
		408) echoRgb "請求逾時 (HTTP 408, 伺服器繁忙)" "0"; return 1 ;;
		423) echoRgb "資源被鎖定 (HTTP 423, 有其他客戶端正在寫入)" "0"; return 1 ;;
		429) echoRgb "請求過於頻繁 (HTTP 429, 觸發伺服器限流)" "0"; return 1 ;;
		500) echoRgb "伺服器內部錯誤 (HTTP 500)" "0"; return 1 ;;
		502) echoRgb "閘道錯誤 (HTTP 502, 反向代理 / 上游服務有問題)" "0"; return 1 ;;
		503) echoRgb "服務不可用 (HTTP 503, 伺服器維護或過載)" "0"; return 1 ;;
		504) echoRgb "閘道逾時 (HTTP 504)" "0"; return 1 ;;
		3*) echoRgb "未處理的重定向 (HTTP $code, curl -L 已展開但仍失敗, 可能跳到非 WebDAV 端點)" "0"; return 1 ;;
		000)
			# curl 連 HTTP 都還沒走到, 看 stderr 判斷具體原因
			echoRgb "curl 無法完成請求" "0"
			case $curl_err in
			*WRONG_VERSION_NUMBER*|*wrong\ version\ number*)
				echoRgb "原因: 協議跟端口不匹配 (URL 寫 https 但伺服器是 http, 或反過來)" "0"
				case $remote_url in
				https://*) echoRgb "建議: 把 remote_url 改成 http://$REMOTE_HOST:$REMOTE_PORT/..." "3" ;;
				http://*) echoRgb "建議: 把 remote_url 改成 https://$REMOTE_HOST:$REMOTE_PORT/..." "3" ;;
				esac ;;
			*"Could not resolve host"*|*"Couldn't resolve host"*)
				echoRgb "原因: DNS 解析失敗 (域名不存在或 DNS 服務問題)" "0" ;;
			*"Connection refused"*)
				echoRgb "原因: 連線被拒 (端口未開或防火牆攔截)" "0" ;;
			*"Connection timed out"*|*"timed out"*)
				echoRgb "原因: 連線逾時 (網路或防火牆問題)" "0" ;;
			*"SSL certificate"*|*"certificate verify"*|*"server certificate verification failed"*)
				echoRgb "原因: SSL 證書驗證失敗 (自簽證書或過期)" "0"
				echoRgb "建議: 若是自簽證書, 改用 http://, 或在 curl 加 -k (需改腳本)" "3" ;;
			*"SSL_ERROR_SYSCALL"*|*"SSL connect error"*)
				echoRgb "原因: SSL 握手失敗 (TLS 版本不相容 / 伺服器斷線)" "0" ;;
			*"server certificate verification failed"*)
				echoRgb "原因: 伺服器證書驗證失敗" "0"
				echoRgb "建議: 若是自簽證書, 用 http:// 或在 curl 加 -k (需改腳本)" "3" ;;
			*"Host requires authentication"*|*"401 Unauthorized"*)
				echoRgb "原因: 需要認證但帳密為空或錯誤" "0" ;;
			*"Operation too slow"*)
				echoRgb "原因: 傳輸過慢被中斷" "0" ;;
			*"Empty reply from server"*)
				echoRgb "原因: 伺服器收到請求但沒回應 (服務未啟動 / 配置錯誤)" "0" ;;
			*) echoRgb "詳細: $curl_err" "0" ;;
			esac
			return 1 ;;
		*)   echoRgb "WebDAV 異常 (HTTP $code)" "0"
			[[ -n $curl_err ]] && echoRgb "詳細: $curl_err" "0"
			return 1 ;;
		esac
		;;
	esac
	echoRgb "========================================" "3"
	echoRgb "全部測試通過, 可以開始備份" "1"
	return 0
}

# 列出遠端可用的備份目錄並產生 appList_network.txt
# 流程: 連遠端 → 列 Backup_*_* 目錄 → 讓使用者選 → 檢查必要檔案 → 掃 app 清單 → 輸出
remote_list_backups() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	# 規範化 remote_keep_local
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	# 目標目錄 = 跟本地備份一樣的命名規則
	local target_dir="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $target_dir" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	# 進入目標目錄, 列出檔案/子資料夾
	local sub_listing="$TMPDIR/.remote_sub_listing"
	: > "$sub_listing"
	if [[ $remote_type = smb ]]; then
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local smb_out
		smb_out=$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
			-c "cd ${rem_path:-/}/$target_dir; ls; exit" 2>&1)
		if echo "$smb_out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端目錄不存在: $target_dir" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			rm -f "$sub_listing"
			return 1
		fi
		if echo "$smb_out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "讀取遠端失敗:" "0"
			echo "$smb_out" | grep -E 'NT_STATUS|ERR' | head -3
			rm -f "$sub_listing"
			return 1
		fi
		# 格式: "D dirname" 或 "N filename"
		echo "$smb_out" | awk 'NF>=5 && $1 != "." && $1 != ".." {print $2, $1}' > "$sub_listing"
	elif [[ $remote_type = webdav ]]; then
		local base_url="${remote_url%/}"
		local http_code
		http_code=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$TMPDIR/.wdav_out" \
			"$base_url/$target_dir/" 2>/dev/null)
		# debug: 把 PROPFIND 原始回應寫到 log 供除錯
		local dbg_log="${logfile%/*}/webdav_debug.log"
		mkdir -p "${logfile%/*}" 2>/dev/null
		{
			echo "===== WebDAV PROPFIND $(date '+%Y-%m-%d %H:%M:%S') ====="
			echo "URL: $base_url/$target_dir/"
			echo "HTTP code: $http_code"
			echo "----- Raw XML response -----"
			cat "$TMPDIR/.wdav_out" 2>/dev/null
			echo ""
			echo "----- End -----"
		} > "$dbg_log"
		case $http_code in
		2*) ;;
		404)
			echoRgb "遠端目錄不存在: $target_dir (HTTP 404)" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			# PROPFIND 根目錄看實際有什麼, 幫用戶確認路徑名
			local root_code root_xml="$TMPDIR/.wdav_root"
			root_code=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
				-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$root_xml" \
				"$base_url/" 2>/dev/null)
			{
				echo ""
				echo "----- 根目錄探測 PROPFIND $base_url/ -----"
				echo "HTTP code: $root_code"
				cat "$root_xml" 2>/dev/null
				echo ""
			} >> "$dbg_log"
			case $root_code in
			2*)
				# 抓 href 列表給用戶看
				local found
				found=$(cat "$root_xml" 2>/dev/null | tr '><' '\n' | awk '
					/^(D:)?response$/ { in_resp=1; href="" }
					/^\/(D:)?response$/ { if (in_resp && href != "") print href; in_resp=0 }
					/^(D:)?href$/ { getline href }
				' | grep -v '^/$' | grep -v "^${base_url#http*://*/}$")
				if [[ -n $found ]]; then
					echoRgb "遠端根目錄實際有以下項目:" "3"
					echo "$found" | head -20
				fi
				;;
			esac
			rm -f "$root_xml"
			echoRgb "原始回應已記錄: $dbg_log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		*) echoRgb "讀取遠端失敗 (HTTP $http_code)" "0"
			echoRgb "原始回應已記錄: $dbg_log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		esac
		local propfind_out
		propfind_out=$(cat "$TMPDIR/.wdav_out" 2>/dev/null)
		rm -f "$TMPDIR/.wdav_out"
		# 解析每個 response, 過濾掉「目錄自己」(href 跟 base 同名)
		# 收集成 "D|encoded_name" 或 "N|encoded_name"
		# 兼容兩種 WebDAV XML 格式: 有 D: 名前綴 或無前綴
		# 注意: busybox awk 對 ($|[..]) 解析有 bug, 改用 sub 去除前綴後字串比對
		local raw_listing="$TMPDIR/.raw_wdav_listing"
		echo "$propfind_out" | tr '><' '\n' | awk '
			{
				# 取每行第一個 token (去掉屬性)
				tag = $1
				# 去掉 D: 前綴, 處理 /D: 也變 /
				sub(/^D:/, "", tag)
				sub(/^\/D:/, "/", tag)
				# 去掉自關閉的 / (collection/ → collection)
				sub(/\/$/, "", tag)
			}
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					n = split(href, a, "/")
					name = a[n]
					if (name == "" && n > 1) name = a[n-1]
					if (name != "" && name != "/") {
						print (is_dir ? "D" : "N") "|" name
					}
				}
				in_resp=0
				next
			}
			tag == "href" { getline href; next }
			tag == "collection" { is_dir=1 }
		' > "$raw_listing"
		# 過濾掉目錄自己 (encoded 或非 encoded 都比對)
		# target_dir 是 "Backup_zstd_0" 純 ASCII,不需要編碼
		grep -vE "\|${target_dir}\$" "$raw_listing" > "$sub_listing"
		rm -f "$raw_listing"
		# URL 解碼 (支援 UTF-8 中文)
		# 用 printf 將 %XX 轉成實際字元
		local decoded="$TMPDIR/.decoded_listing"
		: > "$decoded"
		while IFS='|' read -r typ name; do
			[[ -z $name ]] && continue
			# printf '%b' 不認 %XX, 要先轉成 \xXX
			local converted
			converted=$(echo "$name" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
			# 用 printf 把 \xXX 還原成真實字元
			local real
			real=$(printf '%b' "$converted")
			echo "$typ $real" >> "$decoded"
		done < "$sub_listing"
		mv "$decoded" "$sub_listing"
	fi
	if [[ ! -s $sub_listing ]]; then
		echoRgb "遠端目錄為空或讀取失敗" "0"
		# 列出 raw XML 跟解析後的結果到 log 方便除錯
		if [[ $remote_type = webdav && -f ${logfile%/*}/webdav_debug.log ]]; then
			{
				echo ""
				echo "----- Parsed listing (sub_listing) -----"
				[[ -f $sub_listing ]] && cat "$sub_listing"
				echo "(empty)"
			} >> "${logfile%/*}/webdav_debug.log"
			echoRgb "詳細回應已記錄: ${logfile%/*}/webdav_debug.log" "3"
		fi
		rm -f "$sub_listing"
		return 1
	fi
	# 檢查必要檔案: tools/ start.sh restore_settings.conf
	local has_tools=0 has_start=0 has_conf=0
	while read -r type name; do
		case "$name" in
		tools) [[ $type = D ]] && has_tools=1 ;;
		start.sh) [[ $type != D ]] && has_start=1 ;;
		restore_settings.conf) [[ $type != D ]] && has_conf=1 ;;
		esac
	done < "$sub_listing"
	local missing=""
	[[ $has_tools = 0 ]] && missing="$missing tools/"
	[[ $has_start = 0 ]] && missing="$missing start.sh"
	[[ $has_conf = 0 ]] && missing="$missing restore_settings.conf"
	if [[ -n $missing ]]; then
		echoRgb "錯誤: 遠端 $target_dir 缺少必要檔案:$missing" "0"
		echoRgb "此備份不完整,無法用於恢復" "0"
		rm -f "$sub_listing"
		return 1
	fi
	echoRgb "必要檔案檢查通過 (tools/ start.sh restore_settings.conf)" "1"
	# 產生 appList_network.txt
	# 規則:
	#   - 排除 tools, start.sh, restore_settings.conf (固定下載項)
	#   - 是目錄: wifi/Media → 特殊項; 其他 → app
	#   - 是檔案就忽略
	local out="$MODDIR/appList_network.txt"
	# 遠端 app 清單
	local apps="$TMPDIR/.apps_list"
	: > "$apps"
	while read -r type name; do
		[[ $type = D ]] || continue
		case "$name" in
		tools|wifi|Media) continue ;;
		esac
		echo "$name" >> "$apps"
	done < "$sub_listing"
	sort "$apps" > "$TMPDIR/.apps_sorted"
	# 本地備份資料夾清單
	local local_apps="$TMPDIR/.local_apps"
	local _local_backup="$MODDIR/$(get_backup_dirname)"
	: > "$local_apps"
	for _d in "$_local_backup"/*/; do
		_d="${_d%/}"; _d="${_d##*/}"
		case "$_d" in tools|wifi|Media|log) continue ;; esac
		[[ -f "$_local_backup/$_d/app_details.json" ]] && echo "$_d" >> "$local_apps"
	done
	sort "$local_apps" > "$TMPDIR/.local_sorted"
	local only_remote only_local
	only_remote="$(comm -23 "$TMPDIR/.apps_sorted" "$TMPDIR/.local_sorted")"
	only_local="$(comm -13 "$TMPDIR/.apps_sorted" "$TMPDIR/.local_sorted")"
	{
		echo "# 遠端備份目錄: $target_dir"
		echo "# 連線: $remote_type://$REMOTE_HOST/"
		echo "# 用 # 註解掉不要下載的項目, 編輯完選 '從遠端下載備份' 即可"
		echo ""
		echo "# ---- 應用 (每行一個 app) ----"
		cat "$TMPDIR/.apps_sorted"
		echo ""
		echo "# ---- 特殊項目 (非 app, 有就會下載) ----"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in
			wifi|Media) echo "$name" ;;
			esac
		done < "$sub_listing"
		echo ""
		echo "# ---- 比對結果 ----"
		if [[ -n $only_remote ]]; then
			echo "# 遠端有、本地無 (可下載):"
			echo "$only_remote" | while read -r _n; do echo "#   $_n"; done
		fi
		if [[ -n $only_local ]]; then
			echo "# 本地有、遠端無 (未上傳):"
			echo "$only_local" | while read -r _n; do echo "#   $_n"; done
		fi
		[[ -z $only_remote && -z $only_local ]] && echo "# 本地與遠端完全一致"
	} > "$out"
	cp "$TMPDIR/.apps_sorted" "$TMPDIR/.apps_sorted_keep" 2>/dev/null
	rm -f "$apps" "$TMPDIR/.apps_sorted" "$local_apps" "$TMPDIR/.local_sorted"
	rm -f "$sub_listing"
	echoRgb "已輸出清單: $out" "1"
	local _rc _lc
	[[ -n $only_remote ]] && _rc="$(echo "$only_remote" | grep -c .)"
	[[ -n $only_local ]]  && _lc="$(echo "$only_local"  | grep -c .)"
	[[ -n $only_remote ]] && echoRgb "遠端有、本地無: ${_rc}個" "3" && echo "$only_remote" | while read -r _n; do echoRgb "$_n" "3"; done
	[[ -n $only_local ]]  && echoRgb "本地有、遠端無: ${_lc}個" "0" && echo "$only_local"  | while read -r _n; do echoRgb "$_n" "0"; done
	[[ -z $only_remote && -z $only_local ]] && echoRgb "本地與遠端完全一致" "1"
	# 有差異時提供快速操作
	if [[ -n $only_local ]]; then
		if ask_yn "立即上傳本地多出的應用?" "上傳" "跳過"; then
			backup_path
			REMOTE_APPLIST="$only_local"
			REMOTE_TRIGGER=1
			case $remote_type in
			smb) upload_smb ;;
			webdav) upload_remote "webdav" ;;
			esac
			unset REMOTE_TRIGGER REMOTE_APPLIST
		fi
	fi
	if [[ -n $only_remote ]]; then
		if ask_yn "立即下載遠端多出的應用?" "下載" "跳過"; then
			local _dl_items="$TMPDIR/.dl_diff_items"
			echo "$only_remote" > "$_dl_items"
			local chosen="$(get_backup_dirname)"
			local dest="$MODDIR/$chosen"
			mkdir -p "$dest" 2>/dev/null
			remote_parse_endpoint
			if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
				if [[ $remote_type = smb ]]; then
					_remote_download_smb "$chosen" "$dest" "$_dl_items"
				elif [[ $remote_type = webdav ]]; then
					_remote_download_webdav "$chosen" "$dest" "$_dl_items"
				fi
			else
				echoRgb "遠端連線失敗" "0"
			fi
			rm -f "$_dl_items"
		fi
	fi
	ask_yn_indep "順手檢查遠端app_details.json健全度? (會逐個下載驗證,較耗時)" "檢查" "跳過"
	if [[ $branch = true ]]; then
		local _ra _jchk_total _jchk_i=0 _running=0
		_jchk_total="$(grep -vc '^$' "$TMPDIR/.apps_sorted_keep" 2>/dev/null)"
		rm -rf "$TMPDIR/.health_check_dl" 2>/dev/null
		mkdir -p "$TMPDIR/.health_check_dl" 2>/dev/null
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			let _jchk_i++
			printf '\r -下載中 %d/%d' "$_jchk_i" "$_jchk_total" >&2
			( _get_remote_appdetails "$_ra" "$TMPDIR/.health_check_dl/$_ra.json" 2>/dev/null ) &
			let _running++
			if [[ $_running -ge 8 ]]; then wait; _running=0; fi
		done < "$TMPDIR/.apps_sorted_keep"
		wait
		echo >&2
		# 下載完畢後序列跑健全檢查 (純本地讀檔, 快, 不需並發)
		_jchk_i=0
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			let _jchk_i++
			echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
			[[ -s "$TMPDIR/.health_check_dl/$_ra.json" ]] && \
				_json_health_check "$TMPDIR/.health_check_dl/$_ra.json" "$_ra (遠端)"
		done < "$TMPDIR/.apps_sorted_keep"
		rm -rf "$TMPDIR/.health_check_dl" 2>/dev/null
		echoRgb "檢查完成 $_jchk_i/$_jchk_total" "1"
		_json_health_report
	fi
	rm -f "$TMPDIR/.apps_sorted_keep" 2>/dev/null
	echoRgb "請編輯該檔案,留下你要下載的項目,然後選 '從遠端下載備份'" "3"
}

# 依 appList_network.txt 下載備份到 $MODDIR/Backup_*_$user
remote_download_backup() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	local list="$MODDIR/appList_network.txt"
	if [[ ! -f $list ]]; then
		echoRgb "找不到 $list" "0"
		echoRgb "請先執行 '列出遠端備份' 產生清單" "3"
		return 1
	fi
	local dl_start
	dl_start=$(date +%s)
	# 目標目錄 = 跟本地備份一樣的命名規則
	local chosen="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $chosen" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	# 解析清單 (去除註解/空行)
	local items_file="$TMPDIR/.dl_items"
	grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$list" > "$items_file"
	if [[ ! -s $items_file ]]; then
		echoRgb "清單為空,沒有東西需要下載" "0"
		rm -f "$items_file"
		return 1
	fi
	local item_count
	item_count=$(wc -l < "$items_file")
	echoRgb "將下載 $item_count 個項目 + 固定 3 項 (tools/ start.sh restore_settings.conf)" "3"
	# 下載目標: $MODDIR/$chosen (例: $MODDIR/Backup_zstd_0)
	local dest="$MODDIR/$chosen"
	mkdir -p "$dest" 2>/dev/null
	echoRgb "下載到: $dest" "2"
	# 依協議分派
	local fail=0
	if [[ $remote_type = smb ]]; then
		_remote_download_smb "$chosen" "$dest" "$items_file" || fail=1
	elif [[ $remote_type = webdav ]]; then
		_remote_download_webdav "$chosen" "$dest" "$items_file" || fail=1
	fi
	rm -f "$items_file"
	local dl_elapsed=$(( $(date +%s) - dl_start ))
	if [[ $fail -eq 0 ]]; then
		echoRgb "_______________________________________" "2"
		echoRgb "下載完成: $dest 用時${dl_elapsed}秒" "1"
		echoRgb "可直接執行 $dest/start.sh 進行恢復" "3"
		remote_log "下載完成: $dest 用時${dl_elapsed}秒"
	else
		echoRgb "下載過程有失敗,請檢查上方訊息 (用時${dl_elapsed}秒)" "0"
		remote_log "下載失敗 用時${dl_elapsed}秒"
		return 1
	fi
}

# SMB 下載實作
# 每個 item 一次 smbclient (用 -D 直接切目錄,避免 cd 路徑解析問題)
# $1=遠端 Backup_zstd_X 目錄名, $2=本地目標, $3=要下載的項目清單檔
_remote_download_smb() {
	local chosen="$1" dest="$2" items_file="$3"
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	local base="${rem_path:+$rem_path/}$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local idx=0 fail_total=0
	# 下載每個項目 (用 -D 切到指定目錄, 再 mget *)
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		echoRgb "[$idx/$total_items] $(progress_bar $((idx * 100 / total_items))) 下載 $item" "3"
		mkdir -p "$dest/$item" 2>/dev/null
		local out
		out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
			-D "$base/$item" \
			-c "lcd $dest/$item; prompt off; recurse on; mget *; exit" 2>&1)
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_[A-Z_]+' \
			|| [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "✗ $item" "0"
			echo "$out" | grep -E 'NT_STATUS' | head -3
			let fail_total++
		else
			echoRgb "✓ $item" "1"
		fi
	done < "$items_file"
	# 固定 3 項: tools/ (獨立連線)
	echoRgb "下載固定項目: tools/ start.sh restore_settings.conf" "3"
	mkdir -p "$dest/tools" 2>/dev/null
	local tools_out
	tools_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base/tools" \
		-c "lcd $dest/tools; prompt off; recurse on; mget *; exit" 2>&1)
	tools_out="$(smb_filter_noise "$tools_out")"
	# 固定 3 項: start.sh / restore_settings.conf (獨立連線)
	local fix_out
	fix_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base" \
		-c "lcd $dest; prompt off; get start.sh; get restore_settings.conf; exit" 2>&1)
	fix_out="$(smb_filter_noise "$fix_out")"
	# 驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "固定項目下載有錯誤" "0"
		echo "$tools_out
$fix_out" | grep -E 'NT_STATUS' | head -5
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}

# WebDAV 下載實作 (並行模式: 先遞迴掃出所有檔案 url, 再 curl -Z 並行下載)
_remote_download_webdav() {
	local chosen="$1" dest="$2" items_file="$3"
	local base_url="${remote_url%/}/$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local fail_total=0
	# 遞迴掃描 WebDAV 路徑, 把所有檔案 (含子目錄內) 寫入清單檔
	# 清單格式: <遠端編碼URL>\t<本地完整路徑>
	# $1=遠端 base url (已編碼), $2=本地目錄, $3=清單檔
	_webdav_scan_files() {
		local r_url="$1" l_dir="$2" out_list="$3"
		mkdir -p "$l_dir" 2>/dev/null
		local out
		out=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" "$r_url/" 2>/dev/null)
		# 用 mktemp 避免遞迴呼叫時不同層級共用同個檔案造成資料覆蓋
		local parsed
		parsed=$(mktemp "$TMPDIR/.wdav_scan_XXXXXX")
		echo "$out" | tr '><' '\n' | awk '
			{
				tag = $1
				sub(/^D:/, "", tag)
				sub(/^\/D:/, "/", tag)
				sub(/\/$/, "", tag)
			}
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					print (is_dir ? "D" : "F") "\t" href
				}
				in_resp=0
				next
			}
			tag == "href" { getline href; next }
			tag == "collection" { is_dir=1 }
		' > "$parsed"
		local r_url_basename_encoded r_url_basename
		r_url_basename_encoded="$(echo "$r_url" | sed 's|/$||; s|.*/||')"
		r_url_basename=$(url_decode_path "$r_url_basename_encoded")
		local rc=0
		while IFS=$'\t' read -r typ href; do
			[[ -z $href ]] && continue
			local encoded_name name
			encoded_name="$(echo "$href" | sed 's|/$||; s|.*/||')"
			name=$(url_decode_path "$encoded_name")
			[[ -z $name ]] && continue
			[[ $name = "$r_url_basename" ]] && continue
			if [[ $typ = D ]]; then
				_webdav_scan_files "$r_url/$encoded_name" "$l_dir/$name" "$out_list" || rc=1
			else
				# 寫入清單: URL\t本地路徑
				echo -e "$r_url/$encoded_name\t$l_dir/$name" >> "$out_list"
			fi
		done < "$parsed"
		rm -f "$parsed"
		return $rc
	}
	# 用 curl -Z (--parallel) 批次下載清單內的所有檔案
	# 每行 "url\tlocal_path", 並行度預設 4
	_webdav_parallel_get() {
		local list="$1"
		[[ ! -s $list ]] && return 0
		# 組裝 curl --config 格式: url + output 一對一
		local cfg="$TMPDIR/.curl_cfg_$$"
		: > "$cfg"
		while IFS=$'\t' read -r url lpath; do
			# curl config 格式: 每組 url + output
			# 路徑要用引號避開空白
			echo "url = \"$url\"" >> "$cfg"
			echo "output = \"$lpath\"" >> "$cfg"
		done < "$list"
		curl -sS -L --http1.1 --connect-timeout 10 --retry 2 -Z --parallel-max 4 \
			-u "$remote_user:$remote_pass" -K "$cfg" 2>/dev/null
		local rc=$?
		rm -f "$cfg"
		return $rc
	}
	# 1. 遞迴掃描所有要下載的檔案
	local all_files="$TMPDIR/.wdav_all_files"
	: > "$all_files"
	local idx=0
	local scan_fail=0
	# 1a. items_file 內每個項目
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		local encoded_item
		encoded_item=$(url_encode_path "$item")
		[[ -z $encoded_item ]] && encoded_item="$item"
		echoRgb "[$idx/$total_items] $(progress_bar $((idx * 100 / total_items))) 掃描 $item" "3"
		if ! _webdav_scan_files "$base_url/$encoded_item" "$dest/$item" "$all_files"; then
			echoRgb "✗ 掃描失敗: $item" "0"
			scan_fail=1
			let fail_total++
		fi
	done < "$items_file"
	# 1b. 固定項目 tools/
	echoRgb "掃描固定項目: tools/" "3"
	if ! _webdav_scan_files "$base_url/tools" "$dest/tools" "$all_files"; then
		echoRgb "✗ 掃描失敗: tools/" "0"
		scan_fail=1
		let fail_total++
	fi
	# 1c. 固定檔案 start.sh / restore_settings.conf 直接加進清單
	for f in start.sh restore_settings.conf; do
		echo -e "$base_url/$f\t$dest/$f" >> "$all_files"
	done
	# 2. 並行下載
	local total_files
	total_files=$(wc -l < "$all_files")
	echoRgb "並行下載 $total_files 個檔案 (4 路同時)" "3"
	_webdav_parallel_get "$all_files"
	rm -f "$all_files"
	# 3. 事後驗證每個項目本地是否有檔案
	local _vi=0
	while read -r item; do
		[[ -z $item ]] && continue
		let _vi++
		if [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "[$_vi/$total_items] $(progress_bar $((_vi * 100 / total_items))) ✗ $item (本地為空)" "0"
			let fail_total++
		else
			echoRgb "[$_vi/$total_items] $(progress_bar $((_vi * 100 / total_items))) ✓ $item" "1"
		fi
	done < "$items_file"
	# 固定項目驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "固定項目下載有錯誤" "0"
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}

# trap EXIT 觸發的遠端上傳函數
# 只在 backup/backup_media/backup_update_apk 成功完成後才觸發上傳
# 其他選項 (測試/列出/下載/退出) 不觸發, 由 REMOTE_TRIGGER 旗標控制
remote_cleanup() {
	# 只有在 backup / backup_media / backup_update_apk 跑完後才上傳
	# 其他功能 (測試連線、生成列表、檢查壓縮等) 不觸發上傳
	[[ $REMOTE_TRIGGER != 1 ]] && return 0
	# 防雙重觸發 (backup 內直接呼叫 + trap EXIT 都可能呼叫)
	[[ $REMOTE_DONE = 1 ]] && return 0
	REMOTE_DONE=1
	# 流式模式: 應用數據與 json 已在備份過程中逐個流式傳走, 此處只補傳結尾的 wifi (若有)
	if [[ $remote_stream = 1 && -n $remote_type ]]; then
		local _wifidir="$TMPDIR/.stream_stage/wifi"
		if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $_wifidir ]]; then
			local _wf
			for _wf in "$_wifidir"/*; do
				[[ -f $_wf ]] && _stream_upload "wifi/${_wf##*/}" < "$_wf"
			done
			echoRgb "wifi 設定已上傳遠端" "1"
		fi
		echoRgb "流式上傳完成 (數據未佔用本機空間)" "1"
		# 上傳恢復必要檔案到遠端 (tools/ start.sh restore_settings.conf), 讓遠端備份可獨立恢復 (功能8/10 需要)
		stream_upload_infra
		# 統計遠端備份資料夾大小 (對齊本地備份的 Calculate_size 顯示)
		local _subdir="$(get_backup_dirname)"
		local _rtotal _rnew
		_rtotal="$(remote_dir_size "$_subdir")"
		if [[ -n $_rtotal && $_rtotal != 0 ]]; then
			echoRgb "遠端備份資料夾↓↓↓\n -$remote_url ($_subdir)" "2"
			echoRgb "遠端備份總體大小$(size "$_rtotal") $_rtotal" "3"
			# 本次差異: 整體資料夾大小差異 (備份前快照 vs 現在, 對齊本地 Calculate_size)
			_rnew=$(awk -v a="${_rtotal:-0}" -v b="${_RTOTAL_BEFORE:-0}" 'BEGIN{print a-b}')
			case $_rnew in
			-*) echoRgb "本次備份減少 $(size "$(awk -v n="$_rnew" 'BEGIN{print -n}')")" "3" ;;
			0)  echoRgb "文件大小未改變" "3" ;;
			*)  echoRgb "本次備份增加 $(size "$_rnew")" "3" ;;
			esac
		fi
		# 方案A: 只清理 TMPDIR 暫存區 (絕不碰用戶既有的本地 $Backup 備份)
		rm -rf "$TMPDIR/.stream_stage" 2>/dev/null
		# 遠端json健全度檢查: 流式模式每個app上傳完就已即時上傳json, 此處對本次變更的app做收尾驗證
		if [[ -s $TMPDIR/.changed_apps ]]; then
			echoRgb "—————— 備份後 JSON 結構驗證 ——————" "3"
			local _ra _rfile _jchk_total _jchk_i=1 _jchk_sorted="$TMPDIR/.stream_json_check_apps"
			sort -u "$TMPDIR/.changed_apps" > "$_jchk_sorted"
			_jchk_total="$(grep -vc '^$' "$_jchk_sorted")"
			while read -r _ra; do
				[[ -z $_ra ]] && continue
				echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
				_rfile="$TMPDIR/.remote_health_check_$$.json"
				if remote_download_single_file "$_ra/app_details.json" "$_rfile" 2>/dev/null && [[ -s $_rfile ]]; then
					_json_health_check "$_rfile" "$_ra (遠端)"
				else
					echo "$_ra (遠端): app_details.json 不存在或無法下載" >> "$TMPDIR/.json_health_issues"
				fi
				rm -f "$_rfile" 2>/dev/null
				let _jchk_i++
			done < "$_jchk_sorted"
			rm -f "$_jchk_sorted"
			echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
			_json_health_report
		fi
		return 0
	fi
	if [[ $backup_has_changes = 0 ]]; then
		if [[ $remote_upload_per_app = 1 ]]; then
			echoRgb "逐應用上傳模式：無備份變更，只上傳依賴文件" "2"
		else
			echoRgb "無備份變更，只上傳依賴文件" "2"
		fi
		# 設置標記，跳過應用數據上傳
		REMOTE_SKIP_APPDATA=1
	elif [[ $remote_upload_per_app = 0 && -s "$TMPDIR/.changed_apps" ]]; then
		# 非逐應用上傳模式，但有變更的應用，只上傳變更的應用
		local changed_apps changed_count
		changed_apps="$(sort -u "$TMPDIR/.changed_apps" | tr '\n' ' ')"
		changed_count="$(sort -u "$TMPDIR/.changed_apps" | awk 'END{print NR}')"
		[[ -n $remote_type ]] && echoRgb "僅上傳變更的應用 (共 $changed_count 個): $changed_apps" "2"
		# 設置 REMOTE_APPLIST 為變更的應用列表
		REMOTE_APPLIST="$(sort -u "$TMPDIR/.changed_apps")"
	fi
	case $remote_type in
	webdav) upload_remote "webdav" ;;
	smb) upload_remote "smb" ;;
	*) return 0 ;;
	esac
	REMOTE_SKIP_APPDATA=0
	# 遠端json健全度檢查: 下載剛上傳的 app_details.json 逐一驗證 (確保傳輸/合併過程沒有損壞欄位)
	# 優先用 .changed_apps (本次實際變更上傳的app, 覆蓋面較廣); 無則 fallback REMOTE_APPLIST
	local _health_src
	if [[ -s $TMPDIR/.changed_apps ]]; then
		_health_src="$(sort -u "$TMPDIR/.changed_apps")"
	else
		_health_src="$REMOTE_APPLIST"
	fi
	if [[ -n $_health_src ]]; then
		local _ra _rfile _jchk_total _jchk_i=1
		_jchk_total="$(echo "$_health_src" | grep -vc '^$')"
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
			_rfile="$TMPDIR/.remote_health_check_$$.json"
			if remote_download_single_file "$_ra/app_details.json" "$_rfile" 2>/dev/null && [[ -s $_rfile ]]; then
				_json_health_check "$_rfile" "$_ra (遠端)"
			fi
			rm -f "$_rfile" 2>/dev/null
			let _jchk_i++
		done <<EOF4
$_health_src
EOF4
		echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
		_json_health_report
	fi
	unset REMOTE_APPLIST
}
# 秒 -> Nx天 Ny小時 Nz分鐘 Ns秒 (省略前導 0 單位)
hms() {
	awk -v t="$1" 'BEGIN{
		t=int(t); d=int(t/86400); h=int((t%86400)/3600); m=int((t%3600)/60); s=t%60
		o=""
		if(d>0) o=o d"天 "
		if(o!="" || h>0) o=o h"小時 "
		if(o!="" || m>0) o=o m"分鐘 "
		o=o s"秒"
		printf "%s", o
	}'
}

# 運作時間 + 深度睡眠 (uptime vs CLOCK_MONOTONIC 差 = 深睡時長)
Show_boottime() {
	local BOOT MONO
	BOOT=$(awk '{print $1; exit}' /proc/uptime)
	MONO=$(awk '/now at/{print $3; exit}' /proc/timer_list 2>/dev/null)
	if [[ -z $MONO ]]; then
		hms "$BOOT"
		return
	fi
	awk -v b="$BOOT" -v m="$MONO" 'BEGIN{
		mono=m/1e9; susp=b-mono; if(susp<0)susp=0
		printf "%.0f %.0f %.1f\n", b, susp, susp/b*100
	}' | while read -r rt sp pct; do
		printf "%s\n -深度睡眠:%s (%s%%)" "$(hms "$rt")" "$(hms "$sp")" "$pct"
	done
}
[[ -f /sys/block/sda/size ]] && ROM_TYPE="UFS" || ROM_TYPE="eMMC"
if [[ -f /proc/scsi/scsi ]]; then
	UFS_MODEL="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $2,$4}')"
else
	UFS_MODEL="$(cat "/sys/class/block/sda/device/inquiry" 2>/dev/null)"
	[[ $UFS_MODEL = "" ]] && UFS_MODEL="unknown"
fi
_model="$(getprop ro.product.model 2>/dev/null)"
Device_name="$(grep -Ew "$_model" "$tools_path/Device_List" 2>/dev/null | awk -F'"' '{print $4}' | head -1)"
[[ $Device_name = "" ]] && Device_name="$_model"
Manager_version="$(su -v 2>/dev/null)"
if [[ $Manager_version != "" ]]; then
	[[ $Manager_version = *KernelSU* ]] && ksu="ksu"
	[[ $ksu = "" && -d /data/adb/ksu ]] && ksu="ksu"
else
	if [[ -d /data/adb/ksu ]]; then
		Manager_version=KernelSU
		ksu="ksu"
	fi
fi
Socname="$(getprop ro.soc.model)"
if [[ $Socname != "" && -f $tools_path/soc.json ]]; then
	DEVICE_NAME="$(jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' "$tools_path/soc.json" 2>/dev/null)"
	RAMINFO="$(jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' "$tools_path/soc.json" 2>/dev/null)"
	[[ $DEVICE_NAME = null || $DEVICE_NAME = "" ]] && DEVICE_NAME="處理器:null"
	[[ $RAMINFO = null || $RAMINFO = "" ]] && RAMINFO="RAM:null"
else
	DEVICE_NAME="處理器:null"
	RAMINFO="RAM:null"
fi
_brand="$(getprop ro.product.brand 2>/dev/null)"
_device="$(getprop ro.product.device 2>/dev/null)"
_busybox_path="$(which busybox)"
_busybox_ver="$(busybox | head -1 | cut -d' ' -f2)"
echoRgb "---------------------SpeedBackup---------------------"
echoRgb "腳本路徑:$MODDIR\n -已開機:$(Show_boottime)\n -執行時間:$(date +"%Y-%m-%d %H:%M:%S")\n -busybox路徑:$_busybox_path\n -busybox版本:$_busybox_ver\n -腳本版本:$backup_version\n -dex版本:$(get_dex_version_line)\n -管理器:$Manager_version\n -品牌:$_brand\n -型號:$Device_name($_device)\n -閃存顆粒:$UFS_MODEL($ROM_TYPE)\n -$DEVICE_NAME\n -$RAMINFO\n -Android版本:$release SDK:$sdk\n -內核:$(uname -r)\n -Selinux狀態:$([[ $(getenforce) = Permissive ]] && echo "寬容" || echo "嚴格")\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
case $MODDIR in
*Backup_*)
	if [[ -f $MODDIR/app_details.json ]]; then
		if [[ -d ${MODDIR%/*/*}/tools ]]; then
			path_hierarchy="${MODDIR%/*/*}"
		else
			path_hierarchy="${MODDIR%/*}"
		fi
	else
		if [[ -d ${MODDIR%/*}/tools ]]; then
			path_hierarchy="${MODDIR%/*}"
		else
			[[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR"
		fi
	fi ;;
*) [[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR" ;;
esac
[[ $SCRIPT_LANG = "" ]] && echoRgb "系統無參數語言獲取失敗\n -如果需要更改腳本語言請於$conf_path\n -Shell_LANG=填入對應數字" "0"
case $SCRIPT_LANG in
*TW* | *tw* | *HK*)
	Script_target_language="zh-TW" ;;
*CN* | *cn*)
	Script_target_language="zh-CN" ;;
esac
echoRgb "$Script_target_language腳本"
# 互動式輸入選項 (音量鍵或數字鍵)
# 配合 keycheck 抓音量鍵, 沒音量鍵則退回鍵盤輸入
Enter_options() {
	echoRgb "$1" "2"
	unset option parameter
	while true ;do
		if [[ $option != "" ]]; then
			case $option in
			0|1)
				parameter="$option"
				[[ $option = 1 ]] && echoRgb "$2" "2" || echoRgb "$3" "2"
				break ;;
			*)
				echoRgb "$option參數錯誤 只能是0或1" "0"
				read option ;;
			esac
		else
			read option
		fi
	done
}
# 二選一互動 helper (統一音量鍵)
# 用法 A (return 模式): ask_yn "提示" "選項1" "選項2"
#   選項1 → return 0, 選項2 → return 1
#   例: ask_yn "確認?" "確認" "取消" && do_it
#
# 用法 B (變數模式): ask_yn "提示" "選項1" "選項2" 變數名
#   結果寫入指定變數 (true/false)，同時設 $branch
#   例: ask_yn "備份模式?" "完整" "僅APK" Backup_Mode
ask_yn() {
	local _msg="$1" _opt1="$2" _opt2="$3" _var="$4"
	echoRgb "$_msg\n -音量上=$_opt1, 音量下=$_opt2" "2"
	get_version "$_opt1" "$_opt2"
	# 變數模式: 把結果寫入指定變數
	if [[ -n $_var ]]; then
		eval "$_var=\"\$branch\""
	fi
	[[ $branch = true ]]
}
# 獨立二選一 helper, 不依賴全域 Lo (給 user/update/low_battery_mode/外部儲存等
# 各自有專屬 conf 開關的情境用): 變數已有值就跳過詢問, 沒有就一律走音量鍵詢問
# 用法: ask_yn_indep "提示" "選項1" "選項2" 變數名
ask_yn_indep() {
	local _msg="$1" _opt1="$2" _opt2="$3" _var="$4" _cur
	if [[ -n $_var ]]; then
		eval "_cur=\"\$$_var\""
		if [[ -n $_cur ]]; then
			isBoolean "$_cur" "$_var" && eval "$_var=\"\$nsx\""
			[[ $nsx = true ]]; return
		fi
	fi
	echoRgb "$_msg\n -音量上=$_opt1, 音量下=$_opt2" "2"
	get_version "$_opt1" "$_opt2"
	[[ -n $_var ]] && eval "$_var=\"\$branch\""
	[[ $branch = true ]]
}
if [[ ! -f ${0%/*}/app_details.json ]]; then
	if [[ $user = "" ]]; then
		user_id="$(ls /data/user | tr ' ' '\n')"
		if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
			echo "$user_id" | while read -r; do
				[[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
			done
			echoRgb "設備存在多用戶,選擇操作目標用戶"
			if [[ $(awk 'END{print NR}' <<< "$user_id") = 2 ]]; then
				user1="$(echo "$user_id" | sed -n '1p')"
				user2="$(echo "$user_id" | sed -n '2p')"
				echoRgb "音量上選擇用戶:$user1，音量下選擇用戶:$user2" "2"
				Select_user="true"
				get_version "$user1" "$user2" && user="$branch"
				unset Select_user
			else
				while true ;do
					if [[ $option != "" ]]; then
						user="$option"
						break
					else
						echoRgb "請輸入需要操作目標分區" "1"
						read option
					fi
				done
			fi
		else
			user="0"
		fi
	else
		user_id="$(ls /data/user | tr ' ' '\n')"
		if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
			echo "$user_id" | while read -r; do
				[[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
			done
		else
			echoRgb "主用戶:$user_id" "2"
		fi
	fi
else
	case $(echo "${0%}") in
	*Backup_zstd_*) user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')" ;;
	*Backup_tar_*) user="$(echo "${0%}" | sed 's/.*\/Backup_tar_\([0-9]*\).*/\1/')" ;;
	*) echoRgb "請勿修改備份資料夾名稱，保持原本的Backup_壓縮算法名稱_使用者id" "0" && exit 2 ;;
	esac
fi
[[ $user != 0 ]] && am start-user "$user"
path="/data/media/$user/Android"
path2="/data/user/$user"
path3="/data/user_de/$user"
[[ ! -d $path2 ]] && echoRgb "$user分區不存在，請將上方提示的用戶id按照需求填入\n -$conf_path配置項user=,一次只能填寫一個" "0" && exit 2
echoRgb "當前操作為用戶$user"
export USER_ID="$user"
unset LD_LIBRARY_PATH
#因接收USER_ID環境變量問題故將函數放在此處
# dex 調用 wrapper: _dex_debug=1 時記錄每次調用到 .dex_call_log (用於確認批量/預掃是否生效)
# 平時 _dex_debug 為空, 零額外開銷; 要監控時在腳本開頭設 _dex_debug=1
_dex() {
	[[ $_dex_debug = 1 ]] && {
		local _c
		for _c in "$@"; do case $_c in
			grant*|revoke*|setOps*|getRuntime*|getInstalled*|getPackage*|setDisplay*|getNotification*|setNotification*|getBattery*|setBattery*|get|set) echo "$_c" >> "$TMPDIR/.dex_call_log"; break ;;
		esac; done
	}
	command app_process "$@"
}

# 設定 dex 取應用名稱用的 locale (export 給 HiddenApiUtil 的 applyLocale 讀)
# 優先序: Shell_LANG 明確指定 > dex getLocale 取系統實際語言 > 退出提示手動設定
case $Shell_LANG in
1) export APP_LABEL_LOCALE="zh-CN" ;;
0) export APP_LABEL_LOCALE="zh-TW" ;;
*)
	# 用 settings 取用戶實際設定的語言 (system_locales, 如 zh-Hant-TW / zh-Hans-CN), 命令列可靠取得
	_syslocale="$(settings get system system_locales 2>/dev/null | head -1)"
	[[ -z $_syslocale || $_syslocale = null ]] && _syslocale="$(getprop persist.sys.locale)"
	case $_syslocale in
	zh-Hant*|zh_Hant*|zh-TW*|zh_TW*|zh-HK*|zh_HK*|zh-MO*) export APP_LABEL_LOCALE="zh-TW" ;;
	zh-Hans*|zh_Hans*|zh-CN*|zh_CN*|zh-SG*|zh*)            export APP_LABEL_LOCALE="zh-CN" ;;
	*)
		echoRgb "系統語言取得失敗或非中文 (取得: ${_syslocale:-空})" "0"
		echoRgb "dex 將取得英文應用名稱, 可能導致名稱比對/恢復異常" "0"
		echoRgb "請於 backup_settings.conf 設定 Shell_LANG=0 (繁中) 或 1 (簡中)" "3"
		exit 1 ;;
	esac
	;;
esac
alias appinfo="_dex /system/bin com.xayah.dex.HiddenApiUtil getInstalledPackagesAsUser $USER_ID $@"
alias appinfo2="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageLabel $USER_ID $@"
alias appinfo3="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageArchiveInfo $@"
alias get_ssaid="_dex /system/bin com.xayah.dex.SsaidUtil get $USER_ID $@"
alias set_ssaid="_dex /system/bin com.xayah.dex.SsaidUtil set $USER_ID $@"
alias get_uid="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageUid $USER_ID $@"
alias get_Permissions="_dex /system/bin com.xayah.dex.HiddenApiUtil getRuntimePermissions $USER_ID $@"
alias Set_true_Permissions="_dex /system/bin com.xayah.dex.HiddenApiUtil grantRuntimePermission $USER_ID $@"
alias Set_false_Permissions="_dex /system/bin com.xayah.dex.HiddenApiUtil revokeRuntimePermission $USER_ID $@"
alias Set_Ops="_dex /system/bin com.xayah.dex.HiddenApiUtil setOpsMode $USER_ID $@"
alias get_Notifications="_dex /system/bin com.xayah.dex.HiddenApiUtil getNotificationSettings $USER_ID $@"
alias Set_Notifications="_dex /system/bin com.xayah.dex.HiddenApiUtil setNotificationSettings $USER_ID $@"
alias get_Battery_Settings="_dex /system/bin com.xayah.dex.HiddenApiUtil getBatterySettings $USER_ID $@"
alias Set_Battery_Settings="_dex /system/bin com.xayah.dex.HiddenApiUtil setBatterySettings $USER_ID $@"
alias setDisplay="_dex /system/bin com.xayah.dex.HiddenApiUtil setDisplayPowerMode $@"
find_tools_path="$(find "$path_hierarchy"/* -maxdepth 1 -name "tools" -type d ! -path "$path_hierarchy/tools" | grep -v "/Backup_[^/]*/tools$")"
# 備份 WiFi 密碼到指定目錄, 用 classes.dex 讀 system 內的 WifiConfigStore
backup_wifi() {
	local wifi_dir="$1"
	[[ -z $wifi_dir ]] && echoRgb "backup_wifi: 目錄參數為空" "0" && return 1
	[[ ! -d $wifi_dir ]] && mkdir -p "$wifi_dir"
	if [[ -d $wifi_dir ]]; then
		echoRgb "備份wifi密碼"
		rm -rf "${wifi_dir:?}"/*
		app_process /system/bin com.xayah.dex.NetworkUtil saveNetworks>"$wifi_dir/wifi.json"
		echo_log "wifi備份"
	fi
}
# 從備份恢復 WiFi 密碼 (寫回 WifiConfigStore)
recover_wifi() {
	if [[ -d $1 ]]; then
		if [[ -f $1/wifi.json ]]; then
			echoRgb "恢復wifi密碼"
			app_process /system/bin com.xayah.dex.NetworkUtil restoreNetworks "$1/wifi.json"
			echo_log "wifi恢復"
		else
			echoRgb "wifi.json遺失"
		fi
	else
		echoRgb "$1不存在 wifi無法恢復" "0"
	fi
}
Rename_script () {
	HT="${HT:=0}"
	find "$path_hierarchy" -maxdepth 3 -name "*.sh" -type f -not -name "tools.sh" | sort | while read -r; do
		MODDIR_NAME="${REPLY%/*}"
		FILE_NAME="${REPLY##*/}"
		if [[ -f ${REPLY%/*}/app_details.json || -f ${REPLY%/*}/app_details ]]; then
			if [[ $FILE_NAME = backup.sh ]]; then
				touch_shell "1" "$REPLY"
			elif [[ $FILE_NAME = recover.sh ]]; then
				touch_shell "3" "$REPLY"
			elif [[ $FILE_NAME = upload.sh ]]; then
				touch_shell "5" "$REPLY"
			fi
		else
			if [[ -d ${REPLY%/*}/tools ]]; then
				if [[ $FILE_NAME = start.sh ]]; then
					[[ -f ${REPLY%/*}/backup_settings.conf ]] && touch_shell "0" "$REPLY"
					[[ -f ${REPLY%/*}/restore_settings.conf ]] && touch_shell "2" "$REPLY"
				fi
			fi
			let HT++
		fi
	done
	unset HT
}
# 在指定路徑生成入口腳本 (start.sh / backup.sh / recover.sh / upload.sh)
# $1=模式 (0/1/2/3/5), $2=目標檔案路徑
# 模式對應的 MODDIR 路徑推算規則不同 (依腳本放置位置)
touch_shell() {
	unset conf_path MODDIR_Path
	case $1 in
	0)
		MODDIR_Path='${0%/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*}/backup_settings.conf' ;;
	1)
		MODDIR_Path='${0%/*/*/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*/*/*}/backup_settings.conf' ;;
	2)
		MODDIR_Path='${0%/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*}/restore_settings.conf' ;;
	3)
		MODDIR_Path='${0%/*/*}'
		MODDIR_Path1='${0%/*}'
		conf_path='${0%/*/*}/restore_settings.conf' ;;
	5)
		# upload.sh: 放在 Backup_zstd_X/<app>/, MODDIR 是 Backup_zstd_X 自己
		MODDIR_Path='${0%/*/*/*}'
		MODDIR_Path1='${0%/*/*}'
		conf_path='${0%/*/*/*}/backup_settings.conf' ;;
	esac
	echo "#!/system/bin/sh
if [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then
	MODDIR=\"$MODDIR_Path1\"
	conf_path=\"$conf_path\"
	[ ! -f \"$conf_path\" ] && . \"$MODDIR_Path/tools/tools.sh\"
else
	echo \"$MODDIR_Path/tools/tools.sh遺失\"
fi
mkdir -p \"\${0%/*}/log\" 2>/dev/null
logfile=\"\${0%/*}/log/log_\$(date +%Y-%m-%d_%H-%M).txt\"
. \"$MODDIR_Path/tools/tools.sh\" | tee \"\$logfile\"
sed -i \"\$(printf 's/\033\[[0-9;]*m//g')\" \"\$logfile\"" > "$2"
}
# 用 ts 翻譯檔案 (取代散落各處的 ts<X>temp && cp temp X && rm temp 模式)
# 用法: ts_inplace <檔案>
ts_inplace() {
	local f="$1" tmp="$TMPDIR/.ts_$$"
	if ts < "$f" > "$tmp"; then
		cp "$tmp" "$f"
		rm -f "$tmp"
	else
		rm -f "$tmp"
		return 1
	fi
}

# 從 zip 檔自動更新腳本 (檢測 $MODDIR 內的 .zip 並提取 tools.sh)
# 用法: update_script [zip路徑]  — 有傳入時直接用，否則掃 $MODDIR
update_script() {
	[[ -n $1 ]] && zipFile="$1"
	[[ -z $zipFile ]] && zipFile="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null)"
	if [[ -n $zipFile ]]; then
		# 多個 zip 用 case 判斷, 取代 echo|wc -l
		case $zipFile in
		*$'\n'*)
			echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zipFile" "0"
			exit 1 ;;
		esac
		if unzip -l "$zipFile" 2>/dev/null | grep -q "backup_settings\.conf$"; then
			# 在應用備份目錄內執行: 不解壓、不更新，僅給出導引提示
			case $MODDIR in
			*Backup_*)
				if [[ -f $MODDIR/app_details.json ]]; then
					local _hint_path="${path_hierarchy:-${MODDIR%/*}}"
					echoRgb "偵測到更新包: ${zipFile##*/}" "2"
					echoRgb "⚠ 目前在應用備份目錄內，無法在此執行更新" "0"
					echoRgb "請到以下目錄執行 start.sh 後即可自動更新:\n -$_hint_path" "3"
					return 0
				fi ;;
			esac
			unzip -o "$zipFile" -j "tools/tools.sh" -d "$MODDIR" &>/dev/null
			if [[ -f $MODDIR/tools.sh ]]; then
				# 版本比對: 12 碼純數字時間戳 (e.g. 202605161200), awk 一次抓取
				local _new_ver _cur_ver
				_new_ver=$(awk -F= '/^backup_version=/ {gsub(/[a-zA-Z"]/, "", $2); print $2; exit}' "$MODDIR/tools.sh")
				_cur_ver=$(echo "$backup_version" | tr -d 'a-zA-Z')
				if [[ ${_new_ver:-0} -ge ${_cur_ver:-0} ]]; then
					shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$MODDIR/tools.sh")"
					echoRgb "從$zipFile更新"
					if [[ -d $path_hierarchy/tools ]]; then
						mv "$path_hierarchy/tools" "$TMPDIR"
						[[ -d $TMPDIR/tools ]] && {
						unzip -o "$zipFile" tools/* -d "$path_hierarchy" | sed 's/inflating/釋放/g ; s/creating/創建/g ; s/Archive/解壓縮/g'
						chmod -R 0777 "$path_hierarchy/tools" 2>/dev/null
						echo_log "解壓縮${zipFile##*/}"
						if [[ $result = 0 ]]; then
							if [[ $shell_language != $Script_target_language ]]; then
								echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
								ts_inplace "$path_hierarchy/tools/Device_List"
								echo_log "$path_hierarchy/tools/Device_List翻譯"
								ts_inplace "$path_hierarchy/tools/tools.sh" && sed -i "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$path_hierarchy/tools/tools.sh"
								echo_log "$path_hierarchy/tools/tools.sh翻譯"
								HT=1
							fi
							update_backup_settings_conf>"$path_hierarchy/backup_settings.conf"
							ts_inplace "$path_hierarchy/backup_settings.conf"
							echo_log "$path_hierarchy/backup_settings.conf翻譯"
							echo "$find_tools_path" | while read -r; do
								if [[ $REPLY != $path_hierarchy/tools ]]; then
									# 安全守衛: REPLY 必須是絕對路徑且深度≥2層才操作, 防異常路徑誤刪
									local _reply_parent="${REPLY%/*}"
									[[ -z $_reply_parent || $_reply_parent = "/" || ${#_reply_parent} -lt 4 ]] && continue
									[[ $REPLY != /* ]] && continue
									rm -rf "$REPLY" 2>/dev/null
									cp -r "$path_hierarchy/tools" "$_reply_parent"
									update_Restore_settings_conf>"$_reply_parent/restore_settings.conf"
									ts_inplace "${REPLY%/*}/restore_settings.conf"
									echo_log "${REPLY%/*}/restore_settings.conf翻譯"
								fi
							done
							Rename_script
							if [[ -n $Output_path ]]; then
								[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
								if [[ ${Output_path:0:1} != / ]]; then
									update_path="$MODDIR/$Output_path/$(get_backup_dirname)"
								else
									update_path="$Output_path/$(get_backup_dirname)"
								fi
								# FUSE 層 rm -rf 可能因權限問題失敗; 改 cp -rf 直接覆蓋無需先刪
								mkdir -p "$update_path/tools" 2>/dev/null
								cp -rf "$path_hierarchy/tools/." "$update_path/tools/" 2>/dev/null || cp -r "$path_hierarchy/tools" "$update_path"
								chmod -R 0777 "$update_path/tools" 2>/dev/null
								echoRgb "$update_path/tools已經更新完成"
							fi
						else
							mv "$TMPDIR/tools" "$MODDIR"
						fi
						# TMPDIR 清理加保護，避免變數為空時誤刪
						[[ -n $TMPDIR ]] && rm -rf "$TMPDIR/tools" "$zipFile" "$MODDIR/tools.sh"
						echoRgb "更新完成 請重新執行腳本" "2"
						exit
						} || echoRgb "tools移動到TMPDIR失敗" "0"
					fi
				else
					echoRgb "${zipFile##*/}版本低於當前版本,自動刪除" "0"
					rm -rf "$zipFile" "$path_hierarchy/tools.sh"
				fi
			else
				rm -rf "$zipFile"
				unset zipFile
			fi
		fi
	fi
	unset NAME
}
update_script
# 掃 Download 和 QQ 收件匣，找到有效 zip 直接傳入 update_script
# 兩個來源都嘗試 (Download 有無關 zip 時不該擋住 QQ 的更新包)
_dl_zip="$(ls -t /storage/emulated/0/Download/*.zip 2>/dev/null | head -1)"
_qq_zip="$(ls -t /storage/emulated/0/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv/*.zip 2>/dev/null | head -1)"
for _try_zip in "$_dl_zip" "$_qq_zip"; do
	[[ -z $_try_zip ]] && continue
	# 只有「含 backup_settings.conf 的更新包」才傳入; 普通 zip 略過不處理
	if unzip -l "$_try_zip" 2>/dev/null | grep -q "backup_settings\.conf$"; then
		echoRgb "偵測到更新包: ${_try_zip##*/}" "2"
		update_script "$_try_zip"
	fi
done
unset _dl_zip _qq_zip _try_zip
if [[ $sdk -lt 30 ]]; then
	alias INSTALL="pm install --user $user -r -t >/dev/null"
	alias create="pm install-create --user $user -tl"
else
	if [[ $sdk -gt 33 ]]; then
		alias INSTALL="pm install -r --bypass-low-target-sdk-block -i com.android.vending --user $user -t >/dev/null"
		alias create="pm install-create -i com.android.vending --bypass-low-target-sdk-block --user $user -t"
	else
		alias INSTALL="pm install -r -i com.android.vending --user $user -t >/dev/null"
		alias create="pm install-create -i com.android.vending --user $user -t"
	fi
fi
#settings get system system_locales
Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
if [[ $path_hierarchy != "" && $Script_target_language != ""  ]]; then
	K=1
	J="$(find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | wc -l)"
	find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | while read -r; do
		unset shell_language
		shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY")"
		case $shell_language in
		zh-CN|zh-TW)
			if [[ $Script_target_language != $shell_language ]]; then
				[[ $K = 1 ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
				ts_inplace "$REPLY"
				if [[ $? = 0 ]]; then
					touch "$TMPDIR/0"
					echo_log "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")翻譯"
					MODDIR="${0%/*}"
					if [[ -f ${REPLY%/*/*}/backup_settings.conf ]]; then
						update_backup_settings_conf>"${REPLY%/*/*}/backup_settings.conf"
						ts_inplace "${REPLY%/*/*}/backup_settings.conf"
						echo_log "${REPLY%/*/*}/backup_settings.conf翻譯"
					fi
					if [[ -f ${REPLY%/*/*}/restore_settings.conf ]]; then
						update_Restore_settings_conf>"${REPLY%/*/*}/restore_settings.conf"
						ts_inplace "${REPLY%/*/*}/restore_settings.conf"
						echo_log "${REPLY%/*/*}/restore_settings.conf翻譯"
					fi
					sed "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$REPLY" > temp && cp temp "$REPLY" && rm temp
					[[ $shell_language != $(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY") ]] && echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改成功" || echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改失敗" "0"
					ts_inplace "${REPLY%/*}/Device_List"
					echo_log "${REPLY%/*}/Device_List翻譯"
					[[ $K = 1 ]] && Rename_script
				else
					echoRgb "$REPLY ts進程出現錯誤" "0"
				fi
				let K++
			fi ;;
		esac
	done
	[[ -e $TMPDIR/0 ]] && rm "$TMPDIR/0" && echoRgb "轉換腳本完成，退出腳本重新執行即可使用" && exit 2
fi
#校驗選填是否正確
ask_yn_indep "自動更新腳本?" "更新" "不更新" update
if [[ $update = true ]]; then
	json="$(down "$Language")"
else
	echoRgb "自動更新被關閉" "0"
fi
if [[ $json != "" ]]; then
	tag="$(jq -r '.tag_name'<<< "$json" 2>/dev/null)"
	if [[ $tag != "" && $backup_version != $tag ]]; then
		if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$tag" | tr -d "a-zA-Z")") -eq 0 ]]; then
			download="$(jq -r '.assets[].browser_download_url'<<< "$json")"
			case $cdn in
			0) zip_url="$download" ;;
			1) zip_url="https://ghfast.top/$download" ;;
			2) zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download" ;;
			*) echoRgb "$conf_path cdn=設置錯誤 範圍只能是0-2" && exit 2 ;;
			esac
			if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$download" | tr -d "a-zA-Z")") -eq 0 ]]; then
				echoRgb "發現新版本:$tag"
				# 在應用備份目錄內: 僅提示去正確目錄，不執行下載
				_skip_update_dl=0
				case $MODDIR in
				*Backup_*)
				    echo "$MODDIR"
				    exit
					if [[ -f $MODDIR/app_details.json ]]; then
						echoRgb "⚠ 目前在應用備份目錄內，無法在此下載更新" "0"
						echoRgb "請到以下目錄執行 start.sh 後即可自動更新:\n -${path_hierarchy:-${MODDIR%/*}}" "3"
						_skip_update_dl=1
					fi ;;
				esac
				if [[ $_skip_update_dl = 0 && $update = true ]]; then
					echoRgb "$(ts "更新日誌:\n$(down "$Language" | jq -r '.body')")"
					if ask_yn "是否更新腳本?" "更新" "不更新" choose; then
						echoRgb "下載中.....耐心等待 如果下載失敗請掛飛機"
						starttime1="$(date -u "+%s")"
						_dl_dest="${path_hierarchy:-$MODDIR}"
						down "$zip_url" >"$_dl_dest/update.zip" &
						wait
						endtime 1
						[[ ! -f $_dl_dest/update.zip ]] && echoRgb "下載失敗" && exit 2
						zipFile="$_dl_dest/update.zip"
						unset _dl_dest
					fi
				elif [[ $_skip_update_dl = 0 ]]; then
					echoRgb "$conf_path內update選項為0忽略更新僅提示更新" "0"
				fi
				unset _skip_update_dl
			fi
		fi
	fi
else
	[[ $update = true ]] && echoRgb "更新獲取失敗" "0"
fi
update_script
# 給定路徑, 穿透 bind/FUSE 找出真實底層的「可餵給 df 的路徑」
# 用於 Android emulated storage (sdcardfs/FUSE) 上 bind 了其他分區的情況
# 例: /storage/emulated/0/虛擬分區 實際是 /mnt/YAWAsau/備份 的 bind, 應回傳 /mnt/YAWAsau
# 策略:
#   1) 先把已知的 sdcardfs/FUSE 視圖路徑顯式轉成內核真實路徑 /data/media/<N>/<X>
#      (不能用 realpath, /storage/emulated 通常是 symlink 到 /mnt/installer/.../emulated,
#       resolve 後反而會撞到 FUSE 掛載點, 拿不到底下的 bind)
#   2) 在 /proc/self/mountinfo 找 mp 是 target 祖先的最長匹配 → 取得 source
#   3) 找同 source 且 root="/" 的 canonical mountpoint, 回傳該路徑
#      (Android toybox df 不接受 block device, 必須回傳真實「路徑」)
#   4) 找不到 canonical 時, 若 source 是現存目錄就用 source, 否則原樣回傳
_resolve_real_mount() {
	local p="$1" rp target rest out
	[[ -z $p ]] && { echo "$p"; return; }
	# 先 readlink -f 一次, 解開常見入口 symlink (/sdcard, /storage/self/primary, /mnt/sdcard 等)
	# 注意: 之前嘗試過 realpath 會把 /storage/emulated/0 解成 /mnt/installer/.../emulated/0,
	# 撞到 FUSE 掛載點; 現在下方 case 已涵蓋 /mnt/installer/... 等視圖, 所以 readlink 後也能正確處理
	rp="$(readlink -f "$p" 2>/dev/null)"
	[[ -n $rp ]] && p="$rp"
	# 把已知 sdcardfs/FUSE 視圖路徑剝皮成 /data/media/<N>/<X>
	case "$p" in
		/storage/emulated/*)            rest="${p#/storage/emulated/}"; target="/data/media/$rest" ;;
		/mnt/installer/*/emulated/*)    rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/runtime/*/emulated/*)      rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/pass_through/*/emulated/*) rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/user/*/emulated/*)         rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		*)                              target="$p" ;;
	esac
	out="$(awk -v target="$target" '
	function unesc(s) { gsub(/\\040/, " ", s); return s }
	{
		root=unesc($4); mp=unesc($5)
		i=6; while (i<=NF && $i!="-") i++
		src=unesc($(i+2))
		n++; mp_a[n]=mp; root_a[n]=root; src_a[n]=src
	}
	END {
		best_len=-1
		for (i=1; i<=n; i++) {
			m=mp_a[i]
			if (m==target || index(target, m"/")==1) {
				if (length(m) > best_len) { best_len=length(m); R_src=src_a[i] }
			}
		}
		if (best_len<0) exit
		# 找同 source 且 root="/" 的 canonical mountpoint
		for (i=1; i<=n; i++) {
			if (src_a[i]==R_src && root_a[i]=="/") { print mp_a[i]; exit }
		}
		# 沒 canonical 且 source 是路徑而非 /dev/*, 就用 source
		if (substr(R_src,1,1)=="/" && R_src !~ /^\/dev\//) print R_src
	}' /proc/self/mountinfo 2>/dev/null)"
	if [[ -n $out && ( -d $out || -b $out ) ]]; then
		echo "$out"
	else
		echo "$p"
	fi
}
# 計算本地備份目錄路徑
# 格式: $Output_path/Backup_${Compression_method}_${user}
# 並建立目錄, 設定 $Backup 全域變數供其他函數使用
# 返回帶後綴的備份目錄名 (Backup_${Compression_method}_${user}${suffix})
# 解析 Backup_suffix 中的日期時間變量: %yyyymmdd %hhmmss %yyyymmddhhmmss %yyyy %mm %dd
get_backup_dirname() {
	local base="Backup_${Compression_method}_${user:-0}"
	if [[ -n $Backup_suffix ]]; then
		local resolved="$Backup_suffix"
		local now="$(date '+%Y%m%d%H%M%S')"
		resolved="${resolved//%yyyymmddhhmmss/$now}"
		resolved="${resolved//%yyyymmdd/${now:0:8}}"
		resolved="${resolved//%hhmmss/${now:8}}"
		resolved="${resolved//%yyyy/${now:0:4}}"
		resolved="${resolved//%mm/${now:4:2}}"
		resolved="${resolved//%dd/${now:6:2}}"
		echo "${base}${resolved}"
	else
		echo "$base"
	fi
}

# ======================================================
# 備份路徑 / 預掃 / app_details 讀取
# ======================================================
backup_path() {
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		if [[ ${Output_path:0:1} != / ]]; then
			Directory_type="相對路徑"
			Backup="$MODDIR/$Output_path/$(get_backup_dirname)"
		else
			Directory_type="絕對路徑"
			Backup="$Output_path/$(get_backup_dirname)"
		fi
		outshow="使用自定義目錄($Directory_type)"
	else
		Backup="$MODDIR/$(get_backup_dirname)"
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
			Backup="$MODDIR/$(get_backup_dirname)"
		else
			ask_yn_indep "檢測到隨身碟 是否在隨身碟備份?" "選擇了隨身碟備份" "選擇了本地備份"
			[[ $branch = true ]] && hx="$branch"
			[[ $hx = true ]] && Backup="$OTGPATH/$(get_backup_dirname)"
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
	_real_parent="$(_resolve_real_mount "${Backup%/*}")"
	_real_suffix=""
	[[ -n $_real_parent && $_real_parent != "${Backup%/*}" ]] && _real_suffix=" -└─ 掛載於: $_real_parent${Backup##${Backup%/*}}"
	remote_setup
	# 一致性保護: remote_stream=1 但 remote_type 無效/空 (驗證失敗被清空) → 關閉流式, 避免半啟用混亂
	if [[ $remote_stream = 1 && -z $remote_type ]]; then
		echoRgb "remote_stream=1 但遠端未啟用(remote_type 空/驗證失敗), 已停用流式, 改為純本機備份" "0"
		remote_stream=0
	fi
	# 分區統計移到 remote_setup/一致性保護之後:
	# 連線失敗自動轉純本機備份時, 也能正確顯示本地資訊; 流式 (數據不落地) 才不顯示
	if [[ $remote_stream != 1 ]]; then
		echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "$_real_parent" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$_real_parent" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup\n$_real_suffix"
		echoRgb "$outshow" "2"
	fi
	# 快照備份前遠端大小 (結尾算差異, 對齊本地備份的整體資料夾差異統計)
	if [[ -n $remote_type ]]; then
		_RTOTAL_BEFORE="$(remote_dir_size "$(get_backup_dirname)" 2>/dev/null)"
		[[ -z $_RTOTAL_BEFORE ]] && _RTOTAL_BEFORE=0
	fi
}

# 預掃 pkg → uid map (給備份主迴圈用, 避免每個 app 都 fork 一次 pm + awk)
# 寫到 $TMPDIR/.pkg_uid 格式: pkg<TAB>uid
# 用法: prepare_pkg_uid_map (backup / backup_update_apk 開頭呼叫)
prepare_pkg_uid_map() {
	pm list packages -U --user "${user:-0}" 2>/dev/null \
		| awk -F'[ :]' '{print $2"\t"$4}' > "$TMPDIR/.pkg_uid"
}

# 預掃 pkg → installer (安裝來源) map
# 寫到 $TMPDIR/.pkg_installer 格式: pkg<TAB>installer
# pm list packages -i 輸出: package:<pkg>  installer=<installer>
prepare_pkg_installer_map() {
	pm list packages -i --user "${user:-0}" 2>/dev/null \
		| sed -e 's/^package://' -e 's/  installer=/\t/' \
		| awk -F'\t' '$2 != "" && $2 != "null" {print $1"\t"$2}' > "$TMPDIR/.pkg_installer"
}

# 預掃各 app 的電池/背景設定（dex v12: RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND / deviceidle whitelist）
# 寫到 $TMPDIR/.pkg_battery, 格式: pkg<TAB>json
# dex 輸出每行: packageName BATTERY:xxx value...
prepare_battery_settings_map() {
	local _battery_tmp="$TMPDIR/.pkg_battery"
	: > "$_battery_tmp"
	local _all_pkgs
	if [[ -n $1 ]]; then
		_all_pkgs="$1"
	else
		_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	fi
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃電池/背景設定中..." "2"
	get_Battery_Settings $_all_pkgs 2>/dev/null | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; key=$2
			val=$3; for(i=4;i<=NF;i++) val=val" "$i
			gsub(/\\/, "\\\\", key); gsub(/"/, "\\\"", key)
			gsub(/\\/, "\\\\", val); gsub(/"/, "\\\"", val)
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			entry[pkg]=entry[pkg] "\"" key "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_battery_tmp"
}

# 預掃各 app 的後台運行狀態 (appops RUN_ANY_IN_BACKGROUND)
# 預掃各 app 的後台運行狀態 (appops RUN_ANY_IN_BACKGROUND)
# 對應系統設定「允許在背景使用 / 無限制 / 最佳化」
# 用法: prepare_battery_whitelist [單一包名]  — 不傳則掃 $txt 全部
# 寫到 $TMPDIR/.battery_wl 格式: pkg<TAB>mode (mode = allow/ignore/deny/default)
# 只記錄「有明確設定」的 (RUN_ANY_IN_BACKGROUND: xxx), 系統預設(Default mode)不記錄
prepare_battery_whitelist() {
	: > "$TMPDIR/.battery_wl"
	# dex v12 已經批量讀到 RUN_ANY_IN_BACKGROUND 時，直接從 .pkg_battery 轉出舊 battery_opt，避免逐 app appops get 變慢
	if [[ -s "$TMPDIR/.pkg_battery" ]]; then
		jq -Rr '
			split("	") as $x |
			select(($x|length) >= 2) |
			($x[1] | fromjson? // {}) as $j |
			($j["BATTERY:RUN_ANY_IN_BACKGROUND"] // "" | split(" ") | last) as $m |
			select($m != null and $m != "") |
			"\($x[0])	\($m)"
		' "$TMPDIR/.pkg_battery" > "$TMPDIR/.battery_wl" 2>/dev/null
		[[ -s "$TMPDIR/.battery_wl" ]] && return
	fi
	local _list
	if [[ -n $1 ]]; then
		_list="$1"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	local _total _i=0
	_total="$(echo "$_list" | grep -vc '^$')"
	echo "$_list" | while read -r _pkg; do
		[[ -z $_pkg ]] && continue
		let _i++
		printf '\r -預掃後台運行 %d/%d %s' "$_i" "$_total" "$(progress_bar $((_i * 100 / _total)))" >&2
		# appops 導向 </dev/null 避免吃掉迴圈 stdin
		_ops="$(appops get "$_pkg" RUN_ANY_IN_BACKGROUND </dev/null 2>/dev/null)"
		# 兼容兩種輸出格式:
		#   舊/部分裝置: "RUN_ANY_IN_BACKGROUND: allow"
		#   新/部分裝置: "Default mode: allow"
		_mode="$(echo "$_ops" | sed -n -e 's/^RUN_ANY_IN_BACKGROUND: \([a-z]*\).*/\1/p' -e 's/^Default mode: \([a-z]*\).*/\1/p' | head -1)"
		[[ -n $_mode ]] && printf '%s\t%s\n' "$_pkg" "$_mode" >> "$TMPDIR/.battery_wl"
	done
	echo >&2
}

# 預掃所有待備份 app 的數據目錄大小 (data/user/user_de/obb), 並行加速 (約快 3 倍)
# 寫到 $TMPDIR/.dir_sizes, 格式: pkg<TAB>type<TAB>size; 主迴圈 _dir_size 查此表免重複遍歷
prepare_dir_size_map() {
	local _map="$TMPDIR/.dir_sizes"
	: > "$_map"
	local _list
	if [[ -n $1 ]]; then
		_list="$1"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	[[ -z $_list ]] && return
	local _workdir="$TMPDIR/.dirsize_work"
	rm -rf "$_workdir"; mkdir -p "$_workdir"
	local _total _i=0 _running=0 _par=8
	_total="$(echo "$_list" | grep -vc '^$')"
	# 用 here-string 餵 while, 避免管道把迴圈丟進子 shell (子 shell 內背景任務的變數作用域問題)
	local _pkg _typ _dp
	while read -r _pkg; do
		[[ -z $_pkg ]] && continue
		let _i++
		printf '\r -預掃數據大小 %d/%d %s' "$_i" "$_total" "$(progress_bar $((_i * 100 / _total)))" >&2
		for _typ in user user_de data obb; do
			case $_typ in
				user)    _dp="$path2/$_pkg" ;;
				user_de) _dp="$path3/$_pkg" ;;
				data)    _dp="$path/data/$_pkg" ;;
				obb)     _dp="$path/obb/$_pkg" ;;
			esac
			[[ ! -d $_dp ]] && continue
			# 背景並行算大小, 各寫獨立檔 (無共享寫入, 安全); 背景內再確認 workdir 存在防競態
			{ [[ -d $_workdir ]] && printf '%s\t%s\t%s\n' "$_pkg" "$_typ" "$(find "$_dp" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1}END{print s+0}')" > "$_workdir/${_pkg}.${_typ}" 2>/dev/null; } &
			_running=$((_running+1))
			[[ $_running -ge $_par ]] && { wait; _running=0; }
		done
	done <<EOF
$_list
EOF
	wait
	echo >&2
	cat "$_workdir"/* 2>/dev/null > "$_map"
	rm -rf "$_workdir"
}

# 遠端模式: 並發預掃所有 app 的遠端 app_details.json 到本地快取
# 主迴圈 apk/data 增量比對直接讀快取, 免每 app 多次遠端往返
prepare_remote_json_map() {
	local _cache="$TMPDIR/.remote_json"
	rm -rf "$_cache"; mkdir -p "$_cache"
	[[ -z $remote_type ]] && return
	local _list
	_list="$(echo "$txt" | awk '{sub(/[[:space:]]+[^[:space:]]+$/,""); print}' | grep -v '^$')"
	[[ -z $_list ]] && { touch "$_cache/.done"; return; }
	local _subdir
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	# 全部 app 直接批量抓 json (不靠遠端列表交集 — smbclient 列表對中文名會轉碼毀名導致誤配)
	# 不存在的檔 get 失敗即空, 內容驗證會濾掉; 批量模式連線數不增
	echo "$_list" > "$TMPDIR/.json_fetch"
	local _total _i=0
	_total="$(grep -vc '^$' "$TMPDIR/.json_fetch")"
	if [[ $_total -eq 0 ]]; then
		rm -f "$TMPDIR/.json_fetch"; touch "$_cache/.done"; echo >&2; return
	fi
	if [[ $remote_type = smb ]]; then
		# SMB: 單連線批量 get (每批 20 檔), 連線數 120→6
		local _auth SMB_OPTS _batchcmd="" _app _n=0
		if [[ -n $remote_user ]]; then _auth="-U $remote_user%$remote_pass"; else _auth="-N"; fi
		SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _base="$SMB_REM_PATH/$_subdir"; _base="${_base#/}"; _base="${_base//\//\\}"
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++ _n++
			_batchcmd="$_batchcmd get \"${_app//\//\\}\\app_details.json\" \"$_cache/$_app.json\";"
			if [[ $_n -ge 20 ]]; then
				printf '\r -預掃遠端清單 %d/%d' "$_i" "$_total" >&2
				command smbclient "$SMB_SHARE" $_auth $SMB_OPTS -c "cd \"$_base\"; $_batchcmd" >/dev/null 2>&1
				_batchcmd=""; _n=0
			fi
		done < "$TMPDIR/.json_fetch"
		[[ -n $_batchcmd ]] && command smbclient "$SMB_SHARE" $_auth $SMB_OPTS -c "cd \"$_base\"; $_batchcmd" >/dev/null 2>&1
		printf '\r -預掃遠端清單 %d/%d' "$_total" "$_total" >&2
	else
		# WebDAV: curl 輕量, 8 併發逐檔
		local _running=0 _app
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++
			printf '\r -預掃遠端清單 %d/%d' "$_i" "$_total" >&2
			( _stream_download "$_subdir/$_app/app_details.json" 2>/dev/null > "$_cache/$_app.json" ) &
			let _running++
			if [[ $_running -ge 8 ]]; then wait; _running=0; fi
		done < "$TMPDIR/.json_fetch"
		wait
	fi
	rm -f "$TMPDIR/.json_fetch"
	# 內容驗證: 非 { 開頭視為不存在
	local _jf
	for _jf in "$_cache"/*.json; do
		[[ -f $_jf ]] || continue
		case "$(head -c 1 "$_jf" 2>/dev/null)" in
		'{') ;;
		*) rm -f "$_jf" ;;
		esac
	done
	echo >&2
	local _got
	_got="$(ls "$_cache"/*.json 2>/dev/null | grep -c json)"
	echoRgb "遠端清單快取: $_got/$_total 個 app 有遠端紀錄" "2"
	touch "$_cache/.done"
}

# 取遠端 app_details: 預掃快取命中直接用 (含「確定不存在」), 未預掃才即時下載
_get_remote_appdetails() {
	local _cache="$TMPDIR/.remote_json"
	# Media 不在批量預掃範圍內 (prepare_remote_json_map 只抓 appList.txt 裡的 app 名稱),
	# 快取裡永遠不會有 Media.json, 走快取分支必定誤判失敗 — 直接即時下載繞過快取
	if [[ $1 = Media ]]; then
		remote_download_single_file "$1/app_details.json" "$2"
		return $?
	fi
	if [[ -f $_cache/.done ]]; then
		if [[ -s "$_cache/$1.json" ]]; then
			cp "$_cache/$1.json" "$2" 2>/dev/null
			return 0
		fi
		return 1
	fi
	remote_download_single_file "$1/app_details.json" "$2"
}

# 流式模式: 並發預掃遠端各 app 是否已有入口腳本 (recover.sh)
# 結果寫 $TMPDIR/.remote_scripts (一行一個「已有腳本」的 app 名), 主迴圈查表零開銷
# 一次抓遠端檔案總列表 (供腳本檢查/核驗共用, 單連線取代逐檔往返)
prepare_remote_filelist() {
	: > "$TMPDIR/.remote_files"
	[[ -z $remote_type ]] && return
	echoRgb "預掃遠端檔案列表 (單次連線)..." "3"
	remote_list_files "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}" > "$TMPDIR/.remote_files" 2>/dev/null
	echoRgb "遠端列表取得 $(grep -vc '^$' "$TMPDIR/.remote_files" 2>/dev/null) 筆" "2"
}

prepare_remote_scripts_map() {
	local _map="$TMPDIR/.remote_scripts"
	: > "$_map"
	[[ $remote_stream != 1 ]] && return
	# 從總列表取「已有 recover.sh」的 app (零額外連線)
	awk -F'/recover.sh' '/\/recover.sh$/{print $1}' "$TMPDIR/.remote_files" 2>/dev/null > "$_map"
}


# 預掃 pkg → version code map (取代 Backup_apk 內每個 app 都 fork pm 的開銷)
# 寫到 $TMPDIR/.pkg_ver 格式: pkg<TAB>versionCode
prepare_pkg_ver_map() {
	# 正確解析 pm list packages --show-versioncode 輸出
	# 格式: package:<pkg> versionCode:<code> [更多欄位]
	# 用 awk 找出 versionCode: 後的數字, 同 pkg 多行只取第一個
	pm list packages --show-versioncode --user "${user:-0}" 2>/dev/null \
		| awk '
			{
				pkg = ""
				ver = ""
				for (i = 1; i <= NF; i++) {
					if ($i ~ /^package:/) {
						pkg = $i
						sub(/^package:/, "", pkg)
					} else if ($i ~ /^versionCode:/) {
						ver = $i
						sub(/^versionCode:/, "", ver)
					}
				}
				if (pkg != "" && ver != "" && !(pkg in seen)) {
					print pkg "\t" ver
					seen[pkg] = 1
				}
			}
		' > "$TMPDIR/.pkg_ver"
}

# 預掃所有 app 的 runtime permissions (取代 Backup_Permissions 內每個 app 各 fork dex)
# 寫到 $TMPDIR/.pkg_perms, 格式: pkg<TAB>json (json = getRuntimePermissions 輸出轉成的 object)
# Backup_Permissions 直接 awk 查, 不再呼叫 get_Permissions
prepare_permissions_map() {
	local _perms_tmp="$TMPDIR/.pkg_perms"
	: > "$_perms_tmp"
	# 一次取得所有 app 的包名 (空白分隔)
	local _all_pkgs
	_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃應用權限中..." "2"
	# 一次 get_Permissions 讀回所有 app (dex 只啟動 1 次, 取代逐 app N 次)
	# 輸出每行: 包名 權限名 true/false op mode → awk 按包名分組直接生成 json
	get_Permissions $_all_pkgs 2>/dev/null | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; perm=$2
			if (perm == "EXTRA_OP" && NF >= 4) {
				# 舊/未知 AppOps 輸出格式: pkg EXTRA_OP op mode
				# JSON key 必須唯一, 否則多個 EXTRA_OP 會互相覆蓋
				perm="EXTRA_OP_" $3
				val=$3 " " $4
			} else {
				# 一般格式: pkg permissionOrAppOp true/false op mode
				val=$3; for(i=4;i<=NF;i++) val=val" "$i
			}
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			# json 跳脫: 包名/權限名/值皆為安全字元(字母數字點底線冒號空白), 直接包引號
			entry[pkg]=entry[pkg] "\"" perm "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_perms_tmp"
}

# 預掃所有 app 的通知設定（NotificationManager / NotificationChannel）
# 寫到 $TMPDIR/.pkg_notify, 格式: pkg<TAB>json
# dex 輸出每行: packageName NOTIFY_xxx value
prepare_notifications_map() {
	local _notify_tmp="$TMPDIR/.pkg_notify"
	: > "$_notify_tmp"
	local _all_pkgs
	_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃應用通知設定中..." "2"
	get_Notifications $_all_pkgs 2>/dev/null | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; key=$2
			val=$3; for(i=4;i<=NF;i++) val=val" "$i
			# JSON escape: backslash first, then double quote
			gsub(/\\/, "\\\\", key); gsub(/"/, "\\\"", key)
			gsub(/\\/, "\\\\", val); gsub(/"/, "\\\"", val)
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			entry[pkg]=entry[pkg] "\"" key "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_notify_tmp"
}
# 用法: app_details_read <檔案路徑>
# 設定全域變數: APK_VER / SSAID_OLD / PERMS_OLD / PKG_NAME / BACKUP_TIME
#              SIZE_user / SIZE_data / SIZE_obb / SIZE_user_de / SIZE_media (各類型大小)
#              INSTALLER_OLD / BATTERY_OLD / BATTERY_SETTINGS_OLD
app_details_read() {
	local file="$1"
	APK_VER=""; SSAID_OLD=""; PERMS_OLD=""; NOTIFY_OLD=""; BATTERY_SETTINGS_OLD=""; PKG_NAME=""; BACKUP_TIME=""
	SIZE_user=""; SIZE_data=""; SIZE_obb=""; SIZE_user_de=""; SIZE_media=""
	INSTALLER_OLD=""; BATTERY_OLD=""
	[[ ! -f $file ]] && return
	# jq 把各值各印一行到暫存檔
	# 用 try ... catch "" 確保每個 expression 不論成敗都輸出一行 (即使空字串)
	# 避免某行 error 導致整個輸出位移
	local tmpf="$TMPDIR/.app_details_read_$$"
	jq -r '
		(try ([.[] | objects | select(.apk_version != null).apk_version] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.Ssaid != null).Ssaid] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.permissions != null).permissions | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.notification_settings != null).notification_settings | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.battery_settings != null).battery_settings | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.PackageName != null).PackageName] | .[0]) catch "" // ""),
		(try (.["Backup time"].date) catch "" // ""),
		(try (.user.Size) catch "" // ""),
		(try (.data.Size) catch "" // ""),
		(try (.obb.Size) catch "" // ""),
		(try (.user_de.Size) catch "" // ""),
		(try (.media.Size) catch "" // ""),
		(try ([.[] | objects | select(.installer != null).installer] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.battery_opt != null).battery_opt] | .[0]) catch "" // "")
	' "$file" 2>/dev/null > "$tmpf"
	# 用 FD 逐行讀 (mksh 相容)
	exec 3< "$tmpf"
	read -r APK_VER <&3
	read -r SSAID_OLD <&3
	read -r PERMS_OLD <&3
	read -r NOTIFY_OLD <&3
	read -r BATTERY_SETTINGS_OLD <&3
	read -r PKG_NAME <&3
	read -r BACKUP_TIME <&3
	read -r SIZE_user <&3
	read -r SIZE_data <&3
	read -r SIZE_obb <&3
	read -r SIZE_user_de <&3
	read -r SIZE_media <&3
	read -r INSTALLER_OLD <&3
	read -r BATTERY_OLD <&3
	exec 3<&-
	rm -f "$tmpf"
}

# Chrome 特例: trichromelibrary 會留多個舊版本, 只保留最新一個
# 在 Backup_apk 末尾 (name2=com.android.chrome 時) 呼叫
cleanup_chrome_legacy() {
	local files
	files=$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null)
	[[ -z $files ]] && return
	local n
	n=$(awk 'END{print NR}' <<< "$files")
	# 多於 1 個 → 按時間刪掉舊的, 只留最新
	if [[ $n -gt 1 ]]; then
		echo "$files" \
			| while read -r f; do
				printf '%s %s\n' "$(stat -c '%Y' "$f" 2>/dev/null)" "$f"
			done \
			| sort -n \
			| head -n -1 \
			| while read -r _ts oldfile; do
				rm -rf "${oldfile%/*/*}" && echo "刪除文件:${oldfile%/*/*}"
			done
	fi
	# 拷貝最新一個到備份目錄
	local kept
	kept=$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>/dev/null | head -1)
	[[ -f $kept ]] && cp -r "$kept" "$Backup_folder/nmsl.apk"
}

# 查 app uid (三層 fallback, 優先用 prepare_pkg_uid_map 預掃的 .pkg_uid)
# 用法: uid=$(get_app_uid "$pkg")
get_app_uid() {
	local pkg="$1" uid
	# 優先從預掃 map 查
	if [[ -f $TMPDIR/.pkg_uid ]]; then
		uid=$(awk -v p="$pkg" -F'\t' '$1 == p {print $2; exit}' "$TMPDIR/.pkg_uid")
		[[ -n $uid ]] && { echo "$uid"; return; }
	fi
	# fallback 1: pm list
	uid=$(pm list packages -U --user "${user:-0}" </dev/null | awk -v pkg="$pkg" -F'[ :]' '$2 == pkg {print $4; exit}')
	# fallback 2: dumpsys
	[[ -z $uid ]] && uid=$(dumpsys package "$pkg" 2>/dev/null | awk -F'uid=' '{print $2}' | grep -Eo '[0-9]+' | head -n 1)
	# fallback 3: get_uid
	[[ -z $uid ]] && uid=$(get_uid "$pkg" 2>/dev/null)
	echo "$uid" | grep -Eo '[0-9]+' | head -n 1
}

# 恢復用: 一次抓 Release_data 需要的 Size / keystore / path
# 用法: release_details_read <app_details.json> <entry>
# 設定全域變數: REL_SIZE / REL_KEYSTORE / REL_PATH
release_details_read() {
	local file="$1" entry="$2"
	REL_SIZE=""; REL_KEYSTORE=""; REL_PATH=""
	[[ ! -f $file ]] && return
	local tmpf="$TMPDIR/.rel_jq_$$"
	jq -r --arg e "$entry" '
		(try .[$e].Size catch "" // ""),
		(try ([.[] | objects | select(.keystore != null).keystore] | .[0]) catch "" // ""),
		(try .[$e].path catch "" // "")
	' "$file" 2>/dev/null > "$tmpf"
	exec 3< "$tmpf"
	read -r REL_SIZE <&3
	read -r REL_KEYSTORE <&3
	read -r REL_PATH <&3
	exec 3<&-
	rm -f "$tmpf"
}

# 預掃 pm list packages --user (取代 Restore 主迴圈內每 app fork)
# 寫到 $TMPDIR/.installed_pkgs (一行一個 pkg name)
prepare_installed_pkgs_map() {
	pm list packages --user "${user:-0}" 2>/dev/null \
		| cut -f2 -d':' > "$TMPDIR/.installed_pkgs"
}

# 計算指定目錄的總大小並輸出可讀字串 (KB/MB/GB)
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(calc_dir_size "$1")"
	# awk 比較大小差異 (無 32-bit 溢位)
	local _diff
	_diff=$(awk -v a="$filesizee" -v b="${filesize:-0}" 'BEGIN{print a-b}')
	case $_diff in
	-*)
		NJL="本次備份減少 $(size "$(awk -v a="${filesize:-0}" -v b="$filesizee" 'BEGIN{print a-b}')")" ;;
	0)
		NJL="文件大小未改變" ;;
	*)
		NJL="本次備份增加 $(size "$_diff")" ;;
	esac
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(size "$filesizee") $filesizee"
	echoRgb "$NJL"
}
# 把 bytes 轉成人類可讀格式 (B/KB/MB/GB)
# 用法: size <bytes 數值> 或 size <檔案路徑> (會 stat 取大小)
size() {
	local b_size get_size
	case $1 in
	*[!0-9]*)
		b_size="$(stat -c%s "$1" 2>/dev/null)" ;;
	*)
		b_size="$1" ;;
	esac
	# 用 awk printf 四捨五入 (跟檔案管理器一致), awk 處理大數無 32-bit 溢位問題
	if [[ $b_size -eq 0 ]]; then
		get_size="0 bytes"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1024)?1:0}') -eq 1 ]]; then
		get_size="${b_size} bytes"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1048576)?1:0}') -eq 1 ]]; then
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1024}") KB"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1073741824)?1:0}') -eq 1 ]]; then
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1048576}") MB"
	else
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1073741824}") GB"
	fi
	echo "$get_size"
}
#分區佔用信息
partition_info() {
	unset Skip
	Occupation_status="$(df -B1 "$(_resolve_real_mount "${1%/*}")" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1)}')"
	Filesize2="$(size "$Filesize")"
	# 流式模式: 數據不落地本機, 本機剩餘空間跟這次備份無關, 不顯示 (避免誤導使用者以為是遠端容量)
	if [[ $remote_stream = 1 ]]; then
		echo " -$2大小:$Filesize2"
	else
		echo " -$2大小:$Filesize2 剩餘大小:$(size "$Occupation_status")"
	fi
	if [[ $remote_stream != 1 && -n $Filesize ]]; then
		if awk -v a="$Filesize" -v b="$Occupation_status" 'BEGIN{exit !(a+0 > b+0)}'; then
			echoRgb "$2備份大小將超出rom可用大小" "0"
			Skip=1
		fi
	fi
	Occupation_status="$(df -h "$(_resolve_real_mount "${Backup%/*}")" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
# 取得指定 app 的後台運行 PID (用於跳過正在運行的 app)
Process_Information() {
	dumpsys activity processes 2>/dev/null | awk -v key="$1" -v user="$user" '
	function getUserFromUid(uid){return int(uid/100000)}
	# 進程塊起點: ProcessRecord{hash PID:name/uid} → 抓 pid (兼容無獨立 pid= 行的新格式)
	/ProcessRecord\{/ {tmp=$0; sub(/^.*ProcessRecord\{[^ ]+ /,"",tmp); sub(/:.*/,"",tmp); pid=tmp; uid=""; pkg=""; next}
	/^ *user #[0-9]+ uid=/ {if($0 ~ /ISOLATED uid=[0-9]+/){uid="";next} tmp=$0; sub(/^.*uid=/,"",tmp); sub(/ .*/,"",tmp); uid=tmp}
	/packageList=\{/ {tmp=$0; sub(/^.*packageList=\{/,"",tmp); sub(/\}.*/,"",tmp); pkg=tmp; if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)) print pid}}
	'
}
# 強制終止指定 app (am force-stop + pkill 雙保險)
kill_app() {
	process_Information="$(Process_Information "$name2")"
	if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
		if [[ $process_Information != "" ]]; then
			am force-stop --user "$user" "$name2" &>/dev/null
			echo "$process_Information" | xargs -r kill -9 2>/dev/null
			pkill -9 -f "$name2$|$name2[:/_]" 2>/dev/null
			#killall -9 "$name2" &>/dev/null
			#am kill "$name2" &>/dev/null
			echoRgb "殺死$name1進程"
		fi
	fi
}
# ======================================================
# 備份核心函數 (Backup_apk / Backup_data / ssaid / 權限)
# ======================================================
# 備份 app 的 apk 檔 (含 split apk, 用 tar/zstd 打包)
Backup_apk() {
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
	# 從預掃 map 查當前版本 (取代 fork pm + cut + head)
	eval "apk_version2=\${_pv_${name2//[!a-zA-Z0-9]/_}}"
	# 如果啟用遠程備份，從遠端獲取 app_details.json 進行對比
	local _remote_checked=0
	if [[ -n $remote_type ]]; then
		local remote_app_details="$TMPDIR/.remote_app_details_$$"
		local remote_rel="${name1}/app_details.json"
		if _get_remote_appdetails "$name1" "$remote_app_details" 2>/dev/null; then
			[[ -s $remote_app_details ]] && {
				_remote_checked=1
				# 從遠端 app_details 讀取版本號
				local remote_apk_ver
				remote_apk_ver=$(jq -r --arg name "$name1" 'try .[$name].apk_version catch "" // ""' "$remote_app_details" 2>/dev/null)
				# 如果遠端版本與當前版本一致, 且本地已有 apk 備份, 才跳過備份
				# (本地缺備份時不可跳過, 否則全新備份會漏掉此 app)
				local _local_apk_exists=0
				{ [[ -f "$Backup_folder/apk.tar.zst" ]] || [[ -f "$Backup_folder/apk.tar" ]]; } && _local_apk_exists=1
				# 流式模式: 遠端有且版本一致即可跳過 (不需本機 tar, 因流式本就不留本地)
				[[ $remote_stream = 1 ]] && _local_apk_exists=1
				if awk -v p="$name2" '$0==p{f=1} END{exit !f}' "$TMPDIR/.listver_changed" 2>/dev/null; then
					# 啟動檢查偵測到實機版本已變: 遠端 json 版本號不可信 (可能被失敗輪汙染), 強制重備
					echoRgb "清單偵測到版本已更新, 重新備份apk" "3"
				elif [[ -n $remote_apk_ver && $remote_apk_ver = "$apk_version2" && $_local_apk_exists = 1 ]]; then
					# 版本相符再核對遠端 apk 檔實際存在 (json 可能被舊版/失敗輪汙染而 apk 缺檔)
					_rapk_ok=0
					if [[ $remote_stream = 1 ]]; then
						if awk -v a="$name1/apk.tar.zst" -v b="$name1/apk.tar" '$0==a||$0==b{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>/dev/null; then
							_rapk_ok=1
						else
							# 列表沒找到 (可能中文名轉碼) → 單檔下載開頭確認
							case "$(_stream_download "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}/$name1/apk.tar.zst" 2>/dev/null | head -c 60)" in
							""|*NT_STATUS*) _rapk_ok=0 ;;
							*) _rapk_ok=1 ;;
							esac
						fi
					else
						_rapk_ok=1
					fi
					if [[ $_rapk_ok = 1 ]]; then
						if ! awk -v p="$name2" '$2==p{f=1} END{exit !f}' "$TMPDIR/.backup_done" 2>/dev/null; then
							echo "${Backup_folder##*/} $name2" >> "$TMPDIR/.backup_done"
						fi
						unset xb
						let osj++
						result=0
						echoRgb "Apk版本無更新(遠端備份無變化) 跳過備份" "2"
						rm -f "$remote_app_details"
						return 0
					fi
					echoRgb "版本相符但遠端缺apk檔, 補備份一次" "0"
				fi
			}
		fi
		rm -f "$remote_app_details"
		# 遠端啟用但查無此備份: 即使本地版本未變, 仍會備份並上傳一次
		[[ $_remote_checked = 0 ]] && echoRgb "遠端無此備份 將備份一次並上傳" "2"
	fi
	# APK_VER 已經由 app_details_read 載入 (在主迴圈呼叫過)
	apk_version="$APK_VER"
	# 遠端已啟用但無備份時，不應依據本地 app_details 跳過，應上傳到遠端
	_local_apk_exists=0
	{ [[ -f "$Backup_folder/apk.tar.zst" ]] || [[ -f "$Backup_folder/apk.tar" ]]; } && _local_apk_exists=1
	# 流式模式: 不依賴本機 tar (本機可能有舊備份殘留), 強制當作無本機檔, 走重新壓縮流式
	[[ $remote_stream = 1 ]] && _local_apk_exists=0
	if [[ $apk_version = $apk_version2 ]] && [[ $_local_apk_exists = 1 ]]; then
		# 版本一致且本地已有備份: 不重新打包
		if ! awk -v p="$name2" '$2==p{f=1} END{exit !f}' "$TMPDIR/.backup_done" 2>/dev/null; then
			echo "${Backup_folder##*/} $name2" >> "$TMPDIR/.backup_done"
		fi
		unset xb
		let osj++
		result=0
		# 遠端啟用但查無此備份: 不重壓, 直接把現有本地檔標記為待上傳 (流式無本地檔, 不走此路)
		if [[ $remote_stream != 1 && -n $remote_type && $_remote_checked = 0 ]]; then
			backup_has_changes=1
			_mark_changed
			echoRgb "Apk版本無更新 遠端缺檔: 直接上傳本地備份(免重壓)" "2"
		else
			echoRgb "Apk版本無更新 跳過備份" "2"
		fi
	else
		if [[ $nobackup = false ]]; then
			# 版本一致且本地已有 apk 備份: 不重壓 (避免重複備份)
			if [[ $apk_version != "" && $apk_version = "$apk_version2" && $_local_apk_exists = 1 ]]; then
				let osj++
				echoRgb "版本:$apk_version 無更新 跳過備份" "2"
				if ! awk -v p="$name2" '$2==p{f=1} END{exit !f}' "$TMPDIR/.backup_done" 2>/dev/null; then
					echo "${Backup_folder##*/} $name2" >> "$TMPDIR/.backup_done"
				fi
				result=0
				return 0
			fi
			if [[ $apk_version != "" ]]; then
				if [[ $apk_version = "$apk_version2" ]]; then
					let osj++
					if [[ $remote_stream = 1 || -n $remote_type ]]; then
						echoRgb "版本:$apk_version (遠端無此版本, 補備份一次)"
					else
						echoRgb "版本:$apk_version (本機無備份檔, 補備份一次)"
					fi
				else
					let osn++
					# 用暫存檔取代字串拼接
					echo "$name1 \"$name2\"" >> "$TMPDIR/.update_apks"
					echoRgb "版本:$apk_version>$apk_version2"
				fi
			else
				let osk++
				echo "$name1 \"$name2\"" >> "$TMPDIR/.add_apks"
				echoRgb "版本:$apk_version2"
			fi
			unset Filesize
			Filesize="$(calc_dir_size "$apk_path2")"
			rm -rf "$Backup_folder/apk.tar"*
			partition_info "$Backup" "$name1 apk"
			if [[ $Skip != 1 ]]; then
				#備份apk
				echoRgb "$1"
				echo "$apk_path" | sed -e '/^$/d' | while read -r; do
					echoRgb "${REPLY##*/} $(size "$REPLY")"
				done
				tar_compress_glob "$Backup_folder/apk" "$apk_path2" "*.apk"
				echo_log "備份$apk_number個Apk"
				if [[ $result = 0 ]]; then
					# 流式模式: apk 已流式傳遠端, 本機無 tar 可校驗, 跳過 (信任傳輸)
					[[ $remote_stream != 1 ]] && Validation_file "$Backup_folder/apk.tar"*
					if [[ $result = 0 ]]; then
						# 加進備份完成清單 (avoid 重複)
						if ! awk -v p="$name2" '$2==p{f=1} END{exit !f}' "$TMPDIR/.backup_done" 2>/dev/null; then
							echo "${Backup_folder##*/} $name2" >> "$TMPDIR/.backup_done"
						fi
						[[ $apk_version != "" ]] && {
						echoRgb "覆蓋app_details"
						jq_inplace "$app_details" --arg apk_version "$apk_version2" --arg software "$name1" --arg pkg "$name2" '.[$software].apk_version = $apk_version | .[$software].PackageName = $pkg'
						} || {
						echoRgb "新增app_details"
						extra_content="{
						\"$name1\": {
							\"PackageName\": \"$name2\",
							\"apk_version\": \"$apk_version2\"
						}
						}"
						jq_inplace "$app_details" --argjson new_content "$extra_content" '. += $new_content'
						}
						# 標記有備份變更
						backup_has_changes=1
						# 記錄有變更的應用
						_mark_changed
						# Chrome 特例
						[[ $name2 = com.android.chrome ]] && cleanup_chrome_legacy
					else
						rm -rf "$Backup_folder"
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
# 備份 app 的 SSAID (應用識別碼)
# 用 classes.dex 透過 app_process 讀 /data/system/users/$user/settings_ssaid.xml
# 沒備份 SSAID 恢復後遊戲帳號會被當新裝置
Backup_ssaid() {
	# Ssaid (舊值) 已由 app_details_read 載入到 SSAID_OLD
	Ssaid="$SSAID_OLD"
	ssaid="$(awk -v pkg="$name2" '$1 == pkg {print $2}'<<<"$ssaid_info")"
	[[ $ssaid != null && $ssaid != "" ]] && echoRgb "SSAID:$ssaid"
	if [[ $ssaid != null && $ssaid != $Ssaid ]]; then
		echoRgb "備份ssaid"
		echoRgb "$Ssaid>$ssaid"
		# 用暫存檔取代字串拼接
		echo "$name1 \"$name2\"" >> "$TMPDIR/.ssaid_apks"
		jq_inplace "$app_details" --arg entry "$name1" --arg new_value "$ssaid" '.[$entry].Ssaid |= $new_value'
		echo_log "備份ssaid"
		[[ $result = 0 ]] && _mark_changed
	fi
	[[ $ssaid = null ]] && ssaid=
}
# 備份 app 的 runtime permissions (運行時權限)
# 恢復時可一鍵還原所有授權, 不用再手動點
Backup_Permissions() {
	# 從預掃 map 讀取當前系統權限
	eval "Get_Permissions=\${_pp_${name2//[!a-zA-Z0-9]/_}}"
	# 上次備份的舊值 (由 app_details_read 載入到 PERMS_OLD)
	local perms_old="$PERMS_OLD"
	[[ $_perm_diag = 1 ]] && echoRgb "[診斷] $name1 PERMS_OLD長度=${#perms_old} app_details=$app_details 種子存在=$([[ -s $TMPDIR/.remote_json/$name1.json ]] && echo Y || echo N)" "0" >&2
	if [[ $Get_Permissions != "" && ($Get_Permissions = *true* || $Get_Permissions = *false*) ]]; then
		if [[ $perms_old = "" ]]; then
			echoRgb "備份權限"
			jq_inplace "$app_details" --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName].permissions |= $permissions'
			echo_log "備份權限"
			[[ $result = 0 ]] && _mark_changed
		else
			if [[ $perms_old = *true* || $perms_old = *false* ]]; then
				if [[ $perms_old != $Get_Permissions ]]; then
					echoRgb "權限變更"
					jq -n --argjson old "$perms_old" --argjson new "$Get_Permissions" \
						'
						def flag: split(" ")[0];
						def opmode:
						  (split(" ")) as $v |
						  if ($v|length) >= 3 then " op=" + $v[1] + " mode=" + $v[2]
						  elif ($v|length) >= 2 then " op=" + $v[0] + " mode=" + $v[1]
						  else "" end;
						$new
						| to_entries
						| map(select(.key as $k | $old[$k] == null or $old[$k] != .value)
						  | "\(.key)|\(if ($old[.key] == null) then "新增→" + (.value|flag) + (.value|opmode) else ($old[.key]|flag) + "→" + (.value|flag) + "  " + ($old[.key]|opmode) + " →" + (.value|opmode) end)")
						| .[]
						' \
						-r 2>/dev/null | while IFS='|' read -r _pname _pchange; do
						echoRgb "$(_perm_cn "$_pname"): $_pchange"
					done
					jq_inplace "$app_details" --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName] |= . + {permissions: $permissions}'
					echo_log "備份權限"
					[[ $result = 0 ]] && _mark_changed
				fi
			fi
		fi
	else
		[[ $Get_Permissions != "" ]] && echoRgb "備份權限失敗" "0"
	fi
}
# 備份通知設定（NotificationManager / NotificationChannel）
# 恢復時可還原通知總開關、通知圓點、對話/泡泡、channel 重要性等可寫欄位
Backup_Notifications() {
	# 從預掃 map 讀取當前系統通知設定
	eval "Get_Notifications=\${_pn_${name2//[!a-zA-Z0-9]/_}}"
	local notify_old="$NOTIFY_OLD"
	[[ -z $Get_Notifications ]] && return
	if [[ $notify_old = "" ]]; then
		echoRgb "備份通知設定"
		jq_inplace "$app_details" --arg packageName "$name1" --argjson notification_settings "$Get_Notifications" '.[$packageName].notification_settings |= $notification_settings'
		echo_log "備份通知設定"
		[[ $result = 0 ]] && _mark_changed
	else
		if [[ $notify_old != "$Get_Notifications" ]]; then
			echoRgb "通知設定變更"
			jq -n --argjson old "$notify_old" --argjson new "$Get_Notifications" '
				$new
				| to_entries
				| map(select(.key as $k | $old[$k] == null or $old[$k] != .value)
				  | "\(.key)|\(if ($old[.key] == null) then "新增→" + .value else $old[.key] + "→" + .value end)")
				| .[]
			' -r 2>/dev/null | while IFS='|' read -r _nkey _nchange; do
				echoRgb "$(_notify_cn "$_nkey"): $_nchange"
			done
			jq_inplace "$app_details" --arg packageName "$name1" --argjson notification_settings "$Get_Notifications" '.[$packageName] |= . + {notification_settings: $notification_settings}'
			echo_log "備份通知設定"
			[[ $result = 0 ]] && _mark_changed
		fi
	fi
}

# 通知設定 key → 中文顯示
_notify_cn() {
	case $1 in
		NOTIFY_APP:enabled) echo "通知總開關" ;;
		NOTIFY_APP:importance) echo "通知重要性" ;;
		NOTIFY_APP:showBadge) echo "允許使用通知圓點" ;;
		NOTIFY_APP:bubblePreference|NOTIFY_APP:allowBubbles) echo "對話區/泡泡通知" ;;
		NOTIFY_CHANNEL:*:showBadge) echo "允許使用通知圓點" ;;
		NOTIFY_CHANNEL:*:importance) echo "通知分類重要性" ;;
		NOTIFY_CHANNEL:*:allowBubbles|NOTIFY_CHANNEL:*:canBubble) echo "對話區/泡泡通知" ;;
		NOTIFY_CHANNEL:*:importantConversation) echo "重要對話" ;;
		NOTIFY_CHANNEL:*:demoted) echo "降低對話優先級" ;;
		NOTIFY_CHANNEL:*:vibration) echo "通知分類震動" ;;
		NOTIFY_CHANNEL:*:lights) echo "通知分類燈號" ;;
		NOTIFY_CHANNEL:*:deleted) echo "通知分類已刪除" ;;
		NOTIFY_GROUP:*:blocked) echo "通知分類群組封鎖" ;;
		*) echo "$1" ;;
	esac

}

# 電池/背景設定 key → 中文顯示
_battery_cn() {
	case $1 in
		BATTERY:RUN_IN_BACKGROUND) echo "背景執行" ;;
		BATTERY:RUN_ANY_IN_BACKGROUND) echo "任意背景執行" ;;
		BATTERY:deviceidle_whitelist) echo "Doze白名單" ;;
		*) echo "$1" ;;
	esac
}

# 備份額外 metadata: installer (安裝來源) 與 battery_opt/battery_settings (電池/背景設定)
# 從預掃 map 讀取, 不額外 fork; 變更時寫入 app_details.json
Backup_extra() {
	# installer name
	local installer
	eval "installer=\${_pi_${name2//[!a-zA-Z0-9]/_}}"
	if [[ -n $installer && $installer != $INSTALLER_OLD ]]; then
		jq_inplace "$app_details" --arg entry "$name1" --arg v "$installer" '.[$entry].installer |= $v'
		echo_log "備份installer"
		[[ $result = 0 ]] && echoRgb "安裝來源:$installer" "2"
		[[ $result = 0 ]] && _mark_changed
	fi
	# battery_settings: dex v12 批量後台/電池設定（RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND / deviceidle whitelist）
	local batt_settings
	eval "batt_settings=\${_bs_${name2//[!a-zA-Z0-9]/_}}"
	if [[ -n $batt_settings && $batt_settings != "$BATTERY_SETTINGS_OLD" ]]; then
		if [[ $BATTERY_SETTINGS_OLD != "" ]]; then
			echoRgb "電池/背景設定變更" "2"
			jq -n --argjson old "$BATTERY_SETTINGS_OLD" --argjson new "$batt_settings" '
				$new
				| to_entries
				| map(select(.key as $k | $old[$k] == null or $old[$k] != .value)
				  | "\(.key)|\(if ($old[.key] == null) then "新增→" + .value else $old[.key] + "→" + .value end)")
				| .[]
			' -r 2>/dev/null | while IFS='|' read -r _bkey _bchange; do
				echoRgb "$(_battery_cn "$_bkey"): $_bchange"
			done
		else
			echoRgb "備份電池/背景設定" "2"
		fi
		jq_inplace "$app_details" --arg entry "$name1" --argjson v "$batt_settings" '.[$entry].battery_settings |= $v'
		echo_log "備份battery_settings"
		[[ $result = 0 ]] && _mark_changed
	fi
	# battery_opt: 舊版相容（RUN_ANY_IN_BACKGROUND 單一 mode）
	local batt
	eval "batt=\${_bw_${name2//[!a-zA-Z0-9]/_}}"
	if [[ -n $batt && $batt != $BATTERY_OLD ]]; then
		jq_inplace "$app_details" --arg entry "$name1" --arg v "$batt" '.[$entry].battery_opt |= $v'
		echo_log "備份battery_opt"
		[[ $result = 0 ]] && echoRgb "後台運行設定:$batt" "2"
		[[ $result = 0 ]] && _mark_changed
	fi
}
#檢測數據位置進行備份
Backup_data() {
	data_path="$path/$1/$name2"
	MODDIR_NAME="${data_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	# 取舊 Size:
	# - 應用備份 ($1 = user/data/obb/user_de): 直接讀 app_details_read 預讀的變數
	# - 媒體備份 ($1 = 動態資料夾名 Download/DCIM/...): 預讀變數沒有, fallback 用 jq 即時查
	# - 其他 (thanox 等): 同 fallback
	Size=""
	case $1 in
	user|data|obb|user_de|media)
		eval "Size=\"\$SIZE_$1\""
		;;
	*)
		[[ -f $app_details ]] && Size="$(jq -r --arg entry "$1" 'try .[$entry].Size catch "" // ""' "$app_details" 2>/dev/null)"
		;;
	esac
	[[ -z $Size ]] && Size=""
	case $1 in
	user) data_path="$path2/$name2" ;;
	user_de) data_path="$path3/$name2" ;;
	data|obb|media) ;;
	*)
		data_path="$2"
		# 自訂資料夾固定用 tar 打包 (不透過暫改全域 Compression_method 再復原這種做法,
		# 改用 local override 變數, 避免備份結尾等其他環節讀到中途被污染的全域值)
		[[ $1 != thanox ]] && local _comp_override=tar
		zsize=1
		zmediapath=1
		;;
	esac
	# 如果啟用遠程備份，從遠端獲取 app_details.json 進行對比
	local _remote_data_checked=0
	if [[ -n $remote_type ]]; then
		local remote_app_details="$TMPDIR/.remote_app_details_$$"
		local _remote_lookup_name
		case $1 in
		user|data|obb|user_de|media) _remote_lookup_name="$name1" ;;
		# 自訂資料夾 (如 Download/DCIM): 所有資料夾共用同一份 Media/app_details.json,
		# 不是各自獨立的 "$1/app_details.json" — 查詢路徑必須固定用 "Media"
		*) _remote_lookup_name="Media" ;;
		esac
		local remote_rel="${_remote_lookup_name}/app_details.json"
		if ! _get_remote_appdetails "$_remote_lookup_name" "$remote_app_details" 2>/dev/null; then
			# 重試一次, 避免單次網路抖動導致整段增量比對失效
			sleep 1
			_get_remote_appdetails "$_remote_lookup_name" "$remote_app_details" 2>/dev/null
		fi
		if [[ -s $remote_app_details ]]; then
			{
				# 從遠端 app_details 讀取 Size
				local remote_size
				remote_size=$(jq -r --arg entry "$1" 'try .[$entry].Size catch "" // ""' "$remote_app_details" 2>/dev/null)
				[[ $_INCREMENTAL_DEBUG = 1 ]] && echoRgb "[診斷] 查詢=$_remote_lookup_name 抓到檔案大小=$(wc -c < "$remote_app_details" 2>/dev/null) remote_size=$remote_size" "0" >&2
				# 如果遠端 Size 與當前一致，跳過備份
				if [[ -n $remote_size && $remote_size != "null" ]]; then
					_remote_data_checked=1
					local current_size
					_dir_size "$name2" "$1" "$data_path"; current_size="$_DIR_SIZE_RET"
					# 本地必須已有該 tar 才可跳過, 否則全新備份會漏掉
					local _local_data_exists=0
					ls "$Backup_folder/$1.tar"* >/dev/null 2>&1 && _local_data_exists=1
					# 流式模式: 遠端 Size 一致即可跳過 (不需本機 tar)
					[[ $remote_stream = 1 ]] && _local_data_exists=1
					if [[ "$remote_size" = "$current_size" && $_local_data_exists = 1 ]]; then
						echoRgb "$1數據無變化(遠端備份無變化) 跳過備份" "2"
						rm -f "$remote_app_details"
						return 0
					fi
				fi
			}
		else
			[[ $_INCREMENTAL_DEBUG = 1 ]] && echoRgb "[診斷] 查詢=$_remote_lookup_name _get_remote_appdetails失敗(重試後仍下載失敗)" "0" >&2
		fi
		rm -f "$remote_app_details"
	fi
	if [[ -d $data_path ]]; then
		unset Filesize ssaid Get_Permissions result Permissions
		_dir_size "$name2" "$1" "$data_path"; Filesize="$_DIR_SIZE_RET"
		# ssaid/permissions 只要是 user 類型就無條件執行 (不依賴 size 變化)
		case $1 in
		user)
			Backup_ssaid
			Backup_Permissions
			Backup_Notifications
			Backup_extra
			;;
		esac
		[[ $Filesize != "" ]] && {
		# 遠端缺檔但本地 Size 無變化且本地 tar 已存在: 不重壓, 直接標記上傳現有本地檔
		local _local_data_exists2=0 _tarchk
		for _tarchk in "$Backup_folder/$1".tar*; do
			[[ -e $_tarchk ]] && { _local_data_exists2=1; break; }
		done
		# 流式模式: 忽略本機殘留 tar, 強制重新壓縮流式上傳
		[[ $remote_stream = 1 ]] && _local_data_exists2=0
		if [[ $remote_stream != 1 && -n $remote_type && $_remote_data_checked = 0 && $Size = $Filesize && $_local_data_exists2 = 1 ]]; then
			backup_has_changes=1
			case $1 in user|data|obb|user_de|media) _mark_changed ;; esac
			echoRgb "$1數據無變化 遠端缺檔: 直接上傳本地備份(免重壓)" "2"
			return 0
		fi
		# 遠端已啟用但無備份時，即使本地 Size 無變化也應上傳到遠端
		local _force_data_backup=0
		# 遠端已啟用時，匹配的情況已在上面 return 0，走到這裡代表遠端要嘛沒有 Size 要嘛不匹配，都應備份
		[[ -n $remote_type ]] && _force_data_backup=1
		if [[ $Size != $Filesize ]] || [[ $_force_data_backup = 1 ]]; then
			case $1 in
			user)
				# 從預掃的 pkg→uid map 查 uid (省去 fork pm + awk)
				local _uid
				eval "_uid=\${_pu_${name2//[!a-zA-Z0-9]/_}}"
				if [[ -n $_uid ]] && [[ $(su "$_uid" -c keystore_cli_v2 list 2>/dev/null | wc -l) -ge 2 ]]; then
					echoRgb "$name1包含keystore 恢復可能閃退" "0"
					jq_inplace "$app_details" --arg entry "$name1" '.[$entry].keystore |= "true"'
				else
					jq_inplace "$app_details" --arg entry "$name1" '.[$entry].keystore |= "false"'
				fi ;;
			esac
			#停止應用
			case $1 in
			user|data|obb|user_de) kill_app ;;
			esac
			rm -rf "$Backup_folder/$1.tar"*
			partition_info "$Backup" "$1"
			if [[ $Skip != 1 ]]; then
				echoRgb "備份$1數據"
				# 判斷是否超過 1KB (太小的數據不值得備份, 可能是空目錄)
				# 注意: Android mksh 在 32-bit 環境下 [[ $a -gt N ]] 對超過 ~2GB 的數值會溢位
				# 改用字串長度判斷: bytes 數值字串長度 >= 4 就是 >= 1000 bytes (約 1KB)
				if [[ ${#Filesize} -ge 4 ]]; then
					Start_backup="true"
				else
					Start_backup="false"
				fi
				if [[ $Start_backup = true ]]; then
					local _dp_name="${data_path##*/}"
					case $1 in
					user|user_de)
						tar_compress_dir "$Backup_folder/$1" "${data_path%/*}" "$_dp_name" \
							--exclude="$_dp_name/.ota" \
							--exclude="$_dp_name/cache" \
							--exclude="$_dp_name/lib" \
							--exclude="$_dp_name/code_cache" \
							--exclude="$_dp_name/no_backup" \
							2>/dev/null
						;;
					*)
						tar_compress_dir "$Backup_folder/$1" "${data_path%/*}" "$_dp_name" \
							--exclude="Backup_*" \
							--exclude="$_dp_name/cache" \
							--exclude="$_dp_name/QQ" \
							--exclude="$_dp_name/Telegram" \
							--exclude="$_dp_name/.*"
						;;
					esac
					echo_log "備份$1數據"
				else
					echoRgb "$1數據 $Filesize2太小" "0" && result=1
				fi
				if [[ $result = 0 ]]; then
					# 流式模式: 數據已直接傳遠端, 本機無 tar 可校驗, 跳過校驗 (信任傳輸)
					[[ $remote_stream != 1 ]] && Validation_file "$Backup_folder/$1.tar"*
					if [[ $result = 0 ]]; then
						if [[ $remote_stream = 1 ]]; then
							echoRgb "$1數據已流式上傳遠端 (大小 $(size "$Filesize"))" "1"
						elif [[ ! $Filesize -eq 0 ]]; then
							size2="$(stat -c %s "$Backup_folder/$1.tar"*)"
							rate="$(awk -v s="$size2" -v f="$Filesize" 'BEGIN{printf "%.2f", (1-(s/f))*100}')"
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
							jq_inplace "$app_details" --argjson new_content "$extra_content" '. += $new_content'
						else
							extra_content="{
							\"$1\": {
								\"Size\": \"$Filesize\"
							},
							\"Backup time\": {
								\"date\": \"$(date "+%Y.%m.%d %H:%M:%S")\"
							}
							}"
							jq_inplace "$app_details" --argjson new_content "$extra_content" '. += $new_content'
						fi
						# 標記有備份變更
						backup_has_changes=1
						# 記錄有變更的應用 (media=Android/media/<pkg>, 屬正常app數據;
						# 排除的是大寫Media自定義目錄備份功能, 走REMOTE_UPLOAD_MEDIA另計)
						case $1 in user|data|obb|user_de|media) _mark_changed ;; esac
					else
						rm -rf "$Backup_folder/$1".tar.*
					fi
				fi
			fi
		else
			[[ $Size != "" ]] && echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
		}
	else
		[[ -f $data_path ]] && echoRgb "$1是一個文件 不支持備份" "0"
	fi
}
# 恢復 app 的 data 資料 (解壓 tar.zst 到 /data/data/<pkg>/)
# 處理 selinux context、uid 綁定
Release_data() {
	tar_path="$1"
	X="$path2/$name2"
	MODDIR_NAME="${tar_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${tar_path##*/}"
	# 只去 .tar / .tar.zst 後綴 (不可用 %%.* , 否則 service.d.tar 會被砍成 service)
	FILE_NAME2="${FILE_NAME%.zst}"
	FILE_NAME2="${FILE_NAME2%.tar}"
	case ${FILE_NAME##*.} in
	zst | tar)
		unset FILE_PATH Size Selinux_state
		# 一次 jq 抓 Size / keystore / path (取代 3 個獨立 jq fork)
		release_details_read "$app_details" "$FILE_NAME2"
		Size="$REL_SIZE"
		case $FILE_NAME2 in
		user)
			if [[ -d $X ]]; then
				[[ $REL_KEYSTORE = true ]] && echoRgb "$name1存在keystore 恢復可能閃退" "0"
				FILE_PATH="$path2"
				# 合併 LS|awk|sed → 1 個 awk (省 2 fork)
				Selinux_state="$(LS "$X" 2>/dev/null | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			else
				echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
			fi ;;
		user_de)
			X="$path3/$name2"
			if [[ -d $X ]]; then
				FILE_PATH="$path3"
				Selinux_state="$(LS "$X" 2>/dev/null | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			else
				echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
			fi ;;
		data)
			FILE_PATH="$path/data"
			Selinux_state="$(LS "$FILE_PATH" 2>/dev/null | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			;;
		obb)
			FILE_PATH="$path/obb"
			Selinux_state="$(LS "$FILE_PATH" 2>/dev/null | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			;;
		media)
			FILE_PATH="$path/media"
			;;
		thanox) FILE_PATH="/data/system" && find "/data/system" -name "thanos"* -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null ;;
		*)
			if [[ $A != "" ]]; then
				if [[ ${MODDIR_NAME##*/} = Media ]]; then
					FILE_PATH="$REL_PATH"
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
			# 流式恢復: 從遠端拉 → 管道解壓 (不落地本機); _STREAM_SRC 為遠端相對路徑
			if [[ $_RESTORE_STREAM = 1 && -n $_STREAM_SRC ]]; then
				case ${FILE_NAME##*.} in
				zst) _stream_download "$_STREAM_SRC" | zstd -d 2>/dev/null | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$FILE_PATH" ;;
				tar) [[ ${MODDIR_NAME##*/} = Media ]] && _stream_download "$_STREAM_SRC" | tar --checkpoint-action="ttyout=%T\r" -axf - -C "$FILE_PATH" || _stream_download "$_STREAM_SRC" | tar --checkpoint-action="ttyout=%T\r" -amxf - -C "$FILE_PATH" ;;
				esac
				result=$?
			else
				case ${FILE_NAME##*.} in
				zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$tar_path" -C "$FILE_PATH" ;;
				tar) [[ ${MODDIR_NAME##*/} = Media ]] && tar --checkpoint-action="ttyout=%T\r" -axf "$tar_path" -C "$FILE_PATH" || tar --checkpoint-action="ttyout=%T\r" -amxf "$tar_path" -C "$FILE_PATH" ;;
				esac
			fi
		else
			Set_back_1
		fi
		echo_log "解壓縮$FILE_NAME"
		if [[ $result = 0 ]]; then
			case $FILE_NAME2 in
			user|data|obb|user_de)
				# 用 helper 查 uid (取代 3 層 fallback 散落)
				G="$(get_app_uid "$name2")"
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
								echo_log "selinux上下文設置"
							else
								echoRgb "路徑:$X出現錯誤"
							fi ;;
						data|obb)
							chown -hR "$uid" "$FILE_PATH/$name2/"
							echo_log "設置用戶組$uid"
							chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>/dev/null
							echo_log "selinux上下文設置" ;;
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
	case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
}
# 安裝 apk (含 split apk 處理), 自動繞過安裝驗證
installapk() {
	# 流式恢復: 從遠端拉 apk.tar.zst → 解壓到 TMPDIR (apk 安裝需檔案, pm install 不能用 stdin)
	if [[ $_RESTORE_STREAM = 1 && -n $_STREAM_APK_SRC ]]; then
		[[ -n $TMPDIR ]] && rm -f "$TMPDIR"/*.apk 2>/dev/null
		case ${_STREAM_APK_SRC##*.} in
		zst) _stream_download "$_STREAM_APK_SRC" | zstd -d 2>/dev/null | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$TMPDIR" ;;
		tar) _stream_download "$_STREAM_APK_SRC" | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$TMPDIR" ;;
		esac
		result=$?
		echo_log "apk流式解壓"
	else
		apkfile="$(find "$Backup_folder" -maxdepth 1 -name "apk.*" -type f 2>/dev/null)"
		if [[ $apkfile != "" ]]; then
			case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
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
	fi
	if [[ $result = 0 ]]; then
		# 用 glob + 計數取代 find | wc (省 2 fork)
		local _apks _apk_count=0
		for _apks in "$TMPDIR"/*.apk; do
			[[ -f $_apks ]] && let _apk_count++
		done
		case $_apk_count in
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
			# 用 glob 取代 find | grep -v (省 fork)
			for _apks in "$TMPDIR"/*.apk; do
				[[ -f $_apks && ${_apks##*/} != nmsl.apk ]] || continue
				pm install-write "$b" "${_apks##*/}" "$_apks" </dev/null >/dev/null
				echo_log "${_apks##*/}安裝"
			done
			pm install-commit "$b" >/dev/null
			echo_log "split Apk安裝"
			;;
		esac
	fi
}
# 關閉 apk 安裝驗證 (verifier_verify_adb_installs)
# 避免 Play Protect / 系統驗證攔截批次安裝
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
# 從 app 安裝資訊取得 app 名稱 / apk 路徑 / 版本等資料
# 用 classes.dex 透過 hidden API 拿到完整 PackageInfo
get_name(){
	txt="$MODDIR/appList.txt"
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
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$Folder/app_details.json" | head -n 1)"
			PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$Folder/app_details.json")"
		fi
		if [[ $PackageName = "" || $ChineseName = "" ]]; then
			echoRgb "${Folder##*/}包名獲取失敗，解壓縮獲取包名中..." "0"
			case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
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
						case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
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
	# 重新生成後一致性檢查: 比對資料夾與 appList.txt
	if [[ -f $txt ]]; then
		local _chk_folders="$TMPDIR/.chk_folders" _chk_listed="$TMPDIR/.chk_listed"
		for d in "$MODDIR"/*/; do
			d="${d%/}"; d="${d##*/}"
			case "$d" in wifi|Media|tools|log) continue ;; esac
			echo "$d"
		done | sort > "$_chk_folders"
		awk '!/^#|^＃/ && NF {print $1}' "$txt" | sort > "$_chk_listed"
		local _only_folder _only_list
		_only_folder="$(comm -23 "$_chk_folders" "$_chk_listed")"
		_only_list="$(comm -13 "$_chk_folders" "$_chk_listed")"
		if [[ -n $_only_folder || -n $_only_list ]]; then
			echoRgb "_______________________________________" "2"
			echoRgb "一致性檢查發現異常:" "0"
			[[ -n $_only_folder ]] && { echoRgb "有資料夾但不在清單:" "0"; echo "$_only_folder"; }
			[[ -n $_only_list ]] && { echoRgb "在清單但無資料夾:" "0"; echo "$_only_list"; }
		else
			echoRgb "一致性檢查通過: 資料夾與清單完全對應" "1"
		fi
		rm -f "$_chk_folders" "$_chk_listed" 2>/dev/null
	fi
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
			if ! ask_yn "確認列表無誤後刪除?" "刪除" "退出腳本編輯列表"; then
				exit 0
			fi
			if true; then
				echoRgb "警告 即將刪除未安裝應用資料夾，請再三確認後在執行" "0"
				echoRgb "以下資料夾將被刪除:" "0"
				echo "$delete_app" | sed '/^$/d' | awk '{print "  - "$1}'
				if ! ask_yn "確認刪除?" "確認刪除" "取消"; then
					echoRgb "已取消刪除" "1"
					exit 0
				fi
				i=1
				r="$(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }')"
				while [[ $i -le $r ]]; do
					name1="$(echo "$delete_app" | awk -v n=$i 'NF{c++} c==n{print $1; exit}')"
					name2="$(echo "$delete_app" | awk -v n=$i 'NF{c++} c==n{print $2; exit}')"
					if [[ -z $name1 ]]; then
						echoRgb "第$i個應用名稱解析失敗 跳過刪除以保護備份" "0"
						let i++ && continue
					fi
					Backup_folder="$MODDIR/$name1"
					[[ -d $Backup_folder ]] && rm -rf "$Backup_folder"
					# 按應用名(第一欄)整行刪除, 避免 sed 對中文/特殊字元誤刪或留半截行
					if [[ -f $txt ]]; then
						awk -v t="$name1" 'NF==0 || $1 != t' "$txt" > "$txt.tmp" 2>/dev/null && mv "$txt.tmp" "$txt"
					fi
					let i++
				done
				# 刪除後一致性檢查: 確認資料夾與 appList.txt 同步
				if [[ -f $txt ]]; then
					_dchk_f="$TMPDIR/.dchk_folders"; _dchk_l="$TMPDIR/.dchk_listed"
					for d in "$MODDIR"/*/; do
						d="${d%/}"; d="${d##*/}"
						case "$d" in wifi|Media|tools|log) continue ;; esac
						echo "$d"
					done | sort > "$_dchk_f"
					awk '!/^#|^＃/ && NF {print $1}' "$txt" | sort > "$_dchk_l"
					_d_of="$(comm -23 "$_dchk_f" "$_dchk_l")"
					_d_ol="$(comm -13 "$_dchk_f" "$_dchk_l")"
					if [[ -n $_d_of || -n $_d_ol ]]; then
						echoRgb "_______________________________________" "2"
						echoRgb "刪除後一致性檢查發現異常:" "0"
						[[ -n $_d_of ]] && { echoRgb "有資料夾但不在清單:" "0"; echo "$_d_of"; }
						[[ -n $_d_ol ]] && { echoRgb "在清單但無資料夾:" "0"; echo "$_d_ol"; }
					else
						echoRgb "刪除後一致性檢查通過: 資料夾與清單完全對應" "1"
					fi
					rm -f "$_dchk_f" "$_dchk_l" 2>/dev/null
				fi
			else
				exit 0
			fi
		fi
	fi
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
	endtime 1
	exit 0
}
# 低電量檢測 (依 low_battery_mode conf 設定決定行為; 留空則跳音量鍵詢問)
self_test() {
	local _level _charging
	_charging="$(dumpsys deviceidle get charging)"
	_level="$(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+')"
	[[ $_charging = true || -z $_level || $_level -gt 15 ]] && return
	case $low_battery_mode in
	1)
		echoRgb "電量${_level}%太低且未充電\n -為防止備份檔案或是恢復因低電量強制關機導致檔案損毀\n -請連接充電器後備份" "0" && exit 2
		;;
	2)
		echoRgb "電量${_level}%太低且未充電 (low_battery_mode=2, 已忽略繼續執行)" "0"
		;;
	*)
		echoRgb "電量${_level}%太低且未充電\n -音量上: 無視風險繼續操作 / 音量下: 退出" "0"
		get_version "繼續" "退出"
		[[ $branch != true ]] && exit 2
		;;
	esac
}
# 驗證單一檔案的 sha256 校驗碼 (對照 tools 目錄內預存的雜湊)
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
# 檢查壓縮檔完整性 (zstd -t / tar -t)
# 主選單「壓縮檔完整性檢查」呼叫
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
		echoRgb "$((i * 100 / r))% $(progress_bar $((i * 100 / r)))"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n $(cat "$error_log")" || echoRgb "恭喜~~全數校驗通過"
	rm -rf "$error_log"
}
# 產生 ASCII 進度條, 用法: progress_bar 42 → [████████░░░░░░░░░░░░]
progress_bar() {
	local pct="${1:-0}" width=20 filled i=0 bar=""
	[[ $pct -lt 0 ]] && pct=0
	[[ $pct -gt 100 ]] && pct=100
	filled=$((pct * width / 100))
	while [[ $i -lt $width ]]; do
		[[ $i -lt $filled ]] && bar="$bar█" || bar="$bar░"
		let i++
	done
	echo "[$bar]"
}
# 毫秒轉可讀時間 (15000 → 15秒, 60000 → 1分鐘, 1800000 → 30分鐘)
ms_to_readable() {
	local ms="$1" s
	[[ -z $ms || $ms = null ]] && { echo "$ms"; return; }
	# INT_MAX 附近 = 系統「永不休眠」
	[[ $ms -ge 2147483 ]] && [[ $ms -ge 2000000000 ]] && { echo "永不休眠"; return; }
	s=$((ms / 1000))
	if [[ $s -lt 60 ]]; then
		echo "${s}秒"
	elif [[ $s -lt 3600 ]]; then
		local m=$((s / 60)) rs=$((s % 60))
		[[ $rs = 0 ]] && echo "${m}分鐘" || echo "${m}分${rs}秒"
	else
		local h=$((s / 3600)) rm=$(((s % 3600) / 60))
		[[ $rm = 0 ]] && echo "${h}小時" || echo "${h}小時${rm}分鐘"
	fi
}
# 把過去時間字串 (YYYY.MM.DD HH:MM:SS) 轉成「幾天幾小時幾分前」
time_ago() {
	local ts="$1"
	[[ -z $ts || $ts = null ]] && { echo "$ts"; return; }
	local norm past now diff
	norm="$(echo "$ts" | sed 's/\./-/g')"
	past="$(date -d "$norm" +%s 2>/dev/null)"
	now="$(date +%s)"
	[[ -z $past ]] && { echo "$ts"; return; }
	diff=$((now - past))
	[[ $diff -lt 0 ]] && { echo "$ts"; return; }
	if [[ $diff -lt 60 ]]; then
		echo "${diff}秒前"
	elif [[ $diff -lt 3600 ]]; then
		echo "$((diff / 60))分鐘前"
	elif [[ $diff -lt 86400 ]]; then
		local h=$((diff / 3600)) m=$(((diff % 3600) / 60))
		[[ $m = 0 ]] && echo "${h}小時前" || echo "${h}小時${m}分前"
	else
		local d=$((diff / 86400)) h=$(((diff % 86400) / 3600)) m=$(((diff % 3600) / 60))
		echo "${d}天${h}小時${m}分前"
	fi
}
Set_screen_pause_seconds () {
	local _scr_save="$TMPDIR/.screen_timeout_orig"
	if [[ $1 = on ]]; then
		#獲取系統設置的無操作息屏秒數
		if [[ $Get_dark_screen_seconds = "" ]]; then
			Get_dark_screen_seconds="$(settings get system screen_off_timeout)"
			# 防呆: 若讀到的已是我們設定的 1800000 (代表上次沒還原成功),
			# 改用上次存檔的原值, 避免把 1800000 當成原值記下來
			if [[ $Get_dark_screen_seconds = 1800000 && -f $_scr_save ]]; then
				Get_dark_screen_seconds="$(cat "$_scr_save" 2>/dev/null)"
			fi
			# 原值存檔, 即使進程異常結束下次也能還原
			[[ $Get_dark_screen_seconds != 1800000 ]] && echo "$Get_dark_screen_seconds" > "$_scr_save"
			#設置30分鐘後息屏
			settings put system screen_off_timeout 1800000
			echo_log "設置無操作息屏時間30分鐘"
		fi
		[[ $setDisplayPowerMode = true ]] && {
		setDisplay 0
		echo_log "設置螢幕狀態false"
		}
	elif [[ $1 = off ]]; then
		# 還原: 優先用變數, 沒有則讀存檔
		[[ $Get_dark_screen_seconds = "" && -f $_scr_save ]] && Get_dark_screen_seconds="$(cat "$_scr_save" 2>/dev/null)"
		if [[ $Get_dark_screen_seconds != "" && $Get_dark_screen_seconds != 1800000 ]]; then
			settings put system screen_off_timeout "$Get_dark_screen_seconds"
			echo_log "設置無操作息屏時間為$(ms_to_readable "$Get_dark_screen_seconds")"
			input keyevent 224
			rm -f "$_scr_save"
			Get_dark_screen_seconds=""
		fi
		[[ $setDisplayPowerMode = true ]] && {
		setDisplay 2
		echo_log "設置螢幕狀態true"
		}
	fi
}
restore_permissions () {
	echoRgb "恢復權限"
	# appops reset 雙模式: 批量時只收集包名, 迴圈後集中執行 (appops 命令一次一app, 集中避免散落)
	if [[ $_batch_perm_mode = 1 ]]; then
		printf '%s\n' "$name2" >> "$TMPDIR/.batch_opsreset"
	else
		appops reset --user "$user" "$name2" &>/dev/null
	fi
	# 一次 jq 抓全部需要的欄位 (true/false/ops 權限 + installer + battery + Ssaid)
	# 取代原本多個 jq fork; 批量恢復時每個 app 省下數次 jq, 累積可觀
	local tmpf="$TMPDIR/.perm_$$"
	jq -r '
		(try (to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("true")) | .key) | join(" ")) catch "" // ""),
		(try (to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select(.value | startswith("false")) | .key) | join(" ")) catch "" // ""),
		(try (.[] | select(.permissions != null).permissions | to_entries | map(
			(.value | split(" ")) as $v |
			if (($v | length) >= 3 and $v[1] != "-1") then
				"\($v[1]) \($v[2])"
			elif (.key | startswith("EXTRA_OP_")) and (($v | length) >= 2) then
				"\($v[0]) \($v[1])"
			else
				empty
			end
		) | join(" ")) catch "" // ""),
		(try (.[] | select(.notification_settings != null).notification_settings | to_entries | map("\(.key) \(.value)") | join(" ")) catch "" // ""),
		(try (.[] | select(.battery_settings != null).battery_settings | to_entries | map(
			(.value | split(" ")) as $v |
			if (.key == "BATTERY:deviceidle_whitelist") then
				"\(.key) \(.value)"
			elif (($v | length) >= 2) then
				"\(.key) \($v[1])"
			elif (($v | length) >= 1) then
				"\(.key) \($v[0])"
			else
				empty
			end
		) | join(" ")) catch "" // ""),
		(try (.[] | select(.installer != null).installer) catch "" // ""),
		(try (.[] | select(.battery_opt != null).battery_opt) catch "" // ""),
		(try (.[] | select(.Ssaid != null).Ssaid) catch "" // "")
	' "$app_details" 2>/dev/null > "$tmpf"
	local _installer _battery
	exec 3< "$tmpf"
	read -r true_permissions <&3
	read -r false_permissions <&3
	read -r Set_Ops_permissions <&3
	read -r Set_Notify_settings <&3
	read -r Set_Battery_settings <&3
	read -r _installer <&3
	read -r _battery <&3
	read -r _rp_ssaid <&3
	exec 3<&-
	rm -f "$tmpf"
	# 雙模式: _batch_perm_mode=1 只收集到暫存檔(批量), 否則立即調 dex(單獨恢復後路)
	# 目前都經批量迴圈進來故走收集; else 分支保留供日後直接單獨恢復用
	[[ $true_permissions != "" ]] && {
		if [[ $_batch_perm_mode = 1 ]]; then
			printf '[%s %s] ' "$name2" "$true_permissions" >> "$TMPDIR/.batch_grant"
		else
			Set_true_Permissions "[$name2 $true_permissions]"
			[[ $? != 0 ]] && echo_log "設置允許權限"
		fi
	}
	[[ $false_permissions != "" ]] && {
		if [[ $_batch_perm_mode = 1 ]]; then
			printf '[%s %s] ' "$name2" "$false_permissions" >> "$TMPDIR/.batch_revoke"
		else
			Set_false_Permissions "[$name2 $false_permissions]"
			[[ $? != 0 ]] && echo_log "設置拒絕權限"
		fi
	}
	[[ $Set_Ops_permissions != "" ]] && {
		if [[ $_batch_perm_mode = 1 ]]; then
			printf '[%s %s] ' "$name2" "$Set_Ops_permissions" >> "$TMPDIR/.batch_ops"
		else
			Set_Ops "[$name2 $Set_Ops_permissions]"
			[[ $? != 0 ]] && echo_log "設置ops權限"
		fi
	}
	[[ $Set_Notify_settings != "" ]] && {
		if [[ $_batch_perm_mode = 1 ]]; then
			printf '[%s %s] ' "$name2" "$Set_Notify_settings" >> "$TMPDIR/.batch_notify"
		else
			Set_Notifications "[$name2 $Set_Notify_settings]"
			[[ $? != 0 ]] && echo_log "設置通知設定"
		fi
	}
	[[ $Set_Battery_settings != "" ]] && {
		if [[ $_batch_perm_mode = 1 ]]; then
			printf '[%s %s] ' "$name2" "$Set_Battery_settings" >> "$TMPDIR/.batch_battery"
		else
			Set_Battery_Settings "[$name2 $Set_Battery_settings]"
			[[ $? != 0 ]] && echo_log "設置電池/背景設定"
		fi
	}
	# 恢復 installer (安裝來源) 與 battery_opt (後台運行 appops mode) — 已於上方一次 jq 取得
	[[ -n $_installer ]] && {
		pm set-installer "$name2" "$_installer" &>/dev/null
		[[ $? = 0 ]] && echoRgb "恢復安裝來源:$_installer" "2"
	}
	# 舊版 battery_opt 相容: 只有在沒有 battery_settings 時才套用, 避免覆蓋 dex v12 的完整設定
	if [[ -z $Set_Battery_settings ]]; then
		case $_battery in
		allow|ignore|deny|default)
			appops set "$name2" RUN_ANY_IN_BACKGROUND "$_battery" &>/dev/null
			# allow(無限制)時一併加入 doze 白名單豁免
			[[ $_battery = allow ]] && dumpsys deviceidle whitelist "+$name2" &>/dev/null
			echoRgb "恢復後台運行設定:$_battery" "2"
			;;
		esac
	fi
}
# 批量沖刷: 把累積的 grant/revoke/ops 各一次 app_process 設置 (取代逐 app 各啟動 JVM)
# 批量恢復 N 個 app 的權限 JVM 從 3N 次降到最多 3 次
flush_batch_permissions() {
	[[ $_batch_perm_mode != 1 ]] && return
	local _g="$TMPDIR/.batch_grant" _r="$TMPDIR/.batch_revoke" _o="$TMPDIR/.batch_ops" _n="$TMPDIR/.batch_notify" _b="$TMPDIR/.batch_battery" _rs="$TMPDIR/.batch_opsreset" _rspkg
	# 先批量 appops reset (必須在設權限前, 把各 app ops 清到預設再設)
	if [[ -s $_rs ]]; then
		echoRgb "重置應用ops中..." "3"
		while read -r _rspkg; do
			[[ -z $_rspkg ]] && continue
			appops reset --user "$user" "$_rspkg" &>/dev/null
		done < "$_rs"
		rm -f "$_rs"
	fi
	# 有任一暫存檔有內容才提示 (避免無權限可設時也印)
	[[ -s $_g || -s $_r || -s $_o || -s $_n || -s $_b ]] && echoRgb "批量設置應用權限/通知/電池設定中,請稍候..." "2"
	if [[ -s $_g ]]; then
		echoRgb "授予權限中..." "3"
		[[ $_dex_debug = 1 ]] && echo "FLUSH-grant" >> "$TMPDIR/.dex_call_log"
		xargs app_process /system/bin com.xayah.dex.HiddenApiUtil grantRuntimePermission "$USER_ID" < "$_g" >/dev/null 2>&1
		[[ $? != 0 ]] && echo_log "批量設置允許權限"
	fi
	if [[ -s $_r ]]; then
		echoRgb "撤銷權限中..." "3"
		[[ $_dex_debug = 1 ]] && echo "FLUSH-revoke" >> "$TMPDIR/.dex_call_log"
		xargs app_process /system/bin com.xayah.dex.HiddenApiUtil revokeRuntimePermission "$USER_ID" < "$_r" >/dev/null 2>&1
		[[ $? != 0 ]] && echo_log "批量設置拒絕權限"
	fi
	if [[ -s $_o ]]; then
		echoRgb "設置ops模式中..." "3"
		[[ $_dex_debug = 1 ]] && echo "FLUSH-setOps" >> "$TMPDIR/.dex_call_log"
		xargs app_process /system/bin com.xayah.dex.HiddenApiUtil setOpsMode "$USER_ID" < "$_o" >/dev/null 2>&1
		[[ $? != 0 ]] && echo_log "批量設置ops權限"
	fi
	if [[ -s $_n ]]; then
		echoRgb "設置通知設定中..." "3"
		[[ $_dex_debug = 1 ]] && echo "FLUSH-setNotifications" >> "$TMPDIR/.dex_call_log"
		xargs app_process /system/bin com.xayah.dex.HiddenApiUtil setNotificationSettings "$USER_ID" < "$_n" >/dev/null 2>&1
		[[ $? != 0 ]] && echo_log "批量設置通知設定"
	fi
	if [[ -s $_b ]]; then
		echoRgb "設置電池/背景設定中..." "3"
		[[ $_dex_debug = 1 ]] && echo "FLUSH-setBattery" >> "$TMPDIR/.dex_call_log"
		xargs app_process /system/bin com.xayah.dex.HiddenApiUtil setBatterySettings "$USER_ID" < "$_b" >/dev/null 2>&1
		[[ $? != 0 ]] && echo_log "批量設置電池/背景設定"
	fi
	[[ -s $_g || -s $_r || -s $_o || -s $_n || -s $_b ]] && echoRgb "權限/通知/電池設定完成" "1"
	rm -f "$TMPDIR/.pkg_notify" "$TMPDIR/.pkg_battery" 2>/dev/null
	# ====== 恢復後權限驗證 (只驗 grant/revoke 開關, 不驗 ops mode) ======
	# flush 後一次 getRuntimePermissions 批量讀回實際權限, 跟應設狀態比對
	if [[ $_perm_verify != 0 && ( -s $_g || -s $_r ) ]]; then
		echoRgb "驗證權限恢復結果..." "2"
		# 從 batch 檔解析出 期望狀態: 格式 pkg<TAB>perm<TAB>true/false
		local _expect="$TMPDIR/.perm_expect" _actual="$TMPDIR/.perm_actual"
		: > "$_expect"
		# grant 檔 → 期望 true; revoke 檔 → 期望 false. 格式 [pkg perm perm] [pkg perm]
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<2)next
			for(i=2;i<=n;i++) print a[1]"\t"a[i]"\ttrue"
		}' "$_g" >> "$_expect" 2>/dev/null
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<2)next
			for(i=2;i<=n;i++) print a[1]"\t"a[i]"\tfalse"
		}' "$_r" >> "$_expect" 2>/dev/null
		# 取所有涉及的包名, 一次批量讀回實際權限 (1 次 dex)
		local _vpkgs
		_vpkgs="$(awk -F'\t' '{print $1}' "$_expect" | sort -u | paste -sd' ' -)"
		get_Permissions $_vpkgs 2>/dev/null | awk '{print $1"\t"$2"\t"$3}' > "$_actual"
		# 比對: 期望 vs 實際, 列出不一致
		local _mismatch
		_mismatch="$(awk -F'\t' '
			NR==FNR { act[$1"\t"$2]=$3; next }
			{
				key=$1"\t"$2
				if (key in act) {
					if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key]
				} else {
					print "  ? "$1"  "$2"  應="$3" 實際=未讀到"
				}
			}' "$_actual" "$_expect")"
		if [[ -z $_mismatch ]]; then
			echoRgb "✅ Runtime 權限驗證通過" "1"
		else
			echoRgb "⚠️ 以下 Runtime 權限與備份記錄不一致:" "0"
			echo "$_mismatch"
		fi
		rm -f "$_expect" "$_actual"
	fi
	# ====== 恢復後 AppOps mode 驗證 ======
	# 驗證 setOpsMode 實際 mode 是否與備份值一致（op + mode）
	if [[ $_perm_verify != 0 && -s $_o ]]; then
		echoRgb "驗證 AppOps mode 恢復結果..." "2"
		local _ops_expect="$TMPDIR/.ops_expect" _ops_actual="$TMPDIR/.ops_actual" _ops_pkgs _ops_mismatch
		: > "$_ops_expect"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) print a[1]"\t"a[i]"\t"a[i+1]
		}' "$_o" >> "$_ops_expect" 2>/dev/null
		_ops_pkgs="$(awk -F'\t' '{print $1}' "$_ops_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_ops_pkgs ]]; then
			get_Permissions $_ops_pkgs 2>/dev/null | awk 'NF>=5 {print $1"\t"$4"\t"$5}' > "$_ops_actual"
			_ops_mismatch="$(awk -F'\t' '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  op="$2"  應mode="$3" 實際mode="act[key]
					} else {
						print "  ? "$1"  op="$2"  應mode="$3" 實際=未讀到"
					}
				}' "$_ops_actual" "$_ops_expect")"
			if [[ -z $_ops_mismatch ]]; then
				echoRgb "✅ AppOps mode 驗證通過" "1"
			else
				echoRgb "⚠️ 以下 AppOps mode 與備份記錄不一致:" "0"
				echo "$_ops_mismatch"
			fi
		fi
		rm -f "$_ops_expect" "$_ops_actual"
	fi
	# ====== 恢復後通知設定驗證 ======
	# 驗證 notification_settings 的 key/value 是否與備份值一致
	# 注意：部分 app 的 NotificationChannel 只有在 app 第一次啟動/建立通知後才會出現。
	# 因此 NOTIFY_CHANNEL/NOTIFY_GROUP「未讀到」不直接當成恢復錯誤，而是列為「待建立分類」。
	if [[ $_perm_verify != 0 && -s $_n ]]; then
		echoRgb "驗證通知設定恢復結果..." "2"
		local _notify_expect="$TMPDIR/.notify_expect" _notify_actual="$TMPDIR/.notify_actual" _notify_pkgs
		local _notify_mismatch_file="$TMPDIR/.notify_mismatch" _notify_pending_file="$TMPDIR/.notify_pending"
		local _notify_mismatch _notify_pending
		: > "$_notify_expect"
		: > "$_notify_mismatch_file"
		: > "$_notify_pending_file"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) print a[1]"\t"a[i]"\t"a[i+1]
		}' "$_n" >> "$_notify_expect" 2>/dev/null
		_notify_pkgs="$(awk -F'\t' '{print $1}' "$_notify_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_notify_pkgs ]]; then
			get_Notifications $_notify_pkgs 2>/dev/null | awk 'NF>=3 {
				val=$3; for(i=4;i<=NF;i++) val=val" "$i
				print $1"\t"$2"\t"val
			}' > "$_notify_actual"
			awk -F'\t' -v mis="$_notify_mismatch_file" -v pend="$_notify_pending_file" '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key] >> mis
					} else if ($2 ~ /^NOTIFY_CHANNEL:/ || $2 ~ /^NOTIFY_GROUP:/) {
						# 通知分類/群組尚未建立：同一個 channel/group 只列一次，避免刷滿螢幕。
						n=split($2, parts, ":")
						if (n >= 2) print "  ? "$1"  "parts[1]":"parts[2]"  尚未建立/未讀到，啟動應用建立通知分類後再驗證" >> pend
						else print "  ? "$1"  "$2"  尚未建立/未讀到，啟動應用建立通知分類後再驗證" >> pend
					} else {
						# app-level 設定未讀到才是真正不一致
						print "  ✗ "$1"  "$2"  應="$3" 實際=未讀到" >> mis
					}
				}' "$_notify_actual" "$_notify_expect"
			_notify_mismatch="$(cat "$_notify_mismatch_file" 2>/dev/null)"
			_notify_pending="$(sort -u "$_notify_pending_file" 2>/dev/null)"
			if [[ -z $_notify_mismatch && -z $_notify_pending ]]; then
				echoRgb "✅ 通知設定驗證通過" "1"
			else
				if [[ -n $_notify_mismatch ]]; then
					echoRgb "⚠️ 以下通知設定與備份記錄不一致:" "0"
					echo "$_notify_mismatch"
				fi
				if [[ -n $_notify_pending ]]; then
					local _pending_cnt
		            _pending_cnt="$(awk -F'\t' '{k=$1"\t"$2} !seen[k]++ {c++} END{print c+0}' "$TMPDIR/.notify_pending" 2>/dev/null)"
		            echoRgb "⚠️ 有 ${_pending_cnt} 個通知分類/群組尚未建立，已略過逐條顯示；啟動 app 建立 NotificationChannel 後可再重跑通知恢復/驗證" "2"
		            echoRgb "✅ app-level 通知設定與已存在的通知分類驗證通過；缺失分類不判定為恢復錯誤" "1"
				fi
			fi
		fi
		rm -f "$_notify_expect" "$_notify_actual" "$_notify_mismatch_file" "$_notify_pending_file"
	fi

	# ====== 恢復後電池/背景設定驗證 ======
	# RUN_* 實際輸出是 pkg key op mode modeName，驗證 mode；deviceidle_whitelist 驗證 true/false
	if [[ $_perm_verify != 0 && -s $_b ]]; then
		echoRgb "驗證電池/背景設定恢復結果..." "2"
		local _battery_expect="$TMPDIR/.battery_expect" _battery_actual="$TMPDIR/.battery_actual" _battery_pkgs _battery_mismatch
		: > "$_battery_expect"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) {
				key=a[i]; val=a[i+1]
				if (key=="BATTERY:RUN_IN_BACKGROUND" || key=="BATTERY:RUN_ANY_IN_BACKGROUND") {
					if (val=="allow" || val=="allowed" || val=="true") val=0
					else if (val=="ignore" || val=="ignored" || val=="false") val=1
					else if (val=="deny" || val=="denied" || val=="errored") val=2
					else if (val=="default") val=3
					else if (val=="foreground") val=4
				}
				print a[1]"\t"key"\t"val
			}
		}' "$_b" >> "$_battery_expect" 2>/dev/null
		_battery_pkgs="$(awk -F'\t' '{print $1}' "$_battery_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_battery_pkgs ]]; then
			get_Battery_Settings $_battery_pkgs 2>/dev/null | awk 'NF>=3 {
				if ($2=="BATTERY:deviceidle_whitelist") {
					print $1"\t"$2"\t"$3
				} else if ($2=="BATTERY:RUN_IN_BACKGROUND" || $2=="BATTERY:RUN_ANY_IN_BACKGROUND") {
					print $1"\t"$2"\t"$4
				}
			}' > "$_battery_actual"
			_battery_mismatch="$(awk -F'\t' '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key]
					} else {
						print "  ? "$1"  "$2"  應="$3" 實際=未讀到"
					}
				}' "$_battery_actual" "$_battery_expect")"
			if [[ -z $_battery_mismatch ]]; then
				echoRgb "✅ 電池/背景設定驗證通過" "1"
			else
				echoRgb "⚠️ 以下電池/背景設定與備份記錄不一致:" "0"
				echo "$_battery_mismatch"
			fi
		fi
		rm -f "$_battery_expect" "$_battery_actual"
	fi
	rm -f "$_g" "$_r" "$_o" "$_n" "$_b" "$TMPDIR/.perm_expect" "$TMPDIR/.perm_actual" "$TMPDIR/.ops_expect" "$TMPDIR/.ops_actual" "$TMPDIR/.notify_expect" "$TMPDIR/.notify_actual" "$TMPDIR/.notify_mismatch" "$TMPDIR/.notify_pending" "$TMPDIR/.battery_expect" "$TMPDIR/.battery_actual" 2>/dev/null
}
# 取得當前正在後台運行的所有 app 列表
# 配合「後台應用忽略」設定, 跳過正在運行的 app 不備份
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
# ======================================================
# backup() 主函數
# ======================================================
# 主備份函數 - 對 appList.txt 內所有 app 執行完整備份
# 流程: 讀清單 → 逐個 app → 備份 apk + data + user_de + obb → 備份 SSAID/權限
# 結尾備份 wifi、生成 start.sh、設置 REMOTE_TRIGGER=1 觸發遠端上傳
backup() {
	self_test
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	# 流式上傳路徑快取: 在 Compression_method 還未被 Backup_data() 暫時污染前固定一次
	_BACKUP_DIRNAME_CACHED="$(get_backup_dirname)"
	prepare_pkg_uid_map
	prepare_pkg_ver_map
	load_kv_map "$TMPDIR/.pkg_uid" _pu
	load_kv_map "$TMPDIR/.pkg_ver" _pv
	: > "$TMPDIR/.backup_done"
	: > "$TMPDIR/.update_apks"
	: > "$TMPDIR/.add_apks"
	: > "$TMPDIR/.ssaid_apks"
	: > "$TMPDIR/.changed_apps"
	# 初始化備份變更標記
	backup_has_changes=0
	#校驗選填是否正確
	[[ $Backup_Mode != "" ]] && isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx" || {
	echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
	get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
	}
	if [[ $Backup_Mode = true ]]; then
		if [[ -n $(awk '!/[#＃]/ && NF' <<< "$blacklist") ]]; then
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
	}
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
	show_conf backup
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
	# 用暫存檔取代 here-string (mksh 不支援 <<<)
	local _upd_tmp="$TMPDIR/.update_check_$$"
	grep -Ev '^[#＃!]' "$txt" | awk '{print $1 ":" $2}' > "$_upd_tmp"
	# 預掃 pkg→version map (若還沒掃過), 取代每 app fork pm
	[[ ! -f $TMPDIR/.pkg_ver ]] && prepare_pkg_ver_map
	while read -r apk; do
		Backup_folder="$Backup/$(echo "$apk" | cut -d':' -f1)"
		app_details="$Backup_folder/app_details.json"
		if [[ -d $Backup_folder ]]; then
			# 讀本地同步副本 (流式模式上傳成功後 cp 到本地, 記錄上次成功備份的版本)
			# 與實機比對才有意義; 遠端快取是給 apk 跳過比對用的, 職責不同
			apk_version="$(jq -r 'try (.[] | select(.apk_version != null).apk_version) catch ""' "$app_details" 2>/dev/null | head -n 1 | tr -d ' \t\r\n')"
			# 從預掃 map 查 versionCode (取代每 app fork pm)
			local _pkg
			_pkg="$(echo "$apk" | cut -d':' -f2)"
			apk_version2="$(awk -v pkg="$_pkg" -F'\t' '$1 == pkg {print $2; exit}' "$TMPDIR/.pkg_ver" 2>/dev/null)"
			# debug: 比對版本失敗時印出來
			if [[ $apk_version != $apk_version2 ]]; then
				echoRgb "$(echo "$apk" | cut -d':' -f1) 版本變化: $apk_version → $apk_version2" "3"
				[[ $Tmplist2 = "" ]] && Tmplist2="${apk/:/ }" || Tmplist2="$Tmplist2\n${apk/:/ }"
				# 記錄包名: 本輪強制重備 apk (遠端 json 可能被失敗輪汙染成新版本號而 apk 仍是舊檔)
				echo "$_pkg" >> "$TMPDIR/.listver_changed"
			fi
		fi
	done < "$_upd_tmp"
	rm -f "$_upd_tmp"
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
	filesize="$(calc_dir_size "$Backup")"
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
		# 單獨備份模式: 只預掃這一個 app 的權限
		local _single_pkg
		_single_pkg="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json" 2>/dev/null)"
		local _perms_tmp="$TMPDIR/.pkg_perms" _notify_tmp="$TMPDIR/.pkg_notify"
		: > "$_perms_tmp"; : > "$_notify_tmp"
		if [[ -n $_single_pkg ]]; then
			local _raw _json _nraw _njson
			_raw="$(get_Permissions "$_single_pkg" 2>/dev/null)"
			if [[ -n $_raw ]]; then
				_json="$(echo "$_raw" | jq -nRc '[inputs | select(. != "null" and length>0) | split(" ") | {(.[1]): (.[2:] | join(" "))}] | if length > 0 then add else empty end' 2>/dev/null)"
				[[ -n $_json ]] && printf '%s	%s
' "$_single_pkg" "$_json" >> "$_perms_tmp"
			fi
			_nraw="$(get_Notifications "$_single_pkg" 2>/dev/null)"
			if [[ -n $_nraw ]]; then
				_njson="$(echo "$_nraw" | jq -nRc '[inputs | select(. != "null" and length>0) | split(" ") | {(.[1]): (.[2:] | join(" "))}] | if length > 0 then add else empty end' 2>/dev/null)"
				[[ -n $_njson ]] && printf '%s	%s
' "$_single_pkg" "$_njson" >> "$_notify_tmp"
			fi
		fi
		prepare_pkg_installer_map
		prepare_battery_settings_map "$_single_pkg"
		prepare_battery_whitelist "$_single_pkg"
		prepare_remote_filelist
		prepare_remote_scripts_map
		prepare_remote_json_map
		load_kv_map "$TMPDIR/.pkg_perms" _pp
		load_kv_map "$TMPDIR/.pkg_notify" _pn
		load_kv_map "$TMPDIR/.pkg_installer" _pi
		load_kv_map "$TMPDIR/.battery_wl" _bw
		load_kv_map "$TMPDIR/.pkg_battery" _bs
	else
		ssaid_info="$(get_ssaid "$(echo "$txt" | awk '{printf "%s ", $2}')")"
		prepare_permissions_map
		prepare_notifications_map
		prepare_pkg_installer_map
		prepare_battery_settings_map
		prepare_battery_whitelist
		prepare_dir_size_map
		load_dir_size_map
		prepare_remote_filelist
		prepare_remote_scripts_map
		prepare_remote_json_map
		load_kv_map "$TMPDIR/.pkg_perms" _pp
		load_kv_map "$TMPDIR/.pkg_notify" _pn
		load_kv_map "$TMPDIR/.pkg_installer" _pi
		load_kv_map "$TMPDIR/.battery_wl" _bw
		load_kv_map "$TMPDIR/.pkg_battery" _bs
	fi
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	notification "101" "開始備份"
	# 保存本次備份實際使用的清單,供遠端上傳用 (純變數,不寫檔)
	# 子目錄 backup.sh (app_details.json 存在於 0%/*) 只備份單一 app,
	# 上傳時也只該上傳這一個 app 的目錄
	if [[ -n $remote_type ]]; then
		if [[ -f ${0%/*}/app_details.json ]]; then
			# 單獨備份: REMOTE_APPLIST 只設這個 app
			# ${0%/*} 是子目錄路徑, 末段就是 app 名 (例 Chrome)
			_app_dirname="${0%/*}"
			REMOTE_APPLIST="${_app_dirname##*/}"
			unset _app_dirname
		elif [[ -n $txt ]]; then
			REMOTE_APPLIST="$txt"
		fi
	fi
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ ! -f ${0%/*}/app_details.json ]]; then
			# 一次 sed 抓行, 用 parameter expansion 拆欄位 (省 3 fork)
			_line="$(echo "$txt" | sed -n "${i}p")"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
		else
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "${0%/*}/app_details.json" | head -n 1)"
			PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")"
			name1="$ChineseName"
			name2="$PackageName"
		fi
		[[ $name2 = "" || $name1 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
		apk_path="$(pm path --user "$user" "$name2" 2>/dev/null | cut -f2 -d ':')"
		apk_path2="${apk_path%%$'\n'*}"
		apk_path2="${apk_path2%/*}"
		if [[ -d $apk_path2 ]]; then
			echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
			echoRgb "備份 $name1" "2"
			notification "101" "備份第$i/$r個應用 剩下$((r - i))個
備份 $name1"
			unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version apk_version2  zsize zmediapath Size data_path Ssaid ssaid
			nobackup="false"
			Background_application_list
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略備份" "0" && nobackup="true"
			if [[ $Backup_Mode = true ]]; then
				if [[ $name1 = !* || $name1 = ！* ]]; then
					name1="${name1//!/}"
					name1="${name1//！/}"
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
			# 流式模式: 設遠端目標目錄 (鏡像 $name1), 遠端目錄由 _stream_upload 自動建
			# 用 TMPDIR 暫存區取代本機 $Backup (不碰用戶既有本地備份, 結束無需大清理)
			if [[ $remote_stream = 1 && -n $remote_type ]]; then
				_STREAM_DEST="$name1"
				Backup_folder="$TMPDIR/.stream_stage/$name1"
				app_details="$Backup_folder/app_details.json"
				# 每 app 先清空 staging (防上輪殘留), 再無條件以遠端 json 快取為種:
				# 1. 權限/SSAID/installer/版本比對有舊值參照, 無變化正確跳過
				# 2. 本輪只更新部分欄位時, 其餘欄位 (如版本) 不會在上傳時被覆蓋丟失
				rm -rf "$Backup_folder" 2>/dev/null
				mkdir -p "$Backup_folder" 2>/dev/null
				[[ -s $TMPDIR/.remote_json/$name1.json ]] && \
				cp "$TMPDIR/.remote_json/$name1.json" "$app_details" 2>/dev/null
				# 種子可能是舊版/從未經過新增分支寫入的 json, 缺 PackageName 會導致流式恢復失敗;
				# 在此補上 (不影響其他欄位, 用 jq 確認該 key 存在才寫, 避免空 json 結構錯誤)
				if [[ -s $app_details ]] && [[ "$(jq -r ".[\"$name1\"].PackageName // empty" "$app_details" 2>/dev/null)" = "" ]]; then
					jq_inplace "$app_details" --arg software "$name1" --arg pkg "$name2" \
						'if .[$software] then .[$software].PackageName = $pkg else . end' 2>/dev/null
				fi
			fi
			# 一次讀取 app_details.json 所有欄位 (APK_VER / SSAID_OLD / PERMS_OLD / PKG_NAME / BACKUP_TIME / SIZE_*)
			# 取代後續每個函數內各自 fork jq
			app_details_read "$app_details"
			if [[ -f $app_details ]]; then
				PackageName="$PKG_NAME"
				[[ $PackageName != $name2 ]] && jq_inplace "$app_details" --arg name2 "$name2" 'walk(if type == "object" and .PackageName then .PackageName = $name2 else . end)'
				echoRgb "上次備份時間$(time_ago "$BACKUP_TIME")"
			fi
			[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
			starttime2="$(date -u "+%s")"
			[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			# 算 apk_path 有幾行 (省 echo|wc -l)
			apk_number=1
			case $apk_path in
			*$'\n'*) apk_number=$(echo "$apk_path" | wc -l) ;;
			esac
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
								#備份media數據 (部分app如FB Messenger使用 Android/media/<pkg> 存放媒體檔)
								Backup_data "media"
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
			# 入口腳本: 非流式寫本地; 流式查預掃表 (.remote_scripts) 缺才傳 (有就不傳, 省流量)
			if [[ $remote_stream = 1 ]]; then
				if ! awk -v a="$name1" '$0==a{f=1} END{exit !f}' "$TMPDIR/.remote_scripts" 2>/dev/null; then
					mkdir -p "$Backup_folder" 2>/dev/null
					touch_shell "3" "$Backup_folder/recover.sh"
					touch_shell "1" "$Backup_folder/backup.sh"
					touch_shell "5" "$Backup_folder/upload.sh"
					_stream_upload "$name1/recover.sh" < "$Backup_folder/recover.sh" 2>/dev/null
					_stream_upload "$name1/backup.sh" < "$Backup_folder/backup.sh" 2>/dev/null
					_stream_upload "$name1/upload.sh" < "$Backup_folder/upload.sh" 2>/dev/null
				fi
			else
				[[ ! -f $Backup_folder/recover.sh ]] && touch_shell "3" "$Backup_folder/recover.sh"
				[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "1" "$Backup_folder/backup.sh"
				[[ ! -f $Backup_folder/upload.sh ]] && touch_shell "5" "$Backup_folder/upload.sh"
			fi
			fi
			# 備份全部跳過時清理空的 app_details.json 殘留
			[[ -f $app_details ]] && [[ "$(jq 'length' "$app_details" 2>/dev/null)" = "0" ]] && rm -f "$app_details"
			endtime 2 "$name1 備份" "3"
			# 流式: 數據 tar 已在壓縮時直接流到遠端, 此處補傳 app_details.json
			# 只在本輪該 app 有變更 (.changed_apps) 時上傳, 全跳過則遠端 json 本就最新
			# 該 app 本輪有任一流式上傳失敗 → 不傳 json (缺 json 下輪必整個重備, 避免壞數據被增量跳過殘留)
			if awk -v n="$name1" '$0==n{f=1} END{exit !f}' "$TMPDIR/.stream_failed" 2>/dev/null; then
				echoRgb "$name1 本輪有上傳失敗, 不更新遠端 json (下次將重新備份此應用)" "0"
			elif [[ $remote_stream = 1 && -n $remote_type && -f $app_details ]] && \
				awk -v n="$name1" '$0==n{f=1} END{exit !f}' "$TMPDIR/.changed_apps" 2>/dev/null; then
				# 防線: staging 未以快取為種 (此 app 無 .remote_json 快取) 時,
				# 先抓遠端現有 json 合併, 避免部分欄位覆蓋掉遠端完整 json (版本等丟失)
				if [[ ! -s $TMPDIR/.remote_json/$name1.json ]]; then
					_mergetmp="$TMPDIR/.merge_remote_$$"
					if remote_download_single_file "$name1/app_details.json" "$_mergetmp" 2>/dev/null && \
						[[ "$(head -c 1 "$_mergetmp" 2>/dev/null)" = "{" ]]; then
						jq -s '.[0] * .[1]' "$_mergetmp" "$app_details" > "$_mergetmp.out" 2>/dev/null && \
						[[ -s $_mergetmp.out ]] && mv "$_mergetmp.out" "$app_details"
					fi
					rm -f "$_mergetmp" "$_mergetmp.out" 2>/dev/null
				fi
				if _stream_upload "$name1/app_details.json" < "$app_details"; then
					echoRgb "app_details.json 已上傳遠端" "1"
				else
					echoRgb "app_details.json 上傳失敗" "0"
				fi
			fi
			# 邊備份邊上傳：每個應用備份完立即上傳遠端，然後刪除本機檔案節省空間
			# 流式模式不走此路徑 (數據已流式傳走, 無本機 tar 可上傳, json 上面已傳)
			if [[ $remote_stream = 1 ]]; then
				:
			elif [[ $remote_upload_per_app = 1 && -n $remote_type ]]; then
				# 有備份變更 → 上傳
				if awk -v n="$name1" 'BEGIN{f=1} $0==n{f=0} END{exit f}' "$TMPDIR/.changed_apps" 2>/dev/null; then
					per_app_upload_and_cleanup "$name1"
				else
					# 本地無變更，但遠端可能沒有備份 → 檢查遠端 app_details.json
					_remote_has_backup=0
					_remote_check_file="$TMPDIR/.remote_check_$$"
					if remote_download_single_file "${name1}/app_details.json" "$_remote_check_file" 2>/dev/null; then
						[[ -s $_remote_check_file ]] && _remote_has_backup=1
					fi
					rm -f "$_remote_check_file"
					if [[ $_remote_has_backup = 0 ]]; then
						echoRgb "遠端無備份，上傳到遠端" "2"
						per_app_upload_and_cleanup "$name1"
					else
						echoRgb "無備份變更，跳過上傳" "2"
					fi
				fi
			fi
			lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
			echoRgb "完成$((i * 100 / r))% $(progress_bar $((i * 100 / r)))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "3"
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
			update_apk2="$(cat "$TMPDIR/.update_apks" 2>/dev/null)"
			add_app2="$(cat "$TMPDIR/.add_apks" 2>/dev/null)"
			SSAID_apk2="$(cat "$TMPDIR/.ssaid_apks" 2>/dev/null)"
			update_apk2="${update_apk2:=" -暫無更新"}"
			add_app2="${add_app2:=" -暫無更新"}"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2\n -包含SSAID的應用\n$SSAID_apk2" "3"
			notification "101" "app備份完成 $(endtime 1 "應用備份" "3")"
			# 把 backup_done 暫存檔的新項目合併進 txt_path2 (保留舊內容, 用 sort -u 去重)
			if [[ -s $TMPDIR/.backup_done ]]; then
				if [[ -f $txt_path2 ]]; then
					cat "$txt_path2" "$TMPDIR/.backup_done" | sort -u | sed '/^$/d' > "$txt_path2.new"
					mv "$txt_path2.new" "$txt_path2"
				else
					sort -u "$TMPDIR/.backup_done" | sed '/^$/d' > "$txt_path2"
				fi
			fi
			# 清掉備份用的暫存檔
			rm -f "$TMPDIR/.backup_done" "$TMPDIR/.update_apks" "$TMPDIR/.add_apks" "$TMPDIR/.ssaid_apks" 2>/dev/null
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(awk '!/[#＃]/ && NF{count++} END{print count}' <<< "$Custom_path")"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					notification "102" "Media備份開始"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					app_details="$Backup_folder/app_details.json"
					if [[ $remote_stream = 1 && -n $remote_type ]]; then
						_STREAM_DEST="Media"; Backup_folder="$TMPDIR/.stream_stage/Media"; app_details="$Backup_folder/app_details.json"; mkdir -p "$Backup_folder" 2>/dev/null
					fi
					mediatxt="$Backup/mediaList.txt"
					# 延遲建立: 只有實際備份了至少一個資料夾才建立 (避免空殼)
					_media_created=0
					_ensure_media_dirs() {
						[[ $_media_created = 1 ]] && return
						[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
						[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
						[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
						[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
						_media_created=1
					}
					echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' > "$TMPDIR/.media_custom_paths"
					while read -r; do
						echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
						notification "102" "備份第$A/$B個資料夾 剩下$((B - A))個"
						starttime2="$(date -u "+%s")"
						if [[ ${REPLY##*/} = adb ]]; then
							if [[ $ksu != ksu ]]; then
								echoRgb "Magisk adb"
								_ensure_media_dirs
								Backup_data "${REPLY##*/}" "$REPLY"
							else
								echoRgb "KernelSU adb不支持備份" "0"
								Set_back_0
							fi
						else
							_ensure_media_dirs
							Backup_data "${REPLY##*/}" "$REPLY"
						fi
						endtime 2 "${REPLY##*/}備份" "1"
						echoRgb "完成$((A * 100 / B))% $(progress_bar $((A * 100 / B)))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "2"
						rgb_d="$rgb_a"
						rgb_a=188
						echoRgb "_________________$(endtime 1 "已經")___________________"
						rgb_a="$rgb_d" && let A++
					done < "$TMPDIR/.media_custom_paths"
					rm -f "$TMPDIR/.media_custom_paths"
					# 收尾: 無實際備份檔則清空殼
					# 流式模式: .tar 壓縮完即上傳, 本機不會留 .tar 檔 (設計如此), 改用 _media_created 旗標判斷
					if [[ $remote_stream = 1 && -n $remote_type ]]; then
						if [[ $_media_created != 1 ]]; then
							echoRgb "Media 無實際備份內容, 清除 mediaList.txt" "0"
							rm -rf "$Backup_folder" 2>/dev/null
							[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>/dev/null) = 0 ]] && rm -f "$mediatxt"
						else
							[[ $remote_stream != 1 ]] && echoRgb "目錄↓↓↓\n -$Backup_folder"
							REMOTE_UPLOAD_MEDIA=1
							# 只有 app_details 真的有實際內容(非初始空殼)才上傳, 避免「全部資料夾無變化跳過」
							# 時, 本地空殼覆蓋掉遠端原本正確的版本
							if [[ -f $app_details ]] && jq -e 'length > 0' "$app_details" >/dev/null 2>&1; then
								_stream_upload "Media/app_details.json" < "$app_details"
								[[ -f $mediatxt ]] && _stream_upload "mediaList.txt" < "$mediatxt"
								echoRgb "Media 清單已上傳遠端" "1"
							else
								echoRgb "Media 本輪全部資料夾無變化, 跳過json上傳(避免覆蓋遠端正確版本)" "2"
							fi
						fi
					elif [[ -d $Backup_folder ]] && ! find "$Backup_folder" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | grep -q .; then
						echoRgb "Media 無實際備份內容, 清除空目錄與 mediaList.txt" "0"
						rm -rf "$Backup_folder"
						[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>/dev/null) = 0 ]] && rm -f "$mediatxt"
					else
						echoRgb "目錄↓↓↓\n -$Backup_folder"
						[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
					fi
					notification "102" "Media備份完成 $(endtime 1 "自定義備份")"
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		let i++ en++ nskg++
	done
	# 流式模式: wifi 也存 TMPDIR 暫存區 (不碰本地 $Backup)
	if [[ $remote_stream = 1 && -n $remote_type ]]; then
		backup_wifi "$TMPDIR/.stream_stage/wifi"
	else
		backup_wifi "$Backup/wifi"
	fi
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user" >/dev/null 2>&1
	# 流式模式: 本地無備份檔 (數據在遠端), 跳過本地大小統計; 遠端統計在 remote_cleanup 結尾顯示
	[[ $remote_stream != 1 ]] && Calculate_size "$Backup"
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	notification "105" "備份完成 $(endtime 1 "批量備份開始到結束")"
	verify_backup_manifest
	[[ -f $txt_path ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path"
	[[ -f $txt_path2 ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path2"
	# 備份完成後針對本次有變動的應用做 json 健全度檢查 (結構+欄位一併驗證)
	# 流式模式: json 在遠端 (本地 staging 已刪), 跳過本地驗證 (上傳時已即時驗證)
	if [[ $remote_stream != 1 && -s $TMPDIR/.changed_apps ]]; then
		echoRgb "—————— 備份後 JSON 結構驗證 ——————" "3"
		local _jchk_sorted="$TMPDIR/.post_json_apps"
		sort -u "$TMPDIR/.changed_apps" > "$_jchk_sorted"
		local _jchk_total _jchk_i=1
		_jchk_total="$(wc -l < "$_jchk_sorted")"
		while read -r _japp; do
			local _jf="$Backup/$_japp/app_details.json"
			echoRgb "[$_jchk_i/$_jchk_total] $_japp" "3"
			_json_health_check "$_jf" "$_japp"
			let _jchk_i++
		done < "$_jchk_sorted"
		echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
		rm -f "$_jchk_sorted"
	fi
	_json_health_report
	REMOTE_TRIGGER=1
	# subshell 環境下 trap EXIT 在主 shell 不會觸發, 這裡直接呼叫
	remote_cleanup
	exit 0
}
# 增量備份: 只備份版本號有更新的 app
# 對照 app_details.json 內舊版本, 沒變動的跳過
backup_update_apk() {
	Update_backup='true'
	backup
}
# 重新生成應用列表的 app 名稱欄位 (恢復模式選單用)
dumpname() {
	get_name "Apkname"
}
# 轉換 app 資料夾名稱 (舊格式 → 新格式)
convert() {
	get_name "convert"
}
# 對整個備份目錄做壓縮檔完整性檢查 (Check_archive 的批次入口)
check_file() {
	Check_archive "$MODDIR"
}
# 驗證所有 app_details.json 結構完整性 (jq 解析)
# 主選單「JSON結構檢查」呼叫
Check_json() {
	starttime1="$(date -u "+%s")"
	local error_log="$TMPDIR/json_error_log"
	rm -rf "$error_log"
	local r i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | wc -l)"
	[[ $r -eq 0 ]] && { echoRgb "找不到任何 app_details.json" "0"; return; }
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort | while read -r; do
		local dir="${REPLY%/*}"
		echoRgb "檢查第$i/$r個 剩下$((r - i))個" "3"
		echoRgb "檢查:${dir##*/}"
		if jq empty "$REPLY" >/dev/null 2>&1; then
			echoRgb "JSON結構正常" "1"
		else
			echoRgb "JSON結構損壞或格式錯誤" "0"
			echo "$REPLY">>"$error_log"
		fi
		echoRgb "$((i * 100 / r))% $(progress_bar $((i * 100 / r)))"
		let i++
	done
	endtime 1
	if [[ -f $error_log ]]; then
		echoRgb "以下 JSON 檔損壞:\n $(cat "$error_log")" "0"
	else
		echoRgb "恭喜~~全數 JSON 結構正常" "1"
	fi
	rm -rf "$error_log"
}
# 目前本地備份統計總覽: 應用/媒體數量、檔案數、總大小、含SSAID應用數、json有效率
Backup_Stats() {
	starttime1="$(date -u "+%s")"
	echoRgb "—————— 目前備份統計 ——————" "3"
	local _jsons _total_json=0 _valid_json=0 _ssaid_cnt=0 _app_cnt=0 _media_cnt=0
	# 唯讀算出備份目錄 (不呼叫 backup_path(), 避免其 mkdir/隨身碟詢問等副作用)
	local _scan_dir
	if [[ $Output_path != "" ]]; then
		local _op="$Output_path"
		[[ ${_op: -1} = / ]] && _op="${_op%?}"
		if [[ ${_op:0:1} != / ]]; then
			_scan_dir="$MODDIR/$_op/$(get_backup_dirname)"
		else
			_scan_dir="$_op/$(get_backup_dirname)"
		fi
	else
		_scan_dir="$MODDIR/$(get_backup_dirname)"
	fi
	[[ ! -d $_scan_dir ]] && _scan_dir="$MODDIR"
	_jsons="$(find "$_scan_dir" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null)"
	if [[ -z $_jsons ]]; then
		echoRgb "找不到任何備份 (無 app_details.json, 已搜尋: $_scan_dir)" "0"
		return
	fi
	_total_json="$(echo "$_jsons" | grep -vc '^$')"
	while read -r _jf; do
		[[ -z $_jf ]] && continue
		local _dirname="${_jf%/*}"
		_dirname="${_dirname##*/}"
		if [[ $_dirname = Media ]]; then
			let _media_cnt++
		else
			let _app_cnt++
		fi
		if jq -e . "$_jf" >/dev/null 2>&1; then
			let _valid_json++
			local _has_ssaid
			_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_jf" 2>/dev/null)"
			[[ ${_has_ssaid:-0} -gt 0 ]] && let _ssaid_cnt++
		fi
	done <<EOF5
$_jsons
EOF5
	# 檔案數與總大小: 用既有 calc_dir_size 邏輯量整個 Backup 目錄, 對應電腦端「大小」算法
	local _filecount _totalsize
	_filecount="$(find "$_scan_dir" -maxdepth 3 -type f 2>/dev/null | grep -vc '^$')"
	_totalsize="$(calc_dir_size "$_scan_dir" 2>/dev/null)"
	echoRgb "應用數量: $_app_cnt 個" "2"
	[[ $_media_cnt -gt 0 ]] && echoRgb "媒體/自訂資料夾: $_media_cnt 個" "2"
	echoRgb "檔案總數: ${_filecount:-0} 個" "2"
	echoRgb "備份總大小: $(size "${_totalsize:-0}")" "2"
	echoRgb "含SSAID的應用: $_ssaid_cnt 個" "2"
	if [[ $_valid_json -eq $_total_json ]]; then
		echoRgb "JSON有效率: $_valid_json/$_total_json (全數正常)" "1"
	else
		echoRgb "JSON有效率: $_valid_json/$_total_json (有 $((_total_json - _valid_json)) 個損壞)" "0"
	fi
	endtime 1 "統計用時"
}
# 統計分派: conf 有設定遠端就用遠端統計, 沒有就本地統計
Stats_Dispatch() {
	if [[ -n $remote_type ]]; then
		Remote_Backup_Stats
	else
		Backup_Stats
	fi
}
# 遠端備份統計總覽: 應用數量、檔案數、總大小、含SSAID應用數、json有效率 (遠端版)
Remote_Backup_Stats() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "統計功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	starttime1="$(date -u "+%s")"
	local target_dir="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $target_dir" "3"
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	[[ $remote_type = smb ]] && remote_parse_smb_url
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	echoRgb "—————— 遠端備份統計 ——————" "3"
	echoRgb "正在掃描遠端檔案列表 (單次連線)..." "3"
	local _filelist="$TMPDIR/.remote_stats_files"
	remote_list_files "$target_dir" > "$_filelist" 2>/dev/null
	if [[ ! -s $_filelist ]]; then
		echoRgb "遠端目錄不存在或無檔案: $target_dir" "0"
		rm -f "$_filelist"
		return 1
	fi
	local _filecount _app_cnt=0 _media_cnt=0 _apps="$TMPDIR/.remote_stats_apps"
	_filecount="$(grep -vc '^$' "$_filelist")"
	# 過濾出 app_details.json 所在的子目錄名 (即 app 名/Media)
	grep -E '/app_details\.json$|^app_details\.json$' "$_filelist" | sed 's|/app_details\.json$||' | sort -u > "$_apps"
	if [[ ! -s $_apps ]]; then
		echoRgb "找不到任何 app_details.json" "0"
		rm -f "$_filelist" "$_apps"
		return 1
	fi
	local _total_json _ra
	_total_json="$(grep -vc '^$' "$_apps")"
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		if [[ $_ra = Media ]]; then
			let _media_cnt++
		else
			let _app_cnt++
		fi
	done < "$_apps"
	echoRgb "正在計算遠端總大小..." "3"
	local _totalsize
	_totalsize="$(remote_dir_size "$target_dir")"
	# 並發下載逐一驗證 json 有效性 + 統計 SSAID (沿用健全度檢查的並發下載模式)
	echoRgb "正在下載驗證 $_total_json 個app的json..." "3"
	rm -rf "$TMPDIR/.remote_stats_dl" 2>/dev/null
	mkdir -p "$TMPDIR/.remote_stats_dl" 2>/dev/null
	local _running=0 _i=0
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		let _i++
		printf '\r -下載中 %d/%d' "$_i" "$_total_json" >&2
		( remote_download_single_file "$_ra/app_details.json" "$TMPDIR/.remote_stats_dl/$_ra.json" 2>/dev/null ) &
		let _running++
		if [[ $_running -ge 8 ]]; then wait; _running=0; fi
	done < "$_apps"
	wait
	echo >&2
	local _valid_json=0 _ssaid_cnt=0
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		local _jf="$TMPDIR/.remote_stats_dl/$_ra.json"
		if [[ -s $_jf ]] && jq -e . "$_jf" >/dev/null 2>&1; then
			let _valid_json++
			local _has_ssaid
			_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_jf" 2>/dev/null)"
			[[ ${_has_ssaid:-0} -gt 0 ]] && let _ssaid_cnt++
		fi
	done < "$_apps"
	rm -rf "$TMPDIR/.remote_stats_dl" "$_filelist" "$_apps" 2>/dev/null
	echoRgb "應用數量: $_app_cnt 個" "2"
	[[ $_media_cnt -gt 0 ]] && echoRgb "媒體/自訂資料夾: $_media_cnt 個" "2"
	echoRgb "檔案總數: ${_filecount:-0} 個" "2"
	echoRgb "備份總大小: $(size "${_totalsize:-0}")" "2"
	echoRgb "含SSAID的應用: $_ssaid_cnt 個" "2"
	if [[ $_valid_json -eq $_total_json ]]; then
		echoRgb "JSON有效率: $_valid_json/$_total_json (全數正常)" "1"
	else
		echoRgb "JSON有效率: $_valid_json/$_total_json (有 $((_total_json - _valid_json)) 個損壞或無法下載)" "0"
	fi
	endtime 1 "統計用時"
}
# ======================================================
# Restore() 主函數
# ======================================================
# 主恢復函數 - 安裝 apk + 恢復 data + 還原 SSAID/權限
# ssaid_mode=true 時只恢復含 SSAID 的 app
# 從遠端流式恢復: 讀 appList_network.txt, 逐 app 流式拉回解壓 (不佔本機)
# 復用 Restore 的全部邏輯 (uid/selinux/權限/ssaid), 只是資料來源改為遠端流式
remote_stream_restore() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "流式恢復僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	local list="$MODDIR/appList_network.txt"
	if [[ ! -f $list ]]; then
		echoRgb "找不到 $list" "0"
		echoRgb "請先執行 '列出遠端備份' 產生清單, 編輯後再來流式恢復" "3"
		return 1
	fi
	# 連線預檢 + 解析 SMB 路徑 (流式 _stream_download 需要 SMB_SHARE/SMB_REM_PATH)
	remote_parse_endpoint
	[[ $remote_type = smb ]] && remote_parse_smb_url
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	# 遠端備份子目錄 (Backup_zstd_X)
	_RESTORE_SUBDIR="$(get_backup_dirname)"
	echoRgb "流式恢復來源: $remote_type://$REMOTE_HOST/ ($_RESTORE_SUBDIR)" "3"
	echoRgb "清單: $list" "2"
	# 設流式恢復旗標, 復用 Restore 全流程
	_RESTORE_STREAM=1
	mkdir -p "$TMPDIR/.restore_stage" 2>/dev/null
	Restore
	# 清理 staging (只有 json, 數據從未落地)
	rm -rf "$TMPDIR/.restore_stage" 2>/dev/null
	_RESTORE_STREAM=0
}

Restore() {
	self_test
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	# 預掃資料 (取代主迴圈內每 app fork)
	prepare_pkg_uid_map
	prepare_pkg_ver_map
	prepare_installed_pkgs_map
	# 初始化恢復 SSAID 暫存檔 (取代 SSAID_Package2 字串拼接)
	: > "$TMPDIR/.restore_ssaid"
	if [[ ! -f ${0%/*}/app_details.json ]]; then
		echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/start.sh選擇終止腳本\n -否則腳本將繼續執行直到結束" "0"
		echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/start.sh選擇轉換資料夾名稱"
		txt="$MODDIR/appList.txt"
		# 流式恢復: 改用 appList_network.txt (功能8 產生), 過濾掉註解與特殊項(wifi/Media), 只留 app 行
		if [[ $_RESTORE_STREAM = 1 ]]; then
			grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$MODDIR/appList_network.txt" 2>/dev/null \
				| grep -Evx '[[:space:]]*(wifi|Media)[[:space:]]*' > "$TMPDIR/.stream_restore_list"
			txt="$TMPDIR/.stream_restore_list"
		fi
		[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來恢復" "0" && exit 2
		sort -u "$txt" -o "$txt" 2>/dev/null
		i=1
		r="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>/dev/null)"
		[[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
		Backup_folder2="$MODDIR/Media"
		#校驗選填是否正確
		[[ $recovery_mode != "" ]] && isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx" || {
		echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
		get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
		}
		[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
		echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		}
		if [[ $_RESTORE_STREAM = 1 ]]; then
			Get_user="$(get_backup_dirname | grep -Eo '[0-9]+$')"
		else
			Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
		fi
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
		}
		[[ $recovery_mode2 = false ]] && exit 2
		if [[ $recovery_mode = true && $ssaid_mode != true && $_RESTORE_STREAM != 1 ]]; then
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
				echoRgb "未安裝應用列表\n$txt" "1"
				if ! ask_yn "確認恢復?" "恢復安裝" "退出腳本"; then
					exit
				fi
			else
				echoRgb "獲取完成 但備份內應用都已安裝....正在退出腳本" "0" && exit 0
			fi
		fi
		if [[ $ssaid_mode = true ]]; then
			# 改 here-string 為暫存檔 (mksh 不支援 <<<)
			# 用暫存檔取代 ssaid_name 字串拼接 (O(N²) → O(N))
			local _find_tmp="$TMPDIR/.find_ssaid_$$"
			local _ssaid_tmp="$TMPDIR/.ssaid_list_$$"
			find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>/dev/null | sort > "$_find_tmp"
			: > "$_ssaid_tmp"
			while read -r; do
				if [[ $(jq -r 'try (.[] | select(.Ssaid != null).Ssaid) catch ""' "$REPLY" 2>/dev/null) != "" ]]; then
					ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch ""' "$REPLY" 2>/dev/null | head -n 1)"
					PackageName="$(jq -r 'try (.[] | select(.PackageName != null).PackageName) catch ""' "$REPLY" 2>/dev/null)"
					echo "$ChineseName $PackageName" >> "$_ssaid_tmp"
				fi
			done < "$_find_tmp"
			[[ -s $_ssaid_tmp ]] && ssaid_name="$(cat "$_ssaid_tmp")"
			rm -f "$_find_tmp" "$_ssaid_tmp"
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
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$app_details" | head -n 1)"
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
	# 啟用權限批量模式: 迴圈內 restore_permissions 只收集到暫存檔, 迴圈結束後 flush 一次沖刷 (JVM 3N → 3)
	# 此迴圈同時服務批量恢復(N個app)與單獨恢復(1個app); 單獨恢復時收集1組→flush設1組, 等價立即執行
	_batch_perm_mode=1
	rm -f "$TMPDIR/.batch_grant" "$TMPDIR/.batch_revoke" "$TMPDIR/.batch_ops" "$TMPDIR/.batch_opsreset"
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ ! -f ${0%/*}/app_details.json ]]; then
			echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
			notification "105" "恢復第$i/$r個應用 剩下$((r - i))個
恢復 $name1"
			# 一次 sed 抓行, 用 parameter expansion 拆欄位
			_line="$(echo "$txt" | sed -n "${i}p")"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
			unset No_backupdata apk_version
			if [[ $name1 = *! || $name1 = *！ ]]; then
				name1="${name1//!/}"
				name1="${name1//！/}"
				echoRgb "跳過恢復$name1 所有數據" "0"
				No_backupdata=1
			fi
			Backup_folder="$MODDIR/$name1"
			# 流式恢復: 本地無備份, 從遠端拉 app_details.json 到 TMPDIR staging
			if [[ $_RESTORE_STREAM = 1 ]]; then
				Backup_folder="$TMPDIR/.restore_stage/$name1"
				mkdir -p "$Backup_folder" 2>/dev/null
				_stream_download "$_RESTORE_SUBDIR/$name1/app_details.json" > "$Backup_folder/app_details.json" 2>/dev/null
			fi
			if [[ -f "$Backup_folder/app_details.json" ]]; then
				app_details="$Backup_folder/app_details.json"
				apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
				# 流式: 列表(appList_network.txt)只有資料夾名, 包名 name2 從 json 的 PackageName 取
				if [[ $_RESTORE_STREAM = 1 ]]; then
					name2="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details" 2>/dev/null)"
				fi
			else
				echoRgb "$Backup_folder/app_details.json不存在" "0"
			fi
			[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
		fi
		# 流式恢復: Backup_folder 是 staging (只有 json), 視為存在以進入恢復流程
		if [[ -d $Backup_folder ]] || [[ $_RESTORE_STREAM = 1 ]]; then
			echoRgb "恢復$name1" "2"
			Background_application_list
			restore="true"
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略恢復" "0" && restore="false"
			[[ $restore = true ]] && {
			starttime2="$(date -u "+%s")"
			# 用預掃的 .installed_pkgs 查 (取代 fork pm 3 次)
			# 注意: installapk 後 app 已裝, 再裝完用 grep 重查
			local _is_installed
			_is_installed=$(awk -v p="$name2" '$0==p{f=1} END{exit !f}' "$TMPDIR/.installed_pkgs" 2>/dev/null && echo 1)
			# 流式: 設定 apk 遠端來源 (installapk 會用)
			# 流式: 設定 apk 遠端來源 (依壓縮方式決定後綴)
			if [[ $_RESTORE_STREAM = 1 ]]; then
				case $Compression_method in
				tar|Tar|TAR) _STREAM_APK_SRC="$_RESTORE_SUBDIR/$name1/apk.tar" ;;
				*) _STREAM_APK_SRC="$_RESTORE_SUBDIR/$name1/apk.tar.zst" ;;
				esac
			fi
			local _was_installed="$_is_installed"
			if [[ -z $_is_installed ]]; then
				installapk
				# installapk 內部會用 echo_log 設 $result
				if [[ $result = 0 ]]; then
					echo "$name2" >> "$TMPDIR/.installed_pkgs"
					_is_installed=1
				else
					_is_installed=0
				fi
			else
				# 已裝, 比版本決定要不要 reinstall
				local _cur_ver
				_cur_ver=$(awk -v pkg="$name2" -F'\t' '$1 == pkg {print $2; exit}' "$TMPDIR/.pkg_ver" 2>/dev/null)
				if [[ $apk_version -gt ${_cur_ver:-0} ]]; then
					installapk && [[ $? = 0 ]] && echoRgb "版本提升${_cur_ver}>$apk_version" "1"
				fi
			fi
			# 流式 + 僅恢復未安裝模式: 已裝的 app 跳過數據恢復 (流式無預篩, 在此落實 recovery_mode 語義)
			if [[ $_RESTORE_STREAM = 1 && $recovery_mode = true && -n $_was_installed ]]; then
				echoRgb "$name1 已安裝, 僅恢復未安裝模式下跳過數據恢復" "2"
			elif [[ $_is_installed = 1 ]]; then
				if [[ $No_backupdata = "" ]]; then
					[[ $name2 != *mt* ]] && {
					kill_app
					if [[ $_RESTORE_STREAM = 1 ]]; then
						# 流式: 枚舉資料類型, 設 _STREAM_SRC 遠端路徑, 逐個流式解壓
						local _dt
						for _dt in user data obb user_de; do
							# 只恢復遠端 json 有記錄的資料 (Size 存在表示有備份)
							local _has
							_has="$(jq -r --arg k "$_dt" 'try .[$k].Size catch "" // ""' "$app_details" 2>/dev/null)"
							[[ -z $_has || $_has = null ]] && continue
							case $Compression_method in
							tar|Tar|TAR) _STREAM_SRC="$_RESTORE_SUBDIR/$name1/$_dt.tar" ;;
							*) _STREAM_SRC="$_RESTORE_SUBDIR/$name1/$_dt.tar.zst" ;;
							esac
							Release_data "$Backup_folder/${_STREAM_SRC##*/}"
						done
						unset _STREAM_SRC
					else
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" -name "*.tar*" -type f 2>/dev/null | sort | while read -r; do
						Release_data "$REPLY"
					done
					fi
					unset G
					restore_permissions
					Ssaid="$_rp_ssaid"
					if [[ $Ssaid != "" ]]; then
						# 用暫存檔取代字串拼接
						echo "$name1 $name2 $Ssaid" >> "$TMPDIR/.restore_ssaid"
						unset Ssaid
					fi
					}
				fi
			else
				[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
			fi
			endtime 2 "$name1恢復" "2" && echoRgb "完成$((i * 100 / r))% $(progress_bar $((i * 100 / r)))" "3"
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
			# 從暫存檔讀取累積的 ssaid 清單 (取代 SSAID_Package2 字串拼接)
			[[ -s $TMPDIR/.restore_ssaid ]] && SSAID_Package2="$(cat "$TMPDIR/.restore_ssaid")"
			[[ $SSAID_Package2 != "" ]] && {
			echoRgb "開始恢復saaid" "0"
			set_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s %s ", $2, $3}')"
			ssaid_info="$(get_ssaid "$(echo "$SSAID_Package2" | awk '{printf "%s ", $2}')")"
			echo "$SSAID_Package2" | while read -r; do
				Ssaid="$(echo "$REPLY" | cut -d' ' -f3)"
				name1="$(echo "$REPLY" | cut -d' ' -f1)"
				name2="$(echo "$REPLY" | cut -d' ' -f2)"
				# awk 取代 <<<here-string (mksh 不支援)
				if [[ $(echo "$ssaid_info" | awk -v pkg="$name2" '$1 == pkg {print $2}') = $Ssaid ]]; then
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
				B="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>/dev/null)"
				[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
				notification "106" "Media恢復開始"
				while [[ $A -le $B ]]; do
					name1="$(awk -v n=$A '!/[#＃]/ && NF{c++} c==n{print $1; exit}' "$txt" 2>/dev/null)"
					starttime2="$(date -u "+%s")"
					echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
					Release_data "$Backup_folder2/$name1"
					endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))% $(progress_bar $((A * 100 / B)))" "3" && echoRgb "____________________________________" && let A++
				done
				endtime 1 "自定義恢復" "2"
				notification "106" "Media恢復完成 $(endtime 1 "Media恢復" "2")"
			fi
			[[ $_RESTORE_STREAM != 1 ]] && recover_wifi "$MODDIR/wifi"
			}
		fi
		let i++ en++ nskg++
	done
	# 迴圈結束: 一次批量設置所有 app 的權限 (grant/revoke/ops 各一次 JVM)
	flush_batch_permissions
	# 復位: 確保批量模式不外溢. 目前 restore_permissions 僅此迴圈調用, 但保留復位作防禦
	_batch_perm_mode=0
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user" >/dev/null 2>&1
	starttime1="$TIME"
	echoRgb "$DX完成" && endtime 1 "$DX開始到結束"
	notification "109" "恢復完成 $(endtime 1 "$DX開始到結束")"
	case "$TMPDIR" in ""|"/") echo "TMPDIR異常，拒絕清理: $TMPDIR"; exit 1 ;; *) rm -rf "$TMPDIR"/* 2>/dev/null ;; esac
}
# 恢復自定義資料夾 (Media 等)
Restore3() {
	self_test
	echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了" "2"
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	if ! ask_yn "繼續恢復自定義資料夾?" "恢復自定義資料夾" "離開腳本"; then
		exit 0
	fi
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
	B="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>/dev/null)"
	Set_screen_pause_seconds on
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && exit 1
	notification "108" "Media恢復開始"
	while [[ $A -le $B ]]; do
		name1="$(awk -v n=$A '!/[#＃]/ && NF{c++} c==n{print $1; exit}' "$txt" 2>/dev/null)"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$((A * 100 / B))% $(progress_bar $((A * 100 / B)))" "3" && echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	notification "108" "Media恢復完成 $(endtime 1 "Media恢復")"
}
# 僅恢復包含 SSAID 應用 (不含數據,只裝 apk + 還原 SSAID)
# 用於只想保留遊戲帳號識別、不要舊存檔的場景
Restore4() {
	if [[ $ssaid_mode_1 = true ]]; then
		while read -r; do
			if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
				ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$REPLY" | head -n 1)"
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
			_line="$(echo "$txt" | sed -n "${i}p")"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
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
# ======================================================
# 生成列表 / 檢查 / backup_media / wifi
# ======================================================
# 生成應用列表 (掃描所有已安裝 user app, 輸出到 appList.txt)
# 配合 blacklist/whitelist 過濾系統 app
Getlist() {
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內生成列表" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	[[ $blacklist_mode != "" ]] && isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx" || {
	echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
	get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
	}
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
	# 在 Apk_info 被收窄前, 先存全系統包名集合 (供結尾「舊註解清理」用, 省去再跑一次 pm list packages)
	echo "$Apk_info" | awk '{print $2}' | sed '/^[[:space:]]*$/d' | sort -u > "$TMPDIR/.getlist_allpkg"
	Apk_info="$(printf '%s\n%s\n' "$(echo "$Apk_info" | awk '$3 != "system" {print $1, $2}')" "$Pre_installed_apps" | sed '/^[[:space:]]*$/d' | sort -u)"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	exit 2 ; } || Apk_info2="$(echo "$Apk_info" | cut -d' ' -f2)"
	Apk_Quantity="$(awk 'END{print NR}' <<< "$Apk_info")"
	echoRgb "列出第三方應用......." "2"
	i=0; rc=0; rd=0; Q=0; Qc=0; rb=0
	# 預先收集所有「待加進 txt」的行, 用暫存檔取代 REPLY2 字串拼接 (O(N²) → O(N))
	local appended="$TMPDIR/.getlist_append"
	: > "$appended"
	# 一次 awk 把所有 app 預分類, 取代主迴圈內的多次 grep/awk fork
	# 輸出格式: <類別>\t<原行>
	# 類別: BLACK / XPOSED / WHITE / PRELOAD / NORMAL
	local classified="$TMPDIR/.getlist_class"
	# 分類 awk: 同時做「已存在判斷」與「同名不同包重命名」, 主迴圈不再 fork grep/add_entry
	# 用 FNR==NR 先吃 $txt (現有清單): 收集已存在包名集合 exist[], 以及 app名→已被佔用 namecnt[]
	# 第二檔 (Apk_info) 才做分類; 輸出格式: <類別>\t<最終label>\t<pkg>
	echo "$Apk_info" | sed 's/[\/:()\[\]\-!]//g' > "$TMPDIR/.getlist_apkinfo"
	awk -v whitelist="$whitelist" \
		-v blacklist="$blacklist" \
		-v xposed="$xposed_name" '
		BEGIN {
			n = split(whitelist, _w, /[ \t\n]+/)
			for (k in _w) if (_w[k] != "") wl[_w[k]] = 1
			n = split(blacklist, _b, /[ \t\n]+/)
			for (k in _b) if (_b[k] != "" && _b[k] !~ /^[#＃]/) bl[_b[k]] = 1
			n = split(xposed, _x, /[ \t\n]+/)
			for (k in _x) if (_x[k] != "") xp[_x[k]] = 1
			preload_re = "(oneplus|miui|xiaomi|oppo|flyme|meizu|coloros)"
			preload_exact["com.android.soundrecorder"] = 1
			preload_exact["com.mfashiongallery.emag"] = 1
			preload_exact["com.mi.health"] = 1
			preload_exact["com.duokan.phone.remotecontroller"] = 1
			preload_exact["com.android.calendar"] = 1
			preload_exact["com.android.deskclock"] = 1
			preload_exact["com.google.android.safetycore"] = 1
			preload_exact["com.google.android.contactkeys"] = 1
			preload_exact["com.google.android.apps.messaging"] = 1
			preload_exact["com.google.android.calendar"] = 1
		}
		# 第一檔: 現有 $txt — 收集已存在 pkg 與 app名已佔用情況
		FNR==NR {
			# 包名永遠是最後一欄 $NF; label 是前面所有欄位 (app 名可能含空格)
			# (註解行如 "#日曆 com.google...calendar" 也要排除該 app 重複輸出)
			if (NF < 2) next
			_cpkg = $NF
			_clabel = $1
			for (_j = 2; _j < NF; _j++) _clabel = _clabel " " $_j
			if ($0 ~ /^[#＃!]/) {
				exist_cmt[_cpkg] = 1       # 被註解(#/!)的已存在包名
			} else {
				exist[_cpkg] = 1           # 正常已存在包名
				namepkg[_clabel] = _cpkg   # 同名衝突判斷只看非註解行
				used[_clabel] = 1
			}
			next
		}
		# 第二檔: Apk_info — 分類
		{
			# 防禦: 跳過空行或缺包名的行 (避免產生空 pkg 分類, 與 Apk_Quantity 計數不一致)
			if (NF < 2) next
			# 包名永遠是最後一欄 $NF; label 是前面所有欄位 (app 名可能含空格)
			pkg = $NF
			label = $1
			for (_j = 2; _j < NF; _j++) label = label " " $_j
			# 已存在(正常) → EXIST; 已存在(被註解) → EXIST_CMT; 兩者主迴圈都只計數跳過
			if (pkg in exist)     { print "EXIST\t"     label "\t" pkg; next }
			if (pkg in exist_cmt) { print "EXIST_CMT\t" label "\t" pkg; next }
			# 同名不同包 → 加數字後綴 (與 add_entry 等價)
			final = label
			if ((label in used) && namepkg[label] != pkg) {
				c = 1
				while ((final = label "_" c) in used) c++
			}
			used[final] = 1; namepkg[final] = pkg
			if (pkg in bl)        { print "BLACK\t"      final "\t" pkg; next }
			if (pkg ~ preload_re || pkg in preload_exact) {
				if (pkg in xp)    { print "PRELOAD_XP\t" final "\t" pkg; next }
				if (pkg in wl)    { print "PRELOAD_WL\t" final "\t" pkg; next }
				print "PRELOAD\t" final "\t" pkg; next
			}
			if (pkg in xp)        { print "XPOSED\t"     final "\t" pkg; next }
			print "NORMAL\t" final "\t" pkg
		}' "$txt" "$TMPDIR/.getlist_apkinfo" > "$classified"
	rm -f "$TMPDIR/.getlist_apkinfo"
	[[ -n "$(echo "$blacklist" | grep -Ev '#|＃')" ]] && NZK=1
	# 主迴圈: 從分類結果讀, 每行已預先標好類別
	LR=1
	local _seen=0   # 核對1: 迴圈實際處理的 app 數, 應 == Apk_Quantity
	# 分類 awk 已算好最終 label 與已存在判斷, 迴圈內不再 fork (grep/cat/add_entry 全消除)
	while IFS=$'\t' read -r kind app_label app_pkg; do
		[[ -z $app_pkg ]] && continue
		let _seen++
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_name="$app_label"
		REPLY="$app_label $app_pkg"
		case $kind in
		EXIST)
			let Q++
			let LR++; let rgb_a++
			continue
			;;
		EXIST_CMT)
			let Qc++
			echoRgb "$app_name 已註解 略過輸出" "0"
			let LR++; let rgb_a++
			continue
			;;
		BLACK)
			if [[ $NZK = 1 ]]; then
				if [[ $blacklist_mode = false ]]; then
					echo "$REPLY" >> "$appended"
					tmp=1
					echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
					let i++ rb++
				else
					echoRgb "$app_label黑名單應用 不輸出" "0"
					let rb++
				fi
			fi
			let LR++; let rgb_a++
			continue
			;;
		PRELOAD_XP)
			echoRgb "$((i+1)):$app_name為Xposed模塊 進行添加" "0"
			echo "$REPLY" >> "$appended"
			tmp=1
			let i++ rd++
			;;
		PRELOAD_WL)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
			let i++
			;;
		PRELOAD)
			echoRgb "$app_name 預裝應用 忽略輸出" "0"
			echo "#$REPLY" >> "$appended"
			tmp=1
			let rc++
			;;
		XPOSED)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):Xposed: $app_name $app_pkg($rgb_a)"
			let i++ rd++
			;;
		NORMAL|*)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
			let i++
			;;
		esac
		let LR++; let rgb_a++
	done < "$classified"
	# 核對1 用: 先記錄合併前 txt 既有的有效行數 (非註解) — 須在 append 前取
	local _old_eff
	_old_eff=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$txt" 2>/dev/null)
	local _chk_fail=0
	# ====== 數量核對1: 全員到齊 (無論有無新輸出都檢查) ======
	# 迴圈處理數 _seen 應 == 分類檔行數, 且 == 系統第三方總數 Apk_Quantity
	local _cls_lines
	_cls_lines=$(awk 'END{print NR+0}' "$classified" 2>/dev/null)
	if [[ ${_seen:-0} -ne ${_cls_lines:-0} ]]; then
		echoRgb "⚠️ 數量核對1異常: 迴圈處理=$_seen 但分類檔行數=$_cls_lines (迴圈漏讀)" "0"
		_chk_fail=1
	elif [[ ${_seen:-0} -ne ${Apk_Quantity:-0} ]]; then
		echoRgb "⚠️ 數量核對1異常: 已分類=$_seen 但第三方總數=$Apk_Quantity (分類前後數量不符)" "0"
		_chk_fail=1
	else
		echoRgb "✅ 數量核對1: 全部 $Apk_Quantity 個 app 皆已分類處理" "1"
	fi
	# 把累積的 append 一次寫進 txt
	if [[ -s $appended ]]; then
		# 修復: txt 結尾若缺換行符, 直接 append 會與新內容第一行黏成一行 (已知問題根因)
		[[ -s $txt ]] && [[ -n "$(tail -c1 "$txt")" ]] && echo >> "$txt"
		cat "$appended" >> "$txt"
		echoRgb "已經將預裝應用輸出至appList.txt並注釋# 需要備份則去掉#" "0"
		[[ -n $tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -已註解略過=\"$Qc\"\n -輸出=\"$i\""
		# ====== 數量核對2: 輸出行 (僅在有新輸出時) ======
		# 合併後有效行 應 == 合併前有效行 + 本次輸出 i
		local _eff_lines _expect _new_eff
		_eff_lines=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$txt")
		# 本次 append 的非註解有效行數 (輸出 i 含註解行, 不可全加)
		_new_eff=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$appended" 2>/dev/null)
		_expect=$(( ${_old_eff:-0} + ${_new_eff:-0} ))
		if [[ $_eff_lines -ne $_expect ]]; then
			echoRgb "⚠️ 數量核對2異常: 列表有效行=$_eff_lines 但預期(原有$_old_eff+本次新增有效$_new_eff)=$_expect" "0"
			_chk_fail=1
		else
			echoRgb "✅ 數量核對2: 列表有效行=$_eff_lines (原有$_old_eff+本次新增有效$_new_eff)" "1"
		fi
	else
		# 無新輸出 (全部已存在/已註解): 顯示統計, 核對2 不適用
		[[ -n $tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -已註解略過=\"$Qc\"\n -輸出=\"$i\""
		echoRgb "本次無新增應用 (全部已存在或已註解)" "2"
	fi
	# 任一核對失敗 → 中止, 不寫出可能有誤的列表
	if [[ $_chk_fail = 1 ]]; then
		echoRgb "\n -輸出異常 數量核對不通過 請聯繫作者解決" "0"
		rm -rf "$txt"
		rm -f "$appended" "$classified"
		exit
	fi
	rm -f "$appended" "$classified"
	# 結尾過濾: 對 txt 內的每行檢查 pkg 是否還在系統內, 不在的刪掉
	# 用一個 awk 一次處理 (取代原本 per-row fork awk)
	if [[ -f $txt ]]; then
		local pkg_set="$TMPDIR/.getlist_pkgset"
		echo "$Apk_info2" > "$pkg_set"
		# 註解行用「全系統已裝包名」判斷 (Apk_info2 僅第三方+白名單預裝, 會誤刪系統 app)
		# 直接複用開頭 appinfo 已存的全包名集合, 不再跑 pm list packages (省一次全系統查詢)
		local all_pkg_set="$TMPDIR/.getlist_allpkg"
		local _allpkg_n
		_allpkg_n="$(wc -l < "$all_pkg_set" 2>/dev/null || echo 0)"
		local filtered="$TMPDIR/.getlist_filtered"
		# 三檔: (1)第三方清單 existing[] (2)全系統清單 allpkg[] (3)txt 逐行判斷
		awk -v allpkg_n="$_allpkg_n" '
			# 第一檔: 第三方清單
			FNR==NR { existing[$1]=1; next }
			# 第二檔: 全系統清單
			FILENAME == ALLF { allpkg[$1]=1; next }
			# 第三檔: txt
			/^[[:space:]]*$/ { print; next }
			/^[[:space:]]*[#＃!]/ {
				cpkg = $2
				if (cpkg ~ /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/) {
					# 合法包名的註解行: 全系統清單為空時一律保留(防 pm 失敗誤刪), 否則查全系統存在性
					if (allpkg_n == 0 || cpkg in allpkg) print
					else print "##__MISSING__\t" $0
				} else {
					print   # 說明行 / 無合法包名 → 保留
				}
				next
			}
			{
				pkg = $2
				if (pkg == "" || pkg in existing) print
				else print "##__MISSING__\t" $0
			}' ALLF="$all_pkg_set" "$pkg_set" "$all_pkg_set" "$txt" > "$filtered"
		# 印出被刪除的行 (給用戶看)
		grep '^##__MISSING__' "$filtered" | sed 's/^##__MISSING__\t//' | while read -r missing_line; do
			echoRgb "$missing_line不存在系統，從列表中刪除" "0"
		done
		# 寫回 txt (排序, 去空行)
		grep -v '^##__MISSING__' "$filtered" \
			| sed -e '/^$/d' | sort > "$txt"
		rm -f "$pkg_set" "$all_pkg_set" "$filtered"
	fi
	wait
	# ====== appList.txt 結構驗證 (類似 JSON 自動檢查) ======
	# 檢查: 非註解行欄位數=2、包名格式合法、包名無重複
	if [[ -f $txt ]]; then
		echoRgb "—————— 應用列表結構驗證 ——————" "3"
		local _lc_err="$TMPDIR/.applist_err"
		: > "$_lc_err"
		awk '
			/^[[:space:]]*$/      { next }
			/^[[:space:]]*[#＃!]/ { next }
			{
				total++
				if (NF != 2) { print "欄位數異常(" NF "欄): " $0; next }
				pkg = $2
				if (pkg !~ /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/) print "包名格式可疑: " $1 " " pkg
				if (pkg in seen) print "包名重複: " pkg " (與 " seen[pkg] " 重複)"
				else seen[pkg] = $1
			}
			END { print "##TOTAL##\t" total > "/dev/stderr" }
		' "$txt" 2> "$TMPDIR/.applist_cnt" >> "$_lc_err"
		local _lc_total
		_lc_total="$(awk -F'\t' '/^##TOTAL##/{print $2}' "$TMPDIR/.applist_cnt" 2>/dev/null)"
		rm -f "$TMPDIR/.applist_cnt"
		if [[ -s $_lc_err ]]; then
			echoRgb "列表驗證發現異常:" "0"
			while read -r _el; do echoRgb "❌ $_el" "0"; done < "$_lc_err"
			echoRgb "請檢查 appList.txt 後再進行備份" "0"
		else
			echoRgb "✅ 列表結構正常 (${_lc_total:-0} 個有效應用)" "1"
		fi
		rm -f "$_lc_err"
	fi
	endtime 1
	cat "$txt">"$MODDIR/appList.txt" && rm "$txt"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$MODDIR/appList.txt"
	echoRgb "輸出包名結束 請查看$MODDIR/appList.txt"
}
# 備份自定義資料夾 (來自 Custom_path 設定)
# 例: Pictures / Download / DCIM / /data/adb 等
# 結尾設 REMOTE_UPLOAD_MEDIA=1 + REMOTE_TRIGGER=1
backup_media() {
	self_test
	backup_path
	show_conf media
	# 清除可能殘留的遠端json快取: backup_media 本身不會建立這個快取(只有批量備份的
	# prepare_remote_json_map 會), 但若先前跑過批量備份或中斷的測試留下舊快取,
	# _get_remote_appdetails 會一直讀到僵死的舊內容, 導致增量比對永遠用錯誤的舊資料
	rm -rf "$TMPDIR/.remote_json" 2>/dev/null
	# 流式上傳路徑快取: 在 Compression_method 還未被 Backup_data() 暫時污染前固定一次
	_BACKUP_DIRNAME_CACHED="$(get_backup_dirname)"
	# 快照備份前遠端大小 (backup() 主函數才有做這個快照, backup_media 是獨立函數需自己補上,
	# 否則沿用上次殘留的全域變數值, 導致結尾差異統計算出離譜的數字)
	if [[ -n $remote_type ]]; then
		_RTOTAL_BEFORE="$(remote_dir_size "$_BACKUP_DIRNAME_CACHED" 2>/dev/null)"
		[[ -z $_RTOTAL_BEFORE ]] && _RTOTAL_BEFORE=0
	fi
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(awk '!/[#＃]/ && NF{count++} END{print count}' <<< "$Custom_path")"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		app_details="$Backup_folder/app_details.json"
		if [[ $remote_stream = 1 && -n $remote_type ]]; then
			_STREAM_DEST="Media"; Backup_folder="$TMPDIR/.stream_stage/Media"; app_details="$Backup_folder/app_details.json"; mkdir -p "$Backup_folder" 2>/dev/null
		fi
		mediatxt="$Backup/mediaList.txt"
		# 延遲建立: 只有實際備份了至少一個資料夾才建立 Media/txt 等 (避免空殼)
		_media_created=0
		_ensure_media_dirs() {
			[[ $_media_created = 1 ]] && return
			[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
			[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
			[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
			[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
			[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
			[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
			filesize="$(calc_dir_size "$Backup_folder")"
			_media_created=1
		}
		Set_screen_pause_seconds on
		notification "109" "Media備份開始"
		echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' > "$TMPDIR/.media_custom_paths"
		while read -r; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")"
			if [[ ${REPLY##*/} = adb ]]; then
				if [[ $ksu != ksu ]]; then
					echoRgb "Magisk adb"
					_ensure_media_dirs
					Backup_data "${REPLY##*/}" "$REPLY"
				else
					echoRgb "KernelSU adb不支持備份" "0"
				fi
			else
				_ensure_media_dirs
				Backup_data "${REPLY##*/}" "$REPLY"
			fi
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$((A * 100 / B))% $(progress_bar $((A * 100 / B)))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "2" && echoRgb "____________________________________" && let A++
		done < "$TMPDIR/.media_custom_paths"
		rm -f "$TMPDIR/.media_custom_paths"
		# 收尾: 若 Media 內無任何備份檔 (全部跳過/不支持), 清掉空殼避免上傳空目錄
		# 流式模式: .tar 壓縮完即上傳, 本機 $Backup_folder 永遠不會留有 .tar 檔 (設計如此),
		# 故改用 _media_created 旗標 (有實際處理過至少一個資料夾才會被設成1) 判斷, 不能沿用本機檔案掃描
		if [[ $remote_stream = 1 && -n $remote_type ]]; then
			if [[ $_media_created != 1 ]]; then
				echoRgb "Media 無實際備份內容, 清除 mediaList.txt" "0"
				rm -rf "$Backup_folder" 2>/dev/null
				[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>/dev/null) = 0 ]] && rm -f "$mediatxt"
			else
				REMOTE_UPLOAD_MEDIA=1
				# 只有 app_details 真的有實際內容(非初始空殼)才上傳, 避免「全部資料夾無變化跳過」
				# 時, 本地空殼覆蓋掉遠端原本正確的版本
				if [[ -f $app_details ]] && jq -e 'length > 0' "$app_details" >/dev/null 2>&1; then
					_stream_upload "Media/app_details.json" < "$app_details"
					[[ -f $mediatxt ]] && _stream_upload "mediaList.txt" < "$mediatxt"
					echoRgb "Media 清單已上傳遠端" "1"
				else
					echoRgb "Media 本輪全部資料夾無變化, 跳過json上傳(避免覆蓋遠端正確版本)" "2"
				fi
			fi
		elif [[ -d $Backup_folder ]] && ! find "$Backup_folder" -maxdepth 1 -name "*.tar*" -type f 2>/dev/null | grep -q .; then
			echoRgb "Media 無實際備份內容, 清除空目錄與 mediaList.txt" "0"
			rm -rf "$Backup_folder"
			[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>/dev/null) = 0 ]] && rm -f "$mediatxt"
		else
			[[ $remote_stream != 1 ]] && Calculate_size "$Backup_folder"
			[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
		fi
		Set_screen_pause_seconds off
		endtime 1 "自定義備份"
		notification "109" "Media備份完成 $(endtime 1 "自定義備份")"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	REMOTE_TRIGGER=1
	# subshell 環境下 trap EXIT 在主 shell 不會觸發, 這裡直接呼叫
	remote_cleanup
}
# 從 tools/Device_List 對照表查詢設備識別資訊 (處理器型號、RAM 規格等)
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
		if [[ $(stat -c%s "$tools_path/Device_List" 2>/dev/null) -gt 1 ]]; then
			[[ $shell_language = zh-TW ]] && ts_inplace "$tools_path/Device_List"
			echoRgb "已下載機型列表在$tools_path/Device_List"
		else
			echoRgb "下載機型失敗"
		fi
	else
		echoRgb "下載機型失敗"
	fi
}
# 主選單「備份WiFi」入口
# 建立備份目錄結構 + 複製 tools/ + 生成 start.sh + 備份 wifi.json
wifi() {
	backup_path
	show_conf wifi
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	backup_wifi "$Backup/wifi"
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
}
# ======================================================
# 主選單入口
# ======================================================
if [[ $0 = *backup.sh ]]; then
	start=backup
elif [[ $0 = *upload.sh ]]; then
	# upload.sh 位於 Backup_zstd_X/<app>/upload.sh
	# MODDIR 已被入口腳本設成 Backup_zstd_X
	# 取得 app 名 = upload.sh 所在的資料夾名
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
	# 主選單循環: 跑完一個動作回到選單繼續
	# 備份類動作 (backup/backup_update_apk/backup_media/wifi) 跑完直接退出整個腳本
	# 其他動作 (Getlist/remote_test/list/download) 跑完回選單
	while true; do
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
			"從遠端流式恢復(不佔本機)"
			"目前備份統計"
			"殺死運行中腳本"
		)
		# 備份類 commands 結尾用 "; exit" 確保跑完退出主 shell, 而非回到選單
		commands=(
			"Getlist"
			"backup; exit"
			"backup_update_apk; exit"
			"backup_media; exit"
			"wifi; exit"
			"remote_test"
			"upload_current_backup"
			"remote_list_backups"
			"remote_download_backup"
			"remote_stream_restore; exit"
			"Stats_Dispatch"
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
			"JSON結構檢查"
			"轉換文件夾名稱"
			"殺死運行中腳本"
		)
		# 恢復類 commands 結尾用 "; exit" 確保跑完退出
		commands=(
			"dumpname"
			"Restore; exit"
			"ssaid_mode=true && Restore; exit"
			"ssaid_mode_1=true && Restore4; exit"
			"Restore3; exit"
			"recover_wifi \"$MODDIR/wifi\"; exit"
			"check_file"
			"Check_json"
			"convert"
			"echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
		)
	fi
	echoRgb "請選擇要執行的操作："
	for i in "${!steps[@]}"; do
		printf " -%d) %s\n" "$((i+1))" "${steps[$i]}"
	done
	echo " -0) 離開腳本"
	echo -n " -請輸入選項編號: "
	# read 失敗 (stdin 關閉/EOF, 例如後台執行無 tty) 立刻退出,避免無限循環
	if ! read choice; then
		echoRgb "無互動 stdin, 退出" "0"
		exit 0
	fi
	case $choice in
	0)
		echoRgb "已退出腳本" "0"
		exit 0 ;;
	[1-9]*)
		if (( choice >= 1 && choice <= ${#steps[@]} )); then
			index="$((choice - 1))"
			echo " -執行：${steps[$index]}"
			background="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
			if [[ "$background" = "1" ]]; then
				# 後台執行: 用 subshell 防 exit 殺主 shell
				(eval "${commands[$index]}") &
				bg_pid=$!
				# 不論動作類型都 wait, 確保主選單不會被子進程輸出蓋掉
				wait "$bg_pid"
				# 備份/恢復類動作 (commands 含 exit) 跑完整個腳本退出
				case ${commands[$index]} in
				*exit*) exit 0 ;;
				esac
			else
				# 前台: 不包 subshell, command 內的 exit 會真的退出整個腳本
				# (備份類 commands 結尾有 exit, 達成「跑完就退出」)
				eval "${commands[$index]}"
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
