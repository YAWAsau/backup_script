package com.xayah.dex;

import android.system.Os;
import android.system.OsConstants;
import java.io.File;
import java.io.FileDescriptor;
import java.nio.charset.StandardCharsets;

/** Optional bounded diagnostics, separate from stderr and command replies. */
public final class DiagnosticLog {
    private static boolean reportedFailure;
    private DiagnosticLog() {}
    public static synchronized void write(String name, String message) {
        String dir = System.getenv("SPEED_DEBUG_RUN_DIR");
        if (dir == null || dir.isEmpty() || !name.matches("[a-z_]+\\.log")) return;
        File parent = new File(dir);
        // Never recreate a run directory after archive finalization or when disabled.
        if (!parent.isDirectory()) return;
        FileDescriptor fd = null;
        try {
            fd = Os.open(new File(parent, name).getPath(), OsConstants.O_WRONLY
                    | OsConstants.O_CREAT | OsConstants.O_APPEND | OsConstants.O_CLOEXEC
                    | OsConstants.O_NOFOLLOW | OsConstants.O_NONBLOCK, 0600);
            android.system.StructStat st = Os.fstat(fd);
            if (!OsConstants.S_ISREG(st.st_mode)) throw new java.io.IOException("not regular");
            if (st.st_size >= 1048576) return;
            byte[] bytes = ("[DEBUG] " + message + "\n").getBytes(StandardCharsets.UTF_8);
            int offset = 0;
            while (offset < bytes.length) {
                int count = Os.write(fd, bytes, offset, bytes.length - offset);
                if (count <= 0) throw new java.io.IOException("short diagnostic write");
                offset += count;
            }
        } catch (Exception error) {
            if (!reportedFailure) {
                reportedFailure = true;
                System.err.println("[WARN] DIAGNOSTIC_WRITE_FAILED file=" + name
                        + " type=" + error.getClass().getSimpleName());
            }
        } finally {
            if (fd != null) try { Os.close(fd); } catch (Exception ignored) {}
        }
    }
}
