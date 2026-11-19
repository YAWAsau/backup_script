package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject

/**
 * End-exclusive record ranges. Records remain intact and in original order.
 * String.length is UTF-16 length, matching the native document validator.
 */
internal fun nativeMenuLogChunks(texts:List<String>):List<IntRange> {
    val chunks=ArrayList<IntRange>()
    var start=0
    while(start<texts.size){
        var end=start
        var characters=0L
        while(end<texts.size&&end-start<16){
            val length=texts[end].length.toLong()
            // Always admit the first row, even when it exceeds the budget.
            if(end>start&&characters+length>8192L)break
            characters+=length
            end++
            if(characters>=8192L)break
        }
        chunks.add(start until end)
        start=end
    }
    return chunks
}

internal fun nativeMenuGroupKey(item:JSONObject):String {
    val label=item.optString("group")
    if(label.isEmpty())return ""
    return item.optString("groupId").takeIf{it.isNotEmpty()}?.let{"id:$it"}?:"label:$label"
}
internal fun nativeMenuBackChoice(item:JSONObject):Boolean = item.getString("id")=="0"&&
    (if(item.has("role"))item.optString("role")=="back" else item.getString("label").startsWith("返回"))
internal fun nativeMenuRestoreGroup(choices:List<JSONObject>,saved:String):String? =
    choices.firstOrNull{nativeMenuGroupKey(it)==saved||it.optString("group")==saved}?.let(::nativeMenuGroupKey)
internal class NativeMenuOptionGroup(val key:String,val label:String,val rank:Int) {
    val items=ArrayList<JSONObject>()
}
internal class NativeMenuOptionIndex(choices:List<JSONObject>,hidden:(JSONObject)->Boolean,legacyRank:(String)->Int) {
    val options=ArrayList<JSONObject>()
    val ungrouped=ArrayList<JSONObject>()
    val byKey=LinkedHashMap<String,NativeMenuOptionGroup>()
    val groups:List<NativeMenuOptionGroup>
    init {
        for(item in choices){
            if(item.optBoolean("setting")||hidden(item))continue
            options.add(item)
            val key=nativeMenuGroupKey(item)
            if(key.isEmpty()){ungrouped.add(item);continue}
            byKey.getOrPut(key){
                val label=item.optString("group")
                NativeMenuOptionGroup(key,label,when(item.optString("groupId")){"backup"->0;"restore"->1;"network","tools"->2;else->legacyRank(label)})
            }.items.add(item)
        }
        groups=byKey.values.sortedBy{it.rank}
    }
}
// Choices are immutable for this page. Only local/remote mode changes visibility;
// disabled state is evaluated from live health on every render, never cached here.
internal class NativeMenuOptionCache(private val choices:List<JSONObject>,private val legacyRank:(String)->Int) {
    private var localMode:Boolean?=null
    private var index:NativeMenuOptionIndex?=null
    fun get(local:Boolean,hidden:(JSONObject)->Boolean):NativeMenuOptionIndex {
        if(index==null||localMode!=local){index=NativeMenuOptionIndex(choices,hidden,legacyRank);localMode=local}
        return index!!
    }
}

/** Native owner of menu choices. A successful submission is terminal and never retried. */
internal class NativeMenuPage(private val session:NativeSession):NativePage {
    private val controls get()=session.controls
    private lateinit var menu:JSONObject
    override val awaitHostNavigationAfterFinish:Boolean
        get()=menu.optBoolean("managed")||menu.optBoolean("preparing")
    private var health=JSONObject()
    private var healthTransport:NativeApi?=null
    private var healthEpoch=0L
    private var healthConfirmedForOffer=false
    private val connectionPrompt=NativeConnectionPrompt(session,
        eligible={visible&&locationChoice==null&&panel==1&&legal.isEmpty()&&!wallpaper&&!session.finished&&menu.optBoolean("healthEnabled")&&!localMode()&&health.optString("protocol") in setOf("smb","webdav")&&health.optBoolean("lanAvailable")&&health.optString("status")=="offline"},
        automatic={health.optBoolean("autoDiscovery")&&healthConfirmedForOffer&&health.optString("reason") in setOf("account_missing","password_missing","discovery_unconfigured","auth_failed","share_required")})
    private fun localMode()=menu.optBoolean("healthLocal")||health.optString("protocol")=="local"
    private fun hidden(item:JSONObject)=menu.optBoolean("healthEnabled")&&localMode()&&item.optString("remote") in setOf("only","setup")
    private fun blocked(item:JSONObject)=session.finished||(menu.optBoolean("healthEnabled")&&when(item.optString("remote")){
        "connected"->localMode()||health.optString("status")!="ready"
        "","setup"->false
        else->!localMode()&&health.optString("status")!="ready"
    })
    private var locationChoice:JSONObject?=null
    private var locationError=""
    private fun openLocation(){
        if(session.finished||menu.optBoolean("healthLocal"))return
        connectionPrompt.pause()
        locationError=""
        locationChoice=JSONObject(session.api.get("backup-location"))
        session.emit()
    }
    private fun saveLocation(value:String){
        val choice=locationChoice?:return
        if(value==choice.optString("value")){locationChoice=null;session.emit();return}
        try{
            val result=session.api.post("backup-location",obj("value" to value,"revision" to choice.getString("revision")).toString())
            locationChoice=null;stopHealth();session.finish(result)
        }catch(e:Exception){
            locationError="儲存失敗：${e.message}。請確認目前設定。"
            // Never infer success from an optimistic choice, even after a lost reply.
            try{locationChoice=JSONObject(session.api.get("backup-location"))}catch(_:Exception){}
            refreshHealth();session.emit()
        }
    }
    private fun healthModel():JSONObject {
        val state=if(localMode())"local" else if(health.optString("status") in setOf("ready","checking"))health.optString("status") else if(health.optBoolean("lanAvailable")&&connectionPrompt.scanning)"discovering" else if(health.optBoolean("lanAvailable")&&connectionPrompt.found)"setup" else health.optString("status","offline")
        val dialect=health.optString("smbDialect").takeIf{it in setOf("2.0.2","2.1","3.0","3.0.2","3.1.1")}.orEmpty()
        val protocol=when(health.optString("protocol")){"smb"->if(state=="ready"&&dialect.isNotEmpty())"SMB $dialect" else "SMB";"webdav"->"WebDAV";else->"遠端"}
        val reason=when(health.optString("reason")){
            "account_missing"->"未設定帳號，伺服器要求驗證"
            "password_missing"->"未設定密碼，伺服器要求驗證"
            "discovery_unconfigured"->"尚未設定連線設備，請選擇設備並設定帳密"
            "no_lan"->"未連接區域網路"
            "no_lan_cellular"->"未連接區域網路（目前僅行動網路）"
            "auth_failed"->"帳號或密碼錯誤"
            "account_unavailable"->"帳戶已鎖定、停用或密碼已過期"
            "access_denied"->"伺服器拒絕存取，請檢查權限"
            "share_required"->"未指定分享名稱"
            "share_missing"->"分享名稱或路徑不存在"
            "path_missing"->"遠端路徑不存在"
            "timeout"->"連線逾時"
            "protocol_error"->"協定或驗證方式不相容"
            "server_error"->"伺服器發生錯誤"
            "rate_limited"->"請求過於頻繁，請稍後重試"
            "discovery_failed"->"無法找到已選定的遠端設備"
            "invalid_address"->"位址格式錯誤"
            "invalid_config"->"設定無法讀取或格式錯誤"
            "local_error"->"本機連線元件初始化失敗"
            "monitor_stopped"->"連線狀態服務已中斷，請重新開啟主選單"
            "config_changed"->"設定已變更，等待重新驗證"
            else->"無法連線，請檢查位址、網路或日誌"
        }
        val label=when(state){"local"->if(menu.optBoolean("healthLocal"))"本地恢復" else "本地備份";"ready"->"$protocol 已連線";"discovering"->"$protocol：掃描中";"setup"->"已發現服務，請選擇設備並設定帳密";"checking"->"$protocol：驗證連線中";else->if(health.optBoolean("lanAvailable")&&connectionPrompt.error.isNotEmpty())connectionPrompt.error else if(health.optBoolean("lanAvailable")&&connectionPrompt.searched&&!connectionPrompt.found)"未發現 SMB／WebDAV 服務，請檢查網路或手動設定" else "$protocol 未連線：$reason"}
        val button=controls.node("health:refresh","button",label){kind,_,_->
            if(kind=="long")openLocation()
            else if(kind=="click"&&!localMode()){
                if(panel==1&&health.optString("status")=="offline"&&health.optBoolean("lanAvailable"))connectionPrompt.reopen()
                else if(healthTransport==null)startHealth() else refreshHealth()
                session.emit()
            }
        }.put("modeSwitch",!menu.optBoolean("healthLocal")&&menu.getJSONArray("info").length()>0)
        val network=health.optJSONObject("network")?:JSONObject()
        val rows=network.optJSONArray("rows")?:JSONArray()
        val warning=listOf(network.optString("detail"),if(state=="ready"&&health.optString("protocol")=="smb"&&dialect.isEmpty())"SMB 協定版本未回報" else "").filter{it.isNotEmpty()}.joinToString("\n")
        val daemons=JSONArray()
        val daemonState=health.optJSONObject("daemons")?:JSONObject()
        for((key,name) in listOf("rust" to "Rust daemon","dex" to "Dex daemon")) {
            val daemon=daemonState.optJSONObject(key)?:JSONObject()
            val status=daemon.optString("status","checking")
            val failures=daemon.optJSONArray("failures")
            val failedNames=if(failures==null)"" else (0 until failures.length()).mapNotNull{failures.optJSONObject(it)?.optString("name")?.takeIf{it.isNotBlank()}}.joinToString("、")
            val detail=when(daemon.optString("reason")){"process_exited"->"程序已結束";"timeout"->"握手逾時";"monitor_stopped"->"狀態監測已中斷";else->"握手失敗"}
            val label=when(status){"ready"->"$name 已連線";"idle"->"$name 尚未啟動";"checking"->"$name 驗證中";else->"$name 異常：${if(failedNames.isNotBlank())failedNames else detail}"}
            daemons.put(obj("state" to status,"label" to label))
        }
        return button.put("daemons",daemons).put("state",state).put("protocol",health.optString("protocol")).put("rows",rows).put("detail",warning).put("translateDetail",true)
    }
    private fun healthStreamStopped(){
        val daemons=health.optJSONObject("daemons")?:JSONObject()
        for(key in listOf("rust","dex","services")){
            val group=daemons.optJSONObject(key)?:JSONObject()
            group.put("status","offline").put("reason","monitor_stopped")
            daemons.put(key,group)
        }
        health.put("daemons",daemons)
        if(health.optString("status")!="local"){
            if(health.optString("status")!="offline"||health.optString("reason") !in setOf("no_lan","no_lan_cellular","timeout"))health.put("reason","monitor_stopped")
            health.put("status","offline")
        }
    }

    private fun startHealth(){
        if(session.finished||!menu.optBoolean("healthEnabled")||healthTransport!=null)return
        val epoch=++healthEpoch;val api=session.api.fork();healthTransport=api
        val initialGeneration=health.optLong("generation",-1);var sawChecking=false
        healthConfirmedForOffer=false
        Thread({try{api.observeRemoteHealth{line->val update=JSONObject(line);session.execute{if(epoch==healthEpoch&&visible&&!session.finished){
            health=update
            if(health.optString("status")=="checking")sawChecking=true
            healthConfirmedForOffer=health.optString("status")=="offline"&&(sawChecking||health.optLong("generation",-1)>initialGeneration)
            if(health.optString("status") in setOf("ready","local"))connectionPrompt.connected()
            connectionPrompt.start();session.emit()
        }}}}
            catch(e:Exception){session.execute{if(epoch==healthEpoch&&visible&&!session.finished){
                session.diagnostic("health-stream:"+e.javaClass.simpleName)
                healthTransport=null
                healthStreamStopped()
                session.emit()
            }}}
            finally{api.close()}},"remote-health-events").apply{isDaemon=true;start()}
    }
    private fun refreshHealth(){
        val epoch=healthEpoch
        Thread({try{session.api.fork().use{it.post("remote-refresh","")}}
            catch(_:Exception){session.execute{if(epoch==healthEpoch&&visible&&!session.finished){healthStreamStopped();session.emit()}}}},"remote-health-refresh").apply{isDaemon=true;start()}
    }
    private fun stopHealth(){++healthEpoch;healthTransport?.close();healthTransport=null}
    override fun close(){
        // Session shutdown may also call close from its deadline thread.
        // Only resource cancellation happens here; model state stays session-owned.
        synchronized(logIoLock){
            logClosed.set(true)
            logTransport?.close();logTransport=null
            logWorker.shutdownNow()
        }
        connectionPrompt.close();stopHealth()
    }
    private var choices=emptyList<JSONObject>()
    private lateinit var optionCache:NativeMenuOptionCache
    private var panel=1
    private var revision=0L
    private var group=""
    private var text=""
    private val picked=linkedSetOf<String>()
    private var legal=""
    private var wallpaper=false
    private var theme=false
    private var licenses:JSONObject?=null
    private var search=""
    private var visible=false
    private var pingAt=0L
    private var remaining=30000L
    private var submissionBlocked=false
    private var logFiles=emptyList<String>()
    private var logCategory="own"
    private var allLogFiles=emptyList<String>()
    private fun systemLog(name:String)=name.substringAfterLast("/").removePrefix("console-crash-").let{it.startsWith("logcat-")||it.startsWith("native-tombstone-")||it.startsWith("anr-")}
    private fun selectLogFiles(){logFiles=allLogFiles.filter{systemLog(it)==(logCategory=="system")};logFilePage=0;if(logFile !in logFiles)logFile=logFiles.firstOrNull().orEmpty()}
    private var logSource=""
    private var logSources=emptyList<JSONObject>()
    private var logFile=""
    private var logFilePage=0
    private var logFileEmpty=false
    private var logLevel="ALL"
    private var logRecords=emptyList<JSONObject>()
    private var logRecordChunks=emptyList<IntRange>()
    private var logEmpty=true
    private var logLimited=false
    private val logIoLock=Any()
    private val logClosed=java.util.concurrent.atomic.AtomicBoolean()
    private val logWorker=java.util.concurrent.ThreadPoolExecutor(
        1,1,0L,java.util.concurrent.TimeUnit.MILLISECONDS,
        java.util.concurrent.ArrayBlockingQueue<Runnable>(1),
        java.util.concurrent.ThreadFactory{r->Thread(r,"native-log-reader").apply{isDaemon=true}})
    // Transport access is protected by logIoLock, including deadline-thread close.
    private var logTransport:NativeApi?=null
    private var logGeneration=0L
    private var logLoading=false
    private var logError=""
    private fun readLog(preferMain:Boolean=false){
        if(logClosed.get()||session.finished)return
        val generation=++logGeneration
        logRecordChunks=emptyList()
        // Snapshot every filter on the session executor. Never read mutable
        // page/session selection state from the worker.
        val source=logSource
        val category=logCategory
        val level=logLevel
        val requestedFile=logFile
        val oldFiles=logFiles
        logLoading=true;logError=""
        logRecords=emptyList();logEmpty=false;logFileEmpty=false;logLimited=false
        synchronized(logIoLock){
            if(logClosed.get())return
            logTransport?.close()
            logTransport=null
            // Keep at most the active read and the latest pending read.
            logWorker.queue.clear()
            val transport=session.api.fork()
            logTransport=transport
            logWorker.execute {
                try{
                    transport.use { reader->
                        val sources=JSONArray(reader.get("diagnostic-sources")).modelObjects()
                        val files=JSONArray(if(source.isEmpty())reader.get("diagnostic-files")
                            else reader.post("diagnostic-files",JSONObject().put("source",source).toString())).strings()
                        val filtered=files.filter{systemLog(it)==(category=="system")}
                        val file=if(!preferMain&&requestedFile in filtered)requestedFile
                            else filtered.find{it=="main.log"||it.endsWith("/main.log")}?:filtered.firstOrNull().orEmpty()
                        val result=if(file.isEmpty())null else JSONObject(reader.post("diagnostic-view",
                            JSONObject().put("file",file).put("level",level).put("source",source).toString()))
                        val records=result?.getJSONArray("records")?.modelObjects()?:emptyList()
                        // Validate before handing the result to render.
                        val recordChunks=nativeMenuLogChunks(records.map{it.getString("text")})
                        sources.forEach{it.getString("id")}
                        session.execute{
                            if(!logClosed.get()&&!session.finished&&generation==logGeneration&&
                                source==logSource&&category==logCategory&&level==logLevel){
                                logSources=sources;allLogFiles=files;logFiles=filtered;logFile=file
                                if(oldFiles!=filtered)logFilePage=0
                                logRecords=records
                                logRecordChunks=recordChunks
                                logEmpty=result==null||records.isEmpty()
                                logLimited=result?.optBoolean("limited")?:false
                                logFileEmpty=result?.optBoolean("fileEmpty")?:false
                                logLoading=false;logError=""
                                session.emit()
                            }
                        }
                    }
                }catch(_:Exception){
                    session.execute{
                        if(!logClosed.get()&&!session.finished&&generation==logGeneration){
                            logLoading=false;logEmpty=false
                            logError="日誌預覽載入失敗，可重新整理或匯出除錯包。"
                            // Do not overwrite export/share status or expose exception bodies.
                            session.emit()
                        }
                    }
                }finally{
                    transport.close()
                    synchronized(logIoLock){if(logTransport===transport)logTransport=null}
                }
            }
        }
    }
    private fun submit(route:String,value:String){
        if(session.finished||submissionBlocked)return
        try{val result=session.api.post(route,value);stopHealth();session.finish(result)}
        catch(e:java.io.IOException){
            if(e !is NativeApi.ApiFailure){submissionBlocked=true;session.status="提交結果尚未確認，已停用重複提交。請返回執行日誌確認工作狀態。";session.emit()}
            else throw e
        }
    }
    override fun load(){
        menu=JSONObject(session.api.get("menu"))
        health=menu.optJSONObject("health")?:JSONObject()
        require(menu.getJSONArray("info").length()<=256)
        choices=menu.getJSONArray("choices").modelObjects()
        require(choices.size<=1000&&choices.map{it.getString("id")}.distinct().size==choices.size)
        choices=choices.sortedWith(compareBy<JSONObject>{it.getString("id")=="0"}.thenBy{it.getString("id").toIntOrNull()?:Int.MAX_VALUE})
        optionCache=NativeMenuOptionCache(choices,session.catalog::groupOrder)
        val resume=choices.find{it.getString("id")==menu.optString("resume")}
        panel=if(menu.optString("page")=="settings"||resume?.optBoolean("setting")==true)2 else if(menu.optString("page")=="home")0 else 1
        group=if(panel==2)"" else resume?.let(::nativeMenuGroupKey)?:""
        val saved=session.readState()
        panel=saved.optInt("panel",panel).coerceIn(0,2)
        // Missing/non-string state must not erase the shell's resume category.
        (saved.opt("group") as? String)?.let{savedGroup->
            // Migrate old label-based state once; new state survives translation changes.
            nativeMenuRestoreGroup(choices,savedGroup)?.let{group=it}
        }
        theme=saved.optBoolean("theme")&&panel==2
        text=saved.optString("text").take(2048)
        picked.addAll((saved.optJSONArray("picked")?:JSONArray()).strings().filter{id->id!="0"&&choices.any{it.getString("id")==id}})
        if(menu.optBoolean("confirm")&&picked.size>1)picked.clear()
        // start() emits the first loading model before worker results can apply.
        if(menu.optString("title") in setOf("日誌","日志"))readLog(preferMain=true)
    }
    private fun choose(id:String){
        if(session.finished||submissionBlocked)return
        require(id.split(' ').all{value->choices.any{it.getString("id")==value}})
        if(id.split(' ').any{v->choices.any{it.getString("id")==v&&(hidden(it)||blocked(it))}}){session.status="遠端尚未連線，請檢查設定或點選連線狀態重新驗證。";session.emit();return}
        submit("choose",id)
    }
    private fun cancel(){if(submissionBlocked){session.exit();return};if(!session.finished)session.finish(session.api.post("cancel",""))}
    private fun footerReturn()=menu.getJSONArray("info").length()==0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&!menu.optBoolean("powerCountdown")&&choices.any(::nativeMenuBackChoice)
    private fun returnButton()=controls.button("menu:return",if(group.isNotEmpty())"返回功能分類" else choices.find{it.getString("id")=="0"}?.getString("label")?:"取消"){back()}.put("backNavigation",true)
    private fun optionNodes():List<JSONObject>{
        if(menu.optBoolean("preparing"))return listOf(controls.node("preparing","loading","正在同步最新清單，保留既有勾選與註釋。").put("indicator","orbit"))
        val index=optionCache.get(localMode(),::hidden)
        val options=index.options
        if(group.isNotEmpty()&&group !in index.byKey)group=""
        val groups=index.groups
        if(groups.isNotEmpty()&&group.isEmpty())return index.ungrouped.filter{it.getString("id")!="0"}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}}+groups.map{g->controls.button("group:${g.key}",g.label,g.items.all{blocked(it)}){group=g.key;session.emit()}.put("navigation",true)}
        if(menu.optBoolean("input"))return listOf(controls.input("menu:input",menu.getString("title"),text){text=it},controls.button("menu:submit","確認",session.finished){require(text.length<=2048&&!text.any{it<' '});submit("input",text)}.put("primary",true))
        val nodes=mutableListOf<JSONObject>()
        if(group.isNotEmpty())nodes+=controls.node("group:heading","heading",index.byKey.getValue(group).label)
        val selectable=menu.optBoolean("multi")||menu.optBoolean("confirm")
        val duplicateResult=menu.getJSONArray("info").length()==0&&!selectable&&options.size==2&&options[0].getString("label")==options[1].getString("label")
        if(!duplicateResult)for(item in if(group.isEmpty())options else index.byKey.getValue(group).items){
            val id=item.getString("id")
            if(id=="0"&&(groups.isNotEmpty()||footerReturn()))continue
            nodes+=controls.button("choice:$id",item.getString("label"),blocked(item)){
                if(selectable&&id!="0"){
                    if(menu.optBoolean("confirm")){picked.clear();picked.add(id)}else if(!picked.remove(id))picked.add(id)
                    session.emit()
                }else choose(id)
            }.put("selected",id in picked).put("navigation",!selectable&&id!="0")
        }
        if(selectable)nodes+=controls.button("menu:submit","確認所選項目",session.finished){if(picked.isEmpty()){session.status="請先點選項目，再確認。";session.emit()}else choose(picked.joinToString(" "))}.put("primary",true)
        return nodes
    }
    private fun appearanceNodes():List<JSONObject>{
        val logChoices=choices.filter{it.optBoolean("setting")&&it.optString("iconKey").ifEmpty{session.catalog.settingIconKey(it.getString("label"))}=="logs"}
        val nodes=choices.filter{it.optBoolean("setting")&&it !in logChoices}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}.put("navigation",true).put("iconKey",item.optString("iconKey"))}.toMutableList()
        fun setting(key:String,label:String,options:List<Pair<String,String>>){nodes+=controls.select("appearance:$key",label,session.appearance.values[key]?:"",options){value->
            session.status="儲存中…";session.emit()
            try {session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;session.status="儲存成功"}
            catch(e:Exception){session.status="儲存失敗：${e.message}"}
            session.emit()
        }.put("iconKey",if(key=="miuix-monet")"monet" else key)}
        nodes+=controls.button("wallpaper:settings","壁紙"){wallpaper=true;session.emit()}.put("navigation",true).put("iconKey","wallpaper")
        setting("style","介面風格",listOf("miuix" to "Miuix","material" to "Material"))
        setting("language","介面語言",listOf("zh-Hant" to "繁體中文","zh-Hans" to "简体中文"))
        setting("appearance","外觀",listOf("system" to "跟隨系統","light" to "淺色","dark" to "深色","space" to "星空","night" to "夜空"))
        if(session.appearance.values["style"]=="material") {
            setting("material-palette","調色盤風格",NativeMaterialColors.styles.map{it to it})
            val palette=session.appearance.values["material-palette"]?:"TonalSpot"
            val specs=NativeMaterialColors.specs(palette)
            val effective=NativeMaterialColors.effectiveSpec(palette,session.appearance.values["material-spec"]?:"SPEC_2025")
            nodes+=controls.select("appearance:material-spec","色彩規格",effective,specs.map{it to it.removePrefix("SPEC_")}){value->
                try{session.api.post("material-spec",value);session.appearance.values["material-spec"]=value;session.status="儲存成功"}
                catch(e:Exception){session.status="儲存失敗：${e.message}"}
                session.emit()
            }.put("iconKey","material-spec")
        }
        setting("scale","顯示大小",listOf(80,90,100,110,120,130).map{it.toString() to "$it%"})
        setting("font-adaptive","字體自適應",listOf("on" to "開啟","off" to "關閉"))
        nodes+=controls.select("process-monitor","懸浮監控",if(session.processMonitorEnabled())"on" else "off",listOf("on" to "開啟","off" to "關閉")){
            session.setProcessMonitor(it=="on")
        }.put("iconKey","processor")
        nodes+=controls.node("monitor-transparency","range","懸浮監控卡片背景透明度"){kind,value,_->
            if(kind=="value")session.setProcessMonitorTransparency(value.toInt())
        }.put("iconKey","processor").put("key","monitor-transparency")
            .put("value",session.processMonitorTransparency().toString())
            .put("min",0).put("max",100).put("step",1)
            .put("description","僅調整懸浮監控卡片背景：0% 不透明，100% 透明；文字保持清晰。關閉監控時也可儲存。")
        for((key,label) in listOf("glass-blur" to "高斯模糊","monet" to "莫奈動態配色","glass-adaptive" to "自適應玻璃亮度","glass-content" to "玻璃透視內容")) {
            if(key!="monet"||session.appearance.values["style"]=="material"||(session.appearance.values["appearance"]!="night"&&session.appearance.values["appearance"]!="space")) {
                val preferenceKey=if(key=="monet"&&session.appearance.values["style"]!="material")"miuix-monet" else key
                setting(preferenceKey,label,listOf("on" to "開啟","off" to "關閉"))
            }
        }
        for((key,label) in listOf("glass-blur-strength" to "模糊程度","glass-transparency" to "透明度","glass-refraction" to "折射強度"))nodes+=controls.node("appearance:$key","range",label){kind,value,_->
            if(kind=="value"&&(key!="glass-blur-strength"||session.appearance.values["glass-blur"]!="off")){require(value.toInt() in 0..100);session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;session.emit()}
        }.put("iconKey",key).put("disabled",key=="glass-blur-strength"&&session.appearance.values["glass-blur"]=="off").put("key",key).put("value",session.appearance.values[key]).put("min",0).put("max",100).put("step",1)
        nodes+=controls.button("appearance:reset","恢復玻璃預設"){
            for((key,value) in listOf("glass-blur" to "on","glass-blur-strength" to "100","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off","glass-content" to "off")){session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value}
            session.emit()
        }.put("iconKey","reset")
        nodes+=controls.button("about","關於"){legal="about";session.emit()}.put("navigation",true).put("iconKey","about")
        nodes+=logChoices.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}.put("navigation",true).put("iconKey",item.optString("iconKey"))}
        val descriptions=mapOf(
            "style" to "選擇 Miuix 或 Material 介面風格。",
            "glass-content" to "讓內容延伸至底部導覽列背後；關閉可減少文字與玻璃重疊。",
            "backup-settings" to "設定備份內容、保存位置與遠端連線。",
            "restore-settings" to "設定恢復方式與應用資料處理選項。",
            "logs" to "查看日誌等級，匯出完整工作階段的除錯包。",
            "wallpaper" to "選擇程式背景，調整透明度、模糊與壓暗。",
            "language" to "切換繁體中文或簡體中文，儲存後立即更新介面。",
            "appearance" to "選擇淺色、深色、跟隨系統或動態背景。",
            "scale" to "調整文字與介面控制項的顯示比例。",
            "font-adaptive" to "依壁紙明暗調整壁紙上的文字；卡片、彈窗與按鈕維持所選外觀的字色。",
            "glass-blur" to "讓介面卡片與玻璃元件後方的背景柔化。",
            "monet" to "使用系統壁紙衍生的主題配色。",
            "glass-adaptive" to "依背景亮度調整玻璃顏色與文字對比。",
            "glass-blur-strength" to "調整背景柔化強度，需先開啟高斯模糊。",
            "glass-light" to "調整背景光線穿透玻璃的程度。",
            "glass-transparency" to "調整玻璃元件的透明程度。",
            "glass-refraction" to "調整液態玻璃對背景的折射效果。",
            "reset" to "將模糊、透明與折射還原為預設值。",
            "about" to "查看鳴謝、開源許可與專案資訊。")
        for(node in nodes){
            val key=node.optString("iconKey").ifEmpty{session.catalog.settingIconKey(node.getString("label"))}
            descriptions[key]?.let{node.put("description",it)}
            if(key.isNotEmpty())node.put("iconKey",key)
        }
        fun category(node:JSONObject):String {
            val key=node.optString("iconKey")
            return when {
                key=="style"->"style"
                key=="language"->"language"
                key=="processor"->"monitor"
                key in setOf("about","logs")->"about"
                node.optString("id") in choices.filter{it.optBoolean("setting")}.map{controls.id("choice:${it.getString("id")}")}->"backup"
                else->"theme"
            }
        }
        val selected=nodes.filter{(category(it)=="theme")==theme}.toMutableList()
        if(!theme){
            val entry=controls.button("theme:open","主題"){theme=true;panel=2;session.emit()}
                .put("navigation",true).put("iconKey","appearance").put("cardGroup","style")
                .put("description","調整外觀、配色與液態玻璃效果。")
            val index=selected.indexOfFirst{it.optString("iconKey")=="style"}
            selected.add(if(index<0)0 else index+1,entry)
        }
        for(node in selected)if(!node.has("cardGroup")){
            val category=category(node)
            val key=node.optString("iconKey")
            node.put("cardGroup",if(category!="theme")category else when {
                key=="wallpaper"->"wallpaper"
                key.startsWith("glass")||key=="reset"->"glass"
                key in setOf("scale","font-adaptive")->"scale"
                else->"colors"
            })
        }
        return selected
    }
    private fun info():JSONArray {
        val hardware=setOf("brand","model","processor","memory","storage","android")
        val versions=setOf("script-version","manager","busybox-version","busybox-path","script-path","author","support")
        val rows=menu.getJSONArray("info").modelObjects()
        fun identity(row:JSONObject)=row.optString("id").ifEmpty{session.catalog.homeIconKey(row.getString("key"))}
        return arr(listOf("裝置資訊","執行環境","版本與路徑").mapIndexedNotNull{index,title->
            val selected=rows.filter{r->val id=identity(r);when(index){0->id in hardware;2->id in versions;else->id !in hardware&&id !in versions}}
            if(selected.isEmpty()&&index!=1)null else obj("title" to title,"appRootAuthorization" to (index==1),"rows" to arr(selected.map{r->
                val key=r.getString("key");val value=r.getString("value")
                obj("label" to key,"value" to value,"iconKey" to identity(r))
            }))
        })
    }
    override fun render(model:JSONObject){
        renderContent(model)
        val locationDialog=locationChoice?.let{choice->
            val nodes=mutableListOf(controls.node("location:title","heading","備份位置"))
            for((value,label) in listOf("local" to "本地備份","remote" to "遠端備份"))nodes+=controls.button("location:$value",if(choice.optString("value")==value)"✓ $label" else label){saveLocation(value)}.put("primary",choice.optString("value")==value)
            if(locationError.isNotEmpty())nodes+=controls.node("location:error","text",locationError)
            nodes+=controls.button("location:cancel","取消"){locationChoice=null;session.emit()}
            obj("id" to controls.bind("location:dialog"){kind,_,_->if(kind in setOf("dismiss","cancel")){locationChoice=null;session.emit()}},"nodes" to arr(nodes))
        }
        (locationDialog?:connectionPrompt.model())?.let{dialog->
            val screen=model.optJSONObject("screen")
            if(screen!=null)screen.put("dialog",dialog)
            else model.put("overlay",controls.screen("connection-prompt","",emptyList(),emptyList()).put("dialogOnly",true).put("dialog",dialog))
            model.put("backRoute","").put("returnToMenu",false)
        }
    }
    private fun renderContent(model:JSONObject){
        remember()
        // Only advertise destinations which Back actually selects, not visit history.
        val destination=when {
            submissionBlocked->""
            wallpaper->if(theme)"menu:theme" else "menu::$group"
            theme->"menu::$group"
            legal in setOf("licenses","thanks","daemons")->"menu:about:$group"
            legal.isNotEmpty()->"menu::$group"
            group.isNotEmpty()&&(menu.getJSONArray("info").length()==0||panel==1)->if(menu.getJSONArray("info").length()==0)"submenu:${session.epoch}:" else "menu::"
            else->""
        }
        model.put("backRoute",destination)
        // Only the managed ordinary submenu cancel/return contract hands back to
        // the main menu. Inputs, confirmations, countdowns and external sessions do not.
        model.put("returnToMenu",menu.optBoolean("managed")&&menu.getJSONArray("info").length()==0&&
            group.isEmpty()&&legal.isEmpty()&&!wallpaper&&!theme&&!submissionBlocked&&
            !menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&
            !menu.optBoolean("powerCountdown")&&!menu.optBoolean("skipAfter")&&!menu.optBoolean("preparing"))
        if(menu.optString("title") in setOf("日誌","日志")){
            val nodes=mutableListOf<JSONObject>()
            val filters=mutableListOf<JSONObject>()
            filters+=controls.group("logs:category:row","setting",listOf(controls.select("logs:category","日誌來源",logCategory,listOf("own" to "運行日誌","system" to "系統日誌")){logCategory=it;logLevel="ALL";selectLogFiles();readLog();session.emit()}),"日誌來源").put("iconKey","log-source").put("detail","工作輸出與系統診斷分開查看；系統只收集與 SpeedBackup 相關的紀錄。").put("translateDetail",true)
            filters+=controls.group("logs:source:row","setting",listOf(controls.select("logs:source","工作階段",logSource,listOf("" to "目前工作階段")+logSources.map{it.getString("id") to (java.text.SimpleDateFormat("MM-dd HH:mm:ss",java.util.Locale.getDefault()).format(java.util.Date(it.optLong("modified")*1000))+" · "+(it.optLong("bytes")/1024)+" KB")}){
                logSource=it;logFilePage=0;allLogFiles=emptyList();logFiles=emptyList();logFile="";readLog(preferMain=true);session.emit()
            }),"工作階段").put("iconKey","log-session").put("detail","查看目前日誌或保留的歷史除錯包").put("translateDetail",true)
            if(logFiles.isNotEmpty())filters+=controls.group("logs:file:row","setting",listOf(controls.select("logs:file","日誌檔案",logFile,logFiles.drop(logFilePage*256).take(256).map{it to it}){logFile=it;readLog();session.emit()}.apply{getJSONArray("options").modelObjects().forEach{it.put("literalLabel",true)}}),"日誌檔案").put("iconKey","logs").put("detail",if(logCategory=="system")"查看開啟頁面時收集的相關系統快照；ANR 與崩潰報告不套用等級篩選。" else "選擇這個工作階段的記錄檔").put("translateDetail",true)
            if(logCategory=="system"&&!logFile.contains("anr-")&&!logFile.contains("tombstone-"))filters+=controls.group("logs:level:row","setting",listOf(controls.select("logs:level","日誌等級",logLevel,listOf("ALL" to "全部","ERROR" to "ERROR","WARN" to "WARN","INFO" to "INFO","DEBUG" to "DEBUG","OTHER" to "未分類")+(if(logCategory=="system")listOf("VERBOSE" to "VERBOSE","FATAL" to "FATAL")else emptyList())){logLevel=it;readLog();session.emit()}),"日誌等級").put("iconKey","log-level").put("detail","只篩選畫面顯示，不影響匯出內容").put("translateDetail",true)
            if(logFiles.size>256)nodes+=controls.group("logs:file-pages","log-actions",listOf(
                controls.button("logs:file-prev","上一頁檔案",logFilePage==0){logFilePage--;session.emit()},
                controls.button("logs:file-next","下一頁檔案",(logFilePage+1)*256>=logFiles.size){logFilePage++;session.emit()}))
            val refresh=controls.button("logs:refresh","重新整理"){readLog();session.emit()}
            val export=controls.select("logs:export-menu","匯出／傳送日誌","export",listOf("export" to "匯出整包日誌","share" to "傳送整包日誌")){action->if(action=="share")session.shareDiagnostics(logSource) else session.exportDiagnostics(logSource)}.put("value","").put("disabled",session.sharingDiagnostics)
            filters+=controls.group("logs:export:row","setting",listOf(export),"匯出／傳送日誌").put("iconKey","log-export").put("detail","保存整包日誌，或選擇應用程式傳送。").put("translateDetail",true)
            nodes.add(0,controls.group("logs:filters","settings-section",filters))
            nodes+=controls.node("logs:scope","text",if(logLimited)"畫面顯示近期記錄；匯出包含完整工作階段，不受等級篩選影響。" else "篩選只影響畫面；匯出包含完整工作階段。")
            if(logLoading)nodes+=controls.node("logs:loading","loading","正在載入日誌…")
            if(logError.isNotEmpty())nodes+=controls.node("logs:error","text",logError)
            for(range in logRecordChunks){
                nodes+=controls.group("logs:content:${range.first}","log-content",
                    range.map{i->val row=logRecords[i];controls.node("logs:line:$i","log",row.getString("text"))})
            }
            if(logEmpty)nodes+=controls.node("logs:empty","text",if(logCategory=="system"&&(logFiles.isEmpty()||logFileEmpty))"暫無系統崩潰與ANR紀錄(由腳本引起)" else if(logFiles.isEmpty())"目前沒有可讀取的日誌檔案。" else if(logFileEmpty)"這個日誌檔案目前為空。" else "此等級沒有記錄，可切換「全部」查看。沒有明確等級的舊日誌列在「未分類」。")
            model.put("sectionRoute","menu:logs").put("screen",controls.screen("menu:logs","日誌",nodes,listOf(refresh,returnButton()),session.status))
            return
        }
        // Shell subpages open a new HTTP menu; retain the main viewport for this run/config.
        menu.optString("viewportScope").takeIf{it.isNotEmpty()}?.let{model.put("resumeSession","menu:"+it)}
        model.put("sectionRoute",if(wallpaper)"menu:wallpaper" else if(theme)"menu:theme" else "menu:$legal:$group")
        if(wallpaper){
            val system=controls.button("wallpaper:system","使用系統壁紙"){session.importSystemWallpaper()}
            model.put("screen",controls.screen("menu:wallpaper","壁紙",emptyList(),listOf(controls.button("wallpaper:return","返回設定"){back()}),"","匯入圖片，或使用目前的系統壁紙。").put("wallpaperSystem",system.getString("id")))
            return
        }
        if(legal.isNotEmpty()){renderLegal(model);return}
        // One-shot submenu documents must not overwrite the main menu's menu::
        // snapshot. Their session key is stable for this document's whole lifetime.
        if(menu.getJSONArray("info").length()==0)model.put("sectionRoute","submenu:${session.epoch}:$group")
        if(menu.optBoolean("powerCountdown")){
            val actions=controls.group("power:actions","row",listOf(
                controls.button("power:cancel","取消",session.finished){cancel()},
                controls.button("power:send","送出",session.finished||submissionBlocked){choose("1")}.put("primary",true)
            )).put("dialogAction",true)
            val dialogNodes=listOfNotNull(
                controls.node("power:title","heading",menu.getString("title")).put("trailingNumber",((remaining+999)/1000).toString()),
                controls.node("power:hint","text","倒數結束後自動送出關機請求；離開畫面會取消。"),
                controls.node("power:status","text",session.status).takeIf{session.status.isNotBlank()},
                actions
            )
            model.put("backRoute","").put("returnToMenu",false)
                .put("screen",controls.screen("power-countdown","",emptyList(),emptyList())
                    .put("dialogOnly",true)
                    .put("dialog",obj("id" to controls.bind("power:dialog"){kind,_,_->if(kind in setOf("dismiss","cancel"))cancel()},"nodes" to arr(dialogNodes))))
            return
        }
        if(menu.optBoolean("prompt")){
            val nodes=mutableListOf(controls.node("prompt:title","heading",menu.getString("title")))
            menu.optString("description").takeIf{it.isNotBlank()}?.let{nodes+=controls.node("prompt:description","text",it)}
            if(session.status.isNotBlank())nodes+=controls.node("prompt:status","text",session.status)
            val options=optionNodes().toMutableList()
            val zero=choices.find{it.getString("id")=="0"}
            val cancel=controls.button("prompt:cancel",zero?.getString("label")?:"取消",session.finished){if(zero!=null&&!menu.optBoolean("input"))choose("0") else cancel()}
            options.removeAll{it.optString("id")==controls.id("choice:0")}
            if(menu.optBoolean("preparing")){
                nodes+=options
                nodes+=controls.group("prompt:actions","row",listOf(cancel)).put("dialogAction",true)
            }else if(menu.optBoolean("input")||menu.optBoolean("multi")||menu.optBoolean("confirm")){
                val submit=options.lastOrNull{it.optString("id")==controls.id("menu:submit")}
                if(submit!=null)options.remove(submit)
                nodes+=options
                nodes+=controls.group("prompt:actions","row",listOfNotNull(cancel,submit)).put("dialogAction",true)
            }else if(options.size<=1){
                nodes+=controls.group("prompt:actions","row",listOf(cancel)+options.map{it.put("navigation",false).put("primary",true)}).put("dialogAction",true)
            }else{
                nodes+=options.map{it.put("navigation",false)}
                nodes+=controls.group("prompt:actions","row",listOf(cancel)).put("dialogAction",true)
            }
            model.put("backRoute","").put("returnToMenu",false).put("prompt",true)
                .put("screen",controls.screen("prompt","",emptyList(),emptyList()).put("dialogOnly",true)
                    .put("dialog",obj("id" to controls.bind("prompt:dialog"){kind,_,_->if(kind in setOf("dismiss","cancel"))cancel()},"nodes" to arr(nodes))))
            return
        }
        val nodes=optionNodes()
        if(menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")){
            model.put("menu",obj("title" to "SpeedBackup","eyebrow" to "","subtitle" to "快速安全的資料管理","status" to session.status,"cancel" to "離開","info" to info(),"choices" to arr(if(group.isNotEmpty())listOf(returnButton())+nodes else nodes),"appearance" to arr(appearanceNodes()),"themePage" to theme,"themeBack" to (if(theme)controls.button("theme:return","返回設定"){back()} else JSONObject()),"revision" to revision,"connection" to if(menu.optBoolean("healthEnabled"))healthModel() else JSONObject()))
            if(theme){
                model.getJSONObject("menu").put("title","主題").put("subtitle","").put("connection",JSONObject())
            }
            model.put("navigationRoot",group.isEmpty()&&!theme).put("backPanel",backPanel()?:-1)
            model.put("tabs",!theme).put("selected",panel).put("buttons",arr((if(theme)emptyList() else listOf("nav-home" to "首頁","nav-actions" to "功能","nav-style" to "設定","cancel" to "離開")).map{obj("id" to it.first,"label" to it.second,"disabled" to session.finished)}))
        }else{
            val hint=if(menu.optBoolean("powerCountdown")&&!session.finished)"剩餘 ${(remaining+999)/1000} 秒；離開畫面會取消關機請求。" else session.status
            model.put("screen",controls.screen("menu:$group",menu.getString("title"),if(!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&!menu.optBoolean("powerCountdown"))actionRows(nodes,"menu:$group") else nodes,listOf(returnButton()),hint,menu.optString("description")))
        }
    }
    /** Group ordinary menu actions without changing callbacks or selection screens. */
    private fun actionRows(nodes:List<JSONObject>,key:String):List<JSONObject>{
        val spacious=key.startsWith("menu:")&&nodes.size in 1..6&&nodes.all{it.optString("kind")=="button"}
        val result=mutableListOf<JSONObject>()
        val rows=mutableListOf<JSONObject>()
        var section=0
        fun flush(){if(rows.isNotEmpty()){result+=controls.group("$key:section:${section++}","settings-section",rows.toList());rows.clear()}}
        for(node in nodes){
            if(node.optString("kind")=="button"&&!node.optBoolean("primary")&&!node.optBoolean("selected")){
                node.put("navigation",true)
                rows+=controls.group("$key:row:${node.getString("id")}","setting",listOf(node),node.getString("label")).put("detail","").put("spacious",spacious).put("iconKey",node.optString("iconKey").ifEmpty{session.catalog.settingIconKey(node.getString("label"))})
            }else{flush();result+=node}
        }
        flush();return result
    }
    private fun renderLegal(model:JSONObject){
        val nodes=mutableListOf<JSONObject>()
        if(legal=="thanks"){
            nodes+=controls.node("thanks:h1acker","contributor","h1jacker").put("detail","提供自動發現 WebDAV 方案，以及早期各種構建支持").put("translateDetail",true).put("avatar","h1acker")
            nodes+=controls.node("thanks:xayah","contributor","XayahSuSuSu").put("detail","數據備份 App 作者，提供 SELinux context 與腳本早期 Dex 支持").put("translateDetail",true).put("avatar","xayah")
            nodes+=controls.node("thanks:skkk","contributor","skkk-10p").put("detail","提供早期 native static 支持").put("translateDetail",true).put("avatar","skkk")
            nodes+=controls.node("thanks:rainy","contributor","雨季少年").put("detail","提供早期 Samba 構建與伺服器支持，遠端備份思路發起者").put("translateDetail",true).put("avatar","rainy")
        }else if(legal=="about"){
            nodes+=controls.button("daemon-status","Daemon 狀態"){legal="daemons";if(menu.optBoolean("healthEnabled")){if(healthTransport==null)startHealth() else refreshHealth()};session.emit()}.put("navigation",true).put("iconKey","daemon")
            nodes+=controls.button("thanks","鳴謝"){legal="thanks";session.emit()}.put("navigation",true).put("iconKey","credits")
            nodes+=controls.button("licenses","開源許可"){licenses=licenses?:JSONObject(session.api.get("licenses"));require(licenses!!.getJSONArray("entries").length()<=1000);legal="licenses";session.emit()}.put("navigation",true).put("iconKey","licenses")
            nodes+=controls.button("source","檢視原始碼"){session.openLink("https://github.com/YAWAsau/backup_script")}.put("navigation",true).put("iconKey","source")
            nodes+=controls.button("community","QQ 群組 976613477"){session.openLink(session.catalog.communityUrl)}.put("navigation",true).put("iconKey","community")
        }else if(legal=="daemons"){
            nodes+=nativeDaemonStatusNodes(controls,health,menu.optBoolean("healthEnabled")){if(healthTransport==null)startHealth() else refreshHealth()}
        }else{
            nodes+=controls.input("license:search","搜尋開源許可",search){search=it.take(200);session.emit()}
            for((i,item) in (licenses?.optJSONArray("entries")?:JSONArray()).modelObjects().withIndex()){
                if(search.isNotBlank()&&!item.toString().contains(search,ignoreCase=true))continue
                nodes+=controls.node("license:$i","license",item.getString("name")).put("url",item.getString("url")).put("detail",listOf(item.optString("author"),item.optString("version"),item.optString("license"),item.optString("description"),item.optString("id")).filter{it.isNotBlank()}.joinToString(" · "))
            }
        }
        model.put("screen",controls.screen("menu:$legal",when(legal){"about"->"關於";"daemons"->"Daemon 狀態";"thanks"->"鳴謝";else->"開源許可"},if(legal=="about")listOf(controls.node("about:brand","brand","SpeedBackup").put("literalLabel",true).put("detail",menu.optJSONArray("info")?.modelObjects()?.firstOrNull{it.optString("id")=="script-version"||session.catalog.homeIconKey(it.optString("key"))=="script-version"}?.optString("value").orEmpty()))+actionRows(nodes,"about") else nodes,listOf(controls.button("legal:return","返回"){back()}),session.status))
    }
    override fun action(value:String){
        if(value.startsWith("license:")){
            val id=value.substringAfter(':')
            for((i,item) in (licenses?.optJSONArray("entries")?:JSONArray()).modelObjects().withIndex())if(controls.id("license:$i")==id){session.openLink(item.getString("url"));return}
            return
        }
        if(value.startsWith("menu:")){
            val event=JSONObject(value.substringAfter(':'))
            if(event.optString("kind")=="page"&&event.optLong("revision")>=revision){panel=event.getInt("index").coerceIn(0,2);revision=event.optLong("revision");connectionPrompt.start();session.emit()}
        }else when(value){"nav-home"->{panel=0;session.emit()};"nav-actions"->{panel=1;connectionPrompt.start();session.emit()};"nav-style"->{panel=2;session.emit()};"cancel"->{if(menu.getJSONArray("info").length()>0)session.confirm("確定要離開 SpeedBackup？"){cancel()}else cancel()};"close"->cancel();"back"->back()}
    }
    private fun backPanel():Int? {
        val hasHome=menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")
        return if(!hasHome||wallpaper||theme||legal.isNotEmpty())null else when {
            panel==2->1
            panel==1&&group.isEmpty()->0
            else->null
        }
    }
    override fun back(){
        if(locationChoice!=null){locationChoice=null;session.emit();return}
        if(connectionPrompt.showing){connectionPrompt.back();return}
        if(submissionBlocked){session.exit();return}
        val hasHome=menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")
        when{
            wallpaper->{wallpaper=false;panel=2;session.emit()}
            theme->{theme=false;panel=2;session.emit()}
            legal in setOf("licenses","thanks","daemons")->{legal="about";session.emit()}
            legal.isNotEmpty()->{legal="";panel=2;session.emit()}
            backPanel()!=null->{panel=backPanel()!!;session.emit()}
            (!hasHome||panel==1)&&group.isNotEmpty()->{group="";session.emit()}
            footerReturn()->choose("0")
            hasHome&&panel>0->{panel=0;session.emit()}
            else->cancel()
        }
    }
    override fun tick(){
        if(session.finished||!visible)return
        if(menu.optBoolean("powerCountdown")){remaining=JSONObject(session.api.post("countdown","")).getLong("remainingMs");session.emit()}
        else if(android.os.SystemClock.elapsedRealtime()-pingAt>=30000){pingAt=android.os.SystemClock.elapsedRealtime();session.api.post("ping","")}
    }
    // A countdown is time-driven; ordinary menus only need the server lease heartbeat.
    override val tickIntervalMillis:Long get()=if(menu.optBoolean("powerCountdown"))1000 else 30000
    private fun remember(){if(!session.finished)session.writeState(obj("panel" to panel,"theme" to theme,"group" to group,"text" to text,"picked" to arr(picked)))}
    override fun lifecycle(visible:Boolean){
        val wasVisible=this.visible
        this.visible=visible
        if(visible){
            startHealth();connectionPrompt.start()
            if(!wasVisible&&menu.optBoolean("powerCountdown")&&!session.finished&&!submissionBlocked)
                remaining=JSONObject(session.api.post("countdown","")).getLong("remainingMs")
        }else{connectionPrompt.pause();stopHealth()}
        remember()
        // Initial Activity attachment may report hidden before its first resume.
        // Only leaving a displayed countdown cancels; no timer starts while hidden.
        if(!visible&&wasVisible&&menu.optBoolean("powerCountdown"))cancel()
    }
}
