package io.github.yawasau.speedbackup.webview

import org.json.JSONObject

/** Read the existing event stream; opening this page never starts a daemon. */
internal fun nativeDaemonStatusNodes(controls:NativeControls,health:JSONObject,monitorAvailable:Boolean,refresh:()->Unit):List<JSONObject>{
    val nodes=mutableListOf<JSONObject>()
    nodes+=controls.node("daemon:note","text","列出本次作業的 daemon 與常駐服務；按需服務未啟動屬正常。核心服務驗證握手，其餘依程序存活判斷。").put("muted",true)
    if(monitorAvailable)nodes+=controls.button("daemon:refresh","重新檢查"){refresh()}
    else nodes+=controls.node("daemon:unavailable","text","此入口未提供狀態監測；請從完整主選單查看。").put("muted",true)
    val groups=listOf(
        Triple("rust","Rust daemon",listOf("cgfreezer","File broker","TTY relay","netwatch","Console service")),
        Triple("dex","Dex daemon",listOf("RootDaemon","WebDAV daemon","Root watchdog","WebDAV watchdog","Wi-Fi watcher")),
        Triple("services","其他常駐服務",listOf("Health monitor","Network event reader","SMB publisher")))
    val data=health.optJSONObject("daemons")?:JSONObject()
    for((key,title,expected) in groups){
        val group=data.optJSONObject(key)?:JSONObject()
        val components=group.optJSONArray("components")
        val rows=linkedMapOf<String,JSONObject>()
        if(components!=null)for(i in 0 until components.length().coerceAtMost(64)){
            val row=components.optJSONObject(i)?:continue
            val name=row.optString("name").take(100)
            if(name.isNotBlank())rows[name]=row
        }
        val unknown=group.optString("reason")=="monitor_stopped"
        val children=(expected+rows.keys).distinct().map { name ->
            val row=rows[name]
            val state=if(unknown)"unknown" else row?.optString("status","unknown")?:"unknown"
            val reason=if(unknown)"monitor_stopped" else row?.optString("reason").orEmpty()
            val label=when(state){
                "ready"->if(row?.optString("verification")=="handshake")"正常回應" else "執行中"
                "idle"->"未啟動"
                "checking"->"檢查中"
                "offline"->when(reason){"timeout"->"無回應";"process_exited"->"已結束";else->"異常"}
                else->"無法確認"
            }
            val details=mutableListOf<String>()
            if(name=="RootDaemon")details+="整合 Hidden API、AppState、通知與程序觀察"
            if(state=="ready")row?.optInt("pid",0)?.takeIf{it>1}?.let{details+="PID $it"}
            when(reason){
                "monitor_stopped"->details+="狀態監測已中斷，無法確認程序目前是否存活"
                "handshake_failed"->details+="服務握手未通過"
                "timeout"->details+="等待服務回應逾時"
                "process_exited"->details+="原程序已結束或身分已變更"
            }
            if(state=="unknown"&&reason!="monitor_stopped")details+="尚無本次作業的監測資料"
            controls.group("daemon:$key:$name","setting",listOf(controls.node("daemon:value:$key:$name","text",label)),name)
                .put("detail",details.joinToString(" · ")).put("iconKey","daemon")
        }
        nodes+=controls.node("daemon:heading:$key","heading",title)
        nodes+=controls.group("daemon:group:$key","settings-section",children)
    }
    return nodes
}
