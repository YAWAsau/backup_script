package com.xayah.dex;

/**
 * Single source of truth for the compiled classes.dex artifact version.
 *
 * Component-specific capability strings remain in their own classes.  Public
 * --version output should use this value so a rebuilt classes.dex does not
 * look like mixed r512/r547 artifacts when only one class was edited.
 */
public final class DexBuildInfo {
    public static final String VERSION = "v2.6.278-backup-trace19 build=v24.20.14-7.67-1135-backup-trace19-202609210001";
    public static final String PATCH_BUILD = "v24.20.14-7.67-1135-backup-trace19-202609210001";
    public static final String BUILD_TAG = "202609210001";
    public static final String R_TAG = "r718-backup-trace19";

    private DexBuildInfo() {}
}
