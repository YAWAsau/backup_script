package io.github.yawasau.speedbackup.webview;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;

/** One idle socket per process. Kernel EOF signals process death without heartbeat traffic. */
final class HostLifeline {
    private static LocalSocket socket;
    private static String name;
    static synchronized void connect(String next) {
        if(next==null||!next.matches("sb-web-origin-[0-9]+-[0-9]+-[0-9]+")||next.equals(name))return;
        final LocalSocket previous=socket;
        final LocalSocket current=new LocalSocket();socket=current;name=next;
        new Thread(()->{
            try {
                if(previous!=null)previous.close();
                current.connect(new LocalSocketAddress(next,LocalSocketAddress.Namespace.ABSTRACT));
                // No payload, token or heartbeat. Root checks peer UID and process identity.
                if(current.getInputStream().read()!=1)throw new java.io.IOException("not accepted");
                android.util.Log.i("SpeedBackupGuard","Death-event connection established");
                current.getInputStream().read();
            }catch(Exception unavailable){android.util.Log.w("SpeedBackupGuard","Death-event fallback: "+unavailable.getClass().getSimpleName());}
            finally {try{current.close();}catch(Exception ignored){} synchronized(HostLifeline.class){if(socket==current){socket=null;name=null;}}}
        },"host-lifeline").start();
    }
}
