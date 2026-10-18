package com.xayah.dex;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/** Bounded fallback commands; never wait for EOF from an inherited child pipe. */
final class BoundedShell {
    static final class Result {
        final int code;
        final String output;
        Result(int code, String output) { this.code = code; this.output = output; }
    }

    static Result run(String command, long timeoutMillis) throws Exception {
        Process process = new ProcessBuilder("sh", "-c", "exec " + command).redirectErrorStream(true).start();
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        InputStream input = process.getInputStream();
        byte[] buffer = new byte[8192];
        try {
            for (;;) {
                if (System.nanoTime() >= deadline) return new Result(124, "");
                int available = input.available();
                if (available > 0) {
                    int n = input.read(buffer, 0, Math.min(buffer.length, available));
                    if (n > 0) {
                        if (output.size() + n > 8 * 1024 * 1024) return new Result(125, "");
                        output.write(buffer, 0, n);
                        continue;
                    }
                }
                if (!process.isAlive()) {
                    if (input.available() > 0) continue;
                    return new Result(process.exitValue(), new String(output.toByteArray(), StandardCharsets.UTF_8));
                }
                Thread.sleep(20);
            }
        } finally {
            if (process.isAlive()) process.destroyForcibly();
            input.close();
            process.getOutputStream().close();
            process.getErrorStream().close();
        }
    }
    private BoundedShell() {}
}
