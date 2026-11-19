package com.xayah.dex;

import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** Informational receipts only. Binary stdout and exception stderr are untouched. */
final class DiagnosticInfo {
    private DiagnosticInfo() {}

    static void write(String message) {
        try {
            String path = System.getenv("SPEEDBACKUP_INFO_LOG");
            if (path == null || path.isEmpty()) {
                return;
            }

            try (FileOutputStream out = new FileOutputStream(path, true)) {
                out.write((message + "\n").getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception ignored) {
            // Optional diagnostic failures must not affect the backup or its streams.
        }
    }
}
