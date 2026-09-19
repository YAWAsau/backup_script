package com.xayah.dex;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManagerHidden;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

import dev.rikka.tools.refine.Refine;

/**
 * Positive-evidence-only Xposed framework/manager facts.
 * Missing package/module evidence is reported as unknown, never as framework absence.
 */
final class XposedRuntimeFactsUtil {
    private static final String[] STANDALONE_MANAGERS = new String[]{
            "org.lsposed.manager",
            "org.meowcat.edxposed.manager",
            "de.robv.android.xposed.installer"
    };

    private XposedRuntimeFactsUtil() {}

    static Facts inspect(int userId) {
        Facts out = new Facts();
        List<String> frameworkEvidence = new ArrayList<>();
        List<String> managerEvidence = new ArrayList<>();

        File lspd = new File("/data/adb/lspd");
        if (lspd.isDirectory()) {
            out.frameworkState = "detected";
            out.frameworkFamily = "lsposed";
            out.parasiticHint = true;
            frameworkEvidence.add("data:/data/adb/lspd");
        }
        scanRootModules(out, frameworkEvidence);
        scanManagerPackages(out, managerEvidence, userId);

        if (!frameworkEvidence.isEmpty()) out.frameworkEvidence = String.join(",", frameworkEvidence);
        if (!managerEvidence.isEmpty()) out.managerEvidence = String.join(",", managerEvidence);
        if ("lsposed".equals(out.frameworkFamily) && "unknown".equals(out.managerMode) && out.parasiticHint) {
            out.managerOpenCap = "root-parasitic-hint";
        }
        return out;
    }

    private static void scanRootModules(Facts out, List<String> evidence) {
        File root = new File("/data/adb/modules");
        File[] dirs = root.listFiles(File::isDirectory);
        if (dirs == null || dirs.length == 0) return;
        Arrays.sort(dirs, (a, b) -> a.getName().compareTo(b.getName()));
        int seen = 0;
        for (File dir : dirs) {
            if (++seen > 128) break;
            File prop = new File(dir, "module.prop");
            if (!prop.isFile() || new File(dir, "disable").exists() || new File(dir, "remove").exists()) continue;
            String text = readModulePropBounded(prop).toLowerCase(Locale.US);
            String family = familyFromText(text);
            if (family == null) continue;
            mergeFrameworkFamily(out, family);
            out.frameworkState = "detected";
            evidence.add("module:" + safeToken(dir.getName()));
            if ("lsposed".equals(family)) out.parasiticHint = true;
        }
    }

    private static String readModulePropBounded(File file) {
        StringBuilder out = new StringBuilder(1024);
        try (BufferedReader br = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line;
            int lines = 0;
            while ((line = br.readLine()) != null && ++lines <= 96 && out.length() < 16384) {
                String s = line.trim();
                if (s.startsWith("id=") || s.startsWith("name=")) {
                    out.append(s).append('\n');
                }
            }
        } catch (Throwable ignored) {}
        return out.toString();
    }

    private static String familyFromText(String text) {
        if (text == null || text.isEmpty()) return null;
        if (text.contains("lsposed") || text.contains("lspd")) return "lsposed";
        if (text.contains("edxposed")) return "edxposed";
        if (text.contains("xposed")) return "xposed";
        return null;
    }

    private static void mergeFrameworkFamily(Facts out, String family) {
        if (family == null || family.isEmpty()) return;
        if ("unknown".equals(out.frameworkFamily)) {
            out.frameworkFamily = family;
            return;
        }
        if (out.frameworkFamily.equals(family)) return;
        if ("lsposed".equals(family) || "lsposed".equals(out.frameworkFamily)) out.frameworkFamily = "lsposed";
        else if ("edxposed".equals(family) || "edxposed".equals(out.frameworkFamily)) out.frameworkFamily = "edxposed";
    }

    private static void scanManagerPackages(Facts out, List<String> evidence, int userId) {
        try {
            PackageManager pm = PackageManagerUtil.getPackageManager(HiddenApiHelper.getContext()).packageManager();
            PackageManagerHidden pmHidden = Refine.unsafeCast(pm);
            int[] users = userId == 0 ? new int[]{0} : new int[]{userId, 0};
            outer:
            for (String pkg : STANDALONE_MANAGERS) {
                for (int candidateUser : users) {
                    try {
                        PackageInfo pi = pmHidden.getPackageInfoAsUser(pkg, PackageManager.GET_META_DATA, candidateUser);
                        if (pi == null || pi.applicationInfo == null) continue;
                        out.managerMode = "standalone";
                        out.managerPackage = pkg;
                        if ("org.lsposed.manager".equals(pkg)) {
                            out.managerFamily = "lsposed";
                        } else if ("org.meowcat.edxposed.manager".equals(pkg)) {
                            out.managerFamily = "edxposed";
                        } else if ("de.robv.android.xposed.installer".equals(pkg)) {
                            out.managerFamily = "xposed";
                        }
                        evidence.add("manager:" + pkg + "@" + candidateUser);
                        try {
                            out.managerOpenCap = pm.getLaunchIntentForPackage(pkg) != null ? "direct" : "installed-no-launcher";
                        } catch (Throwable ignored) {
                            out.managerOpenCap = "installed";
                        }
                        break outer;
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable ignored) {}
    }

    private static String safeToken(String value) {
        if (value == null) return "";
        return value.replace('\t', '_').replace('\n', '_').replace('\r', '_').replace(' ', '_');
    }

    static final class Facts {
        String frameworkState = "unknown";
        String frameworkFamily = "unknown";
        String frameworkEvidence = "";
        String managerMode = "unknown";
        String managerFamily = "unknown";
        String managerPackage = "";
        String managerOpenCap = "unknown";
        String managerEvidence = "";
        boolean parasiticHint = false;

        String toTsv() {
            return safeToken(frameworkState) + '\t'
                    + safeToken(frameworkFamily) + '\t'
                    + safeToken(frameworkEvidence) + '\t'
                    + safeToken(managerMode) + '\t'
                    + safeToken(managerFamily) + '\t'
                    + safeToken(managerPackage) + '\t'
                    + safeToken(managerOpenCap) + '\t'
                    + (parasiticHint ? "true" : "false");
        }
    }
}
