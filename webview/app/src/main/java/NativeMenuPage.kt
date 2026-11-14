package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject

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
        eligible={visible&&panel==1&&legal.isEmpty()&&!wallpaper&&!session.finished&&menu.optBoolean("healthEnabled")&&!localMode()&&health.optString("protocol") in setOf("smb","webdav")&&health.optBoolean("lanAvailable")&&health.optString("status")=="offline"},
        automatic={health.optBoolean("autoDiscovery")&&healthConfirmedForOffer&&health.optString("reason") in setOf("account_missing","password_missing","discovery_unconfigured","auth_failed","share_required")})
    private fun localMode()=menu.optBoolean("healthLocal")||health.optString("protocol")=="local"
    private fun hidden(item:JSONObject)=menu.optBoolean("healthEnabled")&&localMode()&&item.optString("remote") in setOf("only","setup")
    private fun blocked(item:JSONObject)=session.finished||(menu.optBoolean("healthEnabled")&&!localMode()&&item.optString("remote") !in setOf("","setup")&&health.optString("status")!="ready")
    private fun healthModel():JSONObject {
        val state=if(localMode())"local" else if(health.optString("status") in setOf("ready","checking"))health.optString("status") else if(health.optBoolean("lanAvailable")&&connectionPrompt.scanning)"discovering" else if(health.optBoolean("lanAvailable")&&connectionPrompt.found)"setup" else health.optString("status","offline")
        val protocol=when(health.optString("protocol")){"smb"->"SMB";"webdav"->"WebDAV";else->"遠端"}
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
        val label=when(state){"local"->"本地備份";"ready"->"$protocol 已連線";"discovering"->"$protocol：掃描中";"setup"->"已發現服務，請選擇設備並設定帳密";"checking"->"$protocol：驗證連線中";else->if(health.optBoolean("lanAvailable")&&connectionPrompt.error.isNotEmpty())connectionPrompt.error else if(health.optBoolean("lanAvailable")&&connectionPrompt.searched&&!connectionPrompt.found)"未發現 SMB／WebDAV 服務，請檢查網路或手動設定" else "$protocol 未連線：$reason"}
        val button=controls.button("health:refresh",label){
            if(panel==1&&!localMode()&&health.optString("status")=="offline"&&health.optBoolean("lanAvailable"))connectionPrompt.reopen()
            else if(healthTransport==null)startHealth() else refreshHealth()
            session.emit()
        }
        val network=health.optJSONObject("network")?:JSONObject()
        val rows=network.optJSONArray("rows")?:JSONArray()
        val warning=network.optString("detail")
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
        Thread({try{api.post("remote-refresh","");api.remoteHealth{line->val update=JSONObject(line);session.execute{if(epoch==healthEpoch&&visible&&!session.finished){
            health=update
            if(health.optString("status")=="checking")sawChecking=true
            healthConfirmedForOffer=health.optString("status")=="offline"&&(sawChecking||health.optLong("generation",-1)>initialGeneration)
            if(health.optString("status") in setOf("ready","local"))connectionPrompt.connected()
            connectionPrompt.start();session.emit()
        }}}}
            catch(_:Exception){session.execute{if(epoch==healthEpoch&&visible&&!session.finished){
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
    override fun close(){connectionPrompt.close();stopHealth()}
    private var choices=emptyList<JSONObject>()
    private var panel=1
    private var revision=0L
    private var group=""
    private var text=""
    private val picked=linkedSetOf<String>()
    private var legal=""
    private var wallpaper=false
    private var licenses:JSONObject?=null
    private var search=""
    private var visible=false
    private var pingAt=0L
    private var remaining=0L
    private var submissionBlocked=false
    private var logFiles=emptyList<String>()
    private var logCategory="own"
    private var allLogFiles=emptyList<String>()
    private fun systemLog(name:String)=name.substringAfterLast("/").removePrefix("console-crash-").let{it.startsWith("logcat-")||it.startsWith("native-tombstone-")||it.startsWith("anr-")}
    private fun selectLogFiles(){logFiles=allLogFiles.filter{systemLog(it)==(logCategory=="system")};logFilePage=0;if(logFile !in logFiles)logFile=logFiles.firstOrNull().orEmpty()}
    private var logSource=""
    private var logSources=emptyList<JSONObject>()
    private fun listLogs(){allLogFiles=JSONArray(if(logSource.isEmpty())session.api.get("diagnostic-files") else session.api.post("diagnostic-files",JSONObject().put("source",logSource).toString())).strings();selectLogFiles()}
    private var logFile=""
    private var logFilePage=0
    private var logFileEmpty=false
    private var logLevel="ALL"
    private var logRecords=emptyList<JSONObject>()
    private var logEmpty=true
    private var logLimited=false
    private fun readLog(){
        logRecords=emptyList();logEmpty=false;logFileEmpty=false
        if(logFile.isEmpty()){logRecords=emptyList();logEmpty=true;logLimited=false;return}
        val result=JSONObject(session.api.post("diagnostic-view",JSONObject().put("file",logFile).put("level",logLevel).put("source",logSource).toString()))
        logRecords=result.getJSONArray("records").modelObjects();logEmpty=result.optBoolean("empty");logLimited=result.optBoolean("limited");logFileEmpty=result.optBoolean("fileEmpty")
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
        if(menu.optString("title") in setOf("日誌","日志")){
            try {
                logSources=JSONArray(session.api.get("diagnostic-sources")).modelObjects();listLogs()
                logFile=logFiles.find{it=="main.log"}?:logFiles.firstOrNull().orEmpty();readLog()
            } catch(e:Exception) {
                logRecords=emptyList()
                session.status="日誌預覽載入失敗，可重新整理或匯出除錯包。"
            }
        }
        require(choices.size<=1000&&choices.map{it.getString("id")}.distinct().size==choices.size)
        choices=choices.sortedWith(compareBy<JSONObject>{it.getString("id")=="0"}.thenBy{it.getString("id").toIntOrNull()?:Int.MAX_VALUE})
        val resume=choices.find{it.getString("id")==menu.optString("resume")}
        panel=if(menu.optString("page")=="settings"||resume?.optBoolean("setting")==true)2 else if(menu.optString("page")=="home")0 else 1
        group=if(panel==2)"" else resume?.optString("group")?:""
        val saved=session.readState()
        panel=saved.optInt("panel",panel).coerceIn(0,2)
        saved.optString("group").takeIf{g->choices.any{it.optString("group")==g}}?.let{group=it}
        text=saved.optString("text").take(2048)
        picked.addAll((saved.optJSONArray("picked")?:JSONArray()).strings().filter{id->id!="0"&&choices.any{it.getString("id")==id}})
        if(menu.optBoolean("confirm")&&picked.size>1)picked.clear()
    }
    private fun choose(id:String){
        if(session.finished||submissionBlocked)return
        require(id.split(' ').all{value->choices.any{it.getString("id")==value}})
        if(id.split(' ').any{v->choices.any{it.getString("id")==v&&(hidden(it)||blocked(it))}}){session.status="遠端尚未連線，請檢查設定或點選連線狀態重新驗證。";session.emit();return}
        submit("choose",id)
    }
    private fun cancel(){if(submissionBlocked){session.exit();return};if(!session.finished)session.finish(session.api.post("cancel",""))}
    private fun footerReturn()=menu.getJSONArray("info").length()==0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&!menu.optBoolean("powerCountdown")&&choices.any{it.getString("id")=="0"&&it.getString("label").startsWith("返回")}
    private fun returnButton()=controls.button("menu:return",if(group.isNotEmpty())"返回功能分類" else choices.find{it.getString("id")=="0"}?.getString("label")?:"取消"){back()}.put("backNavigation",true)
    private fun optionNodes():List<JSONObject>{
        if(menu.optBoolean("preparing"))return listOf(controls.node("preparing","heading","正在同步最新清單，保留既有勾選與註釋。"))
        val options=choices.filterNot{it.optBoolean("setting")||hidden(it)}
        if(group.isNotEmpty()&&options.none{it.optString("group")==group})group=""
        val groups=options.map{it.optString("group")}.filter{it.isNotEmpty()}.distinct().sortedBy{when(it){"備份","備份相關功能"->0;"恢復","恢復相關功能"->1;else->2}}
        if(groups.isNotEmpty()&&group.isEmpty())return options.filter{it.optString("group").isEmpty()&&it.getString("id")!="0"}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}}+groups.map{g->controls.button("group:$g",g,options.filter{it.optString("group")==g}.all{blocked(it)}){group=g;session.emit()}.put("navigation",true)}
        if(menu.optBoolean("input"))return listOf(controls.input("menu:input",menu.getString("title"),text){text=it},controls.button("menu:submit","確認",session.finished){require(text.length<=2048&&!text.any{it<' '});submit("input",text)}.put("primary",true))
        val nodes=mutableListOf<JSONObject>()
        if(group.isNotEmpty())nodes+=controls.node("group:heading","heading",group)
        val selectable=menu.optBoolean("multi")||menu.optBoolean("confirm")
        val duplicateResult=menu.getJSONArray("info").length()==0&&!selectable&&options.size==2&&options[0].getString("label")==options[1].getString("label")
        if(!duplicateResult)for(item in options.filter{group.isEmpty()||it.optString("group")==group}){
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
        val logChoices=choices.filter{it.optBoolean("setting")&&session.catalog.text(it.getString("label"),"zh-Hant")=="日誌"}
        val nodes=choices.filter{it.optBoolean("setting")&&it !in logChoices}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}.put("navigation",true)}.toMutableList()
        fun setting(key:String,label:String,options:List<Pair<String,String>>){nodes+=controls.select("appearance:$key",label,session.appearance.values[key]?:"",options){value->
            session.status="儲存中…";session.emit()
            try {session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;session.status="儲存成功"}
            catch(e:Exception){session.status="儲存失敗：${e.message}"}
            session.emit()
        }}
        nodes+=controls.button("wallpaper:settings","壁紙"){wallpaper=true;session.emit()}.put("navigation",true)
        setting("style","介面風格",listOf("miuix" to "Miuix","material" to "Material"))
        setting("language","介面語言",listOf("zh-Hant" to "繁體中文","zh-Hans" to "简体中文"))
        setting("appearance","外觀",listOf("system" to "跟隨系統","light" to "淺色","dark" to "深色","amoled" to "AMOLED 純黑","space" to "星空","night" to "夜空"))
        if(session.appearance.values["style"]=="material"){
            setting("material-palette","調色盤風格",NativeMaterialColors.styles.map{it to it})
            val palette=session.appearance.values["material-palette"]?:"TonalSpot"
            val specs=NativeMaterialColors.specs(palette)
            val effective=NativeMaterialColors.effectiveSpec(palette,session.appearance.values["material-spec"]?:"SPEC_2025")
            nodes+=controls.select("appearance:material-spec","色彩規格",effective,specs.map{it to it.removePrefix("SPEC_")}){value->
                try{session.api.post("material-spec",value);session.appearance.values["material-spec"]=value;session.status="儲存成功"}
                catch(e:Exception){session.status="儲存失敗：${e.message}"}
                session.emit()
            }
        }
        setting("scale","顯示大小",listOf(80,90,100,110,120,130).map{it.toString() to "$it%"})
        setting("font-adaptive","字體自適應",listOf("on" to "開啟","off" to "關閉"))
        for((key,label) in listOf("glass-blur" to "高斯模糊","monet" to "莫奈動態配色","glass-adaptive" to "自適應玻璃亮度","glass-content" to "玻璃透視內容")) {
            if(key!="monet"||session.appearance.values["appearance"] !in setOf("space","night"))setting(key,label,listOf("on" to "開啟","off" to "關閉"))
        }
        for((key,label) in listOf("glass-blur-strength" to "模糊程度","glass-light" to "透光強度","glass-transparency" to "透明度","glass-refraction" to "折射強度"))nodes+=controls.node("appearance:$key","range",label){kind,value,_->
            if(kind=="value"&&(key!="glass-blur-strength"||session.appearance.values["glass-blur"]!="off")){require(value.toInt() in 0..100);session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;session.emit()}
        }.put("disabled",key=="glass-blur-strength"&&session.appearance.values["glass-blur"]=="off").put("key",key).put("value",session.appearance.values[key]).put("min",0).put("max",100).put("step",1)
        nodes+=controls.button("appearance:reset","恢復玻璃預設"){
            for((key,value) in listOf("glass-blur" to "on","glass-blur-strength" to "100","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off","glass-content" to "off")){session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value}
            session.emit()
        }
        nodes+=controls.button("about","關於"){legal="about";session.emit()}.put("navigation",true)
        nodes+=logChoices.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),blocked(item)){choose(item.getString("id"))}.put("navigation",true)}
        val descriptions=mapOf(
            "玻璃透視內容" to "讓內容延伸至底部導覽列背後；關閉可減少文字與玻璃重疊。",
            "備份設定" to "設定備份內容、保存位置與遠端連線。",
            "恢復設定" to "設定恢復方式與應用資料處理選項。",
            "日誌" to "查看日誌等級，匯出完整工作階段的除錯包。",
            "壁紙" to "選擇程式背景，調整透明度、模糊與壓暗。",
            "介面語言" to "切換繁體中文或簡體中文，儲存後立即更新介面。",
            "外觀" to "選擇淺色、深色、跟隨系統或動態背景。",
            "顯示大小" to "調整文字與介面控制項的顯示比例。",
            "字體自適應" to "依壁紙明暗調整壁紙上的文字；卡片、彈窗與按鈕維持所選外觀的字色。",
            "高斯模糊" to "讓介面卡片與玻璃元件後方的背景柔化。",
            "莫奈動態配色" to "使用系統壁紙衍生的主題配色。",
            "自適應玻璃亮度" to "依背景亮度調整玻璃顏色與文字對比。",
            "模糊程度" to "調整背景柔化強度，需先開啟高斯模糊。",
            "透光強度" to "調整背景光線穿透玻璃的程度。",
            "透明度" to "調整玻璃元件的透明程度。",
            "折射強度" to "調整液態玻璃對背景的折射效果。",
            "恢復玻璃預設" to "將模糊、透光、透明與折射還原為預設值。",
            "關於" to "查看鳴謝、開源許可與專案資訊。")
        for(node in nodes){
            val label=session.catalog.text(node.getString("label"),"zh-Hant")
            descriptions[label]?.let{node.put("description",it)}
            nativeSettingIconLabels[label]?.let{node.put("iconKey",it)}
        }
        return nodes
    }
    private fun info():JSONArray {
        val hardware=setOf("品牌","型號","處理器","記憶體","閃存","Android")
        val versions=setOf("腳本版本","管理器","busybox版本","busybox路徑","腳本路徑","作者","支援")
        val rows=menu.getJSONArray("info").modelObjects()
        return arr(listOf("裝置資訊","執行環境","版本與路徑").mapIndexedNotNull{index,title->
            val selected=rows.filter{r->val key=session.catalog.text(r.getString("key"),"zh-Hant");val id=r.optString("id");val h=if(id.isEmpty())key in hardware else id in setOf("brand","model","processor","memory","storage","android");val v=if(id.isEmpty())key in versions else id in setOf("script-version","manager","busybox-version","busybox-path","script-path","author","support");when(index){0->h;2->v;else->!h&&!v}}
            if(selected.isEmpty())null else obj("title" to title,"rows" to arr(selected.map{r->
                val key=r.getString("key");val value=r.getString("value")
                obj("label" to key,"value" to value,"iconKey" to r.optString("id").ifEmpty{nativeHomeIconKey(session.catalog.text(key,"zh-Hant"))})
            }))
        })
    }
    override fun render(model:JSONObject){
        renderContent(model)
        connectionPrompt.model()?.let{dialog->
            if(model.optJSONObject("screen")==null){model.remove("menu");model.put("screen",controls.screen("connection-prompt","連線設定",emptyList(),emptyList()))}
            model.getJSONObject("screen").put("dialog",dialog)
            model.put("backRoute","").put("returnToMenu",false)
        }
    }
    private fun renderContent(model:JSONObject){
        remember()
        // Only advertise destinations which Back actually selects, not visit history.
        val destination=when {
            submissionBlocked->""
            wallpaper->"menu::$group"
            legal in setOf("licenses","thanks","daemons")->"menu:about:$group"
            legal.isNotEmpty()->"menu::$group"
            group.isNotEmpty()&&(menu.getJSONArray("info").length()==0||panel==1)->if(menu.getJSONArray("info").length()==0)"submenu:${session.epoch}:" else "menu::"
            else->""
        }
        model.put("backRoute",destination)
        // Only the managed ordinary submenu cancel/return contract hands back to
        // the main menu. Inputs, confirmations, countdowns and external sessions do not.
        model.put("returnToMenu",menu.optBoolean("managed")&&menu.getJSONArray("info").length()==0&&
            group.isEmpty()&&legal.isEmpty()&&!wallpaper&&!submissionBlocked&&
            !menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&
            !menu.optBoolean("powerCountdown")&&!menu.optBoolean("skipAfter")&&!menu.optBoolean("preparing"))
        if(menu.optString("title") in setOf("日誌","日志")){
            val nodes=mutableListOf<JSONObject>()
            val filters=mutableListOf<JSONObject>()
            filters+=controls.group("logs:category:row","setting",listOf(controls.select("logs:category","日誌來源",logCategory,listOf("own" to "運行日誌","system" to "系統日誌")){logCategory=it;logLevel="ALL";selectLogFiles();readLog();session.emit()}),"日誌來源").put("iconKey","log-source").put("detail","工作輸出與系統診斷分開查看；系統只收集與 SpeedBackup 相關的紀錄。").put("translateDetail",true)
            filters+=controls.group("logs:source:row","setting",listOf(controls.select("logs:source","工作階段",logSource,listOf("" to "目前工作階段")+logSources.map{it.getString("id") to (java.text.SimpleDateFormat("MM-dd HH:mm:ss",java.util.Locale.getDefault()).format(java.util.Date(it.optLong("modified")*1000))+" · "+(it.optLong("bytes")/1024)+" KB")}){
                logSource=it;logFilePage=0;logRecords=emptyList();logEmpty=true;listLogs();logFile=logFiles.find{it=="main.log"||it.endsWith("/main.log")}?:logFiles.firstOrNull().orEmpty();readLog();session.emit()
            }),"工作階段").put("iconKey","log-session").put("detail","查看目前日誌或保留的歷史除錯包").put("translateDetail",true)
            if(logFiles.isNotEmpty())filters+=controls.group("logs:file:row","setting",listOf(controls.select("logs:file","日誌檔案",logFile,logFiles.drop(logFilePage*256).take(256).map{it to it}){logFile=it;readLog();session.emit()}.apply{getJSONArray("options").modelObjects().forEach{it.put("literalLabel",true)}}),"日誌檔案").put("iconKey","logs").put("detail",if(logCategory=="system")"查看開啟頁面時收集的相關系統快照；ANR 與崩潰報告不套用等級篩選。" else "選擇這個工作階段的記錄檔").put("translateDetail",true)
            if(logCategory=="system"&&!logFile.contains("anr-")&&!logFile.contains("tombstone-"))filters+=controls.group("logs:level:row","setting",listOf(controls.select("logs:level","日誌等級",logLevel,listOf("ALL" to "全部","ERROR" to "ERROR","WARN" to "WARN","INFO" to "INFO","DEBUG" to "DEBUG","OTHER" to "未分類")+(if(logCategory=="system")listOf("VERBOSE" to "VERBOSE","FATAL" to "FATAL")else emptyList())){logLevel=it;readLog();session.emit()}),"日誌等級").put("iconKey","log-level").put("detail","只篩選畫面顯示，不影響匯出內容").put("translateDetail",true)
            if(logFiles.size>256)nodes+=controls.group("logs:file-pages","log-actions",listOf(
                controls.button("logs:file-prev","上一頁檔案",logFilePage==0){logFilePage--;session.emit()},
                controls.button("logs:file-next","下一頁檔案",(logFilePage+1)*256>=logFiles.size){logFilePage++;session.emit()}))
            val refresh=controls.button("logs:refresh","重新整理"){logSources=JSONArray(session.api.get("diagnostic-sources")).modelObjects();listLogs();if(logFile !in logFiles)logFile=logFiles.firstOrNull().orEmpty();readLog();session.emit()}
            val export=controls.select("logs:export-menu","匯出／傳送日誌","export",listOf("export" to "匯出整包日誌","share" to "傳送整包日誌")){action->if(action=="share")session.shareDiagnostics(logSource) else session.exportDiagnostics(logSource)}.put("value","").put("disabled",session.sharingDiagnostics)
            filters+=controls.group("logs:export:row","setting",listOf(export),"匯出／傳送日誌").put("iconKey","log-export").put("detail","保存整包日誌，或選擇應用程式傳送。").put("translateDetail",true)
            nodes.add(0,controls.group("logs:filters","settings-section",filters))
            nodes+=controls.node("logs:scope","text",if(logLimited)"畫面顯示近期記錄；匯出包含完整工作階段，不受等級篩選影響。" else "篩選只影響畫面；匯出包含完整工作階段。")
            if(logRecords.isNotEmpty())nodes+=controls.group("logs:content","log-content",logRecords.mapIndexed{i,row->controls.node("logs:line:$i","log",row.getString("text"))})
            if(logEmpty)nodes+=controls.node("logs:empty","text",if(logCategory=="system"&&(logFiles.isEmpty()||logFileEmpty))"暫無系統崩潰與ANR紀錄(由腳本引起)" else if(logFiles.isEmpty())"目前沒有可讀取的日誌檔案。" else if(logFileEmpty)"這個日誌檔案目前為空。" else "此等級沒有記錄，可切換「全部」查看。沒有明確等級的舊日誌列在「未分類」。")
            model.put("sectionRoute","menu:logs").put("screen",controls.screen("menu:logs","日誌",nodes,listOf(refresh,returnButton()),session.status))
            return
        }
        model.put("sectionRoute",if(wallpaper)"menu:wallpaper" else "menu:$legal:$group")
        if(wallpaper){
            val system=controls.button("wallpaper:system","使用系統壁紙"){session.importSystemWallpaper()}
            model.put("screen",controls.screen("menu:wallpaper","壁紙",emptyList(),listOf(controls.button("wallpaper:return","返回設定"){back()}),"","匯入圖片，或使用目前的系統壁紙。").put("wallpaperSystem",system.getString("id")))
            return
        }
        if(legal.isNotEmpty()){renderLegal(model);return}
        // One-shot submenu documents must not overwrite the main menu's menu::
        // snapshot. Their session key is stable for this document's whole lifetime.
        if(menu.getJSONArray("info").length()==0)model.put("sectionRoute","submenu:${session.epoch}:$group")
        val nodes=optionNodes()
        if(menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")){
            model.put("menu",obj("title" to menu.getString("title"),"eyebrow" to "SpeedBackup","subtitle" to menu.optString("description").ifEmpty{"選擇功能開始操作"},"status" to session.status,"cancel" to "離開","info" to info(),"choices" to arr(if(group.isNotEmpty())listOf(returnButton())+nodes else nodes),"appearance" to arr(appearanceNodes()),"revision" to revision,"connection" to if(menu.optBoolean("healthEnabled"))healthModel() else JSONObject()))
            model.put("navigationRoot",group.isEmpty()).put("backPanel",backPanel()?:-1)
            model.put("tabs",true).put("selected",panel).put("buttons",arr(listOf("nav-home" to "首頁","nav-actions" to "功能","nav-style" to "設定","cancel" to "離開").map{obj("id" to it.first,"label" to it.second,"disabled" to session.finished)}))
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
                rows+=controls.group("$key:row:${node.getString("id")}","setting",listOf(node),node.getString("label")).put("detail","").put("spacious",spacious).put("iconKey",node.optString("iconKey").ifEmpty{nativeSettingIconLabels[node.getString("label")].orEmpty()})
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
            nodes+=controls.button("daemon-status","Daemon 狀態"){legal="daemons";session.emit()}.put("navigation",true).put("iconKey","daemon")
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
        model.put("screen",controls.screen("menu:$legal",when(legal){"about"->"關於";"daemons"->"Daemon 狀態";"thanks"->"鳴謝";else->"開源許可"},if(legal=="about")actionRows(nodes,"about") else nodes,listOf(controls.button("legal:return","返回"){back()}),session.status))
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
        return if(!hasHome||wallpaper||legal.isNotEmpty())null else when {
            panel==2->1
            panel==1&&group.isEmpty()->0
            else->null
        }
    }
    override fun back(){
        if(connectionPrompt.showing){connectionPrompt.back();return}
        if(submissionBlocked){session.exit();return}
        val hasHome=menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")
        when{
            wallpaper->{wallpaper=false;panel=2;session.emit()}
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
    private fun remember(){if(!session.finished)session.writeState(obj("panel" to panel,"group" to group,"text" to text,"picked" to arr(picked)))}
    override fun lifecycle(visible:Boolean){this.visible=visible;if(visible){startHealth();connectionPrompt.start()}else{connectionPrompt.pause();stopHealth()};remember();if(!visible&&menu.optBoolean("powerCountdown"))cancel()}
}
