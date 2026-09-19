package com.xayah.dex;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/** Bounded memory; one write per chunk, no payload staging or per-chunk allocation. */
final class ChunkedBodyWriter {
    private static final byte[] HEX = "0123456789abcdef".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    private static final byte[] END = {'0', '\r', '\n', '\r', '\n'};

    static void write(InputStream input, OutputStream output, int capacity) throws IOException {
        if (capacity < 1 || capacity > 16 * 1024 * 1024) throw new IllegalArgumentException("invalid chunk capacity");
        final int offset = 12;
        byte[] block = new byte[capacity + offset + 2];
        for (;;) {
            int n = input.read(block, offset, capacity);
            if (n < 0) break;
            if (n == 0) {
                int one = input.read();
                if (one < 0) break;
                block[offset] = (byte) one;
                n = 1;
            }
            int start = offset;
            block[--start] = '\n';
            block[--start] = '\r';
            int value = n;
            do { block[--start] = HEX[value & 15]; value >>>= 4; } while (value != 0);
            block[offset + n] = '\r';
            block[offset + n + 1] = '\n';
            output.write(block, start, offset + n + 2 - start);
        }
        // Only emit the terminal chunk after a real EOF, never after an I/O failure.
        output.write(END);
    }
}
