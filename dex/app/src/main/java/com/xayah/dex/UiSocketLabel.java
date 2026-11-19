package com.xayah.dex;

import android.net.LocalServerSocket;
import android.system.Os;
import android.system.OsConstants;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/** Creation-only scope on this Java thread; never a process domain transition. */
final class UiSocketLabel {
    private static final String ATTR="/proc/thread-self/attr/sockcreate";
    private static byte[] read()throws Exception {
        FileDescriptor fd=Os.open(ATTR,OsConstants.O_RDONLY|OsConstants.O_CLOEXEC,0);
        try{byte[] b=new byte[4097];int n=Os.read(fd,b,0,b.length);if(n>4096)throw new IOException("socket attribute length");return java.util.Arrays.copyOf(b,n);}finally{Os.close(fd);}
    }
    private static void write(byte[] b)throws Exception {
        FileDescriptor fd=Os.open(ATTR,OsConstants.O_WRONLY|OsConstants.O_CLOEXEC,0);
        try{if(Os.write(fd,b,0,b.length)!=b.length)throw new IOException("socket attribute write");}finally{Os.close(fd);}
    }
    // Runs in root app_process with existing HiddenApiHelper exemptions, not an ordinary APK.
    // Reflective UnixSocketAddress/Os.bind access depends on the actual API 28+ platform APIs.
    @android.annotation.SuppressLint("BlockedPrivateApi")
    static LocalServerSocket bind(String name,int user)throws Exception {
        String domain=new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("/proc/thread-self/attr/current")),StandardCharsets.US_ASCII).replace("\0","").trim();
        // Scope the compatibility fix to the proven failing root domain. Other
        // root-manager domains retain their existing transport, not a guessed label.
        if(!domain.equals("u:r:magisk:s0"))return new LocalServerSocket(name);
        String[] metadata=AppListReturn.socketMetadata(user).split("\t",-1);
        if(metadata.length!=3||!metadata[0].equals("UI_META"))throw new IOException("host installation required");
        String cp=System.getenv("CLASSPATH");
        if(cp==null||cp.contains(":"))throw new IOException("native resolver path");
        File exe=new File(new File(cp).getCanonicalFile().getParentFile(),"speednative");
        android.system.StructStat stat=Os.stat(exe.getPath());
        if(stat.st_uid!=0||(stat.st_mode&0022)!=0)throw new SecurityException("native resolver ownership");
        Process process=new ProcessBuilder(exe.getPath(),"--resolve-ui-context",metadata[1],metadata[2],"io.github.yawasau.speedbackup.webview").redirectError(new File("/dev/null")).start();
        String context;
        try{
            process.getOutputStream().close();
            if(!process.waitFor(8,TimeUnit.SECONDS)||process.exitValue()!=0)throw new IOException("native resolver failed");
            ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[1024];int n;
            try(InputStream in=process.getInputStream()){while((n=in.read(b))!=-1){if(out.size()+n>4097)throw new IOException("native context length");out.write(b,0,n);}}
            context=new String(out.toByteArray(),StandardCharsets.US_ASCII);
            if(context.endsWith("\n"))context=context.substring(0,context.length()-1);
            if(context.isEmpty()||context.split(":",-1).length<4)throw new IOException("native context invalid");
            for(int i=0;i<context.length();i++)if(context.charAt(i)<=32||context.charAt(i)>=127)throw new IOException("native context encoding");
        }finally{process.destroyForcibly();process.getInputStream().close();process.getErrorStream().close();}
        if(read().length!=0)throw new SecurityException("socket scope already active");
        FileDescriptor fd=null;boolean reset=false;
        try{
            write(context.getBytes(StandardCharsets.US_ASCII));
            // Exactly one native socket syscall: no Java lazy socket creation,
            // callbacks, workers, Binder, or logging while the override is set.
            fd=Os.socket(OsConstants.AF_UNIX,OsConstants.SOCK_STREAM|OsConstants.SOCK_CLOEXEC,0);
            write(new byte[]{0});if(read().length!=0)throw new IOException("socket scope reset");reset=true;
        }finally{
            if(!reset){
                if(fd!=null)try{Os.close(fd);}catch(Exception ignored){}
                try{write(new byte[]{0});if(read().length!=0)throw new IOException("socket scope reset");}
                catch(Exception fatal){Runtime.getRuntime().halt(125);}
            }
        }
        boolean transferred=false;
        try{
            // Bind the raw, unconnected fd only after the creation label reset.
            // LocalSocket(FileDescriptor) requires a connected peer (getpeername).
            java.lang.reflect.Method createAbstract=Class.forName("android.system.UnixSocketAddress").getDeclaredMethod("createAbstract",String.class);
            createAbstract.setAccessible(true);
            java.net.SocketAddress address=(java.net.SocketAddress)createAbstract.invoke(null,name);
            java.lang.reflect.Method bind=Os.class.getDeclaredMethod("bind",FileDescriptor.class,java.net.SocketAddress.class);
            bind.setAccessible(true);
            bind.invoke(null,fd,address);
            final FileDescriptor owned=fd;
            LocalServerSocket server=new LocalServerSocket(fd){
                private boolean released;
                @Override public synchronized void close()throws IOException {
                    if(released)return;released=true;
                    // LocalServerSocket's fd wrapper does not own the supplied
                    // descriptor. This wrapper owns the original Os fd.
                    try{super.close();}finally{try{if(owned.valid())Os.close(owned);}catch(android.system.ErrnoException e){throw new IOException(e);}}
                }
            };
            transferred=true;return server;
        }finally{if(!transferred)Os.close(fd);}
    }
}
