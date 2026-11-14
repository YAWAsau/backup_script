package com.xayah.dex;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import org.json.JSONObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

/** Optional metadata only. Rust owns reachability and closes stdin on exit.
 * Uses Android callbacks/broadcasts; never starts a Wi-Fi scan or polls.
 * Compatibility references: AOSP WifiStatusTracker and VREM WiFiAnalyzer WiFiWidth.
 */
public final class WifiConnectionWatch {
    private final File directory;
    private final WifiManager wifi;
    private final ConnectivityManager connectivity;
    private String last = "";
    private Object tetherManager,tetherCallback;
    private final java.util.Map<String,Integer> tethered=new java.util.TreeMap<>();
    private final java.util.Map<String,Integer> localOnly=new java.util.TreeMap<>();
    private final java.util.Map<Integer,java.util.List<String>> tetherRegex=new java.util.HashMap<>();
    private boolean tetherKnown=false;
    private final java.util.Set<Network> lostNetworks=new java.util.HashSet<>();
    private Network primaryNetwork;
    private WifiInfo primaryInfo;
    private void refreshFromSystem() {
        try {
            // The registered callback owns this identity until onLost; deprecated
            // NetworkInfo may be null on OEM ROMs while the callback is still valid.
            if(wifi.isWifiEnabled()&&primaryNetwork!=null&&primaryInfo!=null){update(primaryInfo);return;}
        } catch(Exception ignored) { }
        primaryNetwork=null;primaryInfo=null;
        update(null);
    }
    private WifiConnectionWatch(File directory, Context context) {
        this.directory=directory;
        wifi=(WifiManager)context.getSystemService(Context.WIFI_SERVICE);
        connectivity=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
    }
    private static Object invoke(Object target,String method) throws Exception {return target.getClass().getMethod(method).invoke(target);}
    private void regex(Object source) {
        String[] methods={"getTetherableWifiRegexs","getTetherableUsbRegexs","getTetherableBluetoothRegexs"};
        for(int type=0;type<methods.length;type++)try{
            Object values=invoke(source,methods[type]);java.util.List<String> list=new java.util.ArrayList<>();
            if(values instanceof String[])java.util.Collections.addAll(list,(String[])values);
            else if(values instanceof Iterable)for(Object value:(Iterable<?>)values)if(value instanceof String)list.add((String)value);
            tetherRegex.put(type,list);
        }catch(Exception | LinkageError ignored){}
    }
    private int tetherType(String name) {
        for(java.util.Map.Entry<Integer,java.util.List<String>> entry:tetherRegex.entrySet())for(String pattern:entry.getValue())
            try{if(name.matches(pattern))return entry.getKey();}catch(RuntimeException ignored){}
        return -1; // Never infer a sharing role solely from an OEM interface name.
    }
    private void interfaces(Object values,java.util.Map<String,Integer> output) {
        output.clear();
        Iterable<?> list=values instanceof Iterable?(Iterable<?>)values:values instanceof String[]?java.util.Arrays.asList((String[])values):java.util.Collections.emptyList();
        for(Object value:list)try{
            String name;int type=-1;
            if(value instanceof String)name=(String)value;
            else {name=(String)invoke(value,"getInterface");type=((Number)invoke(value,"getType")).intValue();}
            if(name!=null&&name.matches("[a-zA-Z0-9_.-]{1,32}"))output.put(name,type);
        }catch(Exception | LinkageError ignored){}
    }
    private void tetherBroadcast(Intent intent) {
        if(!"android.net.conn.TETHER_STATE_CHANGED".equals(intent.getAction())||tetherCallback!=null)return;
        if(intent.hasExtra("tetherArray")){
            Object names=intent.getExtras().get("tetherArray");interfaces(names,tethered);tetherKnown=true;
            interfaces(intent.getExtras().get("android.net.extra.ACTIVE_LOCAL_ONLY"),localOnly);
        }
    }
    private void startTether(Context context,Handler handler) {
        try{
            tetherManager=context.getSystemService("tethering");
            if(tetherManager==null)throw new IllegalStateException();
            Class<?> callback=Class.forName("android.net.TetheringManager$TetheringEventCallback");
            Object proxy=java.lang.reflect.Proxy.newProxyInstance(callback.getClassLoader(),new Class<?>[]{callback},(object,method,args)->{
                String name=method.getName();
                if(name.equals("hashCode"))return System.identityHashCode(object);
                if(name.equals("equals"))return object==args[0];
                if(name.equals("toString"))return "SpeedBackupTetherEvents";
                if(args!=null&&args.length>0){
                    if(name.equals("onTetheredInterfacesChanged")){interfaces(args[0],tethered);tetherKnown=true;refreshFromSystem();}
                    else if(name.equals("onLocalOnlyInterfacesChanged")){interfaces(args[0],localOnly);refreshFromSystem();}
                    else if(name.equals("onTetherableInterfaceRegexpsChanged")){regex(args[0]);refreshFromSystem();}
                }
                return null;
            });
            tetherManager.getClass().getMethod("registerTetheringEventCallback",java.util.concurrent.Executor.class,callback)
                .invoke(tetherManager,(java.util.concurrent.Executor)r->handler.post(r),proxy);
            tetherCallback=proxy;
        }catch(Exception | LinkageError ignored){tetherCallback=null;regex(connectivity);}
    }
    private void stopTether() {
        if(tetherCallback!=null)try{tetherManager.getClass().getMethod("unregisterTetheringEventCallback",Class.forName("android.net.TetheringManager$TetheringEventCallback")).invoke(tetherManager,tetherCallback);}catch(Exception | LinkageError ignored){}
    }
    private void networkMetadata(JSONObject value) throws Exception {
        org.json.JSONArray links=new org.json.JSONArray();
        boolean networksKnown=true;
        Network[] networks=connectivity.getAllNetworks();
        lostNetworks.retainAll(java.util.Arrays.asList(networks));
        for(Network network:networks)try{
            if(lostNetworks.contains(network))continue;
            NetworkCapabilities cap=connectivity.getNetworkCapabilities(network);android.net.LinkProperties properties=connectivity.getLinkProperties(network);
            if(cap==null||properties==null||properties.getInterfaceName()==null){networksKnown=false;continue;}
            String kind=cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN)?"vpn":cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)?"wifi":cap.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)?"ethernet":cap.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)?"cellular":"network";
            links.put(new JSONObject().put("interface",properties.getInterfaceName()).put("kind",kind));
        }catch(Exception | LinkageError ignored){networksKnown=false;}
        org.json.JSONArray sharing=new org.json.JSONArray();
        java.util.Map<String,Integer> all=new java.util.TreeMap<>(localOnly);all.putAll(tethered);
        for(java.util.Map.Entry<String,Integer> entry:all.entrySet()){
            int type=entry.getValue()<0?tetherType(entry.getKey()):entry.getValue();
            String kind=type==0?"hotspot":type==1||type==4?"usb_tether":type==2?"bluetooth_tether":type==5?"ethernet_tether":"tether";
            sharing.put(new JSONObject().put("interface",entry.getKey()).put("kind",kind));
        }
        value.put("networkKnown",networksKnown).put("links",links).put("sharing",sharing).put("sharingKnown",tetherKnown);
    }
    private static String width(int value) {
        switch(value) { case 0:return "20";case 1:return "40";case 2:return "80";
            case 3:return "160";case 4:return "80+80";case 5:return "320";default:return ""; }
    }
    @SuppressWarnings("deprecation")
    private String connectedInterface(WifiInfo info) {
        try {
            String candidate="";int count=0;
            for(Network network:connectivity.getAllNetworks()) {
                NetworkCapabilities capabilities=connectivity.getNetworkCapabilities(network);
                if(capabilities==null||!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI))continue;
                android.net.LinkProperties properties=connectivity.getLinkProperties(network);
                if(properties==null)continue;
                String name=properties.getInterfaceName();
                if(name==null||!name.matches("[a-zA-Z0-9_.-]{1,32}"))continue;
                candidate=name;count++;
                int ip=info.getIpAddress();
                if(ip!=0)for(android.net.LinkAddress address:properties.getLinkAddresses()) {
                    byte[] bytes=address.getAddress().getAddress();
                    if(bytes.length==4&&((bytes[0]&255)|((bytes[1]&255)<<8)|((bytes[2]&255)<<16)|((bytes[3]&255)<<24))==ip)return name;
                }
            }
            return count==1?candidate:"";
        } catch(Exception ignored) {return "";}
    }
    // Optional driver query, only on Android events. No scans, timers or bundled iw.
    // Match the current primary frequency; never use a different MLO link's width.
    private String driverWidth(WifiInfo info) {
        Process process=null;
        try {
            if(!new File("/system/bin/iw").canExecute())return "";
            String name=connectedInterface(info);if(name.isEmpty())return "";
            process=new ProcessBuilder("/system/bin/iw","dev",name,"info").redirectErrorStream(true).start();
            if(!process.waitFor(1,java.util.concurrent.TimeUnit.SECONDS)||process.exitValue()!=0)return "";
            byte[] buffer=new byte[16385];int size=0,n;
            try(java.io.InputStream stream=process.getInputStream()) {
                while(size<buffer.length&&(n=stream.read(buffer,size,buffer.length-size))>0)size+=n;
            }
            if(size==buffer.length)return "";
            java.util.regex.Matcher match=java.util.regex.Pattern.compile("channel \\d+ \\((\\d+) MHz\\), width: (20|40|80|160|320|80\\+80) MHz").matcher(new String(buffer,0,size,StandardCharsets.UTF_8));
            String result="";
            while(match.find())if(Integer.parseInt(match.group(1))==info.getFrequency()) {
                if(!result.isEmpty()&&!result.equals(match.group(2)))return "";
                result=match.group(2);
            }
            return result;
        } catch(Exception | LinkageError ignored) {return "";}
        finally {if(process!=null&&process.isAlive())process.destroyForcibly();}
    }
    private void publish(JSONObject value) {
        try {
            networkMetadata(value);
            String text=value.toString();
            if(text.equals(last))return;
            File temporary=new File(directory,"wifi.new");
            Files.write(temporary.toPath(),text.getBytes(StandardCharsets.UTF_8));
            android.system.Os.chmod(temporary.getPath(),0600);
            Files.move(temporary.toPath(),new File(directory,"wifi.json").toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
            last=text;
        } catch(Exception ignored) { }
    }
    @SuppressWarnings("deprecation")
    private void update(WifiInfo supplied) {
        JSONObject value=new JSONObject();
        try {
            value.put("available",true).put("connected",false);
            if(wifi==null)throw new IllegalStateException();
            WifiInfo info=supplied;
            if(info==null) {
                try { info=wifi.getConnectionInfo(); } catch(Exception ignored) { }
            }
            boolean connected=false;
            try { android.net.NetworkInfo state=connectivity.getNetworkInfo(ConnectivityManager.TYPE_WIFI);connected=state!=null&&state.isConnected(); } catch(Exception ignored) { }
            if(supplied!=null)connected=true;
            if(!connected||info==null) { publish(value);return; }
            value.put("connected",true);
            String ssid=info.getSSID();
            if(ssid!=null&&!"<unknown ssid>".equals(ssid)) {
                if(ssid.length()>=2&&ssid.startsWith("\"")&&ssid.endsWith("\""))ssid=ssid.substring(1,ssid.length()-1);
                value.put("ssid",ssid.substring(0,Math.min(128,ssid.length())));
            }
            // Negotiated link rate (Mbps), not payload throughput. Refresh only on system events.
            try { int rate=info.getLinkSpeed();if(rate>0)value.put("linkSpeedMbps",rate); } catch(Exception | LinkageError ignored) { }
            int frequency=info.getFrequency(),rssi=info.getRssi();
            if(frequency>0)value.put("frequencyMhz",frequency);
            if(rssi>-127&&rssi<=0)value.put("rssiDbm",rssi);
            if(Build.VERSION.SDK_INT>=30)try { value.put("wifiStandard",info.getWifiStandard()); } catch(Exception ignored) { }
            String linkWidth=driverWidth(info);
            if(!linkWidth.isEmpty())value.put("linkWidthMhz",linkWidth);
            // ScanResult describes the AP's advertised width, not negotiated link speed.
            // Only match the associated BSSID/frequency, never guess by SSID.
            try {
                String bssid=info.getBSSID();
                if(bssid!=null&&!"02:00:00:00:00:00".equals(bssid))for(ScanResult scan:wifi.getScanResults()) {
                    long age=SystemClock.elapsedRealtime()-scan.timestamp/1000;
                    if(bssid.equalsIgnoreCase(scan.BSSID)&&scan.frequency==frequency&&age>=0&&age<=120000) {
                        String bandwidth=width(scan.channelWidth);
                        if(!bandwidth.isEmpty())value.put("widthMhz",bandwidth).put("widthSource","ap");
                        break;
                    }
                }
            } catch(Exception | LinkageError ignored) { }
        } catch(Exception | LinkageError ignored) {
            try { value.put("available",false); } catch(Exception impossible) { }
        }
        publish(value);
    }
    public static void main(String[] args) {
        Context context=null;BroadcastReceiver receiver=null;ConnectivityManager.NetworkCallback callback=null;
        HandlerThread thread=null;WifiConnectionWatch watch=null;
        try {
            if(args.length!=1)throw new IllegalArgumentException();
            File directory=new File(args[0]);
            android.system.StructStat stat=android.system.Os.lstat(directory.getPath());
            if(!directory.isDirectory()||stat.st_uid!=android.os.Process.myUid()||(stat.st_mode&0777)!=0700)throw new IllegalArgumentException();
            Looper.prepareMainLooper();context=HiddenApiHelper.getContext();
            watch=new WifiConnectionWatch(directory,context);
            final WifiConnectionWatch active=watch;
            thread=new HandlerThread("wifi-metadata-events");thread.start();Handler handler=new Handler(thread.getLooper());
            receiver=new BroadcastReceiver(){@Override public void onReceive(Context c,Intent i){active.tetherBroadcast(i);active.refreshFromSystem();}};
            IntentFilter filter=new IntentFilter();
            filter.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION);filter.addAction(WifiManager.WIFI_STATE_CHANGED_ACTION);
            filter.addAction("android.net.conn.TETHER_STATE_CHANGED");filter.addAction("android.net.wifi.WIFI_AP_STATE_CHANGED");
            filter.addAction(WifiManager.RSSI_CHANGED_ACTION);filter.addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
            try {
                if(Build.VERSION.SDK_INT>=33)context.registerReceiver(receiver,filter,null,handler,Context.RECEIVER_EXPORTED);
                else context.registerReceiver(receiver,filter,null,handler);
            } catch(Exception ignored) { receiver=null; }
            active.startTether(context,handler);
            callback=Build.VERSION.SDK_INT>=31?new DetailedCallback(active):new BasicCallback(active);
            try { watch.connectivity.registerNetworkCallback(new NetworkRequest.Builder().clearCapabilities().build(),callback,handler); }
            catch(Exception ignored) { callback=null; }
            handler.post(()->active.update(null));
            // The owning Rust process holds this pipe. EOF terminates even on old kernels.
            System.in.read();
        } catch(Exception | LinkageError ignored) {
            if(watch!=null)watch.publish(new JSONObject());
        } finally {
            if(watch!=null)watch.stopTether();
            if(receiver!=null&&context!=null)try{context.unregisterReceiver(receiver);}catch(Exception ignored){}
            if(callback!=null&&watch!=null)try{watch.connectivity.unregisterNetworkCallback(callback);}catch(Exception ignored){}
            if(thread!=null)thread.quitSafely();
        }
        System.exit(0);
    }
    private static class BasicCallback extends ConnectivityManager.NetworkCallback {
        final WifiConnectionWatch watch;
        BasicCallback(WifiConnectionWatch watch){this.watch=watch;}
        @Override public void onAvailable(Network n){watch.lostNetworks.remove(n);watch.refreshFromSystem();}
        @Override public void onCapabilitiesChanged(Network n,NetworkCapabilities capabilities){watch.lostNetworks.remove(n);watch.update(null);}
        @Override public void onLinkPropertiesChanged(Network n,android.net.LinkProperties properties){watch.refreshFromSystem();}
        @Override public void onLost(Network n){watch.lostNetworks.add(n);watch.update(null);}
    }
    private static final class DetailedCallback extends ConnectivityManager.NetworkCallback {
        final WifiConnectionWatch watch;
        DetailedCallback(WifiConnectionWatch watch){super(FLAG_INCLUDE_LOCATION_INFO);this.watch=watch;}
        @Override public void onAvailable(Network n){watch.lostNetworks.remove(n);watch.refreshFromSystem();}
        @Override public void onCapabilitiesChanged(Network n,NetworkCapabilities capabilities){
            watch.lostNetworks.remove(n);
            Object transport=capabilities.getTransportInfo();
            if(transport instanceof WifiInfo) {
                WifiInfo info=(WifiInfo)transport;
                try { if(Boolean.FALSE.equals(info.getClass().getMethod("isPrimary").invoke(info)))return; } catch(Exception ignored) { }
                watch.primaryNetwork=n;watch.primaryInfo=info;
                watch.update(info);
            } else watch.refreshFromSystem();
        }
        @Override public void onLinkPropertiesChanged(Network n,android.net.LinkProperties properties){watch.refreshFromSystem();}
        @Override public void onLost(Network n){
            watch.lostNetworks.add(n);
            if(n.equals(watch.primaryNetwork)){watch.primaryNetwork=null;watch.primaryInfo=null;}
            watch.refreshFromSystem();
        }
    }
}
