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

import java.io.File;
import java.io.IOException;
import java.text.Collator;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipFile;

import dev.rikka.tools.refine.Refine;

/**
 * SpeedBackup App inventory snapshot.
 *
 * One PackageManager scan provides label/pkg/uid/version/source/flag/category data for shell.
 * In a persistent root daemon this class keeps a per-user/per-locale cache for the current run.
 */
final class AppInventoryUtil {
    static final String VERSION = "v1.3.12-r370-framework-facts";
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

    static synchronized String runGetlistCommand(String[] args) throws Exception {
        if (args == null || args.length < 2) {
            return "APP_INVENTORY_GETLIST_BAD_ARGS appInventoryGetlist USER_ID [targetPackageCsv] [refresh]\n";
        }
        int userId = parseInt(args[1], 0);
        String targetCsv = args.length >= 3 && args[2] != null ? args[2] : "";
        boolean refresh = false;
        for (String a : args) {
            if ("refresh".equalsIgnoreCase(a) || "--refresh".equalsIgnoreCase(a)) {
                refresh = true;
                break;
            }
        }
        List<Item> items = snapshot(userId, refresh);
        HomeInfo home = defaultHomeInfo(userId);
        ImeInfo ime = defaultImeInfo(userId);
        Set<String> targets = parsePackageSet(targetCsv);
        if (!home.packageName.isEmpty()) targets.add(home.packageName);
        if (!ime.packageName.isEmpty()) targets.add(ime.packageName);
        StringBuilder out = new StringBuilder(items.size() * 64);
        out.append("#META\tdefaultHome\t")
                .append(sanitize(home.packageName)).append('\t')
                .append(sanitize(home.label)).append('\t')
                .append(sanitize(home.source)).append('\n');
        out.append("#META\tdefaultIme\t")
                .append(sanitize(ime.packageName)).append('\t')
                .append(sanitize(ime.label)).append('\t')
                .append(sanitize(ime.source)).append('\n');
        for (Item item : items) {
            if (item == null || item.packageName == null || item.packageName.isEmpty()) continue;
            boolean include = !item.system || item.xposed || targets.contains(item.packageName);
            if (!include) continue;
            out.append(removeSpaces(item.label)).append(' ')
                    .append(item.packageName).append(' ')
                    .append(item.flag).append('\n');
        }
        return out.toString();
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



    static synchronized String pkgUidSingle(int userId, String packageName, boolean refresh) throws Exception {
        if (packageName == null || packageName.trim().isEmpty()) {
            return "APP_INVENTORY_PKG_UID_BAD_ARGS appInventoryPkgUid USER_ID PACKAGE [refresh]\n";
        }
        String pkgName = packageName.trim();
        if (refresh) {
            clearCache();
        }
        Context ctx = HiddenApiHelper.getContext();
        PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
        PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
        try {
            PackageInfo pkg = pmHidden.getPackageInfoAsUser(pkgName, PackageManager.GET_META_DATA, userId);
            Item item = toItem(pm, pkg, userId);
            if (item != null && item.uid >= 0) {
                return item.packageName + "\t" + item.uid + "\n";
            }
            return "APP_INVENTORY_PKG_UID_MISSING package=" + sanitize(pkgName) + " userId=" + userId + " reason=uid_missing\n";
        } catch (Throwable t) {
            return "APP_INVENTORY_PKG_UID_MISSING package=" + sanitize(pkgName) + " userId=" + userId
                    + " reason=" + sanitize(t.getClass().getSimpleName()) + "\n";
        }
    }

    static synchronized String packageStatusSingle(int userId, String packageName, boolean refresh) throws Exception {
        if (packageName == null || packageName.trim().isEmpty()) {
            return statusMissing(userId, packageName, "BAD_ARGS");
        }
        String pkgName = packageName.trim();
        if (refresh) {
            clearCache();
        }
        Context ctx = HiddenApiHelper.getContext();
        PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
        PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
        try {
            PackageInfo pkg = pmHidden.getPackageInfoAsUser(pkgName, PackageManager.GET_META_DATA, userId);
            Item item = toItem(pm, pkg, userId);
            if (item == null) {
                return statusMissing(userId, pkgName, "ITEM_NULL");
            }
            JsonObject o = item.toJson();
            o.addProperty("schema", "speedbackup.package_status.v1");
            o.addProperty("recordType", "packageStatus");
            o.addProperty("source", "packageManager");
            o.addProperty("reason", "OK");
            o.addProperty("suspended", false);
            addDataDirs(o, userId, item.packageName);
            return GSON.toJson(o) + "\n";
        } catch (Throwable t) {
            return statusMissing(userId, pkgName, t.getClass().getSimpleName());
        }
    }

    static synchronized String packageStatusBatch(int userId, String[] packageNames, boolean refresh) throws Exception {
        if (refresh) {
            clearCache();
        }
        StringBuilder out = new StringBuilder();
        if (packageNames == null || packageNames.length == 0) {
            return statusMissing(userId, "", "BAD_ARGS");
        }
        boolean any = false;
        for (String raw : packageNames) {
            if (raw == null) continue;
            String pkg = raw.trim();
            if (pkg.isEmpty() || "refresh".equalsIgnoreCase(pkg) || "--refresh".equalsIgnoreCase(pkg)) continue;
            any = true;
            out.append(packageStatusSingle(userId, pkg, false));
        }
        if (!any) out.append(statusMissing(userId, "", "BAD_ARGS"));
        return out.toString();
    }

    static synchronized String packageFactsBatch(int userId, String[] packageNames, boolean refresh) throws Exception {
        if (refresh) clearCache();
        StringBuilder out = new StringBuilder();
        out.append("#schema\tspeedbackup.pm_facts.v1\n");
        out.append("#fields\tpackage\tinstalled\tuid\tversionCode\tversionName\tenabled\tsystem\tupdatedSystem\txposed\tcategory\tinstaller\tsourceDir\tpublicSourceDir\tsplitCount\tsplitSourceDirs\tdataDir\tdeDataDir\tuserDataExists\tuserDeDataExists\treason\n");
        if (packageNames == null || packageNames.length == 0) {
            out.append("MISSING\t\tfalse\t-1\t-1\t\tfalse\tfalse\tfalse\tfalse\t\t\t\t\t0\t\t\t\tfalse\tfalse\tBAD_ARGS\n");
            return out.toString();
        }
        Context ctx = HiddenApiHelper.getContext();
        PackageManager pm = PackageManagerUtil.getPackageManager(ctx).packageManager();
        PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
        boolean any = false;
        for (String raw : packageNames) {
            if (raw == null) continue;
            String pkgName = raw.trim();
            if (pkgName.isEmpty() || "refresh".equalsIgnoreCase(pkgName) || "--refresh".equalsIgnoreCase(pkgName)) continue;
            any = true;
            try {
                PackageInfo pkg = pmHidden.getPackageInfoAsUser(pkgName, PackageManager.GET_META_DATA, userId);
                Item item = toItem(pm, pkg, userId);
                if (item == null) {
                    appendMissingFact(out, userId, pkgName, "ITEM_NULL");
                } else {
                    appendItemFact(out, item, "OK");
                }
            } catch (Throwable t) {
                appendMissingFact(out, userId, pkgName, t.getClass().getSimpleName());
            }
        }
        if (!any) appendMissingFact(out, userId, "", "BAD_ARGS");
        return out.toString();
    }

    private static void appendItemFact(StringBuilder out, Item item, String reason) {
        String splits = item.splitSourceDirs == null ? "" : String.join("|", item.splitSourceDirs);
        String userDataDir = item.packageName == null || item.packageName.isEmpty() ? "" : "/data/user/" + item.userId + "/" + item.packageName;
        String userDeDataDir = item.packageName == null || item.packageName.isEmpty() ? "" : "/data/user_de/" + item.userId + "/" + item.packageName;
        out.append("OK").append('\t')
                .append(sanitize(item.packageName)).append('\t')
                .append(item.installed).append('\t')
                .append(item.uid).append('\t')
                .append(item.versionCode).append('\t')
                .append(sanitize(item.versionName)).append('\t')
                .append(item.enabled).append('\t')
                .append(item.system).append('\t')
                .append(item.updatedSystem).append('\t')
                .append(item.xposed).append('\t')
                .append(sanitize(item.category)).append('\t')
                .append(sanitize(item.installerPackageName)).append('\t')
                .append(sanitize(item.sourceDir)).append('\t')
                .append(sanitize(item.publicSourceDir)).append('\t')
                .append(item.splitCount).append('\t')
                .append(sanitize(splits)).append('\t')
                .append(sanitize(userDataDir)).append('\t')
                .append(sanitize(userDeDataDir)).append('\t')
                .append(!userDataDir.isEmpty() && new File(userDataDir).isDirectory()).append('\t')
                .append(!userDeDataDir.isEmpty() && new File(userDeDataDir).isDirectory()).append('\t')
                .append(sanitize(reason)).append('\n');
    }

    private static void appendMissingFact(StringBuilder out, int userId, String pkgName, String reason) {
        String pkg = pkgName == null ? "" : pkgName.trim();
        String userDataDir = pkg.isEmpty() ? "" : "/data/user/" + userId + "/" + pkg;
        String userDeDataDir = pkg.isEmpty() ? "" : "/data/user_de/" + userId + "/" + pkg;
        out.append("MISSING").append('\t')
                .append(sanitize(pkg)).append('\t')
                .append("false\t-1\t-1\t\tfalse\tfalse\tfalse\tfalse\t\t\t\t\t0\t\t")
                .append(sanitize(userDataDir)).append('\t')
                .append(sanitize(userDeDataDir)).append('\t')
                .append(!userDataDir.isEmpty() && new File(userDataDir).isDirectory()).append('\t')
                .append(!userDeDataDir.isEmpty() && new File(userDeDataDir).isDirectory()).append('\t')
                .append(sanitize(reason)).append('\n');
    }

    private static String statusMissing(int userId, String packageName, String reason) {
        String pkgName = packageName == null ? "" : packageName.trim();
        JsonObject o = new JsonObject();
        o.addProperty("schema", "speedbackup.package_status.v1");
        o.addProperty("recordType", "packageStatus");
        o.addProperty("userId", userId);
        o.addProperty("packageName", pkgName);
        o.addProperty("installed", false);
        o.addProperty("uid", -1);
        o.addProperty("versionCode", -1L);
        o.addProperty("versionName", "");
        o.addProperty("enabled", false);
        o.addProperty("suspended", false);
        o.addProperty("sourceDir", "");
        o.add("splitSourceDirs", new JsonArray());
        o.addProperty("splitCount", 0);
        o.addProperty("source", "packageManager");
        o.addProperty("reason", sanitize(reason));
        addDataDirs(o, userId, pkgName);
        return GSON.toJson(o) + "\n";
    }

    private static void addDataDirs(JsonObject o, int userId, String packageName) {
        String pkgName = packageName == null ? "" : packageName.trim();
        String userDataDir = pkgName.isEmpty() ? "" : "/data/user/" + userId + "/" + pkgName;
        String userDeDataDir = pkgName.isEmpty() ? "" : "/data/user_de/" + userId + "/" + pkgName;
        o.addProperty("dataDir", userDataDir);
        o.addProperty("deDataDir", userDeDataDir);
        o.addProperty("userDataExists", !userDataDir.isEmpty() && new File(userDataDir).isDirectory());
        o.addProperty("userDeDataExists", !userDeDataDir.isEmpty() && new File(userDeDataDir).isDirectory());
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
            item.publicSourceDir = ai.publicSourceDir == null ? "" : ai.publicSourceDir;
            try { item.installerPackageName = pm.getInstallerPackageName(pkg.packageName); } catch (Throwable ignored) { item.installerPackageName = ""; }
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
        String f = filter.trim();
        if (f.startsWith("packages:")) {
            String list = f.substring("packages:".length());
            if (list.isEmpty()) return false;
            for (String p : list.split("[,|\\s]+")) {
                if (p != null && p.equals(item.packageName)) return true;
            }
            return false;
        }
        List<String> fs = Arrays.asList(filter.split("\\|"));
        return (fs.contains("user") && !item.system)
                || (fs.contains("system") && item.system)
                || (fs.contains("xposed") && item.xposed);
    }

    private static String safeLabel(PackageManager pm, ApplicationInfo ai, String fallback) {
        try {
            CharSequence label = ai.loadLabel(pm);
            if (label != null) {
                String value = safePathLabel(label.toString(), fallback);
                if (!value.isEmpty()) return value;
            }
        } catch (Throwable ignored) {
        }
        return safePathLabel(fallback, "app");
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
        return safePathLabel(string, "app");
    }

    private static String safePathLabel(String string, String fallback) {
        String value = string == null ? "" : string.replaceAll("\\s+", "").replace('/', '_').replace('\\', '_').replace("..", "__");
        if (value.isEmpty() || ".".equals(value) || "..".equals(value)) {
            value = fallback == null ? "" : fallback.replaceAll("[^A-Za-z0-9._-]", "_").replace("..", "__");
        }
        if (value.isEmpty() || ".".equals(value) || "..".equals(value)) value = "app";
        return value;
    }

    private static String sanitize(String value) {
        if (value == null) return "";
        return value.replace('\n', '_').replace('\r', '_').replace('\t', '_').replace(' ', '_');
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

    private static Set<String> parsePackageSet(String raw) {
        Set<String> out = new HashSet<>();
        if (raw == null || raw.trim().isEmpty()) return out;
        for (String p : raw.split("[,|\\s]+")) {
            if (p == null) continue;
            String pkg = p.trim();
            if (pkg.matches("[A-Za-z0-9_.-]+") && !pkg.startsWith(".") && !pkg.contains("..")) out.add(pkg);
        }
        return out;
    }

    private static HomeInfo defaultHomeInfo(int userId) {
        HomeInfo out = new HomeInfo();
        try {
            AppStateEngine.EngineResponse response = AppStateEngine.defaultHome(userId);
            String body = response == null ? "" : response.body;
            for (String line : body.split("\\n")) {
                if (line == null || line.trim().isEmpty()) continue;
                JsonObject o = GSON.fromJson(line, JsonObject.class);
                if (o == null || !"defaultHome".equals(jsonString(o, "recordType"))) continue;
                JsonObject result = o.has("result") && o.get("result").isJsonObject()
                        ? o.getAsJsonObject("result") : null;
                String resultName = result == null ? "" : jsonString(result, "name");
                if (!"OK".equals(resultName) || jsonBoolean(o, "isResolver", true)) continue;
                String pkg = jsonString(o, "packageName");
                if (!pkg.matches("[A-Za-z0-9_.-]+") || pkg.startsWith(".") || pkg.contains("..")) continue;
                out.packageName = pkg;
                out.label = safePathLabel(jsonString(o, "label"), pkg);
                out.source = jsonString(o, "source");
                return out;
            }
        } catch (Throwable ignored) {}
        return out;
    }


    private static final class ImeInfo {
        String packageName = "";
        String label = "";
        String source = "";
    }

    private static ImeInfo defaultImeInfo(int userId) {
        ImeInfo out = new ImeInfo();
        try {
            AppStateEngine.EngineResponse response = AppStateEngine.defaultIme(userId);
            String body = response == null ? "" : response.body;
            for (String line : body.split("\\n")) {
                if (line == null || line.trim().isEmpty()) continue;
                JsonObject o = GSON.fromJson(line, JsonObject.class);
                if (o == null || !"defaultIme".equals(jsonString(o, "recordType"))) continue;
                JsonObject result = o.has("result") && o.get("result").isJsonObject()
                        ? o.getAsJsonObject("result") : null;
                String resultName = result == null ? "" : jsonString(result, "name");
                if (!"OK".equals(resultName)) continue;
                String pkg = jsonString(o, "packageName");
                if (!pkg.matches("[A-Za-z0-9_.-]+") || pkg.startsWith(".") || pkg.contains("..")) continue;
                out.packageName = pkg;
                out.label = safePathLabel(jsonString(o, "label"), pkg);
                out.source = jsonString(o, "source");
                return out;
            }
        } catch (Throwable ignored) {}
        return out;
    }

    private static String jsonString(JsonObject object, String key) {
        try {
            if (object != null && object.has(key) && !object.get(key).isJsonNull()) {
                return object.get(key).getAsString();
            }
        } catch (Throwable ignored) {}
        return "";
    }

    private static boolean jsonBoolean(JsonObject object, String key, boolean fallback) {
        try {
            if (object != null && object.has(key) && !object.get(key).isJsonNull()) {
                return object.get(key).getAsBoolean();
            }
        } catch (Throwable ignored) {}
        return fallback;
    }

    static final class HomeInfo {
        String packageName = "";
        String label = "";
        String source = "";
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
        String publicSourceDir;
        String installerPackageName;
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
            o.addProperty("publicSourceDir", publicSourceDir == null ? "" : publicSourceDir);
            o.addProperty("installerPackageName", installerPackageName == null ? "" : installerPackageName);
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
