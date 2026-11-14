package io.github.yawasau.speedbackup.webview;

import android.content.*;
import android.content.pm.*;
import android.graphics.drawable.Icon;
import java.nio.charset.StandardCharsets;

/** Private entry registry. Exported launcher accepts an opaque ID, never a command/path. */
public final class EntryShortcuts {
    static final String PREFS="entry_shortcuts_v1";
    static boolean validPath(String path){return path!=null&&path.startsWith("/")&&path.endsWith("/start.sh")&&path.indexOf('\n')<0&&path.indexOf('\r')<0&&path.indexOf('\0')<0;}
    static String remember(Context context,Intent intent){
        String backend=intent.getStringExtra("shortcutBackend");
        if(backend!=null&&backend.startsWith("/data/")&&backend.endsWith("/speednative")&&!backend.contains("\n")&&!backend.contains("\r"))context.getSharedPreferences(PREFS,0).edit().putString("backend",backend).commit();
        String path=intent.getStringExtra("shortcutEntry"),mode=intent.getStringExtra("shortcutMode");
        return remember(context,path,mode,false);
    }
    static String remember(Context context,String path,String mode,boolean pending){
        if(!validPath(path)||!("0".equals(mode)||"2".equals(mode)))return null;
        try{
            byte[] hash=java.security.MessageDigest.getInstance("SHA-256").digest((mode+"\n"+path).getBytes(StandardCharsets.UTF_8));
            StringBuilder key=new StringBuilder("entry-");for(byte b:hash)key.append(String.format(java.util.Locale.ROOT,"%02x",b&255));String id=key.toString();
            // A repaired shortcut keeps its original desktop identity after the next launch.
            SharedPreferences prefs=context.getSharedPreferences(PREFS,0);
            for(String name:prefs.getAll().keySet())if(name.matches("entry-[0-9a-f]{64}\\.path")){
                String old=name.substring(0,name.length()-5);
                if(path.equals(prefs.getString(name,null))&&mode.equals(prefs.getString(old+".mode",null))){id=old;break;}
            }
            // MainActivity is DUMP-protected; only an authenticated root launch registers entries.
            SharedPreferences.Editor edit=context.getSharedPreferences(PREFS,0).edit().putString(id+".path",path).putString(id+".mode",mode);
            if(pending)edit.putBoolean(id+".pending",true);
            if(!edit.commit())return null;return id;
        }catch(Exception unavailable){return null;}
    }
    public static String path(Context c,String id){return id!=null&&id.matches("entry-[0-9a-f]{64}")?c.getSharedPreferences(PREFS,0).getString(id+".path",null):null;}
    static String mode(Context c,String id){return path(c,id)!=null?c.getSharedPreferences(PREFS,0).getString(id+".mode",""):"";}
    static String backend(Context c){return c.getSharedPreferences(PREFS,0).getString("backend","");}
    static boolean relocate(Context c,String id,String expected,String replacement){
        if(!validPath(replacement)||!expected.equals(path(c,id)))return false;
        if(!c.getSharedPreferences(PREFS,0).edit().putString(id+".path",replacement).commit())return false;
        pin(c,id,true);return true;
    }
    public static String title(Context c,String id){return NativeLanguage.text(c,"2".equals(c.getSharedPreferences(PREFS,0).getString(id+".mode",""))?"恢復":"備份");}
    static boolean pinPending(Context c){return pinPending(c,true);}
    static boolean pinPending(Context c,boolean automatic){
        SharedPreferences prefs=c.getSharedPreferences(PREFS,0);
        for(String key:prefs.getAll().keySet())if(key.endsWith(".pending")&&prefs.getBoolean(key,false)){
            String id=key.substring(0,key.length()-8);
            ShortcutManager manager=c.getSystemService(ShortcutManager.class);
            boolean pinned=false;
            if(manager!=null)for(ShortcutInfo existing:manager.getPinnedShortcuts())if(existing.getId().equals(id)){pinned=true;break;}
            if(pinned){prefs.edit().remove(key).apply();continue;}
            // requested only means the dialog was offered. Cancellation keeps the
            // durable entry for explicit retry, without nagging on every resume.
            if(automatic&&prefs.getBoolean(id+".requested",false))continue;
            pin(c,id,automatic);
            return true;
        }return false;
    }
    static void pin(Context c,String id,boolean automatic){
        String path=path(c,id);if(!validPath(path)){if(!automatic)toast(c,"請先從備份或恢復目錄的 start.sh 啟動");return;}
        ShortcutManager manager=c.getSystemService(ShortcutManager.class);SharedPreferences prefs=c.getSharedPreferences(PREFS,0);
        if(manager==null||!manager.isRequestPinShortcutSupported()){if(!automatic)toast(c,"目前桌面不支援建立捷徑");return;}
        boolean restore="2".equals(prefs.getString(id+".mode",""));
        Intent launch=new Intent(c,LauncherActivity.class).setAction(Intent.ACTION_MAIN).putExtra("entryId",id);
        ShortcutInfo shortcut=new ShortcutInfo.Builder(c,id).setShortLabel(title(c,id)).setLongLabel("SpeedBackup "+title(c,id)+" · "+path)
            .setIcon(Icon.createWithResource(c,restore?R.drawable.ic_shortcut_restore:R.drawable.ic_shortcut_backup)).setIntent(launch).build();
        try{
            for(ShortcutInfo existing:manager.getPinnedShortcuts())if(existing.getId().equals(id)){manager.updateShortcuts(java.util.Collections.singletonList(shortcut));prefs.edit().putBoolean(id+".requested",true).apply();if(!automatic)toast(c,"桌面捷徑已存在");return;}
            if(automatic&&prefs.getBoolean(id+".requested",false))return;
            if(manager.requestPinShortcut(shortcut,null))prefs.edit().putBoolean(id+".requested",true).apply();
        }catch(RuntimeException unavailable){if(!automatic)toast(c,"無法加入桌面，請在桌面設定確認捷徑權限");}
    }
    static void toast(Context c,String message){android.widget.Toast.makeText(c,NativeLanguage.text(c,message),android.widget.Toast.LENGTH_LONG).show();}
}
