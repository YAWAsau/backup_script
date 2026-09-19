package com.xayah.dex;

/** Typed control-plane completion. Diagnostics never determine the result. */
final class OperationResult {
    private final String operation;
    private final boolean ok;
    private int token = -1;
    private int requested = -1;
    private int completed = -1;
    private int recovered = -1;
    private int failed = -1;
    private int missing = -1;
    private int user = -1;
    private Boolean restored;
    private Boolean deleted;
    private String pkg = "-";

    OperationResult(String operation, boolean ok) {
        if (operation == null || !operation.matches("[a-z][a-z0-9-]*")) {
            throw new IllegalArgumentException("operation");
        }
        this.operation = operation;
        this.ok = ok;
    }
    OperationResult token(int value) {
        token = value;
        return this;
    }

    OperationResult counts(int requested, int completed, int recovered, int failed, int missing) {
        this.requested = requested;
        this.completed = completed;
        this.recovered = recovered;
        this.failed = failed;
        this.missing = missing;
        return this;
    }

    OperationResult restoration(boolean restored, boolean deleted) {
        this.restored = restored;
        this.deleted = deleted;
        return this;
    }

    OperationResult identity(int user, String pkg) {
        this.user = user;
        this.pkg = pkg == null || pkg.isEmpty() ? "-" : pkg;
        if (!this.pkg.matches("[a-zA-Z0-9_.-]+")) throw new IllegalArgumentException("package");
        return this;
    }
    private static String number(int value) {
        return value < 0 ? "-" : Integer.toString(value);
    }

    private static String bool(Boolean value) {
        return value == null ? "-" : value.toString();
    }

    String line() {
        return "SBRESULT\t1\t" + operation + "\t" + (ok ? "ok\t0" : "failed\t1")
                + "\t" + number(token) + "\t" + number(requested) + "\t" + number(completed)
                + "\t" + number(recovered) + "\t" + number(failed) + "\t" + number(missing)
                + "\t" + bool(restored) + "\t" + bool(deleted) + "\t" + number(user) + "\t" + pkg + "\n";
    }

    String appendTo(Object diagnostics) {
        String text = diagnostics == null ? "" : diagnostics.toString();
        return text + (text.isEmpty() || text.endsWith("\n") ? "" : "\n") + line();
    }

    static String[] read(String output, String operation) {
        if (output == null) return null;
        String[] result = null;
        for (String line : output.split("\n", -1)) {
            if (!line.startsWith("SBRESULT\t")) continue;
            String[] f = line.split("\t", -1);
            if (f.length < 3 || !f[2].equals(operation)) continue;
            if (result != null || f.length != 15 || !f[1].equals("1")) return null;
            if (!(f[3].equals("ok") && f[4].equals("0")) && !(f[3].equals("failed") && f[4].equals("1"))) return null;
            for (int i = 5; i <= 10; i++) if (!validNumber(f[i])) return null;
            if (!validNumber(f[13]) || !f[14].matches("[a-zA-Z0-9_.-]+")) return null;
            for (int i = 11; i <= 12; i++) if (!f[i].equals("-") && !f[i].equals("true") && !f[i].equals("false")) return null;
            result = f;
        }
        return result;
    }

    private static boolean validNumber(String value) {
        if (value.equals("-")) return true;
        if (!value.matches("0|[1-9][0-9]*")) return false;
        try {
            return Integer.parseInt(value) >= 0;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    static boolean isOk(String output, String operation) {
        String[] result = read(output, operation);
        return result != null && result[3].equals("ok");
    }
    static int exitCode(String output, String operation) {
        return isOk(output, operation) ? 0 : 1;
    }

    static int token(String output, String operation) {
        String[] result = read(output, operation);
        return result == null || result[5].equals("-") ? -1 : Integer.parseInt(result[5]);
    }
}
