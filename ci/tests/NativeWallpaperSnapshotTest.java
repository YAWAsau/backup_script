import java.lang.reflect.*;
/** Run with the unminified APK on Android; does not install or change preferences. */
public final class NativeWallpaperSnapshotTest {
 public static void main(String[] args) throws Exception {
  android.os.Looper.prepareMainLooper();
  boolean before=args.length==1 && args[0].equals("before");
  Class<?> snap=Class.forName("androidx.compose.runtime.snapshots.Snapshot");
  Object companion=snap.getField("Companion").get(null);
  Class<?> wallpaper=null;Object instance=null;
  if(!before){
   wallpaper=Class.forName("io.github.yawasau.speedbackup.webview.NativeUserWallpaper");
   instance=wallpaper.getField("INSTANCE").get(null);
   wallpaper.getMethod("initialize").invoke(instance);
  }
  Object older=companion.getClass().getMethod("takeSnapshot",Class.forName("kotlin.jvm.functions.Function1")).invoke(companion,new Object[]{null});
  if(before){
   wallpaper=Class.forName("io.github.yawasau.speedbackup.webview.NativeUserWallpaper");
   instance=wallpaper.getField("INSTANCE").get(null);
  }
  Object previous=snap.getMethod("unsafeEnter").invoke(older);boolean reproduced=false;
  try {
   try {
    for(String getter:new String[]{"getRendered","getBitmap","getEnabled","getTransparency","getCommittedOpacity","getBlur","getDim","getBusy","getStatus"})wallpaper.getMethod(getter).invoke(instance);
   }catch(InvocationTargetException e){
    if(!before || !(e.getCause() instanceof IllegalStateException) || !e.getCause().getMessage().contains("snapshot"))throw e;
    reproduced=true;System.out.println("REPRODUCED: "+e.getCause().getMessage());
   }
   if(before&&!reproduced)throw new AssertionError("expected late-initialization snapshot failure");
   if(!before)System.out.println("PASS: wallpaper initialized before snapshot; all shared state getters readable");
  }finally{snap.getMethod("unsafeLeave",snap).invoke(older,previous);snap.getMethod("dispose").invoke(older);}
 }
}
