package com.xayah.dex;

import android.content.ComponentName;
import android.content.Context;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.system.Os;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Daemon playback callbacks. Hot decisions read a snapshot, never run shell/JVM. */
final class AudioPlaybackGuard {
    enum State { PLAYING, IDLE, UNKNOWN }
    private static final Map<Integer,Watch> watches=new HashMap<>();
    private static final java.util.regex.Pattern PACKAGE=java.util.regex.Pattern.compile("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+");
    private static String error(Throwable e) {
        while(e.getCause()!=null && e.getCause()!=e) e=e.getCause();
        return e.getClass().getSimpleName()+":"+String.valueOf(e.getMessage()).replaceAll("[\\r\\n\\t ]","_");
    }
    private static final class Snapshot {
        final boolean ready; final Set<String> playing;
        Snapshot(boolean ready,Set<String> playing) { this.ready=ready; this.playing=new HashSet<>(playing); }
    }
    private static synchronized Watch watch(int user) throws Exception {
        if(user<0) throw new IllegalArgumentException("user");
        Watch w=watches.get(user);
        if(w==null) { w=new Watch(user); watches.put(user,w); w.start(); }
        return w;
    }
    static State state(int user,String pkg) {
        if(pkg==null || !PACKAGE.matcher(pkg).matches()) return State.UNKNOWN;
        try { Snapshot s=watch(user).snapshot; return !s.ready?State.UNKNOWN:s.playing.contains(pkg)?State.PLAYING:State.IDLE; }
        catch(Throwable e) { return State.UNKNOWN; }
    }
    static boolean blocks(int user,String pkg) { return state(user,pkg)==State.PLAYING; }
    static String status(int user,String pkg) { return "AUDIO_PLAYBACK "+state(user,pkg).name().toLowerCase(Locale.ROOT)+"\n"; }
    static String start(int user,String path) {
        try {
            File f=new File(path).getAbsoluteFile(),parent=f.getParentFile();
            if(parent==null || !parent.isDirectory() || !f.getCanonicalPath().equals(f.getPath())) throw new IllegalArgumentException("path");
            android.system.StructStat st=Os.stat(parent.getPath());
            if(st.st_uid!=0 || (st.st_mode & 0022)!=0) throw new IllegalArgumentException("private directory required");
            Watch w=watch(user);
            synchronized(w) { w.file=f; w.lastWritten=""; w.publish(); }
            return "AUDIO_PLAYBACK_WATCH "+(w.snapshot.ready?"ready":"unknown")+" audio="+w.audioOk+" media="+w.mediaOk+" audioError="+w.audioError+" mediaError="+w.mediaError+"\n";
        } catch(Throwable e) { return "AUDIO_PLAYBACK_WATCH unknown reason="+error(e)+"\n"; }
    }
    private static final class Watch {
        final int user; final Context context; final AudioManager audio; final MediaSessionManager media;
        final HandlerThread thread=new HandlerThread("speedbackup-audio"); final Handler handler;
        final Map<MediaController,MediaController.Callback> controllers=new HashMap<>();
        final Map<MediaController,Boolean> sessionPlaying=new HashMap<>();
        Set<String> audioPlaying=new HashSet<>(); boolean audioOk,mediaOk;
        String audioError="-",mediaError="-";
        volatile Snapshot snapshot=new Snapshot(false,new HashSet<>());
        File file; String lastWritten="";
        final AudioManager.AudioPlaybackCallback audioListener=new AudioManager.AudioPlaybackCallback() {
            @Override public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) { updateAudio(configs); }
        };
        final MediaSessionManager.OnActiveSessionsChangedListener mediaListener=this::updateSessions;
        Watch(int user) throws Exception {
            this.user=user; context=HiddenApiHelper.getContext();
            // app_process does not run Zygote's media framework initialization.
            // This initializes only the service accessor in our own process.
            try {
                Class<?> init=Class.forName("android.media.MediaFrameworkPlatformInitializer");
                if(init.getMethod("getMediaServiceManager").invoke(null)==null) {
                    Class<?> manager=Class.forName("android.media.MediaServiceManager");
                    init.getMethod("setMediaServiceManager",manager).invoke(null,manager.getDeclaredConstructor().newInstance());
                }
            } catch(ClassNotFoundException ignored) { /* pre-mainline framework */ }
            audio=(AudioManager)context.getSystemService(Context.AUDIO_SERVICE);
            media=(MediaSessionManager)context.getSystemService(Context.MEDIA_SESSION_SERVICE);
            thread.start(); handler=new Handler(thread.getLooper());
        }
        synchronized void start() {
            // Register before reading initial state; callbacks serialize on this monitor.
            try {
                audio.registerAudioPlaybackCallback(audioListener,handler);
                updateAudio(audio.getActivePlaybackConfigurations());
                binder("audio").linkToDeath(() -> { synchronized(Watch.this) { audioOk=false; publish(); } },0);
            } catch(Throwable e) { audioOk=false; audioError=error(e); }
            try {
                try {
                    MediaSessionManager.class.getMethod("addOnActiveSessionsChangedListener",MediaSessionManager.OnActiveSessionsChangedListener.class,ComponentName.class,int.class,Handler.class)
                            .invoke(media,mediaListener,null,user,handler);
                } catch(NoSuchMethodException newerFramework) {
                    Object handle=android.os.UserHandle.class.getMethod("of",int.class).invoke(null,user);
                    java.util.concurrent.Executor executor=task -> handler.post(task);
                    MediaSessionManager.class.getMethod("addOnActiveSessionsChangedListener",ComponentName.class,android.os.UserHandle.class,java.util.concurrent.Executor.class,MediaSessionManager.OnActiveSessionsChangedListener.class)
                            .invoke(media,null,handle,executor,mediaListener);
                }
                Object result;
                try {
                    result=MediaSessionManager.class.getMethod("getActiveSessionsForUser",ComponentName.class,int.class).invoke(media,null,user);
                } catch(NoSuchMethodException newerFramework) {
                    Object handle=android.os.UserHandle.class.getMethod("of",int.class).invoke(null,user);
                    result=MediaSessionManager.class.getMethod("getActiveSessionsForUser",ComponentName.class,android.os.UserHandle.class).invoke(media,null,handle);
                }
                List<MediaController> list=new ArrayList<>();
                for(Object controller:(List<?>)result) list.add((MediaController)controller);
                updateSessions(list);
                binder("media_session").linkToDeath(() -> { synchronized(Watch.this) { mediaOk=false; publish(); } },0);
            } catch(Throwable e) { mediaOk=false; mediaError=error(e); }
            publish();
        }
        IBinder binder(String name) throws Exception {
            return (IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,name);
        }
        synchronized void updateAudio(List<AudioPlaybackConfiguration> configs) {
            Set<String> next=new HashSet<>();
            try {
                Method uidMethod=AudioPlaybackConfiguration.class.getDeclaredMethod("getClientUid");
                Method stateMethod=AudioPlaybackConfiguration.class.getDeclaredMethod("getPlayerState");
                uidMethod.setAccessible(true); stateMethod.setAccessible(true);
                for(AudioPlaybackConfiguration config:configs) {
                    int uid=(Integer)uidMethod.invoke(config);
                    if(uid<0) throw new IllegalStateException("anonymized playback");
                    // PLAYER_STATE_STARTED=2: protect playback even when muted by volume/app-ops.
                    if(uid/100000!=user || ((Integer)stateMethod.invoke(config))!=2) continue;
                    String[] packages=context.getPackageManager().getPackagesForUid(uid);
                    if(packages==null) throw new IllegalStateException("unknown active uid");
                    Collections.addAll(next,packages);
                }
                audioPlaying=next; audioOk=true; audioError="-";
            } catch(Throwable e) { audioOk=false; audioError=error(e); }
            publish();
        }
        synchronized void updateSessions(List<MediaController> list) {
            for(Map.Entry<MediaController,MediaController.Callback> e:controllers.entrySet()) {
                try { e.getKey().unregisterCallback(e.getValue()); } catch(Throwable ignored) { }
            }
            controllers.clear(); sessionPlaying.clear();
            try {
                if(list==null) throw new IllegalStateException("sessions unavailable");
                for(MediaController c:list) {
                    MediaController.Callback cb=new MediaController.Callback() {
                        @Override public void onPlaybackStateChanged(PlaybackState state) {
                            synchronized(Watch.this) {
                                if(!controllers.containsKey(c)) return;
                                sessionPlaying.put(c,playing(state)); publish();
                            }
                        }
                        @Override public void onSessionDestroyed() {
                            synchronized(Watch.this) { controllers.remove(c); sessionPlaying.remove(c); publish(); }
                        }
                    };
                    controllers.put(c,cb); c.registerCallback(cb,handler);
                    sessionPlaying.put(c,playing(c.getPlaybackState()));
                }
                mediaOk=true; mediaError="-";
            } catch(Throwable e) { mediaOk=false; mediaError=error(e); }
            publish();
        }
        boolean playing(PlaybackState s) { return s!=null && s.getState()==PlaybackState.STATE_PLAYING; }
        synchronized void publish() {
            Set<String> playing=new HashSet<>(audioPlaying);
            for(Map.Entry<MediaController,Boolean> e:sessionPlaying.entrySet()) if(e.getValue()) playing.add(e.getKey().getPackageName());
            snapshot=new Snapshot(audioOk && mediaOk,playing);
            if(file==null || !file.getParentFile().isDirectory()) return;
            List<String> sorted=new ArrayList<>(playing); Collections.sort(sorted);
            StringBuilder b=new StringBuilder("AUDIO_PLAYBACK_V1 ").append(android.os.Process.myPid()).append(' ').append(user).append(' ').append(snapshot.ready?"ready":"unknown").append('\n');
            for(String pkg:sorted) b.append(pkg).append('\n');
            String text=b.toString(); if(text.equals(lastWritten)) return;
            File tmp=new File(file.getPath()+".new");
            try {
                try(FileOutputStream stream=new FileOutputStream(tmp)) { Os.chmod(tmp.getPath(),0600); stream.write(text.getBytes(StandardCharsets.UTF_8)); }
                Os.rename(tmp.getPath(),file.getPath()); lastWritten=text;
            } catch(Throwable e) { snapshot=new Snapshot(false,playing); lastWritten=""; file.delete(); tmp.delete(); }
        }
    }
}
