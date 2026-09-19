package com.xayah.dex;

/** Display facts are separate from the legacy name used as a backup directory key. */
final class AppLabelResolver {
    interface Source {
        CharSequence primary() throws Exception;
        CharSequence nonLocalized() throws Exception;
        CharSequence resource() throws Exception;
    }

    static final class Result {
        final String displayLabel;
        final String legacyLabel;
        final String source;
        Result(String displayLabel, String legacyLabel, String source) {
            this.displayLabel = displayLabel;
            this.legacyLabel = legacyLabel;
            this.source = source;
        }
    }

    static Result resolve(Source source, String packageName) {
        String primary = null;
        try {
            CharSequence value = source.primary();
            if (value != null) primary = value.toString();
        } catch (Throwable ignored) {}
        String legacy = primary == null ? packageName : primary;
        if (usable(primary, packageName)) return new Result(primary, legacy, "loadLabel");
        try {
            CharSequence value = source.nonLocalized();
            if (value != null && usable(value.toString(), packageName)) {
                return new Result(value.toString(), legacy, "nonLocalizedLabel");
            }
        } catch (Throwable ignored) {}
        try {
            CharSequence value = source.resource();
            if (value != null && usable(value.toString(), packageName)) {
                return new Result(value.toString(), legacy, "labelRes");
            }
        } catch (Throwable ignored) {}
        return new Result(packageName, legacy, "packageName");
    }

    private static boolean usable(String value, String packageName) {
        return value != null && !value.trim().isEmpty() && !value.equals(packageName);
    }

    private AppLabelResolver() {}
}
