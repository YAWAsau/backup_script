# -------- 遠程備份功能 --------
# 預連線測試 (避免後續操作卡住)
# 用法: remote_precheck <host> <port>
remote_precheck() {
	local host="$1" port="$2"
	[[ -z $host ]] && { echoRgb "remote_precheck: host為空" "0"; return 1; }
	# 嘗試用 nc 或 /dev/tcp 在3秒內判斷可否連線
	if command -v nc >/dev/null 2>&1; then
		nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && return 0
	fi
	# fallback: 用 timeout + bash /dev/tcp
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 sh -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1 && return 0
	fi
	return 1
}

# 寫入遠端上傳 log (帶時間戳)
# 用法: remote_log "訊息"
remote_log() {
	[[ -z $Backup ]] && return
	local logf="$Backup/remote_upload.log"
	mkdir -p "${logf%/*}" 2>/dev/null
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$logf"
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
	echoRgb "_______________________________________" "2"
	echoRgb "$proto 上傳完成: 成功 $ok_count / 失敗 $fail_count" "3"
	remote_log "$proto 上傳結束: 成功 $ok_count / 失敗 $fail_count"
	if [[ $fail_count -gt 0 ]]; then
		echoRgb "失敗清單(已記錄到 remote_upload.log):" "0"
		local n=0
		while read -r line && [[ $n -lt 5 ]]; do
			echoRgb "  $line" "0"
			let n++
		done < "$fail_list"
		[[ $fail_count -gt 5 ]] && echoRgb "  ...還有 $((fail_count - 5)) 個,請看 log" "0"
	fi
	# 刪本地檔案的策略: remote_keep_local=true 永遠保留
	# 否則: 必須「全部成功」才刪除所有上傳過的檔案
	if [[ $remote_keep_local != true ]]; then
		if [[ $fail_count -eq 0 && $ok_count -gt 0 ]]; then
			echoRgb "全部上傳成功,清除本地已上傳檔案" "1"
			while read -r f; do
				[[ -n $f ]] && rm -f "$f"
			done < "$ok_list"
		elif [[ $fail_count -gt 0 ]]; then
			echoRgb "部分上傳失敗,本地檔案全部保留 (含已上傳的)" "0"
			remote_log "部分失敗,本地檔案全部保留"
		fi
	else
		echoRgb "remote_keep_local=1 本地檔案保留" "3"
	fi
	rm -f "$ok_list" "$fail_list" 2>/dev/null
	[[ $fail_count -eq 0 ]]
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
	if [[ -n $REMOTE_APPLIST ]]; then
		echoRgb "讀取本次備份名單" "2"
		echo "$REMOTE_APPLIST" | grep -Ev '^[[:space:]]*[#＃!]|^[[:space:]]*$' | while read -r line; do
			local name1="${line%% *}"
			[[ -z $name1 ]] && continue
			local full="$Backup/$name1"
			[[ -d $full ]] || continue
			find "$full" -type f > "$tmp_collect" 2>/dev/null
			[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
		done
	fi
	if [[ $REMOTE_UPLOAD_MEDIA = 1 && -d $Backup/Media ]]; then
		find "$Backup/Media" -type f > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $Backup/wifi ]]; then
		find "$Backup/wifi" -type f > "$tmp_collect" 2>/dev/null
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	# 固定附加: tools/ 資料夾、start.sh、restore_settings.conf
	# 只要 list_file 已經有內容(代表本次有東西要上傳)就一併帶上,讓遠端目錄能獨立還原
	if [[ -s $list_file ]]; then
		[[ -d $Backup/tools ]] && find "$Backup/tools" -type f >> "$list_file" 2>/dev/null
		[[ -f $Backup/start.sh ]] && echo "$Backup/start.sh" >> "$list_file"
		[[ -f $Backup/restore_settings.conf ]] && echo "$Backup/restore_settings.conf" >> "$list_file"
	fi
	rm -f "$tmp_collect" 2>/dev/null
}

upload_smb() {
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
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
		*)
			echoRgb "remote_url 必須以 smb:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			remote_type=""; return 1 ;;
		esac
		;;
	esac
	# 帳密為空提醒 (非致命, 可能是匿名認證)
	[[ -z $remote_user ]] && echoRgb "remote_user 未設定 (將以匿名嘗試連線)" "0"
	echoRgb "使用: $filepath/smbclient" "2"
	# 解析 smb://server/share/remotepath
	local url="${remote_url#smb://}"
	url="${url%/}"
	local server="${url%%/*}"
	local after_server="${url#$server/}"
	local share_name="${after_server%%/*}"
	local rem_path="/${after_server#$share_name}"
	rem_path="${rem_path%/}"
	[[ $rem_path = / ]] && rem_path=""
	local share="//$server/$share_name"
	# 拆出 host 和 port (server 可能是 host 或 host:port)
	local host="${server%%:*}"
	local port="${server#*:}"
	[[ $port = $server ]] && port=445
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
	echoRgb "準備上傳 $total 個檔案" "3"
	remote_log "SMB 開始: $share, 共 $total 檔"
	# smbclient 共用參數:
	#   -t 10           : 命令 timeout 秒數
	#   -s /dev/null    : 跳過讀取 smb.conf (避免手動編譯版找不到 conf 噴警告)
	local SMB_OPTS="-t 10 -s /dev/null"
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
			echoRgb "完成$((done_dirs * 100 / total_dirs))%" "3"
		fi
	done
	rm -rf "$group_dir" 2>/dev/null
	rm -f "$list_file" 2>/dev/null
	upload_summary "SMB" "$ok_list" "$fail_list"
}

upload_remote() {
	local proto="$1"
	[[ $proto = scp ]] && { upload_scp; return $?; }
	[[ $proto = smb ]] && { upload_smb; return $?; }
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	local base_url
	case $proto in
	webdav)
		base_url="${remote_url%/}"
		[[ $base_url != http://* && $base_url != https://* ]] && { echoRgb "WebDAV地址格式錯誤: $remote_url" "0"; return 1; }
		;;
	ftp)
		base_url="$remote_url"
		[[ $base_url != ftp://* ]] && { echoRgb "FTP地址格式錯誤，需 ftp:// 開頭" "0"; return 1; }
		;;
	esac
	# 連線預檢: 從 base_url 解出 host:port
	local _hp="${base_url#*://}"
	_hp="${_hp%%/*}"
	local _host="${_hp%%:*}"
	local _port="${_hp#*:}"
	if [[ $_port = $_hp ]]; then
		case $proto in
		webdav) [[ $base_url = https://* ]] && _port=443 || _port=80 ;;
		ftp) _port=21 ;;
		esac
	fi
	if ! remote_precheck "$_host" "$_port"; then
		echoRgb "$proto伺服器無法連線: $_host:$_port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	echoRgb "使用: $filepath/curl" "2"
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
	echoRgb "準備上傳 $total 個檔案" "3"
	remote_log "$proto 開始: $base_url, 共 $total 檔"
	# WebDAV: 創建遠程目錄 (MKCOL), FTP: curl --ftp-create-dirs 自動處理
	if [[ $proto = webdav ]]; then
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
				curl -sS -L --http1.1 -X MKCOL -u "$remote_user:$remote_pass" "$cur" 2>/dev/null
			done
		done
	fi
	# 預掃總目錄數 (排除 wifi, 不計入百分比)
	local total_dirs done_dirs=0 last_dir="" cur_top_dir=""
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
		# 目錄切換時印上一個目錄的進度
		if [[ -n $last_dir && $cur_top != "$last_dir" ]]; then
			if [[ $last_dir != wifi && $total_dirs -gt 0 ]]; then
				let done_dirs++
				echoRgb "完成$((done_dirs * 100 / total_dirs))%" "3"
			fi
			echoRgb "上傳目錄 $cur_top" "3"
		elif [[ -z $last_dir ]]; then
			echoRgb "上傳目錄 $cur_top" "3"
		fi
		last_dir="$cur_top"
		local target_url
		if [[ $proto = webdav ]]; then
			local enc_rel="$(url_encode_path "$rel")"
			target_url="$base_url/$enc_rel"
		else
			target_url="$base_url/$rel"
		fi
		local http_code curl_err
		if [[ $proto = ftp ]]; then
			http_code="$(curl -sS --retry 2 --retry-delay 3 --connect-timeout 10 --ftp-create-dirs \
				-T "$f" -u "$remote_user:$remote_pass" -w '%{http_code}' -o "$TMPDIR/.curl_err" "$target_url" 2>&1)"
		elif [[ $proto = webdav ]]; then
			http_code="$(curl -sS -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
				-T "$f" -u "$remote_user:$remote_pass" -w '%{http_code}' -o "$TMPDIR/.curl_err" "$target_url" 2>&1)"
		else
			http_code="$(curl -sS --retry 2 --retry-delay 3 --connect-timeout 10 \
				-T "$f" -u "$remote_user:$remote_pass" -w '%{http_code}' -o "$TMPDIR/.curl_err" "$target_url" 2>&1)"
		fi
		curl_err="$(cat "$TMPDIR/.curl_err" 2>/dev/null)"; rm -f "$TMPDIR/.curl_err"
		# http_code 2xx 視為成功;FTP 226/250 也是;0 表示連不上
		case $http_code in
		2*)
			echo "$f" >> "$ok_list"
			echoRgb "[$idx/$total] ✓ $rel" "1"
			;;
		*)
			echo "$rel  (HTTP $http_code)" >> "$fail_list"
			echoRgb "[$idx/$total] ✗ $rel (HTTP $http_code)" "0"
			[[ -n $curl_err ]] && remote_log "FAIL $proto $rel HTTP=$http_code err=$curl_err" \
				|| remote_log "FAIL $proto $rel HTTP=$http_code"
			;;
		esac
	done < "$list_file"
	# 最後一個目錄(非wifi)的進度
	if [[ -n $last_dir && $last_dir != wifi && $total_dirs -gt 0 ]]; then
		let done_dirs++
		echoRgb "完成$((done_dirs * 100 / total_dirs))%" "3"
	fi
	rm -f "$list_file" 2>/dev/null
	upload_summary "$proto" "$ok_list" "$fail_list"
}

upload_scp() {
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	local use_sshpass
	command -v sshpass >/dev/null 2>&1 && use_sshpass=1
	local host="${remote_url#//}"
	local rpath
	if [[ $host = *:* ]]; then
		rpath="${host#*:}"
		host="${host%%:*}"
	elif [[ $host = */* ]]; then
		rpath="/${host#*/}"
		host="${host%%/*}"
	else
		rpath="/"
	fi
	[[ -z $host ]] && { echoRgb "SCP地址格式錯誤，例: 192.168.1.100:/path" "0"; return 1; }
	# 連線預檢
	if ! remote_precheck "$host" 22; then
		echoRgb "SCP伺服器無法連線: $host:22 (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
	# 檢查連接
	if [[ -n $use_sshpass ]]; then
		sshpass -p "$remote_pass" ssh $opts "$remote_user@$host" "echo ok" >/dev/null 2>&1 \
			|| { echoRgb "SCP密碼或主機錯誤" "0"; return 1; }
	elif [[ $remote_user != "" ]]; then
		ssh -o BatchMode=yes -o ConnectTimeout=5 $opts "$remote_user@$host" "echo ok" >/dev/null 2>&1 \
			|| { echoRgb "SCP需密鑰認證或sshpass (未安裝)" "0"; return 1; }
	else
		echoRgb "remote_user未設置" "0"; return 1
	fi
	local list_file="$TMPDIR/.slist"
	local ok_list="$TMPDIR/.scpok"
	local fail_list="$TMPDIR/.scpfail"
	: > "$ok_list"; : > "$fail_list"
	remote_collect_targets "$list_file"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>/dev/null
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	echoRgb "準備上傳 $total 個檔案" "3"
	remote_log "SCP 開始: $remote_user@$host:$rpath, 共 $total 檔"
	# 先一次性建立所有需要的遠端目錄
	local dirs_file="$TMPDIR/.scp_dirs"
	while read -r f; do
		local rel="${f#$Backup/}"
		local d="${rel%/*}"
		[[ -n $d && $d != "$rel" ]] && echo "$rpath/$d"
	done < "$list_file" | sort -u > "$dirs_file"
	if [[ -s $dirs_file ]]; then
		local mkdir_cmd
		mkdir_cmd="$(awk '{printf "mkdir -p \"%s\"; ", $0}' "$dirs_file")"
		if [[ -n $use_sshpass ]]; then
			sshpass -p "$remote_pass" ssh $opts "$remote_user@$host" "$mkdir_cmd" 2>/dev/null
		else
			ssh $opts "$remote_user@$host" "$mkdir_cmd" 2>/dev/null
		fi
	fi
	rm -f "$dirs_file"
	# 嘗試用 tar pipeline 一次傳完 (比逐檔 scp 快很多)
	# 條件: tar 存在
	local use_tar=0
	command -v tar >/dev/null 2>&1 && use_tar=1
	if [[ $use_tar = 1 ]]; then
		echoRgb "使用 tar pipeline 批次傳輸" "3"
		# 用 -T 從清單讀檔, -C 切到 $Backup 讓相對路徑乾淨
		# 遠端用 tar x -C $rpath 解開
		local tar_rc=1
		# 把 list_file 轉成相對 $Backup 的相對路徑
		local rel_list="$TMPDIR/.scp_rel"
		while read -r f; do
			echo "${f#$Backup/}"
		done < "$list_file" > "$rel_list"
		if [[ -n $use_sshpass ]]; then
			tar -C "$Backup" -cf - -T "$rel_list" 2>/dev/null \
				| sshpass -p "$remote_pass" ssh $opts "$remote_user@$host" "tar -C '$rpath' -xf -" 2>&1
			tar_rc=$?
		else
			tar -C "$Backup" -cf - -T "$rel_list" 2>/dev/null \
				| ssh $opts "$remote_user@$host" "tar -C '$rpath' -xf -" 2>&1
			tar_rc=$?
		fi
		rm -f "$rel_list"
		if [[ $tar_rc -eq 0 ]]; then
			# 全部成功
			cat "$list_file" >> "$ok_list"
			local n=0
			while read -r f; do
				let n++
				echoRgb "[$n/$total] ✓ ${f#$Backup/}" "1"
			done < "$list_file"
		else
			# tar pipeline 失敗,退回逐檔 scp
			echoRgb "tar pipeline 失敗,退回逐檔 scp" "0"
			use_tar=0
		fi
	fi
	if [[ $use_tar = 0 ]]; then
		# 預掃總目錄數
		local total_dirs done_dirs=0 last_dir="" cur_top=""
		while read -r f; do
			local top="${f#$Backup/}"
			top="${top%%/*}"
			[[ $top = wifi ]] && continue
			echo "$top"
		done < "$list_file" | sort -u > "$TMPDIR/.scp_dirs_count"
		total_dirs="$(wc -l < "$TMPDIR/.scp_dirs_count" 2>/dev/null)"
		rm -f "$TMPDIR/.scp_dirs_count"
		local idx=0
		while read -r f; do
			[[ -z $f ]] && continue
			let idx++
			local rel="${f#$Backup/}"
			cur_top="${rel%%/*}"
			# 目錄切換時印上一個目錄的進度
			if [[ -n $last_dir && $cur_top != "$last_dir" ]]; then
				if [[ $last_dir != wifi && $total_dirs -gt 0 ]]; then
					let done_dirs++
					echoRgb "完成$((done_dirs * 100 / total_dirs))%" "3"
				fi
				echoRgb "上傳目錄 $cur_top" "3"
			elif [[ -z $last_dir ]]; then
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			last_dir="$cur_top"
			local target="$remote_user@$host:$rpath/$rel"
			local scp_rc
			if [[ -n $use_sshpass ]]; then
				sshpass -p "$remote_pass" scp $opts "$f" "$target" >/dev/null 2>&1
				scp_rc=$?
			else
				scp $opts "$f" "$target" >/dev/null 2>&1
				scp_rc=$?
			fi
			if [[ $scp_rc -eq 0 ]]; then
				echo "$f" >> "$ok_list"
				echoRgb "[$idx/$total] ✓ $rel" "1"
			else
				echo "$rel" >> "$fail_list"
				echoRgb "[$idx/$total] ✗ $rel" "0"
				remote_log "FAIL SCP $rel"
			fi
		done < "$list_file"
		# 最後一個目錄(非wifi)的進度
		if [[ -n $last_dir && $last_dir != wifi && $total_dirs -gt 0 ]]; then
			let done_dirs++
			echoRgb "完成$((done_dirs * 100 / total_dirs))%" "3"
		fi
	fi
	rm -f "$list_file" 2>/dev/null
	upload_summary "SCP" "$ok_list" "$fail_list"
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
	ftp)
		local u="${remote_url#ftp://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"; [[ $REMOTE_PORT = $u ]] && REMOTE_PORT=21
		;;
	scp)
		local u="${remote_url#//}"
		if [[ $u = *:* ]]; then REMOTE_HOST="${u%%:*}"
		elif [[ $u = */* ]]; then REMOTE_HOST="${u%%/*}"
		else REMOTE_HOST="$u"; fi
		REMOTE_PORT=22
		;;
	esac
}

# URL percent-encode 路徑中的非 ASCII 字元 (保留 / 分隔符)
# 用 od 取得每個 byte 的 hex, 轉 %XX, 再把 %2F 還原成 /
# 例: "鱼泡网/file.json" → "%E9%B1%BC%E6%B3%A1%E7%BD%91/file.json"
url_encode_path() {
	local s="$1"
	[[ -z $s ]] && { echo ""; return; }
	# printf 避免 echo -n 跨 shell 行為不一致
	printf '%s' "$s" | busybox od -A n -t x1 2>/dev/null | tr -d ' \n' | \
		busybox sed 's/../%&/g; s/%2[fF]/\//g'
}

remote_setup() {
	[[ -z $remote_type ]] && return
	# 規範化 remote_keep_local 成 true/false
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	echoRgb "遠程備份: $remote_type -> $remote_url" "3"
	case $remote_type in
	webdav|ftp|smb|scp)
		;;
	*) echoRgb "未知遠程類型: $remote_type" "0"; remote_type=""; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置，停用遠端上傳" "0"; remote_type=""; return 1; }
	# 事前連線測試: 從各協議解出 host:port 做快速 TCP 探測
	remote_parse_endpoint
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
		if [[ $remote_keep_local = true ]]; then
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
remote_test() {
	echoRgb "============== 遠端連線測試 ==============" "3"
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
	webdav|ftp|smb|scp) ;;
	*) echoRgb "未知 remote_type: $remote_type (可選: webdav/ftp/smb/scp)" "0"; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url 未設置" "0"; return 1; }
	# 第一關: TCP 預檢
	remote_parse_endpoint
	echoRgb "—————— TCP 連線測試 ——————" "3"
	echoRgb "目標: $REMOTE_HOST:$REMOTE_PORT" "2"
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "TCP 連線通過" "1"
	else
		echoRgb "TCP 連線失敗" "0"
		echoRgb "可能原因:" "0"
		echoRgb "  - WiFi 未開啟或不在同網段" "0"
		echoRgb "  - 伺服器 IP / port 寫錯" "0"
		echoRgb "  - 伺服器未啟動 / 防火牆阻擋" "0"
		return 1
	fi
	# 第二關: 認證 + 列目錄
	echoRgb "—————— 認證與列目錄測試 ——————" "3"
	case $remote_type in
	smb)
		local url="${remote_url#smb://}"; url="${url%/}"
		local server="${url%%/*}"
		local after_server="${url#$server/}"
		local share_name="${after_server%%/*}"
		local rem_path="/${after_server#$share_name}"
		rem_path="${rem_path%/}"; [[ $rem_path = / ]] && rem_path=""
		local share="//$server/$share_name"
		local out
		out="$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
			-c "cd ${rem_path:-/}; ls; exit" 2>&1 \
			| grep -Ev '^Try "help"|^dos charset|^Can.t load|^Domain=|^OS=' | sed '/^$/d')"
		if echo "$out" | grep -qE 'NT_STATUS_LOGON_FAILURE'; then
			echoRgb "認證失敗 (帳號或密碼錯誤)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_BAD_NETWORK_NAME'; then
			echoRgb "share 名稱錯誤: $share_name (請檢查伺服器是否有此分享)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端路徑不存在: $rem_path (將在首次上傳時建立)" "3"
		elif echo "$out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "SMB 錯誤:" "0"
			echo "$out" | head -5
			return 1
		else
			echoRgb "認證通過, share 可存取" "1"
			[[ -n $rem_path ]] && echoRgb "遠端路徑 $rem_path 可存取" "1"
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
			*"SSL certificate"*|*"certificate verify"*)
				echoRgb "原因: SSL 證書驗證失敗 (自簽證書或過期)" "0" ;;
			*) echoRgb "詳細: $curl_err" "0" ;;
			esac
			return 1 ;;
		*)   echoRgb "WebDAV 異常 (HTTP $code)" "0"
			[[ -n $curl_err ]] && echoRgb "詳細: $curl_err" "0"
			return 1 ;;
		esac
		;;
	ftp)
		local code
		code="$(curl -sS --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-w '%{http_code}' -o /dev/null "$remote_url" 2>&1)"
		case $code in
		2*|226|250) echoRgb "FTP 認證通過 (回應 $code)" "1" ;;
		530) echoRgb "認證失敗 (530, 帳號或密碼錯誤)" "0"; return 1 ;;
		*)   echoRgb "FTP 異常 (回應 $code)" "0"; return 1 ;;
		esac
		;;
	scp)
		local host="${remote_url#//}" rpath
		if [[ $host = *:* ]]; then rpath="${host#*:}"; host="${host%%:*}"
		elif [[ $host = */* ]]; then rpath="/${host#*/}"; host="${host%%/*}"
		else rpath="/"; fi
		local opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
		local out rc
		if command -v sshpass >/dev/null 2>&1; then
			out="$(sshpass -p "$remote_pass" ssh $opts "$remote_user@$host" "ls -d '$rpath' 2>/dev/null || echo NOPATH" 2>&1)"
			rc="$?"
		else
			out="$(ssh -o BatchMode=yes $opts "$remote_user@$host" "ls -d '$rpath' 2>/dev/null || echo NOPATH" 2>&1)"
			rc="$?"
		fi
		if [[ $rc -ne 0 ]]; then
			echoRgb "SSH 連線失敗" "0"
			echo "$out" | head -3
			[[ -z $(command -v sshpass) ]] && echoRgb "提示: 沒有 sshpass,僅支援密鑰認證" "3"
			return 1
		fi
		echoRgb "SSH 認證通過" "1"
		if echo "$out" | grep -q NOPATH; then
			echoRgb "遠端路徑不存在: $rpath (將在首次上傳時建立)" "3"
		else
			echoRgb "遠端路徑 $rpath 可存取" "1"
		fi
		;;
	esac
	echoRgb "========================================" "3"
	echoRgb "全部測試通過, 可以開始備份" "1"
	return 0
}

remote_cleanup() {
	case $remote_type in
	webdav) upload_remote "webdav" ;;
	ftp) upload_remote "ftp" ;;
	smb) upload_remote "smb" ;;
	scp) upload_remote "scp" ;;
	*) return 0 ;;
	esac
}
# -------- DNS 解析輔助 (ARM curl 繞過) --------
_dns_resolve() {
	local host="$1"
	case $host in
	*[!0-9.]*) ;;
	*) echo "$host"; return 0 ;;
	esac
	if [[ -f $TMPDIR/.dns_cache ]]; then
		local _cached
		_cached=$(awk -v h="$host" -F'\t' '$1 == h {print $2; exit}' "$TMPDIR/.dns_cache" 2>/dev/null)
		[[ -n $_cached ]] && { echo "$_cached"; return 0; }
	fi
	local ip=""
	if command -v nslookup >/dev/null 2>&1; then
		ip=$(nslookup "$host" 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | tail -1)
	fi
	if [[ -z $ip ]] && command -v ping >/dev/null 2>&1; then
		ip=$(ping -c 1 -W 1 "$host" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1)
	fi
	[[ -n $ip ]] && printf '%s\t%s\n' "$host" "$ip" >> "$TMPDIR/.dns_cache"
	echo "$ip"
}
# 覆蓋 curl: 自動透過 --resolve 繞過內建 DNS (解決 ARM curl 二進制解析失敗)
curl() {
	local extra_resolve="" _arg _rest _hp _host _port _ip
	for _arg in "$@"; do
		case $_arg in
		http://*|https://*|ftp://*)
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
			case $_host in
			*[!0-9.]*) ;;
			*) continue ;;
			esac
			_ip=$(_dns_resolve "$_host")
			if [[ -n $_ip && $_ip != "$_host" ]]; then
				extra_resolve="$extra_resolve --resolve $_host:$_port:$_ip"
			fi
			;;
		esac
	done
	if [[ -n $extra_resolve ]]; then
		command curl $extra_resolve "$@"
	else
		command curl "$@"
	fi
}
# -------- URL 輔助函數 --------
url_decode_path() {
	local s="$1"
	local converted
	converted=$(echo "$s" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
	printf '%b' "$converted"
}
speed_calc() {
	local bytes="$1" secs="$2"
	[[ -z $bytes || -z $secs ]] && return
	[[ $secs -le 0 ]] && return
	local _ge_mb _ge_kb
	_ge_mb=$(echo "$bytes >= 1048576" | bc 2>/dev/null)
	_ge_kb=$(echo "$bytes >= 1024" | bc 2>/dev/null)
	if [[ $_ge_mb = 1 ]]; then
		echo "$(echo "scale=2; $bytes / $secs / 1048576" | bc) MB/s"
	elif [[ $_ge_kb = 1 ]]; then
		echo "$(echo "scale=1; $bytes / $secs / 1024" | bc) KB/s"
	elif [[ $bytes -gt 0 ]]; then
		echo "$((bytes / secs)) B/s"
	fi
}
list_total_size() {
	local list="$1"
	[[ ! -f $list ]] && { echo 0; return; }
	awk '{
		cmd="stat -c%s \""$0"\" 2>/dev/null"
		cmd | getline sz
		close(cmd)
		s+=sz+0
	} END{print s+0}' "$list"
}
# -------- SMB 輔助函數 --------
remote_parse_smb_url() {
	local url="${remote_url#smb://}"; url="${url%/}"
	local server="${url%%/*}"
	local after_server="${url#$server/}"
	local share_name="${after_server%%/*}"
	local rem_path="/${after_server#$share_name}"
	rem_path="${rem_path%/}"
	[[ $rem_path = / ]] && rem_path=""
	SMB_SHARE="//$server/$share_name"
	SMB_REM_PATH="$rem_path"
}
smb_filter_noise() {
	echo "$1" | grep -Ev '^Try "help"|^dos charset|^Can.t load|^Domain=|^OS=|^$'
}
dir_has_files() {
	[[ -d $1 ]] || return 1
	[[ -n $(find "$1" -type f -print -quit 2>/dev/null) ]]
}
# -------- SMB 區域網路掃描 --------
scan_smb() {
	local my_ip
	my_ip="$(ip route get 1 2>/dev/null | awk '{print $7; exit}')"
	[[ -z $my_ip ]] && my_ip="$(ifconfig 2>/dev/null | grep -m1 'inet addr:192' | awk '{print $2}' | cut -d: -f2)"
	[[ -z $my_ip ]] && { echoRgb "無法取得本機 IP" "0"; return 1; }
	local subnet="${my_ip%.*}"
	echoRgb "本機 IP: $my_ip" "2"
	echoRgb "掃描 $subnet.0/24 上的 SMB 主機 (445 port)..." "3"
	if ! command -v nc >/dev/null 2>&1; then
		echoRgb "未找到 nc 命令,無法掃描" "0"
		return 1
	fi
	local results="$TMPDIR/.smb_scan_results"
	: > "$results"
	local i pids=""
	for i in $(seq 1 254); do
		local target="$subnet.$i"
		( nc -z -w 1 "$target" 445 >/dev/null 2>&1 && echo "$target" >> "$results" ) &
		pids="$pids $!"
		if [[ $((i % 50)) -eq 0 ]]; then
			wait $pids 2>/dev/null
			pids=""
			echoRgb "  ...已掃描 $i/254" "2"
		fi
	done
	wait $pids 2>/dev/null
	if [[ ! -s $results ]]; then
		echoRgb "未發現 SMB 主機" "0"
		rm -f "$results"
		return 1
	fi
	echoRgb "------- 掃描完成 -------" "3"
	sort -t. -k4 -n "$results" | while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		if command -v nmblookup >/dev/null 2>&1; then
			local hn
			hn="$(nmblookup -A "$target" 2>/dev/null | awk 'NR==2{print $1}' | tr -d '<>\t ')"
			[[ -n $hn ]] && echoRgb "  主機名: $hn" "2"
		fi
		smbclient -L "//$target" -N -t 3 -s /dev/null 2>/dev/null \
			| awk '/Disk/ {print "  共享: "$1}' \
			| while read -r line; do echoRgb "$line" "2"; done
	done
	rm -f "$results"
}
# -------- 單獨上傳 / 上傳當前備份 --------
single_upload() {
	local app_name="$1"
	[[ -z $app_name ]] && { echoRgb "single_upload: 缺少 app 名" "0"; return 1; }
	[[ -z $Backup ]] && Backup="$MODDIR"
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && { echoRgb "找不到目錄: $target" "0"; return 1; }
	dir_has_files "$target" || { echoRgb "$app_name 目錄為空,沒有東西可上傳" "0"; return 1; }
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	case $app_name in
	Media) REMOTE_UPLOAD_MEDIA=1 ;;
	wifi) REMOTE_UPLOAD_WIFI=1 ;;
	*) REMOTE_APPLIST="$app_name" ;;
	esac
	REMOTE_TRIGGER=1
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	echoRgb "—————— 單獨上傳: $app_name ——————" "3"
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	unset REMOTE_TRIGGER
}
upload_current_backup() {
	backup_path
	[[ ! -d $Backup ]] && { echoRgb "本地備份目錄不存在: $Backup" "0"; return 1; }
	echoRgb "本地備份: $Backup" "2"
	local applist=""
	if [[ -n $list_location ]]; then
		if [[ ${list_location:0:1} = / ]]; then
			[[ -f $list_location ]] && applist="$list_location"
		else
			[[ -f $MODDIR/$list_location ]] && applist="$MODDIR/$list_location"
		fi
	fi
	[[ -z $applist && -f $MODDIR/appList.txt ]] && applist="$MODDIR/appList.txt"
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	if [[ -n $applist ]]; then
		REMOTE_APPLIST="$(cat "$applist")"
		local app_count
		app_count=$(echo "$REMOTE_APPLIST" | grep -cEv '^[[:space:]]*[#＃!]|^[[:space:]]*$')
		echoRgb "讀取 $applist (有效 $app_count 個 app)" "2"
	else
		echoRgb "找不到 appList.txt" "0"
	fi
	if [[ -n $Custom_path ]]; then
		if dir_has_files "$Backup/Media"; then
			REMOTE_UPLOAD_MEDIA=1
			echoRgb "Custom_path 已設, 將上傳 Media" "2"
		fi
	fi
	if dir_has_files "$Backup/wifi"; then
		REMOTE_UPLOAD_WIFI=1
		echoRgb "wifi 目錄存在, 將上傳 wifi" "2"
	fi
	if [[ -z $REMOTE_APPLIST && $REMOTE_UPLOAD_MEDIA != 1 && $REMOTE_UPLOAD_WIFI != 1 ]]; then
		echoRgb "沒有可上傳項目 (appList 為空, Custom_path 未設, 無 wifi)" "0"
		return 1
	fi
	REMOTE_TRIGGER=1
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	unset REMOTE_TRIGGER
}
# -------- 列出遠端備份目錄 --------
remote_list_backups() {
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	local target_dir="Backup_${Compression_method}_${user:-0}"
	echoRgb "目標遠端目錄: $target_dir" "3"
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	local sub_listing="$TMPDIR/.remote_sub_listing"
	: > "$sub_listing"
	if [[ $remote_type = smb ]]; then
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local smb_out
		smb_out=$(smbclient "$share" -U "$remote_user%$remote_pass" -t 10 -s /dev/null \
			-c "cd ${rem_path:-/}/$target_dir; ls; exit" 2>&1)
		if echo "$smb_out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端目錄不存在: $target_dir" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			rm -f "$sub_listing"; return 1
		fi
		if echo "$smb_out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "讀取遠端失敗:" "0"
			echo "$smb_out" | grep -E 'NT_STATUS|ERR' | head -3
			rm -f "$sub_listing"; return 1
		fi
		echo "$smb_out" | awk 'NF>=5 && $1 != "." && $1 != ".." {print $2, $1}' > "$sub_listing"
	elif [[ $remote_type = webdav ]]; then
		local base_url="${remote_url%/}"
		local http_code
		http_code=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$TMPDIR/.wdav_out" \
			"$base_url/$target_dir/" 2>/dev/null)
		local dbg_log="$MODDIR/log/webdav_debug.log"
		mkdir -p "$MODDIR/log" 2>/dev/null
		{ echo "===== WebDAV PROPFIND $(date) ====="
		  echo "URL: $base_url/$target_dir/"
		  echo "HTTP code: $http_code"
		  cat "$TMPDIR/.wdav_out" 2>/dev/null; echo ""; } > "$dbg_log"
		case $http_code in
		2*) ;;
		404)
			echoRgb "遠端目錄不存在: $target_dir (HTTP 404)" "0"
			local root_code root_xml="$TMPDIR/.wdav_root"
			root_code=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
				-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$root_xml" "$base_url/" 2>/dev/null)
			case $root_code in
			2*) local found
				found=$(cat "$root_xml" 2>/dev/null | tr '><' '\n' | awk '
					/^(D:)?response$/ { in_resp=1; href="" }
					/^\/(D:)?response$/ { if (in_resp && href != "") print href; in_resp=0 }
					/^(D:)?href$/ { getline href }' | grep -v '^/$' | grep -v "^${base_url#http*://*/}$")
				[[ -n $found ]] && echoRgb "遠端根目錄實際有以下項目:" "3" && echo "$found" | head -20 ;;
			esac
			rm -f "$root_xml"
			echoRgb "原始回應已記錄: $dbg_log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		*) echoRgb "讀取遠端失敗 (HTTP $http_code)" "0"
			echoRgb "原始回應已記錄: $dbg_log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out"; return 1 ;;
		esac
		local propfind_out
		propfind_out=$(cat "$TMPDIR/.wdav_out" 2>/dev/null); rm -f "$TMPDIR/.wdav_out"
		local raw_listing="$TMPDIR/.raw_wdav_listing"
		echo "$propfind_out" | tr '><' '\n' | awk '
			{ tag = $1; sub(/^D:/,"",tag); sub(/^\/D:/,"/",tag); sub(/\/$/,"",tag) }
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					n = split(href, a, "/"); name = a[n]
					if (name == "" && n > 1) name = a[n-1]
					if (name != "" && name != "/") print (is_dir ? "D" : "N") "|" name
				}
				in_resp=0; next
			}
			tag == "href" { getline href; next }
			tag == "collection" { is_dir=1 }
		' > "$raw_listing"
		grep -vE "\|${target_dir}\$" "$raw_listing" > "$sub_listing"
		rm -f "$raw_listing"
		local decoded="$TMPDIR/.decoded_listing"
		: > "$decoded"
		while IFS='|' read -r typ name; do
			[[ -z $name ]] && continue
			local converted
			converted=$(echo "$name" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
			local real
			real=$(printf '%b' "$converted")
			echo "$typ $real" >> "$decoded"
		done < "$sub_listing"
		mv "$decoded" "$sub_listing"
	fi
	if [[ ! -s $sub_listing ]]; then
		echoRgb "遠端目錄為空或讀取失敗" "0"
		rm -f "$sub_listing"; return 1
	fi
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
		rm -f "$sub_listing"; return 1
	fi
	echoRgb "必要檔案檢查通過 (tools/ start.sh restore_settings.conf)" "1"
	local out="$MODDIR/appList_network.txt"
	{
		echo "# 遠端備份目錄: $target_dir"
		echo "# 連線: $remote_type://$REMOTE_HOST/"
		echo "# 用 # 註解掉不要下載的項目, 編輯完選 '從遠端下載備份' 即可"
		echo ""
		echo "# ---- 應用 (每行一個 app) ----"
		local apps="$TMPDIR/.apps_list"
		: > "$apps"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in tools|wifi|Media) continue ;; esac
			echo "$name" >> "$apps"
		done < "$sub_listing"
		sort "$apps"
		rm -f "$apps"
		echo ""
		echo "# ---- 特殊項目 (非 app, 有就會下載) ----"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in wifi|Media) echo "$name" ;; esac
		done < "$sub_listing"
	} > "$out"
	rm -f "$sub_listing"
	echoRgb "已輸出清單: $out" "1"
	echoRgb "請編輯該檔案,留下你要下載的項目,然後選 '從遠端下載備份'" "3"
}
# -------- 從遠端下載備份 --------
remote_download_backup() {
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
	local chosen="Backup_${Compression_method}_${user:-0}"
	echoRgb "目標遠端目錄: $chosen" "3"
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	local items_file="$TMPDIR/.dl_items"
	grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$list" > "$items_file"
	if [[ ! -s $items_file ]]; then
		echoRgb "清單為空,沒有東西需要下載" "0"
		rm -f "$items_file"; return 1
	fi
	local item_count
	item_count=$(wc -l < "$items_file")
	echoRgb "將下載 $item_count 個項目 + 固定 3 項 (tools/ start.sh restore_settings.conf)" "3"
	local dest="$MODDIR/$chosen"
	mkdir -p "$dest" 2>/dev/null
	echoRgb "下載到: $dest" "2"
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
_remote_download_smb() {
	local chosen="$1" dest="$2" items_file="$3"
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	local SMB_OPTS="-t 30 -s /dev/null"
	local base="${rem_path:+$rem_path/}$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local idx=0 fail_total=0
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		echoRgb "[$idx/$total_items] 下載 $item" "3"
		mkdir -p "$dest/$item" 2>/dev/null
		local out
		out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
			-D "$base/$item" \
			-c "lcd $dest/$item; prompt off; recurse on; mget *; exit" 2>&1)
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_[A-Z_]+' \
			|| [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "  ✗ $item" "0"
			echo "$out" | grep -E 'NT_STATUS' | head -3
			let fail_total++
		else
			echoRgb "  ✓ $item" "1"
		fi
	done < "$items_file"
	echoRgb "下載固定項目: tools/ start.sh restore_settings.conf" "3"
	mkdir -p "$dest/tools" 2>/dev/null
	local tools_out
	tools_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base/tools" \
		-c "lcd $dest/tools; prompt off; recurse on; mget *; exit" 2>&1)
	tools_out="$(smb_filter_noise "$tools_out")"
	local fix_out
	fix_out=$(smbclient "$share" -U "$remote_user%$remote_pass" $SMB_OPTS \
		-D "$base" \
		-c "lcd $dest; prompt off; get start.sh; get restore_settings.conf; exit" 2>&1)
	fix_out="$(smb_filter_noise "$fix_out")"
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "  固定項目下載有錯誤" "0"
		echo "$tools_out $fix_out" | grep -E 'NT_STATUS' | head -5
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "  tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "  start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "  restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "  ✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}
_remote_download_webdav() {
	local chosen="$1" dest="$2" items_file="$3"
	local base_url="${remote_url%/}/$chosen"
	local total_items
	total_items=$(wc -l < "$items_file")
	local fail_total=0
	_webdav_scan_files() {
		local r_url="$1" l_dir="$2" out_list="$3"
		mkdir -p "$l_dir" 2>/dev/null
		local out
		out=$(curl -sS -L --http1.1 --connect-timeout 10 -u "$remote_user:$remote_pass" \
			-X PROPFIND -H "Depth: 1" "$r_url/" 2>/dev/null)
		local parsed="$TMPDIR/.wdav_scan_$$"
		echo "$out" | tr '><' '\n' | awk '
			{ tag = $1; sub(/^D:/,"",tag); sub(/^\/D:/,"/",tag); sub(/\/$/,"",tag) }
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					print (is_dir ? "D" : "F") "\t" href
				}
				in_resp=0; next
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
				echo -e "$r_url/$encoded_name\t$l_dir/$name" >> "$out_list"
			fi
		done < "$parsed"
		rm -f "$parsed"
		return $rc
	}
	_webdav_parallel_get() {
		local list="$1"
		[[ ! -s $list ]] && return 0
		local cfg="$TMPDIR/.curl_cfg_$$"
		: > "$cfg"
		while IFS=$'\t' read -r url lpath; do
			echo "url = \"$url\"" >> "$cfg"
			echo "output = \"$lpath\"" >> "$cfg"
		done < "$list"
		curl -sS -L --http1.1 --connect-timeout 10 --retry 2 -Z --parallel-max 4 \
			-u "$remote_user:$remote_pass" -K "$cfg" 2>/dev/null
		local rc=$?
		rm -f "$cfg"
		return $rc
	}
	local all_files="$TMPDIR/.wdav_all_files"
	: > "$all_files"
	local idx=0 scan_fail=0
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		local encoded_item
		encoded_item=$(url_encode_path "$item")
		[[ -z $encoded_item ]] && encoded_item="$item"
		echoRgb "[$idx/$total_items] 掃描 $item" "3"
		if ! _webdav_scan_files "$base_url/$encoded_item" "$dest/$item" "$all_files"; then
			echoRgb "  ✗ 掃描失敗: $item" "0"
			scan_fail=1; let fail_total++
		fi
	done < "$items_file"
	echoRgb "掃描固定項目: tools/" "3"
	if ! _webdav_scan_files "$base_url/tools" "$dest/tools" "$all_files"; then
		echoRgb "  ✗ 掃描失敗: tools/" "0"
		scan_fail=1; let fail_total++
	fi
	for f in start.sh restore_settings.conf; do
		echo -e "$base_url/$f\t$dest/$f" >> "$all_files"
	done
	local total_files
	total_files=$(wc -l < "$all_files")
	echoRgb "並行下載 $total_files 個檔案 (4 路同時)" "3"
	_webdav_parallel_get "$all_files"
	rm -f "$all_files"
	while read -r item; do
		[[ -z $item ]] && continue
		if [[ -z "$(ls -A "$dest/$item" 2>/dev/null)" ]]; then
			echoRgb "  ✗ $item (本地為空)" "0"
			let fail_total++
		else
			echoRgb "  ✓ $item" "1"
		fi
	done < "$items_file"
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "  固定項目下載有錯誤" "0"
		[[ -z "$(ls -A "$dest/tools" 2>/dev/null)" ]] && echoRgb "  tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "  start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "  restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "  ✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>/dev/null
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>/dev/null
	[[ $fail_total -eq 0 ]]
}
