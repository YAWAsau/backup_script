package io.github.yawasau.speedbackup.webview;
import org.json.*;
import java.util.Arrays;

/** Run on Android with NativeModelSnapshot on the same class path. No app/session access. */
public final class NativeModelSnapshotTest {
    private static void check(boolean ok,String what){if(!ok)throw new AssertionError(what);}
    private static volatile int sink;
    public static void main(String[] args)throws Exception {
        JSONArray nodes=new JSONArray();
        for(int i=0;i<300;i++)nodes.put(new JSONObject().put("kind",i%10==0?"text":"log").put("id","control-"+i).put("label","fixture line "+i+" "+"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"));
        JSONObject source=new JSONObject().put("seq",42).put("safeTop",0).put("screen",new JSONObject().put("key","console").put("nodes",nodes)).put("nullable",JSONObject.NULL);
        String original=source.toString();
        JSONObject first=NativeModelSnapshot.layoutCopy(source);
        first.remove("seq");first.put("safeTop",24);first.getJSONObject("screen").put("nodes",new JSONArray());
        check(source.toString().equals(original),"layout modified published snapshot");
        JSONObject second=NativeModelSnapshot.layoutCopy(source);
        check(second.getLong("seq")==42&&second.getInt("safeTop")==0,"re-layout inherited previous metadata");
        check(second.getJSONObject("screen").getJSONArray("nodes").length()==300,"re-layout lost console logs");
        check(second.has("nullable")&&second.isNull("nullable"),"JSON null changed");
        check(new JSONObject(first.toString()).getJSONObject("screen").getJSONArray("nodes").length()==0,"prepared document serialization incorrect");
        JSONObject menu=new JSONObject().put("seq",7).put("menu",new JSONObject().put("title","fixture"));
        JSONObject copy=NativeModelSnapshot.layoutCopy(menu);copy.put("safeBottom",16);copy.remove("seq");
        check(menu.getLong("seq")==7&&!menu.has("safeBottom"),"menu layout metadata leaked");
        for(int i=0;i<30;i++){NativeModelSnapshot.layoutCopy(source);new JSONObject(source.toString());}
        long[] oldTimes=new long[7],newTimes=new long[7];
        for(int r=0;r<7;r++){
            long start=System.nanoTime();for(int i=0;i<100;i++)sink=new JSONObject(source.toString()).length();oldTimes[r]=System.nanoTime()-start;
            start=System.nanoTime();for(int i=0;i<100;i++)sink=NativeModelSnapshot.layoutCopy(source).length();newTimes[r]=System.nanoTime()-start;
        }
        Arrays.sort(oldTimes);Arrays.sort(newTimes);
        System.out.println("PASS: source isolation, re-layout logs, metadata, JSON null and serialization");
        System.out.println("copy median ns/op: old="+oldTimes[3]/100+" new="+newTimes[3]/100+"; isolated 300-row fixture, not end-to-end latency");
    }
}
