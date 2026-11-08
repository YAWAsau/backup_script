package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject

/** Native owner of menu choices. A successful submission is terminal and never retried. */
internal class NativeMenuPage(private val session:NativeSession):NativePage {
    private val controls get()=session.controls
    private lateinit var menu:JSONObject
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
    private fun submit(route:String,value:String){
        if(session.finished||submissionBlocked)return
        try{session.finish(session.api.post(route,value))}
        catch(e:java.io.IOException){
            if(e !is NativeApi.ApiFailure){submissionBlocked=true;session.status="提交結果尚未確認，已停用重複提交。請返回執行日誌確認工作狀態。";session.emit()}
            else throw e
        }
    }
    override fun load(){
        menu=JSONObject(session.api.get("menu"))
        require(menu.getJSONArray("info").length()<=256)
        choices=menu.getJSONArray("choices").modelObjects()
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
        submit("choose",id)
    }
    private fun cancel(){if(submissionBlocked){session.exit();return};if(!session.finished)session.finish(session.api.post("cancel",""))}
    private fun footerReturn()=menu.getJSONArray("info").length()==0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")&&!menu.optBoolean("powerCountdown")&&choices.any{it.getString("id")=="0"&&it.getString("label").startsWith("返回")}
    private fun returnButton()=controls.button("menu:return",if(group.isNotEmpty())"返回功能分類" else choices.find{it.getString("id")=="0"}?.getString("label")?:"取消"){back()}
    private fun optionNodes():List<JSONObject>{
        if(menu.optBoolean("preparing"))return listOf(controls.node("preparing","heading","正在同步最新清單，保留既有勾選與註釋。"))
        val options=choices.filterNot{it.optBoolean("setting")}
        val groups=options.map{it.optString("group")}.filter{it.isNotEmpty()}.distinct().sortedBy{when(it){"備份","備份相關功能"->0;"恢復","恢復相關功能"->1;else->2}}
        if(groups.isNotEmpty()&&group.isEmpty())return options.filter{it.optString("group").isEmpty()&&it.getString("id")!="0"}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),session.finished){choose(item.getString("id"))}}+groups.map{g->controls.button("group:$g",g){group=g;session.emit()}}
        if(menu.optBoolean("input"))return listOf(controls.input("menu:input",menu.getString("title"),text){text=it},controls.button("menu:submit","確認",session.finished){require(text.length<=2048&&!text.any{it<' '});submit("input",text)}.put("primary",true))
        val nodes=mutableListOf<JSONObject>()
        if(group.isNotEmpty())nodes+=controls.node("group:heading","heading",group)
        val selectable=menu.optBoolean("multi")||menu.optBoolean("confirm")
        val duplicateResult=menu.getJSONArray("info").length()==0&&!selectable&&options.size==2&&options[0].getString("label")==options[1].getString("label")
        if(!duplicateResult)for(item in options.filter{group.isEmpty()||it.optString("group")==group}){
            val id=item.getString("id")
            if(id=="0"&&(groups.isNotEmpty()||footerReturn()))continue
            nodes+=controls.button("choice:$id",item.getString("label"),session.finished){
                if(selectable&&id!="0"){
                    if(menu.optBoolean("confirm")){picked.clear();picked.add(id)}else if(!picked.remove(id))picked.add(id)
                    session.emit()
                }else choose(id)
            }.put("selected",id in picked)
        }
        if(selectable)nodes+=controls.button("menu:submit","確認所選項目",session.finished){if(picked.isEmpty()){session.status="請先點選項目，再確認。";session.emit()}else choose(picked.joinToString(" "))}.put("primary",true)
        return nodes
    }
    private fun appearanceNodes():List<JSONObject>{
        val nodes=choices.filter{it.optBoolean("setting")}.map{item->controls.button("choice:${item.getString("id")}",item.getString("label"),session.finished){choose(item.getString("id"))}}.toMutableList()
        fun setting(key:String,label:String,options:List<Pair<String,String>>){nodes+=controls.select("appearance:$key",label,session.appearance.values[key]?:"",options){value->
            session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;if(key=="language"&&menu.getJSONArray("info").length()>0)session.finish("正在重新載入語言設定…")else session.emit()
        }}
        nodes+=controls.button("wallpaper:settings","壁紙"){wallpaper=true;session.emit()}
        setting("language","介面語言",listOf("zh-Hant" to "繁體中文","zh-Hans" to "简体中文"))
        setting("appearance","外觀",listOf("system" to "跟隨系統","light" to "淺色","dark" to "深色","space" to "星空","night" to "夜空"))
        setting("scale","顯示大小",listOf(80,90,100,110,120,130).map{it.toString() to "$it%"})
        for((key,label) in listOf("glass-blur" to "高斯模糊","monet" to "莫奈動態配色","glass-adaptive" to "自適應玻璃亮度")) {
            if(key!="monet"||session.appearance.values["appearance"] !in setOf("space","night"))setting(key,label,listOf("on" to "開啟","off" to "關閉"))
        }
        for((key,label) in listOf("glass-light" to "透光強度","glass-transparency" to "透明度","glass-refraction" to "折射強度"))nodes+=controls.node("appearance:$key","range",label){kind,value,_->
            if(kind=="value"){require(value.toInt() in 0..100);session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value;session.emit()}
        }.put("key",key).put("value",session.appearance.values[key]).put("min",0).put("max",100).put("step",1)
        nodes+=controls.button("appearance:reset","恢復玻璃預設"){
            for((key,value) in listOf("glass-blur" to "on","glass-light" to "100","glass-transparency" to "100","glass-refraction" to "100","glass-adaptive" to "off")){session.api.post(key,if(key=="appearance")value+"\tfull" else value);session.appearance.values[key]=value}
            session.emit()
        }
        nodes+=controls.button("about","關於"){legal="about";session.emit()}
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
                obj("label" to key,"value" to value)
            }))
        })
    }
    override fun render(model:JSONObject){
        remember()
        model.put("sectionRoute",if(wallpaper)"menu:wallpaper" else "menu:$legal:$group")
        if(wallpaper){
            val system=controls.button("wallpaper:system","使用系統壁紙"){session.importSystemWallpaper()}
            model.put("screen",controls.screen("menu:wallpaper","壁紙",emptyList(),listOf(controls.button("wallpaper:return","返回設定"){back()}),"","匯入圖片，或使用目前的系統壁紙。").put("wallpaperSystem",system.getString("id")))
            return
        }
        if(legal.isNotEmpty()){renderLegal(model);return}
        val nodes=optionNodes()
        if(menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")){
            model.put("menu",obj("title" to menu.getString("title"),"eyebrow" to "SpeedBackup","subtitle" to menu.optString("description").ifEmpty{"選擇功能開始操作"},"status" to session.status,"cancel" to "離開","info" to info(),"choices" to arr(if(group.isNotEmpty())listOf(returnButton())+nodes else nodes),"appearance" to arr(appearanceNodes()),"revision" to revision))
            model.put("tabs",true).put("selected",panel).put("buttons",arr(listOf("nav-home" to "首頁","nav-actions" to "功能","nav-style" to "設定","cancel" to "離開").map{obj("id" to it.first,"label" to it.second,"disabled" to session.finished)}))
        }else{
            val hint=if(menu.optBoolean("powerCountdown")&&!session.finished)"剩餘 ${(remaining+999)/1000} 秒；離開畫面會取消關機請求。" else session.status
            model.put("screen",controls.screen("menu:$group",menu.getString("title"),nodes,listOf(returnButton()),hint,menu.optString("description")))
        }
    }
    private fun renderLegal(model:JSONObject){
        val nodes=mutableListOf<JSONObject>()
        if(legal=="thanks"){
            nodes+=controls.node("thanks:h1acker","contributor","h1jacker").put("detail","提供自動發現 WebDAV 方案，以及早期各種構建支持").put("translateDetail",true).put("avatar","h1acker")
            nodes+=controls.node("thanks:xayah","contributor","XayahSuSuSu").put("detail","數據備份 App 作者，提供 SELinux context 與腳本早期 Dex 支持").put("translateDetail",true).put("avatar","xayah")
            nodes+=controls.node("thanks:skkk","contributor","skkk-10p").put("detail","提供早期 native static 支持").put("translateDetail",true).put("avatar","skkk")
            nodes+=controls.node("thanks:rainy","contributor","雨季少年").put("detail","提供早期 Samba 構建與伺服器支持，遠端備份思路發起者").put("translateDetail",true).put("avatar","rainy")
        }else if(legal=="about"){
            nodes+=controls.button("thanks","鳴謝"){legal="thanks";session.emit()}
            nodes+=controls.button("licenses","開源許可"){licenses=licenses?:JSONObject(session.api.get("licenses"));require(licenses!!.getJSONArray("entries").length()<=1000);legal="licenses";session.emit()}
            nodes+=controls.button("source","檢視原始碼"){session.openLink("https://github.com/YAWAsau/backup_script")}
            nodes+=controls.button("community","QQ 群組 976613477"){session.openLink(session.catalog.communityUrl)}
        }else{
            nodes+=controls.input("license:search","搜尋開源許可",search){search=it.take(200);session.emit()}
            for((i,item) in (licenses?.optJSONArray("entries")?:JSONArray()).modelObjects().withIndex()){
                if(search.isNotBlank()&&!item.toString().contains(search,ignoreCase=true))continue
                nodes+=controls.node("license:$i","license",item.getString("name")).put("url",item.getString("url")).put("detail",listOf(item.optString("author"),item.optString("version"),item.optString("license"),item.optString("description"),item.optString("id")).filter{it.isNotBlank()}.joinToString(" · "))
            }
        }
        model.put("screen",controls.screen("menu:$legal",when(legal){"about"->"關於";"thanks"->"鳴謝";else->"開源許可"},nodes,listOf(controls.button("legal:return","返回"){back()}),session.status))
    }
    override fun action(value:String){
        if(value.startsWith("license:")){
            val id=value.substringAfter(':')
            for((i,item) in (licenses?.optJSONArray("entries")?:JSONArray()).modelObjects().withIndex())if(controls.id("license:$i")==id){session.openLink(item.getString("url"));return}
            return
        }
        if(value.startsWith("menu:")){
            val event=JSONObject(value.substringAfter(':'))
            if(event.optString("kind")=="page"&&event.optLong("revision")>=revision){panel=event.getInt("index").coerceIn(0,2);revision=event.optLong("revision");session.emit()}
        }else when(value){"nav-home"->{panel=0;session.emit()};"nav-actions"->{panel=1;session.emit()};"nav-style"->{panel=2;session.emit()};"cancel","close"->cancel();"back"->back()}
    }
    override fun back(){
        if(submissionBlocked){session.exit();return}
        val hasHome=menu.getJSONArray("info").length()>0&&!menu.optBoolean("input")&&!menu.optBoolean("multi")&&!menu.optBoolean("confirm")
        when{
            wallpaper->{wallpaper=false;panel=2;session.emit()}
            legal=="licenses"||legal=="thanks"->{legal="about";session.emit()}
            legal.isNotEmpty()->{legal="";panel=2;session.emit()}
            hasHome&&panel==2->{panel=1;session.emit()}
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
    override fun lifecycle(visible:Boolean){this.visible=visible;remember();if(!visible&&menu.optBoolean("powerCountdown"))cancel()}
}
