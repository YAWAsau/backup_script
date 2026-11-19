package io.github.yawasau.speedbackup.webview

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import androidx.compose.ui.graphics.toArgb
import android.os.*
import android.provider.Settings
import android.view.*
import android.widget.*
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Manifest wiring is intentionally external:
 * non-exported, same application process, foregroundServiceType="specialUse",
 * special-use subtype property, FOREGROUND_SERVICE(_SPECIAL_USE) and
 * SYSTEM_ALERT_WINDOW permissions. No session token is persisted; the user's
 * overlay permission remains granted when monitoring is switched off.
 */
internal object ProcessMonitorState {
    private val lock=Any()
    private var generation=0L
    private var activeTicket=-1L
    private var address:String?=null
    private var running=false
    private var service:ProcessMonitorService?=null
    private val main=Handler(Looper.getMainLooper())
    private fun prefs(c:Context)=c.getSharedPreferences("native_process_monitor_v1",Context.MODE_PRIVATE)
    fun enabled(c:Context)=synchronized(lock){prefs(c).getBoolean("enabled",false)}
    fun observe(c:Context,changed:()->Unit):AutoCloseable {
        val preferences=prefs(c.applicationContext)
        val listener=android.content.SharedPreferences.OnSharedPreferenceChangeListener{_,key->if(key=="enabled")changed()}
        preferences.registerOnSharedPreferenceChangeListener(listener)
        return AutoCloseable{preferences.unregisterOnSharedPreferenceChangeListener(listener)}
    }
    fun current(ticket:Long)=synchronized(lock){generation==ticket}
    fun available()=synchronized(lock){running}
    fun report(ticket:Long,value:Boolean)=synchronized(lock){
        if(activeTicket==ticket)running=value
    }
    fun attach(value:ProcessMonitorService)=synchronized(lock){service=value}
    fun detach(value:ProcessMonitorService)=synchronized(lock){
        if(service===value)service=null
    }
    fun request(c:Context,on:Boolean):Long=synchronized(lock){
        ++generation
        address=null
        if(!on){activeTicket=-1L;running=false}
        prefs(c).edit().putBoolean("enabled",on).commit()
        generation
    }
    // Transient failures retain the user's desired setting.
    fun fail(c:Context,ticket:Long):Boolean=synchronized(lock){
        if(generation!=ticket)return@synchronized false
        address=null
        if(!Settings.canDrawOverlays(c)){
            activeTicket=-1L;running=false
            prefs(c).edit().putBoolean("enabled",false).commit()
        }
        true
    }
    fun valid(ticket:Long)=synchronized(lock){activeTicket==ticket&&ticket>=0}
    fun release(c:Context,ticket:Long){
        val next=synchronized(lock){
            if(generation!=ticket)return
            address=null
            activeTicket=-1L
            running=false
            ++generation
        }
        val app=c.applicationContext
        // A document handoff replaces its root session; give the next session
        // time to claim a new generation before retiring the old overlay.
        main.postDelayed({stop(app,next)},500)
    }
    fun stop(c:Context,ticket:Long){
        val app=c.applicationContext
        main.post{
            synchronized(lock){
                if(generation==ticket){
                    address=null
                    activeTicket=-1L
                    running=false
                    // Do not stopService a pending startForegroundService delivery.
                    // It must first be allowed to satisfy its foreground obligation.
                    service?.invalidate(app)
                }
            }
        }
    }
    fun launch(c:Context,next:String,ticket:Long,result:ResultReceiver)=synchronized(lock){
        val app=c.applicationContext
        if(generation!=ticket||!enabled(app)){
            result.send(0,null)
            return@synchronized
        }
        try{
            check(Settings.canDrawOverlays(app))
            NativeApi(next).close() // Constructor validates only; it performs no I/O.
            address=next
            app.startForegroundService(Intent(app,ProcessMonitorService::class.java)
                .setAction(ProcessMonitorService.START)
                .putExtra("ticket",ticket).putExtra("result",result))
        }catch(_:Exception){
            fail(app,ticket)
            stop(app,ticket)
            result.send(0,null)
        }
    }
    fun accept(c:Context,ticket:Long,block:(String)->Unit):Boolean=synchronized(lock){
        val next=address
        if(generation!=ticket||!enabled(c)||next==null)false
        else {activeTicket=ticket;address=null;block(next);true}
    }
}

/** Transparency affects only the card fill, never window or text alpha. */
internal fun monitorBackgroundAlpha(transparency:Int):Int =
    ((100-transparency.coerceIn(0,100))*255+50)/100

/** Own-process observation only; never launches a shell or root subprocess. */
class ProcessMonitorService:Service() {
    companion object {
        const val START="io.github.yawasau.speedbackup.MONITOR_START"
        private const val STOP="io.github.yawasau.speedbackup.MONITOR_STOP"
        private const val CHANNEL="own-process-monitor-v1"
        private const val NOTIFICATION_ID=1059
    }
    private val main=Handler(Looper.getMainLooper())
    private val worker=Executors.newSingleThreadExecutor{r->
        Thread(r,"own-process-monitor").apply{isDaemon=true}
    }
    private var nextPoll:Runnable?=null
    private var previous:Sample?=null
    private var errors=0
    private var api:NativeApi?=null
    private var address=""
    private var ticket=-1L
    private var serial=0L
    private var destroyed=false
    private var registered=false
    private var active=false
    private lateinit var wm:WindowManager
    private var panel:LinearLayout?=null
    private lateinit var rows:LinearLayout
    private lateinit var scroll:ScrollView
    private lateinit var params:WindowManager.LayoutParams
    private var appliedLayout:Triple<Int,Int,Int>?=null
    private data class RowView(
        val root:LinearLayout,
        val name:TextView,
        val metrics:TextView,
        val cpu:TextView
    )
    private val views=linkedMapOf<String,RowView>()
    private lateinit var titleView:TextView
    private lateinit var totalView:TextView
    private lateinit var closeView:TextView
    private val appearancePrefs by lazy {
        getSharedPreferences("native-appearance",Context.MODE_PRIVATE)
    }
    private val appearanceKeys=setOf(
        "style","appearance","monet","miuix-monet",
        "material-palette","material-spec","monitor-transparency"
    )
    private var appearanceRegistered=false
    private var appliedAppearance:List<Any?>?=null
    private var ink=Color.BLACK
    private var shadowInk=0xbbffffff.toInt()
    private var rowTypeface=Typeface.create("sans-serif",Typeface.NORMAL)
    private var headingTypeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)
    private val appearanceRefresh=Runnable {
        if(!destroyed)refreshAppearance()
    }
    private val appearanceListener=SharedPreferences.OnSharedPreferenceChangeListener { _,key->
        if(key==null||key in appearanceKeys){
            // Never touch views on a preference writer's thread. Coalesce commits.
            main.removeCallbacks(appearanceRefresh)
            main.post(appearanceRefresh)
        }
    }
    private var result:ResultReceiver?=null
    private val screenReceiver=object:BroadcastReceiver(){
        override fun onReceive(context:Context,intent:Intent){
            if(intent.action==Intent.ACTION_SCREEN_OFF)pause() else resume()
        }
    }
    private fun text(value:String)=NativeLanguage.text(this,value)
    private fun dp(n:Int)=(n*resources.displayMetrics.density).toInt()
    override fun onBind(intent:Intent?) : IBinder?=null
    override fun onCreate(){
        super.onCreate()
        wm=getSystemService(WindowManager::class.java)
        val filter=IntentFilter().apply{
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if(Build.VERSION.SDK_INT>=33)registerReceiver(screenReceiver,filter,Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(screenReceiver,filter)
        registered=true
        if(!appearanceRegistered){
            appearancePrefs.registerOnSharedPreferenceChangeListener(appearanceListener)
            appearanceRegistered=true
        }
        ProcessMonitorState.attach(this)
    }
    private fun notification():Notification{
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL,text("進程監控"),NotificationManager.IMPORTANCE_LOW))
        val stop=PendingIntent.getService(this,NOTIFICATION_ID,
            Intent(this,ProcessMonitorService::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this,CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle("SpeedBackup · CPU/RAM")
            .setContentText(text("進程監控")).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null,text("停止"),stop).build()).build()
    }
    private fun foreground(){
        if(Build.VERSION.SDK_INT>=34)
            startForeground(NOTIFICATION_ID,notification(),ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIFICATION_ID,notification())
    }
    private fun validOverlay()=
        !destroyed&&panel!=null&&ProcessMonitorState.valid(ticket)

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int{
        if(intent?.action==STOP){stopExplicit();return START_NOT_STICKY}
        // Even rejected deliveries must satisfy startForegroundService promptly.
        try{foreground()}catch(_:Exception){
            val incoming=intent?.getLongExtra("ticket",-1)?:-1
            ProcessMonitorState.fail(applicationContext,incoming)
            intent?.getParcelableExtra<ResultReceiver>("result")?.send(0,null)
            if(!validOverlay()){cleanup();stopSelfResult(startId)}
            return START_NOT_STICKY
        }
        if(intent?.action!=START){
            if(!validOverlay()){
                cleanup()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
            }
            return START_NOT_STICKY
        }
        val incoming=intent.getLongExtra("ticket",-1)
        val callback=intent.getParcelableExtra<ResultReceiver>("result")
        if(destroyed){
            ProcessMonitorState.fail(applicationContext,incoming)
            callback?.send(0,null)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        val accepted=ProcessMonitorState.accept(applicationContext,incoming){next->
            pause()
            address=""
            ticket=incoming
            result=callback
            try{
                check(Settings.canDrawOverlays(this))
                address=next
                if(panel==null)createPanel()
                if(!destroyed){
                    unavailable()
                    resume()
                    result?.send(1,null);result=null
                }
            }catch(_:Exception){fatal()}
        }
        if(!accepted){
            callback?.send(0,null)
            if(!validOverlay()){
                cleanup()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
            }
        }
        return START_NOT_STICKY
    }
    internal fun invalidate(context:Context){
        if(!ProcessMonitorState.valid(ticket)){
            cleanup()
            stopSelf()
        }
    }
    private fun stopExplicit(){
        val next=ProcessMonitorState.request(applicationContext,false)
        cleanup()
        ProcessMonitorState.stop(applicationContext,next)
        stopSelf()
    }
    private fun fatal(){
        ProcessMonitorState.fail(applicationContext,ticket)
        result?.send(0,null);result=null
        cleanup()
        stopSelf()
    }
    private fun unlocked():Boolean=
        getSystemService(PowerManager::class.java).isInteractive &&
        !getSystemService(KeyguardManager::class.java).isKeyguardLocked

    private fun pause(){
        active=false
        ++serial
        nextPoll?.let{main.removeCallbacks(it)}
        nextPoll=null
        // Never cancel and reuse a task/client: closing disconnects its live request.
        api?.close();api=null
        previous=null
        errors=0
        if(panel!=null)unavailable()
    }
    private fun resume(){
        if(destroyed||active||address.isEmpty()||!unlocked())return
        if(!ProcessMonitorState.valid(ticket)){invalidate(applicationContext);return}
        if(!Settings.canDrawOverlays(this)){fatal();return}
        try{
            val client=NativeApi(address)
            api=client
            active=true
            previous=null
            errors=0
            schedulePoll(++serial,client,0)
        }catch(_:Exception){fatal()}
    }
    private fun schedulePoll(run:Long,client:NativeApi,delay:Long){
        val task=Runnable{
            nextPoll=null
            if(destroyed||!active||run!=serial)return@Runnable
            if(!ProcessMonitorState.valid(ticket)){invalidate(applicationContext);return@Runnable}
            if(!Settings.canDrawOverlays(this)){fatal();return@Runnable}
            if(!unlocked()){pause();return@Runnable}
            val baseline=previous
            try{
                worker.execute{
                    var sample:Sample?=null
                    var output:Rendered?=null
                    try{
                        val value=parse(client.get("process-monitor"))
                        output=format(value,baseline)
                        sample=value
                    }catch(_:Exception){}
                    val completed=sample
                    val rendered=output
                    main.post{
                        if(!destroyed&&active&&run==serial){
                            if(!ProcessMonitorState.valid(ticket))invalidate(applicationContext)
                            else if(!Settings.canDrawOverlays(this))fatal()
                            else if(!unlocked())pause()
                            else{
                                previous=completed
                                if(rendered==null){
                                    errors=(errors+1).coerceAtMost(12)
                                    unavailable()
                                }else{
                                    errors=0
                                    ProcessMonitorState.report(ticket,true)
                                    if(totalView.text.toString()!=rendered.total)totalView.text=rendered.total
                                    totalView.contentDescription=rendered.total +
                                        ". Total CPU of backend-verified project processes; " +
                                        "100% is one core. Partial means some CPU data is unavailable."
                                    showRows(rendered.rows)
                                }
                                val wait=when{
                                    errors>=12->10000L
                                    errors>=3->5000L
                                    else->1000L
                                }
                                // Completion-driven scheduling: one request per run.
                                // The single worker also serializes retired and new runs.
                                schedulePoll(run,client,wait)
                            }
                        }
                    }
                }
            }catch(_:java.util.concurrent.RejectedExecutionException){
                if(!destroyed)fatal()
            }
        }
        nextPoll=task
        main.postDelayed(task,delay)
    }
    private data class Proc(val name:String,val pid:Long,val start:String,val ticks:Long,val rss:Long){
        val key:String get()="$pid:$start"
    }
    private data class Sample(val total:Long,val cores:Int,val processes:List<Proc>,val partial:Boolean=false)
    private fun integer(o:JSONObject,key:String,max:Long=Long.MAX_VALUE):Long{
        val v=o.get(key)
        val number=when(v){
            is Int->v.toLong()
            is Long->v
            is String->{require(v.isNotEmpty()&&v.length<=19&&v.all{it in '0'..'9'});v.toLong()}
            else->error("invalid counter")
        }
        return number.also{require(it in 0..max)}
    }
    private fun parse(raw:String):Sample{
        require(raw.length<=65536)
        val root=JSONObject(raw)
        val total=integer(root,"totalTicks")
        val cores=integer(root,"cpuCount",4096).toInt()
        require(cores>0)
        val list=root.getJSONArray("processes")
        require(list.length()<=64)
        val ids=HashSet<Long>()
        val processes=(0 until list.length()).map{
            val p=list.getJSONObject(it)
            val name=p.get("name");val start=p.get("startTime")
            require(name is String&&name.length in 1..256&&!name.any{ch->ch.isISOControl()})
            require(start is String&&start.length in 1..128&&!start.any{ch->ch.isISOControl()})
            val pid=integer(p,"pid",Int.MAX_VALUE.toLong())
            require(pid>0&&ids.add(pid))
            Proc(name,pid,start,integer(p,"cpuTicks"),integer(p,"rssBytes",1L shl 60))
        }
        return Sample(total,cores,processes,root.optBoolean("partial",false))
    }
    private data class RowData(
        val key:String,
        val name:String,
        val metrics:String?=null,
        val cpu:String?=null,
        val accessibility:String=name
    )
    private data class Rendered(
        val total:String,
        val rows:List<RowData>
    )
    private fun format(now:Sample,old:Sample?):Rendered{
        val baseline=old?.takeIf{it.cores==now.cores&&now.total>it.total}
        val prior=baseline?.processes?.associateBy{it.key}.orEmpty()
        val delta=if(baseline!=null)now.total-baseline.total else 0L
        var sum=0.0
        var valid=0
        // Only this snapshot's live rows: no old/stopped rows, and no CPU filter.
        // Rank using full numeric percentages, not formatted display strings.
        // PID/start identity breaks ties deterministically across snapshots.
        val percentages=HashMap<String,Double?>()
        val identities=now.processes.associateBy{it.key}
        val formatted=now.processes.map{p->
            val before=prior[p.key]
            var percent:Double?=null
            if(before!=null&&p.ticks>=before.ticks&&delta>0){
                val ticks=p.ticks-before.ticks
                if(ticks<=delta){
                    percent=ticks.toDouble()/delta.toDouble()*now.cores*100.0
                }
            }
            percentages[p.key]=percent
            val cpu=if(percent!=null){
                // Accumulate full-precision numeric values, never rounded strings.
                sum+=percent
                ++valid
                String.format(Locale.ROOT,"%.1f%%",percent)
            }else "—"
            val ram=if(p.rss<1048576L) "${p.rss/1024L} KB"
                else String.format(Locale.ROOT,"%.1f MB",p.rss.toDouble()/1048576.0)
            RowData(
                key=p.key,
                name=p.name,
                metrics="PID ${p.pid} · $ram",
                cpu=cpu,
                accessibility="${p.name}, PID ${p.pid}, RAM $ram, " +
                    if(percent==null) "CPU unavailable" else "CPU $cpu; 100% is one core"
            )
        }
        val total=when{
            // A missing baseline (including an empty initial snapshot) is not 0%.
            valid==0->if(now.partial) "TOTAL CPU — · partial" else "TOTAL CPU —"
            now.partial||valid<now.processes.size->
                "TOTAL CPU ${String.format(Locale.ROOT,"%.1f%%",sum)} · partial"
            else->"TOTAL CPU ${String.format(Locale.ROOT,"%.1f%%",sum)}"
        }
        val ranked=formatted.sortedWith(
            compareByDescending<RowData>{percentages[it.key]?:Double.NEGATIVE_INFINITY}
                .thenBy{identities.getValue(it.key).pid}
                .thenBy{identities.getValue(it.key).start}
        )
        return Rendered(total,ranked)
    }
    private fun styleInk(view:TextView){
        view.setTextColor(ink)
        view.typeface=rowTypeface
        view.setShadowLayer(
            resources.displayMetrics.density,
            0f,
            resources.displayMetrics.density*0.5f,
            shadowInk
        )
    }
    private fun label(value:String,size:Float=10.5f)=TextView(this).apply{
        text=value
        textSize=size
        includeFontPadding=false
        styleInk(this)
    }
    private fun refreshAppearance(){
        if(destroyed)return
        val root=panel?:return
        val appearance=NativeAppearance(this).apply{loadLocal()}
        val values=appearance.values
        val dark=appearance.dark()
        val transparency=appearancePrefs.getInt("monitor-transparency",65).coerceIn(0,100)
        val snapshot:List<Any?> = appearanceKeys.map{values[it]}+listOf(dark,transparency)
        if(appliedAppearance==snapshot)return

        val material=values["style"]=="material"
        val tint=if(material){
            NativeMaterialColors.make(
                this,dark,values["monet"]=="on",
                values["material-palette"]?:"TonalSpot",
                values["material-spec"]?:"SPEC_2025"
            ).surfaceContainerLow.toArgb()
        }else{
            val dynamic=values["miuix-monet"]=="on" &&
                values["appearance"]!="night" && values["appearance"]!="space" && Build.VERSION.SDK_INT>=31
            NativeMiuixColors.make(
                NativeMiuixColors.systemSeed(this,dark),dark,dynamic,
                "TonalSpot","SPEC_2025"
            ).surfaceContainer.toArgb()
        }
        // Theme-derived contrast only: no screen capture or background sampling.
        ink=if(dark)Color.WHITE else Color.BLACK
        shadowInk=if(dark)0xbb000000.toInt() else 0xbbffffff.toInt()
        rowTypeface=Typeface.create(
            if(material)"sans-serif" else "sans-serif-medium",Typeface.NORMAL
        )
        headingTypeface=Typeface.create(
            "sans-serif-medium",if(material)Typeface.NORMAL else Typeface.BOLD
        )
        root.background=GradientDrawable().apply{
            shape=GradientDrawable.RECTANGLE
            cornerRadius=dp(if(material)16 else 10).toFloat()
            // Default 65% transparency rounds to the original 0x59 opacity.
            // Keep title, rows, border, and window alpha unchanged.
            setColor((tint and 0x00ffffff) or (monitorBackgroundAlpha(transparency) shl 24))
            setStroke(dp(1).coerceAtLeast(1),(ink and 0x00ffffff) or 0x22000000)
        }
        root.clipToOutline=true
        styleInk(titleView)
        titleView.typeface=headingTypeface
        styleInk(totalView)
        totalView.typeface=headingTypeface
        styleInk(closeView)
        views.values.forEach{
            styleInk(it.name)
            styleInk(it.metrics)
            styleInk(it.cpu)
        }
        appliedAppearance=snapshot
        // Typeface changes affect intrinsic widths too, not just colors.
        if(root.isAttachedToWindow)reposition()
    }
    private fun createPanel(){
        params=WindowManager.LayoutParams(
            dp(220),WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply{gravity=Gravity.TOP or Gravity.LEFT;x=dp(12);y=dp(80)}
        val root=LinearLayout(this).apply{
            orientation=LinearLayout.VERTICAL
        }
        val header=LinearLayout(this).apply{gravity=Gravity.CENTER_VERTICAL}
        val title=label("SpeedBackup · CPU/RAM",10.5f).apply{
            gravity=Gravity.CENTER_VERTICAL
            setPadding(dp(8),0,0,0)
            setSingleLine(true)
            ellipsize=TextUtils.TruncateAt.END
        }
        val close=label("×",20f).apply{
            gravity=Gravity.CENTER
            contentDescription=text("關閉")
            isFocusable=true
            setOnClickListener{stopExplicit()}
        }
        titleView=title
        closeView=close
        totalView=label("TOTAL CPU —",10.5f).apply{
            setPadding(dp(8),0,dp(8),dp(3))
            // Allow wrapping instead of truncating the partial/unavailable marker.
            setHorizontallyScrolling(false)
            contentDescription=
                "Total CPU of backend-verified project processes; " +
                "100% is one core. Only running verified project processes are shown."
        }
        // Explicit compact compromise: 36dp target, not a claimed 48dp target.
        header.addView(title,LinearLayout.LayoutParams(0,dp(36),1f))
        header.addView(close,LinearLayout.LayoutParams(dp(36),dp(36)))
        var downX=0f;var downY=0f;var originX=0;var originY=0
        title.setOnTouchListener{_,e->
            when(e.actionMasked){
                MotionEvent.ACTION_DOWN->{downX=e.rawX;downY=e.rawY;originX=params.x;originY=params.y;true}
                MotionEvent.ACTION_MOVE->{
                    params.x=originX+(e.rawX-downX).toInt()
                    params.y=originY+(e.rawY-downY).toInt()
                    reposition();true
                }
                MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL->true
                else->false
            }
        }
        rows=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL}
        scroll=object:ScrollView(this){
            override fun onMeasure(widthMeasureSpec:Int,heightMeasureSpec:Int){
                val maximum=minOf(
                    dp(220),(screenSize().second*0.30f).toInt()
                ).coerceAtLeast(1)
                super.onMeasure(widthMeasureSpec,View.MeasureSpec.makeMeasureSpec(maximum,View.MeasureSpec.AT_MOST))
            }
        }.apply{
            isFillViewport=false
            isVerticalScrollBarEnabled=true
            // Explicit MATCH_PARENT keeps every row on the same right edge.
            addView(rows,android.widget.FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        }
        root.addView(header);root.addView(totalView);root.addView(scroll)
        // All label/scroll lateinits are ready before measuring themed paints.
        // Theme and size before attachment to avoid an oversized first frame.
        panel=root
        refreshAppearance()
        params.width=desiredPanelWidth(screenSize().first)
        wm.addView(root,params)
        appliedLayout=Triple(params.width,params.x,params.y)
        root.addOnLayoutChangeListener{_,_,_,_,_,_,_,_,_->reposition()}
        reposition()
    }
    @Suppress("DEPRECATION")
    private fun screenSize():Pair<Int,Int>{
        if(Build.VERSION.SDK_INT>=30){
            val metrics=wm.currentWindowMetrics
            val insets=metrics.windowInsets.getInsetsIgnoringVisibility(
                WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            return (metrics.bounds.width()-insets.left-insets.right).coerceAtLeast(1) to
                (metrics.bounds.height()-insets.top-insets.bottom).coerceAtLeast(1)
        }
        val size=android.graphics.Point()
        wm.defaultDisplay.getSize(size)
        return size.x.coerceAtLeast(1) to size.y.coerceAtLeast(1)
    }
    private fun textWidth(view:TextView,value:String=view.text.toString()):Int =
        kotlin.math.ceil(view.paint.measureText(value).toDouble()).toInt() +
            view.compoundPaddingLeft + view.compoundPaddingRight

    private fun cpuReservation(view:TextView):String {
        // Reserve for this device's full CPU capacity, not a hypothetical server.
        // Include displayed values if CPU availability changes between samples.
        val digit=('0'..'9').maxByOrNull{view.paint.measureText(it.toString())}?:'0'
        val capacityDigits=(Runtime.getRuntime().availableProcessors().coerceIn(1,4096)*100).toString().length
        val shownDigits=views.values.maxOfOrNull{it.cpu.text.toString().substringBefore('.').count{c->c.isDigit()}}?:0
        return digit.toString().repeat(maxOf(capacityDigits,shownDigits))+"."+digit+"%"
    }

    private fun desiredPanelWidth(usableWidth:Int):Int {
        // Called only after createPanel initializes all labels. Measure intrinsic
        // paint widths rather than constrained view widths (which feed back and
        // can oscillate). At the cap names ellipsize and metrics/total wrap;
        // all rows retain the same fonts and parent width.
        val total=totalView.text.toString().replace(
            Regex("(?<=TOTAL CPU )(?:[0-9]+\\.[0-9]+%|—)"),
            cpuReservation(totalView)
        )
        var desired=maxOf(
            textWidth(titleView)+dp(36),
            textWidth(totalView,total)
        )
        views.values.forEach{row->
            val cpuWidth=if(row.cpu.visibility==View.VISIBLE)
                maxOf(textWidth(row.cpu,cpuReservation(row.cpu)),textWidth(row.cpu,"—"))
            else 0
            if(cpuWidth>0){
                val lp=row.cpu.layoutParams
                if(lp.width!=cpuWidth){
                    lp.width=cpuWidth
                    row.cpu.layoutParams=lp
                }
            }
            val content=maxOf(
                textWidth(row.name)+cpuWidth,
                if(row.metrics.visibility==View.VISIBLE)textWidth(row.metrics) else 0
            )
            desired=maxOf(desired,content+row.root.paddingLeft+row.root.paddingRight)
        }
        return desired.coerceIn(
            1,minOf(dp(220),(usableWidth*0.60f).toInt()).coerceAtLeast(1)
        )
    }

    private fun reposition(){
        val root=panel?:return
        try{
            val (width,height)=screenSize()
            params.width=desiredPanelWidth(width)
            params.x=params.x.coerceIn(0,(width-params.width).coerceAtLeast(0))
            params.y=params.y.coerceIn(0,(height-root.height).coerceAtLeast(0))
            val layout=Triple(params.width,params.x,params.y)
            if(appliedLayout!=layout){appliedLayout=layout;wm.updateViewLayout(root,params)}
        }catch(_:Exception){fatal()}
    }
    override fun onConfigurationChanged(newConfig:Configuration){
        super.onConfigurationChanged(newConfig)
        refreshAppearance()
        panel?.requestLayout()
        reposition()
    }
    private fun unavailable(){
        ProcessMonitorState.report(ticket,false)
        if(panel!=null){
            totalView.text="TOTAL CPU —"
            totalView.contentDescription="Total CPU unavailable; 100% is one core."
            showRows(listOf(RowData("unavailable",text("進程資料無法取得"))))
        }
    }
    private fun createRow():RowView{
        val container=LinearLayout(this).apply{
            orientation=LinearLayout.VERTICAL
            // Compact row rhythm; label() disables extra font padding.
            setPadding(dp(8),dp(1),dp(8),dp(2))
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        val headline=LinearLayout(this).apply{
            orientation=LinearLayout.HORIZONTAL
            gravity=Gravity.CENTER_VERTICAL
        }
        val name=label("").apply{
            setSingleLine(true)
            ellipsize=TextUtils.TruncateAt.END
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val cpu=label("").apply{
            // A shared paint-based fixed reservation is assigned after content
            // changes; only the weighted name yields space at the width cap.
            setSingleLine(true)
            ellipsize=null
            gravity=Gravity.RIGHT or Gravity.CENTER_VERTICAL
            setPadding(dp(6),0,0,0)
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val metrics=label("",10f).apply{
            // Full row width, no line limit or ellipsis: PID/RAM may wrap.
            setHorizontallyScrolling(false)
            importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        headline.addView(name,LinearLayout.LayoutParams(
            0,LinearLayout.LayoutParams.WRAP_CONTENT,1f
        ))
        headline.addView(cpu,LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
        container.addView(headline,LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
        container.addView(metrics,LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))
        return RowView(container,name,metrics,cpu)
    }
    private fun showRows(values:List<RowData>){
        if(panel==null)return
        val display=if(values.isEmpty())
            listOf(RowData("empty",text("沒有可顯示的進程"))) else values
        val keys=display.map{it.key}.toSet()
        views.keys.filter{it !in keys}.toList().forEach{key->
            views.remove(key)?.let{rows.removeView(it.root)}
        }
        display.forEachIndexed{index,value->
            val view=views.getOrPut(value.key){
                createRow().also{rows.addView(it.root,LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ))}
            }
            val process=value.metrics!=null
            val metrics=value.metrics.orEmpty()
            val cpu=value.cpu.orEmpty()
            if(view.name.text.toString()!=value.name)view.name.text=value.name
            if(view.metrics.text.toString()!=metrics)view.metrics.text=metrics
            if(view.cpu.text.toString()!=cpu)view.cpu.text=cpu
            view.metrics.visibility=if(process)View.VISIBLE else View.GONE
            view.cpu.visibility=if(process)View.VISIBLE else View.GONE
            // Configure wrapping only on transitions, not on every sample.
            if(view.name.tag!=process){
                view.name.setSingleLine(process)
                view.name.ellipsize=if(process)TextUtils.TruncateAt.END else null
                view.name.tag=process
            }
            if(view.root.contentDescription!=value.accessibility)
                view.root.contentDescription=value.accessibility
            if(rows.indexOfChild(view.root)!=index){
                rows.removeView(view.root)
                rows.addView(view.root,index)
            }
        }
        // Includes total-line changes made by the caller. reposition compares
        // width and position before issuing any window layout update.
        reposition()
    }
    private fun cleanup(){
        if(destroyed)return
        destroyed=true
        if(appearanceRegistered){
            appearancePrefs.unregisterOnSharedPreferenceChangeListener(appearanceListener)
            appearanceRegistered=false
        }
        main.removeCallbacks(appearanceRefresh)
        ProcessMonitorState.report(ticket,false)
        ProcessMonitorState.detach(this)
        pause()
        main.removeCallbacksAndMessages(null)
        worker.shutdownNow()
        if(registered){try{unregisterReceiver(screenReceiver)}catch(_:Exception){};registered=false}
        val root=panel;panel=null
        if(root!=null)try{wm.removeViewImmediate(root)}catch(_:Exception){}
        views.clear()
        address=""
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
    override fun onDestroy(){
        // Never mutate desired preference here: a newer start may already be queued.
        cleanup()
        super.onDestroy()
    }
}
