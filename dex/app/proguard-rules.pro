# R8 shrink rules for app_process dex tools.
# Keep CLI entry points. R8 may still shrink unused members around them.
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


