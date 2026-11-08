package io.github.yawasau.speedbackup.webview;
import android.content.Context;
/** Explicit app language, independent of the device locale. */
public final class NativeLanguage {
    private static volatile String current="zh-Hant";
    public static String normalize(String value){return "zh-Hans".equals(value)?"zh-Hans":"zh-Hant";}
    public static void set(String value){current=normalize(value);}
    public static String get(){return current;}
    public static String text(Context context,String value){return NativeCatalog.Companion.get(context).text(value,current);}
}
