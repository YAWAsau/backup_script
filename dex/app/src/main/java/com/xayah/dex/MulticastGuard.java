package com.xayah.dex;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.os.Looper;

/** Platform-only lease. Rust owns discovery and closes stdin when it ends. */
public final class MulticastGuard {
    public static void main(String[] args) {
        // Binder death releases the lease even if the parent or this process dies.
        // A hard bound also covers an accidentally inherited stdin descriptor.
        Thread timeout = new Thread(() -> {
            try { Thread.sleep(25000); } catch (InterruptedException ignored) { }
            System.exit(2);
        }, "multicast-lease-timeout");
        timeout.setDaemon(true);
        timeout.start();
        WifiManager.MulticastLock lock = null;
        int status = 1;
        try {
            Looper.prepareMainLooper();
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Object thread = activityThread.getMethod("systemMain").invoke(null);
            Context context = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
            WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifi == null) throw new IllegalStateException("Wi-Fi service unavailable");
            lock = wifi.createMulticastLock("SpeedBackup-discovery-" + android.os.Process.myPid());
            lock.setReferenceCounted(false);
            lock.acquire();
            System.out.write('1');
            System.out.flush();
            System.in.read();
            status = 0;
        } catch (Exception e) {
            System.err.println("Multicast lease unavailable: " + e.getClass().getSimpleName());
        } finally {
            if (lock != null && lock.isHeld()) {
                try { lock.release(); } catch (Exception ignored) { }
            }
        }
        System.exit(status);
    }
}
