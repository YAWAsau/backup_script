package io.github.yawasau.speedbackup.webview;

import android.content.Intent;
import android.os.*;
import android.net.Uri;
import android.graphics.Color;
import android.view.*;
import org.json.JSONObject;

/** Native renderer and authenticated Rust API client. Root owns all work. */
public final class MainActivity extends androidx.activity.ComponentActivity {
    private static final String PROTOCOL="speedbackup.webview.v1";
    private final Handler main=new Handler(Looper.getMainLooper());
    private volatile IBinder session;
    private IBinder endpoint;
    private IBinder.DeathRecipient death;
    private volatile boolean closing;
    private boolean linked,sessionReady,cancelOnPause,activityResumed;
    private String origin,navigationId,navigationTarget;
    private android.widget.FrameLayout frame;
    private android.widget.TextView transition;
    private NativeChrome nativeChrome;
    private NativeSession controller;
    private long documentGeneration;
    private long modelTicket;
    private final NativeLogCache logCache=new NativeLogCache();
    private final java.util.concurrent.ExecutorService modelWorker=java.util.concurrent.Executors.newSingleThreadExecutor();
    private final java.util.concurrent.atomic.AtomicReference<Runnable> pendingModel=new java.util.concurrent.atomic.AtomicReference<>();
    private final java.util.concurrent.atomic.AtomicBoolean modelWorking=new java.util.concurrent.atomic.AtomicBoolean();
    private JSONObject lastModel;
    private int safeLeft,safeTop,safeRight,safeBottom;
    private void showTransition(Runnable next){if(!closing){nativeChrome.beginNavigation();next.run();}}
    private void loadDocument(String address){
        final long generation=++documentGeneration;
        if(controller!=null)controller.close();
        pendingModel.set(null);lastModel=null;
        if(!nativeChrome.hasContent()){transition.setText("正在開啟…");transition.setVisibility(View.VISIBLE);}
        final NativeSession next=new NativeSession(this,address,new NativeSession.Listener(){
            public void model(JSONObject value){main.post(()->{if(!closing&&generation==documentGeneration){lastModel=value;prepareModel(value,generation);}});}
            public void link(String url){main.post(()->{if(!closing&&generation==documentGeneration)try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(RuntimeException e){showError("無法開啟連結");}});}
            public void terminal(String message){main.post(()->{if(!closing&&generation==documentGeneration){showError(message);if(navigationId!=null){notifyNavigation(navigationId,2);navigationId=null;navigationTarget=null;}}});}
            public void exit(){main.post(()->{if(generation==documentGeneration)close();});}
        });
        controller=next;next.start();next.lifecycle(activityResumed);
    }
    private void showError(String message){transition.setText(message+"\n請保留日誌供檢查；返回可關閉畫面。");transition.setVisibility(View.VISIBLE);android.util.Log.w("SpeedBackupNative","native presentation failed");}
    private void prepareModel(JSONObject source,long generation){
        if(frame.getWidth()==0){return;}
        final android.util.DisplayMetrics metrics=new android.util.DisplayMetrics();metrics.setTo(getResources().getDisplayMetrics());
        final int width=frame.getWidth()-safeLeft-safeRight;
        final long ticket=++modelTicket;
        final int top=safeTop,bottom=safeBottom,left=safeLeft,right=safeRight;
        pendingModel.set(()->{
            try{
                JSONObject value=new JSONObject(source.toString());value.put("safeTop",top/metrics.density).put("safeBottom",bottom/metrics.density).put("safeLeft",left/metrics.density).put("safeRight",right/metrics.density).put("bottom",20+bottom/metrics.density);
                NativeChrome.Prepared prepared=NativeChrome.prepare(value,width,metrics.density,14f*(float)value.optDouble("scale",1)*metrics.scaledDensity,logCache);
                main.post(()->{if(!closing&&generation==documentGeneration&&ticket==modelTicket){nativeChrome.applyPrepared(prepared);applyBars((int)prepared.getData().optLong("background",0xff000000L));transition.setVisibility(View.GONE);if(navigationId!=null){notifyNavigation(navigationId,1);navigationId=null;navigationTarget=null;}}});
            }catch(Exception e){main.post(()->{if(!closing&&generation==documentGeneration)showError("介面資料驗證失敗："+e.getClass().getSimpleName());});}
        });
        drainModels();
    }
    private void drainModels(){
        if(closing||!modelWorking.compareAndSet(false,true))return;
        try{modelWorker.execute(()->{try{Runnable next;while((next=pendingModel.getAndSet(null))!=null)next.run();}finally{modelWorking.set(false);if(pendingModel.get()!=null)drainModels();}});}catch(java.util.concurrent.RejectedExecutionException ignored){modelWorking.set(false);}
    }
    private void applyBars(int color){
        getWindow().setStatusBarColor(Color.TRANSPARENT);getWindow().setNavigationBarColor(Color.TRANSPARENT);getWindow().setNavigationBarDividerColor(Color.TRANSPARENT);
        if(Build.VERSION.SDK_INT>=29){getWindow().setStatusBarContrastEnforced(false);getWindow().setNavigationBarContrastEnforced(false);}
        boolean light=Color.red(color)*299+Color.green(color)*587+Color.blue(color)*114>=128000;
        if(Build.VERSION.SDK_INT>=30){WindowInsetsController bars=getWindow().getInsetsController();if(bars!=null){int mask=WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;bars.setSystemBarsAppearance(light?mask:0,mask);}}
        else getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION|(light?View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR:0));
    }
    private Intent permissionLaunch;
    private boolean permissionAnswered;
    private void bindAfterPermission(Intent intent)throws Exception {
        if(permissionLaunch!=null){permissionLaunch=intent;return;}
        if(session==null&&WorkGuardService.valid(intent.getStringExtra("consoleUrl"))&&Build.VERSION.SDK_INT>=33&&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED&&
            !getPreferences(0).getBoolean("notificationAsked",false)){
            // Complete setup BEFORE session bind/READY. No live navigation or cancel-on-pause yet.
            permissionLaunch=intent;permissionAnswered=false;
            getPreferences(0).edit().putBoolean("notificationAsked",true).apply();
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},1048);return;
        }
        bind(intent);
    }
    private void finishPermissionSetup(){
        if(!activityResumed||!permissionAnswered||permissionLaunch==null)return;
        Intent launch=permissionLaunch;permissionLaunch=null;permissionAnswered=false;
        if(checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)
            android.widget.Toast.makeText(this,"通知未開啟；可在系統應用設定啟用工作接回通知",android.widget.Toast.LENGTH_LONG).show();
        try{bind(launch);}catch(Exception e){close();}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){
        super.onRequestPermissionsResult(request,permissions,results);
        if(request==1048){permissionAnswered=true;main.post(this::finishPermissionSetup);}
    }
    private void bind(Intent intent) throws Exception {
        String url=intent.getDataString();if(url==null)throw new IllegalArgumentException("missing session address");Uri uri=Uri.parse(url);
        if(!"http".equals(uri.getScheme())||!"127.0.0.1".equals(uri.getHost())||uri.getPort()<1||uri.getUserInfo()!=null||!"/".equals(uri.getPath())||uri.getQuery()!=null||uri.getFragment()==null||!uri.getFragment().matches("[0-9a-f]{64}"))throw new IllegalArgumentException();
        Bundle launchExtras=intent.getExtras();final IBinder next=launchExtras==null?null:launchExtras.getBinder("session");if(next==null)throw new IllegalArgumentException();
        // A death callback may have retired this Activity while it was cached/frozen.
        // Never acknowledge a new session on an Activity already scheduled for removal.
        if(closing||isFinishing()||isDestroyed()){
            if(intent.getBooleanExtra("closingRetry",false))throw new IllegalStateException("closing retry exhausted");
            Intent fresh=new Intent(intent).setComponent(getComponentName());
            fresh.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK);
            fresh.putExtra("closingRetry",true);
            android.util.Log.i("SpeedBackupNative","Recreate retiring Activity before session bind");
            // A still-live predecessor must not restore the terminal over the successor.
            notifySession(4);
            startActivity(fresh);
            return;
        }

        if(nativeChrome!=null)nativeChrome.resetNavigationHistory();
        if(navigationId!=null){notifyNavigation(navigationId,2);navigationId=null;navigationTarget=null;}
        IBinder.DeathRecipient nextDeath=()->main.post(()->{if(session==next)close();});
        next.linkToDeath(nextDeath,0);
        // Tell the old controller it was replaced before releasing its death link.
        if(session!=null){
            Parcel replaced=Parcel.obtain();
            try{replaced.writeInterfaceToken(PROTOCOL);session.transact(4,replaced,null,IBinder.FLAG_ONEWAY);}catch(RemoteException ignored){}finally{replaced.recycle();}
        }
        try{if(session!=null&&linked)session.unlinkToDeath(death,0);}catch(Exception ignored){}
        cancelOnPause=intent.getBooleanExtra("cancelOnPause",false);
        String consoleUrl=intent.getStringExtra("consoleUrl");
        if(WorkGuardService.valid(consoleUrl)){
            HostLifeline.connect(intent.getStringExtra("guardSocket"));
            try{startForegroundService(new Intent(this,WorkGuardService.class).putExtra(WorkGuardService.KEY,consoleUrl).putExtra("guardSocket",intent.getStringExtra("guardSocket")));}
            catch(RuntimeException unavailable){android.util.Log.w("SpeedBackupGuard","Foreground protection unavailable: "+unavailable.getClass().getSimpleName());}

        }
        session=next;death=nextDeath;linked=true;sessionReady=false;navigationTarget=null;navigationId=null;origin="http://127.0.0.1:"+uri.getPort();
        endpoint=new Binder(){
            @Override protected boolean onTransact(int code,Parcel data,Parcel reply,int flags)throws RemoteException {
                if(Binder.getCallingUid()!=0)return false;
                data.enforceInterface(PROTOCOL);
                if(code==4){
                    // Binder worker, never the UI thread. Only the root session owns this endpoint.
                    if(reply==null||session!=next||closing)return false;
                    android.content.pm.ApplicationInfo app=data.readInt()==1?android.content.pm.ApplicationInfo.CREATOR.createFromParcel(data):null;
                    byte[] png=null;
                    if(app!=null)png=applicationIcon(app);
                    if(session!=next||closing)png=null;
                    reply.writeNoException();reply.writeByteArray(png);return true;
                }
                if(code==5){
                    final String id=data.readString(),target=data.readString();
                    if(id==null||!id.matches("[0-9a-f]{64}"))return false;
                    final Uri targetUri=Uri.parse(target==null?"":target);
                    if(!"http".equals(targetUri.getScheme())||!"127.0.0.1".equals(targetUri.getHost())||targetUri.getPort()<1||targetUri.getUserInfo()!=null||!"/".equals(targetUri.getPath())||targetUri.getQuery()!=null||targetUri.getFragment()==null||!targetUri.getFragment().matches("[0-9a-f]{64}"))return false;
                    main.post(()->{
                        if(session!=next)return;
                        if(closing||isFinishing()||isDestroyed()||!activityResumed){notifyNavigation(id,2);return;}
                        if(navigationId!=null){notifyNavigation(id,2);return;}
                        navigationId=id;navigationTarget=target;origin="http://127.0.0.1:"+targetUri.getPort();
                        showTransition(()->loadDocument(target));
                    });return true;
                }
                if(code<1||code>3)return false;
                main.post(()->{
                    // A late close from the preceding controller must not close this page.
                    if(session!=next)return;
                    if(code==1){close();return;}
                    showTransition(()->{if(code==3){moveTaskToBack(true);}notifySession(5);});
                });return true;
            }
        };
        showTransition(()->{loadDocument(url);if(hasWindowFocus())notifySession(1);});
    }
    private byte[] applicationIcon(android.content.pm.ApplicationInfo app){
        android.graphics.Bitmap bitmap=null;
        try{
            // ApplicationInfo comes from root's exact target-user query. Never fall back
            // to the foreground user's package lookup for a missing profile package.
            android.graphics.drawable.Drawable icon=getApplicationContext().getPackageManager().getApplicationIcon(app);
            if(icon==null)return null;
            for(int size:new int[]{128,64}){
                bitmap=android.graphics.Bitmap.createBitmap(size,size,android.graphics.Bitmap.Config.ARGB_8888);
                icon.setBounds(0,0,size,size);icon.draw(new android.graphics.Canvas(bitmap));
                java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();
                if(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,bytes)&&bytes.size()<=32768)return bytes.toByteArray();
                bitmap.recycle();bitmap=null;
            }
        }catch(Throwable e){android.util.Log.w("SpeedBackupIcons","APK icon unavailable: "+e.getClass().getSimpleName());}
        finally{if(bitmap!=null)bitmap.recycle();}
        return null;
    }
    private boolean resumePending;
    private static boolean isResumeIntent(Intent intent){
        return intent!=null&&"io.github.yawasau.speedbackup.RESUME".equals(intent.getAction());
    }
    private static boolean needsRootResume(Intent intent){
        if(isResumeIntent(intent)||intent==null)return true;
        // Android can recreate a task/notification Intent after an APK update
        // without its transient Binder. Recover through the authenticated root
        // rendezvous; never launch work or trust a URI as a Binder replacement.
        Bundle extras=intent.getExtras();
        IBinder binder=extras==null?null:extras.getBinder("session");
        return binder==null||!binder.isBinderAlive();
    }
    private void prepareResume(){
        // User notification clicks enter the normal UI process first. Some task
        // managers reject a cold start directly into the guardian process.
        // Keep this Activity alive until root binds the existing work; removing
        // its task here would trigger swipe-to-clean policies again.
        if(session!=null)return;
        resumePending=true;resumeStarted=false;main.removeCallbacks(resumeTimeout);
        if(transition!=null)transition.setText("正在接回目前工作…");
        if(hasWindowFocus())launchResume();
    }
    private final Runnable resumeTimeout=()->{
        if(resumePending&&session==null&&!isFinishing()){
            resumePending=false;
            android.widget.Toast.makeText(this,"目前工作無法接回，請重新執行 start.sh",android.widget.Toast.LENGTH_LONG).show();close();
        }
    };
    private boolean resumeStarted;
    private void launchResume(){
        if(!resumePending||resumeStarted||closing)return;
        resumeStarted=true;main.removeCallbacks(resumeTimeout);main.postDelayed(resumeTimeout,25000);
        try{startActivity(new Intent(this,ResumeActivity.class));}
        catch(RuntimeException e){resumePending=false;close();}
    }
    @Override protected void onNewIntent(Intent intent){
        super.onNewIntent(intent);setIntent(intent);
        if(needsRootResume(intent)){prepareResume();return;}
        resumePending=false;resumeStarted=false;main.removeCallbacks(resumeTimeout);
        try{bindAfterPermission(intent);}catch(Exception e){android.util.Log.e("SpeedBackupNative","Session bind failed: "+e.getClass().getSimpleName());close();}
    }
    private void notifyNavigation(String id,int accepted){
        if(session==null)return;Parcel p=Parcel.obtain();
        try{p.writeInterfaceToken(PROTOCOL);p.writeString(id);p.writeInt(accepted);session.transact(6,p,null,IBinder.FLAG_ONEWAY);}
        catch(RemoteException e){close();}finally{p.recycle();}
    }
    @Override public void onWindowFocusChanged(boolean focused){
        super.onWindowFocusChanged(focused);if(focused)launchResume();if(focused&&session!=null&&endpoint!=null&&!closing)notifySession(1);
    }
    private void notifySession(int code) {
        if(session==null||(code==1&&sessionReady))return;
        Parcel p=Parcel.obtain();
        try {p.writeInterfaceToken(PROTOCOL);if(code==1)p.writeStrongBinder(endpoint);session.transact(code,p,null,IBinder.FLAG_ONEWAY);if(code==1)sessionReady=true;}
        catch(RemoteException e){close();}finally{p.recycle();}
    }

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        if(Build.VERSION.SDK_INT>=30)getWindow().setDecorFitsSystemWindows(false);
        frame=new android.widget.FrameLayout(this);
        nativeChrome=new NativeChrome(this,(id,epoch)->{if(controller!=null)controller.dispatch(id,epoch);});
        frame.addView(nativeChrome.getView(),new android.widget.FrameLayout.LayoutParams(-1,-1));
        transition=new android.widget.TextView(this);transition.setText("正在開啟…");transition.setGravity(Gravity.CENTER);transition.setTextSize(18);transition.setPadding(24,24,24,24);transition.setClickable(true);
        boolean dark=(getResources().getConfiguration().uiMode&android.content.res.Configuration.UI_MODE_NIGHT_MASK)==android.content.res.Configuration.UI_MODE_NIGHT_YES;
        transition.setTextColor(dark?Color.WHITE:Color.BLACK);transition.setBackgroundColor(dark?Color.BLACK:Color.rgb(247,247,247));
        frame.addView(transition,new android.widget.FrameLayout.LayoutParams(-1,-1));setContentView(frame);applyBars(dark?Color.BLACK:Color.WHITE);
        frame.setOnApplyWindowInsetsListener((v,insets)->{
            int keyboard=0;
            if(Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());keyboard=insets.getInsets(WindowInsets.Type.ime()).bottom;safeLeft=safe.left;safeTop=safe.top;safeRight=safe.right;safeBottom=keyboard>0?0:safe.bottom;}
            else{int bottom=insets.getSystemWindowInsetBottom();if(bottom>insets.getStableInsetBottom()+80*getResources().getDisplayMetrics().density)keyboard=bottom;safeLeft=insets.getSystemWindowInsetLeft();safeRight=insets.getSystemWindowInsetRight();safeTop=insets.getSystemWindowInsetTop();safeBottom=keyboard>0?0:bottom;}
            // Compose follows animated IME insets on API 30+; avoid snapping the entire
            // root (including wallpaper) to the final keyboard height before the animation.
            v.setPadding(0,0,0,Build.VERSION.SDK_INT>=30?0:keyboard);if(lastModel!=null)prepareModel(lastModel,documentGeneration);return insets;
        });
        frame.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{if((r-l!=or-ol||b-t!=ob-ot)&&lastModel!=null)prepareModel(lastModel,documentGeneration);});
        if(Build.VERSION.SDK_INT>=33)getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,this::back);
        try{if(needsRootResume(getIntent()))prepareResume();else bindAfterPermission(getIntent());}catch(Exception e){showError("無法接回工作："+e.getClass().getSimpleName());}
    }
    @Override public void onConfigurationChanged(android.content.res.Configuration configuration){super.onConfigurationChanged(configuration);frame.requestApplyInsets();if(controller!=null)controller.refresh();}
    @Override public void onBackPressed(){back();}
    private void back(){if(closing)return;if(transition.getVisibility()==View.VISIBLE||controller==null){close();return;}controller.dispatch("back",controller.getEpoch());}
    @Override protected void onResume(){super.onResume();activityResumed=true;main.post(this::finishPermissionSetup);if(controller!=null)controller.lifecycle(true);}
    @Override protected void onPause(){activityResumed=false;if(controller!=null)controller.lifecycle(false);super.onPause();if(cancelOnPause&&!closing)close();}
    private void close(){if(closing)return;closing=true;finishAndRemoveTask();}
    @Override protected void onDestroy(){closing=true;++documentGeneration;if(controller!=null)controller.close();pendingModel.set(null);modelWorker.shutdownNow();main.removeCallbacksAndMessages(null);notifySession(2);if(session!=null&&linked)try{session.unlinkToDeath(death,0);}catch(Exception ignored){}super.onDestroy();}
}
