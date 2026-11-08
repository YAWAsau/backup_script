package io.github.yawasau.speedbackup.webview

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal class NativeEditorPage(private val session:NativeSession,context:Context):NativePage {
    private val c get()=session.controls
    private val selection=NativeSelection()
    private val form=NativeSettingsForm(context,session.catalog)
    private lateinit var manager:JSONObject
    private val settings=linkedMapOf<String,List<JSONObject>>()
    private var panel="apps"
    private var timeline=obj("sources" to JSONArray(),"targets" to JSONArray())
    private val icons=HashMap<String,String>()
    private val closed=java.util.concurrent.atomic.AtomicBoolean()
    private var iconsRetryAt=0L
    private var iconsRetry:java.util.concurrent.ScheduledFuture<*>?=null
    private var iconsReady=false
    private val iconSettled=HashSet<String>()
    private var iconsPreload:java.util.concurrent.ScheduledFuture<*>?=null
    private var lastDraft=""
    private var draftDirty=false
    private var draftRetryAt=0L
    private var draftFailures=0
    private var submissionUnknown=false
    private var draftTimer:java.util.concurrent.ScheduledFuture<*>?=null
    private var pingAt=0L
    private var picker:NativePickerController?=null
    @Volatile private var discovery:NativeDiscovery?=null
    private var initialDiscoveryPending=false
    private fun openDiscovery(){discovery?.close();c.forgetPrefix("discovery:");discovery=NativeDiscovery(session).also{it.start()};session.emit()}
    private fun discoveryScreen():JSONObject {
        val scan=discovery!!
        val rows=scan.endpoints.mapIndexed { index, endpoint ->
            c.group("discovery:result:${endpoint.url}","setting",listOf(c.button("discovery:select:${endpoint.url}","選擇此地址"){
                if(discovery!==scan||scan.endpoints.none{it.url==endpoint.url})return@button
                val fields=settings.getValue(panel)
                val auto=fields.firstOrNull{it.optString("key")=="remote_address_mode"}?.optString("value")=="auto"
                if(auto&&endpoint.identity.isEmpty()){session.status="此地址尚未取得設備識別，請稍候或使用手動地址。";session.emit();return@button}
                val identity=fields.firstOrNull{it.optString("key")==if(endpoint.type=="SMB")"remote_smb_identity" else "remote_webdav_identity"}
                if(auto&&identity==null){session.status="設定缺少設備識別欄位，請重新啟動腳本以更新設定。";session.emit();return@button}
                val previousIdentity=identity?.optString("value")
                val key=if(endpoint.type=="SMB")"smb_url" else "webdav_url"
                val target=fields.firstOrNull{it.optString("key")==key}
                val protocol=fields.firstOrNull{it.optString("key")=="remote_type"}
                if(target==null||protocol==null){session.status="此設定不包含 ${endpoint.type} 地址欄位，請返回手動設定。";session.emit();return@button}
                val previous=target.optString("value")
                val path=if(previousIdentity==endpoint.identity&&endpoint.identity.isNotEmpty())runCatching{java.net.URI(previous).rawPath}.getOrNull() else null
                val chosen=if(!path.isNullOrEmpty()&&path!="/")endpoint.url.substringBefore('/',endpoint.url).let{runCatching{val u=java.net.URI(endpoint.url);"${u.scheme}://${u.rawAuthority}$path"}.getOrDefault(endpoint.url)} else endpoint.url
                identity?.put("value",endpoint.identity)
                target.put("value",chosen)
                protocol.put("value",if(endpoint.type=="SMB")"smb" else "webdav")
                scan.close();discovery=null;form.connectionSetup=true
                session.status=if(endpoint.type=="SMB")"已填入伺服器地址，請在 SMB 地址補上共用資料夾名稱，再儲存設定。" else "已填入 WebDAV 地址，請確認帳號與路徑後儲存設定。"
                changed()
            }.put("navigation",true)),"${endpoint.name} · ${endpoint.type}").put("detail",endpoint.url).put("translateDetail",false).put("first",index==0).put("last",index==scan.endpoints.lastIndex)
        }
        return c.screen("editor:discovery","自動發現電腦／NAS",
            listOf(c.node("discovery:status",if(scan.running)"loading" else "text",scan.message))+
                (if(rows.isEmpty())emptyList() else listOf(c.group("discovery:results","settings-section",rows))),
            listOf(c.button("discovery:back","返回手動設定"){scan.close();discovery=null;session.emit()},
                c.button("discovery:refresh",if(scan.running)"停止搜尋" else "重新搜尋"){if(scan.running){scan.stop();session.emit()}else openDiscovery()}),
            session.status.ifEmpty{"選擇設備後沿用已儲存帳密。SMB 設備已讀取識別碼；候選僅表示埠可連線，不能自動追蹤。"})
    }
    private var editing:JSONObject?=null
    private data class ListRow(val id:Long,var value:String)
    private var nextRowId=0L
    private var rowPage=0
    private fun changeRowPage(page:Int){rowPage=page;c.forgetPrefix("rows:item:")}
    private val editRows=mutableListOf<ListRow>()
    private fun openList(field:JSONObject) {
        editing=field
        changeRowPage(0)
        editRows.clear()
        field.getString("value").split('\n').forEach{editRows.add(ListRow(++nextRowId,it))}
        session.emit()
    }
    private fun listScreen(field:JSONObject):JSONObject {
        val lastPage=((editRows.size-1).coerceAtLeast(0)/100)
        rowPage=rowPage.coerceIn(0,lastPage)
        val rows=editRows.drop(rowPage*100).take(100).mapIndexed { localIndex,row ->
            val index=rowPage*100+localIndex
            val input=c.input("rows:item:${row.id}:value","第 ${index+1} 項",row.value){text->
                val position=editRows.indexOf(row)
                if(editing===field&&position>=0){
                    val parts=text.split('\n')
                    row.value=parts.first()
                    if(parts.size>1){editRows.addAll(position+1,parts.drop(1).map{ListRow(++nextRowId,it)});changeRowPage(rowPage);session.emit()}
                }
            }.put("inGroup",true).put("placeholder","輸入項目或 # 註釋")
            val remove=c.button("rows:item:${row.id}:remove","×") {if(editing===field){editRows.remove(row);c.forgetPrefix("rows:item:${row.id}:");val last=((editRows.size-1).coerceAtLeast(0)/100);if(rowPage>last)changeRowPage(last);session.emit()}}
                .put("description","刪除第 ${index+1} 項").put("standard",true)
            c.group("rows:item:${row.id}:group","edit-row",listOf(input,remove))
        }
        val pages=if(lastPage>0)listOf(c.group("rows:pages","row",listOf(
            c.button("rows:previous","上一頁",rowPage==0){if(editing===field){changeRowPage((rowPage-1).coerceAtLeast(0));session.emit()}},
            c.node("rows:count","text","${rowPage+1} / ${lastPage+1}"),
            c.button("rows:next","下一頁",rowPage==lastPage){if(editing===field){changeRowPage((rowPage+1).coerceAtMost(lastPage));session.emit()}})))else emptyList()
        return c.screen("editor:rows:${field.getString("key")}",session.catalog.label(field.getString("key")),
            listOf(c.node("rows:help","text","每行一個項目；保留 # 註釋與原有順序。"))+pages+rows,
            listOf(c.button("rows:add","新增一行"){if(editing===field){editRows.add(ListRow(++nextRowId,""));val last=(editRows.size-1)/100;if(rowPage!=last)changeRowPage(last);session.emit()}},
                c.button("rows:cancel","取消"){if(editing===field){editing=null;c.forgetPrefix("rows:item:");session.emit()}},
                c.button("rows:save","確定"){if(editing===field){field.put("value",editRows.joinToString("\n"){it.value});editing=null;c.forgetPrefix("rows:item:");changed()}}),
            "確定後回到設定，儲存設定才會寫入檔案。")
    }
    private val mode get()=manager.optString("mode")
    private val flow get()=manager.optString("flow")
    private val single get()=mode in setOf("remote","media","remote-delete")
    override fun load(){
        manager=JSONObject(session.api.get("manager"))
        form.authSetup=manager.optBoolean("authSetup");form.connectionSetup=manager.optBoolean("discoverySetup")||form.authSetup
        selection.load(session.api.get("list"),session.api.get("draft"),single)
        lastDraft=selection.draft()
        if(mode=="remote-delete")selection.apps.forEach{it.put("label",it.getString("label").replace(Regex("^\\d+\\. "),""))}
        if(flow in setOf("restore","remote"))timeline=JSONObject(session.api.get("timeline"))
        val savedSettings=selection.saved.optJSONObject("settings")
        for(key in listOf("backup","restore"))if(manager.optBoolean(key)&&savedSettings?.optJSONObject(key)!=null)openSettings(key)
        panel="apps"
        if(manager.optString("panel")=="settings"){openSettings(mode);initialDiscoveryPending=manager.optBoolean("discoverySetup")}
        else if(manager.optString("panel")=="manager")selection.saved.optString("panel").takeIf{it in settings}?.let{panel=it}
        lastDraft=currentDraft()
        selection.saved.optJSONObject("picker")?.let{saved->
            val key=saved.optString("mode")
            if(key in setOf("backup","restore")&&manager.optBoolean(key)){
                openSettings(key)
                settings[key]?.find{it.getString("key")==saved.optString("key")&&it.getString("key") in setOf("Custom_path","Output_path","list_location")&&it.getString("value")==saved.optString("base")}?.let{field->picker=NativePickerController(session,key,field,saved){picker=null;changed()};picker!!.loadInitial()}
            }
        }
        // Publish an initial loading document so Binder navigation can acknowledge
        // before the same controller services icon requests. Never expose blank app rows.
        session.later(0){try{prepareIcons()}finally{iconsReady=true};session.emit()}
    }
    private fun pagePackages():List<String> {
        val found=selection.filtered()
        selection.page=selection.page.coerceIn(0,((found.size+99)/100-1).coerceAtLeast(0))
        return found.drop(selection.page*100).take(100).map{it.getString("pkg")}
    }
    private fun fetchIcons(packages:List<String>):Boolean {
        val missing=packages.filter{!it.startsWith("removed:")&&it !in icons}.take(12)
        if(missing.isEmpty())return true
        if(android.os.SystemClock.elapsedRealtime()<iconsRetryAt){iconSettled.addAll(pagePackages());return false}
        try{
            val data=JSONObject(session.api.post("icons",missing.joinToString("\n")))
            missing.forEach{icons[it]=data.optString(it)}
            iconsRetry?.cancel(false);iconsRetry=null;iconsRetryAt=0
        }catch(e:Exception){
            iconsRetryAt=android.os.SystemClock.elapsedRealtime()+10000
            iconsRetry?.cancel(false)
            iconsRetry=session.later(10000){if(!closed.get()&&!session.finished){prepareIcons();session.emit()}}
            session.diagnostic("native-icons-failed")
            // A failed service must not hide the list indefinitely. These rows use
            // the existing fallback glyph until a successful, bounded retry.
            iconSettled.addAll(pagePackages())
            return false
        }
        // Decode before publishing actual app rows, never on the Compose thread.
        missing.forEach{icons[it]?.takeIf{value->value.isNotEmpty()}?.let{NativeIconCache.decode(it)}}
        iconSettled.addAll(missing)
        return true
    }
    private fun prepareIcons(){
        iconsPreload?.cancel(false);iconsPreload=null
        if(closed.get()||session.finished||panel!="apps"||mode=="media")return
        val first=pagePackages().take(12)
        fetchIcons(first)
        // Rehydrate content-keyed cache after eviction, preserving icons on return.
        first.forEach{icons[it]?.takeIf{v->v.isNotEmpty()}?.let{NativeIconCache.decode(it)}}
        scheduleIconPreload()
    }
    private fun scheduleIconPreload(){
        if(closed.get()||session.finished||panel!="apps"||mode=="media"||android.os.SystemClock.elapsedRealtime()<iconsRetryAt)return
        iconsPreload=session.later(40){
            iconsPreload=null
            if(!closed.get()&&!session.finished&&panel=="apps"){
                val current=pagePackages()
                val next=selection.filtered().drop((selection.page+1)*100).take(12).map{it.getString("pkg")}
                val pending=(current+next).filter{!it.startsWith("removed:")&&it !in icons}.take(12)
                if(pending.isNotEmpty()){
                    val ok=fetchIcons(pending)
                    if(pending.any{it in current})session.emit()
                    if(ok)scheduleIconPreload()
                }
            }
        }
    }
    private fun openSettings(key:String){
        form.authSetup=manager.optBoolean("authSetup");form.connectionSetup=manager.optBoolean("discoverySetup")||form.authSetup
        require(key in setOf("backup","restore")&&manager.optBoolean(key))
        if(key !in settings){
            val fields=JSONArray(session.api.get(key)).modelObjects().map{it.put("original",it.getString("value"))}
            require(fields.size<=1000)
            val saved=if(form.authSetup)null else selection.saved.optJSONObject("settings")?.optJSONObject(key)
            for(field in fields){
                val edit=saved?.optJSONArray(field.getString("key"))?:continue
                // Replay only against the identical source value. Never overwrite
                // an external edit with a stale draft from another conf revision.
                if(edit.length()==2&&edit.opt(0) is String&&edit.opt(1) is String){
                    if(edit.getString(0)==field.getString("original"))field.put("value",edit.getString(1))
                    else session.status="部分設定已由其他程序變更；這些欄位已載入最新值，未套用舊草稿。"
                }
            }
            settings[key]=fields
            if(fields.any{it.getString("key")=="user"})form.users=JSONArray(session.api.get("users")).let{a->(0 until a.length()).map{a.get(it).toString()}}
        }
        panel=key
    }
    private fun changed(){draftDirty=true;draftTimer?.cancel(false);draftTimer=session.later(100){flushDraft()};prepareIcons();session.emit()}
    private fun currentDraft():String {
        val edits=JSONObject()
        for((key,fields) in settings){val values=JSONObject();for(f in fields)if(f.getString("value")!=f.getString("original"))values.put(f.getString("key"),arr(listOf(f.getString("original"),f.getString("value"))));edits.put(key,values)}
        return selection.draft(obj("settings" to edits,"panel" to panel,"picker" to picker?.draft()))
    }
    private fun flushDraft(force:Boolean=false){
        if(session.finished||submissionUnknown||!draftDirty)return
        val remaining=draftRetryAt-android.os.SystemClock.elapsedRealtime()
        if(!force&&remaining>0){
            // A new edit may replace the retry timer with the 100 ms debounce.
            // Preserve the outstanding retry deadline instead of losing the dirty draft.
            draftTimer?.cancel(false)
            draftTimer=session.later(remaining){flushDraft()}
            return
        }
        try{
            val draft=currentDraft();require(draft.toByteArray(Charsets.UTF_8).size<=1024*1024){"草稿過大，無法暫存；請先儲存設定"}
            if(draft!=lastDraft){session.api.post("draft",draft);lastDraft=draft}
            draftDirty=false;draftFailures=0;draftRetryAt=0
        }catch(e:Exception){
            // A timed-out POST can still reach root later. Even reverting to the
            // previous confirmed draft must be sent again to overwrite that late write.
            lastDraft=""
            draftFailures=(draftFailures+1).coerceAtMost(6)
            draftRetryAt=android.os.SystemClock.elapsedRealtime()+(1000L shl draftFailures)
            draftTimer?.cancel(false)
            draftTimer=session.later(1000L shl draftFailures){flushDraft()}
            throw e
        }
    }
    private fun toggle(key:String,label:String,checked:Boolean,disabled:Boolean=false,action:()->Unit)=c.node(key,"toggle",label){kind,_,_->if(kind=="click"&&!disabled)action()}.put("checked",checked).put("disabled",disabled)
    private fun settingsChanged()=settings.values.flatten().count{it.getString("value")!=it.getString("original")}
    private fun saveSettings(key:String){
        val fields=settings.getValue(key)
        session.api.post("save-$key",encodeSettings(fields))
        fields.forEach{it.put("original",it.getString("value"))};draftDirty=true;try{flushDraft()}catch(e:Exception){session.status="設定已儲存，但草稿暫存失敗；請保留目前畫面。";session.diagnostic("native-settings-draft-failed")}
    }
    private fun timelineNodes():List<JSONObject>{
        val choice=selection.timeline
        val sources=timeline.getJSONArray("sources").modelObjects().map{it.getString("id") to it.getString("label")}
        val targets=timeline.getJSONArray("targets").modelObjects().map{it.getString("id") to it.getString("label")}
        val kind=choice.optString("mode","match")
        val selected=if(kind=="account")"account:"+choice.optString("target") else if(kind in setOf("cross","merge"))"cross" else "match"
        val nodes=mutableListOf(c.select("timeline:mode","地圖時間軸恢復方式",selected,listOf("match" to "按原帳號對應恢復")+targets.map{"account:"+it.first to it.second}+listOf("cross" to "跨帳號恢復")){value->
            selection.timeline=obj("mode" to if(value.startsWith("account:"))"account" else value,"target" to if(value.startsWith("account:"))value.substringAfter(':') else "","sources" to JSONArray());changed()
        })
        if(kind in setOf("cross","merge")){
            nodes+=c.select("timeline:cross","跨帳號方式",kind,listOf("cross" to "來源 → 目的","merge" to "合併後恢復")){v->choice.put("mode",v);if(v=="cross")choice.put("sources",arr(choice.getJSONArray("sources").strings().take(1)));changed()}
            if(kind=="cross")nodes+=c.select("timeline:source","選擇來源帳號",choice.getJSONArray("sources").optString(0),listOf("" to "請選擇來源帳號")+sources){v->choice.put("sources",arr(if(v.isEmpty())emptyList() else listOf(v)));changed()}
            else for((id,label) in sources)nodes+=toggle("timeline:source:$id",label,id in choice.getJSONArray("sources").strings()){
                val ids=choice.getJSONArray("sources").strings().toMutableSet();if(!ids.remove(id))ids.add(id);choice.put("sources",arr(ids));changed()
            }.put("inlineControl",true)
            nodes+=c.select("timeline:target","選擇目的帳號",choice.optString("target"),listOf("" to "請選擇目的帳號")+targets){v->choice.put("target",v);changed()}
            nodes+=c.node("timeline:note","text",if(kind=="merge")"保留目的帳號既有紀錄；完全重複的紀錄略過。" else "以所選來源取代目的帳號的語意時間軸紀錄；其他帳號不變。要保留既有紀錄，請選「合併後恢復」。")
        }
        return nodes.map{if(it.optString("kind")=="select")it.put("standard",true) else it}
    }
    private fun timelineSubmission():String {
        if(flow !in setOf("restore","remote")||timeline.getJSONArray("sources").length()==0||selection.apps.none{!it.optBoolean("removed")&&it.optBoolean("selected")&&!it.optBoolean("apk")&&it.optString("displayPackage").ifEmpty{it.getString("pkg")}=="com.google.android.apps.maps"})return ""
        val choice=selection.timeline;val kind=choice.getString("mode");val target=choice.getString("target");val sources=choice.getJSONArray("sources").strings()
        require(kind in setOf("match","account","cross","merge"))
        require(kind=="match"||timeline.getJSONArray("targets").modelObjects().any{it.getString("id")==target}){"請選擇已登入的目的 Google 帳號"}
        if(kind in setOf("cross","merge"))require(sources.isNotEmpty()&&(kind!="cross"||sources.size==1)&&sources.all{id->timeline.getJSONArray("sources").modelObjects().any{it.getString("id")==id}}){"請選擇時間軸來源帳號"}
        return "\n@timeline\t$kind\t$target\t${sources.joinToString(",")}"
    }
    private fun appNodes():List<JSONObject>{
        val nodes=mutableListOf(c.input("apps:search","搜尋應用名稱或包名",selection.search){selection.search=it;selection.page=0;changed()}.put("inGroup",true).put("placeholder","搜尋應用名稱或包名"))
        nodes+=c.group("apps:toolbar","toolbar",listOf(c.select("apps:filter","篩選",selection.filter,listOf("all" to "全部應用","yes" to "已選取","no" to "未選取")){selection.filter=it;selection.page=0;changed()})+listOf("all" to "全選","none" to "清空","invert" to "反選").map{(key,label)->c.button("apps:$key",label){selection.filtered().filterNot{it.optBoolean("removed")}.forEach{val active=if(key=="invert")!it.getBoolean("selected") else key=="all";it.put("selected",active);if(!active)it.put("apk",false)};changed()}})
        val found=selection.filtered();val pages=((found.size+99)/100).coerceAtLeast(1);selection.page=selection.page.coerceIn(0,pages-1)
        nodes+=c.node("apps:count","text","已選 ${selection.apps.count{it.getBoolean("selected")}} / ${selection.apps.size} · 搜尋結果 ${found.size}").put("muted",true)
        val controls=c.group("apps:controls","controls",nodes.toList());nodes.clear();nodes+=controls
        val pageApps=found.drop(selection.page*100).take(100)
        val readyApps=if(mode=="media")pageApps else pageApps.takeWhile{it.getString("pkg").let{id->id.startsWith("removed:")||id in iconSettled}}
        for(app in readyApps){
            val id=app.getString("pkg");val removed=app.optBoolean("removed");val selected=app.getBoolean("selected");val apk=app.getBoolean("apk")
            val children=mutableListOf<JSONObject>()
            if(!single)children+=toggle("app:$id:apk","僅 APK",selected&&apk,removed){val active=!selected||!apk;app.put("selected",active).put("apk",active);changed()}.put("caption","僅 APK")
            children+=toggle("app:$id:full",if(single)"選取" else "完整",selected&&(!apk||single),removed){app.put("selected",!selected||apk).put("apk",false);changed()}.put("caption",if(single)"選取" else "完整")
            if(!removed&&app.optString("displayPackage").ifEmpty{id}=="com.google.android.apps.maps"&&flow in setOf("restore","remote")&&timeline.getJSONArray("sources").length()>0)children+=timelineNodes()
            nodes+=c.node("app:$id","app",app.getString("label")).put("detail",app.optString("displayPackage").ifEmpty{if(single)"" else id}).put("icon",icons[id]?:"").put("badge",app.optString("badge")).put("removed",removed).put("children",arr(children))
        }
        if(readyApps.size<pageApps.size)nodes+=c.node("apps:icons-loading","loading","正在載入其餘應用圖示…").put("indicator","orbit").put("muted",true)
        nodes+=c.group("apps:paging","row",listOf(c.button("apps:prev","上一頁",selection.page==0){selection.page--;changed()},c.node("apps:page","text","${selection.page+1} / $pages").put("centerLabel",true),c.button("apps:next","下一頁",selection.page+1>=pages){selection.page++;changed()}))
        return nodes
    }
    private fun save(){
        if(session.finished||submissionUnknown)return
        val run=run@{
            if(session.finished||submissionUnknown)return@run
            val saved=mutableListOf<String>()
            try{
                if(flow.isNotEmpty())require(selection.apps.any{!it.optBoolean("removed")&&it.getBoolean("selected")}){"請至少選擇一個項目"}
                if(form.authSetup){session.status="正在儲存帳密…";session.emit()}
                val trailer=if(form.authSetup)"" else timelineSubmission()
                for((key,fields) in settings)if(fields.any{it.getString("value")!=it.getString("original")}){saveSettings(key);saved+=key}
                val submit=!form.authSetup&&(selection.changed().isNotEmpty()||flow.isNotEmpty())
                val retryStatus=if(saved.isNotEmpty())"帳密已儲存，正在重新驗證…" else "帳密未修改，正在重新驗證…"
                if(form.authSetup){session.status=retryStatus;session.emit()}
                val response=session.api.post(if(submit)"save" else "finish",if(submit)selection.submission()+trailer else "")
                session.finish(if(form.authSetup)retryStatus else response)
            }catch(e:Exception){if(e is java.io.IOException&&e !is NativeApi.ApiFailure)submissionUnknown=true;session.status=(if(saved.isNotEmpty())"已儲存：${saved.joinToString("、")}。" else "")+"未完成：${e.message}。若連線中斷，請確認日誌與原檔狀態，勿假設未寫入。";session.emit()}
        }
        if(flow.isEmpty()&&!form.authSetup)session.confirm(if(mode=="remote-delete")"提交所選遠端備份？接下來仍需兩次確認才會刪除。" else "儲存並返回？各檔案分別儲存；中途失敗時已儲存的檔案會保留。",run)else run()
    }
    override fun render(model:JSONObject){
        // Rendering must never schedule writes or retry failed requests.
        if(!iconsReady&&panel=="apps"&&mode!="media"){
            pagePackages() // Clamp the restored page before assigning its stable route.
            model.put("screen",c.screen("editor:apps","載入應用清單",listOf(c.node("editor:loading:message","loading","正在準備應用圖示…").put("indicator","orbit")),emptyList()).put("appPage",selection.page))
            model.put("sectionRoute","editor:apps:${selection.page}")
            return
        }
        discovery?.let{model.put("screen",discoveryScreen()).put("sectionRoute","editor:discovery");return}
        picker?.let{model.put("picker",it.model());model.put("sectionRoute","picker:${it.identity}");return}
        editing?.let{field->model.put("screen",listScreen(field));return}
        val nodes=if(panel=="apps")appNodes() else form.rows(panel,if(manager.optBoolean("discoverySetup"))settings.getValue(panel).filter{it.optString("key") in setOf("remote_type","remote_address_mode","remote_smb_identity","remote_webdav_identity","smb_url","smb_remote_user","smb_remote_pass","webdav_url","webdav_remote_user","webdav_remote_pass")}else settings.getValue(panel),c,{changed()},{field->
            picker=NativePickerController(session,panel,field){picker=null;changed()};picker!!.loadInitial();changed()
        },{field->openList(field)},{openDiscovery()}).toMutableList().apply{
            if(!form.connectionSetup)add(c.group("settings:actions","row",listOf(c.button("settings:undo","還原未儲存修改"){session.confirm("還原這份設定尚未儲存的修改？"){settings.getValue(panel).forEach{it.put("value",it.getString("original"))};changed()}},
            c.button("settings:save","儲存此設定"){session.confirm("儲存此設定？其他檔案不會一起寫入。"){saveSettings(panel);session.status="設定已儲存";session.emit()}}.put("primary",true))))
        }
        val tabs=if(manager.optString("panel")=="manager")listOf("apps" to "應用清單","backup" to "備份設定","restore" to "恢復設定").filter{it.first=="apps"||manager.optBoolean(it.first)}.map{(key,label)->c.button("editor:panel:$key",label,session.finished){if(key=="apps")panel=key else openSettings(key);changed()}.put("selected",key==panel)} else emptyList()
        val title=if(form.authSetup)"認證失敗，請重新輸入帳密" else if(panel!="apps"&&form.connectionSetup)(if(settings.getValue(panel).any{it.optString("key")=="remote_type"&&it.optString("value")=="smb"})"SMB" else "WebDAV")+" 連線設定" else if(panel!="apps")if(panel=="restore")"恢復設定" else "備份設定" else if(flow=="backup")"選擇備份應用" else if(flow.isNotEmpty())"選擇恢復項目" else if(mode=="remote-delete")"編輯遠端備份" else "應用清單"
        val label=if(form.authSetup)"儲存並重試" else if(manager.optBoolean("discoverySetup"))"連線並繼續" else if(flow=="backup")"下一步 · 開始備份" else if(flow.isNotEmpty())"下一步 · 開始恢復" else if(mode=="remote-delete")"刪除所選備份" else "儲存並返回"
        val count=selection.changed().size+settingsChanged()
        val hint=if(form.authSetup){if(count>0)"帳密尚未儲存" else "目前儲存的帳密未通過認證，請檢查使用者名稱與密碼。"}else (if(count>0)"$count 項已修改" else "尚未修改")+if(flow in setOf("restore","remote"))"\n恢復前請記得開啟目的 Google 帳號的時間軸，否則可能看不到歷史紀錄。" else ""
        val subtitle=if(form.authSetup)"伺服器拒絕目前儲存的帳密。請修改後按「儲存並重試」，或返回。" else if(panel!="apps"&&form.connectionSetup)"確認地址與登入帳密後儲存。" else if(panel!="apps")"調整本次入口的設定；儲存後會重新載入。" else if(flow.isNotEmpty())"清單已同步；保留既有選取與註釋。選擇完成後按下一步執行。" else if(single)"勾選要處理的項目；儲存或取消後返回。" else "選擇要處理的應用；儲存或取消後返回。"
        val note=c.node("editor:note:$panel","text",if(panel!="apps")"修改設定後儲存；返回將保留已儲存的內容。" else if(single)"儲存選擇後返回；取消會保留原清單。" else "僅 APK／完整只能擇一；都不勾則略過。").put("muted",true)
        val screen=c.screen("editor:$panel",title,(if(tabs.isNotEmpty())listOf(c.group("editor:tabs","row",tabs))else emptyList())+listOf(note)+nodes,listOf(c.button("editor:cancel",if(form.authSetup)"返回" else "取消",session.finished){cancel()},c.button("editor:save",label,session.finished||submissionUnknown){save()}),session.status.ifEmpty{hint},subtitle)
        if(panel=="apps")screen.put("appPage",selection.page)
        model.put("screen",screen).put("sectionRoute","editor:$panel:${if(panel=="apps")selection.page else "settings"}")
    }
    override fun action(value:String){if(value.startsWith("picker:")){picker?.action(JSONObject(value.substringAfter(':')));changed();return};when(value){"cancel"->cancel();"back"->back();"save"->save()}}
    override fun back(){
        if(submissionUnknown){session.exit();return}
        discovery?.let{it.close();discovery=null;session.emit();return}
        picker?.let{it.back();changed();return}
        if(editing!=null){editing=null;session.emit();return}
        if(panel!="apps"&&manager.optString("panel")=="manager"){panel="apps";changed();return}
        if(panel=="apps"&&selection.page>0){selection.page--;changed();return}
        cancel()
    }
    private fun cancel(){
        if(submissionUnknown){session.exit();return}
        val cancel={session.finish(session.api.post("cancel",""))}
        if(form.authSetup)cancel() else if(selection.changed().isNotEmpty()||settingsChanged()>0||selection.timeline.optString("mode","match")!="match")session.confirm("取消並返回？未儲存修改將放棄；先前已儲存的設定會保留。",cancel)else cancel()
    }
    override fun tick(){
        if(android.os.SystemClock.elapsedRealtime()-pingAt>=30000){pingAt=android.os.SystemClock.elapsedRealtime();session.api.get("ping")}
    }
    override val tickIntervalMillis:Long get()=30000
    override fun close(){discovery?.close();closed.set(true);iconsPreload?.cancel(false);iconsRetry?.cancel(false);draftTimer?.cancel(false)}
    override fun lifecycle(visible:Boolean){if(visible&&initialDiscoveryPending){initialDiscoveryPending=false;openDiscovery()};if(!visible)discovery?.stop();if(session.finished)return;try{flushDraft(!visible)}finally{session.api.post("lifecycle",if(visible)"visible" else "hidden")}}
}
