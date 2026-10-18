package com.xayah.dex;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** Per-run root file broker; never retries a transmitted mutation. */
final class NativeFileClient {
    private static Process process;
    private static File socket;
    private static int pid;
    private static Long started;
    private static boolean ready;
    private static boolean uncertain;
    static final class OperationFailure extends IOException {
        final int code;
        OperationFailure(int code){super("file operation failed rc="+code);this.code=code;}
    }
    private static final class TransportFailure extends IOException {
        final boolean written;
        TransportFailure(boolean written,Exception cause){super(cause);this.written=written;}
    }
    private static final ScheduledExecutorService DEADLINES=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"file-rpc-deadline");t.setDaemon(true);return t;});
    private static void need(boolean yes,String message)throws IOException{if(!yes)throw new IOException(message);}
    private static void privateDir(File f)throws Exception {
        StructStat st=Os.lstat(f.getPath());
        need(OsConstants.S_ISDIR(st.st_mode)&&st.st_uid==0&&(st.st_mode&0777)==0700,"unsafe file RPC directory");
        need(f.getCanonicalFile().equals(f.getAbsoluteFile()),"linked file RPC directory");
    }
    private static void ensure()throws Exception {
        if(ready && process!=null && process.isAlive())return;
        ready=false;
        if(process!=null && process.isAlive()) {
            process.destroy();
            if(!process.waitFor(2,TimeUnit.SECONDS)) {
                process.destroyForcibly();
                need(process.waitFor(2,TimeUnit.SECONDS),"old file RPC process not reaped");
            }
        }
        String root=System.getenv("SPEEDBACKUP_RUN_TMPDIR");need(root!=null,"run directory missing");
        File run=new File(root);privateDir(run);
        File dir=new File(run,"fo-"+UUID.randomUUID().toString().replace("-","").substring(0,16));
        need(new File(dir,"fileops.sock").getPath().getBytes(StandardCharsets.UTF_8).length<104,"file RPC socket path too long");
        need(dir.mkdir(),"cannot create file RPC directory");Os.chmod(dir.getPath(),0700);privateDir(dir);
        String selected=System.getenv("SPEEDBACKUP_FILEOPS_NATIVE");
        if(selected==null || selected.isEmpty()) {String cg=CgroupFreezeUtil.nativeHelperPath();need(cg!=null,"native helper missing");selected=new File(new File(cg).getParentFile(),"speednative").getPath();}
        File helper=new File(selected).getCanonicalFile();
        StructStat exe=Os.stat(helper.getPath());need(OsConstants.S_ISREG(exe.st_mode)&&exe.st_uid==0&&(exe.st_mode&0022)==0,"unsafe native executable");
        int owner=android.os.Process.myPid();Long ownerStart=DaemonBootstrap.readProcStarttime(owner);need(ownerStart!=null,"owner missing");
        socket=new File(dir,"fileops.sock");
        process=new ProcessBuilder(helper.getPath(),"speedscan","file-daemon",socket.getPath(),Integer.toString(owner),ownerStart.toString())
            .redirectErrorStream(true).redirectOutput(new File(dir,"daemon.log")).start();
        pid=processPid(process);need(pid>1,"file RPC PID unavailable");started=DaemonBootstrap.readProcStarttime(pid);
        long until=SystemClock.elapsedRealtime()+5000;
        while(!socket.exists()&&process.isAlive()&&SystemClock.elapsedRealtime()<until)Thread.sleep(10);
        need(socket.exists()&&process.isAlive()&&started!=null,"file RPC startup failed");
        Reply hello=exchange(Arrays.asList("SBFILE1",id(),"HELLO"),3000,false);
        need(hello.state.equals("hello")&&hello.rc==0&&new String(hello.body,StandardCharsets.UTF_8).equals(DexBuildInfo.PATCH_BUILD),"file RPC version mismatch");
        ready=true;
    }
    private static String id(){return UUID.randomUUID().toString().replace("-","");}
    private static int processPid(Process child)throws Exception {
        try {return ((Number)child.getClass().getMethod("pid").invoke(child)).intValue();}
        catch(NoSuchMethodException unavailable) {
            // Android UNIXProcess exposes a field on releases without Process.pid().
            java.lang.reflect.Field field=child.getClass().getDeclaredField("pid");
            field.setAccessible(true);return ((Number)field.get(child)).intValue();
        }
    }
    private static final class Reply {String state;int rc;byte[] body;}
    private static Reply reply(InputStream in,String request)throws Exception {
        ByteArrayOutputStream line=new ByteArrayOutputStream();int b;
        while((b=in.read())!='\n'){need(b>=0&&line.size()<180,"missing file RPC receipt");line.write(b);}
        String[] h=line.toString("US-ASCII").split(" ",-1);
        need(h.length==5&&h[0].equals("SBFILE1")&&h[1].equals(request),"invalid file RPC receipt");
        Reply r=new Reply();r.state=h[2];r.rc=Integer.parseInt(h[3]);int n=Integer.parseInt(h[4]);need(n>=0&&n<=1048576,"oversize file RPC response");
        r.body=new byte[n];new DataInputStream(in).readFully(r.body);return r;
    }
    private static Reply exchange(List<String> fields,int timeout,boolean mutation)throws Exception {
        ByteArrayOutputStream body=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(body);
        for(String field:fields){byte[] b=field.getBytes(StandardCharsets.UTF_8);need(b.length<=8192&&!field.contains("\0"),"invalid file RPC argument");out.writeInt(b.length);out.write(b);}
        need(body.size()<=65536,"file RPC request too large");
        boolean written=false;
        try(LocalSocket s=new LocalSocket()) {
            s.connect(new LocalSocketAddress(socket.getPath(),LocalSocketAddress.Namespace.FILESYSTEM));
            need(s.getPeerCredentials().getUid()==0&&s.getPeerCredentials().getPid()==pid&&started.equals(DaemonBootstrap.readProcStarttime(pid)),"file RPC peer mismatch");
            s.setSoTimeout(timeout);
            ScheduledFuture<?> timer=DEADLINES.schedule(()->{try{s.close();}catch(IOException ignored){}},timeout,TimeUnit.MILLISECONDS);
            try {
                DataOutputStream stream=new DataOutputStream(s.getOutputStream());
                written=true; // Includes partial writes: never replay after this point.
                stream.writeInt(body.size());body.writeTo(stream);stream.flush();
                // Keep output open: EOF is cancellation, not an end-of-request marker.
                Reply first=reply(s.getInputStream(),fields.get(1));
                if(!mutation)return first;
                if(first.state.equals("rejected")){first.rc=124;return first;}
                need(first.state.equals("accepted")&&first.rc==0&&first.body.length==0,"file RPC rejected");
                Reply last=reply(s.getInputStream(),fields.get(1));need(last.state.equals("done")||last.state.equals("not-started"),"file RPC incomplete");return last;
            } finally {timer.cancel(false);}
        } catch(Exception e){throw new TransportFailure(written,e);}
    }
    static synchronized void run(String... args)throws Exception {
        need(!uncertain,"previous file RPC outcome uncertain; restore session stopped");
        ensure();String request=id();ArrayList<String> fields=new ArrayList<>(Arrays.asList("SBFILE1",request,"RUN","600000"));fields.addAll(Arrays.asList(args));
        long begin=SystemClock.elapsedRealtime();
        try {
            Reply r;
            try {r=exchange(fields,602000,true);}
            catch(TransportFailure e) {
                if(e.written)throw e;
                ready=false;ensure();
                r=exchange(fields,602000,true);
            }
            // Preserve engine diagnostics, but success is decided by the broker's waitpid result.
            System.err.write(r.body);System.err.flush();
            if(r.rc!=0)throw new OperationFailure(r.rc);
            System.err.println("FILE_RPC_OK command="+args[0]+" elapsedMs="+(SystemClock.elapsedRealtime()-begin));
        } catch(Exception e){
            if(e instanceof TransportFailure && ((TransportFailure)e).written)uncertain=true;
            if(e instanceof OperationFailure && ((OperationFailure)e).code==125)uncertain=true;
            System.err.println((uncertain?"FILE_RPC_UNSAFE":"FILE_RPC_FAILED")+" request="+request+" retry=false command="+args[0]);
            throw e;
        }
    }
}
