package com.xayah.dex;


/** Run-scoped persistent recovery, before daemon shutdown. Continue all stages on failure. */
final class RunStateCleanup {
    // Ordered release owners. Each owner retains its own synchronization, scope
    // resolution and restore-before-unlink policy; this registry never deletes
    // their files or substitutes an aggregate scan for their recovery work.
    enum Resource {
        OBSERVER("observer-cleanup", "SPEEDBACKUP_PROCESS_OBSERVER_BATCH_STATE_DIR", ".speedbackup_process_observer_batch_state") {
            String release(String reason) { return ProcessObserverUtil.cleanupStalePersistentStates(reason,0); }
        },
        WAKE("wake-cleanup", "SPEEDBACKUP_WAKEBLOCK_STATE_DIR", ".speedbackup_wakeblock_state") {
            String release(String reason) { return AppWakeBlockUtil.cleanupStalePersistentStates(reason,0); }
        },
        UID_NETWORK("uidnet-cleanup", "SPEEDBACKUP_UID_NETBLOCK_STATE_DIR", ".speedbackup_uid_netblock_state") {
            String release(String reason) { return UidNetworkBlockUtil.cleanupStalePersistentStates(reason,0); }
        },
        CGROUP("cgroup-cleanup", "SPEEDBACKUP_CGROUP_FREEZER_STATE_FILE", ".speedbackup_cgroup_freezer_state") {
            String release(String reason) { return CgroupFreezeUtil.cleanupStalePersistentStates(reason,0); }
        };
        final String operation;
        final String environment, basename;
        Resource(String operation, String environment, String basename) {
            this.operation=operation; this.environment=environment; this.basename=basename;
        }
        String statePath() { return scopedPath(environment, basename); }
        abstract String release(String reason);
    }
    // Used at owner initialization, before any recovery record is acquired.
    // Environment overrides and fallback scope retain the legacy precedence.
    static String scopedPath(String environment, String basename) {
        String override = System.getenv(environment);
        if (override != null && !override.isEmpty()) return override;
        java.io.File dir = new java.io.File(scopedTmpDir());
        try { dir.mkdirs(); } catch (Throwable ignored) {}
        return new java.io.File(dir, basename).getAbsolutePath();
    }
    static String scopedTmpDir() {
        String run = System.getenv("SPEEDBACKUP_RUN_TMPDIR");
        if (run != null && !run.isEmpty()) return run;
        String tmp = System.getenv("TMPDIR");
        if (tmp != null && tmp.contains(".speedbackup_run_") && !tmp.isEmpty()) return tmp;
        return GuardLifecycle.fallbackRunDirectory();
    }
    private static final Resource[] RESOURCES=Resource.values();
    static String run(String reason) {
        StringBuilder out=new StringBuilder();boolean ok=true;
        for(int stage=0;stage<RESOURCES.length;stage++) {
            try {
                Resource resource=RESOURCES[stage];
                String result=resource.release(reason);
                out.append(result);if(!OperationResult.isOk(result,resource.operation))ok=false;
            } catch(Throwable e){ok=false;out.append("RUN_STATE_CLEANUP_FAILED stage=").append(stage).append(" reason=").append(e.getClass().getSimpleName()).append('\n');}
        }
        return new OperationResult("run-state-cleanup",ok).restoration(ok,ok).appendTo(out);
    }
}
