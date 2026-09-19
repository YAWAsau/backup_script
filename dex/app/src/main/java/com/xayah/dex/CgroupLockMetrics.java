package com.xayah.dex;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Supplier;

/** Measure the existing monitor, including wait time; does not change lock ownership. */
final class CgroupLockMetrics {
    private static final Map<String, long[]> METRICS = new LinkedHashMap<>();

    static String measure(Object monitor, String operation, Supplier<String> action) {
        long before = System.nanoTime();
        synchronized (monitor) {
            long acquired = System.nanoTime();
            try {
                return action.get();
            } finally {
                record(operation, acquired - before, System.nanoTime() - acquired);
            }
        }
    }

    private static synchronized void record(String operation, long wait, long hold) {
        long[] row = METRICS.computeIfAbsent(operation, key -> new long[5]);
        row[0]++;
        row[1] += wait;
        row[2] += hold;
        row[3] = Math.max(row[3], wait);
        row[4] = Math.max(row[4], hold);
    }

    static synchronized String summary() {
        StringBuilder out = new StringBuilder();
        out.append("CGROUP_LOCK_METRICS scope=global-monitor unit=ns operations=").append(METRICS.size()).append('\n');
        for (Map.Entry<String, long[]> entry : METRICS.entrySet()) {
            long[] row = entry.getValue();
            out.append("CGROUP_LOCK_METRIC operation=").append(entry.getKey())
                    .append(" calls=").append(row[0]).append(" waitNs=").append(row[1])
                    .append(" holdNs=").append(row[2]).append(" maxWaitNs=").append(row[3])
                    .append(" maxHoldNs=").append(row[4]).append('\n');
        }
        return out.toString();
    }

    private CgroupLockMetrics() {}
}
