package io.github.yawasau.speedbackup.webview;

import org.json.JSONException;
import org.json.JSONObject;
import java.util.Iterator;

/** NativeSession already detaches published snapshots from its mutable page state.
 * Layout preparation owns only root metadata and the console nodes slot; all other
 * nested values stay read-only. Never use this for a mutable session model.
 */
final class NativeModelSnapshot {
    private static JSONObject copyObject(JSONObject source) throws JSONException {
        JSONObject result=new JSONObject();
        for(Iterator<String> keys=source.keys();keys.hasNext();){String key=keys.next();result.put(key,source.get(key));}
        return result;
    }
    static JSONObject layoutCopy(JSONObject source) throws JSONException {
        JSONObject result=copyObject(source);
        JSONObject screen=source.optJSONObject("screen");
        if(screen!=null&&"console".equals(screen.optString("key")))result.put("screen",copyObject(screen));
        return result;
    }
}
