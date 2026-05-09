# Remote Backup (WebDAV & SMB) 设计文档

**日期:** 2026-05-09  
**目标:** 在不涉及大范围改动的前提下，为脚本增加备份到远程 WebDAV 和 SMB 的功能。

---

## 需求

- 支持直接备份到远程 WebDAV 和 SMB 设备
- 使用脚本内置 busybox，不依赖额外工具
- 配置通过 `backup_settings.conf`
- 最小化对现有代码的改动

---

## 架构

### 配置

在 `backup_settings.conf` 末尾追加 4 个配置项：

```conf
#远程备份类型 (留空不启用)
#webdav 或 smb
remote_type=

#远程地址
#WebDAV例: http://192.168.1.100:8080/dav/
#SMB例:    //192.168.1.100/backup
remote_url=

#远程认证用户名
remote_user=

#远程认证密码
remote_pass=
```

### 新增函数（tools/tools.sh）

所有函数定义在 `tools/tools.sh` 中，靠近 `kill_Serve()` 之后的位置（~line 465）。

| 函数 | 行数 | 说明 |
|------|------|------|
| `mount_smb()` | ~10 | busybox `mount -t cifs` 挂载 SMB 到 `$TMPDIR/smb_mount` |
| `umount_smb()` | ~5 | 安全卸载 SMB 挂载点 |
| `upload_webdav()` | ~20 | 遍历备份目录，用 busybox `wget --method PUT` 逐个上传 |
| `remote_setup()` | ~25 | 入口函数：SMB 挂载后设置 Output_path；WebDAV 注册 trap |
| `remote_cleanup()` | ~15 | SMB 卸载 / WebDAV 上传+清理本地文件 |

### Hook 点

在 `backup_path()` 调用之后（line 991 附近）插入一行：

```sh
remote_setup
```

### 流程

```
backup_path()      # 确定本地备份路径 $Backup
       ↓
remote_setup()     # 如启用远程，挂载 SMB 或准备 WebDAV uploader
       ↓
  [SMB]            [WebDAV]
  mount_smb()      正常本地备份
  $Backup → mount    ↓
  正常备份         upload_webdav() (at EXIT)
    ↓              rm -rf 本地副本
  umount_smb()
```

### SMB 实现细节

```sh
mount_smb() {
    local mnt="$TMPDIR/smb_mount"
    mkdir -p "$mnt"
    busybox mount -t cifs "$remote_url" "$mnt" -o "username=$remote_user,password=$remote_pass,iocharset=utf8"
    # 若 busybox mount 不支持 cifs，尝试系统 mount
    # 失败则返回非0，remote_setup 回退到本地备份
}
```

挂载成功后，`remote_setup()` 将 `$Backup` 覆盖为 `$mnt/Backup_${Compression_method}_$user`，后续备份流程无需修改。

### WebDAV 实现细节

```sh
upload_webdav() {
    local base_url="${remote_url%/}"
    # 创建远程目录 (MKCOL)
    busybox wget -q --method MKCOL --header "Authorization: ..." "$base_url/..." 2>/dev/null
    # 遍历上传
    find "$Backup" -type f | while read f; do
        busybox wget -q --method PUT --body-file="$f" --header "Authorization: ..." "$base_url/..."
        # 上传成功才删除本地文件
    done
}
```

备份先写到本地（正常流程），EXIT 时 `remote_cleanup()` 触发上传，成功后删除本地副本。

### 错误处理

- SMB 挂载失败：回退到本地备份（echo 警告，继续执行）
- WebDAV 上传失败：保留本地文件不删除（保留数据，用户手动排查）
- SMB 连接断开：trap EXIT 确保 `umount_smb()` 被调用
- 网络异常：wget 自带超时，不会永久阻塞

### 恢复支持（后续迭代）

本次仅实现备份到远程。恢复从远程可在后续 PR 中补充，方向是对称实现：
- SMB：挂载后从挂载点恢复
- WebDAV：wget 下载到临时目录后恢复

---

## 改动范围

| 文件 | 改动 |
|------|------|
| `backup_settings.conf` | +9 行配置 |
| `tools/tools.sh` | +75 行（5 个函数 + 1 个 hook 调用） |

---

## 测试要点

1. SMB 挂载成功 → 备份文件出现在远程共享目录
2. SMB 挂载失败 → 回退到本地备份，有警告提示
3. WebDAV 上传成功 → 远程有备份文件，本地副本已清理
4. WebDAV 上传失败 → 本地文件保留，有错误提示
5. EXIT 时 SMB 挂载点被正确卸载（无残留）
