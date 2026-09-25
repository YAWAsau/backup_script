package com.xayah.dex;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** DNS-SD hints over legacy unicast replies, usable from app_process without a Context. */
final class WebDavMdns {
    static final String HTTP="_webdav._tcp.local.", HTTPS="_webdavs._tcp.local.";
    static final class Service {
        String target, path="/", type;
        int port;
    }
    static final class Cache {
        final Map<String,Service> services=new HashMap<>();
        final Map<String,Set<String>> addresses=new HashMap<>();
        final Set<String> asked=new HashSet<>();
        Service service(String n) throws IOException {
            if(services.size()>=64&&!services.containsKey(n))throw new IOException("too many services");
            return services.computeIfAbsent(n,k->new Service());
        }
        void accept(byte[] packet) throws IOException {
            Reader r=new Reader(packet);
            r.u16();int flags=r.u16(), questions=r.u16(), records=r.u16()+r.u16()+r.u16();
            if((flags&0x800f)!=0x8000 || questions>32 || records>128) return;
            for(int i=0;i<questions;i++){r.name();r.u16();r.u16();}
            for(int i=0;i<records;i++) {
                String name=r.name().toLowerCase(Locale.ROOT);int type=r.u16(), cls=r.u16();long ttl=r.u32();int len=r.u16(), end=r.pos+len;
                if(end>packet.length)throw new EOFException();
                if((cls&0x7fff)==1 && ttl>0) {
                    if(type==12&&(name.equals(HTTP)||name.equals(HTTPS))) {
                        String instance=r.name().toLowerCase(Locale.ROOT);
                        if(instance.endsWith("."+name)) service(instance).type=name;
                    } else if(type==33&&(name.endsWith("."+HTTP)||name.endsWith("."+HTTPS))) {
                        r.u16();r.u16();Service s=service(name);s.port=r.u16();s.target=r.name().toLowerCase(Locale.ROOT);
                    } else if(type==16&&(name.endsWith("."+HTTP)||name.endsWith("."+HTTPS))) {
                        while(r.pos<end) {
                            int n=r.u8();if(r.pos+n>end)throw new IOException("TXT length");
                            String txt=new String(packet,r.pos,n,StandardCharsets.UTF_8);r.pos+=n;
                            if(txt.startsWith("path=")) {try{service(name).path=WebDavDiscoveryUtil.validPath(txt.substring(5));}catch(IllegalArgumentException ignored){}}
                        }
                    } else if(type==1&&len==4&&addresses.size()<128) {
                        String ip=WebDavDiscoveryUtil.ipv4(r.u32());
                        addresses.computeIfAbsent(name,k->new HashSet<>()).add(ip);
                    }
                }
                if(r.pos>end)throw new IOException("DNS RDATA overrun");r.pos=end;
            }
        }
        List<WebDavDiscoveryUtil.Endpoint> endpoints(Set<String> allowed) {
            List<WebDavDiscoveryUtil.Endpoint> out=new ArrayList<>();
            for(Service s:services.values()) {
                if(s.type==null||s.target==null||s.port<=0)continue;
                for(String ip:addresses.getOrDefault(s.target,Collections.emptySet())) if(allowed.contains(ip))
                    out.add(new WebDavDiscoveryUtil.Endpoint(ip,s.port,s.type.equals(HTTPS)?"https":"http",s.path,"mdns"));
            }
            return out;
        }
    }
    static List<WebDavDiscoveryUtil.Endpoint> discover(Set<String> allowed,int ms) {
        List<NetworkInterface> interfaces=new ArrayList<>();
        try {
            for(NetworkInterface ni:Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if(!ni.isUp()||ni.isLoopback()||!ni.supportsMulticast())continue;
                for(InetAddress ip:Collections.list(ni.getInetAddresses())) if(ip instanceof Inet4Address && allowed.contains(ip.getHostAddress())) {interfaces.add(ni);break;}
                if(interfaces.size()>=4)break;
            }
        } catch(SocketException e) {return Collections.emptyList();}
        ExecutorService pool=Executors.newFixedThreadPool(Math.max(1,interfaces.size()),WebDavDiscoveryUtil.threads("dav-mdns"));
        List<Future<List<WebDavDiscoveryUtil.Endpoint>>> jobs=new ArrayList<>();
        long end=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(ms+150);
        try {
            for(NetworkInterface ni:interfaces)jobs.add(pool.submit(()->discoverOn(ni,allowed,ms)));
            List<WebDavDiscoveryUtil.Endpoint> out=new ArrayList<>();
            for(Future<List<WebDavDiscoveryUtil.Endpoint>> f:jobs) try {out.addAll(f.get(Math.max(1,TimeUnit.NANOSECONDS.toMillis(end-System.nanoTime())),TimeUnit.MILLISECONDS));}catch(Exception ignored){}
            return out;
        } finally {pool.shutdownNow();}
    }
    static List<WebDavDiscoveryUtil.Endpoint> discoverOn(NetworkInterface ni,Set<String> allowed,int ms) {
        Cache cache=new Cache();
        try(MulticastSocket socket=new MulticastSocket(0)) {
            socket.setNetworkInterface(ni);socket.setTimeToLive(255);socket.setSoTimeout(100);
            InetAddress group=InetAddress.getByAddress(new byte[]{(byte)224,0,0,(byte)251});
            send(socket,group,HTTP,12);send(socket,group,HTTPS,12);
            long end=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(ms), retry=end-TimeUnit.MILLISECONDS.toNanos(ms/2);
            boolean retried=false;int received=0;
            while(System.nanoTime()<end&&!Thread.currentThread().isInterrupted()&&received<128) {
                if(!retried&&System.nanoTime()>=retry){send(socket,group,HTTP,12);send(socket,group,HTTPS,12);retried=true;}
                byte[] bytes=new byte[9000];DatagramPacket packet=new DatagramPacket(bytes,bytes.length);
                try {socket.receive(packet);}catch(SocketTimeoutException e){continue;}
                received++;
                if(packet.getPort()!=5353 || !allowed.contains(packet.getAddress().getHostAddress()))continue;
                try {cache.accept(Arrays.copyOf(bytes,packet.getLength()));}catch(IOException e){continue;}
                for(Map.Entry<String,Service> entry:cache.services.entrySet()) {
                    Service s=entry.getValue();
                    if(s.type==null)continue;
                    if(s.target==null) {
                        if(cache.asked.size()<64&&cache.asked.add(entry.getKey())){send(socket,group,entry.getKey(),33);send(socket,group,entry.getKey(),16);}
                    } else if(!cache.addresses.containsKey(s.target)&&cache.asked.size()<64&&cache.asked.add(s.target)) send(socket,group,s.target,1);
                }
            }
        } catch(IOException|RuntimeException ignored) { /* Multicast failure does not suppress TCP fallback. */ }
        return cache.endpoints(allowed);
    }
    static void send(DatagramSocket socket,InetAddress group,String name,int type) throws IOException {
        byte[] query=query(name,type);socket.send(new DatagramPacket(query,query.length,group,5353));
    }
    static byte[] query(String name,int type) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream();DataOutputStream d=new DataOutputStream(b);
        d.writeShort(0);d.writeShort(0);d.writeShort(1);d.writeShort(0);d.writeShort(0);d.writeShort(0);
        for(String label:name.split("\\.")) {byte[] v=label.getBytes(StandardCharsets.UTF_8);if(v.length<1||v.length>63)throw new IOException("DNS label");d.writeByte(v.length);d.write(v);}
        d.writeByte(0);d.writeShort(type);d.writeShort(1);return b.toByteArray();
    }
    static final class Reader {
        final byte[] bytes;int pos;
        Reader(byte[] b){bytes=b;}
        int u8() throws IOException {if(pos>=bytes.length)throw new EOFException();return bytes[pos++]&255;}
        int u16() throws IOException {return (u8()<<8)|u8();}
        long u32() throws IOException {return ((long)u16()<<16)|u16();}
        String name() throws IOException {
            int at=pos, resume=-1, hops=0;StringBuilder s=new StringBuilder();
            while(true) {
                if(at>=bytes.length||++hops>64)throw new IOException("DNS name cycle");int n=bytes[at++]&255;
                if((n&192)==192) {if(at>=bytes.length)throw new EOFException();int target=((n&63)<<8)|(bytes[at++]&255);if(resume<0)resume=at;at=target;continue;}
                if(n==0)break;
                if(n>63||at+n>bytes.length||s.length()+n+1>255)throw new IOException("DNS name size");
                s.append(new String(bytes,at,n,StandardCharsets.UTF_8)).append('.');at+=n;
            }
            pos=resume<0?at:resume;return s.toString();
        }
    }
}
