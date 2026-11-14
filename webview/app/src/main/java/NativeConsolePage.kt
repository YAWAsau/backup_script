package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class NativeConsolePage(private val session:NativeSession):NativePage{
    private companion object {
        private val eventLine=Regex("^WEBUI_EVENT(?:\\s|$)")
        private val overallLine=Regex("^-?\\s*完成\\s*(\\d{1,3})%")
        private val ansiEscape=Regex("\u001b\\[[0-?]*[ -/]*[@-~]")
        private val terminalProgress=Regex("(?:%|[0-9]+/[0-9]+)\\s*\\[[\\s█▓▒░■□▏▎▍▌▋▊▉\\\\/━─=><.\\-]*\\]")
        private val percentage=Regex("(?:^|[^0-9])([0-9]{1,3}(?:\\.[0-9]+)?)\\s*%")
    }
    private val c get()=session.controls
    private val polling=Executors.newSingleThreadScheduledExecutor{r->Thread(r,"native-console-poll").apply{isDaemon=true}}
    private val closed=AtomicBoolean()
    private var cursor=0L
    private var stateRevision:Long?=null
    private var pending=""
    private var stop=""
    private var ended=false
    private var title="工作執行中"
    private var progress="正在執行，請查看下方日誌"
    private var streamProgress=""
    private var overall:Int?=null
    private val live=ArrayDeque<JSONObject>()
    private var liveCharacters=0
    private var history:JSONObject?=null
    private val historic=ArrayDeque<JSONObject>()
    private var historyRevision=0L
    private var direction=""
    private var decoder=logDecoder(live,0,true)
    private fun logDecoder(target:ArrayDeque<JSONObject>,start:Long,updateProgress:Boolean=false):NativeLogDecoder {
        var from=start
        lateinit var result:NativeLogDecoder
        result=NativeLogDecoder({text,runs->
            if(!eventLine.containsMatchIn(text.trimStart())){
                if(updateProgress)overallLine.find(text.trim())?.groupValues?.get(1)?.toIntOrNull()?.takeIf{it<=100}?.let{overall=it}
                target.add(c.ephemeral("log",text).put("from",from).put("next",result.position).put("spans",arr(runs.map{obj("text" to it.text,"color" to it.color,"weight" to it.weight)})))
                if(target===live){liveCharacters+=text.length;while(live.size>800||liveCharacters>160000)liveCharacters-=live.removeFirst().getString("label").length}
            }
            from=result.position
        },{value->if(updateProgress&&value.isNotBlank())progress=value},start)
        return result
    }
    private fun trimWindow(rows:ArrayDeque<JSONObject>,removeEnd:Boolean){
        var chars=rows.sumOf{it.getString("label").length}
        while(rows.size>800||chars>160000){val row=if(removeEnd)rows.removeLast()else rows.removeFirst();chars-=row.getString("label").length}
    }
    private fun updateHistory(){
        if(historic.isNotEmpty())history=obj("from" to historic.first().getLong("from"),"next" to historic.last().getLong("next"))
        historyRevision++
        history?.let{session.writeState(obj("historyFrom" to it.getLong("from")));session.api.post("history-view",it.getLong("from").toString())}
    }
    override fun load(){
        try{
            val page=JSONObject(session.api.post("history","tail"))
            val from=page.getLong("from");decoder=logDecoder(live,from,true)
            decoder.bytes(android.util.Base64.decode(page.getString("data"),android.util.Base64.DEFAULT));cursor=page.getLong("next")
            val saved=session.api.get("history-view").trim().toLongOrNull()
            if(saved!=null){val old=JSONObject(session.api.post("history","after\t$saved"));history=old;historic.clear();logDecoder(historic,old.getLong("from")).bytes(android.util.Base64.decode(old.getString("data"),android.util.Base64.DEFAULT));direction="resume";updateHistory()}
        }catch(e:Exception){history=null;historic.clear();session.status="無法接回較早日誌，已改為即時日誌：${e.message}"}
        finally{poll()}
    }
    private fun schedulePoll(delay:Long){
        if(closed.get()||ended)return
        try{polling.schedule({session.execute{poll()}},delay,TimeUnit.MILLISECONDS)}catch(_:java.util.concurrent.RejectedExecutionException){}
    }
    private fun poll(){
        if(closed.get())return
        // Long polling owns a separate worker; stop/continue never queue behind it.
        val request=cursor.toString()+(stateRevision?.let{"\t$it"}?:"")
        polling.execute{
            try{
                val result=JSONObject(session.api.post("output",request))
                session.execute{
                    if(!closed.get()){
                      var retryDelay:Long?=null
                      try{
                        val before=listOf(cursor,pending,stop,ended,title,progress,session.status)
                        val bytes=android.util.Base64.decode(result.getString("data"),android.util.Base64.DEFAULT)
                        if(result.getLong("from")!=cursor){live.clear();liveCharacters=0;decoder=logDecoder(live,result.getLong("from"),true)}
                        decoder.bytes(bytes);cursor=result.getLong("next");stateRevision=if(result.has("revision")&&!result.isNull("revision"))result.getLong("revision") else null
                        if(session.status.startsWith("日誌連線失敗：")||session.status.startsWith("日誌資料處理失敗："))session.status=""
                        pending=result.optString("pending");stop=result.optString("stopStatus")
                        if(stop=="failed")session.status="停止未完成；請查看日誌中的原因，可再次點擊停止工作。"
                        else if(stop in setOf("graceful","forced")&&session.status.startsWith("已要求停止"))session.status=""
                        if(result.has("progress")){
                            val nextProgress=result.getString("progress").replace(ansiEscape,"").filter{it>=' '}
                            if(nextProgress.isNotEmpty()||streamProgress.isNotEmpty())progress=nextProgress.ifBlank{"正在執行，請查看下方日誌"}
                            streamProgress=nextProgress
                        }
                        if(!result.isNull("rc")&&bytes.isEmpty()&&stop!="stopping"){
                            ended=true;session.syncShortcuts();decoder.bytes(ByteArray(0),true)
                            val rc=result.getInt("rc");title=when(stop){"graceful"->"工作已停止";"forced"->"工作已強制終止";else->if(rc==0)"工作已結束" else "工作已結束（返回碼 $rc）"}
                            progress=if(rc==0)"執行程序已結束，結果請查看下方日誌。" else "請查看日誌中的錯誤與處理結果。"
                        }else title=if(pending.isNotEmpty())"等待操作" else if(stop=="stopping")"正在停止工作" else "工作執行中"
                        if(bytes.isNotEmpty()||before!=listOf(cursor,pending,stop,ended,title,progress,session.status))session.emit()
                      }catch(e:Exception){retryDelay=2000;session.status="日誌資料處理失敗：${e.javaClass.simpleName}";session.diagnostic("native-output-decode");runCatching{session.emit()}}
                      // Immediately re-arm the server event wait. No client sampling delay.
                      finally{
                        if(!ended){
                            // Legacy/no-revision and exit-during-stop responses cannot long-wait.
                            val delay=retryDelay?:if(stateRevision==null||(!result.isNull("rc")&&stop=="stopping"))250L else null
                            if(delay!=null)schedulePoll(delay)else poll()
                        }
                      }
                    }
                }
            }catch(e:Exception){if(!closed.get())session.execute{session.status="日誌連線失敗：${e.message}";session.emit();schedulePoll(2000)}}
        }
    }
    private fun loadHistory(which:String){
        if(history==null){historic.clear();historic.addAll(live);if(historic.isEmpty())return;history=obj("from" to historic.first().getLong("from"),"next" to historic.last().getLong("next"))}
        val from=history!!.getLong("from");val next=history!!.getLong("next")
        if(which=="after"&&next>=(live.lastOrNull()?.optLong("next")?:cursor)){latest(false);return}
        val page=JSONObject(session.api.post("history",if(which=="before")"before\t$from"else"after\t$next"))
        val rows=ArrayDeque<JSONObject>()
        logDecoder(rows,page.getLong("from")).bytes(android.util.Base64.decode(page.getString("data"),android.util.Base64.DEFAULT),which=="before"||ended)
        if(which=="before"){for(row in rows.toList().asReversed())historic.addFirst(row);trimWindow(historic,true)}
        else{historic.addAll(rows);trimWindow(historic,false)}
        if(which=="after"&&historic.lastOrNull()?.optLong("next")==live.lastOrNull()?.optLong("next")){latest(false);return}
        direction=which;updateHistory()
    }
    private fun latest(publish:Boolean=true){history=null;historic.clear();session.writeState(JSONObject());direction="live";session.api.post("history-view","live");if(publish){historyRevision++;session.emit()}}
    override fun render(model:JSONObject){
        fun navigate(which:String,value:String){
            if(value.toLongOrNull()!=historyRevision)return
            try{loadHistory(which)}finally{historyRevision++;session.emit()}
        }
        val readId=c.bind("console:read"){kind,_,_->if(kind=="click"&&history==null&&live.isNotEmpty()){historic.clear();historic.addAll(live);direction="read";updateHistory();session.emit()}}
        val canOlder=(history?.optLong("from")?:live.firstOrNull()?.optLong("from")?:0)>0
        val older=c.bind("console:older"){kind,value,_->if(kind=="click"&&canOlder)navigate("before",value)}
        val newer=c.bind("console:newer"){kind,value,_->if(kind=="click"&&history!=null)navigate("after",value)}
        val terminalBar=terminalProgress.containsMatchIn(progress)
        val shownProgress=progress.ifBlank{"正在執行，請查看下方日誌"}
        val percent=percentage.find(shownProgress)?.groupValues?.get(1)?.toDoubleOrNull()?.takeIf{it<=100}
        val rows=mutableListOf<JSONObject>()
        overall?.let{rows+=obj("key" to "overall","label" to "整體進度 $it%","value" to it/100.0,"visible" to !ended,"indeterminate" to false)}
        if(!terminalBar)rows+=obj("key" to "phase","label" to if(pending.isNotEmpty()&&!ended)"點擊繼續查看下一步" else shownProgress,"value" to ((percent?:0.0)/100),"visible" to (!ended&&pending.isEmpty()),"indeterminate" to (percent==null))
        val animate=!ended&&!session.appearance.apply(JSONObject()).getBoolean("reducedMotion")
        val nodes=mutableListOf(c.node("console:status","progress").put("rows",arr(rows)).put("animate",animate).put("motion",animate&&session.appearance.dark()),c.node("console:heading","heading","執行日誌"))
        if(rows.isEmpty())nodes.removeAt(0)
        nodes+=if(history!=null)historic.toList() else live.toList()
        val footer=mutableListOf<JSONObject>()
        if(ended)footer+=c.button("console:close","關閉"){session.api.post("close","");session.exit()}
        else{
            if(pending.isNotEmpty()&&stop!="stopping")footer+=c.button("console:continue","繼續"){val receipt=pending;if(receipt.isNotEmpty()){session.api.post("continue",receipt);pending="";session.emit()}}.put("materialPrimary",true)
            footer+=c.button("console:stop","停止工作",stop=="stopping"){session.confirm("停止目前工作？執行中的備份／恢復會中斷。"){session.status=session.api.post("stop","stop-current-job");stop="stopping";session.emit()}}
        }
        val screen=c.screen("console",title,nodes,footer,session.status.ifEmpty{if(ended)"原工作已結束，不會自動再跑一次" else "啟動後可關閉終端，工作會繼續執行"},"已連線 · 關閉畫面或終端不會中止作業")
        screen.put("history",obj("active" to (history!=null),"loading" to false,"revision" to historyRevision,"direction" to direction,"canLoadOlder" to canOlder,"olderId" to older,"canLoadNewer" to (history!=null),"newerId" to newer,"readId" to readId))
        // Reading older log rows is an in-place scroll mode, not a navigation entry.
        // Keep the same route and LazyListState through live/history handoff.
        model.put("screen",screen).put("sectionRoute","console")
            .put("backRoute","").put("shortcutReady",ended)
    }
    override fun action(value:String){when(value){"back","close"->back()}}
    override fun back(){if(history!=null){latest();return};if(ended)session.api.post("close","");session.exit()}
    override fun close(){closed.set(true);polling.shutdownNow()}
}
