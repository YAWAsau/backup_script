package com.xayah.dex;

/**
 * @see <a href="https://cs.android.com/android/platform/superproject/+/android-14.0.0_r61:frameworks/libs/modules-utils/java/com/android/modules/utils/BasicShellCommandHandler.java">BasicShellCommandHandler.java</a>
 */
abstract class BaseUtil {
    protected static String[] mArgs;
    protected static String mCmd;
    protected static int mArgPos;
    protected static String mCurArgData;

    /**
     * Return the next option on the command line -- that is an argument that
     * starts with '-'.  If the next argument is not an option, null is returned.
     */
    public static String getNextOption() {
        if (mCurArgData != null) {
            String prev = mArgs[mArgPos - 1];
            throw new IllegalArgumentException("No argument expected after \"" + prev + "\"");
        }
        if (mArgPos >= mArgs.length) {
            return null;
        }
        String arg = mArgs[mArgPos];
        if (!arg.startsWith("-")) {
            return null;
        }
        mArgPos++;
        if (arg.equals("--")) {
            return null;
        }
        if (arg.length() > 1 && arg.charAt(1) != '-') {
            if (arg.length() > 2) {
                mCurArgData = arg.substring(2);
                return arg.substring(0, 2);
            } else {
                mCurArgData = null;
                return arg;
            }
        }
        mCurArgData = null;
        return arg;
    }

}
