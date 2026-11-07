package io.github.yawasau.speedbackup.webview

import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class NativeConsolePage(private val session:NativeSession):NativePage{
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
    private var overall:Int?=null
    private val live=ArrayDeque<JSONObject>()
    private var history:JSONObject?=null
    private var historic=emptyList<JSONObject>()
    private var historyChunks=emptyList<List<JSONObject>>()
    private var historyChunk=0
    private var historyRevision=0L
    private var direction=""
    private val decoder=NativeLogDecoder({text,runs->append(live,text,runs)},{value->if(value.isNotBlank())progress=value})
    private fun append(target:ArrayDeque<JSONObject>,text:String,runs:List<NativeLogDecoder.Run>){
        if(Regex("^WEBUI_EVENT(?:\\s|$)").containsMatchIn(text.trimStart()))return
        if(target===live)Regex("^-?\\s*完成\\s*(\\d{1,3})%").find(text.trim())?.groupValues?.get(1)?.toIntOrNull()?.takeIf{it<=100}?.let{overall=it}
        target.add(c.ephemeral("log",text).put("spans",arr(runs.map{obj("text" to it.text,"color" to it.color,"weight" to it.weight)})))
        if(target===live)while(target.size>280||target.sumOf{it.getString("label").length}>60000)target.removeFirst()
    }
    override fun load(){
        try{
            val saved=session.api.get("history-view").trim()
            if(saved.toLongOrNull()!=null)loadHistory("resume",saved.toLong())
        }catch(e:Exception){history=null;historic=emptyList();session.status="無法接回較早日誌，已改為即時日誌：${e.message}"}
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
                        if(result.getLong("from")!=cursor){decoder.reset();append(live,"較早的輸出可透過「最早日誌」查看。",emptyList())}
                        decoder.bytes(bytes);cursor=result.getLong("next");stateRevision=if(result.has("revision")&&!result.isNull("revision"))result.getLong("revision") else null
                        if(session.status.startsWith("日誌連線失敗：")||session.status.startsWith("日誌資料處理失敗："))session.status=""
                        pending=result.optString("pending");stop=result.optString("stopStatus")
                        if(stop=="failed")session.status="停止未完成；請查看日誌中的原因，可再次點擊停止工作。"
                        else if(stop in setOf("graceful","forced")&&session.status.startsWith("已要求停止"))session.status=""
                        if(result.optString("progress").isNotBlank())progress=result.getString("progress").replace(Regex("\u001b\\[[0-?]*[ -/]*[@-~]"),"").filter{it>=' '}
                        if(!result.isNull("rc")&&bytes.isEmpty()&&stop!="stopping"){
                            ended=true;decoder.bytes(ByteArray(0),true)
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
    private fun showHistoryChunk(index:Int){
        historyChunk=index;historic=historyChunks[index];historyRevision++
        session.writeState(obj("historyFrom" to history!!.getLong("from"),"historyChunk" to index))
    }
    private fun loadHistory(which:String,resume:Long=0){
        if(which=="before"&&historyChunk>0){direction=which;showHistoryChunk(historyChunk-1);return}
        if(which=="after"&&historyChunk+1<historyChunks.size){direction=which;showHistoryChunk(historyChunk+1);return}
        var request=when(which){"resume"->"after\t$resume";"head"->"head";"after"->"after\t${history!!.getLong("next")}";else->history?.let{"before\t${it.getLong("from")}"}?:"tail"}
        var page=JSONObject(session.api.post("history",request))
        if(history==null&&which=="before"&&page.getLong("from")>0){request="before\t${page.getLong("from")}";page=JSONObject(session.api.post("history",request))}
        val rows=ArrayDeque<JSONObject>();NativeLogDecoder({text,runs->append(rows,text,runs)},{ }).bytes(android.util.Base64.decode(page.getString("data"),android.util.Base64.DEFAULT),true)
        val chunks=partitionHistoryRows(rows)
        historyChunks=chunks;history=page;direction=which
        val saved=session.readState()
        val index=if(which=="resume"&&saved.optLong("historyFrom",-1)==page.getLong("from"))saved.optInt("historyChunk").coerceIn(0,chunks.lastIndex)else if(which=="before")chunks.lastIndex else 0
        showHistoryChunk(index)
        session.api.post("history-view",page.getLong("from").toString())
    }
    private fun latest(){history=null;historic=emptyList();historyChunks=emptyList();historyChunk=0;session.writeState(JSONObject());direction="live";historyRevision++;session.api.post("history-view","live");session.emit()}
    override fun render(model:JSONObject){
        val older=c.button("console:older","較早日誌",(history?.optLong("from")==0L&&historyChunk==0)){loadHistory("before");session.emit()}
        val percent=Regex("(?:^|[^0-9])([0-9]{1,3}(?:\\.[0-9]+)?)\\s*%").find(progress)?.groupValues?.get(1)?.toDoubleOrNull()?.takeIf{it<=100}
        val rows=mutableListOf<JSONObject>()
        overall?.let{rows+=obj("key" to "overall","label" to "整體進度 $it%","value" to it/100.0,"visible" to !ended,"indeterminate" to false)}
        // Terminal text bars remain in the log; never duplicate their glyphs in the native card.
        val terminalBar=Regex("(?:%|[0-9]+/[0-9]+)\\s*\\[[\\s█▓▒░■□▏▎▍▌▋▊▉\\\\/━─=><.\\-]*\\]").containsMatchIn(progress)
        if(!terminalBar)rows+=obj("key" to "phase","label" to if(pending.isNotEmpty()&&!ended)"點擊繼續查看下一步" else progress,"value" to ((percent?:0.0)/100),"visible" to (!ended&&pending.isEmpty()),"indeterminate" to (percent==null))
        val animate=!ended&&!session.appearance.apply(JSONObject()).getBoolean("reducedMotion")
        val nodes=mutableListOf(c.node("console:status","progress").put("rows",arr(rows)).put("animate",animate).put("motion",animate&&session.appearance.dark()),c.node("console:heading","heading","執行日誌"),c.group("console:controls","controls",listOf(c.button("console:follow","跟隨最新"){latest()}.put("follow",true),c.group("console:history","log-actions",listOf(c.button("console:head","最早日誌",(history?.optLong("from")==0L&&historyChunk==0)){loadHistory("head");session.emit()},older,c.button("console:newer","較新日誌",history==null||(historyChunk==historyChunks.lastIndex&&history!!.getLong("next")>=history!!.getLong("total"))){loadHistory("after");session.emit()},c.button("console:live","即時日誌"){latest()}.put("follow",true))))))
        nodes+=if(history!=null)historic else live.toList()
        if(rows.isEmpty())nodes.removeAt(0)
        val footer=mutableListOf<JSONObject>()
        if(ended)footer+=c.button("console:close","關閉"){session.api.post("close","");session.exit()}
        else{
            if(pending.isNotEmpty()&&stop!="stopping")footer+=c.button("console:continue","繼續"){val receipt=pending;if(receipt.isNotEmpty()){session.api.post("continue",receipt);pending="";session.emit()}}
            footer+=c.button("console:stop","停止工作",stop=="stopping"){session.confirm("停止目前工作？執行中的備份／恢復會中斷。"){session.status=session.api.post("stop","stop-current-job");stop="stopping";session.emit()}}
        }
        val screen=c.screen("console",title,nodes,footer,session.status.ifEmpty{if(ended)"原工作已結束，不會自動再跑一次" else "啟動後可關閉終端，工作會繼續執行"},"已連線 · 關閉畫面或終端不會中止作業")
        screen.put("history",obj("active" to (history!=null),"loading" to false,"revision" to historyRevision,"direction" to direction,"canLoadOlder" to (history?.optLong("from")!=0L||historyChunk>0),"olderId" to older.getString("id")))
        model.put("screen",screen).put("sectionRoute","console")
    }
    override fun action(value:String){when(value){"back","close"->back()}}
    override fun back(){if(history!=null){latest();return};if(ended)session.api.post("close","");session.exit()}
    override fun close(){closed.set(true);polling.shutdownNow()}
}
