package com.xayah.dex;

/** Pure mode rules; unknown scope/policy values never establish equivalence. */
final class AppOpModePolicy {
    private AppOpModePolicy() {}

    static Integer storedMode(Integer packageMode, Integer uidMode, Integer platformDefault) {
        if (uidMode == null || platformDefault == null) return null;
        int resolvedUid = uidMode == 3 ? platformDefault : uidMode;
        if (resolvedUid != platformDefault) return resolvedUid;
        if (packageMode == null) return null;
        return packageMode == 3 ? platformDefault : packageMode;
    }

    static boolean locationDisabledMatches(int expected, int effective, Integer stored,
                                            Boolean locationEnabled, boolean granted) {
        return granted && (expected == 0 || expected == 4) && effective == 1
                && stored != null && stored == expected && Boolean.FALSE.equals(locationEnabled);
    }

    static boolean scopedDefaultMatches(int expected, int actual, Integer expectedPackage,
                                         Integer actualPackage, Integer expectedUid,
                                         Integer actualUid, Integer platformDefault) {
        if (expected == actual || platformDefault == null || platformDefault == 3) return false;
        if (expectedPackage == null || actualPackage == null || expectedUid == null || actualUid == null) return false;
        if (!expectedPackage.equals(actualPackage) || !expectedUid.equals(actualUid)) return false;
        return (expected == 3 && actual == platformDefault)
                || (actual == 3 && expected == platformDefault);
    }
}
