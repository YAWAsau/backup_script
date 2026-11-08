package com.xayah.dex;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.zip.InflaterInputStream;

/** Immutable longest-match phrase lookup, shared by all converters in one process. */
final class OpenCcPhrases {
    private static final class Holder {
        static final byte[] DATA = unpack();
        static final Trie S2T = new Trie(DATA, 12);
        static final Trie T2S = new Trie(DATA, 12 + ByteBuffer.wrap(DATA).getInt(4));
    }

    static int append(String text, int start, StringBuilder out, boolean simplifiedToTraditional) {
        return (simplifiedToTraditional ? Holder.S2T : Holder.T2S).append(text, start, out);
    }

    private static byte[] unpack() {
        StringBuilder encoded = new StringBuilder();
        for (String chunk : OpenCcPhraseData.CHUNKS) encoded.append(chunk);
        byte[] compressed = Base64.getDecoder().decode(encoded.toString());
        try (InflaterInputStream input = new InflaterInputStream(new ByteArrayInputStream(compressed));
             ByteArrayOutputStream output = new ByteArrayOutputStream(OpenCcPhraseData.UNCOMPRESSED_BYTES)) {
            byte[] buffer = new byte[65536];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > OpenCcPhraseData.UNCOMPRESSED_BYTES) throw new IOException("Oversized phrase data");
                output.write(buffer, 0, count);
            }
            byte[] data = output.toByteArray();
            ByteBuffer header = ByteBuffer.wrap(data);
            if (data.length != OpenCcPhraseData.UNCOMPRESSED_BYTES || header.getInt(0) != 0x53424350
                    || 12L + header.getInt(4) + header.getInt(8) != data.length) throw new IOException("Invalid phrase data");
            return data;
        } catch (IOException failure) {
            throw new IllegalStateException("Unable to load embedded OpenCC phrases", failure);
        }
    }

    private static final class Trie {
        final byte[] data;
        final ByteBuffer buffer;
        final int nodes, edges, strings;
        final int[] first = new int[65536];

        Trie(byte[] data, int offset) {
            this.data = data;
            this.buffer = ByteBuffer.wrap(data);
            nodes = offset + 12;
            edges = nodes + buffer.getInt(offset) * 12;
            strings = edges + buffer.getInt(offset + 4) * 8;
            int rootEdge = buffer.getInt(nodes), count = buffer.getShort(nodes + 4) & 0xffff;
            for (int i = 0; i < count; i++) {
                int edge = edges + (rootEdge + i) * 8;
                first[buffer.getInt(edge)] = buffer.getInt(edge + 4);
            }
        }

        int next(int node, char unit) {
            int record = nodes + node * 12;
            int low = buffer.getInt(record), high = low + (buffer.getShort(record + 4) & 0xffff) - 1;
            while (low <= high) {
                int middle = (low + high) >>> 1, edge = edges + middle * 8;
                int key = buffer.getInt(edge);
                if (key == unit) return buffer.getInt(edge + 4);
                if (key < unit) low = middle + 1; else high = middle - 1;
            }
            return 0;
        }

        int append(String text, int start, StringBuilder out) {
            int node = first[text.charAt(start)];
            if (node == 0) return start;
            int best = 0, end = start;
            for (int i = start; node != 0; ) {
                i++;
                if ((buffer.getShort(nodes + node * 12 + 6) & 0xffff) != 0) { best = node; end = i; }
                if (i == text.length()) break;
                node = next(node, text.charAt(i));
            }
            if (best != 0) {
                int record = nodes + best * 12;
                out.append(new String(data, strings + buffer.getInt(record + 8), buffer.getShort(record + 6) & 0xffff, StandardCharsets.UTF_8));
            }
            return end;
        }
    }
}
