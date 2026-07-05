# R8 shrink rules for pure app_process dex tools (zero UI build).
# Keep only CLI entry points. There is no Activity/Receiver/Service UI component in this build.
-keep class com.xayah.dex.HiddenApiUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.NotificationUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.NetworkUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.SsaidUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.HttpUtil { public static void main(java.lang.String[]); }
-keep class com.xayah.dex.CCUtil { public static void main(java.lang.String[]); }

# Hidden/API stubs used by Refine, reflection, XML/settings parsing and app_process runtime.
-keep class android.** { *; }
-keep class com.android.** { *; }
-keep class libcore.** { *; }
-keep class dev.rikka.tools.refine.** { *; }

# Keep reflection-visible metadata, but do not obfuscate entry/class names.
-keepattributes *Annotation*,InnerClasses,EnclosingMethod
-dontobfuscate
-dontwarn **


