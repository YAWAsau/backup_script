package com.xayah.dex;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipFile;
import java.util.zip.ZipEntry;

/** Canonical Xposed module package scanner shared by all AppInventory paths. */
final class XposedModuleScanner {
    static final String LEGACY_ENTRY = "assets/xposed_init";
    static final String MODERN_JAVA_ENTRY = "META-INF/xposed/java_init.list";
    static final String MODERN_NATIVE_ENTRY = "META-INF/xposed/native_init.list";
    static final String MODERN_MODULE_PROP = "META-INF/xposed/module.prop";
    static final String MODERN_SCOPE_LIST = "META-INF/xposed/scope.list";

    private XposedModuleScanner() {}

    static boolean legacyMetadata(Object value) {
        return Boolean.TRUE.equals(value);
    }

    private static boolean hasEntry(ZipFile zip, String name) throws IOException {
        ZipEntry entry = zip.getEntry(name);
        if (entry == null || entry.isDirectory()) return false;
        int limit = 65536;
        if (entry.getSize() > limit) throw new IOException("Oversize Xposed entry");
        int capacity = entry.getSize() < 0 ? limit + 1 : (int) entry.getSize() + 1;
        byte[] bytes = new byte[capacity];
        int length = 0;
        try (InputStream input = zip.getInputStream(entry)) {
            while (length < bytes.length) {
                int count = input.read(bytes, length, bytes.length - length);
                if (count < 0) break;
                if (count == 0) throw new IOException("Incomplete Xposed entry");
                length += count;
            }
        }
        if (length == capacity || (entry.getSize() >= 0 && length != entry.getSize())) {
            throw new IOException("Oversize or inconsistent Xposed entry");
        }
        String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes, 0, length)).toString();
        if (text.indexOf('\0') >= 0) throw new IOException("Invalid Xposed entry");
        for (String line : text.split("\\r?\\n")) {
            String value = line.trim();
            if (!value.isEmpty() && !value.startsWith("#")) return true;
        }
        return false;
    }

    static Facts inspect(boolean legacyMetadata, String sourceDir, String[] splitSourceDirs) {
        Facts out = new Facts();
        out.legacyMetadata = legacyMetadata;
        List<String> evidence = new ArrayList<>();
        if (legacyMetadata) evidence.add("legacy-metadata");

        scanApk(out, sourceDir, evidence);
        if (splitSourceDirs != null) {
            for (String split : splitSourceDirs) scanApk(out, split, evidence);
        }

        boolean legacy = out.legacyMetadata || out.legacyEntry;
        boolean modern = out.modernJavaEntry || out.modernNativeEntry;
        out.module = legacy || modern;
        if (legacy && modern) {
            out.moduleFormat = "hybrid";
        } else if (legacy) {
            out.moduleFormat = "legacy";
        } else if (out.modernJavaEntry && out.modernNativeEntry) {
            out.moduleFormat = "modern-java-native";
        } else if (out.modernJavaEntry) {
            out.moduleFormat = "modern-java";
        } else if (out.modernNativeEntry) {
            out.moduleFormat = "modern-native";
        } else {
            out.moduleFormat = "none";
        }
        out.evidence = String.join(",", evidence);
        return out;
    }

    private static void scanApk(Facts out, String apk, List<String> evidence) {
        if (apk == null || apk.isEmpty()) {
            out.apkErrors++;
            return;
        }
        try (ZipFile zip = new ZipFile(apk)) {
            out.apkScanned++;
            if (!out.legacyEntry && hasEntry(zip, LEGACY_ENTRY)) {
                out.legacyEntry = true;
                evidence.add("assets/xposed_init");
            }
            if (!out.modernJavaEntry && hasEntry(zip, MODERN_JAVA_ENTRY)) {
                out.modernJavaEntry = true;
                evidence.add("java_init.list");
            }
            if (!out.modernNativeEntry && hasEntry(zip, MODERN_NATIVE_ENTRY)) {
                out.modernNativeEntry = true;
                evidence.add("native_init.list");
            }
            if (!out.moduleProp && zip.getEntry(MODERN_MODULE_PROP) != null) {
                out.moduleProp = true;
                evidence.add("module.prop");
            }
            if (!out.scopeList && zip.getEntry(MODERN_SCOPE_LIST) != null) {
                out.scopeList = true;
                evidence.add("scope.list");
            }
        } catch (IOException | RuntimeException ignored) {
            out.apkErrors++;
        }
    }

    static final class Facts {
        boolean module;
        boolean legacyMetadata;
        boolean legacyEntry;
        boolean modernJavaEntry;
        boolean modernNativeEntry;
        boolean moduleProp;
        boolean scopeList;
        int apkScanned;
        int apkErrors;
        String moduleFormat = "none";
        String evidence = "";
    }
}
