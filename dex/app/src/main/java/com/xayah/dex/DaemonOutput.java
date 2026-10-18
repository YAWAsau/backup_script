package com.xayah.dex;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.io.UnsupportedEncodingException;

/** Request-local output; never mutate System.out, which is process-global. */
final class DaemonOutput {
    private static final ThreadLocal<PrintStream> CAPTURE = new ThreadLocal<>();

    static PrintStream current() {
        PrintStream out = CAPTURE.get();
        return out == null ? System.out : out;
    }

    static PrintStream begin(ByteArrayOutputStream bytes) throws UnsupportedEncodingException {
        PrintStream previous = CAPTURE.get();
        CAPTURE.set(new PrintStream(bytes, true, "UTF-8"));
        return previous;
    }

    static void end(PrintStream previous) {
        PrintStream out = CAPTURE.get();
        if (out != null) out.flush();
        if (previous == null) CAPTURE.remove(); else CAPTURE.set(previous);
    }

    private DaemonOutput() {}
}
