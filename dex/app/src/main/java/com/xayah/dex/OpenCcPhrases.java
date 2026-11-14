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
        static final Trie[] TRIES = load();
        private static Trie[] load() {
            ByteBuffer header = ByteBuffer.wrap(DATA);
            int count = header.getInt(4), offset = 8 + count * 4;
            Trie[] tries = new Trie[count];
            for (int i = 0; i < count; i++) {
                tries[i] = new Trie(DATA, offset);
                offset += header.getInt(8 + i * 4);
            }
            return tries;
        }
    }

    // Ordered groups short-circuit at the first matching dictionary. Union
    // groups are merged by the generator before building a longest-match trie.
    private static int append(String text, int start, StringBuilder out, int[] group) {
        for (int index : group) {
            int end = Holder.TRIES[index].append(text, start, out);
            if (end > start) return end;
        }
        return start;
    }

    private static String convertGroup(String text, int[] group) {
        StringBuilder out = new StringBuilder(text.length());
        for (int start = 0; start < text.length();) {
            int end = append(text, start, out, group);
            if (end == start) {
                int cp = text.codePointAt(start);
                out.appendCodePoint(cp);
                end += Character.charCount(cp);
            }
            start = end;
        }
        return out.toString();
    }

    private static void convertSegment(String text, int start, int end, int[][] chain, StringBuilder out) {
        String segment = text.substring(start, end);
        for (int[] group : chain) segment = convertGroup(segment, group);
        out.append(segment);
    }

    static String convert(String text, boolean toTraditional) {
        int[][] normalization = toTraditional ? OpenCcPhraseData.S2TWP_NORMALIZE : OpenCcPhraseData.TW2SP_NORMALIZE;
        int[] segmentation = toTraditional ? OpenCcPhraseData.S2TWP_SEGMENT : OpenCcPhraseData.TW2SP_SEGMENT;
        int[][] chain = toTraditional ? OpenCcPhraseData.S2TWP_CHAIN : OpenCcPhraseData.TW2SP_CHAIN;
        for (int[] group : normalization) text = convertGroup(text, group);
        StringBuilder out = new StringBuilder(text.length()), ignored = new StringBuilder();
        int pending = 0;
        for (int i = 0; i < text.length();) {
            ignored.setLength(0);
            int end = append(text, i, ignored, segmentation);
            if (end > i) {
                if (pending < i) convertSegment(text, pending, i, chain, out);
                convertSegment(text, i, end, chain, out);
                pending = end;
                i = end;
            } else {
                i += Character.charCount(text.codePointAt(i));
            }
        }
        if (pending < text.length()) convertSegment(text, pending, text.length(), chain, out);
        return out.toString();
    }

    private static byte[] unpack() {
        StringBuilder encoded = new StringBuilder();
        for (String chunk : OpenCcPhraseData.CHUNKS) encoded.append(chunk);
        byte[] compressed = Base64.getDecoder().decode(encoded.toString());
        try (InflaterInputStream input = new InflaterInputStream(new ByteArrayInputStream(compressed));
             ByteArrayOutputStream output = new ByteArrayOutputStream(OpenCcPhraseData.UNCOMPRESSED_BYTES)) {
            byte[] buffer = new byte[65536];
            int bytesRead;
            while ((bytesRead = input.read(buffer)) != -1) {
                if (output.size() + bytesRead > OpenCcPhraseData.UNCOMPRESSED_BYTES) throw new IOException("Oversized phrase data");
                output.write(buffer, 0, bytesRead);
            }
            byte[] data = output.toByteArray();
            ByteBuffer header = ByteBuffer.wrap(data);
            if (data.length < 8 || data.length != OpenCcPhraseData.UNCOMPRESSED_BYTES
                    || header.getInt(0) != 0x53424332) throw new IOException("Invalid phrase data");
            int count = header.getInt(4);
            long total = 8L + count * 4L;
            if (count <= 0 || total > data.length) throw new IOException("Invalid dictionary count");
            for (int i = 0; i < count; i++) {
                int size = header.getInt(8 + i * 4);
                if (size < 24) throw new IOException("Invalid dictionary size");
                total += size;
            }
            if (total != data.length) throw new IOException("Invalid dictionary bounds");
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
