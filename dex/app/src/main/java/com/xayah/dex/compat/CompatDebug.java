package com.xayah.dex.compat;

import java.util.Locale;

/**
 * Shared debug switch for hidden-api compatibility wrappers.
 * Controlled by HIDDENAPI_DEBUG=1/true/yes; stdout remains machine-readable.
 */
final class CompatDebug {
    static final boolean DEBUG = parseDebugFlag();

    private CompatDebug() {
    }

    private static boolean parseDebugFlag() {
        try {
            String value = System.getenv("HIDDENAPI_DEBUG");
            if (value == null) {
                return false;
            }
            value = value.trim().toLowerCase(Locale.ROOT);
            return value.equals("1") || value.equals("true") || value.equals("yes") || value.equals("on");
        } catch (Throwable ignored) {
            return false;
        }
    }

    static void throwable(String context, Throwable throwable) {
        if (!DEBUG || throwable == null) {
            return;
        }
        System.err.println("[HiddenApiCompat][DEBUG] " + context + ": "
                + throwable.getClass().getName()
                + (throwable.getMessage() != null ? ": " + throwable.getMessage() : ""));
    }

}
