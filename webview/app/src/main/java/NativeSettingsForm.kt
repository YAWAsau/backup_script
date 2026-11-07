package io.github.yawasau.speedbackup.webview

import android.content.Context
import org.json.JSONObject

internal class NativeSettingsForm(context:Context,private val catalog:NativeCatalog) {
    private val choices=context.assets.open("settings-options.json").bufferedReader().use{JSONObject(it.readText())}
    private val paths=setOf("Custom_path","Output_path","list_location")
    private val lists=setOf("blacklist","whitelist","system")
    private val ranges=mapOf("Zstd_level" to Triple(1,22,6),"Zstd_threads" to Triple(0,256,0),"Zstd_small_threads" to Triple(0,256,1))
    var users=emptyList<String>()
    private var davPreset="custom"
    private var davMessage=""
    private val davPresets=listOf("custom" to "一般 WebDAV", "nextcloud" to "Nextcloud", "owncloud" to "ownCloud", "synology" to "Synology NAS", "wd" to "WD My Cloud", "koofr" to "Koofr", "seafile" to "Seafile", "hidrive" to "HiDrive")
    private fun applyDavPreset(fields:List<JSONObject>,field:JSONObject) {
        val existing=field.optString("value").trim()
        val user=fields.firstOrNull{it.optString("key")=="webdav_remote_user"}?.optString("value").orEmpty()
        val encodedUser=java.net.URLEncoder.encode(user,"UTF-8").replace("+","%20")
        val url=runCatching{java.net.URI(existing)}.getOrNull()
        if(davPreset !in setOf("koofr","hidrive")&&(url?.host.isNullOrEmpty()||url?.scheme !in setOf("http","https")||url?.userInfo!=null)) {
            davMessage="請先在 WebDAV 網址填入伺服器位址（包含 https:// 與自訂連接埠）。";return
        }
        if(davPreset in setOf("nextcloud","owncloud")&&user.isEmpty()) {davMessage="請先填寫 WebDAV 帳號；若伺服器的使用者 ID 與登入帳號不同，套用後請依伺服器提供的 WebDAV 位址修正。";return}
        val origin=if(url?.host!=null)java.net.URI(url.scheme,null,url.host,url.port,null,null,null).toASCIIString() else ""
        val path=url?.rawPath.orEmpty().trimEnd('/')
        val installPath=path.substringBefore("/remote.php/").substringBefore("/seafdav")
        val value=when(davPreset){
            "nextcloud","owncloud"->"$origin$installPath/remote.php/dav/files/$encodedUser"
            "koofr"->"https://app.koofr.net/dav/Koofr"
            "hidrive"->"https://webdav.hidrive.strato.com"
            "seafile"->"$origin$installPath/seafdav"
            else->existing
        }
        field.put("value",value)
        davMessage="已套用範本，請儲存後測試連線。Synology／WD 的連接埠與共用資料夾請以 NAS 設定為準。"
    }
    fun rows(mode:String,fields:List<JSONObject>,c:NativeControls,change:()->Unit,browse:(JSONObject)->Unit,editList:(JSONObject)->Unit):List<JSONObject> {
        val groups=linkedMapOf<String,MutableList<JSONObject>>()
        for(f in fields){
            val key=f.getString("key");val value=f.getString("value");val label=catalog.label(key)
            val category=when{
                Regex("^(smb_|webdav_|remote_)").containsMatchIn(key)->"遠端連線與傳輸"
                Regex("^(Zstd_|Compression_method|Backup_suffix)").containsMatchIn(key)->"壓縮與封裝"
                Regex("^(restore_|recovery_mode|media_recovery)").containsMatchIn(key)->"恢復設定"
                key in paths||key in lists||key=="mount_point"->"路徑與清單"
                Regex("^Backup_|^backup_|^Background_apps|blacklist_mode").containsMatchIn(key)->"備份資料範圍"
                else->"一般設定"
            }
            val rows=groups.getOrPut(category){mutableListOf()}
            val id="settings:$mode:$key"
            val set:(String)->Unit={f.put("value",it);change()}
            val options=if(key=="user"&&users.isNotEmpty())listOf("" to "留空（啟動時選擇）")+users.map{it to "使用者 $it"}
                else choices.optJSONArray(key)?.let{a->(0 until a.length()).map{a.getJSONArray(it).let{v->v.getString(0) to v.getString(1)}}}
            val range=ranges[key]
            val child=when{
                key in paths->c.button("$id:browse",if(key=="Custom_path")"瀏覽／多選資料夾" else "瀏覽選擇"){browse(f)}.put("standard",true)
                key in lists->c.button("$id:rows",if(value.isEmpty())"空清單" else "編輯清單"){editList(f)}.put("standard",true)
                options!=null->c.select(id,label,value,options,set).put("standard",true)
                range!=null->{
                    val number=value.toIntOrNull();val representable=number!=null&&number in range.first..range.second&&number.toString()==value
                    val slider=c.node(id,"range",label){kind,text,_->
                        val n=text.toIntOrNull();if(kind=="value"&&n!=null&&n in range.first..range.second&&n.toString()==text)set(text)
                    }.put("min",range.first).put("max",range.second).put("value",(if(representable)number else range.third).toString())
                        .put("preserved",if(representable)"" else value.ifEmpty{"留空（沿用原設定）"}).put("zeroLabel",if(key.contains("threads"))"自動使用可用核心" else "")
                    slider
                }
                else->c.input(id,label,value,set).put("inGroup",true).put("standard",true).put("multi",key=="mount_point"||value.contains('\n')).put("password",key.endsWith("_pass"))
            }
            if(key=="webdav_url") {
                val preset=c.select("$id:preset","WebDAV／NAS 範本",davPreset,davPresets){davPreset=it;davMessage="";change()}.put("standard",true)
                val apply=c.button("$id:apply","套用所選範本"){applyDavPreset(fields,f);change()}.put("standard",true)
                rows.add(c.group("$id:preset-row","setting",listOf(preset,apply),"WebDAV／NAS 範本").put("detail",davMessage.ifEmpty{"先填入伺服器位址與帳號，再套用範本；不會修改密碼。Nextcloud／ownCloud／Koofr 建議使用專用應用程式密碼。"}))
            }
            rows.add(c.group("$id:row","setting",listOf(child),label).put("detail",catalog.help(key,f.optString("help"),mode)+(if(key=="webdav_url")"\n401：帳密或應用程式密碼；403：資料夾權限；404：WebDAV 路徑；405：確認已啟用 WebDAV；413：上傳大小限制；507：空間或配額不足。HTTPS 憑證須有效，NAS 的管理頁網址通常不是 WebDAV 網址。" else "")+(if(key in paths&&value.isNotEmpty())"\n$value" else "")).put("translateDetail",key !in paths).put("first",true).put("last",true))
        }
        return groups.flatMap{(category,rows)->
            rows.forEachIndexed{i,row->row.put("first",i==0).put("last",i==rows.lastIndex)}
            listOf(c.node("settings:$mode:heading:$category","heading",category).put("level","H3"),c.group("settings:$mode:section:$category","settings-section",rows))
        }
    }
}
