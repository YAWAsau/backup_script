package com.xayah.dex;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** HTTP framing over AF_UNIX only. Never opens an IP socket or follows redirects. */
public final class UnixHttpConnection extends HttpURLConnection {
    private static final ScheduledExecutorService TIMER=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"unix-connect-timeout");t.setDaemon(true);return t;});
    private final String name,path;
    private volatile LocalSocket socket;
    private volatile boolean closed;
    private InputStream response;
    private long responseLength=-1;
    private final Map<String,String> headers=new HashMap<>();
    private final ByteArrayOutputStream body=new ByteArrayOutputStream();
    public UnixHttpConnection(String address)throws IOException {
        super(new URL("http://localhost/")); // Required superclass metadata; never used for transport.
        URI u;
        try{u=URI.create(address);}catch(IllegalArgumentException e){throw new IOException("Invalid Unix endpoint",e);}
        name=u.getHost();path=u.getRawPath();
        if(!"unix".equals(u.getScheme())||name==null||!name.matches("sb-ui-[0-9a-f]{64}")||u.getPort()!=-1||u.getRawUserInfo()!=null||u.getRawQuery()!=null||u.getRawFragment()!=null||path==null||!path.matches("/api/[a-z][a-z0-9-]{0,63}"))throw new IOException("Invalid Unix endpoint");
    }
    @Override public OutputStream getOutputStream()throws IOException {
        if(closed||connected)throw new IOException("Connection already closed or sent");
        return new OutputStream(){
            public void write(int b)throws IOException{if(body.size()>=(8*1024*1024))throw new IOException("Request too large");body.write(b);}
            public void write(byte[] b,int off,int n)throws IOException{if(n>(8*1024*1024)-body.size())throw new IOException("Request too large");body.write(b,off,n);}
        };
    }
    /** Safe to display/log: never includes endpoint, headers, body or raw exception text. */
    public static final class TransportFailure extends IOException {
        public final String detail;
        private TransportFailure(String detail,IOException cause){
            super((detail.contains("permissionDeniedText=true")?"本機介面服務存取遭拒":"本機介面服務連線失敗")+"（"+detail.substring(6,detail.indexOf(' '))+"）。請保留日誌供檢查。",cause);
            this.detail=detail;
        }
    }
    private static IOException transportFailure(String stage,IOException error,boolean timedOut){
        String errno="unavailable";
        Throwable cause=error;
        for(int i=0;cause!=null&&i<8;i++,cause=cause.getCause()){
            if(cause instanceof android.system.ErrnoException){errno=Integer.toString(((android.system.ErrnoException)cause).errno);break;}
        }
        // Some Android LocalSocket implementations expose only strerror, not ErrnoException.
        boolean denied=error.getMessage()!=null&&error.getMessage().contains("Permission denied");
        String detail="stage="+stage+" errno="+errno+" permissionDeniedText="+denied+" connectDeadlineExpired="+timedOut;
        android.util.Log.w("SpeedBackupNative","unix-transport "+detail+" uid="+android.os.Process.myUid()+" sdk="+android.os.Build.VERSION.SDK_INT);
        return new TransportFailure(detail,error);
    }
    @Override public void connect()throws IOException {getResponseCode();}
    @Override public int getResponseCode()throws IOException {
        if(responseCode!=-1)return responseCode;
        LocalSocket s=new LocalSocket();
        synchronized(this){if(closed)throw new IOException("Session closed");socket=s;}
        java.util.concurrent.atomic.AtomicBoolean timedOut=new java.util.concurrent.atomic.AtomicBoolean();
        ScheduledFuture<?> timeout=TIMER.schedule(()->{timedOut.set(true);try{s.close();}catch(IOException ignored){}},getConnectTimeout()>0?getConnectTimeout():5000,TimeUnit.MILLISECONDS);
        String stage="abstract-connect";
        try {
            s.connect(new LocalSocketAddress(name,LocalSocketAddress.Namespace.ABSTRACT));
            stage="peer-credentials";
            int peerUid=s.getPeerCredentials().getUid();
            stage="peer-root-check";
            if(peerUid!=0)throw new IOException("Unix peer is not root");
        }catch(IOException e){disconnect();throw transportFailure(stage,e,timedOut.get());}finally{timeout.cancel(false);}
        stage="socket-read-timeout";
        try {
            s.setSoTimeout(getReadTimeout());
            stage="request-headers";
            StringBuilder head=new StringBuilder(method+" "+path+" HTTP/1.1\r\nHost: "+name+"\r\nConnection: close\r\nContent-Length: "+body.size()+"\r\n");
            for(Map.Entry<String,List<String>> h:getRequestProperties().entrySet()){
                String key=h.getKey();if(!key.matches("[A-Za-z0-9-]+"))throw new IOException("Invalid header");
                if(key.equalsIgnoreCase("host")||key.equalsIgnoreCase("content-length")||key.equalsIgnoreCase("connection"))continue;
                for(String value:h.getValue()){for(int i=0;i<value.length();i++){char c=value.charAt(i);if(c<0x20||c>0x7e)throw new IOException("Invalid header value");}head.append(key).append(": ").append(value).append("\r\n");}
            }
            head.append("\r\n");connected=true;
            stage="request-write";
            OutputStream out=s.getOutputStream();out.write(head.toString().getBytes(StandardCharsets.US_ASCII));// Android LocalSocket performs a native write even for zero bytes. A
            // fast server may already have replied and closed after the headers.
            // Do not turn a valid bodyless response into EPIPE with a second write.
            if(body.size()>0)body.writeTo(out);
            out.flush();
            stage="response-headers";
            BufferedInputStream in=new BufferedInputStream(s.getInputStream(),16384);
            String status=line(in);if(!status.matches("HTTP/1\\.[01] [1-5][0-9]{2}( .*)?"))throw new IOException("Invalid response status");
            int code=Integer.parseInt(status.substring(9,12));int total=status.length();
            for(;;){String h=line(in);total+=h.length()+2;if(total>32768)throw new IOException("Response headers too large");if(h.isEmpty())break;
                int colon=h.indexOf(':');if(colon<1)throw new IOException("Invalid response header");String key=h.substring(0,colon).toLowerCase(Locale.ROOT);String value=h.substring(colon+1).trim();
                if(headers.put(key,value)!=null)throw new IOException("Duplicate response header");
            }
            if(headers.containsKey("transfer-encoding"))throw new IOException("Unsupported response encoding");
            long length=-1;
            if(headers.containsKey("content-length")){try{length=Long.parseLong(headers.get("content-length"));}catch(NumberFormatException e){throw new IOException("Invalid response length",e);}if(length<0)throw new IOException("Invalid response length");}
            responseLength=length;
            final long size=length;
            response=new FilterInputStream(in){long remaining=size;
                @Override public int read()throws IOException{byte[] b=new byte[1];int n=read(b,0,1);return n<0?-1:b[0]&255;}
                @Override public int read(byte[] b,int off,int len)throws IOException{if(len==0)return 0;if(remaining==0)return -1;int n=in.read(b,off,remaining<0?len:(int)Math.min(len,remaining));if(n<0&&remaining>0)throw new EOFException("Truncated Unix response");if(n>0&&remaining>0)remaining-=n;return n;}
            };
            responseCode=code;return code;
        }catch(IOException e){disconnect();throw transportFailure(stage,e,false);}
        catch(RuntimeException e){disconnect();throw e;}
    }
    private static String line(InputStream in)throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream();int previous=-1;
        for(;;){int c=in.read();if(c<0)throw new EOFException("Truncated response header");if(previous=='\r'&&c=='\n'){byte[] bytes=b.toByteArray();return new String(bytes,0,bytes.length-1,StandardCharsets.US_ASCII);}if(b.size()>=8192)throw new IOException("Response header line too large");b.write(c);previous=c;}
    }
    @Override public InputStream getInputStream()throws IOException{getResponseCode();return response;}
    @Override public InputStream getErrorStream(){return responseCode>=400?response:null;}
    @Override public long getContentLengthLong(){return responseLength;}
    @Override public String getHeaderField(String key){return key==null?null:headers.get(key.toLowerCase(Locale.ROOT));}
    @Override public boolean usingProxy(){return false;}
    @Override public void disconnect(){LocalSocket s;synchronized(this){closed=true;s=socket;socket=null;}if(s!=null)try{s.close();}catch(IOException ignored){}}
}
