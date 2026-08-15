package com.xayah.dex;

import com.google.gson.JsonObject;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Dex-owned localization for AppState, permissions and AppOps display names.
 *
 * Contract:
 * - raw machine fields are never replaced by localized strings;
 * - localized values are best-effort display helpers;
 * - unknown keys fall back to the original raw key.
 */
public final class AppStateLocalization {
    public static final String VERSION = "v1.0.0-appstate-localization-dex";

    private static final Map<String, String> BUILTIN = new LinkedHashMap<>();
    private static final Map<String, String> PERMISSIONS = new LinkedHashMap<>();
    private static final Map<String, String> MODES = new LinkedHashMap<>();
    private static final Map<String, String> SPECIAL = new LinkedHashMap<>();
    private static final Map<String, String> BATTERY = new LinkedHashMap<>();

    static {
        BUILTIN.put("permission_group_activity_recognition", "體能活動");
        BUILTIN.put("permission_group_sensors", "傳感器");
        BUILTIN.put("permission_group_phone", "電話");
        BUILTIN.put("permission_group_sms", "簡訊");
        BUILTIN.put("permission_group_contacts", "通訊錄");
        BUILTIN.put("permission_group_camera", "相機");
        BUILTIN.put("permission_group_location", "位置");
        BUILTIN.put("permission_group_calender", "日曆");
        BUILTIN.put("permission_group_microphone", "麥克風");
        BUILTIN.put("permission_group_storage", "儲存空間");
        BUILTIN.put("permission_group_other", "其他");
        BUILTIN.put("op_mode_allow", "允許");
        BUILTIN.put("op_mode_ignore", "忽略");
        BUILTIN.put("op_mode_ignore_description_others", "應用程式會得到空資料或操作不被執行");
        BUILTIN.put("op_mode_ignore_description_runtime", "「授予」應用程式權限，但是應用程式會得到空資料或操作不會被執行");
        BUILTIN.put("op_mode_deny", "拒絕");
        BUILTIN.put("op_mode_deny_crash", "拒絕（可能讓應用程式崩潰）");
        BUILTIN.put("op_mode_default", "預設");
        BUILTIN.put("op_mode_foreground", "僅限應用程式使用期間允許");
        BUILTIN.put("op_mode_onetime", "每次都詢問");
        BUILTIN.put("op_mode_unspecified", "尚未設定");
        BUILTIN.put("op_mode_unknown", "未知 (%1$d)");
        BUILTIN.put("op_mode_default_description", "系統設定或應用程式資訊中的設定控制。]]>");
        BUILTIN.put("permission_group_clipboard", "剪貼簿");
        BUILTIN.put("permission_group_device_identifiers", "裝置識別碼");
        BUILTIN.put("op_name_QUERY_ALL_PACKAGES", "查詢所有套件");
        BUILTIN.put("op_name_MANAGE_EXTERNAL_STORAGE", "管理所有檔案");
        BUILTIN.put("op_name_ACCESS_MEDIA_LOCATION", "從媒體檔案讀取位置資訊");
        BUILTIN.put("op_name_READ_DEVICE_IDENTIFIERS", "讀取裝置識別碼");
        BUILTIN.put("op_name_WRITE_MEDIA_IMAGES", "寫入你的相片收藏");
        BUILTIN.put("op_name_READ_MEDIA_IMAGES", "讀取你的相片收藏");
        BUILTIN.put("op_name_WRITE_MEDIA_VIDEO", "寫入你的影片收藏");
        BUILTIN.put("op_name_READ_MEDIA_VIDEO", "讀取你的影片收藏");
        BUILTIN.put("op_name_WRITE_MEDIA_AUDIO", "寫入你的音樂收藏");
        BUILTIN.put("op_name_READ_MEDIA_AUDIO", "讀取你的音樂收藏");
        BUILTIN.put("op_name_SMS_FINANCIAL_TRANSACTIONS", "付費短訊權限");
        BUILTIN.put("op_name_ACTIVITY_RECOGNITION", "識別身體活動");
        BUILTIN.put("op_name_USE_BIOMETRIC", "使用生物識別硬體");
        BUILTIN.put("op_name_REQUEST_DELETE_PACKAGES", "請求刪除程式");
        BUILTIN.put("op_name_BLUETOOTH_SCAN", "藍芽掃描");
        BUILTIN.put("op_name_START_FOREGROUND", "執行前景服務");
        BUILTIN.put("op_name_MANAGE_IPSEC_TUNNELS", "建立和管理 IPsec Tunnels");
        BUILTIN.put("op_name_ACCEPT_HANDOVER", "繼續進行來自其他應用程式的通話");
        BUILTIN.put("op_name_BIND_ACCESSIBILITY_SERVICE", "使用無障礙服務");
        BUILTIN.put("op_name_ANSWER_PHONE_CALLS", "接聽電話");
        BUILTIN.put("op_name_PICTURE_IN_PICTURE", "畫中畫");
        BUILTIN.put("op_name_REQUEST_INSTALL_PACKAGES", "請求安裝程式");
        BUILTIN.put("op_name_READ_PHONE_NUMBERS", "讀取手機號碼");
        BUILTIN.put("op_name_AUDIO_ACCESSIBILITY_VOLUME", "協助工具音量");
        BUILTIN.put("op_name_LOCK_APP", "鎖定程式");
        BUILTIN.put("op_name_SU", "取得 ROOT 權限");
        BUILTIN.put("op_name_DATA_CONNECT_CHANGE", "切換移動數據");
        BUILTIN.put("op_name_NFC_CHANGE", "切換 NFC");
        BUILTIN.put("op_name_BOOT_COMPLETED", "開機時執行");
        BUILTIN.put("op_name_BLUETOOTH_CHANGE", "開啟藍牙");
        BUILTIN.put("op_name_WIFI_CHANGE", "更改 Wi-Fi 狀態");
        BUILTIN.put("op_name_RUN_IN_BACKGROUND", "在背景執行");
        BUILTIN.put("op_name_GET_ACCOUNTS", "取得帳號");
        BUILTIN.put("op_name_TURN_ON_SCREEN", "開啟螢幕");
        BUILTIN.put("op_name_WRITE_EXTERNAL_STORAGE", "寫入儲存空間");
        BUILTIN.put("op_name_READ_EXTERNAL_STORAGE", "讀取儲存空間");
        BUILTIN.put("op_name_MOCK_LOCATION", "模擬位置");
        BUILTIN.put("op_name_READ_CELL_BROADCASTS", "讀取小區廣播");
        BUILTIN.put("op_name_BODY_SENSORS", "身體傳感器");
        BUILTIN.put("op_name_USE_FINGERPRINT", "指紋");
        BUILTIN.put("op_name_PROCESS_OUTGOING_CALLS", "處理撥出電話");
        BUILTIN.put("op_name_USE_SIP", "使用 SIP");
        BUILTIN.put("op_name_ADD_VOICEMAIL", "新增語音郵件");
        BUILTIN.put("op_name_READ_PHONE_STATE", "讀取手機狀態");
        BUILTIN.put("op_name_ASSIST_SCREENSHOT", "輔助螢幕截圖");
        BUILTIN.put("op_name_ASSIST_STRUCTURE", "輔助結構");
        BUILTIN.put("op_name_WRITE_WALLPAPER", "寫入壁紙");
        BUILTIN.put("op_name_ACTIVATE_VPN", "激活 VPN");
        BUILTIN.put("op_name_PROJECT_MEDIA", "投影媒體");
        BUILTIN.put("op_name_TOAST_WINDOW", "顯示 Toast");
        BUILTIN.put("op_name_MUTE_MICROPHONE", "將麥克風靜音或取消靜音");
        BUILTIN.put("op_name_GET_USAGE_STATS", "取得使用情況統計資訊");
        BUILTIN.put("op_name_MONITOR_HIGH_POWER_LOCATION", "監控高耗電位置資訊服務");
        BUILTIN.put("op_name_MONITOR_LOCATION", "監測位置");
        BUILTIN.put("op_name_WAKE_LOCK", "保持喚醒狀態");
        BUILTIN.put("op_name_AUDIO_BLUETOOTH_VOLUME", "藍牙音量");
        BUILTIN.put("op_name_AUDIO_NOTIFICATION_VOLUME", "通知音量");
        BUILTIN.put("op_name_AUDIO_ALARM_VOLUME", "鬧鐘音量");
        BUILTIN.put("op_name_AUDIO_MEDIA_VOLUME", "媒體音量");
        BUILTIN.put("op_name_AUDIO_RING_VOLUME", "鈴聲音量");
        BUILTIN.put("op_name_AUDIO_VOICE_VOLUME", "語音音量");
        BUILTIN.put("op_name_AUDIO_MASTER_VOLUME", "主音量");
        BUILTIN.put("op_name_TAKE_AUDIO_FOCUS", "音訊焦點");
        BUILTIN.put("op_name_TAKE_MEDIA_BUTTONS", "媒體按鈕");
        BUILTIN.put("op_name_WRITE_CLIPBOARD", "修改剪貼簿內容");
        BUILTIN.put("op_name_READ_CLIPBOARD", "讀取剪貼簿內容");
        BUILTIN.put("op_name_PLAY_AUDIO", "播放音訊");
        BUILTIN.put("op_name_RECORD_AUDIO", "錄制音訊");
        BUILTIN.put("op_name_CAMERA", "相機");
        BUILTIN.put("op_name_ACCESS_NOTIFICATIONS", "存取通知");
        BUILTIN.put("op_name_SYSTEM_ALERT_WINDOW", "顯示在其他應用程式上層");
        BUILTIN.put("op_name_WRITE_SETTINGS", "修改系統設定");
        BUILTIN.put("op_name_WRITE_ICC_SMS", "寫入 ICC 簡訊");
        BUILTIN.put("op_name_READ_ICC_SMS", "讀取 ICC 簡訊");
        BUILTIN.put("op_name_SEND_SMS", "發送簡訊");
        BUILTIN.put("op_name_RECEIVE_WAP_PUSH", "接收 WAP PUSH 消息");
        BUILTIN.put("op_name_RECEIVE_MMS", "接收多媒體簡訊");
        BUILTIN.put("op_name_RECEIVE_EMERGECY_SMS", "接收緊急簡訊");
        BUILTIN.put("op_name_RECEIVE_SMS", "接收文字簡訊");
        BUILTIN.put("op_name_WRITE_SMS", "編寫簡訊");
        BUILTIN.put("op_name_READ_SMS", "讀取簡訊");
        BUILTIN.put("op_name_CALL_PHONE", "撥打電話");
        BUILTIN.put("op_name_NEIGHBORING_CELLS", "手機網路掃描");
        BUILTIN.put("op_name_POST_NOTIFICATION", "通知");
        BUILTIN.put("op_name_WIFI_SCAN", "Wi-Fi掃描");
        BUILTIN.put("op_name_WRITE_CALENDAR", "修改日曆");
        BUILTIN.put("op_name_READ_CALENDAR", "讀取日曆");
        BUILTIN.put("op_name_WRITE_CALL_LOG", "修改通話記錄");
        BUILTIN.put("op_name_READ_CALL_LOG", "讀取通話記錄");
        BUILTIN.put("op_name_WRITE_CONTACTS", "修改連絡人");
        BUILTIN.put("op_name_READ_CONTACTS", "讀取連絡人");
        BUILTIN.put("op_name_VIBRATE", "振動");
        BUILTIN.put("op_name_GPS", "GPS");
        BUILTIN.put("op_name_FINE_LOCATION", "精凖位置");
        BUILTIN.put("op_name_COARSE_LOCATION", "粗略位置");
        BUILTIN.put("op_name_LOCATION", "使用位置");
        BUILTIN.put("op_name_special_SENSORS", "傳感器");

        PERMISSIONS.put("android.permission.READ_EXTERNAL_STORAGE", "讀取外部存儲");
        PERMISSIONS.put("android.permission.WRITE_EXTERNAL_STORAGE", "寫入外部存儲");
        PERMISSIONS.put("android.permission.CAMERA", "相機權限");
        PERMISSIONS.put("android.permission.RECORD_AUDIO", "麥克風權限");
        PERMISSIONS.put("android.permission.ACCESS_FINE_LOCATION", "精確定位");
        PERMISSIONS.put("android.permission.ACCESS_COARSE_LOCATION", "粗略定位");
        PERMISSIONS.put("android.permission.ACCESS_MEDIA_LOCATION", "媒體位置訪問");
        PERMISSIONS.put("android.permission.READ_PHONE_STATE", "讀取手機狀態");
        PERMISSIONS.put("android.permission.CALL_PHONE", "直接撥打電話");
        PERMISSIONS.put("android.permission.READ_CONTACTS", "讀取聯絡人");
        PERMISSIONS.put("android.permission.WRITE_CONTACTS", "寫入聯絡人");
        PERMISSIONS.put("android.permission.READ_CALL_LOG", "讀取通話記錄");
        PERMISSIONS.put("android.permission.WRITE_CALL_LOG", "寫入通話記錄");
        PERMISSIONS.put("android.permission.SEND_SMS", "發送短信");
        PERMISSIONS.put("android.permission.READ_SMS", "讀取短信");
        PERMISSIONS.put("android.permission.READ_MEDIA_IMAGES", "讀取圖片");
        PERMISSIONS.put("android.permission.READ_MEDIA_VIDEO", "讀取視頻");
        PERMISSIONS.put("android.permission.READ_MEDIA_AUDIO", "讀取音頻");
        PERMISSIONS.put("android.permission.READ_MEDIA_VISUAL_USER_SELECTED", "讀取用戶選擇的媒體");
        PERMISSIONS.put("android.permission.READ_CALENDAR", "讀取日曆");
        PERMISSIONS.put("android.permission.WRITE_CALENDAR", "寫入日曆");
        PERMISSIONS.put("android.permission.BODY_SENSORS", "身體傳感器");
        PERMISSIONS.put("android.permission.ACTIVITY_RECOGNITION", "活動識別");
        PERMISSIONS.put("android.permission.GET_ACCOUNTS", "獲取帳戶列表");
        PERMISSIONS.put("android.permission.MANAGE_ACCOUNTS", "管理帳戶");
        PERMISSIONS.put("android.permission.USE_CREDENTIALS", "使用憑據");
        PERMISSIONS.put("android.permission.AUTHENTICATE_ACCOUNTS", "驗證帳戶");
        PERMISSIONS.put("android.permission.SYSTEM_ALERT_WINDOW", "懸浮窗權限");
        PERMISSIONS.put("android.permission.WRITE_SETTINGS", "寫入系統設置");
        PERMISSIONS.put("android.permission.REQUEST_INSTALL_PACKAGES", "安裝應用");
        PERMISSIONS.put("android.permission.QUERY_ALL_PACKAGES", "查詢所有應用");
        PERMISSIONS.put("android.permission.READ_PRIVILEGED_PHONE_STATE", "讀取特權手機狀態");
        PERMISSIONS.put("android.permission.BLUETOOTH", "使用藍牙");
        PERMISSIONS.put("android.permission.BLUETOOTH_ADMIN", "藍牙管理");
        PERMISSIONS.put("android.permission.BLUETOOTH_CONNECT", "藍牙連接");
        PERMISSIONS.put("android.permission.BLUETOOTH_SCAN", "藍牙掃描");
        PERMISSIONS.put("android.permission.BLUETOOTH_ADVERTISE", "藍牙廣播");
        PERMISSIONS.put("android.permission.INTERNET", "訪問網絡");
        PERMISSIONS.put("android.permission.ACCESS_NETWORK_STATE", "查看網絡狀態");
        PERMISSIONS.put("android.permission.ACCESS_WIFI_STATE", "查看WiFi狀態");
        PERMISSIONS.put("android.permission.CHANGE_WIFI_STATE", "修改WiFi狀態");
        PERMISSIONS.put("android.permission.CHANGE_NETWORK_STATE", "修改網絡狀態");
        PERMISSIONS.put("android.permission.CHANGE_WIFI_MULTICAST_STATE", "修改WiFi多播狀態");
        PERMISSIONS.put("android.permission.POST_NOTIFICATIONS", "發送通知");
        PERMISSIONS.put("android.permission.RECEIVE_BOOT_COMPLETED", "開機啟動");
        PERMISSIONS.put("android.permission.RECEIVE_USER_PRESENT", "用戶解鎖設備");
        PERMISSIONS.put("android.permission.WAKE_LOCK", "保持喚醒");
        PERMISSIONS.put("android.permission.VIBRATE", "振動權限");
        PERMISSIONS.put("android.permission.FLASHLIGHT", "手電筒");
        PERMISSIONS.put("android.permission.DISABLE_KEYGUARD", "禁用鎖屏");
        PERMISSIONS.put("android.permission.EXPAND_STATUS_BAR", "展開狀態欄");
        PERMISSIONS.put("android.permission.MODIFY_AUDIO_SETTINGS", "修改音頻設置");
        PERMISSIONS.put("android.permission.USE_FINGERPRINT", "使用指紋");
        PERMISSIONS.put("android.permission.USE_BIOMETRIC", "使用生物識別");
        PERMISSIONS.put("android.permission.USE_FACERECOGNITION", "使用面部識別");
        PERMISSIONS.put("android.permission.BIND_NFC_SERVICE", "NFC服務綁定");
        PERMISSIONS.put("android.permission.BIND_NOTIFICATION_LISTENER_SERVICE", "通知監聽服務綁定");
        PERMISSIONS.put("android.permission.BIND_QUICK_ACCESS_WALLET_SERVICE", "快捷錢包服務綁定");
        PERMISSIONS.put("android.permission.BIND_ACCESSIBILITY_SERVICE", "無障礙服務綁定");
        PERMISSIONS.put("android.permission.BIND_WALLPAPER", "壁紙服務綁定");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE", "前台服務");
        PERMISSIONS.put("android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "忽略電池優化");
        PERMISSIONS.put("android.permission.SCHEDULE_EXACT_ALARM", "精確鬧鐘");
        PERMISSIONS.put("android.permission.GET_TASKS", "獲取任務");
        PERMISSIONS.put("android.permission.REORDER_TASKS", "重新排序任務");
        PERMISSIONS.put("android.permission.BROADCAST_STICKY", "粘性廣播");
        PERMISSIONS.put("android.permission.DUMP", "系統信息轉儲");
        PERMISSIONS.put("android.permission.NFC", "NFC權限");
        PERMISSIONS.put("android.permission.SMARTCARD", "智能卡權限");
        PERMISSIONS.put("android.permission.NEARBY_WIFI_DEVICES", "鄰近WiFi設備");
        PERMISSIONS.put("android.permission.MANAGE_EXTERNAL_STORAGE", "管理所有檔案");
        PERMISSIONS.put("android.permission.WRITE_SMS", "寫入短信");
        PERMISSIONS.put("android.permission.RECEIVE_SMS", "接收短信");
        PERMISSIONS.put("android.permission.RECEIVE_MMS", "接收彩信");
        PERMISSIONS.put("android.permission.RECEIVE_WAP_PUSH", "接收WAP推送");
        PERMISSIONS.put("android.permission.READ_CELL_BROADCASTS", "讀取緊急廣播");
        PERMISSIONS.put("android.permission.READ_PHONE_NUMBERS", "讀取電話號碼");
        PERMISSIONS.put("android.permission.ANSWER_PHONE_CALLS", "接聽電話");
        PERMISSIONS.put("android.permission.PROCESS_OUTGOING_CALLS", "處理撥出電話");
        PERMISSIONS.put("android.permission.ADD_VOICEMAIL", "新增語音信箱");
        PERMISSIONS.put("android.permission.USE_SIP", "使用SIP通話");
        PERMISSIONS.put("android.permission.ACCEPT_HANDOVER", "接管通話");
        PERMISSIONS.put("android.permission.ACCESS_BACKGROUND_LOCATION", "背景定位");
        PERMISSIONS.put("android.permission.USE_FULL_SCREEN_INTENT", "全螢幕通知");
        PERMISSIONS.put("android.permission.ACCESS_NOTIFICATION_POLICY", "勿擾模式存取");
        PERMISSIONS.put("android:picture_in_picture", "子母畫面");
        PERMISSIONS.put("android:system_alert_window", "懸浮窗權限(AppOps)");
        PERMISSIONS.put("android:use_full_screen_intent", "全螢幕通知(AppOps)");
        PERMISSIONS.put("android:write_settings", "寫入系統設置(AppOps)");
        PERMISSIONS.put("android:request_install_packages", "安裝未知應用(AppOps)");
        PERMISSIONS.put("android:get_usage_stats", "使用情況存取(AppOps)");
        PERMISSIONS.put("android:manage_external_storage", "管理所有檔案(AppOps)");
        PERMISSIONS.put("android:schedule_exact_alarm", "精確鬧鐘(AppOps)");
        PERMISSIONS.put("android:access_notification_policy", "勿擾模式存取(AppOps)");
        PERMISSIONS.put("android:coarse_location", "粗略定位(AppOps)");
        PERMISSIONS.put("android:fine_location", "精確定位(AppOps)");
        PERMISSIONS.put("android:gps", "GPS定位(AppOps)");
        PERMISSIONS.put("android:vibrate", "振動(AppOps)");
        PERMISSIONS.put("android:read_contacts", "讀取聯絡人(AppOps)");
        PERMISSIONS.put("android:write_contacts", "寫入聯絡人(AppOps)");
        PERMISSIONS.put("android:read_call_log", "讀取通話記錄(AppOps)");
        PERMISSIONS.put("android:write_call_log", "寫入通話記錄(AppOps)");
        PERMISSIONS.put("android:read_calendar", "讀取日曆(AppOps)");
        PERMISSIONS.put("android:write_calendar", "寫入日曆(AppOps)");
        PERMISSIONS.put("android:wifi_scan", "WiFi掃描(AppOps)");
        PERMISSIONS.put("android:post_notification", "發送通知(AppOps)");
        PERMISSIONS.put("android:neighboring_cells", "鄰近基地台(AppOps)");
        PERMISSIONS.put("android:call_phone", "直接撥打電話(AppOps)");
        PERMISSIONS.put("android:read_sms", "讀取短信(AppOps)");
        PERMISSIONS.put("android:write_sms", "寫入短信(AppOps)");
        PERMISSIONS.put("android:receive_sms", "接收短信(AppOps)");
        PERMISSIONS.put("android:receive_emergency_broadcast", "接收緊急廣播(AppOps)");
        PERMISSIONS.put("android:receive_mms", "接收彩信(AppOps)");
        PERMISSIONS.put("android:receive_wap_push", "接收WAP推送(AppOps)");
        PERMISSIONS.put("android:send_sms", "發送短信(AppOps)");
        PERMISSIONS.put("android:read_icc_sms", "讀取SIM短信(AppOps)");
        PERMISSIONS.put("android:write_icc_sms", "寫入SIM短信(AppOps)");
        PERMISSIONS.put("android:access_notifications", "通知存取(AppOps)");
        PERMISSIONS.put("android:camera", "相機(AppOps)");
        PERMISSIONS.put("android:record_audio", "麥克風(AppOps)");
        PERMISSIONS.put("android:play_audio", "播放音訊(AppOps)");
        PERMISSIONS.put("android:read_clipboard", "讀取剪貼板(AppOps)");
        PERMISSIONS.put("android:write_clipboard", "寫入剪貼板(AppOps)");
        PERMISSIONS.put("android:take_media_buttons", "接收媒體按鍵(AppOps)");
        PERMISSIONS.put("android:take_audio_focus", "取得音訊焦點(AppOps)");
        PERMISSIONS.put("android:audio_master_volume", "主音量控制(AppOps)");
        PERMISSIONS.put("android:audio_voice_volume", "通話音量控制(AppOps)");
        PERMISSIONS.put("android:audio_ring_volume", "鈴聲音量控制(AppOps)");
        PERMISSIONS.put("android:audio_media_volume", "媒體音量控制(AppOps)");
        PERMISSIONS.put("android:audio_alarm_volume", "鬧鐘音量控制(AppOps)");
        PERMISSIONS.put("android:audio_notification_volume", "通知音量控制(AppOps)");
        PERMISSIONS.put("android:audio_bluetooth_volume", "藍牙音量控制(AppOps)");
        PERMISSIONS.put("android:wake_lock", "保持喚醒(AppOps)");
        PERMISSIONS.put("android:monitor_location", "監控定位(AppOps)");
        PERMISSIONS.put("android:monitor_high_power_location", "高功耗定位監控(AppOps)");
        PERMISSIONS.put("android:mute_microphone", "靜音麥克風(AppOps)");
        PERMISSIONS.put("android:toast_window", "Toast視窗(AppOps)");
        PERMISSIONS.put("android:project_media", "媒體投放/投影(AppOps)");
        PERMISSIONS.put("android:activate_vpn", "啟用VPN(AppOps)");
        PERMISSIONS.put("android:write_wallpaper", "修改壁紙(AppOps)");
        PERMISSIONS.put("android:assist_structure", "輔助結構存取(AppOps)");
        PERMISSIONS.put("android:assist_screenshot", "輔助截圖存取(AppOps)");
        PERMISSIONS.put("android:read_phone_state", "讀取手機狀態(AppOps)");
        PERMISSIONS.put("android:add_voicemail", "新增語音信箱(AppOps)");
        PERMISSIONS.put("android:use_sip", "使用SIP通話(AppOps)");
        PERMISSIONS.put("android:process_outgoing_calls", "處理撥出電話(AppOps)");
        PERMISSIONS.put("android:use_fingerprint", "使用指紋(AppOps)");
        PERMISSIONS.put("android:body_sensors", "身體傳感器(AppOps)");
        PERMISSIONS.put("android:read_cell_broadcasts", "讀取緊急廣播(AppOps)");
        PERMISSIONS.put("android:mock_location", "模擬位置(AppOps)");
        PERMISSIONS.put("android:read_external_storage", "讀取外部存儲(AppOps)");
        PERMISSIONS.put("android:write_external_storage", "寫入外部存儲(AppOps)");
        PERMISSIONS.put("android:turn_screen_on", "喚醒螢幕(AppOps)");
        PERMISSIONS.put("android:get_accounts", "獲取帳戶列表(AppOps)");
        PERMISSIONS.put("android:run_in_background", "背景執行(AppOps)");
        PERMISSIONS.put("android:audio_accessibility_volume", "無障礙音量控制(AppOps)");
        PERMISSIONS.put("android:read_phone_numbers", "讀取電話號碼(AppOps)");
        PERMISSIONS.put("android:instant_app_start_foreground", "即時應用啟動前台服務(AppOps)");
        PERMISSIONS.put("android:answer_phone_calls", "接聽電話(AppOps)");
        PERMISSIONS.put("android:run_any_in_background", "任意背景執行(AppOps)");
        PERMISSIONS.put("android:change_wifi_state", "修改WiFi狀態(AppOps)");
        PERMISSIONS.put("android:request_delete_packages", "刪除應用(AppOps)");
        PERMISSIONS.put("android:bind_accessibility_service", "綁定無障礙服務(AppOps)");
        PERMISSIONS.put("android:accept_handover", "接管通話(AppOps)");
        PERMISSIONS.put("android:manage_ipsec_tunnels", "管理IPSec通道(AppOps)");
        PERMISSIONS.put("android:start_foreground", "啟動前台服務(AppOps)");
        PERMISSIONS.put("android:bluetooth_scan", "藍牙掃描(AppOps)");
        PERMISSIONS.put("android:use_biometric", "使用生物識別(AppOps)");
        PERMISSIONS.put("android:activity_recognition", "活動識別(AppOps)");
        PERMISSIONS.put("android:sms_financial_transactions", "金融短信交易(AppOps)");
        PERMISSIONS.put("android:read_media_audio", "讀取音頻(AppOps)");
        PERMISSIONS.put("android:write_media_audio", "寫入音頻(AppOps)");
        PERMISSIONS.put("android:read_media_video", "讀取視頻(AppOps)");
        PERMISSIONS.put("android:write_media_video", "寫入視頻(AppOps)");
        PERMISSIONS.put("android:read_media_images", "讀取圖片(AppOps)");
        PERMISSIONS.put("android:write_media_images", "寫入圖片(AppOps)");
        PERMISSIONS.put("android:legacy_storage", "舊版儲存模式(AppOps)");
        PERMISSIONS.put("android:access_accessibility", "無障礙存取(AppOps)");
        PERMISSIONS.put("android:read_device_identifiers", "讀取裝置識別碼(AppOps)");
        PERMISSIONS.put("android:access_media_location", "媒體位置存取(AppOps)");
        PERMISSIONS.put("android:query_all_packages", "查詢所有應用(AppOps)");
        PERMISSIONS.put("android:interact_across_profiles", "跨設定檔互動(AppOps)");
        PERMISSIONS.put("android:activate_platform_vpn", "啟用平台VPN(AppOps)");
        PERMISSIONS.put("android:loader_usage_stats", "載入器使用情況(AppOps)");
        PERMISSIONS.put("android:auto_revoke_permissions_if_unused", "未使用自動撤銷權限(AppOps)");
        PERMISSIONS.put("android:auto_revoke_managed_by_installer", "安裝器管理自動撤銷(AppOps)");
        PERMISSIONS.put("android:no_isolated_storage", "停用隔離儲存(AppOps)");
        PERMISSIONS.put("android:phone_call_microphone", "通話麥克風(AppOps)");
        PERMISSIONS.put("android:phone_call_camera", "通話相機(AppOps)");
        PERMISSIONS.put("android:record_audio_hotword", "熱詞錄音(AppOps)");
        PERMISSIONS.put("android:manage_ongoing_calls", "管理進行中通話(AppOps)");
        PERMISSIONS.put("android:manage_credentials", "管理憑證(AppOps)");
        PERMISSIONS.put("android:use_icc_auth_with_device_identifier", "SIM認證使用裝置識別碼(AppOps)");
        PERMISSIONS.put("android:record_audio_output", "錄製系統音訊輸出(AppOps)");
        PERMISSIONS.put("android:fine_location_source", "精確定位來源(AppOps)");
        PERMISSIONS.put("android:coarse_location_source", "粗略定位來源(AppOps)");
        PERMISSIONS.put("android:manage_media", "管理媒體(AppOps)");
        PERMISSIONS.put("android:bluetooth_connect", "藍牙連接(AppOps)");
        PERMISSIONS.put("android:uwb_ranging", "超寬頻測距(AppOps)");
        PERMISSIONS.put("android:activity_recognition_source", "活動識別來源(AppOps)");
        PERMISSIONS.put("android:bluetooth_advertise", "藍牙廣播(AppOps)");
        PERMISSIONS.put("android:record_incoming_phone_audio", "錄製來電音訊(AppOps)");
        PERMISSIONS.put("android:nearby_wifi_devices", "鄰近WiFi設備(AppOps)");
        PERMISSIONS.put("android:establish_vpn_service", "建立VPN服務(AppOps)");
        PERMISSIONS.put("android:establish_vpn_manager", "建立VPN管理器(AppOps)");
        PERMISSIONS.put("android:access_restricted_settings", "存取受限設定(AppOps)");
        PERMISSIONS.put("android:receive_soundtrigger_audio", "接收聲音觸發音訊(AppOps)");
        PERMISSIONS.put("android:receive_explicit_user_interaction_audio", "接收明確互動音訊(AppOps)");
        PERMISSIONS.put("android:run_user_initiated_jobs", "執行使用者發起工作(AppOps)");
        PERMISSIONS.put("android:read_media_visual_user_selected", "讀取使用者選擇媒體(AppOps)");
        PERMISSIONS.put("android:system_exempt_from_suspension", "系統豁免暫停(AppOps)");
        PERMISSIONS.put("android:system_exempt_from_dismissible_notifications", "系統豁免可清除通知(AppOps)");
        PERMISSIONS.put("android:read_write_health_data", "讀寫健康資料(AppOps)");
        PERMISSIONS.put("android:foreground_service_special_use", "前台服務特殊用途(AppOps)");
        PERMISSIONS.put("android:camera_sandboxed", "沙盒相機(AppOps)");
        PERMISSIONS.put("android:record_audio_sandboxed", "沙盒錄音(AppOps)");
        PERMISSIONS.put("android:receive_sandbox_trigger_audio", "接收沙盒觸發音訊(AppOps)");
        PERMISSIONS.put("android:system_exempt_from_power_restrictions", "系統豁免電源限制(AppOps)");
        PERMISSIONS.put("android:system_exempt_from_hibernation", "系統豁免休眠(AppOps)");
        PERMISSIONS.put("android:system_exempt_from_activity_bg_start_restriction", "系統豁免背景啟動限制(AppOps)");
        PERMISSIONS.put("android:capture_consentless_bugreport_on_userdebug_build", "擷取無同意錯誤報告(AppOps)");
        PERMISSIONS.put("android.permission.RUN_IN_BACKGROUND", "在背景執行");
        PERMISSIONS.put("android.permission.RUN_ANY_IN_BACKGROUND", "任意背景執行");
        PERMISSIONS.put("android.permission.START_FOREGROUND", "啟動前台服務");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_LOCATION", "前台服務-定位");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_CAMERA", "前台服務-相機");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_MICROPHONE", "前台服務-麥克風");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK", "前台服務-媒體播放");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION", "前台服務-畫面錄製");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_PHONE_CALL", "前台服務-通話");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_DATA_SYNC", "前台服務-數據同步");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE", "前台服務-連接設備");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_HEALTH", "前台服務-健康");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING", "前台服務-遠程消息");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED", "前台服務-系統豁免");
        PERMISSIONS.put("android.permission.FOREGROUND_SERVICE_SPECIAL_USE", "前台服務-特殊用途");
        PERMISSIONS.put("android.permission.REQUEST_DELETE_PACKAGES", "刪除應用");
        PERMISSIONS.put("android.permission.PACKAGE_USAGE_STATS", "使用情況存取");
        PERMISSIONS.put("android.permission.GET_USAGE_STATS", "獲取使用情況統計");
        PERMISSIONS.put("android.permission.READ_CLIPBOARD", "讀取剪貼板");
        PERMISSIONS.put("android.permission.WRITE_CLIPBOARD", "寫入剪貼板");
        PERMISSIONS.put("android.permission.MUTE_MICROPHONE", "靜音麥克風");
        PERMISSIONS.put("android.permission.LEGACY_STORAGE", "舊版儲存模式");
        PERMISSIONS.put("android.permission.HIGH_SAMPLING_RATE_SENSORS", "高採樣率傳感器");
        PERMISSIONS.put("android.permission.UWB_RANGING", "超寬頻測距");
        PERMISSIONS.put("android.permission.BIND_VPN_SERVICE", "VPN服務綁定");
        PERMISSIONS.put("android.permission.INTERACT_ACROSS_USERS", "跨用戶互動");
        PERMISSIONS.put("android.permission.MANAGE_OWN_CALLS", "管理自有通話");
        PERMISSIONS.put("android.permission.CALL_COMPANION_APP", "車機配對通話");
        PERMISSIONS.put("android.permission.health.READ_HEART_RATE", "讀取心率");
        PERMISSIONS.put("android.permission.health.READ_STEPS", "讀取步數");
        PERMISSIONS.put("android.permission.health.READ_SLEEP", "讀取睡眠數據");
        PERMISSIONS.put("android.permission.health.READ_OXYGEN_SATURATION", "讀取血氧");
        PERMISSIONS.put("android.permission.health.READ_BODY_TEMPERATURE", "讀取體溫");
        PERMISSIONS.put("android.permission.health.READ_BLOOD_PRESSURE", "讀取血壓");
        PERMISSIONS.put("android.permission.health.READ_BLOOD_GLUCOSE", "讀取血糖");
        PERMISSIONS.put("android.permission.health.READ_EXERCISE", "讀取運動記錄");
        PERMISSIONS.put("android.permission.health.READ_NUTRITION", "讀取營養記錄");
        PERMISSIONS.put("android.permission.health.READ_WEIGHT", "讀取體重");
        PERMISSIONS.put("android.permission.health.READ_MEDICAL_DATA_IMMUNIZATION", "讀取疫苗醫療記錄");
        PERMISSIONS.put("android.permission.health.WRITE_MEDICAL_DATA", "寫入醫療記錄");
        PERMISSIONS.put("*", "$1");

        MODES.put("0", "允許(0)");
        MODES.put("1", "忽略(1)");
        MODES.put("2", "拒絕(2)");
        MODES.put("3", "預設(3)");
        MODES.put("4", "僅前台(4)");
        MODES.put("5", "每次詢問(5)");
        MODES.put("null|''", "未設定");
        MODES.put("missing", "已移除");
        MODES.put("*", "模式$1");

        SPECIAL.put("SYSTEM_ALERT_WINDOW", "懸浮窗權限");
        SPECIAL.put("PICTURE_IN_PICTURE", "子母畫面");
        SPECIAL.put("MANAGE_EXTERNAL_STORAGE", "管理所有檔案");
        SPECIAL.put("WRITE_SETTINGS", "修改系統設定");
        SPECIAL.put("REQUEST_INSTALL_PACKAGES", "安裝未知應用");
        SPECIAL.put("GET_USAGE_STATS", "使用情況存取");
        SPECIAL.put("USE_FULL_SCREEN_INTENT", "全螢幕通知");
        SPECIAL.put("SCHEDULE_EXACT_ALARM", "精確鬧鐘");
        SPECIAL.put("ACCESS_NOTIFICATION_POLICY", "勿擾模式存取");

        BATTERY.put("RUN_IN_BACKGROUND", "背景執行");
        BATTERY.put("BATTERY:RUN_IN_BACKGROUND", "背景執行");
        BATTERY.put("RUN_ANY_IN_BACKGROUND", "任意背景執行");
        BATTERY.put("BATTERY:RUN_ANY_IN_BACKGROUND", "任意背景執行");
        BATTERY.put("deviceidleWhitelist", "Doze白名單");
        BATTERY.put("BATTERY:deviceidle_whitelist", "Doze白名單");
    }

    private AppStateLocalization() {}

    public static String localize(String type, String key) {
        String t = type == null ? "" : type.trim().toLowerCase(Locale.ROOT);
        String k = key == null ? "" : key.trim();
        if (k.isEmpty()) return "";
        switch (t) {
            case "mode":
            case "appstate_mode":
                return modeCn(k);
            case "special":
            case "appstate_special":
                return specialCn(k);
            case "perm":
            case "permission":
                return permissionCn(k);
            case "battery":
                return batteryCn(k);
            case "appops":
            case "appop":
            case "lookup":
            default:
                return lookup(k);
        }
    }

    public static String lookup(String key) {
        if (key == null) return "";
        String raw = key.trim();
        if (raw.isEmpty()) return "";
        String exact = BUILTIN.get(raw);
        if (exact != null && !exact.isEmpty()) return exact;

        String base = raw;
        if (base.startsWith("android.permission.")) base = base.substring("android.permission.".length());
        else if (base.startsWith("android:")) base = base.substring("android:".length());
        else if (base.startsWith("OP_")) base = base.substring("OP_".length());
        else if (base.startsWith("op_name_")) base = base.substring("op_name_".length());

        String upper = base.toUpperCase(Locale.ROOT);
        String lower = base.toLowerCase(Locale.ROOT);
        String[] tries = new String[] {
                base,
                upper,
                "op_name_" + upper,
                "OP_" + upper,
                "android.permission." + upper,
                "android:" + lower,
                "permission_group_" + lower,
                "op_mode_" + lower
        };
        for (String candidate : tries) {
            String value = BUILTIN.get(candidate);
            if (value != null && !value.isEmpty()) return value;
        }
        return raw;
    }

    public static String permissionCn(String key) {
        if (key == null) return "";
        String raw = key.trim();
        if (raw.isEmpty()) return "";
        String viaLookup = lookup(raw);
        if (!raw.equals(viaLookup)) return viaLookup;
        String direct = PERMISSIONS.get(raw);
        if (direct != null && !direct.isEmpty()) return direct;
        if (raw.startsWith("android:op_")) return "未知AppOps(" + raw.substring("android:op_".length()) + ")";
        return raw;
    }

    public static String specialCn(String key) {
        if (key == null) return "";
        String raw = key.trim();
        if (raw.isEmpty()) return "";
        String direct = SPECIAL.get(raw);
        if (direct != null && !direct.isEmpty()) return direct;
        return permissionCn(raw);
    }

    public static String batteryCn(String key) {
        if (key == null) return "";
        String raw = key.trim();
        if (raw.isEmpty()) return "";
        String direct = BATTERY.get(raw);
        return direct == null || direct.isEmpty() ? raw : direct;
    }

    public static String modeCn(int mode) {
        return modeCn(String.valueOf(mode));
    }

    public static String modeCn(String mode) {
        if (mode == null || mode.isEmpty() || "null".equals(mode)) return "未設定";
        String direct = MODES.get(mode);
        if (direct != null && !direct.isEmpty()) return direct;
        switch (mode) {
            case "allow": return "允許";
            case "ignore": return "忽略";
            case "deny": return "拒絕";
            case "default": return "預設";
            case "foreground": return "僅前台";
            case "missing": return "已移除";
            default: return "模式" + mode;
        }
    }

    public static void addModeDisplay(JsonObject object, String modeField) {
        if (object == null || modeField == null || !object.has(modeField) || object.get(modeField).isJsonNull()) return;
        object.addProperty(modeField + "Cn", modeCn(object.get(modeField).getAsString()));
    }

    public static String localizeRequest(String body) {
        if (body == null || body.trim().isEmpty()) return "";
        StringBuilder out = new StringBuilder();
        String[] lines = body.split("\r?\n");
        for (String line : lines) {
            String value = line == null ? "" : line.trim();
            if (value.isEmpty() || value.startsWith("#")) continue;
            String type;
            String key;
            int tab = value.indexOf('\t');
            if (tab >= 0) {
                type = value.substring(0, tab).trim();
                key = value.substring(tab + 1).trim();
            } else {
                String[] parts = value.split("\s+", 2);
                type = parts.length > 0 ? parts[0].trim() : "lookup";
                key = parts.length > 1 ? parts[1].trim() : "";
            }
            if (type.isEmpty() || key.isEmpty()) continue;
            out.append(type).append('\t').append(key).append('\t').append(localize(type, key)).append('\n');
        }
        return out.toString();
    }
}
