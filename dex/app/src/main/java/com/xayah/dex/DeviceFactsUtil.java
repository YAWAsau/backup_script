package com.xayah.dex;

import android.os.Build;
import android.os.SystemProperties;

import java.util.Locale;

final class DeviceFactsUtil {
    static final String SCHEMA = "speedbackup.device_facts.v1";

    private DeviceFactsUtil() {}

    static String json() {
        String manufacturer = nz(Build.MANUFACTURER);
        String brand = nz(Build.BRAND);
        String model = nz(Build.MODEL);
        String device = nz(Build.DEVICE);
        String product = nz(Build.PRODUCT);
        String board = nz(Build.BOARD);
        String hardware = nz(Build.HARDWARE);
        String fingerprint = nz(Build.FINGERPRINT);
        String bootloader = nz(Build.BOOTLOADER);
        String display = nz(Build.DISPLAY);
        String release = nz(Build.VERSION.RELEASE);
        String incremental = nz(Build.VERSION.INCREMENTAL);
        String securityPatch = nz(Build.VERSION.SECURITY_PATCH);
        String socModel = prop("ro.soc.model");
        String socManufacturer = prop("ro.soc.manufacturer");
        String miuiVersion = prop("ro.miui.ui.version.name");
        String hyperosVersion = firstNonEmpty(prop("ro.mi.os.version.name"), prop("ro.miui.ui.version.name"));
        String colorosVersion = firstNonEmpty(prop("ro.build.version.oplusrom"), prop("ro.build.version.ota"));
        String oneuiVersion = prop("ro.build.version.oneui");
        String propMarketName = firstNonEmpty(
                prop("ro.product.marketname"),
                firstNonEmpty(prop("ro.product.vendor.marketname"), prop("ro.product.odm.marketname")));

        String[][] candidates = modelCandidates(brand, manufacturer, model, product, device, board, fingerprint);
        DeviceModelDb.Match match = DeviceModelDb.match(candidates);
        String marketName;
        String marketNameZh;
        String source;
        String confidence;
        String matchedKey;
        String matchedField;
        if (match != null && match.entry != null) {
            marketName = match.entry.marketName;
            marketNameZh = match.entry.marketNameZh;
            source = match.source;
            confidence = match.confidence;
            matchedKey = match.matchedKey;
            matchedField = match.matchedField;
        } else {
            marketName = firstNonEmpty(propMarketName, model);
            marketNameZh = marketName;
            source = propMarketName.isEmpty() ? "raw_build_model" : "raw_prop_marketname";
            confidence = "fallback_raw_model";
            matchedKey = "";
            matchedField = "";
        }

        StringBuilder b = new StringBuilder(2048);
        b.append('{');
        add(b, "schema", SCHEMA).append(',');
        add(b, "dexVersion", HiddenApiUtil.VERSION).append(',');
        add(b, "modelDbVersion", DeviceModelDb.DB_VERSION).append(',');
        add(b, "modelDbEntryCount", DeviceModelDb.entryCount()).append(',');
        add(b, "modelDbSourceLines", DeviceModelDb.sourceLineCount()).append(',');
        add(b, "modelDbSourceSha256", DeviceModelDb.SOURCE_SHA256).append(',');
        add(b, "sdk", Build.VERSION.SDK_INT).append(',');
        add(b, "release", release).append(',');
        add(b, "incremental", incremental).append(',');
        add(b, "securityPatch", securityPatch).append(',');
        add(b, "manufacturer", manufacturer).append(',');
        add(b, "brand", brand).append(',');
        add(b, "model", model).append(',');
        add(b, "device", device).append(',');
        add(b, "product", product).append(',');
        add(b, "board", board).append(',');
        add(b, "hardware", hardware).append(',');
        add(b, "bootloader", bootloader).append(',');
        add(b, "display", display).append(',');
        add(b, "fingerprint", fingerprint).append(',');
        add(b, "abi", join(Build.SUPPORTED_ABIS)).append(',');
        add(b, "socModel", socModel).append(',');
        add(b, "socManufacturer", socManufacturer).append(',');
        add(b, "propMarketName", propMarketName).append(',');
        add(b, "modelKeyCandidates", compactCandidates(candidates)).append(',');
        add(b, "marketName", marketName).append(',');
        add(b, "marketNameZh", marketNameZh).append(',');
        add(b, "modelNameSource", source).append(',');
        add(b, "modelNameConfidence", confidence).append(',');
        add(b, "matchedKey", matchedKey).append(',');
        add(b, "matchedField", matchedField).append(',');
        b.append("\"rom\":{");
        add(b, "miui", !miuiVersion.isEmpty()).append(',');
        add(b, "hyperos", isHyperOs(hyperosVersion, fingerprint, display)).append(',');
        add(b, "coloros", isColorOs(colorosVersion, fingerprint, display, brand, manufacturer)).append(',');
        add(b, "oneui", !oneuiVersion.isEmpty());
        b.append('}');
        b.append('}').append('\n');
        return b.toString();
    }

    /**
     * r397: Prefer public product model properties before vendor/system/bootimage
     * partition model values. r396 correctly added more raw model-code candidates,
     * but on OPlus/OnePlus builds `ro.product.vendor.model` can carry a regional
     * build/fingerprint code (for example CPH2745IN) while the user-visible device
     * model remains ro.product.model/Build.MODEL (for example CPH2747). Matching
     * vendor first can therefore show the wrong regional variant.
     *
     * Keep vendor/system/bootimage candidates as fallback so Xiaomi/other devices
     * whose Build.MODEL is already a marketing name can still resolve exact raw
     * model codes when those are only exposed through partition props.
     */
    private static String[][] modelCandidates(String brand, String manufacturer, String model, String product, String device, String board, String fingerprint) {
        return new String[][] {
                // Public/user-visible model candidates first.
                {"prop:ro.product.model_for_attestation", prop("ro.product.model_for_attestation")},
                {"prop:ro.product.model", prop("ro.product.model")},
                {"prop:ro.product.odm.model", prop("ro.product.odm.model")},
                {"prop:ro.product.product.model", prop("ro.product.product.model")},
                {"model", model},
                {"product", product},

                // Other attestation / partition model codes as fallback.
                {"prop:ro.product.odm.model_for_attestation", prop("ro.product.odm.model_for_attestation")},
                {"prop:ro.product.product.model_for_attestation", prop("ro.product.product.model_for_attestation")},
                {"prop:ro.product.vendor.model_for_attestation", prop("ro.product.vendor.model_for_attestation")},
                {"prop:ro.product.system.model_for_attestation", prop("ro.product.system.model_for_attestation")},
                {"prop:ro.product.bootimage.model_for_attestation", prop("ro.product.bootimage.model_for_attestation")},
                {"prop:ro.product.vendor.model", prop("ro.product.vendor.model")},
                {"prop:ro.product.system.model", prop("ro.product.system.model")},
                {"prop:ro.product.bootimage.model", prop("ro.product.bootimage.model")},

                // Marketing/name properties and broad fallbacks.
                {"prop:persist.sys.device_name", prop("persist.sys.device_name")},
                {"prop:ro.product.name", prop("ro.product.name")},
                {"prop:ro.product.odm.name", prop("ro.product.odm.name")},
                {"prop:ro.product.product.name", prop("ro.product.product.name")},
                {"prop:ro.product.vendor.name", prop("ro.product.vendor.name")},
                {"prop:ro.product.system.name", prop("ro.product.system.name")},
                {"brand_model", join(brand, model)},
                {"manufacturer_model", join(manufacturer, model)},
                {"device", device},
                {"board", board},
                {"fingerprint", fingerprint}
        };
    }

    private static String compactCandidates(String[][] candidates) {
        StringBuilder b = new StringBuilder(512);
        if (candidates == null) return "";
        for (String[] c : candidates) {
            if (c == null || c.length < 2) continue;
            String field = c[0] == null ? "" : c[0];
            String value = c[1] == null ? "" : c[1].trim();
            if (value.isEmpty()) continue;
            if (b.length() > 0) b.append('|');
            b.append(field).append('=').append(value);
        }
        return b.toString();
    }

    private static boolean isHyperOs(String version, String fingerprint, String display) {
        String s = (version + " " + fingerprint + " " + display).toLowerCase(Locale.ROOT);
        return s.contains("hyperos") || s.contains("os1.") || s.contains("os2.") || s.contains("os3.");
    }

    private static boolean isColorOs(String version, String fingerprint, String display, String brand, String manufacturer) {
        String s = (version + " " + fingerprint + " " + display + " " + brand + " " + manufacturer).toLowerCase(Locale.ROOT);
        return s.contains("coloros") || s.contains("oplus") || s.contains("oneplus") || s.contains("oppo") || s.contains("realme");
    }

    private static String prop(String key) {
        try {
            String v = SystemProperties.get(key, "");
            return v == null ? "" : v.trim();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static String firstNonEmpty(String a, String b) {
        if (a != null && !a.isEmpty()) return a;
        return b == null ? "" : b;
    }

    private static String nz(String v) {
        return v == null ? "" : v;
    }

    private static String join(String[] values) {
        if (values == null || values.length == 0) return "";
        StringBuilder b = new StringBuilder();
        for (String v : values) {
            if (v == null || v.isEmpty()) continue;
            if (b.length() > 0) b.append(',');
            b.append(v);
        }
        return b.toString();
    }

    private static String join(String a, String b) {
        String left = a == null ? "" : a.trim();
        String right = b == null ? "" : b.trim();
        if (left.isEmpty()) return right;
        if (right.isEmpty()) return left;
        return left + " " + right;
    }

    private static StringBuilder add(StringBuilder b, String key, String value) {
        b.append('"').append(escape(key)).append("\":\"").append(escape(value)).append('"');
        return b;
    }

    private static StringBuilder add(StringBuilder b, String key, int value) {
        b.append('"').append(escape(key)).append("\":").append(value);
        return b;
    }

    private static StringBuilder add(StringBuilder b, String key, boolean value) {
        b.append('"').append(escape(key)).append("\":").append(value ? "true" : "false");
        return b;
    }

    private static String escape(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '\\': out.append("\\\\"); break;
                case '"': out.append("\\\""); break;
                case '\b': out.append("\\b"); break;
                case '\f': out.append("\\f"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        String hex = Integer.toHexString(c);
                        out.append("\\u");
                        for (int j = hex.length(); j < 4; j++) out.append('0');
                        out.append(hex);
                    } else {
                        out.append(c);
                    }
            }
        }
        return out.toString();
    }
}
