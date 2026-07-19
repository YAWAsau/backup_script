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
