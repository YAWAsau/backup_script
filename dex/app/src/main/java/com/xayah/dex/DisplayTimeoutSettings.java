package com.xayah.dex;

import android.content.ContentResolver;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.locks.ReentrantLock;

/** Root-daemon-only, narrow screen timeout API. Never executes a shell command. */
final class DisplayTimeoutSettings {
    private static final String KEY = "screen_off_timeout";
    private static final Uri URI = Uri.parse("content://settings");
    // This gate is independent of HiddenApiUtil's serial dispatcher. A slow Binder
    // request blocks only timeout operations, not inventory, notifications or ping.
    private static final ReentrantLock GATE = new ReentrantLock();
    private static ContentResolver resolver;
    private static int resolverUser = -1;

    static final class Result {
        final int rc;
        final String name, body;
        Result(int rc, String name, String body) { this.rc=rc; this.name=name; this.body=body; }
    }

    static boolean accepts(String command) {
        return "displayTimeoutGet".equals(command) || "displayTimeoutPut".equals(command)
                || "displayTimeoutUser".equals(command);
    }

    static Result run(String command, byte[] body) {
        if (android.os.Process.myUid() != 0) return new Result(2, "ROOT_REQUIRED", "");
        boolean put = "displayTimeoutPut".equals(command);
        String[] args = new String(body, StandardCharsets.UTF_8).split("\n", -1);
        int timeout, target = 0;
        try {
            if (!accepts(command) || body.length > 128 || args.length != (put ? 4 : 3)
                    || !args[args.length-1].isEmpty()) throw new IllegalArgumentException();
            timeout = decimal(args[1]);
            if (timeout < 1 || timeout > 5000) throw new IllegalArgumentException();
            if (!"current".equals(args[0])) decimal(args[0]);
            if (put) target = decimal(args[2]);
        } catch (RuntimeException e) { return new Result(2, "BAD_REQUEST", ""); }
        if (!GATE.tryLock()) return new Result(75, "BUSY", "");
        boolean attempted = false;
        long deadline = SystemClock.elapsedRealtime() + timeout;
        try {
            if (!HiddenApiBypassBridge.installExemptionsOnce())
                return new Result(69, "UNAVAILABLE", "");
            int user = "current".equals(args[0])
                    ? ((Number) Class.forName("android.app.ActivityManager").getMethod("getCurrentUser").invoke(null)).intValue()
                    : decimal(args[0]);
            if (user < 0) return new Result(69, "UNAVAILABLE", "");
            if ("displayTimeoutUser".equals(command)) return new Result(0, "OK", user + "\n");
            if (resolver == null || resolverUser != user) {
                resolver = new FakeContext(HiddenApiHelper.getContext(), true, user, false).getContentResolver();
                resolverUser = user;
            }
            // The shared SettingsProvider owns all users; specify the target user
            // in every call rather than requiring its process UID to match that user.
            Bundle extras = new Bundle();
            extras.putInt("_user", user);
            if (SystemClock.elapsedRealtime() >= deadline) return new Result(69, "NOT_STARTED", "");
            if (put) {
                extras.putString("value", Integer.toString(target));
                attempted = true;
                resolver.call(URI, "PUT_system", KEY, extras);
                extras.remove("value");
            }
            Bundle result = resolver.call(URI, "GET_system", KEY, extras);
            String value = result == null ? null : result.getString("value");
            decimal(value);
            if (put && !Integer.toString(target).equals(value))
                return new Result(74, "UNKNOWN", "");
            return new Result(0, "OK", value + "\n");
        } catch (Exception e) {
            resolver = null; resolverUser = -1;
            // Once PUT entered Binder, an exception is not proof that it did not
            // commit. Never invite an automatic retry/fallback of this mutation.
            return new Result(attempted ? 74 : 69, attempted ? "UNKNOWN" : "UNAVAILABLE", "");
        } finally { GATE.unlock(); }
    }

    private static int decimal(String value) {
        if (value == null || !value.matches("0|[1-9][0-9]{0,9}")) throw new IllegalArgumentException();
        return Integer.parseInt(value);
    }
}
