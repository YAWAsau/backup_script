package com.xayah.dex;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Run-scoped guard release and confirmed token retirement. Shell owns phase selection. */
public final class GuardLifecycle {
    private static final String[] MAPS={".speedbackup_process_observer_tokens",".speedbackup_cgroup_freezer_tokens",".speedbackup_uid_netblock_tokens"};
    public static void main(String[] args) {
        String result=run(args.length==1?args[0]:"");
        System.out.print(result);System.exit(OperationResult.exitCode(result,"guard-lifecycle"));
    }
    static File runDirectory(File dir) throws Exception {
        File canonical=dir.getCanonicalFile();
        if(!canonical.equals(dir.getAbsoluteFile()) || !canonical.isDirectory()
                || !canonical.getName().startsWith(".speedbackup_run_")
                || !(canonical.getParent().equals("/data/.speedbackup_tmp") || canonical.getParent().equals("/data/local/tmp"))) throw new IOException("run directory");
        return canonical;
    }
    static File child(File run,String raw) throws Exception {
        File f=new File(raw).getAbsoluteFile();
        if(!f.getParentFile().equals(run) || !f.getCanonicalFile().equals(f))throw new IOException("outside run");
        return f;
    }
    private static List<String> lines(File f)throws Exception {
        if(!f.exists())return new ArrayList<>();
        if(!f.isFile() || f.length()>8*1024*1024)throw new IOException("state file");
        return Files.readAllLines(f.toPath(),StandardCharsets.UTF_8);
    }
    private static String field(String line,int index){String[] f=line.split("\t",-1);return f.length>index?f[index]:"";}
    private static int token(String line){return Integer.parseInt(field(line,0));}
    static void replace(File f,List<String> rows)throws Exception {
        File temp=new File(f.getParentFile(),f.getName()+".new."+UUID.randomUUID());
        try {
            Files.write(temp.toPath(),rows,StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);
            android.system.Os.chmod(temp.getPath(),0600);
            Files.move(temp.toPath(),f.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }finally{Files.deleteIfExists(temp.toPath());}
    }
    private static synchronized void prune(File f,Set<Integer> tokens)throws Exception {
        if(tokens.isEmpty()||!f.exists())return;
        List<String> keep=new ArrayList<>();
        for(String row:lines(f))if(row.isEmpty()||row.startsWith("#")||!tokens.contains(token(row)))keep.add(row);
        replace(f,keep);
    }
    private static int number(Properties p,String key,int fallback){return Integer.parseInt(p.getProperty(key,Integer.toString(fallback)));}
    static String publishMaps(String[] args) {
        try {
            if(args.length!=4)throw new IOException("arguments");
            File run=runDirectory(new File(args[1]));File states=child(run,args[2]),errors=child(run,args[3]);
            List<String> rows=lines(states);if(rows.isEmpty()||!errors.isFile()||states.equals(errors))throw new IOException("maps");
            for(String row:rows)if(row.indexOf('\t')<=0 || !field(row,0).matches("[A-Za-z0-9_.]+"))throw new IOException("state row");
            File targetState=new File(run,".pkg_appstate"),targetErrors=new File(run,".appstate_snapshot_errors");
            if(states.equals(targetState)||errors.equals(targetErrors))throw new IOException("staging required");
            Files.move(errors.toPath(),targetErrors.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
            try { Files.move(states.toPath(),targetState.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING); }
            catch(Throwable e){Files.deleteIfExists(targetErrors.toPath());throw e;}
            return new OperationResult("snapshot-map-publish",true).counts(rows.size(),rows.size(),0,0,0).appendTo("");
        }catch(Throwable e){return new OperationResult("snapshot-map-publish",false).appendTo("SNAPSHOT_MAP_PUBLISH_FAILED\n");}
    }
    private static Set<Integer> select(File map,String pkg)throws Exception {
        Set<Integer> selected=new LinkedHashSet<>();
        for(String row:lines(map))if(!row.isEmpty()&&!row.startsWith("#")&&(pkg.equals("-")||pkg.equals(field(row,1)))) {
            int token=token(row);if(token<=0)throw new IOException("token");selected.add(token);
        }
        return selected;
    }
    static String run(String request) {
        StringBuilder out=new StringBuilder();
        int user=-1;String pkg="-";
        try {
            File input=new File(request).getAbsoluteFile();File run=runDirectory(input.getParentFile());child(run,request);
            if(!input.isFile()||input.length()>65536)throw new IOException("request");
            Properties p=new Properties();try(Reader r=new InputStreamReader(new FileInputStream(input),StandardCharsets.UTF_8)){p.load(r);}
            user=number(p,"user",-1);pkg=p.getProperty("package","");String mode=p.getProperty("mode","");
            if(user<0 || !(pkg.equals("-") || pkg.matches("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+"))
                    || !Arrays.asList("app","observer","cgroup","net","all").contains(mode)
                    || (pkg.equals("-")&&!mode.equals("all")))throw new IOException("scope");
            int timeout=number(p,"timeout",1000),corrective=number(p,"corrective",1),thaw=number(p,"thawTimeout",700);
            int wchan=number(p,"wchan",1),verify=number(p,"verify",0);
            if(timeout<0||timeout>60000||thaw<0||thaw>60000||corrective<0||corrective>2||(wchan!=0&&wchan!=1)||(verify!=0&&verify!=1))throw new IOException("options");
            String paused=p.getProperty("paused","-");
            if(!(paused.equals("-")||paused.matches("[1-9][0-9]*(,[1-9][0-9]*)*")))throw new IOException("pids");
            if(!paused.equals("-"))for(String value:paused.split(","))Integer.parseInt(value);
            File[] maps=new File[3];for(int i=0;i<3;i++)maps[i]=child(run,new File(run,MAPS[i]).getPath());
            File batch=p.getProperty("batch","-").equals("-")?null:child(run,p.getProperty("batch"));
            File packages=p.getProperty("batchPackages","-").equals("-")?null:child(run,p.getProperty("batchPackages"));
            File marker=p.getProperty("marker","-").equals("-")?null:child(run,p.getProperty("marker"));
            // Validate every selected row and optional path before any guard mutation.
            List<Set<Integer>> selected=new ArrayList<>();
            String[] kinds={"observer","cgroup","net"};
            for(int i=0;i<3;i++){
                Set<Integer> ids=new LinkedHashSet<>();
                if(mode.equals("all"))ids=select(maps[i],"-");
                else if(mode.equals("app")||mode.equals(kinds[i])) {int id=number(p,kinds[i],0);if(id<0)throw new IOException("token");if(id>0)ids.add(id);}
                selected.add(ids);
            }
            List<String> batchRows=new ArrayList<>();
            if(batch!=null && (mode.equals("app")||mode.equals("all")||mode.equals("observer")))
                for(String row:lines(batch))if(!row.isEmpty()&&!row.startsWith("#")&&(pkg.equals("-")||pkg.equals(field(row,1)))){if(token(row)<=0)throw new IOException("batch token");batchRows.add(row);}
            boolean ok=true;
            if(!batchRows.isEmpty()) {
                File subset=new File(run,".guard_batch_"+UUID.randomUUID());
                try {
                    replace(subset,batchRows);
                    String result=ProcessObserverUtil.stopBatchAsync(subset.getPath(),user);out.append(result);
                    boolean batchOk=BackupGuardRelease.restored(result,"observer-batch-stop",-1);
                    if(batchOk){
                        Set<Integer> ids=new HashSet<>();for(String row:batchRows)ids.add(token(row));
                        prune(batch,ids);prune(maps[0],ids);selected.get(0).removeAll(ids);
                        if(packages!=null){Set<String> left=new HashSet<>();for(String row:lines(batch))left.add(field(row,1));List<String> keep=new ArrayList<>();for(String row:lines(packages))if(left.contains(field(row,0)))keep.add(row);replace(packages,keep);}
                    }else ok=false;
                }finally{Files.deleteIfExists(subset.toPath());}
            }
            if(!mode.equals("all")) {
                int[] ids=new int[3];for(int i=0;i<3;i++)if(!selected.get(i).isEmpty())ids[i]=selected.get(i).iterator().next();
                String result=BackupGuardRelease.release(new String[]{"backupGuardRelease",Integer.toString(user),pkg,Integer.toString(ids[0]),Integer.toString(ids[1]),Integer.toString(ids[2]),Integer.toString(timeout),Integer.toString(corrective),paused,Integer.toString(wchan),Integer.toString(thaw),Integer.toString(verify)});
                out.append(result);boolean released=OperationResult.isOk(result,"backup-guard-release");ok&=released;
                if(released)for(int i=0;i<3;i++)prune(maps[i],selected.get(i));
            }else {
                // Observers first, while all primary freezes remain held. Then thaw, then network.
                for(int i=0;i<3;i++)for(int id:selected.get(i)){
                    String target="";for(String row:lines(maps[i]))if(field(row,0).equals(Integer.toString(id))){target=field(row,1);break;}
                    if(target.isEmpty()){ok=false;continue;}
                    int[] ids=new int[3];ids[i]=id;
                    String result=BackupGuardRelease.release(new String[]{"backupGuardRelease",Integer.toString(user),target,Integer.toString(ids[0]),Integer.toString(ids[1]),Integer.toString(ids[2]),Integer.toString(timeout),Integer.toString(corrective),"-",Integer.toString(wchan),Integer.toString(thaw),Integer.toString(verify)});
                    out.append(result);boolean released=OperationResult.isOk(result,"backup-guard-release");ok&=released;
                    if(released)prune(maps[i],Collections.singleton(id));
                }
            }
            if(ok&&marker!=null)replace(marker,Arrays.asList("package="+pkg,"released=1"));
            return new OperationResult("guard-lifecycle",ok).identity(user,pkg).restoration(ok,ok).appendTo(out);
        }catch(Throwable e){return new OperationResult("guard-lifecycle",false).appendTo(out.append("GUARD_LIFECYCLE_FAILED reason=").append(e.getClass().getSimpleName()).append('\n'));}
    }
}
