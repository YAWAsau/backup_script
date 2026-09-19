package com.xayah.dex;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Run-local reducer. Every attempt replaces its requested packages, including transport failures. */
final class RunResultFiles {
    static List<String> lines(String path) throws IOException {
        return Files.readAllLines(Paths.get(path), StandardCharsets.UTF_8);
    }

    static Set<String> packages(String path) throws IOException {
        Set<String> result = new LinkedHashSet<>();
        for (String line : lines(path)) {
            if (line.trim().isEmpty()) continue;
            String pkg = BatchResultFiles.text(JsonParser.parseString(line).getAsJsonObject(), "packageName");
            if (!pkg.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)*")) throw new IOException("invalid package identity");
            result.add(pkg);
        }
        return result;
    }

    static JsonObject failure(String kind, String pkg, String reason) {
        JsonObject row = new JsonObject(), result = new JsonObject();
        row.addProperty("recordType", kind);
        row.addProperty("packageName", pkg);
        result.addProperty("name", "INTERNAL_ERROR");
        result.addProperty("message", reason);
        row.add("result", result);
        return row;
    }

    static String reduce(String body, String prefix) throws IOException {
        String[] requests = body.split("\n");
        if (requests.length < 1 || prefix == null || prefix.isEmpty()) throw new IOException("missing run manifest");
        Set<String> expected = packages(requests[0]);
        if (expected.isEmpty()) throw new IOException("empty run");
        Map<String, JsonObject> restore = new LinkedHashMap<>(), verify = new LinkedHashMap<>();
        Map<String, JsonObject> ssaidHistory = new LinkedHashMap<>();
        for (String pkg : expected) {
            restore.put(pkg, failure("restore", pkg, "not_attempted"));
            verify.put(pkg, failure("verify", pkg, "not_attempted"));
        }
        for (int i = 1; i < requests.length; i++) {
            if (requests[i].isEmpty()) continue;
            String[] f = requests[i].split("\t", -1);
            if (f.length != 4 || !(f[0].equals("restore") || f[0].equals("verify")) || !f[3].matches("[0-9]+")) {
                throw new IOException("invalid attempt manifest");
            }
            Set<String> requested = packages(f[1]);
            if (!expected.containsAll(requested)) throw new IOException("attempt package outside run");
            Map<String, JsonObject> target = f[0].equals("restore") ? restore : verify;
            for (String pkg : requested) target.put(pkg, failure(f[0], pkg, "transport_or_protocol_failure"));
            Map<String, JsonObject> attempt = new LinkedHashMap<>();
            try {
                String marker = new String(Files.readAllBytes(Paths.get(f[2] + ".summary")), StandardCharsets.UTF_8).trim();
                String[] m = marker.split("\t", -1);
                if (m.length != 14 || !m[0].equals("SBRESULT") || !m[1].equals("1")
                        || !m[2].equals("appstate-" + f[0]) || Integer.parseInt(m[5]) != requested.size()) continue;
                boolean summary = false;
                for (String line : lines(f[2])) {
                    if (line.trim().isEmpty()) continue;
                    JsonObject row = JsonParser.parseString(line).getAsJsonObject();
                    String type = BatchResultFiles.text(row, "recordType");
                    if (type.equals("summary")) {
                        String command = f[0].equals("restore") ? "restoreAppStateBatch" : "verifyAppStateBatch";
                        if (summary || !BatchResultFiles.text(row, "command").equals(command)
                                || !BatchResultFiles.text(row, "schemaVersion").equals("2")
                                || row.get("total").getAsInt() != requested.size()) throw new IOException("invalid batch completion");
                        summary = true; continue;
                    }
                    if (summary) throw new IOException("records after completion");
                    String pkg = BatchResultFiles.text(row, "packageName");
                    if (!type.equals(f[0]) || !requested.contains(pkg) || !row.has("result")
                            || attempt.put(pkg, row) != null) throw new IOException("conflicting attempt result");
                }
                if (!summary || !attempt.keySet().equals(requested)) continue;
                // Recompute the marker from the typed records, never from diagnostic prose.
                BatchResultFiles check = new BatchResultFiles(f[0].equals("verify"));
                for (JsonObject row : attempt.values()) check.accept(row);
                if (!check.summary(Integer.parseInt(m[4])).trim().equals(marker)) continue;
                if (f[0].equals("restore")) {
                    for (Map.Entry<String, JsonObject> entry : attempt.entrySet()) {
                        JsonArray items = entry.getValue().getAsJsonArray("items");
                        if (items == null) continue;
                        for (JsonElement itemValue : items) {
                            JsonObject item = itemValue.getAsJsonObject();
                            if (!BatchResultFiles.text(item, "category").equals("ssaid")) continue;
                            JsonObject prior = ssaidHistory.get(entry.getKey());
                            if (prior != null && BatchResultFiles.text(prior, "action").equals("restored")
                                    && BatchResultFiles.text(item, "action").equals("same")
                                    && BatchResultFiles.text(prior, "actual").equals(BatchResultFiles.text(item, "actual"))) {
                                item.addProperty("action", "restored");
                            }
                            ssaidHistory.put(entry.getKey(), item.deepCopy());
                        }
                    }
                }
                target.putAll(attempt);
            } catch (IOException | RuntimeException invalid) {
                // A failed attempt supersedes prior success; a later retry can replace it.
            }
        }
        // Preserve a completed SSAID write even when a later transport attempt fails.
        for (Map.Entry<String, JsonObject> entry : ssaidHistory.entrySet()) {
            JsonObject row = restore.get(entry.getKey());
            if (!row.has("items")) {
                JsonArray items = new JsonArray(); items.add(entry.getValue()); row.add("items", items);
            }
        }
        BatchResultFiles r = publish(prefix + ".restore", restore, false);
        BatchResultFiles v = publish(prefix + ".verify", verify, true);
        String state = r.failed + v.failed > 0 ? "failed" : r.warn + v.warn + v.vendor > 0 ? "partial" : "ok";
        return "SBRESULT\t1\tappstate-run\t" + state + "\t" + expected.size() + "\n";
    }

    private static BatchResultFiles publish(String prefix, Map<String, JsonObject> rows, boolean verify) throws IOException {
        BatchResultFiles result = new BatchResultFiles(verify);
        StringBuilder data = new StringBuilder();
        for (JsonObject row : rows.values()) { result.accept(row); data.append(row).append('\n'); }
        Path path = Paths.get(prefix);
        Files.deleteIfExists(Paths.get(prefix + ".summary"));
        Files.write(path, data.toString().getBytes(StandardCharsets.UTF_8));
        int code = result.failed > 0 || (!verify && result.warn > 0) ? 1
                : result.warn > 0 ? 60 : result.vendor > 0 ? 61 : 0;
        result.publish(prefix, code);
        return result;
    }
}
