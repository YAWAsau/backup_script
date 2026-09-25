package com.xayah.dex;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;
import javax.net.ssl.*;
import javax.xml.parsers.SAXParserFactory;
import org.xml.sax.Attributes;
import org.xml.sax.helpers.DefaultHandler;

/** Bounded, anonymous, read-only LAN discovery. No credentials, redirects or TLS bypass. */
public final class WebDavDiscoveryUtil {
    static final String CAPABILITY = "webdav.lan_discovery.v1";
    static final String DEFAULT_PORTS = "80,443,8080,8081,8000,8443,8765,5005,5006,5244";
    static final String DEFAULT_PATHS = "/,/dav/,/webdav/";
    static final int MAX_TARGETS = 8192, MAX_OPEN = 512, MAX_BODY = 32768;
    static final ScheduledThreadPoolExecutor TIMER = new ScheduledThreadPoolExecutor(1, threads("dav-deadlines"));
    static { TIMER.setRemoveOnCancelPolicy(true); }

    static final class Scope implements AutoCloseable {
        final long end;
        final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
        final AtomicBoolean stopped = new AtomicBoolean();
        final ScheduledFuture<?> alarm;
        Scope(int ms) {
            end = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(ms);
            alarm = TIMER.schedule(this::stop, ms, TimeUnit.MILLISECONDS);
        }
        int left(int cap) throws IOException {
            long ms = TimeUnit.NANOSECONDS.toMillis(end - System.nanoTime());
            if (stopped.get() || Thread.currentThread().isInterrupted() || ms <= 0)
                throw new SocketTimeoutException("scan deadline");
            return (int)Math.min(cap, Math.max(1, ms));
        }
        void add(Socket s) throws IOException {
            sockets.add(s);
            if (stopped.get()) { s.close(); throw new SocketTimeoutException("cancelled"); }
        }
        void stop() {
            stopped.set(true);
            for (Socket s : sockets) try { s.close(); } catch (IOException ignored) {}
        }
        public void close() { stop(); alarm.cancel(false); }
    }
    static final class Endpoint {
        final String ip, scheme, path, source;
        final int port;
        Endpoint(String ip, int port, String scheme, String path, String source) {
            this.ip=ip; this.port=port; this.scheme=scheme; this.path=path; this.source=source;
        }
        String key() { return ip+":"+port; }
        String url(String p, String protocol) { return protocol+"://"+ip+":"+port+p; }
    }
    static final class Result {
        final String url, state, evidence, source;
        final int status;
        final long ms;
        Result(String u, String st, String e, int code, String src, long time) {
            url=u; state=st; evidence=e; status=code; source=src; ms=time;
        }
        boolean confirmed() { return state.startsWith("confirmed"); }
        public String toString() { return url+"\t"+state+"\t"+evidence+"\t"+status+"\t"+source+"\t"+ms; }
    }
    static final class Response {
        int status;
        Map<String,String> headers = new HashMap<>();
        byte[] body = new byte[0];
    }

    public static void main(String[] args) {
        int code;
        try { code = run(args); }
        catch (IllegalArgumentException e) { System.err.println("Invalid discovery arguments: "+e.getMessage()); code=2; }
        catch (Exception e) { System.err.println("Discovery unavailable: "+e.getClass().getSimpleName()); code=1; }
        System.exit(code);
    }
    static int run(String[] a) throws Exception {
        if (a.length == 0 || a[0].equals("help") || a[0].equals("--help")) {
            System.out.println("scanWebDav [auto|IPv4/CIDR] [ports] [paths] [budgetMs:30000] [TCP workers:96] [mdns:1]\n"
                +"probeWebDav http[s]://IP:port/path [budgetMs:5000]\ncapabilities\n"
                +"TSV: URL state evidence httpStatus source elapsedMs. Exit: 0 confirmed; 1 none confirmed; 2 arguments; 3 partial scan.");
            return 0;
        }
        if (a[0].equals("capabilities")) { System.out.println(CAPABILITY); return 0; }
        if (a[0].equals("probeWebDav")) {
            if (a.length < 2) throw new IllegalArgumentException("URL required");
            URI u = URI.create(a[1]);
            if ((!"http".equals(u.getScheme()) && !"https".equals(u.getScheme())) || u.getUserInfo()!=null || u.getRawQuery()!=null || u.getFragment()!=null)
                throw new IllegalArgumentException("anonymous HTTP(S) URL required");
            String ip = ipv4(ipNumber(u.getHost()));
            int port = u.getPort() == -1 ? (u.getScheme().equals("https")?443:80) : u.getPort();
            if (port < 1 || port > 65535) throw new IllegalArgumentException("port");
            String path = validPath(u.getRawPath().isEmpty()?"/":u.getRawPath());
            try (Scope scope = new Scope(integer(a,2,5000,500,30000))) {
                List<Result> r = verify(new Endpoint(ip,port,u.getScheme(),path,"explicit"), Collections.singletonList(path), scope);
                for (Result v:r) System.out.println(v);
                return r.stream().anyMatch(Result::confirmed)?0:1;
            }
        }
        if (!a[0].equals("scanWebDav")) throw new IllegalArgumentException("unknown command");
        List<Integer> ports = ports(a.length>2?a[2]:DEFAULT_PORTS);
        List<String> paths = paths(a.length>3?a[3]:DEFAULT_PATHS);
        int budget=integer(a,4,30000,2000,120000), workers=integer(a,5,96,1,128);
        int mdns=integer(a,6,1,0,1);
        List<String> hosts = hosts(a.length>1?a[1]:"auto");
        if ((long)hosts.size()*ports.size()>MAX_TARGETS) throw new IllegalArgumentException("too many host/port pairs (maximum 8192)");
        return scan(hosts,ports,paths,budget,workers,mdns!=0);
    }
    static int integer(String[] a,int n,int fallback,int min,int max) {
        int v=n<a.length?Integer.parseInt(a[n]):fallback;
        if(v<min||v>max) throw new IllegalArgumentException("argument "+n+" must be "+min+".."+max);
        return v;
    }
    static List<Integer> ports(String s) {
        Set<Integer> out = new LinkedHashSet<>();
        for(String part:s.split(",",-1)) { int p=Integer.parseInt(part); if(p<1||p>65535) throw new IllegalArgumentException("port"); out.add(p); }
        if(out.size()>32) throw new IllegalArgumentException("maximum 32 ports");
        return new ArrayList<>(out);
    }
    static String validPath(String p) {
        if(!p.startsWith("/")||p.startsWith("//")||p.length()>1024||p.contains("?")||p.contains("#")||p.contains("\\")) throw new IllegalArgumentException("path");
        for(char c:p.toCharArray()) if(c<=32||c>=127) throw new IllegalArgumentException("path must be URL encoded");
        // URI validation also rejects malformed percent escapes.
        URI.create("http://127.0.0.1"+p);
        return p;
    }
    static List<String> paths(String s) {
        Set<String> out = new LinkedHashSet<>();
        for(String p:s.split(",",-1)) out.add(validPath(p));
        if(out.size()>8) throw new IllegalArgumentException("maximum 8 paths");
        return new ArrayList<>(out);
    }
    static long ipNumber(String s) {
        if(s==null) throw new IllegalArgumentException("literal IPv4 required");
        String[] parts=s.split("\\.",-1); if(parts.length!=4) throw new IllegalArgumentException("IPv4");
        long n=0;
        for(String p:parts) {
            if(!p.matches("0|[1-9][0-9]{0,2}")) throw new IllegalArgumentException("IPv4");
            int v=Integer.parseInt(p); if(v>255) throw new IllegalArgumentException("IPv4"); n=(n<<8)|v;
        }
        return n;
    }
    static String ipv4(long n) { return ((n>>24)&255)+"."+((n>>16)&255)+"."+((n>>8)&255)+"."+(n&255); }
    static boolean lan(long n) {
        return (n>>>24)==10 || (n>>>24)==127 || (n>>>20)==0xac1 || (n>>>16)==0xc0a8 || (n>>>16)==0xa9fe;
    }
    static List<String> hosts(String scope) throws SocketException {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        if(scope.equals("auto")) {
            for(NetworkInterface ni:Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if(!ni.isUp()||ni.isLoopback()||ni.isPointToPoint()) continue;
                for(InterfaceAddress ia:ni.getInterfaceAddresses()) {
                    if(!(ia.getAddress() instanceof Inet4Address)) continue;
                    long ip=ipNumber(ia.getAddress().getHostAddress()); if(!lan(ip)) continue;
                    int prefix=ia.getNetworkPrefixLength(); if(prefix<0||prefix>32) continue;
                    // Auto discovery stays in the connected /24 on broad enterprise LANs.
                    if(prefix<24) System.err.println("WEBDAV_SCAN_SCOPE interface="+ni.getName()+" originalPrefix="+prefix+" scanPrefix=24");
                    addRange(out,ip,Math.max(24,prefix));
                }
            }
        } else {
            String[] p=scope.split("/",-1); if(p.length>2) throw new IllegalArgumentException("CIDR");
            addRange(out,ipNumber(p[0]),p.length==1?32:Integer.parseInt(p[1]));
        }
        if(out.isEmpty()) throw new IllegalArgumentException("no connected private IPv4 network");
        List<String> ordered = new ArrayList<>();
        // Known neighbors first; this is an ordering hint, never a reachability gate.
        try(BufferedReader reader=new BufferedReader(new FileReader("/proc/net/arp"))) {
            String line; int rows=0;
            while((line=reader.readLine())!=null&&rows++<4096) {
                String ip=line.trim().split("\\s+",2)[0];if(out.remove(ip))ordered.add(ip);
            }
        } catch(IOException ignored) {}
        ordered.addAll(out);return ordered;
    }
    static void addRange(Set<String> out,long ip,int prefix) {
        if(prefix<22||prefix>32) throw new IllegalArgumentException("supported CIDR /22../32");
        long mask=(0xffffffffL<<(32-prefix))&0xffffffffL, first=ip&mask, last=first|(~mask&0xffffffffL);
        if(!lan(first)||!lan(last)) throw new IllegalArgumentException("private LAN IPv4 required");
        if(prefix<=30) {first++;last--;}
        for(long n=first;n<=last;n++) out.add(ipv4(n));
    }
    static ThreadFactory threads(String name) {
        return r -> {Thread t=new Thread(r,name);t.setDaemon(true);return t;};
    }
    static int scan(List<String> hosts,List<Integer> ports,List<String> paths,int budget,int workers,boolean mdns) throws Exception {
        long start=System.nanoTime();
        ExecutorService tcp=Executors.newFixedThreadPool(workers,threads("dav-tcp"));
        ExecutorService http=Executors.newFixedThreadPool(12,threads("dav-http"));
        ExecutorService hints=Executors.newSingleThreadExecutor(threads("dav-hints"));
        CompletionService<Endpoint> connects=new ExecutorCompletionService<>(tcp);
        CompletionService<List<Result>> probes=new ExecutorCompletionService<>(http);
        Map<String,Result> results=new ConcurrentSkipListMap<>();
        Set<String> queued=new HashSet<>();
        int planned=hosts.size()*ports.size(), checked=0, pending=0, verified=0;
        boolean partial=false;
        try(Scope scope=new Scope(budget)) {
            // Discovery and TCP scanning share the budget and run concurrently.
            Future<List<Endpoint>> advertised = mdns
                ? hints.submit(()->WebDavMdns.discover(new HashSet<>(hosts), Math.min(1500,budget/4)))
                : null;
            for(String ip:hosts) for(int port:ports) connects.submit(()->{
                Socket s=new Socket();
                try {
                    scope.add(s); s.connect(new InetSocketAddress(ip,port),scope.left(650));
                    return new Endpoint(ip,port,(port==443||port==8443||port==5006)?"https":"http",null,"tcp");
                } catch(IOException e) {return null;}
                finally {scope.sockets.remove(s);try{s.close();}catch(IOException ignored){}}
            });
            while(checked<planned||verified<pending||advertised!=null) {
                if(System.nanoTime()>=scope.end) {partial=true;break;}
                if(advertised!=null && advertised.isDone()) {
                    try {
                        for(Endpoint e:advertised.get()) {
                            if(pending>=MAX_OPEN) {partial=true;break;}
                            if(queued.add(e.key()+e.path)) {
                                probes.submit(()->verify(e,paths,scope,r->merge(results,r)));pending++;
                            }
                        }
                    } catch(ExecutionException ignored) {
                        // Failed hints never prevent the independent TCP scan.
                    }
                    advertised=null;
                }
                Future<Endpoint> f=connects.poll(20,TimeUnit.MILLISECONDS);
                // Drain ready connections in batches; check hints and deadline between batches.
                for(int batch=0; f!=null && batch<128; batch++) {
                    checked++;
                    Endpoint e=f.get();
                    if(e!=null && queued.add(e.key()+e.path)) {
                        if(pending>=MAX_OPEN) partial=true;
                        else {probes.submit(()->verify(e,paths,scope,r->merge(results,r)));pending++;}
                    }
                    // Do not dequeue a completion that this batch cannot consume.
                    f=batch<127?connects.poll():null;
                }
                Future<List<Result>> p;
                while((p=probes.poll())!=null) {verified++;for(Result r:p.get()) merge(results,r);}
            }
            // Drain work already completed at the deadline before cancelling sockets.
            Future<List<Result>> p;
            while((p=probes.poll())!=null) {verified++;for(Result r:p.get()) merge(results,r);}
            if(scope.stopped.get() || System.nanoTime()>=scope.end) partial=true;
        } finally {tcp.shutdownNow();http.shutdownNow();hints.shutdownNow();tcp.awaitTermination(300,TimeUnit.MILLISECONDS);http.awaitTermination(300,TimeUnit.MILLISECONDS);hints.awaitTermination(300,TimeUnit.MILLISECONDS);}
        int confirmed=0;
        for(Result r:results.values()) {System.out.println(r);if(r.confirmed()) confirmed++;}
        System.err.println("WEBDAV_SCAN_SUMMARY planned="+planned+" tcpCompleted="+checked+" httpPlanned="+pending+" httpCompleted="+verified
            +" confirmed="+confirmed+" candidates="+(results.size()-confirmed)+" partial="+(partial?1:0)+" elapsedMs="+elapsed(start));
        return partial?3:confirmed>0?0:1;
    }
    static void merge(Map<String,Result> out,Result r) {
        synchronized(out) {
            Result old=out.get(r.url);
            if(old==null || (!old.confirmed()&&r.confirmed())) out.put(r.url,r);
        }
    }
    static long elapsed(long start) {return TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start);}
    static List<Result> verify(Endpoint e,List<String> paths,Scope scope) {
        return verify(e,paths,scope,r->{});
    }
    static void record(List<Result> out,Consumer<Result> publish,Result r) {out.add(r);publish.accept(r);}
    static List<Result> verify(Endpoint e,List<String> paths,Scope scope,Consumer<Result> publish) {
        List<Result> out=new ArrayList<>();
        LinkedHashSet<String> candidates=new LinkedHashSet<>();
        if(e.path!=null) candidates.add(e.path);
        if(!e.source.equals("explicit")) candidates.addAll(paths);
        long start=System.nanoTime(), end=Math.min(scope.end,start+TimeUnit.MILLISECONDS.toNanos(6000));
        String scheme=e.scheme;
        for(String path:candidates) {
            if(System.nanoTime()>=end || scope.stopped.get()) break;
            try {
                Response r;
                try {r=request(e,scheme,path,"OPTIONS",scope,end);}
                catch(SSLException x) {throw x;}
                catch(IOException x) {
                    if(!scheme.equals("http")||e.source.equals("explicit")) throw x;
                    // Custom TLS ports may close a plaintext request without an HTTP response.
                    scheme="https";r=request(e,scheme,path,"OPTIONS",scope,end);
                }
                if(davHeader(r.headers.get("dav"))) {
                    record(out,publish,new Result(e.url(path,scheme),(r.status==401||r.status==403)?"confirmed_auth_required":"confirmed",
                        "DAV_header",r.status,e.source,elapsed(start)));
                    continue;
                }
                boolean auth=r.status==401||r.status==403;
                // A normal HTTP server may implement OPTIONS; Depth:0 prevents recursive listing.
                Response prop=request(e,scheme,path,"PROPFIND",scope,end);
                if(prop.status==207 && davXml(prop.body)) record(out,publish,new Result(e.url(path,scheme),"confirmed","DAV_multistatus",207,e.source,elapsed(start)));
                else if(davHeader(prop.headers.get("dav"))) record(out,publish,new Result(e.url(path,scheme),(prop.status==401||prop.status==403)?"confirmed_auth_required":"confirmed","DAV_header",prop.status,e.source,elapsed(start)));
                else if(auth||prop.status==401||prop.status==403) record(out,publish,new Result(e.url(path,scheme),"auth_unconfirmed","HTTP_auth_only",auth?r.status:prop.status,e.source,elapsed(start)));
            } catch(SSLHandshakeException|SSLPeerUnverifiedException x) {
                if(certificateError(x)) record(out,publish,new Result(e.url(path,scheme),"tls_unconfirmed","certificate_untrusted",0,e.source,elapsed(start)));
                break;
            } catch(IOException|IllegalArgumentException ignored) {break;}
        }
        return out;
    }
    static boolean certificateError(Throwable e) {
        for(Throwable t=e;t!=null;t=t.getCause()) if(t instanceof java.security.cert.CertificateException || t instanceof SSLPeerUnverifiedException) return true;
        return false;
    }
    static boolean davHeader(String value) {
        if(value==null) return false;
        for(String s:value.split(",")) if(s.trim().matches("[123]")) return true;
        return false;
    }
    static boolean davXml(byte[] body) {
        // Refuse DTD/entities before parsing and disable all external entity resolution.
        String text=new String(body,StandardCharsets.UTF_8);
        if(text.contains("<!DOCTYPE")||text.contains("<!ENTITY")||text.indexOf('\0')>=0) return false;
        try {
            SAXParserFactory factory=SAXParserFactory.newInstance();factory.setNamespaceAware(true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities",false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
            final boolean[] valid={false};
            factory.newSAXParser().parse(new ByteArrayInputStream(body),new DefaultHandler(){
                int depth; boolean root,response,href,propstat;
                public void startElement(String uri,String local,String q,Attributes attrs) throws org.xml.sax.SAXException {
                    depth++;
                    if(depth>64) throw new org.xml.sax.SAXException("XML nesting limit");
                    if(depth==1) root=uri.equals("DAV:")&&local.equals("multistatus");
                    if(depth==2) {response=root&&uri.equals("DAV:")&&local.equals("response");href=false;propstat=false;}
                    if(depth==3&&response&&uri.equals("DAV:")) {if(local.equals("href")) href=true;if(local.equals("propstat")) propstat=true;}
                }
                public void endElement(String uri,String local,String q) {if(depth==2&&response&&href&&propstat)valid[0]=true;depth--;}
                public org.xml.sax.InputSource resolveEntity(String a,String b) {return new org.xml.sax.InputSource(new StringReader(""));}
            });
            return valid[0];
        } catch(Exception e) {return false;}
    }
    static int timeout(Scope scope,long end,int cap) throws IOException {
        long left=TimeUnit.NANOSECONDS.toMillis(end-System.nanoTime());
        if(left<=0) throw new SocketTimeoutException("endpoint deadline");
        return scope.left((int)Math.min(left,cap));
    }
    static Response request(Endpoint endpoint,String scheme,String path,String method,Scope scope,long end) throws IOException {
        Socket raw=new Socket(), socket=raw;
        ScheduledFuture<?> alarm=TIMER.schedule(()->{try{raw.close();}catch(IOException ignored){}}, timeout(scope,end,2000),TimeUnit.MILLISECONDS);
        try {
            scope.add(raw);
            raw.connect(new InetSocketAddress(endpoint.ip,endpoint.port),timeout(scope,end,1200));
            raw.setSoTimeout(timeout(scope,end,1200));
            if(scheme.equals("https")) {
                SSLSocket tls=(SSLSocket)((SSLSocketFactory)SSLSocketFactory.getDefault()).createSocket(raw,endpoint.ip,endpoint.port,true);
                socket=tls; scope.add(tls);
                SSLParameters p=tls.getSSLParameters();p.setEndpointIdentificationAlgorithm("HTTPS");tls.setSSLParameters(p);tls.startHandshake();
            }
            byte[] body=method.equals("PROPFIND")?"<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>".getBytes(StandardCharsets.UTF_8):new byte[0];
            String headers=method+" "+validPath(path)+" HTTP/1.1\r\nHost: "+endpoint.ip+":"+endpoint.port+"\r\nUser-Agent: SpeedBackup-Discovery/1\r\nConnection: close\r\nAccept-Encoding: identity\r\n"
                +(method.equals("PROPFIND")?"Depth: 0\r\nContent-Type: application/xml; charset=utf-8\r\n":"")+"Content-Length: "+body.length+"\r\n\r\n";
            OutputStream os=socket.getOutputStream();os.write(headers.getBytes(StandardCharsets.US_ASCII));os.write(body);os.flush();
            InputStream in=new BufferedInputStream(socket.getInputStream(),4096);
            Response response=new Response();
            String status=line(in,socket,scope,end,2048);
            if(!status.matches("HTTP/1\\.[01] [1-5][0-9][0-9]( .*|)")) throw new IOException("HTTP status");
            response.status=Integer.parseInt(status.substring(9,12));
            int bytes=status.length(), count=0;
            while(true) {
                String s=line(in,socket,scope,end,8192);bytes+=s.length();
                if(bytes>16384||++count>100) throw new IOException("headers too large");
                if(s.isEmpty()) break;
                int colon=s.indexOf(':');if(colon<=0) throw new IOException("header");
                String key=s.substring(0,colon).toLowerCase(Locale.ROOT), val=s.substring(colon+1).trim();
                if(response.headers.containsKey(key)) val=response.headers.get(key)+","+val;
                response.headers.put(key,val);
            }
            // Body is needed only to distinguish a genuine DAV 207 from generic HTTP/XML.
            if(method.equals("PROPFIND")&&response.status==207) {
                ByteArrayOutputStream b=new ByteArrayOutputStream();
                if("chunked".equalsIgnoreCase(response.headers.get("transfer-encoding"))) {
                    while(true) {
                        String chunk=line(in,socket,scope,end,128).split(";",2)[0].trim();
                        int n;try{n=Integer.parseInt(chunk,16);}catch(NumberFormatException x){throw new IOException("chunk size");}
                        if(n<0||n>MAX_BODY-b.size()) throw new IOException("body too large");
                        if(n==0) break;
                        copy(in,b,n,socket,scope,end);if(!line(in,socket,scope,end,2).isEmpty()) throw new IOException("chunk end");
                    }
                } else if(response.headers.containsKey("content-length")) {
                    int n;try{n=Integer.parseInt(response.headers.get("content-length"));}catch(NumberFormatException x){throw new IOException("length");}
                    if(n<0||n>MAX_BODY)throw new IOException("body too large");copy(in,b,n,socket,scope,end);
                } else {
                    while(b.size()<=MAX_BODY) {int v=read(in,socket,scope,end);if(v<0)break;b.write(v);}
                    if(b.size()>MAX_BODY)throw new IOException("body too large");
                }
                response.body=b.toByteArray();
            }
            return response;
        } finally {
            alarm.cancel(false);
            scope.sockets.remove(raw);scope.sockets.remove(socket);
            try{socket.close();}finally{raw.close();}
        }
    }
    // SO_TIMEOUT is set once per connection. The request alarm closes the raw socket
    // at its absolute deadline, including TLS and slow-drip responses. Reapplying
    // SO_TIMEOUT for each buffered byte caused a native socket call per character.
    static int read(InputStream in,Socket s,Scope scope,long end) throws IOException {return in.read();}
    static String line(InputStream in,Socket s,Scope scope,long end,int max) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream();
        while(b.size()<=max) {
            int v=read(in,s,scope,end);if(v<0)throw new EOFException();
            if(v=='\n') {byte[] out=b.toByteArray();if(out.length==0||out[out.length-1]!='\r')throw new IOException("HTTP line");return new String(out,0,out.length-1,StandardCharsets.ISO_8859_1);}
            b.write(v);
        }
        throw new IOException("HTTP line too long");
    }
    static void copy(InputStream in,ByteArrayOutputStream b,int n,Socket s,Scope scope,long end) throws IOException {
        byte[] buf=new byte[2048];
        while(n>0) {int got=in.read(buf,0,Math.min(n,buf.length));if(got<0)throw new EOFException();b.write(buf,0,got);n-=got;}
    }
}
