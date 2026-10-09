package com.xayah.dex;

import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** Informational receipts only. Binary stdout and exception stderr are untouched. */
final class DiagnosticInfo {
    private DiagnosticInfo() {}
    static void write(String message) {
        String path = System.getenv("SPEEDBACKUP_INFO_LOG");
        if (path != null && !path.isEmpty()) {
            try (FileOutputStream out = new FileOutputStream(path, true)) {
                out.write((message + "\n").getBytes(StandardCharsets.UTF_8));
                return;
            } catch (Exception ignored) {
                // A broken diagnostic sink must not lose the receipt or fail the backup.
            }
        }
        System.err.println(message);
    }
}
