package com.xayah.dex;

import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/** r704: pure result reducer; never invokes Android services or parses diagnostic messages. */
final class BatchResultFiles {
    final String kind;
    int total, ok, vendor, warn, failed;
    int restored, same, ssaidFailed, checked;
    final StringBuilder issues = new StringBuilder();
    final StringBuilder ssaid = new StringBuilder();

    BatchResultFiles(boolean verify) { kind = verify ? "verify" : "restore"; }

    static String text(JsonObject o, String key) {
        JsonElement e = o == null ? null : o.get(key);
        return e == null || e.isJsonNull() ? "" : e.getAsString();
    }
    static String field(String s) {
        // Escaping is for diagnostics only; package and SSAID keys are validated upstream.
        return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n");
    }
    void accept(JsonObject row) {
        total++;
        JsonObject result = row.getAsJsonObject("result");
        String name = text(result, "name");
        String pkg = text(row, "packageName");
        boolean verify = kind.equals("verify");
        if (name.equals("OK")) ok++;
        else if (verify && name.equals("VERIFY_VENDOR_CONSTRAINED")) vendor++;
        else if (name.equals("VERIFY_MISMATCH") || (!verify && name.equals("PARTIAL"))) warn++;
        else failed++;
        if (!name.equals("OK")) {
            issues.append(verify && name.equals("VERIFY_VENDOR_CONSTRAINED") ? "VERIFY_VENDOR" : kind.toUpperCase(java.util.Locale.ROOT))
                    .append('\t').append(field(pkg)).append('\t').append(field(name)).append('\t')
                    .append(field(text(result, "message"))).append('\n');
        }
        if (!verify && row.has("items")) {
            for (JsonElement e : row.getAsJsonArray("items")) {
                JsonObject item = e.getAsJsonObject();
                if (!text(item, "category").equals("ssaid")) continue;
                String action = text(item, "action");
                if (!text(item.getAsJsonObject("result"), "name").equals("OK")) action = "failed";
                switch (action) {
                    case "restored": restored++; break;
                    case "same": same++; break;
                    case "checked": checked++; break;
                    default: action = "failed"; ssaidFailed++; break;
                }
                // '-' keeps empty columns intact in POSIX shell read.
                ssaid.append(action).append('\t').append(field(pkg)).append('\t')
                        .append(valueOrDash(item, "expected")).append('\t').append(valueOrDash(item, "actual"))
                        .append('\t').append(field(text(item.getAsJsonObject("result"), "message"))).append('\n');
            }
        } else if (verify && row.has("ssaidVerification")) {
            JsonObject v = row.getAsJsonObject("ssaidVerification");
            if (text(v, "status").equals("ok")) same++; else ssaidFailed++;
        }
    }
    private static String valueOrDash(JsonObject o, String key) {
        String value = text(o, key);
        return value.isEmpty() ? "-" : field(value);
    }
    String summary(int code) {
        String status = failed > 0 ? "failed" : (warn > 0 || vendor > 0 ? "partial" : "ok");
        return "SBRESULT\t1\tappstate-" + kind + "\t" + status + "\t" + code + "\t"
                + total + "\t" + ok + "\t" + vendor + "\t" + warn + "\t" + failed + "\t"
                + restored + "\t" + same + "\t" + ssaidFailed + "\t" + checked + "\n";
    }
    void publish(String prefix, int code) throws IOException {
        if (prefix == null || prefix.isEmpty()) return; // CLI without sidecars remains supported.
        File base = new File(prefix);
        if (!base.isAbsolute() || base.getParentFile() == null || !base.getParentFile().isDirectory()) {
            throw new IOException("result prefix must have an existing absolute parent");
        }
        Files.write(new File(prefix + ".issues").toPath(), issues.toString().getBytes(StandardCharsets.UTF_8));
        Files.write(new File(prefix + ".ssaid").toPath(), ssaid.toString().getBytes(StandardCharsets.UTF_8));
        // The summary is the completion marker and is published only after both sidecars.
        File temp = new File(prefix + ".summary.tmp");
        Files.write(temp.toPath(), summary(code).getBytes(StandardCharsets.UTF_8));
        Files.move(temp.toPath(), new File(prefix + ".summary").toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }
}
