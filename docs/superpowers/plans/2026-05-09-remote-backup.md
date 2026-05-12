# Remote Backup (WebDAV & SMB) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WebDAV upload and SMB mount backup support to the backup script using built-in busybox tools.

**Architecture:** Four config variables in `backup_settings.conf` control remote backup. Five new functions in `tools/tools.sh` handle SMB mount/unmount and WebDAV upload. A single hook in `backup_path()` triggers remote setup. The existing EXIT trap is extended to handle remote cleanup.

**Tech Stack:** Shell script (Android mksh compatible), busybox (wget, mount, umount)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `backup_settings.conf` | Append | Remote backup configuration |
| `tools/tools.sh` | Modify | Remote backup functions + hook + trap extension |

---

### Task 1: Add remote config to backup_settings.conf

**Files:**
- Modify: `backup_settings.conf`

- [ ] **Step 1: Append remote backup configuration**

Append after line 123 (`rgb_c=177`), before the trailing newline at line 124:

```conf

#遠程備份類型 (留空不啟用)
#webdav 或 smb
remote_type=

#遠程地址
#WebDAV例: http://192.168.1.100:8080/dav/
#SMB例:    //192.168.1.100/backup
remote_url=

#遠程認證用戶名
remote_user=

#遠程認證密碼
remote_pass=
```

Edit command: Use the Edit tool to append these lines after `rgb_c=177`.

- [ ] **Step 2: Verify config file**

Run: Read `backup_settings.conf` lines 120-140 to confirm the config lines are present.

- [ ] **Step 3: Commit**

```bash
git add backup_settings.conf
git commit -m "feat: add remote backup config (remote_type, remote_url, remote_user, remote_pass)"
```

---

### Task 2: Add remote backup functions to tools.sh

**Files:**
- Modify: `tools/tools.sh` (insert after line 465, before `Show_boottime` at line 466)

- [ ] **Step 1: Insert remote functions**

Insert after line 465 (`kill_Serve` call) and before line 466 (`Show_boottime()`):

```sh
# -------- 遠程備份功能 --------
mount_smb() {
	local mnt="$TMPDIR/smb_mount"
	mkdir -p "$mnt"
	if busybox mount -t cifs "$remote_url" "$mnt" -o "username=$remote_user,password=$remote_pass,iocharset=utf8,vers=2.0" 2>/dev/null; then
		SMB_MOUNT="$mnt"
		[[ $(mount | grep "$mnt") != "" ]] || { echoRgb "SMB掛載失敗: $remote_url" "0"; return 1; }
		echoRgb "SMB已掛載: $remote_url -> $mnt" "1"
		return 0
	fi
	echoRgb "SMB掛載失敗，回退本地備份" "0"
	return 1
}

umount_smb() {
	[[ -n $SMB_MOUNT ]] && {
		busybox umount -l "$SMB_MOUNT" 2>/dev/null
		rm -rf "$SMB_MOUNT"
		unset SMB_MOUNT
		echoRgb "SMB已卸載" "2"
	}
}

upload_webdav() {
	local base_url="${remote_url%/}"
	local auth=$(echo -n "$remote_user:$remote_pass" | busybox base64)
	local failed=0
	local list_file="$TMPDIR/.wdav_list"
	find "$Backup" -type f > "$list_file"
	while read -r f; do
		[[ -z $f ]] && continue
		local rel="${f#$Backup/}"
		echoRgb "上傳: $rel" "2"
		if busybox wget -q --method PUT --body-file="$f" --header "Authorization: Basic $auth" "$base_url/$rel" 2>/dev/null; then
			rm -f "$f"
		else
			failed=1
			break
		fi
	done < "$list_file"
	rm -f "$list_file"
	if [[ $failed -eq 0 ]]; then
		echoRgb "WebDAV上傳完成" "1"
	else
		echoRgb "WebDAV上傳失敗，本地檔案已保留" "0"
		return 1
	fi
}

remote_setup() {
	[[ -z $remote_type ]] && return

	case $remote_type in
	smb)
		mount_smb || return
		Backup="$SMB_MOUNT/Backup_${Compression_method}_$user"
		mkdir -p "$Backup"
		Backup_path="${Backup%/*}"
		Output_path=""
		echoRgb "遠程備份目錄: $Backup" "3"
		;;
	webdav)
		echoRgb "WebDAV模式: 備份完成後將自動上傳" "3"
		;;
	esac
}

remote_cleanup() {
	case $remote_type in
	smb) umount_smb ;;
	webdav) upload_webdav ;;
	esac
}
```

- [ ] **Step 2: Verify insertion**

Run: Read `tools/tools.sh` lines 464-550 to confirm functions are inserted correctly and `Show_boottime()` follows.

- [ ] **Step 3: Commit**

```bash
git add tools/tools.sh
git commit -m "feat: add remote backup functions (mount_smb, umount_smb, upload_webdav, remote_setup, remote_cleanup)"
```

---

### Task 3: Wire hook and trap

**Files:**
- Modify: `tools/tools.sh` (line 462 and line 991-993)

- [ ] **Step 1: Modify EXIT trap in kill_Serve**

Change line 462 from:
```sh
    trap "rm -rf '$LOCK_DIR'" EXIT
```
to:
```sh
    trap "rm -rf '$LOCK_DIR'; remote_cleanup" EXIT
```

- [ ] **Step 2: Add remote_setup call at end of backup_path()**

Change line 991-993 from:
```sh
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
}
```
to:
```sh
	echoRgb "$hx備份資料夾所使用分區統計如下↓\n -$(df -h "${Backup%/*}" | sed -n 's|% /.*|%|p' | awk '{print $(NF-3),$(NF-2),$(NF-1),$(NF)}' | awk 'END{print "總共:"$1"已用:"$2"剩餘:"$3"使用率:"$4}')檔案系統:$(df -T "$Backup_path" | sed -n 's|% /.*|%|p' | awk '{print $(NF-4)}')\n -備份目錄輸出位置↓\n -$Backup"
	echoRgb "$outshow" "2"
	remote_setup
}
```

- [ ] **Step 3: Verify EXIT trap**

Run: Read `tools/tools.sh` line 462 to confirm the trap includes `remote_cleanup`.

- [ ] **Step 4: Verify hook**

Run: Read `tools/tools.sh` lines 989-994 to confirm `remote_setup` is inside `backup_path()` before the closing `}`.

- [ ] **Step 5: Commit**

```bash
git add tools/tools.sh
git commit -m "feat: wire remote backup hook and EXIT trap"
```

---

### Task 4: Verify changes

**Files:**
- Check: `tools/tools.sh`, `backup_settings.conf`

- [ ] **Step 1: Verify git diff**

```bash
git diff master
```

Expected: ~80 lines added across 2 files:
- `backup_settings.conf`: +9 lines (remote config)
- `tools/tools.sh`: +~70 lines (functions, trap modification, hook), 1 line modified (trap), 1 line added (hook call)

- [ ] **Step 2: Verify no syntax errors in shell script**

```bash
bash -n tools/tools.sh
```

Ignore "not found" warnings for Android-specific tools — we're only checking syntax.

- [ ] **Step 3: Verify function names don't collide**

```bash
Select-String -Pattern "^(mount_smb|umount_smb|upload_webdav|remote_setup|remote_cleanup)\b" -Path tools/tools.sh
```

Expected: Each function name appears once (definition only, not duplicated).

- [ ] **Step 4: Commit any fixes if needed**

```bash
git add -A && git commit -m "fix: address verification issues"
```
