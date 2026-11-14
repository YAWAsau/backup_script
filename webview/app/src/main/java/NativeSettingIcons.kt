package io.github.yawasau.speedbackup.webview

import androidx.compose.runtime.*
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.vector.*
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.DeveloperBoard
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Store
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Help
import top.yukonga.miuix.kmp.icon.extended.File
import top.yukonga.miuix.kmp.icon.extended.Stopwatch
import top.yukonga.miuix.kmp.icon.extended.Timer
import top.yukonga.miuix.kmp.icon.extended.Store
import androidx.compose.material.icons.automirrored.filled.AddToHomeScreen
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.BlurOn
import androidx.compose.material.icons.filled.BrightnessAuto
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.ColorLens
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.DashboardCustomize
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DriveFileRenameOutline
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderZip
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.InstallMobile
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.automirrored.filled.ManageSearch
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Opacity
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.ScreenLockPortrait
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Style
import androidx.compose.material.icons.filled.DesignServices
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Wallpaper
import top.yukonga.miuix.kmp.icon.extended.Background
import top.yukonga.miuix.kmp.icon.extended.Backup
import top.yukonga.miuix.kmp.icon.extended.Blocklist
import top.yukonga.miuix.kmp.icon.extended.CloudFill
import top.yukonga.miuix.kmp.icon.extended.Contacts
import top.yukonga.miuix.kmp.icon.extended.Download
import top.yukonga.miuix.kmp.icon.extended.Folder
import top.yukonga.miuix.kmp.icon.extended.GridView
import top.yukonga.miuix.kmp.icon.extended.Home
import top.yukonga.miuix.kmp.icon.extended.Info
import top.yukonga.miuix.kmp.icon.extended.Layers
import top.yukonga.miuix.kmp.icon.extended.Link
import top.yukonga.miuix.kmp.icon.extended.ListView
import top.yukonga.miuix.kmp.icon.extended.Lock
import top.yukonga.miuix.kmp.icon.extended.Messages
import top.yukonga.miuix.kmp.icon.extended.Notes
import top.yukonga.miuix.kmp.icon.extended.Phone
import top.yukonga.miuix.kmp.icon.extended.Rename
import top.yukonga.miuix.kmp.icon.extended.Reset
import top.yukonga.miuix.kmp.icon.extended.SearchDevice
import top.yukonga.miuix.kmp.icon.extended.Theme
import top.yukonga.miuix.kmp.icon.extended.Translate
import top.yukonga.miuix.kmp.icon.extended.Update
import top.yukonga.miuix.kmp.icon.extended.UploadCloud

// RAM module silhouette, distinct from the processor chip in both visual systems.
private val materialRamIcon by lazy {
    ImageVector.Builder("SpeedBackup.Material.Ram",24.dp,24.dp,24f,24f).apply {
        addPath(pathData=addPathNodes("M3 6 H21 Q22 6 22 7 V16 H20 V19 H18 V16 H16 V19 H14 V16 H10 V19 H8 V16 H6 V19 H4 V16 H2 V7 Q2 6 3 6 Z M5 9 V13 H8 V9 Z M10 9 V13 H14 V9 Z M16 9 V13 H19 V9 Z"),fill=SolidColor(Color.Black),pathFillType=PathFillType.EvenOdd)
    }.build()
}

internal val LocalNativeSettingIcon = staticCompositionLocalOf { "" }
internal val nativeSettingIconLabels=mapOf(
    "低電量提示" to "low_battery_mode",
    "後台執行" to "background_execution",
    "遠程關機" to "pc_auto_shutdown",
    "顯示通知" to "notification_enable",
    "語言" to "Shell_LANG",
    "亮屏偽裝" to "setDisplayPowerMode",
    "腳本自更新" to "update",
    "更新節點" to "cdn",
    "使用者" to "user",
    "終端主題色" to "rgb_a",
    "終端輔色" to "rgb_b",
    "終端輔色2" to "rgb_c",
    "日誌大小上限" to "log_max_size_mb",
    "本地備份目錄位置" to "Output_path",
    "應用列表位置" to "list_location",
    "屏蔽掛載干擾" to "mount_point",
    "文件夾備份" to "Custom_path",
    "黑名單" to "blacklist",
    "白名單" to "whitelist",
    "系統應用" to "system",
    "備份目錄名稱定義" to "Backup_suffix",
    "壓縮格式" to "Compression_method",
    "壓縮線程" to "Zstd_threads",
    "壓縮等級" to "Zstd_level",
    "減少執行緒" to "Zstd_small_max_bytes",
    "預設備份模式" to "Backup_Mode",
    "自訂資料夾備份" to "backup_media",
    "備份obb數據" to "Backup_obb_data",
    "備份user數據" to "Backup_user_data",
    "備份通話記錄" to "backup_calllogs",
    "備份簡訊紀錄" to "backup_messages",
    "忽略進程" to "Background_apps_ignore",
    "備份方式" to "remote_type",
    "smb地址" to "smb_url",
    "smb用戶名" to "smb_remote_user",
    "smb密碼" to "smb_remote_pass",
    "webdav地址" to "webdav_url",
    "webdav用戶名稱" to "webdav_remote_user",
    "webdav密碼" to "webdav_remote_pass",
    "遠程數據交換方式" to "remote_stream",
    "非串流檔案處理方式" to "remote_keep_local",
    "非串流應用上傳方式" to "remote_upload_per_app",
    "恢復方式" to "recovery_mode",
    "黑名單模式" to "blacklist_mode",
    "小檔案壓縮線程" to "Zstd_small_threads",
    "壓縮大小提示" to "Zstd_size_hint",
    "恢復自訂資料夾" to "media_recovery",
    "恢復簡訊紀錄" to "restore_messages",
    "恢復通話記錄" to "restore_calllogs",
    "允許安裝舊版應用" to "restore_allow_low_target_sdk",
    "SMB／WebDAV 自動發現地址" to "remote_address_mode",
    "備份設定" to "backup-settings",
    "恢復設定" to "restore-settings",
    "壁紙" to "wallpaper",
    "介面風格" to "style",
    "介面語言" to "language",
    "外觀" to "appearance",
    "調色盤風格" to "material-palette",
    "色彩規格" to "material-spec",
    "顯示大小" to "scale",
    "字體自適應" to "font-adaptive",
    "高斯模糊" to "glass-blur",
    "莫奈動態配色" to "monet",
    "自適應玻璃亮度" to "glass-adaptive",
    "玻璃透視內容" to "glass-content",
    "模糊程度" to "glass-blur-strength",
    "透光強度" to "glass-light",
    "透明度" to "glass-transparency",
    "折射強度" to "glass-refraction",
    "恢復玻璃預設" to "reset",
    "關於" to "about",
    "Daemon 狀態" to "daemon",
    "日誌" to "logs",
    "建立桌面捷徑" to "shortcut",
    "自動發現電腦／NAS" to "discovery",
    "WebDAV／NAS 範本" to "preset")
private fun materialSettingIcon(key:String):ImageVector?=when(key){
    "credits" -> Icons.Filled.Person
    "licenses" -> Icons.Filled.Description
    "source" -> Icons.Filled.Code
    "community" -> Icons.Filled.Sms
    "log-source" -> Icons.Filled.Layers
    "log-session" -> Icons.Filled.Schedule
    "log-level" -> Icons.Filled.Tune
    "log-export" -> Icons.Filled.CloudUpload
    "daemon" -> Icons.Filled.Memory
    "shortcut" -> Icons.AutoMirrored.Filled.AddToHomeScreen
    "system" -> Icons.Filled.Android
    "Backup_Mode","backup-settings" -> Icons.Filled.Backup
    "low_battery_mode" -> Icons.Filled.BatteryAlert
    "blacklist","blacklist_mode" -> Icons.Filled.Block
    "glass-blur","glass-blur-strength" -> Icons.Filled.BlurOn
    "glass-adaptive" -> Icons.Filled.BrightnessAuto
    "backup_calllogs","restore_calllogs" -> Icons.Filled.Call
    "whitelist" -> Icons.Filled.Checklist
    "remote_type" -> Icons.Filled.Cloud
    "remote_upload_per_app" -> Icons.Filled.CloudUpload
    "material-spec" -> Icons.Filled.DesignServices
    "appearance" -> Icons.Filled.Contrast
    "preset" -> Icons.Filled.DashboardCustomize
    "log_max_size_mb","logs" -> Icons.Filled.Description
    "cdn" -> Icons.Filled.Download
    "Backup_suffix" -> Icons.Filled.DriveFileRenameOutline
    "Output_path","Custom_path","backup_media","media_recovery" -> Icons.Filled.Folder
    "Compression_method","Zstd_threads","Zstd_level","Zstd_small_max_bytes","Zstd_small_threads","Zstd_size_hint" -> Icons.Filled.FolderZip
    "scale" -> Icons.Filled.FormatSize
    "about" -> Icons.Filled.Info
    "restore_allow_low_target_sdk" -> Icons.Filled.InstallMobile
    "Backup_obb_data","Backup_user_data" -> Icons.Filled.Inventory2
    "background_execution","Background_apps_ignore","glass-content" -> Icons.Filled.Layers
    "glass-light" -> Icons.Filled.LightMode
    "smb_url","webdav_url" -> Icons.Filled.Link
    "list_location" -> Icons.AutoMirrored.Filled.List
    "smb_remote_pass","webdav_remote_pass" -> Icons.Filled.Lock
    "remote_address_mode","discovery" -> Icons.AutoMirrored.Filled.ManageSearch
    "notification_enable" -> Icons.Filled.Notifications
    "glass-transparency" -> Icons.Filled.Opacity
    "rgb_a","rgb_b","rgb_c","monet" -> Icons.Filled.Palette
    "material-palette" -> Icons.Filled.Style
    "user","smb_remote_user","webdav_remote_user" -> Icons.Filled.Person
    "pc_auto_shutdown" -> Icons.Filled.PowerSettingsNew
    "recovery_mode","restore-settings","reset" -> Icons.Filled.Restore
    "remote_keep_local" -> Icons.Filled.Save
    "setDisplayPowerMode" -> Icons.Filled.ScreenLockPortrait
    "backup_messages","restore_messages" -> Icons.Filled.Sms
    "mount_point" -> Icons.Filled.Storage
    "style" -> Icons.Filled.Style
    "remote_stream" -> Icons.Filled.SyncAlt
    "update" -> Icons.Filled.SystemUpdate
    "font-adaptive" -> Icons.Filled.TextFields
    "Shell_LANG","language" -> Icons.Filled.Translate
    "glass-refraction" -> Icons.Filled.Tune
    "wallpaper" -> Icons.Filled.Wallpaper
    "brand" -> Icons.Filled.Store
    "model" -> Icons.Filled.Smartphone
    "processor" -> Icons.Filled.Memory
    "memory" -> materialRamIcon
    "storage" -> Icons.Filled.Storage
    "android" -> Icons.Filled.Android
    "kernel" -> Icons.Filled.DeveloperBoard
    "selinux" -> Icons.Filled.Security
    "runtime" -> Icons.Filled.Schedule
    "uptime" -> Icons.Filled.Timer
    "sleep" -> Icons.Filled.Bedtime
    "script-version" -> Icons.Filled.Code
    "manager" -> Icons.Filled.Apps
    "busybox-version" -> Icons.Filled.Terminal
    "busybox-path" -> Icons.Filled.Folder
    "script-path" -> Icons.Filled.Folder
    "author" -> Icons.Filled.Person
    "support" -> Icons.AutoMirrored.Filled.Help
    "unknown" -> Icons.Filled.Info
    else->null
}
private fun miuixSettingIcon(key:String):ImageVector?=when(key){
    "credits" -> MiuixIcons.Contacts
    "licenses" -> MiuixIcons.Notes
    "source" -> MiuixIcons.File
    "community" -> MiuixIcons.Messages
    "log-source" -> MiuixIcons.Layers
    "log-session" -> supplementalMiuixIcon("Restore")
    "log-level" -> supplementalMiuixIcon("Tune")
    "log-export" -> MiuixIcons.UploadCloud
    "daemon" -> supplementalMiuixIcon("Memory")
    "low_battery_mode" -> supplementalMiuixIcon("BatteryAlert")
    "background_execution" -> MiuixIcons.Layers
    "pc_auto_shutdown" -> supplementalMiuixIcon("PowerSettingsNew")
    "notification_enable" -> supplementalMiuixIcon("Notifications")
    "Shell_LANG" -> MiuixIcons.Translate
    "setDisplayPowerMode" -> supplementalMiuixIcon("ScreenLockPortrait")
    "update" -> MiuixIcons.Update
    "cdn" -> MiuixIcons.Download
    "user" -> MiuixIcons.Contacts
    "rgb_a" -> MiuixIcons.Theme
    "rgb_b" -> MiuixIcons.Theme
    "rgb_c" -> MiuixIcons.Theme
    "log_max_size_mb" -> MiuixIcons.Notes
    "Output_path" -> MiuixIcons.Folder
    "list_location" -> MiuixIcons.ListView
    "mount_point" -> supplementalMiuixIcon("Storage")
    "Custom_path" -> MiuixIcons.Folder
    "blacklist" -> MiuixIcons.Blocklist
    "whitelist" -> supplementalMiuixIcon("Checklist")
    "system" -> supplementalMiuixIcon("Android")
    "Backup_suffix" -> MiuixIcons.Rename
    "Compression_method" -> supplementalMiuixIcon("FolderZip")
    "Zstd_threads" -> supplementalMiuixIcon("FolderZip")
    "Zstd_level" -> supplementalMiuixIcon("FolderZip")
    "Zstd_small_max_bytes" -> supplementalMiuixIcon("FolderZip")
    "Backup_Mode" -> MiuixIcons.Backup
    "backup_media" -> MiuixIcons.Folder
    "Backup_obb_data" -> supplementalMiuixIcon("Inventory2")
    "Backup_user_data" -> supplementalMiuixIcon("Inventory2")
    "backup_calllogs" -> MiuixIcons.Phone
    "backup_messages" -> MiuixIcons.Messages
    "Background_apps_ignore" -> MiuixIcons.Layers
    "remote_type" -> MiuixIcons.CloudFill
    "smb_url" -> MiuixIcons.Link
    "smb_remote_user" -> MiuixIcons.Contacts
    "smb_remote_pass" -> MiuixIcons.Lock
    "webdav_url" -> MiuixIcons.Link
    "webdav_remote_user" -> MiuixIcons.Contacts
    "webdav_remote_pass" -> MiuixIcons.Lock
    "remote_stream" -> supplementalMiuixIcon("SyncAlt")
    "remote_keep_local" -> supplementalMiuixIcon("Save")
    "remote_upload_per_app" -> MiuixIcons.UploadCloud
    "recovery_mode" -> supplementalMiuixIcon("Restore")
    "blacklist_mode" -> MiuixIcons.Blocklist
    "Zstd_small_threads" -> supplementalMiuixIcon("FolderZip")
    "Zstd_size_hint" -> supplementalMiuixIcon("FolderZip")
    "media_recovery" -> MiuixIcons.Folder
    "restore_messages" -> MiuixIcons.Messages
    "restore_calllogs" -> MiuixIcons.Phone
    "restore_allow_low_target_sdk" -> supplementalMiuixIcon("InstallMobile")
    "remote_address_mode" -> MiuixIcons.SearchDevice
    "backup-settings" -> MiuixIcons.Backup
    "restore-settings" -> supplementalMiuixIcon("Restore")
    "wallpaper" -> MiuixIcons.Background
    "style" -> MiuixIcons.Theme
    "language" -> MiuixIcons.Translate
    "appearance" -> MiuixIcons.Theme
    "material-palette" -> supplementalMiuixIcon("Palette")
    "material-spec" -> supplementalMiuixIcon("ColorLens")
    "scale" -> supplementalMiuixIcon("FormatSize")
    "font-adaptive" -> supplementalMiuixIcon("TextFields")
    "glass-blur" -> supplementalMiuixIcon("BlurOn")
    "monet" -> MiuixIcons.Theme
    "glass-adaptive" -> supplementalMiuixIcon("BrightnessAuto")
    "glass-content" -> MiuixIcons.Layers
    "glass-blur-strength" -> supplementalMiuixIcon("BlurOn")
    "glass-light" -> supplementalMiuixIcon("LightMode")
    "glass-transparency" -> supplementalMiuixIcon("Opacity")
    "glass-refraction" -> supplementalMiuixIcon("Tune")
    "reset" -> MiuixIcons.Reset
    "about" -> MiuixIcons.Info
    "logs" -> MiuixIcons.Notes
    "shortcut" -> MiuixIcons.Home
    "discovery" -> MiuixIcons.SearchDevice
    "preset" -> MiuixIcons.GridView
    "brand" -> MiuixIcons.Store
    "model" -> supplementalMiuixIcon("Smartphone")
    "processor" -> supplementalMiuixIcon("Memory")
    "memory" -> supplementalMiuixIcon("Ram")
    "storage" -> supplementalMiuixIcon("Storage")
    "android" -> supplementalMiuixIcon("Android")
    "kernel" -> supplementalMiuixIcon("DeveloperBoard")
    "selinux" -> supplementalMiuixIcon("Security")
    "runtime" -> MiuixIcons.Timer
    "uptime" -> MiuixIcons.Stopwatch
    "sleep" -> supplementalMiuixIcon("Bedtime")
    "script-version" -> MiuixIcons.File
    "manager" -> MiuixIcons.GridView
    "busybox-version" -> supplementalMiuixIcon("Terminal")
    "busybox-path" -> MiuixIcons.Folder
    "script-path" -> MiuixIcons.Folder
    "author" -> MiuixIcons.Contacts
    "support" -> MiuixIcons.Help
    "unknown" -> MiuixIcons.Info
    else->null
}
private val supplementalIcons=mutableMapOf<String,ImageVector>()
// Original drawings; deliberately independent of Material icon path data.
private fun supplementalMiuixIcon(name:String):ImageVector = supplementalIcons.getOrPut(name){
    val data=when(name){
        "BatteryAlert" -> "M8 4 H16 Q18 4 18 6 V20 H6 V6 Q6 4 8 4 M10 2 H14 M12 8 V13 M12 17 H12.01"
        "PowerSettingsNew" -> "M12 3 V11 M6 5 C0 10 4 21 12 21 C20 21 24 10 18 5"
        "Notifications" -> "M5 17 H19 L17 14 V10 C17 3 7 3 7 10 V14 Z M10 20 Q12 22 14 20 M12 3 V4"
        "ScreenLockPortrait" -> "M7 2 H17 Q19 2 19 4 V20 Q19 22 17 22 H7 Q5 22 5 20 V4 Q5 2 7 2 M10 19 H14 M9 10 H15 V15 H9 Z M10 10 V8 Q12 5 14 8 V10"
        "Storage" -> "M4 4 H20 V10 H4 Z M4 14 H20 V20 H4 Z M7 7 H8 M7 17 H8 M12 7 H17 M12 17 H17"
        "Checklist" -> "M3 6 L5 8 L8 4 M11 6 H21 M3 16 L5 18 L8 14 M11 16 H21"
        "Android" -> "M6 9 Q12 2 18 9 V19 H6 Z M8 5 L6 2 M16 5 L18 2 M9 10 H9.01 M15 10 H15.01 M3 11 V17 M21 11 V17 M9 19 V22 M15 19 V22"
        "FolderZip" -> "M3 6 Q3 4 5 4 H10 L12 7 H19 Q21 7 21 9 V19 Q21 21 19 21 H5 Q3 21 3 19 Z M13 8 V10 H15 V12 H13 V14 H15 M13 16 H16 V19 H13 Z"
        "Inventory2" -> "M4 7 H20 V21 H4 Z M3 3 H21 V7 H3 Z M9 11 H15"
        "SyncAlt" -> "M3 7 H21 M17 3 L21 7 L17 11 M21 17 H3 M7 13 L3 17 L7 21"
        "Save" -> "M4 3 H17 L21 7 V21 H3 V4 Q3 3 4 3 M7 3 V9 H16 V3 M7 21 V14 H17 V21"
        "Restore" -> "M4 11 C4 1 20 1 20 12 C20 22 7 24 4 17 M1 7 L4 11 L8 8 M12 7 V12 L15 14"
        "InstallMobile" -> "M7 2 H17 Q19 2 19 4 V20 Q19 22 17 22 H7 Q5 22 5 20 V4 Q5 2 7 2 M12 6 V15 M8 11 L12 15 L16 11 M10 19 H14"
        "FormatSize" -> "M3 6 H15 M9 6 V21 M18 11 H23 M20.5 11 V21 M1 3 H23"
        "TextFields" -> "M3 5 H17 M10 5 V21 M15 13 H23 M19 13 V21"
        "BlurOn" -> "M5 5 H5.01 M12 5 H12.01 M19 5 H19.01 M5 12 H5.01 M12 12 H12.01 M19 12 H19.01 M5 19 H5.01 M12 19 H12.01 M19 19 H19.01"
        "BrightnessAuto" -> "M12 1 V3 M12 21 V23 M1 12 H3 M21 12 H23 M4 4 L5.5 5.5 M18.5 18.5 L20 20 M4 20 L5.5 18.5 M18.5 5.5 L20 4 M8 17 L12 6 L16 17 M10 13 H14"
        "LightMode" -> "M12 6 A6 6 0 1 0 12 18 A6 6 0 1 0 12 6 M12 1 V3 M12 21 V23 M1 12 H3 M21 12 H23 M4 4 L5.5 5.5 M18.5 18.5 L20 20 M4 20 L5.5 18.5 M18.5 5.5 L20 4"
        "Opacity" -> "M12 2 C10 6 4 10 4 15 A8 8 0 0 0 20 15 C20 10 14 6 12 2 Z M5 15 H19 M7 18 H17"
        "Tune" -> "M3 6 H8 M14 6 H21 M3 18 H14 M20 18 H21 M8 3 H14 V9 H8 Z M14 15 H20 V21 H14 Z"
        "Palette" -> "M12 3 C0 3 0 21 11 21 C15 21 10 16 16 16 C25 16 23 3 12 3 Z M8 7 H8.01 M15 6 H15.01 M19 10 H19.01 M5 12 H5.01"
        "ColorLens" -> "M9 4 A5 5 0 1 0 9 14 A5 5 0 1 0 9 4 M15 4 A5 5 0 1 0 15 14 A5 5 0 1 0 15 4 M12 10 A5 5 0 1 0 12 20 A5 5 0 1 0 12 10"
        "Ram" -> "M3 6 H21 V16 H3 Z M6 9 V13 M10 9 V13 M14 9 V13 M18 9 V13 M5 16 V19 M9 16 V19 M15 16 V19 M19 16 V19"
        "Memory" -> "M6 6 H18 V18 H6 Z M9 9 H15 V15 H9 Z M3 8 H6 M3 16 H6 M18 8 H21 M18 16 H21 M8 3 V6 M16 3 V6 M8 18 V21 M16 18 V21"
        "DeveloperBoard" -> "M4 4 H20 V20 H4 Z M8 8 H15 V16 H8 Z M20 8 H23 M20 12 H23 M20 16 H23"
        "Security" -> "M12 2 L21 6 V12 Q21 18 12 22 Q3 18 3 12 V6 Z M12 3 V21 M4 12 H20"
        "Bedtime" -> "M20 16 A9 9 0 1 1 8 3 C5 13 13 20 20 16 Z"
        "Terminal" -> "M3 4 H21 V20 H3 Z M6 8 L10 12 L6 16 M13 16 H18"
        "Smartphone" -> "M7 2 H17 Q19 2 19 4 V20 Q19 22 17 22 H7 Q5 22 5 20 V4 Q5 2 7 2 M10 5 H14 M11 19 H13"
        else->error("Unknown supplemental icon: $name")
    }
    ImageVector.Builder("SpeedBackup.Miuix.$name",24.dp,24.dp,24f,24f).apply{
        addPath(pathData=addPathNodes(data),fill=null,stroke=SolidColor(Color.Black),
            strokeLineWidth=if(name=="BlurOn")3f else 1.8f,strokeLineCap=StrokeCap.Round,strokeLineJoin=StrokeJoin.Round)
    }.build()
}
@Composable internal fun NativeSettingIcon(tint:Color?=null,enabled:Boolean=true){
    val material=LocalNativeMaterial.current
    val key=LocalNativeSettingIcon.current
    val vector=if(material)materialSettingIcon(key) else miuixSettingIcon(key)
    if(vector==null)return
    val ink=tint?:if(material)androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant else top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme.onSurface
    val color=ink.copy(alpha=ink.alpha*if(enabled)1f else .4f)
    // Decorative: the row's accessible label already names the setting.
    if(material)androidx.compose.material3.Icon(vector,null,Modifier.size(24.dp),tint=color)
    else top.yukonga.miuix.kmp.basic.Icon(vector,null,Modifier.size(24.dp),tint=color)
}
@Composable internal fun nativeSettingIconSlot(enabled:Boolean=true):(@Composable ()->Unit)? =
    if(LocalNativeSettingIcon.current.isEmpty())null else {{NativeSettingIcon(enabled=enabled)}}
