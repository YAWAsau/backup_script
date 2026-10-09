package com.xayah.dex;

/** One daemon request for the ordered local-read guard release. */
final class BackupGuardRelease {
    static String release(String[] args) {
        StringBuilder out = new StringBuilder();
        try {
            if (args.length != 9 && args.length != 12) throw new IllegalArgumentException("arguments");
            int user = Integer.parseInt(args[1]);
            String pkg = args[2];
            int observer = Integer.parseInt(args[3]), cgroup = Integer.parseInt(args[4]);
            int net = Integer.parseInt(args[5]), timeout = Integer.parseInt(args[6]);
            int corrective = Integer.parseInt(args[7]);
            String paused = args[8];
            int wchan = args.length == 12 ? Integer.parseInt(args[9]) : 1;
            int thawTimeout = args.length == 12 ? Integer.parseInt(args[10]) : 700;
            int verify = args.length == 12 ? Integer.parseInt(args[11]) : 0;
            if (user < 0 || !pkg.matches("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+")
                    || observer < 0 || cgroup < 0 || net < 0 || timeout < 0
                    || timeout > 60000 || corrective < 0 || corrective > 2
                    || thawTimeout < 0 || thawTimeout > 60000 || (wchan != 0 && wchan != 1) || (verify != 0 && verify != 1)
                    || !(paused.equals("-") || paused.matches("[1-9][0-9]*(,[1-9][0-9]*)*"))) throw new IllegalArgumentException("scope");
            if (!paused.equals("-")) for (String pid : paused.split(",")) Integer.parseInt(pid);
            long start = System.nanoTime(), last = start;
            if (cgroup != 0) {
                try { out.append(CgroupFreezeUtil.refreshPrimaryAppScopePackageFreeze(user, pkg, "local_read_complete", timeout)); }
                catch (Throwable e) { out.append("GUARD_REFRESH_UNAVAILABLE\n"); }
            }
            last = timing(out, "refresh", last);
            // Pre-stop mismatch is observational: never refreeze an externally thawed app here.
            if (cgroup != 0 && wchan != 0) out.append(ProcessObserverUtil.wchanStatus(user, pkg, "frozen"));
            last = timing(out, "preConfirm", last);
            boolean observerOk = true, cgroupOk = true, netOk = true;
            if (observer != 0) {
                try {
                    String r = ProcessObserverUtil.stopAsync(observer, user, pkg); out.append(r);
                    observerOk = observerRestored(r);
                } catch (Throwable e) { observerOk = false; out.append("GUARD_OBSERVER_EXCEPTION\n"); }
            }
            last = timing(out, "observer", last);
            if (verify != 0) {
                try { out.append(ProcessObserverUtil.topStatus(user));out.append(ProcessObserverUtil.foregroundStatus(user,new String[]{pkg},0)); }
                catch(Throwable e){out.append("GUARD_STATUS_UNAVAILABLE\n");}
            }
            if (cgroup != 0) {
                try {
                    String r = CgroupFreezeUtil.stop(cgroup, user, pkg); out.append(r);
                    cgroupOk = restored(r, "cgroup-stop", cgroup);
                    String w = wchan == 0 ? "" : ProcessObserverUtil.wchanStatus(user, pkg, "thawed"); out.append(w);
                    for (int i = 0; i < corrective && wchanMismatch(w); i++) {
                        out.append(CgroupFreezeUtil.correctiveThawPackage(user, pkg, thawTimeout));
                        w = ProcessObserverUtil.wchanStatus(user, pkg, "thawed"); out.append(w);
                    }
                    if (!cgroupOk) {
                        r = CgroupFreezeUtil.restorePersistedPackage(user, pkg, "local-read-release"); out.append(r);
                        cgroupOk = restored(r, "cgroup-restore-package", -1);
                    }
                    if (w.contains("PROCESS_OBSERVER_WCHAN_ERROR")) cgroupOk = false;
                } catch (Throwable e) { cgroupOk = false; out.append("GUARD_CGROUP_EXCEPTION\n"); }
            }
            last = timing(out, "cgroup", last);
            if (net != 0) {
                try {
                    String r = UidNetworkBlockUtil.stop(net, user, pkg); out.append(r);
                    netOk = restored(r, "uidnet-stop", net);
                    if (!netOk) {
                        r = UidNetworkBlockUtil.restorePersistedPackage(user, pkg, "local-read-release"); out.append(r);
                        netOk = restored(r, "uidnet-stop", -1);
                    }
                } catch (Throwable e) { netOk = false; out.append("GUARD_NET_EXCEPTION\n"); }
            }
            last = timing(out, "net", last);
            boolean resumeOk;
            try { resumeOk = ProcessObserverUtil.resumePausedPids(user, pkg, paused); }
            catch (Throwable e) { resumeOk = false; }
            timing(out, "resume", last);
            out.append("GUARD_RELEASE_RECEIPT user=").append(user).append(" package=").append(pkg)
                    .append(" observer=").append(observer).append(" cgroup=").append(cgroup).append(" net=").append(net)
                    .append(" observerOk=").append(observerOk).append(" cgroupOk=").append(cgroupOk).append(" netOk=").append(netOk)
                    .append(" resumeOk=").append(resumeOk)
                    .append(" totalMs=").append((System.nanoTime()-start)/1000000).append('\n');
            boolean ok = observerOk && cgroupOk && netOk && resumeOk;
            return new OperationResult("backup-guard-release", ok).identity(user, pkg).restoration(ok, ok).appendTo(out);
        } catch (Throwable e) {
            return new OperationResult("backup-guard-release", false).appendTo(out.append("GUARD_RELEASE_REJECTED\n"));
        }
    }
    static boolean restored(String raw, String operation, int token) {
        String[] f = OperationResult.read(raw, operation);
        return f != null && "ok".equals(f[3]) && (token < 0 || Integer.toString(token).equals(f[5]))
                && "true".equals(f[11]) && "true".equals(f[12]);
    }
    static boolean observerRestored(String r) {
        if (r.contains("_FAILED") || r.contains("_REJECTED") || r.contains("stateRetained=true") || r.contains("stateDeleted=false")) return false;
        return r.contains("PROCESS_OBSERVER_DONE ") || r.contains("PROCESS_OBSERVER_STOP_MISSING") || r.contains("APP_WAKE_BLOCK_STOP_MISSING")
                || r.contains("APP_WAKE_BLOCK_PERSISTENT_RESTORE_MISSING")
                || ((r.contains("APP_WAKE_BLOCK_STOP_OK") || r.contains("APP_WAKE_BLOCK_PERSISTENT_RESTORE_DONE")
                     || r.contains("PROCESS_OBSERVER_STOP")) && r.contains("stateDeleted=true"));
    }
    private static boolean wchanMismatch(String raw) {
        for (String line : raw.split("\n")) if (line.startsWith("CGFREEZER_WCHAN_DONE ") && line.contains("ok=false")) return true;
        return false;
    }
    private static long timing(StringBuilder out, String stage, long previous) {
        long now = System.nanoTime();
        out.append("GUARD_RELEASE_STAGE stage=").append(stage).append(" elapsedMs=").append((now-previous)/1000000).append('\n');
        return now;
    }
}
