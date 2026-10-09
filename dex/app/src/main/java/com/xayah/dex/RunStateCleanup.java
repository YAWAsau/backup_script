package com.xayah.dex;

import java.util.regex.Pattern;

/** Run-scoped persistent recovery, before daemon shutdown. Continue all stages on failure. */
final class RunStateCleanup {
    private static final Pattern FAILED=Pattern.compile("_FAILED|_REJECTED|stateRetained=true|stateDeleted=false|fail(ures|ed)?=[1-9]");
    static String run(String reason) {
        StringBuilder out=new StringBuilder();boolean ok=true;
        for(int stage=0;stage<4;stage++) {
            try {
                String result;
                switch(stage) {
                    case 0:result=ProcessObserverUtil.cleanupStalePersistentStates(reason,0);break;
                    case 1:result=AppWakeBlockUtil.cleanupStalePersistentStates(reason,0);break;
                    case 2:result=UidNetworkBlockUtil.cleanupStalePersistentStates(reason,0);break;
                    default:result=CgroupFreezeUtil.cleanupStalePersistentStates(reason,0);
                }
                out.append(result);if(FAILED.matcher(result).find())ok=false;
            } catch(Throwable e){ok=false;out.append("RUN_STATE_CLEANUP_FAILED stage=").append(stage).append(" reason=").append(e.getClass().getSimpleName()).append('\n');}
        }
        return new OperationResult("run-state-cleanup",ok).restoration(ok,ok).appendTo(out);
    }
}
