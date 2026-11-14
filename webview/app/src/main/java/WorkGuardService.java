package io.github.yawasau.speedbackup.webview;

import android.app.*;
import android.graphics.*;
import android.graphics.drawable.Icon;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.os.*;
import android.net.Uri;
import org.json.JSONObject;
import java.net.*;

/** Separate from the UI process; owns no worker and never starts backup commands. */
public final class WorkGuardService extends Service {
    static final String PREFS="active-work",KEY="console";
    static final int ID=1048;
    static final String CHANNEL="active-work";
    private final Handler main=new Handler(Looper.getMainLooper());
    private final java.util.concurrent.ExecutorService worker=java.util.concurrent.Executors.newSingleThreadExecutor();
    private String url="";private int failures=0;private boolean gone=false,detached=false;private long generation;
    static boolean valid(String value){
        if(value==null)return false;
        try{Uri u=Uri.parse(value);return "http".equals(u.getScheme())&&"127.0.0.1".equals(u.getHost())&&u.getPort()>0&&u.getPort()<=65535&&u.getUserInfo()==null&&"/".equals(u.getPath())&&u.getQuery()==null&&u.getFragment()!=null&&u.getFragment().matches("[0-9a-f]{64}");}catch(Exception e){return false;}
    }
    static String request(String url,String endpoint,boolean post)throws Exception{
        return request(url,endpoint,post,"");
    }
    static String request(String url,String endpoint,boolean post,String body)throws Exception{
        if(!valid(url))throw new IllegalArgumentException("session");Uri u=Uri.parse(url);
        HttpURLConnection c=(HttpURLConnection)new URL("http://127.0.0.1:"+u.getPort()+"/api/"+endpoint).openConnection();
        c.setConnectTimeout(2000);c.setReadTimeout(endpoint.equals("guard-wait")?15000:5000);c.setInstanceFollowRedirects(false);c.setRequestProperty("X-SpeedBackup-Token",u.getFragment());
        if(post){byte[] bytes=body.getBytes(java.nio.charset.StandardCharsets.UTF_8);c.setRequestMethod("POST");c.setDoOutput(true);c.setFixedLengthStreamingMode(bytes.length);try(java.io.OutputStream out=c.getOutputStream()){out.write(bytes);}}
        try{if(c.getResponseCode()!=200)throw new java.io.IOException("status "+c.getResponseCode());
            try(java.io.InputStream in=c.getInputStream()){byte[] b=new byte[2049];int count=0,n;while(count<b.length&&(n=in.read(b,count,b.length-count))!=-1)count+=n;if(count>2048)throw new java.io.IOException("length");return new String(b,0,count,java.nio.charset.StandardCharsets.UTF_8);}
        }finally{c.disconnect();}
    }
    @Override public void onCreate(){super.onCreate();}
    private void updateChannel(){getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel(CHANNEL,NativeLanguage.text(this,"工作保護與接回"),NotificationManager.IMPORTANCE_LOW));}
    private Icon notificationIcon;
    private static Bitmap drawSpeedBackupSmallIconBitmap() {
        final int size = 96;
        final Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bitmap);
        canvas.scale(size / 48.0f, size / 48.0f);

        final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        stroke.setColor(Color.WHITE);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeJoin(Paint.Join.ROUND);
        stroke.setStrokeWidth(3.4f);

        final Path lid = new Path();
        lid.moveTo(10.5f, 17.0f);
        lid.lineTo(14.6f, 9.6f);
        lid.lineTo(33.4f, 9.6f);
        lid.lineTo(37.5f, 17.0f);
        canvas.drawPath(lid, stroke);

        final RectF body = new RectF(10.5f, 17.0f, 37.5f, 36.5f);
        canvas.drawRoundRect(body, 3.2f, 3.2f, stroke);
        canvas.drawLine(11.2f, 17.0f, 36.8f, 17.0f, stroke);

        stroke.setStrokeWidth(4.2f);
        final Path check = new Path();
        check.moveTo(18.3f, 25.8f);
        check.lineTo(23.0f, 30.5f);
        check.lineTo(30.6f, 22.0f);
        canvas.drawPath(check, stroke);
        return bitmap;
    }

    private Notification notification(){
        if(notificationIcon==null)notificationIcon=Icon.createWithBitmap(drawSpeedBackupSmallIconBitmap());
        Intent open=new Intent(this,MainActivity.class).setAction("io.github.yawasau.speedbackup.RESUME").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent tap=PendingIntent.getActivity(this,ID,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this,CHANNEL).setSmallIcon(notificationIcon).setColor(0xff3975f6).setContentTitle(NativeLanguage.text(this,"SpeedBackup 工作進行中"))
            .setContentText(NativeLanguage.text(this,detached?"我的進程鼠掉了，點此接回目前工作":"點此開啟目前工作；關閉畫面不會停止作業"))
            .setContentIntent(tap).setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE).build();
    }
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        String next=intent==null?getSharedPreferences(PREFS,0).getString(KEY,""):intent.getStringExtra(KEY);
        if(!valid(next)){stopSelf();return START_NOT_STICKY;}
        String language=intent==null?null:intent.getStringExtra("uiLanguage");
        if(language==null)language=getSharedPreferences(PREFS,0).getString("uiLanguage","zh-Hant");
        NativeLanguage.set(language);getSharedPreferences(PREFS,0).edit().putString("uiLanguage",NativeLanguage.get()).commit();updateChannel();
        String socket=intent==null?getSharedPreferences(PREFS,0).getString("guardSocket",null):intent.getStringExtra("guardSocket");
        HostLifeline.connect(socket);getSharedPreferences(PREFS,0).edit().putString("guardSocket",socket).apply();
        // Save capability only in this private process's preferences, never in a notification or log.
        url=next;getSharedPreferences(PREFS,0).edit().putString(KEY,url).commit();failures=0;gone=false;long ticket=++generation;
        try{if(Build.VERSION.SDK_INT>=34)startForeground(ID,notification(),ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);else startForeground(ID,notification());}
        catch(RuntimeException unavailable){stopSelf();return START_NOT_STICKY;}
        main.removeCallbacksAndMessages(null);poll(ticket,false);return START_STICKY;
    }
    private void poll(long ticket,boolean eventDriven){
        if(gone||ticket!=generation)return;HostLifeline.connect(getSharedPreferences(PREFS,0).getString("guardSocket",null));String current=url;
        final String expected=detached?"0":"1";
        worker.execute(()->{JSONObject status=null;try{status=new JSONObject(request(current,eventDriven?"guard-wait":"guard",eventDriven,expected));}catch(Exception ignored){}final JSONObject result=status;
            main.post(()->{if(gone||ticket!=generation)return;
                if(result==null){if(++failures>=3){end();return;}}
                else{failures=0;if(!result.optBoolean("active",false)){end();return;}boolean next=!result.optBoolean("attached",false);if(next!=detached){detached=next;getSystemService(NotificationManager.class).notify(ID,notification());}}
                boolean events=result!=null&&result.optBoolean("eventDriven",false);
                if(events)poll(ticket,true);
                else main.postDelayed(()->poll(ticket,false),5000); // Legacy backend / failure recovery.
            });});
    }
    private void end(){gone=true;++generation;getSharedPreferences(PREFS,0).edit().remove(KEY).commit();stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();}
    @Override public void onTaskRemoved(Intent root){detached=true;getSystemService(NotificationManager.class).notify(ID,notification());super.onTaskRemoved(root);}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){gone=true;++generation;main.removeCallbacksAndMessages(null);worker.shutdownNow();super.onDestroy();}
}
