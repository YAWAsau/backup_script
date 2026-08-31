-keep class com.xayah.dex.HiddenApiUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.NotificationUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.NetworkUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.SsaidUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.HttpUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.CCUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.WebDavUtil { public static void main(java.lang.String[]); }

-keep class android.** { *; }
-keep class com.android.** { *; }
-keep class libcore.** { *; }
-keep class dev.rikka.tools.refine.** { *; }

-keep class * implements io.ktor.client.HttpClientEngineContainer { *; }
-keep class io.ktor.client.engine.cio.CIO { *; }
-keep class io.ktor.client.engine.cio.CIOEngineContainer { *; }
-keep class org.slf4j.** { *; }
-keep class org.slf4j.nop.** { *; }
-keep class * implements org.slf4j.spi.SLF4JServiceProvider { *; }
-dontwarn io.ktor.**
-dontwarn kotlinx.coroutines.**
-dontwarn kotlinx.serialization.**
-dontwarn nl.adaptivity.xmlutil.**
-dontwarn org.slf4j.**

-keepattributes *Annotation*,InnerClasses,EnclosingMethod
-dontobfuscate
-dontwarn **

-keep class com.xayah.dex.SmbScanUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.AppStateUtil { public static void main(java.lang.String[]); }

# LSPosed AndroidHiddenApiBypass 6.1: keep full helper graph.
-keep class org.lsposed.hiddenapibypass.** { *; }
-keep class com.xayah.dex.HiddenApiBypassBridge { *; }

# SpeedBackup 464 r3: keep unified root daemon CLI entry and all members.
-keep class com.xayah.dex.SpeedBackupRootDaemon { *; }

# SpeedBackup r501: keep root daemon supervisor CLI entry; R8 may strip it because it is only invoked from tools.sh app_process.
-keep class com.xayah.dex.DaemonSupervisorUtil { *; }

# SpeedBackup r43: keep inventory helper used by HiddenApiUtil/root daemon.
-keep class com.xayah.dex.AppInventoryUtil { *; }

# SpeedBackup r201: durable display-timeout transaction and watchdog must survive R8.
