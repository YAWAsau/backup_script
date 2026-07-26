package com.xayah.dex;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;
import android.os.Build;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.text.Collator;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipFile;

import dev.rikka.tools.refine.Refine;

/**
 * SpeedBackup App inventory snapshot.
 *
 * One PackageManager scan provides label/pkg/uid/version/source/flag/category data for shell.
 * In a persistent root daemon this class keeps a per-user/per-locale cache for the current run.
 */
final class AppInventoryUtil {
    static final String VERSION = "v1.1.0-app-inventory-source-path-cache";
    private static final String XPOSED_METADATA = "xposedminversion";
    private static final Gson GSON = new Gson();
    private static final Map<String, List<Item>> CACHE = new HashMap<>();

    private AppInventoryUtil() {}

    static synchronized String runCommand(String[] args) throws Exception {
        if (args == null || args.length < 2) {
            return "APP_INVENTORY_BAD_ARGS appInventorySnapshot USER_ID [jsonl|appinfo|pkgName|pkgVerMap|pkgUidMap|pkgEnabledMap|sourceDirMap|splitSourceDirsMap|pkgApkPathMap] [user|system|xposed|all] [refresh]\n";
        }
        int userId = parseInt(args[1], 0);
        String format = args.length >= 3 && args[2] != null && !args[2].isEmpty() ? args[2] : "jsonl";
        String filter = args.length >= 4 && args[3] != null && !args[3].isEmpty() ? args[3] : "all";
        boolean refresh = false;
        for (String a : args) {
            if ("refresh".equalsIgnoreCase(a) || "--refresh".equalsIgnoreCase(a)) {
                refresh = true;
                break;
            }
        }
        return render(userId, format, filter, refresh);
    }

    static synchronized String render(int userId, String format, String filter, boolean refresh) throws Exception {
        List<Item> items = snapshot(userId, refresh);
        StringBuilder out = new StringBuilder(items.size() * 96);
        for (Item item : items) {
            if (!matchesFilter(item, filter)) continue;
            switch (format) {
                case "pkgName":
                    out.append(item.packageName).append('\n');
                    break;
                case "pkgVerMap":
                    if (item.versionCode >= 0) {
                        out.append(item.packageName).append('\t').append(item.versionCode).append('\n');
                    }
                    break;
                case "pkgUidMap":
                    if (item.uid >= 0) {
                        out.append(item.packageName).append('\t').append(item.uid).append('\n');
                    }
                    break;
                case "pkgEnabledMap":
                    out.append(item.packageName).append('\t').append(item.enabled ? "true" : "false").append('\n');
                    break;
                case "sourceDirMap":
                    if (item.sourceDir != null && !item.sourceDir.isEmpty()) {
                        out.append(item.packageName).append('\t').append(item.sourceDir).append('\n');
                    }
                    break;
                case "splitSourceDirsMap":
                    if (item.splitSourceDirs != null && item.splitSourceDirs.length > 0) {
                        out.append(item.packageName).append('\t').append(String.join("|", item.splitSourceDirs)).append('\n');
                    }
                    break;
                case "pkgApkPathMap":
                    if (item.sourceDir != null && !item.sourceDir.isEmpty()) {
                        out.append(item.packageName).append('\t').append(item.sourceDir).append('\n');
                    }
                    if (item.splitSourceDirs != null) {
                        for (String split : item.splitSourceDirs) {
                            if (split != null && !split.isEmpty()) {
                                out.append(item.packageName).append('\t').append(split).append('\n');
                            }
                        }
                    }
                    break;
                case "appinfo":
                    out.append(removeSpaces(item.label)).append(' ')
                            .append(item.packageName).append(' ')
                            .append(item.flag).append('\n');
                    break;
                case "jsonl":
                default:
                    out.append(GSON.toJson(item.toJson())).append('\n');
                    break;
            }
        }
        return out.toString();
    }

    static synchronized List<Item> snapshot(int userId, boolean refresh) throws Exception {
        Locale locale = AppLocale.parse(System.getenv("APP_LABEL_LOCALE"));
        String cacheKey = userId + "|" + (locale == null ? "" : locale.toLanguageTag());
        if (!refresh) {
            List<Item> cached = CACHE.get(cacheKey);
            if (cached != null) return cached;
        }
        Context ctx = HiddenApiHelper.getContext();
        PackageManagerUtil.PackageManagerWithLocale pmWithLocale = PackageManagerUtil.getPackageManager(ctx);
        PackageManager pm = pmWithLocale.packageManager();
        Locale effectiveLocale = pmWithLocale.locale();
        if (effectiveLocale == null) effectiveLocale = locale;
        PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
        List<PackageInfo> packages = pmHidden.getInstalledPackagesAsUser(PackageManager.GET_META_DATA, userId);
        List<Item> items = new ArrayList<>();
        if (packages != null) {
            for (PackageInfo pkg : packages) {
                Item item = toItem(pm, pkg, userId);
                if (item != null && item.packageName != null && !item.packageName.isEmpty()) {
                    items.add(item);
                }
            }
        }
        Collator collator = Collator.getInstance(effectiveLocale != null ? effectiveLocale : Locale.getDefault());
        items.sort((a, b) -> collator.getCollationKey(a.label == null ? "" : a.label)
                .compareTo(collator.getCollationKey(b.label == null ? "" : b.label)));
        CACHE.put(cacheKey, items);
        return items;
    }

    static synchronized void clearCache() {
        CACHE.clear();
    }

    private static Item toItem(PackageManager pm, PackageInfo pkg, int userId) {
        try {
            if (pkg == null || pkg.applicationInfo == null || pkg.packageName == null) return null;
            ApplicationInfo ai = pkg.applicationInfo;
            Item item = new Item();
            item.userId = userId;
            item.packageName = pkg.packageName;
            item.label = safeLabel(pm, ai, pkg.packageName);
            item.uid = ai.uid;
            item.versionCode = longVersionCode(pkg);
            item.versionName = pkg.versionName == null ? "" : pkg.versionName;
            item.enabled = ai.enabled;
            item.installed = true;
            item.system = (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
            item.updatedSystem = (ai.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0;
            item.xposed = isXposed(ai);
            item.sourceDir = ai.sourceDir == null ? "" : ai.sourceDir;
            item.splitSourceDirs = ai.splitSourceDirs == null ? new String[0] : ai.splitSourceDirs;
            item.splitCount = item.splitSourceDirs.length;
            List<String> flags = new ArrayList<>();
            if (!item.system) flags.add("user");
            if (item.system) flags.add("system");
            if (item.xposed) flags.add("xposed");
            item.flag = String.join("|", flags);
            if (item.xposed) item.category = "xposed";
            else if (item.system) item.category = "system";
            else item.category = "user";
            return item;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static boolean matchesFilter(Item item, String filter) {
        if (item == null) return false;
        if (filter == null || filter.isEmpty() || "all".equals(filter)) return true;
        List<String> fs = Arrays.asList(filter.split("\\|"));
        return (fs.contains("user") && !item.system)
                || (fs.contains("system") && item.system)
                || (fs.contains("xposed") && item.xposed);
    }

    private static String safeLabel(PackageManager pm, ApplicationInfo ai, String fallback) {
        try {
            CharSequence label = ai.loadLabel(pm);
            if (label != null) {
                String value = label.toString().replace('\n', ' ').replace('\r', ' ').trim();
                if (!value.isEmpty()) return value;
            }
        } catch (Throwable ignored) {
        }
        return fallback == null ? "" : fallback;
    }

    private static long longVersionCode(PackageInfo pkg) {
        try {
            if (Build.VERSION.SDK_INT >= 28) return pkg.getLongVersionCode();
        } catch (Throwable ignored) {
        }
        try {
            return pkg.versionCode;
        } catch (Throwable ignored) {
            return -1L;
        }
    }

    private static String removeSpaces(String string) {
        return string == null ? "" : string.replaceAll("\\s", "");
    }

    private static boolean isXposed(ApplicationInfo info) {
        if (info == null) return false;
        try {
            if (info.metaData != null && info.metaData.containsKey(XPOSED_METADATA)) return true;
        } catch (Throwable ignored) {
        }
        return isModernModules(info);
    }

    private static boolean isModernModules(ApplicationInfo info) {
        String[] apks;
        if (info == null || info.sourceDir == null) return false;
        if (info.splitSourceDirs != null) {
            apks = Arrays.copyOf(info.splitSourceDirs, info.splitSourceDirs.length + 1);
            apks[info.splitSourceDirs.length] = info.sourceDir;
        } else {
            apks = new String[]{info.sourceDir};
        }
        for (String apk : apks) {
            if (apk == null || apk.isEmpty()) continue;
            try (ZipFile zip = new ZipFile(apk)) {
                if (zip.getEntry("META-INF/xposed/java_init.list") != null) return true;
            } catch (IOException ignored) {
            }
        }
        return false;
    }

    private static int parseInt(String raw, int fallback) {
        try { return Integer.parseInt(raw == null ? "" : raw.trim()); } catch (Throwable ignored) { return fallback; }
    }

    static final class Item {
        int userId;
        String packageName;
        String label;
        int uid;
        long versionCode;
        String versionName;
        boolean enabled;
        boolean installed;
        boolean system;
        boolean updatedSystem;
        boolean xposed;
        String flag;
        String category;
        String sourceDir;
        String[] splitSourceDirs;
        int splitCount;

        JsonObject toJson() {
            JsonObject o = new JsonObject();
            o.addProperty("schema", "speedbackup.app_inventory.v1");
            o.addProperty("userId", userId);
            o.addProperty("packageName", packageName == null ? "" : packageName);
            o.addProperty("label", label == null ? "" : label);
            o.addProperty("uid", uid);
            o.addProperty("versionCode", versionCode);
            o.addProperty("versionName", versionName == null ? "" : versionName);
            o.addProperty("enabled", enabled);
            o.addProperty("installed", installed);
            o.addProperty("system", system);
            o.addProperty("updatedSystem", updatedSystem);
            o.addProperty("xposed", xposed);
            o.addProperty("flag", flag == null ? "" : flag);
            o.addProperty("category", category == null ? "" : category);
            o.addProperty("sourceDir", sourceDir == null ? "" : sourceDir);
            JsonArray splits = new JsonArray();
            if (splitSourceDirs != null) {
                for (String split : splitSourceDirs) {
                    if (split != null && !split.isEmpty()) splits.add(split);
                }
            }
            o.add("splitSourceDirs", splits);
            o.addProperty("splitCount", splitCount);
            return o;
        }
    }
}
