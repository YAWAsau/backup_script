package com.xayah.dex

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.system.Os
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadLocalRandom
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.system.exitProcess

/**
 * WebDAV client CLI backed by HttpCore.
 *
 * No external HTTP/logging client libraries. Daemon mode keeps HttpCore keep-alive sockets
 * per host/port for fast small-file operations, while putstdinchunkedrel remains true
 * streaming and never buffers the whole archive on disk.
 */
object WebDavUtil {
    private val VERSION = DexBuildInfo.VERSION
    private const val PUT_RESPONSE_BODY_SNIFF_LIMIT = 65536
    private const val PUT_SEMANTIC_FAILURE_HTTP_CODE = 599
    private const val MAX_DAEMON_BODY_BYTES = 64L * 1024L * 1024L

    private val DAV_PROPFIND_BODY = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:resourcetype/>
            <d:getcontentlength/>
            <d:getlastmodified/>
            <d:getetag/>
            <d:displayname/>
          </d:prop>
        </d:propfind>
    """.trimIndent().toByteArray(StandardCharsets.UTF_8)

    private val DAV_QUOTA_BODY = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:quota-available-bytes/>
            <d:quota-used-bytes/>
          </d:prop>
        </d:propfind>
    """.trimIndent().toByteArray(StandardCharsets.UTF_8)

    private val http = HttpCore.Client(keepAlive = true)
    private val mkcolOkCache = ConcurrentHashMap<String, Boolean>()
    private val listOkCache = ConcurrentHashMap<ListCacheKey, String>()
    private val serverKindCache = ConcurrentHashMap<String, String>()
    private val featureFactsCache = ConcurrentHashMap<String, WebDavFeatureFacts>()
    private val managedUploadSeq = AtomicInteger(0)
    private val streamLogSeq = AtomicInteger(0)

    private data class ListCacheKey(val url: String, val depth: Int)
    private enum class DirState { EXISTS, MISSING, FAILED }
    private val dirStateCache = ConcurrentHashMap<String, DirState>()

    private enum class DavOperation { OPTIONS, PROPFIND, HEAD, MKCOL, PUT, GET, MOVE, COPY, DELETE }

    private data class DavPolicyDecision(
        val ok: Boolean,
        val retryable: Boolean = false,
        val normalizedCode: Int = 0,
        val reason: String = ""
    )


    private data class WebDavFeatureFacts(
        val supportsChunkedPut: Boolean? = null,
        val supportsFixedPut: Boolean? = null,
        val supportsGetStream: Boolean? = null,
        val supportsMove: Boolean? = null,
        val supportsCopy: Boolean? = null,
        val supportsStat: Boolean? = null,
        val supportsRemoteSize: Boolean? = null,
        val supportsMkcol: Boolean? = null,
        val supportsDelete: Boolean? = null,
        val supportsDepth0: Boolean? = null,
        val supportsDepth1: Boolean? = null,
        val supportsDepthInfinity: Boolean? = null,
        val supportsRecursiveWalkFallback: Boolean? = null,
        val supportsAtomicPublish: Boolean? = null,
        val supportsOverwriteMove: Boolean? = null,
        val supportsPacerRetryBackoff: Boolean? = null,
        val supportsDirectoryCache: Boolean? = null,
        val supportsQuota: Boolean? = null,
        val bodyCompareOk: Boolean? = null,
        val copyStatOk: Boolean? = null,
        val cleanupOk: Boolean? = null,
        val source: String = "unknown",
        val verifiedAtMs: Long = System.currentTimeMillis(),
    )

    private data class WebDavQuota(
        val availableBytes: Long? = null,
        val usedBytes: Long? = null,
        val state: String = "unsupported",
    )

    private data class WebDavBackendProfile(
        val kind: String,
        val directAll: Boolean,
        val newPayloadDirect: Boolean,
        val cjkPathRetry: Boolean,
        val postBodyTimeoutMs: Int,
        val atomicReplace: Boolean,
        val supportTier: String,
        val featureSource: String,
        val reason: String
    )

    private data class ProviderHint(
        val id: String = "",
        val displayName: String = "",
        val region: String = "",
        val providerClass: String = "",
        val source: String = "none",
        val confidence: String = "unknown"
    )

    private data class ProviderAlias(
        val id: String,
        val displayName: String,
        val region: String,
        val providerClass: String,
        val aliases: List<String>
    )

    private data class AlistSecurityAdvisory(
        val state: String = "not_applicable",
        val version: String = "unknown",
        val minSafeVersion: String = "3.57.0",
        val cve: String = "CVE-2026-25161",
        val action: String = "none"
    )

    private data class ManagedDecision(
        val direct: Boolean,
        val modeName: String,
        val serverKind: String,
        val profile: WebDavBackendProfile,
        val requestedMode: String,
        val knownMissing: Boolean
    )
    private fun infoLog(line: String) {
        val path = System.getenv("WEBDAV_DAEMON_INFO_LOG")?.trim().orEmpty()
        if (path.isNotEmpty()) {
            runCatching {
                File(path).appendText(line + "\n", StandardCharsets.UTF_8)
            }.onSuccess { return }
        }
        System.err.println(line)
    }

    private fun envLong(name: String, defaultValue: Long, minValue: Long, maxValue: Long): Long {
        val raw = System.getenv(name)?.trim()?.toLongOrNull() ?: return defaultValue
        if (raw == 0L) return 0L
        return raw.coerceIn(minValue, maxValue)
    }

    private fun streamHeartbeatMs(): Long = envLong("WEBDAV_STREAM_HEARTBEAT_SEC", 30L, 5L, 3600L) * 1000L
    private fun streamProgressStepBytes(): Long = envLong("WEBDAV_STREAM_PROGRESS_STEP_MB", 256L, 16L, 4096L) * 1024L * 1024L
    private fun streamIdleWarnMs(): Long = envLong("WEBDAV_STREAM_IDLE_WARN_SEC", 60L, 10L, 86400L) * 1000L
    private fun streamStallAbortMs(): Long = envLong("WEBDAV_STREAM_STALL_ABORT_SEC", 180L, 30L, 86400L) * 1000L
    private fun streamPostBodyTimeoutMs(defaultSec: Long = 180L): Int {
        // r600: canonical name reflects the protocol-visible phase. Once the client request
        // body is emitted, AList/OpenList may still synchronously hash/cache/upload to the
        // backing provider before returning HTTP 2xx. The r599 env name is retained only as
        // a compatibility alias for existing configs.
        val canonical = System.getenv("WEBDAV_STREAM_POST_BODY_TIMEOUT_SEC")?.trim()?.toLongOrNull()
        val legacy = System.getenv("WEBDAV_STREAM_FINALIZE_TIMEOUT_SEC")?.trim()?.toLongOrNull()
        val raw = canonical ?: legacy ?: defaultSec
        val sec = if (raw == 0L) defaultSec else raw.coerceIn(60L, 900L)
        return (sec * 1000L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }
    private fun streamVerbose(): Boolean {
        val raw = System.getenv("WEBDAV_STREAM_VERBOSE")?.trim()?.lowercase(java.util.Locale.US) ?: return false
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private fun formatMiB(bytes: Long): String = String.format(java.util.Locale.US, "%.1f", bytes.toDouble() / 1048576.0)

    private class WebDavStreamStallException(message: String) : IOException(message)

    private fun classifyStreamError(e: Throwable?): String {
        if (e == null) return "unknown"
        if (e is WebDavStreamStallException) return "byte_stall"
        val text = ((e.javaClass.name ?: "") + " " + (e.message ?: "")).lowercase(java.util.Locale.US)
        return when {
            text.contains("connection reset") || text.contains("econnreset") -> "remote_reset"
            text.contains("broken pipe") || text.contains("epipe") -> "remote_pipe_broken"
            text.contains("timed out") || text.contains("timeout") || text.contains("etimedout") -> "server_timeout"
            text.contains("socket closed") || text.contains("closed channel") -> "socket_closed"
            text.contains("ssl") || text.contains("tls") || text.contains("handshake") -> "tls_failure"
            text.contains("unexpected eof") || text.contains("eofexception") -> "unexpected_eof"
            text.contains("no route") || text.contains("network is unreachable") || text.contains("unreachable") -> "network_unreachable"
            else -> "daemon_io_exception"
        }
    }

    private class WebDavStreamMeter(
        private val relPath: String,
        private val modeName: String,
        private val serverKind: String,
        private val targetRel: String,
        private val postBodyTimeoutMs: Int,
    ) {
        private val tag = "wdavstream-" + streamLogSeq.incrementAndGet()
        private val heartbeatMs = streamHeartbeatMs()
        private val progressStepBytes = streamProgressStepBytes()
        private val idleWarnMs = streamIdleWarnMs()
        private val stallAbortMs = streamStallAbortMs()
        private val verbose = streamVerbose()
        private val startMs = System.currentTimeMillis()
        private val bytes = AtomicLong(0L)
        private val lastProgressMs = AtomicLong(startMs)
        private val lastLogMs = AtomicLong(startMs)
        private val done = AtomicBoolean(false)
        private val bodyFinishedMs = AtomicLong(0L)
        private val nextProgressBytes = AtomicLong(if (progressStepBytes > 0L) progressStepBytes else Long.MAX_VALUE)
        private val lastIdleBytesLogged = AtomicLong(-1L)
        private val abortCause = AtomicReference<WebDavStreamStallException?>(null)
        private val activeSource = AtomicReference<InputStream?>(null)
        private val activeSocket = AtomicReference<Socket?>(null)

        fun begin() {
            infoLog("WEBDAV_STREAM_BEGIN tag=$tag rel=$relPath target=$targetRel mode=$modeName server=$serverKind heartbeatSec=${heartbeatMs / 1000L} progressStepMB=${progressStepBytes / 1048576L} idleWarnSec=${idleWarnMs / 1000L} stallAbortSec=${stallAbortMs / 1000L} postBodyTimeoutSec=${postBodyTimeoutMs / 1000} postBodySemantics=server_processing_until_put_response")
            if (heartbeatMs > 0L || idleWarnMs > 0L || stallAbortMs > 0L) {
                Thread { watchLoop() }.apply { isDaemon = true; name = "webdav-stream-meter-$tag"; start() }
            }
        }

        fun attachSocket(socket: Socket) {
            activeSocket.set(socket)
        }

        fun wrap(source: InputStream): InputStream {
            activeSource.set(source)
            return object : InputStream() {
                private fun throwIfAborted() {
                    abortCause.get()?.let { throw it }
                }

                override fun read(): Int {
                    throwIfAborted()
                    val v = try {
                        source.read()
                    } catch (e: IOException) {
                        abortCause.get()?.let { throw it }
                        throw e
                    }
                    throwIfAborted()
                    if (v >= 0) onBytes(1)
                    return v
                }

                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    throwIfAborted()
                    val n = try {
                        source.read(buffer, offset, length)
                    } catch (e: IOException) {
                        abortCause.get()?.let { throw it }
                        throw e
                    }
                    throwIfAborted()
                    if (n > 0) onBytes(n.toLong())
                    return n
                }

                override fun close() {
                    activeSource.compareAndSet(source, null)
                    source.close()
                }
            }
        }

        fun sentBytes(): Long = bytes.get()

        fun clientBodyComplete(): Boolean = bodyFinishedMs.get() > 0L

        fun bodyFinished() {
            val now = System.currentTimeMillis()
            if (!bodyFinishedMs.compareAndSet(0L, now)) return
            val total = bytes.get()
            val elapsedMs = (now - startMs).coerceAtLeast(1L)
            infoLog("WEBDAV_STREAM_BODY_DONE tag=$tag rel=$relPath target=$targetRel mode=$modeName server=$serverKind sentBytes=$total sentMiB=${formatMiB(total)} elapsedMs=$elapsedMs clientBodyComplete=1 remoteCommit=unknown responseConfirmed=0 postBodyTimeoutSec=${postBodyTimeoutMs / 1000} postBodySemantics=server_processing_until_put_response")
            infoLog("WEBDAV_STREAM_POST_BODY_WAIT_BEGIN tag=$tag rel=$relPath target=$targetRel mode=$modeName server=$serverKind sentBytes=$total bodyMs=$elapsedMs response=pending remoteCommit=unknown postBodyTimeoutSec=${postBodyTimeoutMs / 1000}")
            lastLogMs.set(now)
        }

        private fun onBytes(delta: Long) {
            val total = bytes.addAndGet(delta)
            val now = System.currentTimeMillis()
            lastProgressMs.set(now)
            if (verbose) {
                maybeLog("progress", total, now, "verbose=1")
                return
            }
            while (total >= nextProgressBytes.get()) {
                val threshold = nextProgressBytes.get()
                if (nextProgressBytes.compareAndSet(threshold, threshold + progressStepBytes)) {
                    maybeLog("progress", total, now, "thresholdMB=${threshold / 1048576L}")
                    break
                }
            }
        }

        private fun maybeLog(kind: String, total: Long, now: Long, extra: String = "") {
            if (kind == "heartbeat" && heartbeatMs <= 0L) return
            val elapsedMs = (now - startMs).coerceAtLeast(1L)
            val idleMs = (now - lastProgressMs.get()).coerceAtLeast(0L)
            val speedKib = if (elapsedMs > 0L) (total * 1000L / elapsedMs / 1024L) else 0L
            if (kind == "heartbeat" && now - lastLogMs.get() < heartbeatMs) return
            lastLogMs.set(now)
            val suffix = if (extra.isNotBlank()) " $extra" else ""
            infoLog("WEBDAV_STREAM_${kind.uppercase(java.util.Locale.US)} tag=$tag rel=$relPath sentBytes=$total sentMiB=${formatMiB(total)} elapsedMs=$elapsedMs idleMs=$idleMs speedKiBps=$speedKib$suffix")
        }

        private fun watchLoop() {
            val candidates = longArrayOf(heartbeatMs, idleWarnMs, stallAbortMs).filter { it > 0L }
            val baseMs = candidates.minOrNull() ?: 5000L
            val sleepMs = minOf(5000L, maxOf(1000L, baseMs / 2L))
            while (!done.get()) {
                try { Thread.sleep(sleepMs) } catch (_: InterruptedException) { return }
                if (done.get()) return
                val now = System.currentTimeMillis()
                val total = bytes.get()
                val idleMs = now - lastProgressMs.get()
                val bodyDoneAt = bodyFinishedMs.get()
                if (bodyDoneAt > 0L) {
                    // No source-byte progress is expected after the client request body is emitted.
                    // This interval is not proof of a provider commit/finalize. AList/OpenList can
                    // still hash/cache and upload to the backing provider before the PUT returns.
                    // Keep the source-byte stall watchdog disabled and bound only the server wait.
                    if (heartbeatMs > 0L && now - lastLogMs.get() >= heartbeatMs) {
                        val postBodyMs = (now - bodyDoneAt).coerceAtLeast(0L)
                        maybeLog("post_body_wait", total, now, "postBodyMs=$postBodyMs response=pending remoteCommit=unknown postBodyTimeoutSec=${postBodyTimeoutMs / 1000}")
                    }
                    continue
                }
                if (stallAbortMs > 0L && idleMs >= stallAbortMs) {
                    abortForStall(total, now, idleMs)
                    return
                }
                if (idleWarnMs > 0L && idleMs >= idleWarnMs && lastIdleBytesLogged.get() != total) {
                    lastIdleBytesLogged.set(total)
                    maybeLog("idle", total, now, "idleWarn=1")
                } else if (heartbeatMs > 0L && now - lastLogMs.get() >= heartbeatMs) {
                    maybeLog("heartbeat", total, now)
                }
            }
        }

        private fun abortForStall(total: Long, now: Long, idleMs: Long) {
            val elapsedMs = (now - startMs).coerceAtLeast(1L)
            val cause = WebDavStreamStallException("webdav stream byte stall rel=$relPath sentBytes=$total idleMs=$idleMs stallAbortMs=$stallAbortMs")
            if (!abortCause.compareAndSet(null, cause)) return
            lastLogMs.set(now)
            val socket = activeSocket.get()
            val source = activeSource.get()
            val socketClosed = socket != null && runCatching { socket.close(); true }.getOrDefault(false)
            val sourceClosed = source != null && runCatching { source.close(); true }.getOrDefault(false)
            val action = if (socket != null) "close_socket_close_source" else "close_source"
            infoLog("WEBDAV_STREAM_ABORT tag=$tag kind=byte_stall rel=$relPath target=$targetRel mode=$modeName server=$serverKind http=0 sentBytes=$total sentMiB=${formatMiB(total)} elapsedMs=$elapsedMs idleMs=$idleMs stallAbortSec=${stallAbortMs / 1000L} action=$action socketClosed=$socketClosed sourceClosed=$sourceClosed optional=0")
        }

        fun finish(httpCode: Int) {
            if (!done.compareAndSet(false, true)) return
            val now = System.currentTimeMillis()
            val total = bytes.get()
            val elapsedMs = (now - startMs).coerceAtLeast(1L)
            val speedKib = total * 1000L / elapsedMs / 1024L
            val ok = httpCode in 200..299
            val event = if (ok) "WEBDAV_STREAM_DONE" else "WEBDAV_STREAM_FAIL"
            val kind = if (ok) "ok" else "http_status"
            val bodyAt = bodyFinishedMs.get()
            val bodyMs = if (bodyAt > 0L) (bodyAt - startMs).coerceAtLeast(0L) else elapsedMs
            val postBodyMs = if (bodyAt > 0L) (now - bodyAt).coerceAtLeast(0L) else 0L
            infoLog("$event tag=$tag kind=$kind rel=$relPath target=$targetRel mode=$modeName server=$serverKind http=$httpCode sentBytes=$total sentMiB=${formatMiB(total)} elapsedMs=$elapsedMs bodyMs=$bodyMs postBodyMs=$postBodyMs clientBodyComplete=${if (bodyAt > 0L) 1 else 0} responseConfirmed=1 remoteCommit=${if (ok) "server-confirmed" else "not-confirmed"} completionSemantics=put_response_plus_optional_publish speedKiBps=$speedKib")
        }

        fun fail(e: Throwable) {
            if (!done.compareAndSet(false, true)) return
            val effective = abortCause.get() ?: e
            val now = System.currentTimeMillis()
            val total = bytes.get()
            val elapsedMs = (now - startMs).coerceAtLeast(1L)
            val speedKib = total * 1000L / elapsedMs / 1024L
            val bodyAt = bodyFinishedMs.get()
            val bodyMs = if (bodyAt > 0L) (bodyAt - startMs).coerceAtLeast(0L) else elapsedMs
            val postBodyMs = if (bodyAt > 0L) (now - bodyAt).coerceAtLeast(0L) else 0L
            val message = (effective.message ?: "").replace('\n', ' ').replace('\r', ' ').take(180)
            val baseKind = classifyStreamError(effective)
            val failureKind = if (bodyAt > 0L && baseKind == "server_timeout") "post_body_timeout" else baseKind
            infoLog("WEBDAV_STREAM_FAIL tag=$tag kind=$failureKind rel=$relPath target=$targetRel mode=$modeName server=$serverKind http=0 sentBytes=$total sentMiB=${formatMiB(total)} elapsedMs=$elapsedMs bodyMs=$bodyMs postBodyMs=$postBodyMs clientBodyComplete=${if (bodyAt > 0L) 1 else 0} responseConfirmed=0 remoteCommit=unknown completionSemantics=no_http_terminal_response speedKiBps=$speedKib error=${effective.javaClass.simpleName} message=$message")
        }
    }


    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isEmpty()) {
            printUsage()
            exitProcess(2)
        }
        when (args[0]) {
            "version" -> { println(VERSION); exitProcess(0) }
            "mkdirrel" -> cmdMkdirRel(args)
            "mkdirsrel" -> cmdMkdirsRel(args)
            "putrel" -> cmdPutRel(args)
            "putbatchrel" -> cmdPutBatchRel(args)
            "putstdinchunkedrel" -> cmdPutStdinChunkedRel(args)
            "putstdinmanagedrel" -> cmdPutStdinManagedRel(args)
            "putmanagedrel" -> cmdPutManagedRel(args)
            "managedbatchputrelwithparents" -> cmdManagedBatchPutRelWithParents(args)
            "managedlistclassifyrel" -> cmdManagedListClassifyRel(args)
            "directchildrenrel" -> cmdDirectChildrenRel(args)
            "downloadmanifestrel" -> cmdDownloadManifestRel(args)
            "orphanrootsrel" -> cmdOrphanRootsRel(args)
            "managedproberel" -> cmdManagedProbeRel(args)
            "compatProbeRel" -> cmdCompatProbeRel(args)
            "backendprofilerel" -> cmdBackendProfileRel(args)
            "ensurebaserel" -> cmdEnsureBaseRel(args)
            "ensuredirrel" -> cmdEnsureDirRel(args)
            "ensuredirsbatchrel" -> cmdEnsureDirsBatchRel(args)
            "preparedirsplanrel" -> cmdPrepareDirsPlanRel(args)
            "optionspreflightrel" -> cmdOptionsPreflightRel(args)
            "quotarel" -> cmdQuotaRel(args)
            "verifyuploadmaprel" -> cmdVerifyUploadMapRel(args)
            "getrel" -> cmdGetRel(args)
            "getstdoutrel" -> cmdGetStdoutRel(args)
            "deleterel" -> cmdDeleteRel(args)
            "moverel" -> cmdMoveRel(args)
            "copyrel" -> cmdCopyRel(args)
            "propfindrel" -> cmdPropfindRel(args)
            "statrel" -> cmdStatRel(args)
            "optionsrel" -> cmdOptionsRel(args)
            "listrel" -> cmdListRel(args)
            "classifylistrel" -> cmdClassifyListRel(args)
            "encodepath" -> cmdEncodePath(args)
            "decodepath" -> cmdDecodePath(args)
            "daemon" -> cmdDaemon(args)
            "daemonunix" -> cmdDaemonUnix(args)
            else -> {
                printUsage()
                exitProcess(2)
            }
        }
    }

    // ---------------------------------------------------------------- daemon ----

    private fun cmdDaemon(args: Array<String>) {
        require(args.size >= 2) { "daemon <port> [idleTimeoutSec] [ownerPid]" }
        val port = args[1].toIntOrNull() ?: run { println("bad port"); exitProcess(2) }
        require(port in 1..65535) { "bad port" }
        val idleTimeoutMs = ((args.getOrNull(2)?.toLongOrNull()) ?: 1800L) * 1000L
        require(idleTimeoutMs > 0) { "idleTimeoutSec must be > 0" }
        val ownerPid = parseOptionalOwnerPid(args.getOrNull(3))
        runDaemon(TcpDaemonListener(port), "DAEMON_READY $port", idleTimeoutMs, ownerPid)
    }

    private fun cmdDaemonUnix(args: Array<String>) {
        require(args.size >= 2) { "daemonunix <socketPath> [idleTimeoutSec] [ownerPid]" }
        val socketPath = args[1]
        val idleTimeoutMs = ((args.getOrNull(2)?.toLongOrNull()) ?: 1800L) * 1000L
        require(idleTimeoutMs > 0) { "idleTimeoutSec must be > 0" }
        val ownerPid = parseOptionalOwnerPid(args.getOrNull(3))
        val listener = UnixDaemonListener(socketPath)
        runDaemon(listener, "DAEMON_READY_UNIX ${listener.socketPath}", idleTimeoutMs, ownerPid)
    }

    private fun parseOptionalOwnerPid(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        val pid = raw.toIntOrNull() ?: throw IllegalArgumentException("ownerPid must be numeric")
        require(pid > 1) { "ownerPid must be > 1" }
        require(readProcStarttime(pid) != null) { "ownerPid is not alive: $pid" }
        return pid
    }

    private fun runDaemon(
        listener: DaemonListener,
        readyLine: String,
        idleTimeoutMs: Long,
        ownerPid: Int?,
    ) {
        DaemonHardening.protectSelf("WEBDAV")
        val lastActivity = AtomicLong(System.currentTimeMillis())
        val activeRequests = AtomicInteger(0)
        val parentPpidAtStart = if (ownerPid == null) readPpid() else -1
        val ownerStarttime = ownerPid?.let { readProcStarttime(it) }
        val listenerRef = AtomicReference<DaemonListener?>()

        fun closeDaemonResources() {
            runCatching { http.closeAll() }
            mkcolOkCache.clear()
            listOkCache.clear()
            serverKindCache.clear()
            featureFactsCache.clear()
            dirStateCache.clear()
            runCatching { listenerRef.getAndSet(null)?.close() }
        }

        Runtime.getRuntime().addShutdownHook(Thread { closeDaemonResources() })

        Thread {
            while (true) {
                Thread.sleep(2000)
                val ownerGone = if (ownerPid != null) {
                    ownerStarttime == null || readProcStarttime(ownerPid) != ownerStarttime
                } else {
                    parentPpidAtStart != -1 && readPpid() != parentPpidAtStart
                }
                if (ownerGone) {
                    closeDaemonResources()
                    exitProcess(0)
                }
                if (activeRequests.get() == 0 && System.currentTimeMillis() - lastActivity.get() > idleTimeoutMs) {
                    closeDaemonResources()
                    exitProcess(0)
                }
            }
        }.apply { isDaemon = true; start() }

        listenerRef.set(listener)
        println(readyLine)
        System.out.flush()

        try {
            while (true) {
                val client = try { listener.accept() } catch (_: Exception) {
                    if (listener.isClosed) break else continue
                }
                lastActivity.set(System.currentTimeMillis())
                activeRequests.incrementAndGet()
                Thread {
                    try {
                        handleDaemonConn(client.input, client.output)
                    } catch (e: Exception) {
                        System.err.println("[daemon] unhandled: ${e.javaClass.name}: ${e.message}")
                    } finally {
                        activeRequests.decrementAndGet()
                        lastActivity.set(System.currentTimeMillis())
                        runCatching { client.close() }
                    }
                }.apply { isDaemon = true; start() }
            }
        } finally {
            closeDaemonResources()
        }
    }

    private interface DaemonConnection : Closeable {
        val input: InputStream
        val output: OutputStream
    }

    private interface DaemonListener : Closeable {
        val isClosed: Boolean
        fun accept(): DaemonConnection
    }

    private class TcpDaemonListener(port: Int) : DaemonListener {
        private val server = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress("127.0.0.1", port))
        }

        override val isClosed: Boolean
            get() = server.isClosed

        override fun accept(): DaemonConnection = TcpDaemonConnection(server.accept())

        override fun close() {
            server.close()
        }
    }

    private class TcpDaemonConnection(private val socket: Socket) : DaemonConnection {
        override val input: InputStream = socket.getInputStream()
        override val output: OutputStream = socket.getOutputStream()

        override fun close() {
            socket.close()
        }
    }

    private class UnixDaemonListener(path: String) : DaemonListener {
        val socketPath: String
        private val closed = AtomicBoolean(false)
        private val bindSocket = LocalSocket(LocalSocket.SOCKET_STREAM)
        private val server: LocalServerSocket

        init {
            require(path.isNotBlank()) { "socketPath is empty" }
            require(!path.contains('\u0000') && !path.contains('\n') && !path.contains('\r')) {
                "socketPath contains invalid characters"
            }

            val socketFile = File(path)
            require(socketFile.isAbsolute) { "socketPath must be absolute" }
            socketPath = socketFile.absolutePath
            require(socketPath.toByteArray(StandardCharsets.UTF_8).size <= UNIX_PATH_MAX_BYTES) {
                "socketPath is too long (max $UNIX_PATH_MAX_BYTES UTF-8 bytes)"
            }

            val parent = socketFile.parentFile ?: throw IOException("socketPath has no parent")
            if (!parent.isDirectory && !parent.mkdirs()) {
                throw IOException("cannot create socket parent: ${parent.absolutePath}")
            }
            if (socketFile.exists() && !socketFile.delete()) {
                throw IOException("cannot remove stale socket: $socketPath")
            }

            try {
                bindSocket.bind(LocalSocketAddress(socketPath, LocalSocketAddress.Namespace.FILESYSTEM))
                server = LocalServerSocket(bindSocket.fileDescriptor)
                runCatching { Os.chmod(socketPath, UNIX_SOCKET_MODE) }
            } catch (e: Throwable) {
                runCatching { bindSocket.close() }
                runCatching { socketFile.delete() }
                throw e
            }
        }

        override val isClosed: Boolean
            get() = closed.get()

        override fun accept(): DaemonConnection = UnixDaemonConnection(server.accept())

        override fun close() {
            if (!closed.compareAndSet(false, true)) return
            // LocalServerSocket(FileDescriptor) does not own the descriptor. Closing the
            // LocalSocket that created/bound it is what releases accept() and the inode.
            runCatching { bindSocket.close() }
            runCatching { server.close() }
            runCatching { File(socketPath).delete() }
        }
    }

    private class UnixDaemonConnection(private val socket: LocalSocket) : DaemonConnection {
        override val input: InputStream = socket.inputStream
        override val output: OutputStream = socket.outputStream

        override fun close() {
            socket.close()
        }
    }

    private fun readPpid(): Int = runCatching {
        File("/proc/self/stat").readText().split(")").last().trim().split(" ")[1].toInt()
    }.getOrDefault(-1)

    private fun readProcStarttime(pid: Int): Long? = runCatching {
        val text = File("/proc/$pid/stat").readText()
        val fields = text.substringAfterLast(')').trim().split(Regex("\\s+"))
        fields.getOrNull(19)?.toLongOrNull()
    }.getOrNull()

    private fun handleDaemonConn(input: InputStream, output: OutputStream) {
        fun readLine(): String {
            // The loopback daemon protocol is byte-oriented and shell/nc sends UTF-8.
            // Do not append byte.toChar(): that turns CJK URL bytes into mojibake
            // (e.g. 主 -> Ã¤Â¸Â»), then HttpCore can no longer choose the correct
            // percent-encoded/raw-UTF8 WebDAV request target.
            val buf = ByteArrayOutputStream(256)
            while (true) {
                val b = input.read()
                if (b == -1 || b == '\n'.code) break
                if (b != '\r'.code) buf.write(b)
            }
            return buf.toByteArray().toString(StandardCharsets.UTF_8)
        }

        val command = readLine()
        val user = readLine()
        val pass = readLine()
        val url = readLine()
        val extra = readLine()
        val requestBodyLen = readLine().toLongOrNull() ?: 0L

        var httpCode = 0
        var respBody = ByteArray(0)
        var streamingResponseStarted = false
        var streamingChunkOutput: RelayChunkedOutputStream? = null
        var lastError: Throwable? = null

        fun safe(block: () -> Int): Int = runCatching(block).getOrElse { e -> lastError = e; HttpCore.extractCode(e) }

        // r547: The daemon control line stores command-specific arguments in a
        // TAB-delimited extra field.  Treat that line as a strict local protocol:
        // a literal TAB inside caller-controlled path/name data must never shift
        // positional fields and become another WebDAV argument.  Shell r546 still
        // sanitizes serialized segments for compatibility with existing classes.dex;
        // this Dex-side gate is the final authority if a future caller or a manual
        // socket request bypasses the shell guard.
        val extraParts: List<String> = if (extra.isEmpty()) emptyList() else extra.split('\t')
        fun extra1(): String = extraParts.getOrElse(0) { "" }
        fun extra2(): String = extraParts.getOrElse(1) { "" }
        fun extra3(): String = extraParts.getOrElse(2) { "" }
        fun relUrl(): String = buildRelUrl(url, extra1())
        fun daemonBadExtra(expected: String): Int {
            val detail = "state=bad_extra\ncommand=${sanitizeTsv(command)}\nfields=${extraParts.size}\nexpected=${sanitizeTsv(expected)}\n"
            respBody = detail.toByteArray(StandardCharsets.UTF_8)
            infoLog("WEBDAV_DAEMON_BAD_EXTRA command=${sanitizeTsv(command)} fields=${extraParts.size} expected=${sanitizeTsv(expected)}")
            return 400
        }
        fun expectExtra(count: Int, expected: String): Boolean =
            if (extraParts.size == count) true else { httpCode = daemonBadExtra(expected); false }
        fun expectExtraRange(min: Int, max: Int, expected: String): Boolean =
            if (extraParts.size in min..max) true else { httpCode = daemonBadExtra(expected); false }

        when (command) {
            "mkdirrel" -> if (expectExtra(1, "relPath")) httpCode = safe { mkcolCached(user, pass, relUrl()) }
            "putrel" -> if (expectExtra(2, "relPath<TAB>localFile")) {
                val file = File(extra2())
                httpCode = if (!file.isFile) 0 else safe {
                    putReplayableLocalFile(user, pass, url, extra1(), file, verifyContext = "daemon-putrel").also { if (it in 200..299) invalidateListCache() }
                }
            }
            "putbatchrel" -> if (expectExtra(1, "baseRel")) {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                httpCode = safe {
                    val result = putBatchRel(user, pass, url, extra1(), body)
                    respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "putstdinchunkedrel" -> if (expectExtra(1, "relPath")) httpCode = safe {
                put(user, pass, relUrl(), input, contentLength = null, chunked = true).also { if (it in 200..299) invalidateListCache() }
            }
            "putstdinmanagedrel" -> if (expectExtra(3, "relPath<TAB>mode<TAB>parentMode")) httpCode = safe {
                putStdinManagedRel(user, pass, url, extra1(), extra2(), extra3(), input)
            }
            "putmanagedrel" -> if (expectExtra(3, "relPath<TAB>localFile<TAB>mode")) httpCode = safe {
                putFileManagedRel(user, pass, url, extra1(), extra2(), extra3(), "ensureParentMkdir")
            }
            "managedbatchputrelwithparents" -> if (expectExtraRange(0, 3, "[mode<TAB>parentMode<TAB>rootRel]")) httpCode = safe {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                val result = managedBatchPutRelWithParents(user, pass, url, extra1(), extra2(), extra3(), body)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "managedlistclassifyrel" -> if (expectExtra(2, "relPath<TAB>depth")) httpCode = safe {
                val result = classifyListRel(user, pass, url, extra1(), extra2().toIntOrNull() ?: -1)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "directchildrenrel" -> if (expectExtra(1, "relPath")) httpCode = safe {
                val result = directChildrenRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "downloadmanifestrel" -> if (expectExtra(2, "baseRel<TAB>destDir")) httpCode = safe {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                val result = downloadManifestRel(user, pass, url, extra1(), extra2(), body)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "orphanrootsrel" -> if (expectExtra(1, "rootRel")) httpCode = safe {
                val result = orphanRootsRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "managedproberel" -> if (expectExtra(1, "relBase")) httpCode = safe {
                val result = managedProbeRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "compatProbeRel" -> if (expectExtraRange(0, 1, "[testRel]")) httpCode = safe {
                val result = compatProbeRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "backendprofilerel" -> if (expectExtraRange(0, 1, "[reason]")) httpCode = safe {
                val profile = webDavBackendProfile(user, pass, url, extra1().ifEmpty { "daemon" })
                val providerHint = providerHintFromBaseUrl(url, profile.kind)
                val facts = featureFactsCache[featureFactsKey(url)]
                respBody = ("schema\tspeedbackup.webdav_backend_profile.v3\n" +
                    "kind\t${profile.kind}\n" +
                    "serverFamily\t${serverFamilyForKind(profile.kind)}\n" +
                    "serverDisplay\t${serverDisplayForKind(profile.kind)}\n" +
                    "behaviorProfile\t${behaviorProfileForKind(profile.kind)}\n" +
                    "providerId\t${providerHint.id}\n" +
                    "providerDisplay\t${providerHint.displayName}\n" +
                    "providerRegion\t${providerHint.region}\n" +
                    "providerClass\t${providerHint.providerClass}\n" +
                    "providerHintSource\t${providerHint.source}\n" +
                    "providerHintConfidence\t${providerHint.confidence}\n" +
                    "directAll\t${if (profile.directAll) 1 else 0}\n" +
                    "newPayloadDirect\t${if (profile.newPayloadDirect) 1 else 0}\n" +
                    "atomicReplace\t${if (profile.atomicReplace) 1 else 0}\n" +
                    "supportTier\t${profile.supportTier}\n" +
                    "featureSource\t${profile.featureSource}\n" +
                    "featureSummary\t${featureSummary(facts)}\n" +
                    "supportsChunkedPut\t${featureBool(facts?.supportsChunkedPut)}\n" +
                    "supportsFixedPut\t${featureBool(facts?.supportsFixedPut)}\n" +
                    "supportsGetStream\t${featureBool(facts?.supportsGetStream)}\n" +
                    "supportsMove\t${featureBool(facts?.supportsMove)}\n" +
                    "supportsCopy\t${featureBool(facts?.supportsCopy)}\n" +
                    "supportsStat\t${featureBool(facts?.supportsStat)}\n" +
                    "supportsRemoteSize\t${featureBool(facts?.supportsRemoteSize)}\n" +
                    "supportsMkcol\t${featureBool(facts?.supportsMkcol)}\n" +
                    "supportsDelete\t${featureBool(facts?.supportsDelete)}\n" +
                    "supportsDepth0\t${featureBool(facts?.supportsDepth0)}\n" +
                    "supportsDepth1\t${featureBool(facts?.supportsDepth1)}\n" +
                    "supportsDepthInfinity\t${featureBool(facts?.supportsDepthInfinity)}\n" +
                    "supportsRecursiveWalkFallback\t${featureBool(facts?.supportsRecursiveWalkFallback)}\n" +
                    "supportsAtomicPublish\t${featureBool(facts?.supportsAtomicPublish)}\n" +
                    "supportsOverwriteMove\t${featureBool(facts?.supportsOverwriteMove)}\n" +
                    "supportsQuota\t${featureBool(facts?.supportsQuota)}\n" +
                    "cjkPathRetry\t${if (profile.cjkPathRetry) 1 else 0}\n" +
                    "postBodyTimeoutSec\t${profile.postBodyTimeoutMs / 1000}\n" +
                    "postBodySemantics\tserver_processing_until_put_response\n").toByteArray(StandardCharsets.UTF_8)
                200
            }
            "ensurebaserel" -> if (expectExtra(0, "<empty>")) httpCode = safe {
                val result = ensureBaseRel(user, pass, url)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "ensuredirrel" -> if (expectExtra(1, "relPath")) httpCode = safe {
                val result = ensureDirRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "ensuredirsbatchrel" -> if (expectExtra(0, "<empty>")) httpCode = safe {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                val result = ensureDirsBatchRel(user, pass, url, body)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "preparedirsplanrel" -> if (expectExtra(3, "rootRel<TAB>mode<TAB>progressFile")) httpCode = safe {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                val result = prepareDirsPlanRel(user, pass, url, extra1(), extra2().ifEmpty { "create" }, body, extra3())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "optionspreflightrel" -> if (expectExtra(2, "relPath<TAB>mode")) httpCode = safe {
                val result = optionsPreflightRel(user, pass, url, extra1(), extra2())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "quotarel" -> if (expectExtra(1, "relPath")) httpCode = safe {
                val result = quotaRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "verifyuploadmaprel" -> if (expectExtra(1, "rootRel")) httpCode = safe {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                val result = verifyUploadMapRel(user, pass, url, extra1(), body)
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "getrel" -> if (expectExtra(2, "relPath<TAB>localFile")) httpCode = safe {
                FileOutputStream(extra2()).use { out -> getTo(user, pass, relUrl(), out) }
            }
            "getstdoutrel" -> if (expectExtra(1, "relPath")) httpCode = safe {
                streamDaemonGet(user, pass, relUrl(), output) { chunkOutput ->
                    streamingResponseStarted = true
                    streamingChunkOutput = chunkOutput
                }
            }
            "deleterel" -> if (expectExtra(1, "relPath")) httpCode = safe { delete(user, pass, relUrl()).also { if (it in 200..299) invalidateListCache() } }
            "moverel" -> if (expectExtra(3, "srcRel<TAB>dstRel<TAB>overwrite")) httpCode = safe { move(user, pass, buildRelUrl(url, extra1()), buildRelUrl(url, extra2()), overwrite = extra3().ifEmpty { "T" } != "F").also { if (it in 200..299) invalidateListCache() } }
            "copyrel" -> if (expectExtra(3, "srcRel<TAB>dstRel<TAB>overwrite")) httpCode = safe { copy(user, pass, buildRelUrl(url, extra1()), buildRelUrl(url, extra2()), overwrite = extra3().ifEmpty { "T" } != "F").also { if (it in 200..299) invalidateListCache() } }
            "propfindrel" -> if (expectExtra(2, "relPath<TAB>depth")) {
                val depth = extra2().toIntOrNull() ?: 0
                httpCode = safe { propfindRaw(user, pass, relUrl(), depth).first }
            }
            "statrel" -> if (expectExtra(1, "relPath")) {
                httpCode = safe {
                    val result = statDav(user, pass, relUrl())
                    if (result.first in 200..299 && result.second != null) respBody = formatDavStat(result.second!!).toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "optionsrel" -> if (expectExtra(1, "relPath")) {
                httpCode = safe {
                    val result = optionsDav(user, pass, relUrl())
                    if (result.first in 200..299) respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "listrel" -> if (expectExtra(2, "relPath<TAB>depth")) {
                val depth = extra2().toIntOrNull() ?: -1
                httpCode = safe {
                    val result = listCached(user, pass, relUrl(), depth)
                    if (result.first in 200..299) respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "classifylistrel" -> if (expectExtra(2, "relPath<TAB>depth")) {
                val depth = extra2().toIntOrNull() ?: -1
                httpCode = safe {
                    val result = classifyListRel(user, pass, url, extra1(), depth)
                    if (result.first in 200..299) respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "encodepath" -> {
                respBody = HttpCore.percentEncodePath(url).toByteArray(StandardCharsets.UTF_8)
                httpCode = 200
            }
            "decodepath" -> {
                respBody = HttpCore.percentDecodePath(url).toByteArray(StandardCharsets.UTF_8)
                httpCode = 200
            }
            else -> httpCode = 0
        }

        if (httpCode == 0 && lastError != null) {
            // v2.6.94: getrel/listrel/statrel may intentionally return rc!=0 for missing,
            // truncated, or stale remote files. Do not dump full stack traces to daemon stderr
            // for these request-scoped WebDAV transport failures; shell-side raw logs already
            // record rc/bytes/http, and stderr must remain reserved for daemon/process fatal
            // failures.
            val knownTransferFailure = lastError is java.io.EOFException ||
                (lastError!!.message ?: "").contains("unexpected EOF", ignoreCase = true) ||
                (lastError!!.message ?: "").contains("empty HTTP response", ignoreCase = true)
            val requestScoped = command == "getrel" || command == "listrel" || command == "statrel" ||
                command == "propfindrel" || command == "optionsrel"
            if (!(requestScoped && knownTransferFailure)) {
                System.err.println("[daemon] cmd=$command url=$url -> ${lastError!!.javaClass.name}: ${lastError!!.message}")
                lastError!!.printStackTrace(System.err)
            }
        }

        if (streamingResponseStarted) {
            // Unknown-origin-length streams are re-framed between daemon and native relay.
            // Only a successfully completed HTTP body writes the terminating zero chunk;
            // an interrupted body therefore makes unixsock return non-zero instead of
            // silently accepting a truncated archive.
            if (httpCode in 200..299) streamingChunkOutput?.finish()
            output.flush()
            return
        }

        val responseBodyLen = respBody.size.toLong()
        writeDaemonResponseHead(output, httpCode, responseBodyLen)
        if (respBody.isNotEmpty()) output.write(respBody)
        output.flush()
    }

    private fun writeDaemonResponseHead(output: OutputStream, code: Int, bodyLength: Long) {
        output.write("HTTP $code\n".toByteArray(StandardCharsets.UTF_8))
        output.write("$bodyLength\n".toByteArray(StandardCharsets.UTF_8))
        output.flush()
    }

    /**
     * Stream a GET response directly from HttpCore into the daemon connection.
     *
     * bodyLength >= 0: raw body with exact byte count.
     * bodyLength == -2: daemon-local chunk framing, decoded by native unixsock v2.
     */
    private fun streamDaemonGet(
        user: String,
        pass: String,
        url: String,
        output: OutputStream,
        onStarted: (RelayChunkedOutputStream?) -> Unit
    ): Int {
        val code = http.getToStreaming(url, user, pass) { status, originLength ->
            val protocolLength = if (status in 200..299 && originLength < 0) DAEMON_CHUNKED_BODY else originLength.coerceAtLeast(0L)
            writeDaemonResponseHead(output, status, protocolLength)
            if (protocolLength == DAEMON_CHUNKED_BODY) {
                RelayChunkedOutputStream(output).also(onStarted)
            } else {
                onStarted(null)
                output
            }
        }
        return code
    }

    private class RelayChunkedOutputStream(private val target: OutputStream) : OutputStream() {
        private var finished = false

        override fun write(value: Int) {
            val one = byteArrayOf(value.toByte())
            write(one, 0, 1)
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            check(!finished) { "relay chunk stream already finished" }
            if (length <= 0) return
            target.write(Integer.toHexString(length).toByteArray(StandardCharsets.US_ASCII))
            target.write("\r\n".toByteArray(StandardCharsets.US_ASCII))
            target.write(buffer, offset, length)
            target.write("\r\n".toByteArray(StandardCharsets.US_ASCII))
        }

        override fun flush() {
            target.flush()
        }

        fun finish() {
            if (finished) return
            finished = true
            target.write("0\r\n\r\n".toByteArray(StandardCharsets.US_ASCII))
            target.flush()
        }
    }

    // ---------------------------------------------------------------- commands ----

    private fun cmdMkdirRel(args: Array<String>) {
        require(args.size >= 5) { "mkdirrel <user> <pass> <baseUrl> <relPath>" }
        finish(runCatching { mkcol(args[1], args[2], buildRelUrl(args[3], args[4])) }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdMkdirsRel(args: Array<String>) {
        require(args.size >= 5) { "mkdirsrel <user> <pass> <baseUrl> <relPath>" }
        finish(runCatching { mkcolParentsRel(args[1], args[2], args[3], args[4]) }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdPutRel(args: Array<String>) {
        require(args.size >= 6) { "putrel <user> <pass> <baseUrl> <relPath> <localFile>" }
        val file = File(args[5])
        if (!file.isFile) { println("HTTP 000"); exitProcess(1) }
        val code = runCatching {
            putReplayableLocalFile(args[1], args[2], args[3], args[4], file, verifyContext = "cli-putrel")
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdPutBatchRel(args: Array<String>) {
        require(args.size >= 5) { "putbatchrel <user> <pass> <baseUrl> <baseRel>  (stdin: rel\tlocalFile lines)" }
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { putBatchRel(args[1], args[2], args[3], args[4], body) }
            .getOrElse { HttpCore.extractCode(it) to "ERROR\t${it.javaClass.simpleName}\t${it.message ?: ""}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdPutStdinChunkedRel(args: Array<String>) {
        require(args.size >= 5) { "putstdinchunkedrel <user> <pass> <baseUrl> <relPath>" }
        val code = runCatching {
            put(args[1], args[2], buildRelUrl(args[3], args[4]), System.`in`, contentLength = null, chunked = true)
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdPutStdinManagedRel(args: Array<String>) {
        require(args.size >= 5) { "putstdinmanagedrel <user> <pass> <baseUrl> <relPath> [mode] [ensureParentMkdir|skipParentMkdir]" }
        val mode = args.getOrNull(5) ?: "auto"
        val parentMode = args.getOrNull(6) ?: "ensureParentMkdir"
        val code = runCatching {
            putStdinManagedRel(args[1], args[2], args[3], args[4], mode, parentMode, System.`in`)
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdPutManagedRel(args: Array<String>) {
        require(args.size >= 6) { "putmanagedrel <user> <pass> <baseUrl> <relPath> <localFile> [mode] [ensureParentMkdir|skipParentMkdir]" }
        val mode = args.getOrNull(6) ?: "auto"
        val parentMode = args.getOrNull(7) ?: "ensureParentMkdir"
        val code = runCatching {
            putFileManagedRel(args[1], args[2], args[3], args[4], args[5], mode, parentMode)
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdManagedBatchPutRelWithParents(args: Array<String>) {
        require(args.size >= 4) { "managedbatchputrelwithparents <user> <pass> <baseUrl> [mode] [ensureParentMkdir|skipParentMkdir]  (stdin: rel\tlocalFile lines)" }
        val mode = args.getOrNull(4) ?: "auto"
        val parentMode = args.getOrNull(5) ?: "ensureParentMkdir"
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { managedBatchPutRelWithParents(args[1], args[2], args[3], mode, parentMode, "", body) }
            .getOrElse { e -> HttpCore.extractCode(e) to "FAIL\t.\t.\t${HttpCore.extractCode(e)}\t${e.javaClass.simpleName}\nSUMMARY\ttotal=0\tok=0\tfailed=1\tmode=exception\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdManagedListClassifyRel(args: Array<String>) {
        require(args.size >= 5) { "managedlistclassifyrel <user> <pass> <baseUrl> <relPath> [depth]" }
        val depth = args.getOrNull(5)?.toIntOrNull() ?: -1
        val code = runCatching {
            val result = classifyListRel(args[1], args[2], args[3], args[4], depth)
            if (result.first in 200..299) print(result.second)
            result.first
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdDirectChildrenRel(args: Array<String>) {
        require(args.size >= 5) { "directchildrenrel <user> <pass> <baseUrl> <relPath>" }
        val code = runCatching {
            val result = directChildrenRel(args[1], args[2], args[3], args[4])
            if (result.first in 200..299) print(result.second)
            result.first
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdDownloadManifestRel(args: Array<String>) {
        require(args.size >= 6) { "downloadmanifestrel <user> <pass> <baseUrl> <baseRel> <destDir>  (stdin: item lines)" }
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { downloadManifestRel(args[1], args[2], args[3], args[4], args[5], body) }
            .getOrElse { e -> HttpCore.extractCode(e) to "ERROR\t${sanitizeTsv(e.javaClass.simpleName)}\t${sanitizeTsv(e.message ?: "")}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdOrphanRootsRel(args: Array<String>) {
        require(args.size >= 5) { "orphanrootsrel <user> <pass> <baseUrl> <rootRel>" }
        val result = runCatching { orphanRootsRel(args[1], args[2], args[3], args[4]) }
            .getOrElse { e -> HttpCore.extractCode(e) to "ERROR\t${sanitizeTsv(e.javaClass.simpleName)}\t${sanitizeTsv(e.message ?: "")}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdManagedProbeRel(args: Array<String>) {
        require(args.size >= 4) { "managedproberel <user> <pass> <baseUrl> [relBase]" }
        val relBase = args.getOrNull(4) ?: ""
        val result = runCatching { managedProbeRel(args[1], args[2], args[3], relBase) }
            .getOrElse { e -> HttpCore.extractCode(e) to "step=exception error=${e.javaClass.simpleName} message=${e.message ?: ""}" }
        print(result.second)
        if (!result.second.endsWith("\n")) println()
        finish(result.first)
    }


    private fun cmdBackendProfileRel(args: Array<String>) {
        require(args.size >= 4) { "backendprofilerel <user> <pass> <baseUrl> [reason]" }
        val profile = webDavBackendProfile(args[1], args[2], args[3], args.getOrNull(4) ?: "cli")
        val providerHint = providerHintFromBaseUrl(args[3], profile.kind)
        val facts = featureFactsCache[featureFactsKey(args[3])]
        val alistServerHeader = if (isAlistFamily(profile.kind)) runCatching { parseKeyValueLines(optionsDav(args[1], args[2], buildRelUrl(args[3], "")).second)["server"].orEmpty() }.getOrDefault("") else ""
        val alistSecurity = alistSecurityAdvisory(profile.kind, alistServerHeader)
        println("schema	speedbackup.webdav_backend_profile.v3")
        println("kind	${profile.kind}")
        println("serverFamily	${serverFamilyForKind(profile.kind)}")
        println("serverDisplay	${serverDisplayForKind(profile.kind)}")
        println("behaviorProfile	${behaviorProfileForKind(profile.kind)}")
        println("providerId	${providerHint.id}")
        println("providerDisplay	${providerHint.displayName}")
        println("providerRegion	${providerHint.region}")
        println("providerClass	${providerHint.providerClass}")
        println("providerHintSource	${providerHint.source}")
        println("providerHintConfidence	${providerHint.confidence}")
        println("alistVersion	${alistSecurity.version}")
        println("alistSecurityAdvisory	${alistSecurity.cve}")
        println("alistPathTraversalRisk	${alistSecurity.state}")
        println("alistMinSafeVersion	${alistSecurity.minSafeVersion}")
        println("alistSecurityAction	${alistSecurity.action}")
        println("directAll	${if (profile.directAll) 1 else 0}")
        println("newPayloadDirect	${if (profile.newPayloadDirect) 1 else 0}")
        println("atomicReplace	${if (profile.atomicReplace) 1 else 0}")
        println("supportTier	${profile.supportTier}")
        println("featureSource	${profile.featureSource}")
        println("featureSummary	${featureSummary(facts)}")
        println("putStrategy	${putStrategyFor(profile, facts)}")
        println("listStrategy	${listStrategyFor(facts)}")
        println("publishStrategy	${publishStrategyFor(profile, facts)}")
        println("verifyStrategy	${verifyStrategyFor(facts)}")
        println("cleanupPolicy	${cleanupPolicyFor(profile, facts)}")
        println("securityAdvisory	${securityAdvisoryFor(profile, alistSecurity)}")
        println("supportsChunkedPut	${featureBool(facts?.supportsChunkedPut)}")
        println("supportsFixedPut	${featureBool(facts?.supportsFixedPut)}")
        println("supportsGetStream	${featureBool(facts?.supportsGetStream)}")
        println("supportsMove	${featureBool(facts?.supportsMove)}")
        println("supportsCopy	${featureBool(facts?.supportsCopy)}")
        println("supportsStat	${featureBool(facts?.supportsStat)}")
        println("supportsRemoteSize	${featureBool(facts?.supportsRemoteSize)}")
        println("supportsMkcol	${featureBool(facts?.supportsMkcol)}")
        println("supportsDelete	${featureBool(facts?.supportsDelete)}")
        println("supportsDepth0	${featureBool(facts?.supportsDepth0)}")
        println("supportsDepth1	${featureBool(facts?.supportsDepth1)}")
        println("supportsDepthInfinity	${featureBool(facts?.supportsDepthInfinity)}")
        println("supportsRecursiveWalkFallback	${featureBool(facts?.supportsRecursiveWalkFallback)}")
        println("supportsAtomicPublish	${featureBool(facts?.supportsAtomicPublish)}")
        println("supportsOverwriteMove	${featureBool(facts?.supportsOverwriteMove)}")
        println("supportsQuota	${featureBool(facts?.supportsQuota)}")
        println("cjkPathRetry	${if (profile.cjkPathRetry) 1 else 0}")
        println("postBodyTimeoutSec	${profile.postBodyTimeoutMs / 1000}")
        println("postBodySemantics	server_processing_until_put_response")
        finish(200)
    }

    private fun cmdCompatProbeRel(args: Array<String>) {
        require(args.size >= 4) { "compatProbeRel <user> <pass> <baseUrl> [testRel]" }
        val result = runCatching { compatProbeRel(args[1], args[2], args[3], args.getOrNull(4) ?: "") }
            .getOrElse { e -> HttpCore.extractCode(e) to compatProbeErrorJson(HttpCore.extractCode(e), "FAIL", e.javaClass.simpleName, e.message ?: "") }
        print(result.second)
        System.out.flush()
        System.err.println("HTTP ${result.first}")
        exitProcess(if (result.first in 200..299) 0 else 1)
    }

    private fun cmdEnsureBaseRel(args: Array<String>) {
        require(args.size >= 4) { "ensurebaserel <user> <pass> <configuredBaseUrl>" }
        val result = runCatching { ensureBaseRel(args[1], args[2], args[3]) }
            .getOrElse { e -> HttpCore.extractCode(e) to "state=exception\nerror=${e.javaClass.simpleName}\nmessage=${e.message ?: ""}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdEnsureDirRel(args: Array<String>) {
        require(args.size >= 5) { "ensuredirrel <user> <pass> <baseUrl> <relPath>" }
        val result = runCatching { ensureDirRel(args[1], args[2], args[3], args[4]) }
            .getOrElse { e -> HttpCore.extractCode(e) to "state=exception\nrel=${args.getOrNull(4) ?: ""}\nerror=${e.javaClass.simpleName}\nmessage=${e.message ?: ""}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdEnsureDirsBatchRel(args: Array<String>) {
        require(args.size >= 4) { "ensuredirsbatchrel <user> <pass> <baseUrl>  (stdin: rel lines)" }
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { ensureDirsBatchRel(args[1], args[2], args[3], body) }
            .getOrElse { e -> HttpCore.extractCode(e) to "FAIL\t.\t${HttpCore.extractCode(e)}\t${e.javaClass.simpleName}\nsummary\ttotal=0\tok=0\tbad=1\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdPrepareDirsPlanRel(args: Array<String>) {
        require(args.size >= 5) { "preparedirsplanrel <user> <pass> <baseUrl> <rootRel> [create|check] [progressFile]  (stdin: desired dir rel lines)" }
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { prepareDirsPlanRel(args[1], args[2], args[3], args[4], args.getOrNull(5) ?: "create", body, args.getOrNull(6) ?: "") }
            .getOrElse { e -> HttpCore.extractCode(e) to "FAIL\t.\t${HttpCore.extractCode(e)}\t${e.javaClass.simpleName}\nSUMMARY\ttotal=0\texisting=0\tcreated=0\tok=0\tfailed=1\trootStatus=0\tmode=exception\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdOptionsPreflightRel(args: Array<String>) {
        require(args.size >= 6) { "optionspreflightrel <user> <pass> <baseUrl> <relPath> <mode>" }
        val result = runCatching { optionsPreflightRel(args[1], args[2], args[3], args[4], args[5]) }
            .getOrElse { e -> HttpCore.extractCode(e) to "state=exception\nmode=${args.getOrNull(5) ?: "control"}\nmissing=\nerror=${e.javaClass.simpleName}\nmessage=${e.message ?: ""}\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdQuotaRel(args: Array<String>) {
        require(args.size >= 5) { "quotarel <user> <pass> <baseUrl> <relPath>" }
        val result = runCatching { quotaRel(args[1], args[2], args[3], args[4]) }
            .getOrElse { e -> HttpCore.extractCode(e) to "state=exception\navailableBytes=-1\nusedBytes=-1\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdVerifyUploadMapRel(args: Array<String>) {
        require(args.size >= 5) { "verifyuploadmaprel <user> <pass> <baseUrl> <rootRel>  (stdin: rel<TAB>expectedBytes)" }
        val body = readRequestBody(System.`in`, -1L).toString(StandardCharsets.UTF_8)
        val result = runCatching { verifyUploadMapRel(args[1], args[2], args[3], args[4], body) }
            .getOrElse { e -> HttpCore.extractCode(e) to "SUMMARY\ttotal=0\tverified=0\tmissing=0\tmismatch=0\tunverifiable=0\tstate=exception\n" }
        print(result.second)
        finish(result.first)
    }

    private fun cmdGetRel(args: Array<String>) {
        require(args.size >= 6) { "getrel <user> <pass> <baseUrl> <relPath> <localFile>" }
        val code = runCatching {
            FileOutputStream(args[5]).use { out -> getTo(args[1], args[2], buildRelUrl(args[3], args[4]), out) }
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdGetStdoutRel(args: Array<String>) {
        require(args.size >= 5) { "getstdoutrel <user> <pass> <baseUrl> <relPath>" }
        val code = runCatching { getTo(args[1], args[2], buildRelUrl(args[3], args[4]), System.out) }.getOrElse { HttpCore.extractCode(it) }
        System.out.flush()
        System.err.println("HTTP $code")
        exitProcess(if (code in 200..299) 0 else 1)
    }

    private fun cmdDeleteRel(args: Array<String>) {
        require(args.size >= 5) { "deleterel <user> <pass> <baseUrl> <relPath>" }
        finish(runCatching { delete(args[1], args[2], buildRelUrl(args[3], args[4])) }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdMoveRel(args: Array<String>) {
        require(args.size >= 6) { "moverel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]" }
        val overwrite = args.getOrNull(6)?.uppercase() != "F"
        finish(runCatching { move(args[1], args[2], buildRelUrl(args[3], args[4]), buildRelUrl(args[3], args[5]), overwrite) }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdCopyRel(args: Array<String>) {
        require(args.size >= 6) { "copyrel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]" }
        val overwrite = args.getOrNull(6)?.uppercase() != "F"
        finish(runCatching { copy(args[1], args[2], buildRelUrl(args[3], args[4]), buildRelUrl(args[3], args[5]), overwrite) }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdPropfindRel(args: Array<String>) {
        require(args.size >= 5) { "propfindrel <user> <pass> <baseUrl> <relPath> [depth]" }
        val depth = args.getOrNull(5)?.toIntOrNull() ?: 0
        finish(runCatching { propfindRaw(args[1], args[2], buildRelUrl(args[3], args[4]), depth).first }.getOrElse { HttpCore.extractCode(it) })
    }

    private fun cmdStatRel(args: Array<String>) {
        require(args.size >= 5) { "statrel <user> <pass> <baseUrl> <relPath>" }
        val code = runCatching {
            val result = statDav(args[1], args[2], buildRelUrl(args[3], args[4]))
            if (result.first in 200..299 && result.second != null) print(formatDavStat(result.second!!))
            result.first
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdOptionsRel(args: Array<String>) {
        require(args.size >= 5) { "optionsrel <user> <pass> <baseUrl> <relPath>" }
        val code = runCatching {
            val result = optionsDav(args[1], args[2], buildRelUrl(args[3], args[4]))
            if (result.first in 200..299) print(result.second)
            result.first
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdListRel(args: Array<String>) {
        require(args.size >= 5) { "listrel <user> <pass> <baseUrl> <relPath> [depth]" }
        val depth = args.getOrNull(5)?.toIntOrNull() ?: -1
        val code = runCatching {
            val (status, body) = propfindRaw(args[1], args[2], buildRelUrl(args[3], args[4]), depth)
            if (status in 200..299) print(parseDavList(body))
            status
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdClassifyListRel(args: Array<String>) {
        require(args.size >= 5) { "classifylistrel <user> <pass> <baseUrl> <relPath> [depth]" }
        val depth = args.getOrNull(5)?.toIntOrNull() ?: -1
        val code = runCatching {
            val result = classifyListRel(args[1], args[2], args[3], args[4], depth)
            if (result.first in 200..299) print(result.second)
            result.first
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdEncodePath(args: Array<String>) {
        require(args.size >= 2) { "encodepath <text>" }
        print(HttpCore.percentEncodePath(args[1]))
    }

    private fun cmdDecodePath(args: Array<String>) {
        require(args.size >= 2) { "decodepath <text>" }
        print(HttpCore.percentDecodePath(args[1]))
    }

    // ---------------------------------------------------------------- relative URL API ----

    private fun buildRelUrl(baseUrl: String, relPath: String): String {
        val base = baseUrl.trimEnd('/')
        val rel = sanitizeRelPath(relPath)
        if (rel.isEmpty()) return base
        return "$base/$rel"
    }

    private fun sanitizeRelPath(relPath: String): String {
        val normalized = relPath.replace('\\', '/')
        if (normalized.isEmpty() || normalized == ".") return ""
        require(!normalized.startsWith("/")) { "WEBDAV_REL_PATH_REJECT absolute" }
        val raw = normalized.trim('/')
        if (raw.isEmpty() || raw == ".") return ""
        val out = ArrayList<String>()
        val ctrl = Regex("[\\u0000-\\u001F\\u007F]")
        for (partRaw in raw.split('/')) {
            val part = partRaw.trim()
            require(part.isNotEmpty() && part != ".") { "WEBDAV_REL_PATH_REJECT empty_component" }
            val decoded = runCatching { HttpCore.percentDecodePath(part) }.getOrElse { part }
            require(part != ".." && decoded != "..") { "WEBDAV_REL_PATH_REJECT traversal" }
            require(!decoded.contains('/') && !decoded.contains('\\')) { "WEBDAV_REL_PATH_REJECT encoded_separator" }
            require(!ctrl.containsMatchIn(part) && !ctrl.containsMatchIn(decoded)) { "WEBDAV_REL_PATH_REJECT control_char" }
            out.add(part)
        }
        return out.joinToString("/")
    }

    // ---------------------------------------------------------------- WebDAV HTTP ----

    private fun invalidateListCache() {
        if (listOkCache.isNotEmpty()) listOkCache.clear()
    }

    private fun invalidateDirectoryCache() {
        if (dirStateCache.isNotEmpty()) dirStateCache.clear()
        if (mkcolOkCache.isNotEmpty()) mkcolOkCache.clear()
    }

    private fun markDir(url: String, state: DirState) {
        dirStateCache[url] = state
        if (state == DirState.EXISTS) mkcolOkCache[url] = true else mkcolOkCache.remove(url)
    }

    private fun isTransientWebDavCode(code: Int): Boolean {
        // Match the failure classes that are plausibly transient/retryable. Avoid retrying
        // permanent protocol/feature errors such as 501 Not Implemented.
        return code == 0 || code == 408 || code == 423 || code == 425 || code == 429 ||
            code == 500 || code == 502 || code == 503 || code == 504 || code == 509
    }

    private fun policyFor(operation: DavOperation, code: Int): DavPolicyDecision {
        return when (operation) {
            DavOperation.MKCOL -> when (code) {
                200, 201, 204 -> DavPolicyDecision(true, normalizedCode = code, reason = "mkcol-ok")
                405 -> DavPolicyDecision(false, normalizedCode = code, reason = "mkcol-already-exists-needs-propfind-confirm")
                409 -> DavPolicyDecision(false, normalizedCode = code, reason = "mkcol-parent-missing")
                else -> DavPolicyDecision(false, retryable = isTransientWebDavCode(code), normalizedCode = code, reason = "mkcol-fail")
            }
            DavOperation.MOVE, DavOperation.COPY -> when (code) {
                200, 201, 204 -> DavPolicyDecision(true, normalizedCode = code, reason = "move-copy-ok")
                409 -> DavPolicyDecision(false, normalizedCode = code, reason = "parent-missing")
                412 -> DavPolicyDecision(false, normalizedCode = code, reason = "overwrite-denied")
                else -> DavPolicyDecision(false, retryable = isTransientWebDavCode(code), normalizedCode = code, reason = "move-copy-fail")
            }
            DavOperation.DELETE -> when (code) {
                200, 202, 204, 404 -> DavPolicyDecision(true, normalizedCode = if (code == 404) 204 else code, reason = "delete-cleanup-ok")
                else -> DavPolicyDecision(false, retryable = isTransientWebDavCode(code), normalizedCode = code, reason = "delete-fail")
            }
            DavOperation.OPTIONS, DavOperation.PROPFIND, DavOperation.HEAD, DavOperation.GET -> {
                if (code in 200..299) DavPolicyDecision(true, normalizedCode = code, reason = "read-ok")
                else DavPolicyDecision(false, retryable = isTransientWebDavCode(code), normalizedCode = code, reason = "read-fail")
            }
            DavOperation.PUT -> {
                if (code in 200..299) DavPolicyDecision(true, normalizedCode = code, reason = "put-ok")
                else DavPolicyDecision(false, retryable = false, normalizedCode = code, reason = if (isAmbiguousPutCode(code)) "put-fail-verify-eligible-no-retry" else "put-fail-no-body-replay")
            }
        }
    }

    private fun pacerSleepMs(attempt: Int, retryAfterMs: Long): Long {
        val base = (250L * (1L shl attempt.coerceAtMost(5))).coerceAtMost(8_000L)
        val jitter = ThreadLocalRandom.current().nextLong((base / 3L + 1L).coerceAtLeast(1L))
        return maxOf(base + jitter, retryAfterMs.coerceAtMost(30_000L)).coerceAtMost(30_000L)
    }

    private fun pacedCode(operation: DavOperation, maxAttempts: Int = 4, block: () -> Int): Int {
        var attempt = 0
        var lastCode = 0
        val started = System.currentTimeMillis()
        while (attempt < maxAttempts) {
            val code = runCatching { block() }.getOrElse { HttpCore.extractCode(it) }
            lastCode = code
            val retryAfterMs = http.consumeLastRetryAfterMs()
            val localPolicyReject = http.consumeLastLocalPolicyReject()
            val decision = policyFor(operation, code)
            if (localPolicyReject || decision.ok || !decision.retryable || attempt + 1 >= maxAttempts) return code
            val sleepMs = pacerSleepMs(attempt, retryAfterMs)
            if (System.currentTimeMillis() - started + sleepMs > 60_000L) return code
            infoLog("WEBDAV_PACER_RETRY op=$operation code=$code attempt=${attempt + 1} sleepMs=$sleepMs retryAfterMs=$retryAfterMs mode=r610")
            runCatching { Thread.sleep(sleepMs) }
            attempt++
        }
        return lastCode
    }

    private fun <T> pacedPair(operation: DavOperation, empty: T, maxAttempts: Int = 4, block: () -> Pair<Int, T>): Pair<Int, T> {
        var attempt = 0
        var last: Pair<Int, T> = 0 to empty
        val started = System.currentTimeMillis()
        while (attempt < maxAttempts) {
            val result = runCatching { block() }.getOrElse { HttpCore.extractCode(it) to empty }
            last = result
            val retryAfterMs = http.consumeLastRetryAfterMs()
            val localPolicyReject = http.consumeLastLocalPolicyReject()
            val decision = policyFor(operation, result.first)
            if (localPolicyReject || decision.ok || !decision.retryable || attempt + 1 >= maxAttempts) return result
            val sleepMs = pacerSleepMs(attempt, retryAfterMs)
            if (System.currentTimeMillis() - started + sleepMs > 60_000L) return result
            infoLog("WEBDAV_PACER_RETRY op=$operation code=${result.first} attempt=${attempt + 1} sleepMs=$sleepMs retryAfterMs=$retryAfterMs mode=r610")
            runCatching { Thread.sleep(sleepMs) }
            attempt++
        }
        return last
    }

    private fun mkcol(user: String, pass: String, url: String): Int {
        return pacedCode(DavOperation.MKCOL) {
            http.request(
                "MKCOL", url, user, pass, mapOf("Content-Length" to "0"),
                followRedirects = true, canReplayBody = true
            )
        }
    }

    private fun collectionExists(user: String, pass: String, url: String): Boolean {
        when (dirStateCache[url]) {
            DirState.EXISTS -> return true
            DirState.MISSING -> return false
            DirState.FAILED -> return false
            null -> {}
        }
        val (code, body) = propfindRaw(user, pass, url, 0)
        if (code == 404) {
            markDir(url, DirState.MISSING)
            return false
        }
        if (code !in 200..299) {
            dirStateCache[url] = DirState.FAILED
            return false
        }
        val entry = runCatching { parseDavEntries(body).firstOrNull() }.getOrNull()
        val exists = entry?.isDirectory ?: true
        markDir(url, if (exists) DirState.EXISTS else DirState.MISSING)
        return exists
    }

    private fun mkcolIdempotent(user: String, pass: String, url: String): Int {
        if (mkcolOkCache[url] == true || dirStateCache[url] == DirState.EXISTS) return 200
        if (collectionExists(user, pass, url)) return 200
        val code = mkcol(user, pass, url)
        val decision = policyFor(DavOperation.MKCOL, code)
        if (decision.ok) {
            markDir(url, DirState.EXISTS)
            invalidateListCache()
            return decision.normalizedCode
        }
        // 405/already-exists, ambiguous 0, and odd NAS/rclone responses only become
        // success after a real PROPFIND confirms the collection. 409 remains a
        // parent-missing signal to the caller's chain mkdir path.
        if (collectionExists(user, pass, url)) return 200
        dirStateCache[url] = if (code == 404 || code == 409) DirState.MISSING else DirState.FAILED
        return code
    }

    private fun mkcolParentsRel(user: String, pass: String, baseUrl: String, relPath: String): Int {
        val rel = relPath.trim('/').takeIf { it.isNotEmpty() && it != "." } ?: return 200
        val parts = rel.split('/').filter { it.isNotEmpty() }
        var cur = ""
        var lastCode = 200
        for (seg in parts) {
            cur = if (cur.isEmpty()) seg else "$cur/$seg"
            val code = mkcolIdempotent(user, pass, buildRelUrl(baseUrl, cur))
            if (code !in 200..299) return code
            lastCode = code
        }
        return lastCode
    }

    private data class ConfiguredBase(val origin: String, val rel: String)

    private fun splitConfiguredBaseUrl(configuredBaseUrl: String): ConfiguredBase? {
        val value = configuredBaseUrl.trim().trimEnd('/')
        val prefix = when {
            value.startsWith("http://", ignoreCase = true) -> "http://"
            value.startsWith("https://", ignoreCase = true) -> "https://"
            else -> return null
        }
        val rest = value.substring(prefix.length)
        if (rest.isEmpty()) return null
        val slash = rest.indexOf('/')
        val authority = if (slash < 0) rest else rest.substring(0, slash)
        if (authority.isEmpty()) return null
        var path = if (slash < 0) "" else rest.substring(slash + 1)
        path = path.substringBefore('#').substringBefore('?').trim('/')
        return ConfiguredBase(prefix + authority, path)
    }

    /**
     * Validate and, only for HTTP 404, create the configured WebDAV base path.
     * This centralizes URL splitting, STAT, parent-chain MKCOL and final verification
     * in the long-lived Dex daemon instead of duplicating the state machine in shell.
     */
    private fun ensureBaseRel(user: String, pass: String, configuredBaseUrl: String): Pair<Int, String> {
        val base = splitConfiguredBaseUrl(configuredBaseUrl)
            ?: return 400 to "state=invalid\norigin=\nrel=\nstat=400\nmkdir=0\nverify=0\n"
        if (base.rel.isEmpty()) {
            return 200 to "state=root\norigin=${base.origin}\nrel=\nstat=200\nmkdir=0\nverify=200\n"
        }
        val target = buildRelUrl(base.origin, base.rel)
        val statCode = statDav(user, pass, target).first
        if (statCode in 200..299) {
            markDir(target, DirState.EXISTS)
            return statCode to "state=exists\norigin=${base.origin}\nrel=${base.rel}\nstat=$statCode\nmkdir=0\nverify=$statCode\n"
        }
        if (statCode != 404) {
            return statCode to "state=unavailable\norigin=${base.origin}\nrel=${base.rel}\nstat=$statCode\nmkdir=0\nverify=0\n"
        }
        val mkdirCode = mkcolParentsRel(user, pass, base.origin, base.rel)
        if (mkdirCode !in 200..299) {
            return mkdirCode to "state=create_failed\norigin=${base.origin}\nrel=${base.rel}\nstat=$statCode\nmkdir=$mkdirCode\nverify=0\n"
        }
        val verifyCode = statDav(user, pass, target).first
        if (verifyCode in 200..299) {
            markDir(target, DirState.EXISTS)
            invalidateListCache()
            return verifyCode to "state=created\norigin=${base.origin}\nrel=${base.rel}\nstat=$statCode\nmkdir=$mkdirCode\nverify=$verifyCode\n"
        }
        return verifyCode to "state=verify_failed\norigin=${base.origin}\nrel=${base.rel}\nstat=$statCode\nmkdir=$mkdirCode\nverify=$verifyCode\n"
    }

    /** Ensure a relative collection exists under an already configured base URL. */
    private fun ensureDirRel(user: String, pass: String, baseUrl: String, relPath: String): Pair<Int, String> {
        val rel = relPath.trim().trim('/').ifEmpty { "." }
        val target = buildRelUrl(baseUrl, rel)
        val statCode = statDav(user, pass, target).first
        if (statCode in 200..299) {
            markDir(target, DirState.EXISTS)
            return statCode to "state=exists\nrel=$rel\nstat=$statCode\nmkdir=0\nverify=$statCode\n"
        }
        if (statCode != 404) {
            return statCode to "state=unavailable\nrel=$rel\nstat=$statCode\nmkdir=0\nverify=0\n"
        }
        val mkdirCode = mkcolParentsRel(user, pass, baseUrl, rel)
        if (mkdirCode !in 200..299) {
            return mkdirCode to "state=create_failed\nrel=$rel\nstat=$statCode\nmkdir=$mkdirCode\nverify=0\n"
        }
        val verifyCode = statDav(user, pass, target).first
        if (verifyCode in 200..299) {
            markDir(target, DirState.EXISTS)
            invalidateListCache()
            return verifyCode to "state=created\nrel=$rel\nstat=$statCode\nmkdir=$mkdirCode\nverify=$verifyCode\n"
        }
        return verifyCode to "state=verify_failed\nrel=$rel\nstat=$statCode\nmkdir=$mkdirCode\nverify=$verifyCode\n"
    }

    /** Ensure multiple relative collections in one daemon request. Input body: one rel path per line. */
    private fun ensureDirsBatchRel(user: String, pass: String, baseUrl: String, body: String): Pair<Int, String> {
        val rels = body.lineSequence()
            .map { it.trim().trim('/') }
            .filter { it.isNotEmpty() && it != "." }
            .distinct()
            .toList()
        if (rels.isEmpty()) return 200 to "summary\ttotal=0\tok=0\tbad=0\n"
        val out = StringBuilder()
        var ok = 0
        var bad = 0
        var finalCode = 200
        for (rel in rels) {
            val result = ensureDirRel(user, pass, baseUrl, rel)
            val code = result.first
            val values = parseKeyValueLines(result.second)
            val state = values["state"].orEmpty().ifEmpty { if (code in 200..299) "ok" else "fail" }
            if (code in 200..299) {
                ok++
                out.append(if (state == "exists") "EXISTS" else "OK")
                    .append('\t').append(rel)
                    .append('\t').append(code)
                    .append('\t').append(state)
                    .append('\n')
            } else {
                bad++
                if (finalCode in 200..299) finalCode = code
                out.append("FAIL")
                    .append('\t').append(rel)
                    .append('\t').append(code)
                    .append('\t').append(state)
                    .append('\n')
            }
        }
        out.append("summary\ttotal=").append(rels.size)
            .append("\tok=").append(ok)
            .append("\tbad=").append(bad)
            .append('\n')
        if (ok > 0) invalidateListCache()
        return finalCode to out.toString()
    }

    /**
     * Dex-side WebDAV directory preparation plan.
     *
     * tools still owns the backup plan and passes desired app directory rels. WebDavUtil owns
     * the WebDAV transaction: list direct children of rootRel, classify which desired parents
     * already exist, create only missing parents, and return TSV facts for tools cache seeding.
     */
    private fun prepareDirsPlanRel(user: String, pass: String, baseUrl: String, rootRelRaw: String, modeRaw: String, body: String, progressFile: String = ""): Pair<Int, String> {
        val rootRel = sanitizeRelPath(rootRelRaw).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val createMissing = when (modeRaw.trim().lowercase(java.util.Locale.US)) {
            "0", "false", "no", "check", "checkonly", "dryrun" -> false
            else -> true
        }
        val desired = body.lineSequence()
            .map { normalizeDesiredDirRel(it, rootRel) }
            .filter { it.isNotEmpty() }
            .distinct()
            .toList()
        if (desired.isEmpty()) {
            writePrepareDirsProgress(progressFile, 0, 0, 0, 0, 0, "EMPTY", "")
            return 200 to "SUMMARY\ttotal=0\texisting=0\tcreated=0\tok=0\tfailed=0\trootStatus=0\tcreateTotal=0\tmode=${if (createMissing) "create" else "check"}\n"
        }

        val existing = HashSet<String>()
        var rootStatus = 0
        val rootUrl = buildRelUrl(baseUrl, rootRel)
        runCatching { propfindRaw(user, pass, rootUrl, 1) }
            .onSuccess { (status, respBody) ->
                rootStatus = status
                if (status in 200..299) {
                    for (entry in parseDavEntries(respBody)) {
                        if (!entry.isDirectory) continue
                        val childRel = davEntryRelativePath(entry.href, rootRel)
                        if (childRel.isEmpty() || childRel.contains('/')) continue
                        val fullRel = if (rootRel.isEmpty()) sanitizeRelPath(childRel) else sanitizeRelPath("$rootRel/$childRel")
                        if (fullRel.isNotEmpty()) {
                            existing.add(fullRel)
                            markDir(buildRelUrl(baseUrl, fullRel), DirState.EXISTS)
                        }
                    }
                }
            }
            .onFailure { rootStatus = HttpCore.extractCode(it) }

        if (rootStatus !in 200..299 && rootStatus != 404 && rootStatus != 410) {
            val out = StringBuilder()
            desired.forEach { rel -> out.append("FAIL\t").append(rel).append("\t").append(rootStatus).append("\troot-list-failed\n") }
            out.append("SUMMARY\ttotal=").append(desired.size)
                .append("\texisting=0\tcreated=0\tok=0\tfailed=").append(desired.size)
                .append("\trootStatus=").append(rootStatus)
                .append("\tcreateTotal=0")
                .append("\tmode=").append(if (createMissing) "create" else "check")
                .append('\n')
            writePrepareDirsProgress(progressFile, 0, 0, 0, 0, desired.size, "ROOT_LIST_FAILED", rootRel)
            return rootStatus to out.toString()
        }

        val out = StringBuilder(desired.size * 48)
        val missing = ArrayList<String>()
        var existingCount = 0
        for (rel in desired) {
            if (existing.contains(rel)) {
                existingCount++
                out.append("EXISTING\t").append(rel).append("\t200\tlist-depth1\n")
            } else {
                missing.add(rel)
            }
        }

        if (!createMissing) {
            missing.forEach { rel -> out.append("MISSING\t").append(rel).append("\t404\tcheck-only\n") }
            val failedCount = missing.size
            val okCount = existingCount
            out.append("SUMMARY\ttotal=").append(desired.size)
                .append("\texisting=").append(existingCount)
                .append("\tcreated=0")
                .append("\tok=").append(okCount)
                .append("\tfailed=").append(failedCount)
                .append("\trootStatus=").append(rootStatus)
                .append("\tcreateTotal=0")
                .append("\tmode=check")
                .append('\n')
            writePrepareDirsProgress(progressFile, desired.size, desired.size, existingCount, 0, failedCount, "CHECK_DONE", rootRel)
            return (if (failedCount == 0) 200 else 404) to out.toString()
        }

        val createTotal = missing.size
        if (createTotal == 0) {
            writePrepareDirsProgress(progressFile, 0, 0, existingCount, 0, 0, "ALL_EXISTING", rootRel)
            out.append("SUMMARY\ttotal=").append(desired.size)
                .append("\texisting=").append(existingCount)
                .append("\tcreated=0\tok=").append(existingCount)
                .append("\tfailed=0")
                .append("\trootStatus=").append(rootStatus)
                .append("\tcreateTotal=0\tworkers=0\telapsedMs=0")
                .append("\tstrategy=list-only-existing\tmode=create\n")
            infoLog("WEBDAV_PREPARE_DIRS_PARALLEL_DONE root=$rootRel total=${desired.size} createTotal=0 workers=0 existing=$existingCount created=0 failed=0 elapsedMs=0 mode=r671")
            return 200 to out.toString()
        }
        writePrepareDirsProgress(progressFile, createTotal, 0, existingCount, 0, 0, "CREATE_BEGIN", rootRel)

        data class CreateResult(val rel: String, val code: Int, val state: String)
        val startedMs = System.currentTimeMillis()
        val workers = minOf(4, createTotal).coerceAtLeast(1)
        val executor = Executors.newFixedThreadPool(workers)
        val completion = ExecutorCompletionService<CreateResult>(executor)
        for (rel in missing) {
            completion.submit(java.util.concurrent.Callable {
                val result = runCatching { createKnownMissingDirectChildRel(user, pass, baseUrl, rel) }
                    .getOrElse { HttpCore.extractCode(it) to "state=exception\n" }
                val code = result.first
                val state = parseKeyValueLines(result.second)["state"].orEmpty().ifEmpty { if (code in 200..299) "ok" else "fail" }
                CreateResult(rel, code, state)
            })
        }
        var createdCount = 0
        var okCount = existingCount
        var failedCount = 0
        var finalCode = 200
        var doneCreate = 0
        try {
            repeat(createTotal) {
                val item = completion.take().get()
                if (item.code in 200..299) {
                    okCount++
                    if (item.state == "created") createdCount++ else existingCount++
                    out.append(if (item.state == "created") "CREATED" else "EXISTING")
                        .append('\t').append(item.rel)
                        .append('\t').append(item.code)
                        .append('\t').append(item.state)
                        .append('\n')
                    doneCreate++
                    writePrepareDirsProgress(progressFile, createTotal, doneCreate, existingCount, createdCount, failedCount, if (item.state == "created") "CREATED" else "EXISTING", item.rel)
                } else {
                    failedCount++
                    if (finalCode in 200..299) finalCode = item.code
                    out.append("FAIL")
                        .append('\t').append(item.rel)
                        .append('\t').append(item.code)
                        .append('\t').append(item.state)
                        .append('\n')
                    doneCreate++
                    writePrepareDirsProgress(progressFile, createTotal, doneCreate, existingCount, createdCount, failedCount, "FAIL", item.rel)
                }
            }
        } finally {
            executor.shutdownNow()
        }
        val elapsedMs = (System.currentTimeMillis() - startedMs).coerceAtLeast(0L)
        out.append("SUMMARY\ttotal=").append(desired.size)
            .append("\texisting=").append(existingCount)
            .append("\tcreated=").append(createdCount)
            .append("\tok=").append(okCount)
            .append("\tfailed=").append(failedCount)
            .append("\trootStatus=").append(rootStatus)
            .append("\tcreateTotal=").append(createTotal)
            .append("\tworkers=").append(workers)
            .append("\telapsedMs=").append(elapsedMs)
            .append("\tstrategy=parallel-known-missing-direct-mkcol")
            .append("\tmode=create")
            .append('\n')
        infoLog("WEBDAV_PREPARE_DIRS_PARALLEL_DONE root=$rootRel total=${desired.size} createTotal=$createTotal workers=$workers existing=$existingCount created=$createdCount failed=$failedCount elapsedMs=$elapsedMs mode=r671")
        if (createdCount > 0) invalidateListCache()
        return finalCode to out.toString()
    }



    /**
     * Fast path for a direct child that the immediately preceding Depth:1 root listing proved missing.
     * Skip only the redundant pre-STAT/parent walk: MKCOL success is still confirmed by a real STAT so
     * a server that returns a false 2xx cannot be cached/reported as created. Any odd response or failed
     * verification falls back to ensureDirRel(), preserving the previous conservative semantics.
     */
    private fun createKnownMissingDirectChildRel(user: String, pass: String, baseUrl: String, relPath: String): Pair<Int, String> {
        val rel = sanitizeRelPath(relPath).trim('/').takeIf { it.isNotEmpty() && it != "." }
            ?: return 400 to "state=invalid\nrel=\n"
        val target = buildRelUrl(baseUrl, rel)
        val code = mkcol(user, pass, target)
        val decision = policyFor(DavOperation.MKCOL, code)
        val verify = statDav(user, pass, target).first
        if (verify in 200..299) {
            markDir(target, DirState.EXISTS)
            invalidateListCache()
            val state = if (decision.ok) "created" else "exists"
            return verify to "state=$state\nrel=$rel\nstat=skipped-known-missing\nmkdir=$code\nverify=$verify\n"
        }
        // Preserve the historical parent-chain recovery / retry behavior for odd servers and
        // never trust an unverified MKCOL 2xx.
        return ensureDirRel(user, pass, baseUrl, rel)
    }

    private fun writePrepareDirsProgress(pathRaw: String, total: Int, done: Int, existing: Int, created: Int, failed: Int, status: String, rel: String) {
        val path = pathRaw.trim()
        if (path.isEmpty()) return
        if (!(path.startsWith("/data/local/tmp/") || path.startsWith("/data/speed_debug/"))) return
        runCatching {
            val file = File(path)
            file.parentFile?.mkdirs()
            val safeStatus = status.replace('\t', '_').replace('\n', '_').replace('\r', '_')
            val safeRel = rel.replace('\t', '_').replace('\n', '_').replace('\r', '_')
            file.writeText("$done\t$total\t$existing\t$created\t$failed\t$safeStatus\t$safeRel\n", StandardCharsets.UTF_8)
        }
    }

    private fun normalizeDesiredDirRel(raw: String, rootRel: String): String {
        val rel = sanitizeRelPath(raw.trim()).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        if (rel.isEmpty()) return ""
        if (rootRel.isEmpty()) return rel
        if (rel == rootRel || rel.startsWith("$rootRel/")) return rel
        return if (!rel.contains('/')) sanitizeRelPath("$rootRel/$rel") else rel
    }

    private fun parseKeyValueLines(text: String): Map<String, String> {
        val result = linkedMapOf<String, String>()
        text.lineSequence().forEach { line ->
            val index = line.indexOf('=')
            if (index > 0) result[line.substring(0, index).trim().lowercase()] = line.substring(index + 1).trim()
        }
        return result
    }

    /**
     * OPTIONS capability preflight. Missing Allow methods stay advisory, matching the
     * historical shell policy; the real managed/stream probe remains authoritative.
     */
    private fun optionsPreflightRel(user: String, pass: String, baseUrl: String, relPath: String, modeRaw: String): Pair<Int, String> {
        val rel = relPath.trim().ifEmpty { "." }
        val mode = modeRaw.trim().lowercase().ifEmpty { "control" }
        val target = buildRelUrl(baseUrl, rel)
        val result = optionsDav(user, pass, target)
        val values = parseKeyValueLines(result.second)
        val allow = values["allow"].orEmpty()
        val dav = values["dav"].orEmpty()
        val server = values["server"].orEmpty()
        val backendKind = classifyServerKind(baseUrl, result.first, result.second)
        val alistSecurity = alistSecurityAdvisory(backendKind, server)
        cacheServerKind(baseUrl, result.first, backendKind)
        val providerHint = providerHintFromBaseUrl(baseUrl, backendKind)
        val serverFamily = serverFamilyForKind(backendKind)
        val serverDisplay = serverDisplayForKind(backendKind)
        val behaviorProfile = behaviorProfileForKind(backendKind)
        val quota = runCatching { quotaDav(user, pass, target).second }.getOrDefault(WebDavQuota())
        val required = when (mode) {
            "stream", "atomic", "upload" -> listOf("OPTIONS", "PROPFIND", "PUT", "GET", "DELETE", "MOVE")
            "restore" -> listOf("OPTIONS", "PROPFIND", "GET")
            else -> listOf("OPTIONS", "PROPFIND", "PUT", "GET", "DELETE")
        }
        val available = allow.split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() }.toSet()
        val missing = if (allow.isEmpty()) emptyList() else required.filterNot { available.contains(it) }
        val state = if (result.first in 200..299) "ok" else "unavailable"
        val body = buildString {
            append("state=").append(state).append('\n')
            append("mode=").append(mode).append('\n')
            append("rel=").append(rel).append('\n')
            append("allow=").append(allow).append('\n')
            append("dav=").append(dav).append('\n')
            append("server=").append(server).append('\n')
            append("backendKind=").append(backendKind).append('\n')
            append("serverFamily=").append(serverFamily).append('\n')
            append("serverDisplay=").append(serverDisplay).append('\n')
            append("behaviorProfile=").append(behaviorProfile).append('\n')
            append("supportTier=").append(supportTier(backendKind, featureFactsCache[featureFactsKey(baseUrl)])).append('\n')
            append("featureSource=").append(featureFactsCache[featureFactsKey(baseUrl)]?.source ?: "server-profile").append('\n')
            append("featureSummary=").append(featureSummary(featureFactsCache[featureFactsKey(baseUrl)])).append('\n')
            append("providerId=").append(providerHint.id).append('\n')
            append("providerDisplay=").append(providerHint.displayName).append('\n')
            append("providerRegion=").append(providerHint.region).append('\n')
            append("providerClass=").append(providerHint.providerClass).append('\n')
            append("providerHintSource=").append(providerHint.source).append('\n')
            append("providerHintConfidence=").append(providerHint.confidence).append('\n')
            append("alistVersion=").append(alistSecurity.version).append('\n')
            append("alistSecurityAdvisory=").append(alistSecurity.cve).append('\n')
            append("alistPathTraversalRisk=").append(alistSecurity.state).append('\n')
            append("alistMinSafeVersion=").append(alistSecurity.minSafeVersion).append('\n')
            append("alistSecurityAction=").append(alistSecurity.action).append('\n')
            append("quotaState=").append(quota.state).append('\n')
            append("quotaAvailableBytes=").append(quota.availableBytes ?: -1L).append('\n')
            append("quotaUsedBytes=").append(quota.usedBytes ?: -1L).append('\n')
            append("missing=").append(missing.joinToString(" ")).append('\n')
            append("allowAdvisory=1\n")
        }
        return result.first to body
    }

    private fun optionsDav(user: String, pass: String, url: String): Pair<Int, String> {
        return pacedPair(DavOperation.OPTIONS, "") {
            var text = ""
            val code = http.request(
                "OPTIONS", url, user, pass, mapOf("Content-Length" to "0"),
                followRedirects = true, canReplayBody = true
            ) { status, headers, input ->
                if (status in 200..299) {
                    val allow = headers.firstHeaderCompat("allow") ?: ""
                    val dav = headers.firstHeaderCompat("dav") ?: ""
                    val server = headers.firstHeaderCompat("server") ?: ""
                    text = buildString {
                        append("allow=").append(allow).append('\n')
                        append("dav=").append(dav).append('\n')
                        append("server=").append(server).append('\n')
                    }
                    HttpCore.discardResponseBody(headers, input)
                } else {
                    HttpCore.discardErrorResponseBody(headers, input)
                }
            }
            code to text
        }
    }

    private fun statDav(user: String, pass: String, url: String): Pair<Int, DavEntry?> {
        var headEntry: DavEntry? = null
        val headCode = pacedCode(DavOperation.HEAD) { http.request(
            "HEAD", url, user, pass, emptyMap(),
            followRedirects = true, canReplayBody = true
        ) { status, headers, _ ->
            if (status in 200..299) {
                val len = headers.firstHeaderCompat("content-length")?.toLongOrNull() ?: -1L
                val etag = headers.firstHeaderCompat("etag") ?: ""
                val modified = headers.firstHeaderCompat("last-modified") ?: ""
                headEntry = DavEntry(normalizeDavHref(url), len, url.endsWith("/"), etag, modified, "", status)
            }
            // HEAD responses must not have a message body even when Content-Length
            // describes the selected representation. Do not call discardResponseBody()
            // here: reading Content-Length bytes after HEAD blocks until timeout/EOF
            // on common WebDAV servers and turns a valid 2xx HEAD into HTTP 0.
        } }
        if (headCode in 200..299 && headEntry != null) return headCode to headEntry

        val (pfCode, body) = propfindRaw(user, pass, url, 0)
        if (pfCode !in 200..299) return pfCode to null
        val entry = parseDavEntries(body).firstOrNull()
        return pfCode to entry
    }

    private fun formatDavStat(e: DavEntry): String {
        return buildString {
            append(e.href).append('\t').append(e.length).append('\t').append(if (e.isDirectory) "D" else "F")
            append('\t').append(e.etag)
            append('\t').append(e.lastModified)
            if (e.displayName.isNotEmpty()) append('\t').append(e.displayName)
            append('\n')
        }
    }

    private fun mkcolCached(user: String, pass: String, url: String): Int {
        if (mkcolOkCache[url] == true || dirStateCache[url] == DirState.EXISTS) return 200
        val code = mkcolIdempotent(user, pass, url)
        if (code in 200..299) invalidateListCache()
        return code
    }

    private fun listCached(user: String, pass: String, url: String, depth: Int): Pair<Int, String> {
        val key = ListCacheKey(url, depth)
        listOkCache[key]?.let { return 200 to it }
        val (status, body) = propfindRaw(user, pass, url, depth)
        if (status !in 200..299) return status to ""
        markDir(url, DirState.EXISTS)
        val parsed = parseDavList(body)
        listOkCache[key] = parsed
        return status to parsed
    }

    private data class CompatProbeStep(val name: String, val code: Int, val ok: Boolean, val detail: String = "")

    private enum class WebDavVendorProfile(val wireName: String) {
        AUTO("auto"),
        RCLONE("rclone"),
        NEXTCLOUD("nextcloud"),
        JIANGUOYUN("jianguoyun"),
        PAN123("123pan"),
        GENERIC("generic"),
    }

    private data class WebDavQuirks(
        val profile: WebDavVendorProfile,
        val allowHeaderAdvisory: Boolean,
        val tolerateIncompleteAllow: Boolean,
        val confirmMkcolWithPropfind: Boolean,
        val mkcol409MeansParentMissing: Boolean,
        val moveCopy201204Ok: Boolean,
        val delete404Ok: Boolean,
        val relPathOnly: Boolean,
        val propfindXmlTolerant: Boolean,
        val directoryCache: String,
        val pacerRetryBackoff: Boolean,
    ) {
        fun names(): List<String> {
            val out = ArrayList<String>()
            if (allowHeaderAdvisory) out.add("allow_header_advisory")
            if (tolerateIncompleteAllow) out.add("incomplete_allow_tolerated")
            if (confirmMkcolWithPropfind) out.add("mkcol_confirm_propfind")
            if (mkcol409MeansParentMissing) out.add("mkcol_409_parent_missing")
            if (moveCopy201204Ok) out.add("move_copy_201_204_ok")
            if (delete404Ok) out.add("delete_404_cleanup_ok")
            if (relPathOnly) out.add("rel_path_only")
            if (propfindXmlTolerant) out.add("propfind_xml_tolerant")
            if (directoryCache.isNotEmpty() && directoryCache != "none") out.add("directory_cache_" + directoryCache.replace('-', '_'))
            if (pacerRetryBackoff) out.add("pacer_retry_backoff")
            return out
        }
    }

    private fun baseHostLower(baseUrl: String): String {
        return runCatching { URL(baseUrl.trimEnd('/')).host.lowercase(java.util.Locale.US) }.getOrDefault("")
    }

    private fun baseLooksLikeAlistDefaultDav(baseUrl: String): Boolean {
        val u = runCatching { URL(baseUrl.trimEnd('/')) }.getOrNull() ?: return false
        val path = u.path ?: return false
        val port = if (u.port > 0) u.port else if (u.protocol.equals("https", ignoreCase = true)) 443 else 80
        return port == 5244 && (path == "/dav" || path.startsWith("/dav/"))
    }

    private fun firstSemver(text: String): String {
        val m = Regex("(?i)(?:v(?:ersion)?\\s*)?([0-9]+\\.[0-9]+\\.[0-9]+)").find(text)
        return m?.groupValues?.getOrNull(1) ?: ""
    }

    private fun compareSemver(a: String, b: String): Int {
        fun part(v: String, index: Int): Int = v.split('.').getOrNull(index)?.takeWhile { it.isDigit() }?.toIntOrNull() ?: 0
        var i = 0
        while (i < 3) {
            val d = part(a, i).compareTo(part(b, i))
            if (d != 0) return d
            i++
        }
        return 0
    }

    private fun alistSecurityAdvisory(kind: String, serverHeader: String): AlistSecurityAdvisory {
        if (!isAlistFamily(kind)) return AlistSecurityAdvisory()
        val version = firstSemver(serverHeader)
        if (version.isEmpty()) {
            return AlistSecurityAdvisory(state = "version_unknown", action = "log_only")
        }
        return if (compareSemver(version, "3.57.0") < 0) {
            AlistSecurityAdvisory(state = "affected_lt_3.57.0", version = version, action = "warn_update")
        } else {
            AlistSecurityAdvisory(state = "not_affected_gte_3.57.0", version = version, action = "none")
        }
    }

    private fun detectWebDavQuirks(
        baseUrl: String,
        allow: String,
        dav: String,
        server: String,
        allowReliable: Boolean,
        steps: List<CompatProbeStep>,
    ): WebDavQuirks {
        val lowerServer = server.lowercase(java.util.Locale.US)
        val lowerDav = dav.lowercase(java.util.Locale.US)
        val lowerHost = baseHostLower(baseUrl)
        val profile = when {
            lowerHost.contains("123pan") || lowerHost.contains("123pan.cn") || lowerServer.contains("123pan") || lowerServer.contains("123") -> WebDavVendorProfile.PAN123
            lowerHost.contains("jianguoyun") || lowerHost.contains("nutstore") || lowerServer.contains("jianguoyun") || lowerServer.contains("jian guo") || lowerServer.contains("nutstore") -> WebDavVendorProfile.JIANGUOYUN
            lowerHost.contains("nextcloud") || lowerServer.contains("nextcloud") || lowerServer.contains("owncloud") || lowerDav.contains("nextcloud") || lowerDav.contains("sabredav") -> WebDavVendorProfile.NEXTCLOUD
            lowerServer.contains("rclone") || (!allowReliable && stepOk(steps, "putstdinchunkedrel") && stepOk(steps, "moverel")) -> WebDavVendorProfile.RCLONE
            else -> WebDavVendorProfile.GENERIC
        }
        val rcloneLike = profile == WebDavVendorProfile.RCLONE
        return WebDavQuirks(
            profile = profile,
            allowHeaderAdvisory = true,
            tolerateIncompleteAllow = rcloneLike || !allowReliable,
            confirmMkcolWithPropfind = true,
            mkcol409MeansParentMissing = true,
            moveCopy201204Ok = true,
            delete404Ok = true,
            relPathOnly = true,
            propfindXmlTolerant = true,
            directoryCache = "daemon-dir-state-cache",
            pacerRetryBackoff = true,
        )
    }

    private fun compatProbeRel(user: String, pass: String, baseUrl: String, requestedRel: String): Pair<Int, String> {
        val base = baseUrl.trimEnd('/')
        val probeRoot = requestedRel.trim('/').takeIf { it.isNotEmpty() && it != "." }
            ?: ".speedbackup_compat_probe_${System.currentTimeMillis()}_${android.os.Process.myPid()}"
        val fixedRel = "$probeRoot/payload.fixed.txt"
        val deleteRel = "$probeRoot/payload.delete.txt"
        val partRel = "$probeRoot/payload.txt.part"
        val finalRel = "$probeRoot/payload.txt"
        val copyRel = "$probeRoot/payload.copy.txt"
        val overwritePartRel = "$probeRoot/payload.overwrite.part"
        val payload = "speedbackup_webdav_compat_probe:${System.currentTimeMillis()}:pid=${android.os.Process.myPid()}\n"
            .toByteArray(StandardCharsets.UTF_8)
        val steps = ArrayList<CompatProbeStep>()
        var allow = ""
        var dav = ""
        var server = ""
        var allowReliable = true
        var bodyMatches = false
        var finalStatOk = false
        var remoteSizeOk = false
        var copyStatOk = false
        var cleanupOk = true
        var fixedPutOk = false
        var chunkedPutOk = false
        var deleteOk = false
        var mkcolOk = false
        var depth0Ok = false
        var depth1Ok = false
        var depthInfinityOk = false
        var recursiveWalkOk = false
        val walkRel = "$probeRoot/.walk"
        var quotaSupported = false
        var finalCode = 200

        fun addRequired(name: String, code: Int, ok: Boolean = code in 200..299, detail: String = ""): Boolean {
            steps.add(CompatProbeStep(name, code, ok, detail))
            if (!ok && finalCode in 200..299) finalCode = if (code in 200..299) 500 else code
            return ok
        }

        fun addOptional(name: String, code: Int, ok: Boolean = code in 200..299, detail: String = ""): Boolean {
            steps.add(CompatProbeStep(name, code, ok, detail))
            return ok
        }

        fun cleanup() {
            val d0 = deleteCleanup(user, pass, buildRelUrl(base, fixedRel), "compat-probe-fixed")
            val d1 = deleteCleanup(user, pass, buildRelUrl(base, deleteRel), "compat-probe-delete")
            val d2 = deleteCleanup(user, pass, buildRelUrl(base, partRel), "compat-probe-part")
            val d3 = deleteCleanup(user, pass, buildRelUrl(base, finalRel), "compat-probe-final")
            val d4 = deleteCleanup(user, pass, buildRelUrl(base, copyRel), "compat-probe-copy")
            val d5 = deleteCleanup(user, pass, buildRelUrl(base, overwritePartRel), "compat-probe-overwrite")
            val d6 = deleteCleanup(user, pass, buildRelUrl(base, walkRel), "compat-probe-walk")
            val d7 = deleteCleanup(user, pass, buildRelUrl(base, probeRoot), "compat-probe-root")
            cleanupOk = listOf(d0, d1, d2, d3, d4, d5, d6, d7).all { it in 200..299 || it == 404 }
            val cleanupCode = if (cleanupOk) 204 else listOf(d0, d1, d2, d3, d4, d5, d6, d7).firstOrNull { it !in 200..299 && it != 404 } ?: 0
            addRequired("cleanup", cleanupCode, cleanupOk)
        }

        try {
            val (optCode, optText) = optionsDav(user, pass, buildRelUrl(base, "."))
            if (optCode in 200..299) {
                val opt = parseCompatKeyValue(optText)
                allow = opt["allow"].orEmpty()
                dav = opt["dav"].orEmpty()
                server = opt["server"].orEmpty()
                val required = listOf("OPTIONS", "PROPFIND", "PUT", "GET", "DELETE")
                allowReliable = allow.isBlank() || required.all { allowHasMethod(allow, it) }
            }
            if (addRequired("optionsrel", optCode, optCode in 200..299, if (allowReliable) "" else "allow-incomplete")) {
                val mkdirCode = mkcolParentsRel(user, pass, base, probeRoot)
                mkcolOk = mkdirCode in 200..299
                if (addRequired("mkdirsrel", mkdirCode, mkcolOk)) {
                    val d0 = propfindRaw(user, pass, buildRelUrl(base, probeRoot), 0).first
                    depth0Ok = d0 in 200..299
                    addOptional("propfind.depth0", d0, depth0Ok)
                    val d1 = propfindRaw(user, pass, buildRelUrl(base, probeRoot), 1).first
                    depth1Ok = d1 in 200..299
                    addOptional("propfind.depth1", d1, depth1Ok)
                    val di = propfindRaw(user, pass, buildRelUrl(base, probeRoot), -1).first
                    depthInfinityOk = di in 200..299
                    addOptional("propfind.infinity", di, depthInfinityOk)
                    if (depth1Ok) {
                        val walkMk = mkcolParentsRel(user, pass, base, walkRel)
                        val walkD1 = if (walkMk in 200..299) propfindRaw(user, pass, buildRelUrl(base, walkRel), 1).first else walkMk
                        recursiveWalkOk = walkMk in 200..299 && walkD1 in 200..299
                        addOptional("propfind.depth1.walk", walkD1, recursiveWalkOk, "mkdir=$walkMk")
                    }
                    if (!depthInfinityOk && !recursiveWalkOk) addRequired("list.strategy", if (di !in 200..299) di else d1, false, "neither-depth-infinity-nor-verified-depth1-walk")
                    else addOptional("list.strategy", 200, true, if (depthInfinityOk) "infinity" else "depth1-walk")

                    val fixedPutUrl = buildRelUrl(base, fixedRel)
                    val fixedPutAttempt = putReplayableBytesAttempt(user, pass, fixedPutUrl, payload)
                    val fixedPutRecovered = fixedPutAttempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
                        user, pass, fixedPutUrl, fixedRel, payload.size.toLong(), fixedPutAttempt.code, fixedPutAttempt.failure,
                        clientBodyComplete = fixedPutAttempt.clientBodyComplete, context = "compat-probe-fixed-put", allowSizeOnly = true
                    )
                    val fixedPutCode = if (fixedPutRecovered) 200 else fixedPutAttempt.code
                    val fixedPutVerified = fixedPutRecovered || (fixedPutCode in 200..299 &&
                        verifiedPut2xxAfterStat(user, pass, base, fixedPutUrl, fixedRel, payload.size.toLong(), "compat-probe-fixed-put-2xx", requireKnownRemoteSize = false, allowSizeOnly = true))
                    fixedPutOk = fixedPutCode in 200..299 && fixedPutVerified
                    addOptional("putfixedrel", fixedPutCode, fixedPutOk, if (fixedPutRecovered) "ambiguous-put-verified" else if (fixedPutVerified) "2xx-stat-verified" else "2xx-stat-mismatch")

                    delete(user, pass, buildRelUrl(base, partRel))
                    delete(user, pass, buildRelUrl(base, finalRel))
                    delete(user, pass, buildRelUrl(base, copyRel))

                    val chunkedPutUrl = buildRelUrl(base, partRel)
                    val chunkedPutAttempt = putReplayableChunkedBytesAttempt(user, pass, chunkedPutUrl, payload)
                    val chunkedPutRecovered = chunkedPutAttempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
                        user, pass, chunkedPutUrl, partRel, payload.size.toLong(), chunkedPutAttempt.code, chunkedPutAttempt.failure,
                        clientBodyComplete = chunkedPutAttempt.clientBodyComplete, context = "compat-probe-chunked-put", allowSizeOnly = true
                    )
                    val chunkedPutCode = if (chunkedPutRecovered) 200 else chunkedPutAttempt.code
                    val chunkedPutVerified = chunkedPutRecovered || (chunkedPutCode in 200..299 &&
                        verifiedPut2xxAfterStat(user, pass, base, chunkedPutUrl, partRel, payload.size.toLong(), "compat-probe-chunked-put-2xx", requireKnownRemoteSize = false, allowSizeOnly = true))
                    chunkedPutOk = chunkedPutCode in 200..299 && chunkedPutVerified
                    addOptional("putstdinchunkedrel", chunkedPutCode, chunkedPutOk, if (chunkedPutRecovered) "ambiguous-put-verified" else if (chunkedPutVerified) "2xx-stat-verified" else "2xx-stat-mismatch")

                    // r612 feature contract is mode-neutral: a backend may be fixed-length-only and
                    // still fully support non-stream SpeedBackup. remote_stream=1 has its own hard
                    // managed chunked gate. Here require at least one upload mode, then measure the
                    // common GET/list/delete/integrity contract against whichever mode actually works.
                    val uploadOk = chunkedPutOk || fixedPutOk
                    addRequired(
                        "upload.strategy",
                        if (uploadOk) 200 else if (chunkedPutCode !in 200..299) chunkedPutCode else fixedPutCode,
                        uploadOk,
                        "chunked=$chunkedPutOk;fixed=$fixedPutOk"
                    )
                    if (uploadOk) {
                        fun putProbe(rel: String, bytes: ByteArray): Int {
                            val targetUrl = buildRelUrl(base, rel)
                            val attempt = if (chunkedPutOk) {
                                putReplayableChunkedBytesAttempt(user, pass, targetUrl, bytes)
                            } else {
                                putReplayableBytesAttempt(user, pass, targetUrl, bytes)
                            }
                            val recovered = attempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
                                user, pass, targetUrl, rel, bytes.size.toLong(), attempt.code, attempt.failure,
                                clientBodyComplete = attempt.clientBodyComplete, context = "compat-probe-working-put", allowSizeOnly = true
                            )
                            val normalized = if (recovered) 200 else attempt.code
                            return if (normalized in 200..299 && !recovered &&
                                !verifiedPut2xxAfterStat(user, pass, base, targetUrl, rel, bytes.size.toLong(), "compat-probe-working-put-2xx", requireKnownRemoteSize = false, allowSizeOnly = true)
                            ) PUT_SEMANTIC_FAILURE_HTTP_CODE else normalized
                        }

                        // Ensure the working object exists at partRel. The chunked probe already left
                        // it there; fixed-only backends first clean any partial/locked artifact left by
                        // the rejected chunked request, then create it with Content-Length.
                        if (!chunkedPutOk) {
                            deleteCleanup(user, pass, buildRelUrl(base, partRel), "compat-probe-chunked-fail-before-fixed")
                            val partFixedCode = putProbe(partRel, payload)
                            addOptional("putfixedrel.part", partFixedCode, partFixedCode in 200..299)
                        }

                        val deletePutCode = putProbe(deleteRel, payload)
                        if (deletePutCode in 200..299) {
                            val del = delete(user, pass, buildRelUrl(base, deleteRel))
                            deleteOk = del in 200..299
                            addRequired("deleterel.known", del, deleteOk)
                        } else {
                            addRequired("deleterel.known", deletePutCode, false, "prepare-delete-object-failed")
                        }

                        val moveCode = move(user, pass, buildRelUrl(base, partRel), buildRelUrl(base, finalRel), overwrite = true, expectedLength = payload.size.toLong())
                        val moveOk = moveCode in 200..299
                        addOptional("moverel", moveCode, moveOk)
                        val verifyRel = if (moveOk) finalRel else partRel
                        val (statCode, statEntry) = statDav(user, pass, buildRelUrl(base, verifyRel))
                        finalStatOk = statCode in 200..299 && statEntry != null && !statEntry.isDirectory
                        remoteSizeOk = finalStatOk && statEntry?.length == payload.size.toLong()
                        addOptional("statrel", statCode, finalStatOk, if (statEntry != null) "len=${statEntry.length};sizeOk=$remoteSizeOk" else "")

                        val got = ByteArrayOutputStream()
                        val getCode = getTo(user, pass, buildRelUrl(base, verifyRel), got)
                        bodyMatches = getCode in 200..299 && payload.contentEquals(got.toByteArray())
                        addRequired("getstdoutrel", getCode, bodyMatches, "expected=${payload.size};got=${got.size()}")

                        if (bodyMatches) {
                            val copyCode = copy(user, pass, buildRelUrl(base, verifyRel), buildRelUrl(base, copyRel), overwrite = true)
                            val copyOk = copyCode in 200..299
                            addOptional("copyrel", copyCode, copyOk)
                            if (copyOk) {
                                val (copyStatCode, copyEntry) = statDav(user, pass, buildRelUrl(base, copyRel))
                                copyStatOk = copyStatCode in 200..299 && copyEntry != null && !copyEntry.isDirectory &&
                                    (copyEntry.length < 0L || copyEntry.length == payload.size.toLong())
                                addOptional("statrel.copy", copyStatCode, copyStatOk, if (copyEntry != null) "len=${copyEntry.length}" else "")
                            }
                            if (moveOk) {
                                val overwritePayload = payload + "overwrite-pass\n".toByteArray(StandardCharsets.UTF_8)
                                val overwritePutCode = putProbe(overwritePartRel, overwritePayload)
                                if (addOptional(if (chunkedPutOk) "putstdinchunkedrel.overwrite" else "putfixedrel.overwrite", overwritePutCode)) {
                                    val overwriteMoveCode = move(user, pass, buildRelUrl(base, overwritePartRel), buildRelUrl(base, finalRel), overwrite = true, expectedLength = overwritePayload.size.toLong())
                                    val overwriteOk = overwriteMoveCode in 200..299
                                    addOptional("moverel.overwrite", overwriteMoveCode, overwriteOk)
                                    if (overwriteOk) {
                                        val got2 = ByteArrayOutputStream()
                                        val get2Code = getTo(user, pass, buildRelUrl(base, finalRel), got2)
                                        val overwriteBodyOk = get2Code in 200..299 && overwritePayload.contentEquals(got2.toByteArray())
                                        addOptional("getstdoutrel.overwrite", get2Code, overwriteBodyOk, "expected=${overwritePayload.size};got=${got2.size()}")
                                    }
                                }
                            }
                        }
                    }
                    val quota = runCatching { quotaDav(user, pass, buildRelUrl(base, ".")) }.getOrNull()
                    quotaSupported = quota?.first in 200..299 && quota?.second?.state == "supported"
                    addOptional("quotarel", quota?.first ?: 0, quotaSupported, quota?.second?.state ?: "unavailable")
                }
            }
        } catch (e: Throwable) {
            val code = HttpCore.extractCode(e)
            steps.add(CompatProbeStep("exception", code, false, "${e.javaClass.simpleName}:${e.message ?: ""}"))
            if (finalCode in 200..299) finalCode = code
        } finally {
            cleanup()
        }

        val chunkedOk = chunkedPutOk
        val moveOk = stepOk(steps, "moverel")
        val listUsable = depthInfinityOk || recursiveWalkOk
        val uploadUsable = chunkedPutOk || fixedPutOk
        val ok = finalCode in 200..299 && uploadUsable && bodyMatches && mkcolOk && deleteOk && listUsable && cleanupOk
        val quirks = detectWebDavQuirks(base, allow, dav, server, allowReliable, steps)
        cacheFeatureFacts(baseUrl, WebDavFeatureFacts(
            supportsChunkedPut = chunkedOk,
            supportsFixedPut = fixedPutOk,
            supportsGetStream = bodyMatches,
            supportsMove = moveOk,
            supportsCopy = stepOk(steps, "copyrel"),
            supportsStat = finalStatOk,
            supportsRemoteSize = remoteSizeOk,
            supportsMkcol = mkcolOk,
            supportsDelete = deleteOk,
            supportsDepth0 = depth0Ok,
            supportsDepth1 = depth1Ok,
            supportsDepthInfinity = depthInfinityOk,
            supportsRecursiveWalkFallback = recursiveWalkOk,
            supportsAtomicPublish = moveOk,
            supportsOverwriteMove = stepOk(steps, "moverel.overwrite") && stepOk(steps, "getstdoutrel.overwrite"),
            supportsPacerRetryBackoff = quirks.pacerRetryBackoff,
            supportsDirectoryCache = quirks.directoryCache.isNotEmpty() && quirks.directoryCache != "none",
            supportsQuota = quotaSupported,
            bodyCompareOk = bodyMatches,
            copyStatOk = copyStatOk,
            cleanupOk = cleanupOk,
            source = "compat-probe-r613"
        ))
        return finishCompatProbe(
            steps, finalCode, ok, allowReliable, allow, dav, server, quirks,
            bodyMatches, finalStatOk, remoteSizeOk, copyStatOk, cleanupOk, fixedPutOk,
            mkcolOk, deleteOk, depth0Ok, depth1Ok, depthInfinityOk, recursiveWalkOk, quotaSupported, probeRoot
        )
    }

    private fun finishCompatProbe(
        steps: List<CompatProbeStep>,
        code: Int,
        ok: Boolean,
        allowReliable: Boolean,
        allow: String,
        dav: String,
        server: String,
        quirks: WebDavQuirks,
        bodyMatches: Boolean,
        finalStatOk: Boolean,
        remoteSizeOk: Boolean,
        copyStatOk: Boolean,
        cleanupOk: Boolean,
        fixedPutOk: Boolean,
        mkcolOk: Boolean,
        deleteOk: Boolean,
        depth0Ok: Boolean,
        depth1Ok: Boolean,
        depthInfinityOk: Boolean,
        recursiveWalkOk: Boolean,
        quotaSupported: Boolean,
        probeRoot: String,
    ): Pair<Int, String> {
        val normalizedCode = if (ok) 200 else if (code in 200..299) 500 else code
        val json = buildString {
            append('{')
            append("\"recordType\":\"webdavCompatProbe\",")
            append("\"schemaVersion\":1,")
            append("\"result\":\"").append(if (ok) "OK" else "FAIL").append("\",")
            append("\"httpCode\":").append(normalizedCode).append(',')
            append("\"serverProfile\":\"").append(quirks.profile.wireName).append("\",")
            append("\"probeRoot\":\"").append(jsonEscape(probeRoot)).append("\",")
            append("\"allowHeaderReliable\":").append(allowReliable).append(',')
            append("\"allow\":\"").append(jsonEscape(allow)).append("\",")
            append("\"dav\":\"").append(jsonEscape(dav)).append("\",")
            append("\"server\":\"").append(jsonEscape(server)).append("\",")
            append("\"quirks\":{")
            append("\"allowHeaderAdvisory\":").append(quirks.allowHeaderAdvisory).append(',')
            append("\"tolerateIncompleteAllow\":").append(quirks.tolerateIncompleteAllow).append(',')
            append("\"confirmMkcolWithPropfind\":").append(quirks.confirmMkcolWithPropfind).append(',')
            append("\"mkcol409MeansParentMissing\":").append(quirks.mkcol409MeansParentMissing).append(',')
            append("\"moveCopy201204Ok\":").append(quirks.moveCopy201204Ok).append(',')
            append("\"delete404Ok\":").append(quirks.delete404Ok).append(',')
            append("\"relPathOnly\":").append(quirks.relPathOnly).append(',')
            append("\"propfindXmlTolerant\":").append(quirks.propfindXmlTolerant).append(',')
            append("\"directoryCache\":\"").append(jsonEscape(quirks.directoryCache)).append("\",")
            append("\"pacerRetryBackoff\":").append(quirks.pacerRetryBackoff)
            append("},")
            append("\"quirkNames\":[")
            quirks.names().forEachIndexed { index, name ->
                if (index > 0) append(',')
                append('\"').append(jsonEscape(name)).append('\"')
            }
            append("],")
            append("\"supportsChunkedPut\":").append(stepOk(steps, "putstdinchunkedrel")).append(',')
            append("\"supportsFixedPut\":").append(fixedPutOk).append(',')
            append("\"supportsGetStream\":").append(stepOk(steps, "getstdoutrel")).append(',')
            append("\"supportsMove\":").append(stepOk(steps, "moverel")).append(',')
            append("\"supportsCopy\":").append(stepOk(steps, "copyrel")).append(',')
            append("\"supportsStat\":").append(finalStatOk).append(',')
            append("\"supportsRemoteSize\":").append(remoteSizeOk).append(',')
            append("\"supportsMkcol\":").append(mkcolOk).append(',')
            append("\"supportsDelete\":").append(deleteOk).append(',')
            append("\"supportsDepth0\":").append(depth0Ok).append(',')
            append("\"supportsDepth1\":").append(depth1Ok).append(',')
            append("\"supportsDepthInfinity\":").append(depthInfinityOk).append(',')
            append("\"supportsRecursiveWalkFallback\":").append(recursiveWalkOk).append(',')
            append("\"supportsAtomicPublish\":").append(stepOk(steps, "moverel")).append(',')
            append("\"supportsOverwriteMove\":").append(stepOk(steps, "moverel.overwrite") && stepOk(steps, "getstdoutrel.overwrite")).append(',')
            append("\"supportsPacerRetryBackoff\":").append(quirks.pacerRetryBackoff).append(',')
            append("\"supportsDirectoryCache\":").append(quirks.directoryCache.isNotEmpty() && quirks.directoryCache != "none").append(',')
            append("\"supportsQuota\":").append(quotaSupported).append(',')
            append("\"propfindXmlTolerant\":").append(quirks.propfindXmlTolerant).append(',')
            append("\"bodyCompareOk\":").append(bodyMatches).append(',')
            append("\"copyStatOk\":").append(copyStatOk).append(',')
            append("\"cleanupOk\":").append(cleanupOk).append(',')
            append("\"steps\":[")
            steps.forEachIndexed { index, step ->
                if (index > 0) append(',')
                append('{')
                append("\"name\":\"").append(jsonEscape(step.name)).append("\",")
                append("\"code\":").append(step.code).append(',')
                append("\"ok\":").append(step.ok)
                if (step.detail.isNotEmpty()) append(",\"detail\":\"").append(jsonEscape(step.detail)).append('\"')
                append('}')
            }
            append(']')
            append('}').append('\n')
        }
        return normalizedCode to json
    }

    private fun stepOk(steps: List<CompatProbeStep>, name: String): Boolean = steps.any { it.name == name && it.ok }

    private fun compatProbeErrorJson(code: Int, result: String, errorClass: String, message: String): String = buildString {
        append('{')
        append("\"recordType\":\"webdavCompatProbe\",")
        append("\"schemaVersion\":1,")
        append("\"result\":\"").append(jsonEscape(result)).append("\",")
        append("\"httpCode\":").append(code).append(',')
        append("\"errorClass\":\"").append(jsonEscape(errorClass)).append("\",")
        append("\"message\":\"").append(jsonEscape(message)).append("\"")
        append('}').append('\n')
    }

    private fun parseCompatKeyValue(text: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for (line in text.lineSequence()) {
            val idx = line.indexOf('=')
            if (idx <= 0) continue
            out[line.substring(0, idx).trim().lowercase(java.util.Locale.US)] = line.substring(idx + 1).trim()
        }
        return out
    }

    private fun allowHasMethod(allow: String, method: String): Boolean {
        if (allow.isBlank()) return false
        return allow.split(',').any { it.trim().equals(method, ignoreCase = true) }
    }

    private fun jsonEscape(value: String): String {
        val sb = StringBuilder(value.length + 16)
        for (c in value) {
            when (c) {
                '\\' -> sb.append("\\\\")
                '"' -> sb.append("\\\"")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c.code < 0x20) sb.append("\\u").append(c.code.toString(16).padStart(4, '0')) else sb.append(c)
            }
        }
        return sb.toString()
    }

    private data class PutAttempt(
        val code: Int,
        val failure: Throwable? = null,
        val clientBodyComplete: Boolean = false
    )

    private class LocalFileCompareOutputStream(private val localFile: File) : OutputStream() {
        private val input = FileInputStream(localFile)
        private var closed = false
        private var mismatch = false
        private var remoteBytes = 0L
        private var finishedOk = false
        private val scratch = ByteArray(HttpCore.COPY_BUF_SIZE)

        override fun write(value: Int) {
            val expected = input.read()
            if (expected != (value and 0xff)) mismatch = true
            remoteBytes++
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            if (length <= 0) return
            var remaining = length
            var pos = offset
            while (remaining > 0) {
                val want = minOf(scratch.size, remaining)
                var gotTotal = 0
                while (gotTotal < want) {
                    val got = input.read(scratch, gotTotal, want - gotTotal)
                    if (got < 0) break
                    gotTotal += got
                }
                if (gotTotal != want) {
                    mismatch = true
                    remoteBytes += remaining.toLong()
                    return
                }
                var i = 0
                while (i < want) {
                    if (scratch[i] != buffer[pos + i]) mismatch = true
                    i++
                }
                pos += want
                remaining -= want
                remoteBytes += want.toLong()
            }
        }

        fun finishExpected(expectedBytes: Long): Boolean {
            if (!closed) {
                val eof = input.read() < 0
                finishedOk = !mismatch && eof && remoteBytes == expectedBytes
                close()
            }
            return finishedOk
        }

        override fun close() {
            if (closed) return
            closed = true
            input.close()
        }
    }

    private class PrefixCaptureOutputStream(private val limit: Int) : OutputStream() {
        private val prefix = ByteArrayOutputStream(limit.coerceAtMost(8192).coerceAtLeast(256))
        private var totalBytes = 0L

        override fun write(value: Int) {
            totalBytes++
            if (prefix.size() < limit) prefix.write(value)
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            if (length <= 0) return
            totalBytes += length.toLong()
            val remain = limit - prefix.size()
            if (remain > 0) prefix.write(buffer, offset, minOf(remain, length))
        }

        fun bytes(): ByteArray = prefix.toByteArray()
        fun total(): Long = totalBytes
        fun truncated(): Boolean = totalBytes > prefix.size().toLong()
    }

    private data class PutSemanticBodyCheck(
        val failed: Boolean,
        val reason: String = "ok",
        val detail: String = ""
    )

    private fun jsonNumberField(text: String, name: String): Long? {
        val pattern = "\"" + Regex.escape(name) + "\"\\s*:\\s*(-?\\d+)"
        return Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groupValues?.getOrNull(1)?.toLongOrNull()
    }

    private fun jsonStringField(text: String, name: String): String? {
        val pattern = "\"" + Regex.escape(name) + "\"\\s*:\\s*\"([^\"]{1,512})\""
        return Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groupValues?.getOrNull(1)?.trim()
    }

    private fun put2xxSemanticBodyCheck(status: Int, headers: Map<String, List<String>>, bodyPrefix: ByteArray, totalBytes: Long, truncated: Boolean): PutSemanticBodyCheck {
        if (status !in 200..299 || bodyPrefix.isEmpty()) return PutSemanticBodyCheck(false)
        val contentType = headers.firstHeaderCompat("content-type")?.lowercase(java.util.Locale.US).orEmpty()
        val text = runCatching { String(bodyPrefix, StandardCharsets.UTF_8) }.getOrDefault("")
        val trimmed = text.trimStart('\uFEFF', ' ', '\t', '\r', '\n')
        if (trimmed.isEmpty()) return PutSemanticBodyCheck(false)
        val jsonLike = contentType.contains("json") || trimmed.startsWith("{") || trimmed.startsWith("[")
        if (!jsonLike) return PutSemanticBodyCheck(false)
        val lower = trimmed.lowercase(java.util.Locale.US)

        for (key in listOf("errno", "errcode", "error_code", "err_no", "retcode")) {
            val n = jsonNumberField(trimmed, key)
            if (n != null && n != 0L) return PutSemanticBodyCheck(true, "json-$key", "$key=$n bytes=$totalBytes truncated=${if (truncated) 1 else 0}")
        }
        val code = jsonNumberField(trimmed, "code")
        if (code != null && code != 0L && code !in 200L..299L &&
            (lower.contains("errmsg") || lower.contains("error") || lower.contains("message") || lower.contains("fail"))) {
            return PutSemanticBodyCheck(true, "json-code", "code=$code bytes=$totalBytes truncated=${if (truncated) 1 else 0}")
        }
        if (Regex("\"success\"\\s*:\\s*false", RegexOption.IGNORE_CASE).containsMatchIn(trimmed)) {
            return PutSemanticBodyCheck(true, "json-success-false", "bytes=$totalBytes truncated=${if (truncated) 1 else 0}")
        }
        val statusText = jsonStringField(trimmed, "status")?.lowercase(java.util.Locale.US).orEmpty()
        if (statusText == "error" || statusText == "failed" || statusText == "fail") {
            return PutSemanticBodyCheck(true, "json-status-$statusText", "bytes=$totalBytes truncated=${if (truncated) 1 else 0}")
        }
        val errorText = jsonStringField(trimmed, "error")
        if (errorText != null) {
            val e = errorText.trim().lowercase(java.util.Locale.US)
            if (e.isNotEmpty() && e != "0" && e != "false" && e != "null" && e != "none" && e != "ok") {
                return PutSemanticBodyCheck(true, "json-error-string", "bytes=$totalBytes truncated=${if (truncated) 1 else 0}")
            }
        }
        return PutSemanticBodyCheck(false)
    }

    private fun consumePutResponseSemanticStatus(status: Int, headers: Map<String, List<String>>, input: InputStream): Pair<Int, String> {
        if (status in 200..299) {
            if (!HttpCore.hasKnownBodyFraming(headers)) {
                HttpCore.discardResponseBody(headers, input)
                return status to ""
            }
            val capture = PrefixCaptureOutputStream(PUT_RESPONSE_BODY_SNIFF_LIMIT)
            HttpCore.readResponseBody(headers, input, capture)
            val check = put2xxSemanticBodyCheck(status, headers, capture.bytes(), capture.total(), capture.truncated())
            if (check.failed) {
                infoLog("WEBDAV_PUT_2XX_BODY_SEMANTIC_ERROR http=$status synthetic=$PUT_SEMANTIC_FAILURE_HTTP_CODE reason=${check.reason} detail=${check.detail} mode=r613")
                return PUT_SEMANTIC_FAILURE_HTTP_CODE to check.reason
            }
            return status to ""
        }
        HttpCore.discardErrorResponseBody(headers, input)
        return status to ""
    }

    private fun verifiedPut2xxAfterStat(
        user: String,
        pass: String,
        baseUrl: String,
        targetUrl: String,
        targetRel: String,
        expectedLength: Long,
        context: String,
        requireKnownRemoteSize: Boolean,
        allowSizeOnly: Boolean,
        compareLocalFile: File? = null,
    ): Boolean {
        val facts = featureFactsCache[featureFactsKey(baseUrl)]
        if (requireKnownRemoteSize && facts?.supportsRemoteSize != true) {
            infoLog("WEBDAV_PUT_2XX_VERIFY_SKIP context=$context rel=$targetRel expectedBytes=$expectedLength reason=remote-size-not-proven mode=r613")
            return true
        }
        val (statCode, entry) = statDav(user, pass, targetUrl)
        val actualLength = entry?.length ?: -1L
        val sizeOk = statCode in 200..299 && entry != null && !entry.isDirectory && actualLength == expectedLength
        var getCode = 0
        var bodyOk = false
        if (sizeOk && compareLocalFile != null && !allowSizeOnly) {
            val bodyResult = remoteBodyMatchesLocalFile(user, pass, targetUrl, targetRel, compareLocalFile)
            getCode = bodyResult.first
            bodyOk = bodyResult.second
        }
        val verified = sizeOk && (allowSizeOnly || compareLocalFile == null || bodyOk)
        infoLog("WEBDAV_PUT_2XX_VERIFY context=$context rel=$targetRel statHttp=$statCode getHttp=$getCode expectedBytes=$expectedLength actualBytes=$actualLength verifyMode=${if (allowSizeOnly) "stat-size" else if (compareLocalFile != null) "stat-size-get-body" else "stat-size"} verified=${if (verified) 1 else 0} mode=r613")
        return verified
    }

    private fun remoteBodyMatchesLocalFile(user: String, pass: String, url: String, relPath: String, localFile: File): Pair<Int, Boolean> {
        var bodyMatches = false
        val code = runCatching {
            http.request("GET", url, user, pass, followRedirects = true, canReplayBody = true) { status, headers, input ->
                if (status in 200..299) {
                    val comparator = LocalFileCompareOutputStream(localFile)
                    try {
                        HttpCore.readResponseBody(headers, input, comparator)
                        bodyMatches = comparator.finishExpected(localFile.length())
                    } finally {
                        runCatching { comparator.close() }
                    }
                } else {
                    HttpCore.discardErrorResponseBody(headers, input)
                }
            }
        }.getOrElse { HttpCore.extractCode(it) }
        infoLog("WEBDAV_PUT_AMBIGUOUS_BODY_COMPARE rel=$relPath getHttp=$code expectedBytes=${localFile.length()} bodyMatch=${if (bodyMatches) 1 else 0} mode=r613")
        return code to (code in 200..299 && bodyMatches)
    }

    private fun isAmbiguousPutCode(code: Int): Boolean {
        // PUT-specific ambiguity is wider than replay retry policy: AList/PikPak-style bridges have
        // been observed returning 405 after the provider already materialized the object. Do not
        // retry the PUT body; verify the target with STAT/optional GET instead.
        return isTransientWebDavCode(code) || code == 405 || code == PUT_SEMANTIC_FAILURE_HTTP_CODE
    }

    private fun ambiguousPutVerifiedAfterStat(
        user: String,
        pass: String,
        targetUrl: String,
        targetRel: String,
        expectedLength: Long,
        code: Int,
        failure: Throwable?,
        clientBodyComplete: Boolean,
        context: String,
        allowSizeOnly: Boolean,
        compareLocalFile: File? = null,
    ): Boolean {
        if (!isAmbiguousPutCode(code)) return false
        val message = failure?.message.orEmpty()
        if (message.startsWith("HTTP_REDIRECT_AUTH_")) return false
        if (!clientBodyComplete || expectedLength < 0L) {
            infoLog("WEBDAV_PUT_AMBIGUOUS_VERIFY context=$context rel=$targetRel originalHttp=$code clientBodyComplete=${if (clientBodyComplete) 1 else 0} expectedBytes=$expectedLength recovered=0 reason=body-incomplete-or-unknown mode=r613")
            return false
        }
        val (statCode, entry) = statDav(user, pass, targetUrl)
        val actualLength = entry?.length ?: -1L
        val sizeOk = statCode in 200..299 && entry != null && !entry.isDirectory && actualLength == expectedLength
        var getCode = 0
        var bodyOk = false
        if (sizeOk && compareLocalFile != null) {
            val bodyResult = remoteBodyMatchesLocalFile(user, pass, targetUrl, targetRel, compareLocalFile)
            getCode = bodyResult.first
            bodyOk = bodyResult.second
        }
        val recovered = sizeOk && (allowSizeOnly || bodyOk)
        val verifyMode = if (allowSizeOnly) "stat-size" else if (compareLocalFile != null) "stat-size-get-body" else "stat-size-disabled"
        infoLog("WEBDAV_PUT_AMBIGUOUS_VERIFY context=$context rel=$targetRel originalHttp=$code statHttp=$statCode getHttp=$getCode expectedBytes=$expectedLength actualBytes=$actualLength clientBodyComplete=1 verifyMode=$verifyMode bodyCompare=${if (compareLocalFile != null) 1 else 0} bodyOk=${if (bodyOk) 1 else 0} recovered=${if (recovered) 1 else 0} mode=r613")
        return recovered
    }

    private fun replayableLocalFileUsesChunked(baseUrl: String): Boolean {
        val facts = featureFactsCache[featureFactsKey(baseUrl)]
        return facts?.supportsFixedPut == false && facts.supportsChunkedPut == true
    }

    private fun putReplayableLocalFileAttempt(user: String, pass: String, baseUrl: String, relPath: String, file: File): PutAttempt {
        val chunked = replayableLocalFileUsesChunked(baseUrl)
        val bodyDone = AtomicBoolean(false)
        infoLog("WEBDAV_REPLAYABLE_FILE_PUT rel=$relPath size=${file.length()} chunked=${if (chunked) 1 else 0} source=${featureFactsCache[featureFactsKey(baseUrl)]?.source ?: "unknown"} mode=r613")
        return runCatching {
            val code = FileInputStream(file).use {
                put(user, pass, buildRelUrl(baseUrl, relPath), it, if (chunked) null else file.length(), chunked = chunked, onBodyComplete = { bodyDone.set(true) })
            }
            PutAttempt(code, null, bodyDone.get())
        }.getOrElse { e ->
            PutAttempt(HttpCore.extractCode(e), e, bodyDone.get())
        }
    }

    private fun putReplayableLocalFile(
        user: String,
        pass: String,
        baseUrl: String,
        relPath: String,
        file: File,
        verifyContext: String = "putrel",
        allowSizeOnly: Boolean = false,
    ): Int {
        val attempt = putReplayableLocalFileAttempt(user, pass, baseUrl, relPath, file)
        val targetUrl = buildRelUrl(baseUrl, relPath)
        val recovered = attempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
            user, pass, targetUrl, relPath, file.length(), attempt.code, attempt.failure,
            clientBodyComplete = attempt.clientBodyComplete, context = verifyContext,
            allowSizeOnly = allowSizeOnly, compareLocalFile = if (allowSizeOnly) null else file
        )
        val normalized = if (recovered) 200 else attempt.code
        return if (normalized in 200..299 && !recovered && !verifiedPut2xxAfterStat(
                user, pass, baseUrl, targetUrl, relPath, file.length(), verifyContext,
                requireKnownRemoteSize = true, allowSizeOnly = allowSizeOnly, compareLocalFile = if (allowSizeOnly) null else file
            )
        ) PUT_SEMANTIC_FAILURE_HTTP_CODE else normalized
    }

    private fun putBatchRel(user: String, pass: String, baseUrl: String, baseRel: String, manifest: String): Pair<Int, String> {
        val base = baseRel.trim('/').takeIf { it.isNotEmpty() && it != "." } ?: ""
        val sb = StringBuilder()
        var total = 0
        var ok = 0
        var fail = 0
        for (line in manifest.lineSequence()) {
            if (line.isBlank()) continue
            total++
            val parts = line.split('\t', limit = 2)
            val rel = parts.getOrNull(0)?.trim()?.trimStart('/') ?: ""
            val local = parts.getOrNull(1)?.trim() ?: ""
            if (rel.isEmpty() || rel.contains("..") || local.isEmpty()) {
                fail++
                sb.append(rel).append('\t').append(0).append('\t').append(0).append('\t').append("BAD_ENTRY").append('\n')
                continue
            }
            val file = File(local)
            if (!file.isFile) {
                fail++
                sb.append(rel).append('\t').append(0).append('\t').append(0).append('\t').append("NO_FILE").append('\n')
                continue
            }
            val fullRel = if (base.isEmpty()) rel else "$base/$rel"
            val parentRel = fullRel.substringBeforeLast('/', missingDelimiterValue = "")
            if (parentRel.isNotEmpty()) {
                var cur = ""
                for (seg in parentRel.split('/')) {
                    if (seg.isEmpty()) continue
                    cur = if (cur.isEmpty()) seg else "$cur/$seg"
                    val mk = mkcolCached(user, pass, buildRelUrl(baseUrl, cur))
                    if (mk !in 200..299) {
                        fail++
                        sb.append(rel).append('\t').append(mk).append('\t').append(file.length()).append('\t').append("MKCOL_FAIL").append('\n')
                        cur = ""
                        break
                    }
                }
                if (cur.isEmpty() && parentRel.isNotEmpty()) continue
            }
            val code = putReplayableLocalFile(user, pass, baseUrl, fullRel, file, verifyContext = "putbatchrel")
            if (code in 200..299) ok++ else fail++
            sb.append(rel).append('\t').append(code).append('\t').append(file.length()).append('\t')
                .append(if (code in 200..299) "OK" else "PUT_FAIL").append('\n')
        }
        if (ok > 0) invalidateListCache()
        sb.append("SUMMARY\t").append(if (fail == 0) 200 else 500).append('\t').append(total).append('\t')
            .append("ok=").append(ok).append(" fail=").append(fail).append('\n')
        return (if (fail == 0) 200 else 500) to sb.toString()
    }

    private fun put(user: String, pass: String, url: String, input: InputStream, contentLength: Long?, chunked: Boolean, meter: WebDavStreamMeter? = null, responseHeadTimeoutMs: Int = HttpCore.LONG_TRANSFER_TIMEOUT_MS, onBodyComplete: (() -> Unit)? = null): Int {
        val headers = linkedMapOf("Content-Type" to "application/octet-stream")
        if (chunked || contentLength == null) headers["Transfer-Encoding"] = "chunked" else headers["Content-Length"] = contentLength.toString()
        var semanticFailure = false
        var semanticReason = ""
        val rawCode = http.request(
            "PUT", url, user, pass, headers,
            bodyWriter = { out ->
                if (chunked || contentLength == null) HttpCore.writeChunked(input, out) else input.copyTo(out)
            },
            responseHeadTimeoutMs = responseHeadTimeoutMs,
            onRequestBodyComplete = { meter?.bodyFinished(); onBodyComplete?.invoke() },
            onConnection = { conn -> meter?.attachSocket(conn.socket) },
            responseConsumer = { status, respHeaders, respInput ->
                val semantic = consumePutResponseSemanticStatus(status, respHeaders, respInput)
                if (semantic.first == PUT_SEMANTIC_FAILURE_HTTP_CODE) {
                    semanticFailure = true
                    semanticReason = semantic.second
                }
            }
        )
        return if (rawCode in 200..299 && semanticFailure) {
            infoLog("WEBDAV_PUT_2XX_BODY_RECLASSIFY http=$rawCode synthetic=$PUT_SEMANTIC_FAILURE_HTTP_CODE reason=$semanticReason action=stat-verify-before-success mode=r613")
            PUT_SEMANTIC_FAILURE_HTTP_CODE
        } else rawCode
    }

    /**
     * Replay-safe fixed payload PUT used only by capability probes.
     *
     * Unlike archive streaming, [bytes] can be written again after an encoded CJK path returns
     * HTTP 404. HttpCore may retry the same PUT once with a raw UTF-8 request target and cache the
     * successful path mode for the subsequent non-replayable streaming PUT on the same origin.
     */
    private fun putReplayableBytesAttempt(user: String, pass: String, url: String, bytes: ByteArray): PutAttempt {
        val headers = linkedMapOf(
            "Content-Type" to "application/octet-stream",
            "Content-Length" to bytes.size.toString()
        )
        val bodyDone = AtomicBoolean(false)
        var semanticCode = 0
        var semanticReason = ""
        return runCatching {
            val code = http.request(
                method = "PUT",
                url = url,
                user = user,
                pass = pass,
                headers = headers,
                canReplayBody = true,
                onRequestBodyComplete = { bodyDone.set(true) },
                bodyWriter = { out -> out.write(bytes) },
                responseConsumer = { status, respHeaders, respInput ->
                    val semantic = consumePutResponseSemanticStatus(status, respHeaders, respInput)
                    if (semantic.first == PUT_SEMANTIC_FAILURE_HTTP_CODE) {
                        semanticCode = semantic.first
                        semanticReason = semantic.second
                    }
                }
            )
            val finalCode = if (code in 200..299 && semanticCode == PUT_SEMANTIC_FAILURE_HTTP_CODE) {
                infoLog("WEBDAV_PUT_2XX_BODY_RECLASSIFY http=$code synthetic=$PUT_SEMANTIC_FAILURE_HTTP_CODE reason=$semanticReason action=probe-stat-verify-before-success mode=r613")
                PUT_SEMANTIC_FAILURE_HTTP_CODE
            } else code
            PutAttempt(finalCode, null, bodyDone.get())
        }.getOrElse { e ->
            PutAttempt(HttpCore.extractCode(e), e, bodyDone.get())
        }
    }

    private fun putReplayableBytes(user: String, pass: String, url: String, bytes: ByteArray): Int {
        return putReplayableBytesAttempt(user, pass, url, bytes).code
    }

    /**
     * Replay-safe chunked PUT used by the managed stream capability probe.
     *
     * The real archive stream is non-replayable, but this tiny in-memory body can be recreated,
     * allowing the probe to verify Transfer-Encoding: chunked without weakening production
     * stream retry semantics.
     */
    private fun putReplayableChunkedBytesAttempt(user: String, pass: String, url: String, bytes: ByteArray): PutAttempt {
        val headers = linkedMapOf(
            "Content-Type" to "application/octet-stream",
            "Transfer-Encoding" to "chunked"
        )
        val bodyDone = AtomicBoolean(false)
        var semanticCode = 0
        var semanticReason = ""
        return runCatching {
            val code = http.request(
                method = "PUT",
                url = url,
                user = user,
                pass = pass,
                headers = headers,
                canReplayBody = true,
                onRequestBodyComplete = { bodyDone.set(true) },
                bodyWriter = { out -> ByteArrayInputStream(bytes).use { input -> HttpCore.writeChunked(input, out) } },
                responseConsumer = { status, respHeaders, respInput ->
                    val semantic = consumePutResponseSemanticStatus(status, respHeaders, respInput)
                    if (semantic.first == PUT_SEMANTIC_FAILURE_HTTP_CODE) {
                        semanticCode = semantic.first
                        semanticReason = semantic.second
                    }
                }
            )
            val finalCode = if (code in 200..299 && semanticCode == PUT_SEMANTIC_FAILURE_HTTP_CODE) {
                infoLog("WEBDAV_PUT_2XX_BODY_RECLASSIFY http=$code synthetic=$PUT_SEMANTIC_FAILURE_HTTP_CODE reason=$semanticReason action=probe-stat-verify-before-success mode=r613")
                PUT_SEMANTIC_FAILURE_HTTP_CODE
            } else code
            PutAttempt(finalCode, null, bodyDone.get())
        }.getOrElse { e ->
            PutAttempt(HttpCore.extractCode(e), e, bodyDone.get())
        }
    }

    private fun putReplayableChunkedBytes(user: String, pass: String, url: String, bytes: ByteArray): Int {
        return putReplayableChunkedBytesAttempt(user, pass, url, bytes).code
    }

    // r603: server product and backing-provider presentation are deliberately separate.
    // WebDAV headers can identify the front-end product (AList/OpenList/rclone/etc.), but an
    // AList/OpenList WebDAV endpoint does not reliably expose its backing storage driver.
    // The provider registry below is therefore presentation-only when inferred from the mount
    // path. It MUST NOT select upload semantics or relax success verification.
    private val providerAliases = listOf(
        ProviderAlias("139yun", "中國移動雲盤", "CN", "consumer_cloud", listOf("中國移動雲盤", "中国移动云盘", "移動雲盤", "移动云盘", "139yun", "139雲", "139云", "mcloud")),
        ProviderAlias("189cloud", "天翼雲盤", "CN", "consumer_cloud", listOf("天翼雲盤", "天翼云盘", "189cloud", "cloud189", "189雲盤", "189云盘")),
        ProviderAlias("aliyundrive", "阿里雲盤", "CN", "consumer_cloud", listOf("阿里雲盤", "阿里云盘", "aliyundrive", "alipan", "aliyunpan")),
        ProviderAlias("123pan", "123雲盤", "CN", "consumer_cloud", listOf("123雲盤", "123云盘", "123pan")),
        ProviderAlias("115", "115", "CN", "consumer_cloud", listOf("115網盤", "115网盘", "115雲盤", "115云盘", "115")),
        ProviderAlias("baidu_photo", "百度/一刻相冊", "CN", "photo_cloud", listOf("一刻相冊", "一刻相册", "百度相冊", "百度相册", "baiduphoto")),
        ProviderAlias("baidu_netdisk", "百度網盤", "CN", "consumer_cloud", listOf("百度網盤", "百度网盘", "baidunetdisk", "baidupan")),
        ProviderAlias("quark", "夸克網盤", "CN", "consumer_cloud", listOf("夸克網盤", "夸克网盘", "quark")),
        ProviderAlias("uc", "UC 網盤", "CN", "consumer_cloud", listOf("uc網盤", "uc网盘", "ucdrive", "uc")),
        ProviderAlias("thunder", "迅雷雲盤", "CN", "consumer_cloud", listOf("迅雷雲盤", "迅雷云盘", "迅雷", "xunlei", "thunder")),
        ProviderAlias("weiyun", "騰訊微雲", "CN", "consumer_cloud", listOf("騰訊微雲", "腾讯微云", "微雲", "微云", "weiyun")),
        ProviderAlias("ilanzou", "藍奏優享", "CN", "consumer_cloud", listOf("藍奏優享", "蓝奏优享", "ilanzou")),
        ProviderAlias("lanzou", "藍奏雲", "CN", "consumer_cloud", listOf("藍奏雲", "蓝奏云", "lanzou")),
        ProviderAlias("feijipan", "飛機盤", "CN", "consumer_cloud", listOf("飛機盤", "飞机盘", "feijipan")),
        ProviderAlias("teambition", "Teambition", "CN_GLOBAL", "collaboration_cloud", listOf("teambition")),
        ProviderAlias("mediatrack", "Mediatrack", "CN", "media_cloud", listOf("mediatrack")),
        ProviderAlias("dogecloud", "多吉雲", "CN", "object_storage", listOf("多吉雲", "多吉云", "dogecloud")),
        ProviderAlias("chaoxing", "超星", "CN", "consumer_cloud", listOf("超星", "chaoxing")),
        ProviderAlias("cnb", "CNB", "CN", "developer_cloud", listOf("cnb")),
        ProviderAlias("doubao", "豆包", "CN", "consumer_cloud", listOf("豆包", "doubao")),
        ProviderAlias("dingtalk_docs", "釘釘文件", "CN", "collaboration_cloud", listOf("釘釘文件", "钉钉文件", "釘釘文檔", "钉钉文档", "dingtalkdocs", "alidocs")),
        ProviderAlias("onedrive", "OneDrive / SharePoint", "GLOBAL", "consumer_cloud", listOf("onedrive", "sharepoint", "onedrivecn", "sharepointcn")),
        ProviderAlias("google_photos", "Google Photos", "GLOBAL", "photo_cloud", listOf("googlephotos", "googlephoto")),
        ProviderAlias("google_drive", "Google Drive", "GLOBAL", "consumer_cloud", listOf("googledrive", "gdrive")),
        ProviderAlias("dropbox", "Dropbox", "GLOBAL", "consumer_cloud", listOf("dropbox")),
        ProviderAlias("mega", "MEGA", "GLOBAL", "consumer_cloud", listOf("mega", "meganz")),
        ProviderAlias("pikpak", "PikPak", "GLOBAL", "consumer_cloud", listOf("pikpak")),
        ProviderAlias("proton_drive", "Proton Drive", "GLOBAL", "consumer_cloud", listOf("protondrive")),
        ProviderAlias("yandex_disk", "Yandex Disk", "GLOBAL", "consumer_cloud", listOf("yandexdisk", "yandex")),
        ProviderAlias("terabox", "TeraBox", "GLOBAL", "consumer_cloud", listOf("terabox")),
        ProviderAlias("mediafire", "MediaFire", "GLOBAL", "consumer_cloud", listOf("mediafire")),
        ProviderAlias("degoo", "Degoo", "GLOBAL", "consumer_cloud", listOf("degoo")),
        ProviderAlias("febbox", "FebBox", "GLOBAL", "consumer_cloud", listOf("febbox")),
        ProviderAlias("teldrive", "Teldrive", "GLOBAL", "consumer_cloud", listOf("teldrive")),
        ProviderAlias("pcloud", "pCloud", "GLOBAL", "consumer_cloud", listOf("pcloud")),
        ProviderAlias("koofr", "Koofr", "GLOBAL", "consumer_cloud", listOf("koofr")),
        ProviderAlias("infini_cloud", "InfiniCLOUD / TeraCLOUD", "GLOBAL", "consumer_cloud", listOf("infinicloud", "teracloud")),
        ProviderAlias("seafile", "Seafile", "GLOBAL", "self_hosted_cloud", listOf("seafile")),
        ProviderAlias("cloudreve", "Cloudreve", "GLOBAL", "self_hosted_cloud", listOf("cloudreve")),
        ProviderAlias("azure_blob", "Azure Blob Storage", "GLOBAL", "object_storage", listOf("azureblob", "azureblobstorage")),
        ProviderAlias("s3", "S3 相容儲存", "GLOBAL", "object_storage", listOf("amazons3", "awss3", "s3", "minio", "cloudflarer2", "r2", "backblazeb2", "b2", "wasabi", "tencentcos", "cos", "aliyunoss", "oss")),
        ProviderAlias("upyun", "又拍雲", "CN", "object_storage", listOf("又拍雲", "又拍云", "upyun"))
    )

    private fun normalizeProviderToken(raw: String): String {
        val sb = StringBuilder(raw.length)
        raw.lowercase(java.util.Locale.US).forEach { ch ->
            if (ch.isLetterOrDigit()) sb.append(ch)
        }
        return sb.toString()
    }

    private fun decodedUrlPathSegments(baseUrl: String): List<String> {
        val rawPath = runCatching { URL(baseUrl.trimEnd('/')).path ?: "" }.getOrDefault("")
        val decoded = runCatching {
            URLDecoder.decode(rawPath.replace("+", "%2B"), StandardCharsets.UTF_8.name())
        }.getOrDefault(rawPath)
        return decoded.split('/').map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun directProviderHintForKind(kind: String): ProviderHint? = when (kind) {
        "123pan" -> ProviderHint("123pan", "123雲盤", "CN", "consumer_cloud", "server_or_host", "verified")
        "jianguoyun" -> ProviderHint("jianguoyun", "堅果雲", "CN", "native_webdav_cloud", "server_or_host", "verified")
        "yandex" -> ProviderHint("yandex_disk", "Yandex Disk", "GLOBAL", "consumer_cloud", "server_or_host", "verified")
        "pcloud" -> ProviderHint("pcloud", "pCloud", "GLOBAL", "consumer_cloud", "server_or_host", "verified")
        "koofr" -> ProviderHint("koofr", "Koofr", "GLOBAL", "consumer_cloud", "server_or_host", "verified")
        "infini_cloud" -> ProviderHint("infini_cloud", "InfiniCLOUD / TeraCLOUD", "GLOBAL", "consumer_cloud", "server_or_host", "verified")
        "cloudreve" -> ProviderHint("cloudreve", "Cloudreve", "GLOBAL", "self_hosted_cloud", "server_or_host", "verified")
        "zspace" -> ProviderHint("zspace_nas", "极空间 NAS", "CN", "nas", "server_or_host", "verified")
        "truenas" -> ProviderHint("truenas", "TrueNAS", "GLOBAL", "nas", "server_or_host", "verified")
        "asustor" -> ProviderHint("asustor", "ASUSTOR NAS", "GLOBAL", "nas", "server_or_host", "verified")
        "terramaster" -> ProviderHint("terramaster", "TerraMaster NAS", "GLOBAL", "nas", "server_or_host", "verified")
        "openmediavault" -> ProviderHint("openmediavault", "OpenMediaVault", "GLOBAL", "nas", "server_or_host", "verified")
        "unraid" -> ProviderHint("unraid", "Unraid", "GLOBAL", "nas", "server_or_host", "verified")
        "synology" -> ProviderHint("synology", "Synology DSM", "GLOBAL", "nas", "server_or_host", "verified")
        "qnap" -> ProviderHint("qnap", "QNAP QTS/QuTS", "GLOBAL", "nas", "server_or_host", "verified")
        "ugreen" -> ProviderHint("ugreen", "UGREEN UGOS Pro", "CN_GLOBAL", "nas", "server_or_host", "verified")
        "fnos" -> ProviderHint("fnos", "飛牛 fnOS", "CN", "nas", "server_or_host", "verified")
        "generic_nas_dav5005" -> ProviderHint("generic_nas_dav5005", "NAS WebDAV（5005/Dav）", "LOCAL", "nas", "port_path", "hint")
        else -> null
    }

    private fun providerHintFromBaseUrl(baseUrl: String, kind: String): ProviderHint {
        directProviderHintForKind(kind)?.let { return it }
        val segments = decodedUrlPathSegments(baseUrl)
        for (segment in segments) {
            val normalized = normalizeProviderToken(segment)
            if (normalized.isEmpty()) continue
            for (provider in providerAliases) {
                for (aliasRaw in provider.aliases) {
                    val alias = normalizeProviderToken(aliasRaw)
                    if (alias.isEmpty()) continue
                    val matched = normalized == alias || (alias.length >= 4 && normalized.contains(alias))
                    if (matched) {
                        return ProviderHint(
                            provider.id,
                            provider.displayName,
                            provider.region,
                            provider.providerClass,
                            "mount_path",
                            "hint"
                        )
                    }
                }
            }
        }
        return ProviderHint()
    }

    private fun serverFamilyForKind(kind: String): String = when (kind) {
        "alist", "openlist", "alist_compatible" -> "alist_openlist"
        "rclone" -> "rclone"
        "123pan" -> "123pan"
        "jianguoyun" -> "jianguoyun"
        "nextcloud_compatible" -> "nextcloud_owncloud"
        "sftpgo" -> "sftpgo_webdav"
        "zspace" -> "zspace_nas"
        "truenas" -> "truenas"
        "asustor" -> "asustor_adm"
        "terramaster" -> "terramaster_tos"
        "openmediavault" -> "openmediavault"
        "unraid" -> "unraid"
        "synology" -> "synology_dsm"
        "qnap" -> "qnap_qts_quts"
        "ugreen" -> "ugreen_ugos"
        "fnos" -> "fnos"
        "yandex" -> "yandex_webdav"
        "pcloud" -> "pcloud_webdav"
        "koofr" -> "koofr_webdav"
        "infini_cloud" -> "infini_cloud_webdav"
        "cloudreve" -> "cloudreve_webdav"
        "generic_nas_dav5005" -> "generic_nas_webdav"
        else -> "generic_webdav"
    }

    private fun serverDisplayForKind(kind: String): String = when (kind) {
        "openlist" -> "OpenList"
        "alist" -> "AList"
        "alist_compatible" -> "AList/OpenList 相容端"
        "rclone" -> "rclone WebDAV"
        "123pan" -> "123雲盤 WebDAV"
        "jianguoyun" -> "堅果雲 WebDAV"
        "nextcloud_compatible" -> "Nextcloud/ownCloud 相容端"
        "sftpgo" -> "SFTPGo WebDAV"
        "zspace" -> "极空间 NAS WebDAV"
        "truenas" -> "TrueNAS WebDAV"
        "asustor" -> "ASUSTOR ADM WebDAV"
        "terramaster" -> "TerraMaster TOS WebDAV"
        "openmediavault" -> "OpenMediaVault WebDAV"
        "unraid" -> "Unraid WebDAV"
        "synology" -> "Synology DSM WebDAV"
        "qnap" -> "QNAP QTS/QuTS WebDAV"
        "ugreen" -> "UGREEN UGOS Pro WebDAV"
        "fnos" -> "飛牛 fnOS WebDAV"
        "yandex" -> "Yandex Disk WebDAV"
        "pcloud" -> "pCloud WebDAV"
        "koofr" -> "Koofr WebDAV"
        "infini_cloud" -> "InfiniCLOUD/TeraCLOUD WebDAV"
        "cloudreve" -> "Cloudreve WebDAV"
        "generic_nas_dav5005" -> "NAS WebDAV（5005/Dav）"
        else -> "一般 WebDAV／未知伺服端"
    }

    private fun behaviorProfileForKind(kind: String): String = when {
        isAlistFamily(kind) -> "sync_put_proxy_http_2xx_required"
        kind == "rclone" || kind == "123pan" -> "direct_put_managed"
        else -> "capability_driven_webdav"
    }

    private fun baseLooksLikeZspaceNas(baseUrl: String, lowerDav: String): Boolean {
        val u = runCatching { URL(baseUrl.trimEnd('/')) }.getOrNull() ?: return false
        val segments = decodedUrlPathSegments(baseUrl)
        val first = segments.firstOrNull()?.lowercase(java.util.Locale.US) ?: return false
        // 极空间/ZSpace exposes WebDAV roots that commonly start with physical-volume
        // identifiers such as /nvme11-15620522265/...; combine that with SabreDAV so
        // a generic local folder named "nvme..." on unrelated WebDAV servers is not
        // promoted solely by path text.  This is presentation-only identity: transport
        // capability and atomic/list strategy still come only from runtime probes.
        val volumeLike = first.matches(Regex("^(nvme|sata|ssd|hdd|usb|emmc)[0-9a-z_-]*-[0-9]{6,}$"))
        val defaultZspaceDavPort = u.port == 5005 || u.port == 5006
        return volumeLike && (lowerDav.contains("sabredav") || defaultZspaceDavPort)
    }

    private fun baseLooksLikeGenericNasDav5005(baseUrl: String, lowerDav: String): Boolean {
        val u = runCatching { URL(baseUrl.trimEnd('/')) }.getOrNull() ?: return false
        val host = u.host.lowercase(java.util.Locale.US)
        val path = (u.path ?: "").lowercase(java.util.Locale.US)
        val port = if (u.port > 0) u.port else if (u.protocol.equals("https", ignoreCase = true)) 443 else 80
        val privateHost = host == "localhost" || host.startsWith("192.168.") || host.startsWith("10.") ||
            Regex("^172\\.(1[6-9]|2[0-9]|3[0-1])\\.").containsMatchIn(host) || host.endsWith(".local")
        val davPath = path == "/dav" || path.startsWith("/dav/") || path.contains("/webdav")
        return privateHost && (port == 5005 || port == 5006) && davPath && lowerDav.contains("1")
    }

    private fun hostLooksLikeOpenMediaVault(host: String): Boolean {
        return host == "omv" || host.startsWith("omv.") || host.startsWith("omv-") || host.contains("openmediavault")
    }

    private fun baseHasPathToken(baseUrl: String, vararg tokens: String): Boolean {
        val segments = decodedUrlPathSegments(baseUrl).map { normalizeProviderToken(it) }
        return segments.any { seg -> tokens.any { token -> seg == token || (token.length >= 5 && seg.contains(token)) } }
    }

    private fun classifyServerKind(baseUrl: String, code: Int, optionsBody: String): String {
        val host = baseHostLower(baseUrl)
        val path = runCatching { URL(baseUrl.trimEnd('/')).path.lowercase(java.util.Locale.US) }.getOrDefault("")
        val values = parseKeyValueLines(optionsBody)
        val lowerServer = values["server"].orEmpty().lowercase(java.util.Locale.US)
        val lowerDav = values["dav"].orEmpty().lowercase(java.util.Locale.US)
        return when {
            host.contains("123pan") || host.contains("123pan.cn") || (code in 200..299 && lowerServer.contains("123pan")) -> "123pan"
            host.contains("jianguoyun") || host.contains("nutstore") || (code in 200..299 && (lowerServer.contains("jianguoyun") || lowerServer.contains("nutstore"))) -> "jianguoyun"
            host.contains("webdav.yandex") || host == "webdav.yandex.com" || host == "webdav.yandex.ru" -> "yandex"
            host.contains("pcloud.com") && host.contains("webdav") -> "pcloud"
            host.contains("koofr") -> "koofr"
            host.contains("infini-cloud") || host.contains("teracloud") -> "infini_cloud"
            host.contains("cloudreve") || (code in 200..299 && lowerServer.contains("cloudreve")) -> "cloudreve"
            code in 200..299 && lowerServer.contains("openlist") -> "openlist"
            code in 200..299 && lowerServer.contains("alist") -> "alist"
            code in 200..299 && lowerServer.contains("rclone") -> "rclone"
            code in 200..299 && lowerServer.contains("sftpgo") -> "sftpgo"
            code in 200..299 && (lowerServer.contains("zspace") || lowerServer.contains("z-space") || lowerServer.contains("极空间") || lowerServer.contains("極空間")) -> "zspace"
            code in 200..299 && baseLooksLikeZspaceNas(baseUrl, lowerDav) -> "zspace"
            host.contains("truenas") || host.contains("freenas") || host.contains("ixsystems") || baseHasPathToken(baseUrl, "truenas", "freenas", "ixsystems") || (code in 200..299 && (lowerServer.contains("truenas") || lowerServer.contains("freenas") || lowerServer.contains("ixsystems"))) -> "truenas"
            host.contains("asustor") || host.contains("myasustor") || baseHasPathToken(baseUrl, "asustor") || (code in 200..299 && lowerServer.contains("asustor")) -> "asustor"
            host.contains("terramaster") || host.contains("tnas") || baseHasPathToken(baseUrl, "terramaster", "tnas") || (code in 200..299 && (lowerServer.contains("terramaster") || lowerServer.contains("tnas"))) -> "terramaster"
            hostLooksLikeOpenMediaVault(host) || baseHasPathToken(baseUrl, "openmediavault") || (code in 200..299 && lowerServer.contains("openmediavault")) -> "openmediavault"
            host.contains("unraid") || baseHasPathToken(baseUrl, "unraid") || (code in 200..299 && lowerServer.contains("unraid")) -> "unraid"
            code in 200..299 && (lowerServer.contains("nextcloud") || lowerServer.contains("owncloud") || lowerDav.contains("nextcloud")) -> "nextcloud_compatible"
            path.contains("/remote.php/dav") || path.contains("/remote.php/webdav") || lowerDav.contains("sabredav") -> "nextcloud_compatible"
            host.contains("synology") || (code in 200..299 && lowerServer.contains("synology")) -> "synology"
            host.contains("myqnapcloud") || host.contains("qnap") || (code in 200..299 && (lowerServer.contains("qnap") || lowerServer.contains("qts") || lowerServer.contains("quts"))) -> "qnap"
            host.contains("ugnas") || host.contains("ugreen") || (code in 200..299 && (lowerServer.contains("ugreen") || lowerServer.contains("ugos"))) -> "ugreen"
            host.contains("fnnas") || host.contains("fnos") || (code in 200..299 && (lowerServer.contains("fnos") || lowerServer.contains("fn nas") || lowerServer.contains("feiniu"))) -> "fnos"
            code in 200..299 && baseLooksLikeGenericNasDav5005(baseUrl, lowerDav) -> "generic_nas_dav5005"
            baseLooksLikeAlistDefaultDav(baseUrl) -> "alist_compatible"
            else -> "generic"
        }
    }

    private fun cacheServerKind(baseUrl: String, code: Int, kind: String) {
        if (code in 200..299 || kind == "alist_compatible") serverKindCache[serverKindCacheKey(baseUrl)] = kind
    }

    private fun serverKindCacheKey(baseUrl: String): String {
        val u = runCatching { URL(baseUrl.trimEnd('/')) }.getOrNull() ?: return baseUrl.trimEnd('/')
        val defaultPort = (u.protocol.equals("http", ignoreCase = true) && (u.port == -1 || u.port == 80)) ||
            (u.protocol.equals("https", ignoreCase = true) && (u.port == -1 || u.port == 443))
        val portPart = if (defaultPort) "" else ":${u.port}"
        return "${u.protocol.lowercase(java.util.Locale.US)}://${u.host.lowercase(java.util.Locale.US)}$portPart"
    }

    private fun featureFactsKey(baseUrl: String): String = baseUrl.trimEnd('/')

    private fun cacheFeatureFacts(baseUrl: String, facts: WebDavFeatureFacts) {
        val key = featureFactsKey(baseUrl)
        val merged = featureFactsCache.compute(key) { _, old ->
            WebDavFeatureFacts(
                supportsChunkedPut = facts.supportsChunkedPut ?: old?.supportsChunkedPut,
                supportsFixedPut = facts.supportsFixedPut ?: old?.supportsFixedPut,
                supportsGetStream = facts.supportsGetStream ?: old?.supportsGetStream,
                supportsMove = facts.supportsMove ?: old?.supportsMove,
                supportsCopy = facts.supportsCopy ?: old?.supportsCopy,
                supportsStat = facts.supportsStat ?: old?.supportsStat,
                supportsRemoteSize = facts.supportsRemoteSize ?: old?.supportsRemoteSize,
                supportsMkcol = facts.supportsMkcol ?: old?.supportsMkcol,
                supportsDelete = facts.supportsDelete ?: old?.supportsDelete,
                supportsDepth0 = facts.supportsDepth0 ?: old?.supportsDepth0,
                supportsDepth1 = facts.supportsDepth1 ?: old?.supportsDepth1,
                supportsDepthInfinity = facts.supportsDepthInfinity ?: old?.supportsDepthInfinity,
                supportsRecursiveWalkFallback = facts.supportsRecursiveWalkFallback ?: old?.supportsRecursiveWalkFallback,
                supportsAtomicPublish = facts.supportsAtomicPublish ?: old?.supportsAtomicPublish,
                supportsOverwriteMove = facts.supportsOverwriteMove ?: old?.supportsOverwriteMove,
                supportsPacerRetryBackoff = facts.supportsPacerRetryBackoff ?: old?.supportsPacerRetryBackoff,
                supportsDirectoryCache = facts.supportsDirectoryCache ?: old?.supportsDirectoryCache,
                supportsQuota = facts.supportsQuota ?: old?.supportsQuota,
                bodyCompareOk = facts.bodyCompareOk ?: old?.bodyCompareOk,
                copyStatOk = facts.copyStatOk ?: old?.copyStatOk,
                cleanupOk = facts.cleanupOk ?: old?.cleanupOk,
                source = facts.source,
                verifiedAtMs = facts.verifiedAtMs,
            )
        } ?: facts
        infoLog(
            "WEBDAV_FEATURE_FACTS source=${merged.source} tier=${supportTier("generic", merged)} " +
                "streamPut=${merged.supportsChunkedPut} fixedPut=${merged.supportsFixedPut} getStream=${merged.supportsGetStream} " +
                "list0=${merged.supportsDepth0} list1=${merged.supportsDepth1} listInf=${merged.supportsDepthInfinity} walk=${merged.supportsRecursiveWalkFallback} " +
                "mkcol=${merged.supportsMkcol} delete=${merged.supportsDelete} atomic=${merged.supportsAtomicPublish} move=${merged.supportsMove} " +
                "copy=${merged.supportsCopy} stat=${merged.supportsStat} remoteSize=${merged.supportsRemoteSize} overwriteMove=${merged.supportsOverwriteMove} " +
                "quota=${merged.supportsQuota} body=${merged.bodyCompareOk} copyStat=${merged.copyStatOk} cleanup=${merged.cleanupOk} mode=r613"
        )
    }

    private fun coreListUsable(facts: WebDavFeatureFacts): Boolean =
        facts.supportsDepthInfinity == true || (facts.supportsDepth1 == true && facts.supportsRecursiveWalkFallback == true)

    private fun coreUploadUsable(facts: WebDavFeatureFacts): Boolean =
        facts.supportsChunkedPut == true || facts.supportsFixedPut == true

    private fun supportTier(kind: String, facts: WebDavFeatureFacts?): String = when {
        facts == null -> "GENERIC"
        (facts.supportsChunkedPut == false && facts.supportsFixedPut == false) || facts.supportsGetStream == false ||
            facts.supportsMkcol == false || facts.supportsDelete == false || facts.cleanupOk == false -> "EXPERIMENTAL"
        coreUploadUsable(facts) && facts.supportsGetStream == true &&
            facts.supportsMkcol == true && facts.supportsDelete == true && coreListUsable(facts) &&
            facts.supportsStat == true && facts.supportsRemoteSize == true &&
            facts.bodyCompareOk == true && facts.cleanupOk == true -> "VERIFIED"
        coreUploadUsable(facts) && facts.supportsGetStream == true &&
            facts.supportsMkcol == true && facts.supportsDelete == true && coreListUsable(facts) -> "COMPATIBLE"
        else -> "EXPERIMENTAL"
    }

    private fun featureBool(v: Boolean?): String = when (v) { true -> "1"; false -> "0"; null -> "?" }

    private fun featureSummary(facts: WebDavFeatureFacts?): String {
        if (facts == null) return "streamPut=?;fixedPut=?;getStream=?;list=?;move=?;copy=?;stat=?;size=?;atomic=?;quota=?"
        val list = when {
            facts.supportsDepthInfinity == true -> "infinity"
            facts.supportsDepth1 == true && facts.supportsRecursiveWalkFallback == true -> "depth1-walk"
            facts.supportsDepth0 == true || facts.supportsDepth1 == true -> "partial"
            facts.supportsDepthInfinity == false && facts.supportsDepth1 == false -> "0"
            else -> "?"
        }
        return "streamPut=${featureBool(facts.supportsChunkedPut)};fixedPut=${featureBool(facts.supportsFixedPut)};" +
            "getStream=${featureBool(facts.supportsGetStream)};list=$list;move=${featureBool(facts.supportsMove)};" +
            "copy=${featureBool(facts.supportsCopy)};stat=${featureBool(facts.supportsStat)};size=${featureBool(facts.supportsRemoteSize)};" +
            "atomic=${featureBool(facts.supportsAtomicPublish)};overwriteMove=${featureBool(facts.supportsOverwriteMove)};" +
            "mkcol=${featureBool(facts.supportsMkcol)};delete=${featureBool(facts.supportsDelete)};quota=${featureBool(facts.supportsQuota)};" +
            "pacer=${featureBool(facts.supportsPacerRetryBackoff)};dirCache=${featureBool(facts.supportsDirectoryCache)};" +
            "body=${featureBool(facts.bodyCompareOk)};copyStat=${featureBool(facts.copyStatOk)};cleanup=${featureBool(facts.cleanupOk)}"
    }


    private fun putStrategyFor(profile: WebDavBackendProfile, facts: WebDavFeatureFacts?): String = when {
        facts?.supportsChunkedPut == true && facts.supportsFixedPut == true -> "chunked+fixed"
        facts?.supportsChunkedPut == true -> "chunked"
        facts?.supportsFixedPut == true -> "fixed"
        facts?.supportsChunkedPut == false && facts.supportsFixedPut == false -> "none"
        profile.newPayloadDirect -> "direct-new-payload"
        profile.directAll -> "direct"
        else -> "auto"
    }

    private fun listStrategyFor(facts: WebDavFeatureFacts?): String = when {
        facts?.supportsDepthInfinity == true -> "depth-infinity"
        facts?.supportsDepth1 == true && facts.supportsRecursiveWalkFallback == true -> "depth1-walk"
        facts?.supportsDepth1 == true -> "depth1-partial"
        facts?.supportsDepth0 == true -> "depth0-stat-only"
        facts?.supportsDepthInfinity == false && facts.supportsDepth1 == false -> "none"
        else -> "auto"
    }

    private fun publishStrategyFor(profile: WebDavBackendProfile, facts: WebDavFeatureFacts?): String = when {
        facts?.supportsAtomicPublish == true && facts.supportsMove == true -> "atomic-move"
        facts?.supportsAtomicPublish == false -> "direct"
        profile.atomicReplace -> "atomic-profile"
        else -> "auto"
    }

    private fun verifyStrategyFor(facts: WebDavFeatureFacts?): String = when {
        facts?.supportsRemoteSize == true && facts.bodyCompareOk == true -> "stat-size+body-compare"
        facts?.supportsRemoteSize == true -> "stat-size"
        facts?.supportsStat == true -> "stat-exists"
        else -> "best-effort"
    }

    private fun cleanupPolicyFor(profile: WebDavBackendProfile, facts: WebDavFeatureFacts?): String = when {
        profile.kind == "cloudreve" -> "delete-blocked-cloudreve"
        facts?.supportsDelete == true && facts.cleanupOk == true -> "delete-verified"
        facts?.supportsDelete == true -> "delete-best-effort"
        facts?.supportsDelete == false -> "no-delete"
        else -> "auto"
    }

    private fun securityAdvisoryFor(profile: WebDavBackendProfile, alist: AlistSecurityAdvisory): String = when {
        profile.kind == "cloudreve" -> "cloudreve-orphan-delete-blocked"
        alist.state == "affected_lt_3.57.0" -> "alist-path-traversal-upgrade-recommended"
        alist.state == "version_unknown" -> "alist-version-unknown-check-recommended"
        else -> "none"
    }

    private fun detectServerKind(user: String, pass: String, baseUrl: String): String {
        val key = serverKindCacheKey(baseUrl)
        serverKindCache[key]?.let { return it }
        val (code, body) = optionsDav(user, pass, buildRelUrl(baseUrl, ""))
        val kind = classifyServerKind(baseUrl, code, body)
        cacheServerKind(baseUrl, code, kind)
        return kind
    }

    private fun isAppDetailsJson(relPath: String): Boolean {
        return relPath.trimEnd('/').substringAfterLast('/') == "app_details.json"
    }

    private fun isAlistFamily(kind: String): Boolean = kind == "alist" || kind == "openlist" || kind == "alist_compatible"

    private fun webDavBackendProfile(user: String, pass: String, baseUrl: String, reason: String): WebDavBackendProfile {
        val kind = detectServerKind(user, pass, baseUrl)
        val facts = featureFactsCache[featureFactsKey(baseUrl)]
        val vendorDirectAll = kind == "rclone" || kind == "123pan"
        // r612: once atomic-publish capability is measured, the fact wins over legacy
        // vendor defaults in either direction. Vendor identity remains only a fallback
        // before probing and a semantic/display hint for server-specific behavior.
        val directAll = when (facts?.supportsAtomicPublish) {
            false -> true
            true -> false
            null -> vendorDirectAll
        }
        // r598: the remote filelist fact is authoritative for a new streaming payload.
        // A generic/blank Server header must not force a known-missing archive back to .part+MOVE.
        // r600 recognizes both official AList and OpenList (used by AListLiteAndroid), while
        // retaining :5244/dav as an alist-compatible fallback when Server is stripped.
        val alistFamily = isAlistFamily(kind)
        val alistServerHeader = if (alistFamily) runCatching { parseKeyValueLines(optionsDav(user, pass, buildRelUrl(baseUrl, "")).second)["server"].orEmpty() }.getOrDefault("") else ""
        val alistSecurity = alistSecurityAdvisory(kind, alistServerHeader)
        val newPayloadDirect = directAll || alistFamily || kind == "generic"
        // r600: BODY_DONE means only that SpeedBackup emitted the request body. AList/OpenList
        // can still synchronously hash/cache/upload to a backing provider before WebDAV PUT 2xx.
        // Keep the safety bound, but model/log it as post-body server processing, not finalize.
        val defaultPostBodySec = if (alistFamily) 900L else 180L
        val profile = WebDavBackendProfile(
            kind = kind,
            directAll = directAll,
            newPayloadDirect = newPayloadDirect,
            cjkPathRetry = true,
            postBodyTimeoutMs = streamPostBodyTimeoutMs(defaultPostBodySec),
            atomicReplace = !directAll && facts?.supportsAtomicPublish != false,
            supportTier = supportTier(kind, facts),
            featureSource = facts?.source ?: "server-profile",
            reason = reason
        )
        val providerHint = providerHintFromBaseUrl(baseUrl, kind)
        infoLog(
            "WEBDAV_BACKEND_PROFILE schema=speedbackup.webdav_backend_profile.v3 " +
                "kind=${profile.kind} serverFamily=${serverFamilyForKind(kind)} serverDisplay=${sanitizeTsv(serverDisplayForKind(kind)).replace(' ', '_')} " +
                "behaviorProfile=${behaviorProfileForKind(kind)} syncPutServer=${if (alistFamily) 1 else 0} " +
                "providerId=${providerHint.id.ifEmpty { "none" }} providerRegion=${providerHint.region.ifEmpty { "none" }} " +
                "providerClass=${providerHint.providerClass.ifEmpty { "none" }} providerHintSource=${providerHint.source} providerHintConfidence=${providerHint.confidence} " +
                "alistVersion=${alistSecurity.version} alistSecurityAdvisory=${alistSecurity.cve} alistPathTraversalRisk=${alistSecurity.state} alistMinSafeVersion=${alistSecurity.minSafeVersion} alistSecurityAction=${alistSecurity.action} " +
                "directAll=${if (profile.directAll) 1 else 0} newPayloadDirect=${if (profile.newPayloadDirect) 1 else 0} " +
                "atomicReplace=${if (profile.atomicReplace) 1 else 0} cjkPathRetry=${if (profile.cjkPathRetry) 1 else 0} " +
                "supportTier=${profile.supportTier} featureSource=${profile.featureSource} featureSummary=${featureSummary(facts).replace(' ', '_')} " +
                "postBodyTimeoutSec=${profile.postBodyTimeoutMs / 1000} reason=$reason " +
                "postBodyPolicy=${if (alistFamily) "sync-put-server-processing" else "response-head"} mode=r613"
        )
        return profile
    }

    private fun normalizeManagedMode(modeRaw: String?): String {
        return (modeRaw ?: "auto").trim().lowercase(java.util.Locale.US).ifEmpty { "auto" }
    }

    private fun modeMeansKnownMissing(mode: String): Boolean {
        return mode == "known-missing" || mode == "new-known-missing" || mode == "direct-new-known-missing" || mode == "auto-known-missing"
    }

    private fun managedDecision(user: String, pass: String, baseUrl: String, relPath: String, modeRaw: String?): ManagedDecision {
        val mode = normalizeManagedMode(modeRaw)
        val forcedProfile = WebDavBackendProfile("not_checked", false, false, true, streamPostBodyTimeoutMs(), true, "GENERIC", "forced", "forced")
        if (mode == "direct") return ManagedDecision(true, "direct_forced", "not_checked", forcedProfile, mode, false)
        if (mode == "atomic") return ManagedDecision(false, "atomic_forced", "not_checked", forcedProfile, mode, false)
        val profile = webDavBackendProfile(user, pass, baseUrl, "managed_put")
        val kind = profile.kind
        val knownMissing = modeMeansKnownMissing(mode)
        val direct = when {
            mode == "direct-json" -> isAppDetailsJson(relPath)
            knownMissing -> profile.newPayloadDirect
            mode == "auto" -> profile.directAll
            else -> false
        }
        val modeName = when {
            direct && mode == "direct-json" -> "direct_json"
            direct && knownMissing && isAlistFamily(kind) -> "alist_family_direct_new_known_missing"
            direct && knownMissing && kind == "generic" -> "generic_direct_new_known_missing"
            direct && knownMissing -> "direct_new_known_missing"
            direct && mode == "auto" && kind == "rclone" && isAppDetailsJson(relPath) -> "rclone_direct_json"
            direct && mode == "auto" && kind == "rclone" -> "rclone_direct_all"
            direct && mode == "auto" && kind == "123pan" && isAppDetailsJson(relPath) -> "pan123_direct_json"
            direct && mode == "auto" && kind == "123pan" -> "pan123_direct_all"
            direct -> "direct"
            else -> "atomic"
        }
        infoLog(
            "WEBDAV_BACKEND_DECISION schema=speedbackup.webdav_backend_decision.v1 " +
                "rel=$relPath requestedMode=$mode knownMissing=${if (knownMissing) 1 else 0} " +
                "kind=$kind direct=${if (direct) 1 else 0} mode=$modeName " +
                "directAll=${if (profile.directAll) 1 else 0} newPayloadDirect=${if (profile.newPayloadDirect) 1 else 0} " +
                "atomicReplace=${if (profile.atomicReplace) 1 else 0} supportTier=${profile.supportTier} featureSource=${profile.featureSource} " +
                "postBodyTimeoutSec=${profile.postBodyTimeoutMs / 1000} postBodySemantics=server_processing_until_put_response modeVersion=r613"
        )
        return ManagedDecision(direct, modeName, kind, profile, mode, knownMissing)
    }

    private fun managedPartRel(relPath: String): String {
        val rel = relPath.trimStart('/')
        val seq = managedUploadSeq.incrementAndGet()
        return "$rel.part.${System.currentTimeMillis()}.$seq"
    }

    private enum class ParentMkdirMode(val wire: String) {
        ENSURE("ensureParentMkdir"),
        SKIP("skipParentMkdir"),
    }

    private fun parseParentMkdirMode(raw: String?): ParentMkdirMode {
        val v = (raw ?: "ensureParentMkdir").trim().lowercase(java.util.Locale.US)
        return when (v) {
            "skip", "skipparentmkdir", "skip-parent-mkdir", "parentalreadyensured", "parentalreadyensured=1", "skipparentmkdir=1" -> ParentMkdirMode.SKIP
            else -> ParentMkdirMode.ENSURE
        }
    }

    private fun parentRelForManagedPut(relPath: String): String {
        val rel = relPath.trim('/').takeIf { it.isNotEmpty() && it != "." } ?: return ""
        return rel.substringBeforeLast('/', missingDelimiterValue = "")
    }

    private fun ensureManagedPutParent(user: String, pass: String, baseUrl: String, relPath: String, parentModeRaw: String?): Int {
        val parentRel = parentRelForManagedPut(relPath)
        val mode = parseParentMkdirMode(parentModeRaw)
        if (parentRel.isEmpty()) {
            infoLog("MANAGED_PUT_PARENT mode=none rel=$relPath parent= code=200")
            return 200
        }
        if (mode == ParentMkdirMode.SKIP) {
            infoLog("MANAGED_PUT_PARENT mode=skipParentMkdir rel=$relPath parent=$parentRel code=200")
            return 200
        }
        val code = mkcolParentsRel(user, pass, baseUrl, parentRel)
        infoLog("MANAGED_PUT_PARENT mode=ensureParentMkdir rel=$relPath parent=$parentRel code=$code")
        return code
    }

    private fun limitInputBytes(input: InputStream, maxBytes: Long, label: String): InputStream {
        return object : InputStream() {
            var count = 0L
            override fun read(): Int {
                if (count >= maxBytes) {
                    // Distinguish an exactly-at-limit stream from one byte over the limit.
                    // Throw only if the source actually has more data; EOF at maxBytes is valid.
                    val extra = input.read()
                    if (extra < 0) return -1
                    throw IOException("WEBDAV_PROVIDER_LIMIT_EXCEEDED label=$label limit=$maxBytes")
                }
                val value = input.read()
                if (value >= 0) count++
                return value
            }
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                if (length == 0) return 0
                if (count >= maxBytes) {
                    val extra = input.read()
                    if (extra < 0) return -1
                    throw IOException("WEBDAV_PROVIDER_LIMIT_EXCEEDED label=$label limit=$maxBytes")
                }
                val allowed = minOf(length.toLong(), maxBytes - count).toInt()
                val n = input.read(buffer, offset, allowed)
                if (n > 0) count += n.toLong()
                return n
            }
            override fun close() = input.close()
        }
    }

    private fun putStdinManagedRel(user: String, pass: String, baseUrl: String, relPath: String, mode: String?, parentMode: String?, input: InputStream): Int {
        val parentCode = ensureManagedPutParent(user, pass, baseUrl, relPath, parentMode)
        if (parentCode !in 200..299) return parentCode
        val decision = managedDecision(user, pass, baseUrl, relPath, mode)
        val baseHost = runCatching { URL(baseUrl).host.lowercase(java.util.Locale.US) }.getOrDefault("")
        val publicJianguoyun = decision.serverKind == "jianguoyun" && (baseHost.contains("jianguoyun") || baseHost.contains("nutstore"))
        val sourceInput = if (publicJianguoyun) {
            infoLog("WEBDAV_PROVIDER_LIMIT_ARM provider=jianguoyun kind=single_file_default_500m rel=$relPath limit=500000000 mode=r610")
            limitInputBytes(input, 500_000_000L, "jianguoyun_500m")
        } else input
        val targetRel = if (decision.direct) relPath else managedPartRel(relPath)
        infoLog("MANAGED_PUT mode=${decision.modeName} server=${decision.serverKind} rel=$relPath target=$targetRel streamMeter=1")
        val postBodyTimeoutMs = decision.profile.postBodyTimeoutMs
        val meter = WebDavStreamMeter(relPath, decision.modeName, decision.serverKind, targetRel, postBodyTimeoutMs)
        meter.begin()
        val meteredInput = meter.wrap(sourceInput)
        var terminalFailure: Throwable? = null
        val code = if (decision.direct) {
            val targetUrl = buildRelUrl(baseUrl, relPath)
            val putCode = runCatching {
                put(user, pass, targetUrl, meteredInput, contentLength = null, chunked = true, meter = meter, responseHeadTimeoutMs = postBodyTimeoutMs)
            }.getOrElse { e -> terminalFailure = e; HttpCore.extractCode(e) }
            val recovered = putCode !in 200..299 && ambiguousPutVerifiedAfterStat(
                user, pass, targetUrl, relPath, meter.sentBytes(), putCode, terminalFailure,
                clientBodyComplete = meter.clientBodyComplete(), context = "stream-direct", allowSizeOnly = true
            )
            val normalized = if (recovered) 200 else putCode
            if (normalized in 200..299 && !verifiedPut2xxAfterStat(user, pass, baseUrl, targetUrl, relPath, meter.sentBytes(), "stream-direct", requireKnownRemoteSize = true, allowSizeOnly = true)) PUT_SEMANTIC_FAILURE_HTTP_CODE else normalized
        } else {
            val targetUrl = buildRelUrl(baseUrl, targetRel)
            val putCode = runCatching {
                put(user, pass, targetUrl, meteredInput, contentLength = null, chunked = true, meter = meter, responseHeadTimeoutMs = postBodyTimeoutMs)
            }.getOrElse { e -> terminalFailure = e; HttpCore.extractCode(e) }
            val putRecovered = putCode !in 200..299 && ambiguousPutVerifiedAfterStat(
                user, pass, targetUrl, targetRel, meter.sentBytes(), putCode, terminalFailure,
                clientBodyComplete = meter.clientBodyComplete(), context = "stream-atomic-part", allowSizeOnly = true
            )
            if (putCode !in 200..299 && !putRecovered) {
                putCode
            } else {
                val putOk = if (putRecovered) true else verifiedPut2xxAfterStat(user, pass, baseUrl, targetUrl, targetRel, meter.sentBytes(), "stream-atomic-part", requireKnownRemoteSize = true, allowSizeOnly = true)
                if (!putOk) {
                    PUT_SEMANTIC_FAILURE_HTTP_CODE
                } else {
                    val moveCode = move(user, pass, targetUrl, buildRelUrl(baseUrl, relPath), overwrite = true, expectedLength = meter.sentBytes())
                    if (moveCode !in 200..299) runCatching { deleteCleanup(user, pass, targetUrl, "atomic-part-after-move-fail") }
                    moveCode
                }
            }
        }
        if (terminalFailure != null && code !in 200..299) meter.fail(terminalFailure!!) else meter.finish(code)
        if (code in 200..299) {
            invalidateListCache()
        } else if (decision.direct && decision.knownMissing) {
            if (isAmbiguousPutCode(code)) {
                infoLog("MANAGED_PUT_DIRECT_NEW_MISSING_CLEANUP_SKIP rel=$relPath mode=${decision.modeName} afterHttp=$code reason=put-ambiguous-unverified mode=r613")
            } else {
                val cleanupCode = runCatching { deleteCleanup(user, pass, buildRelUrl(baseUrl, relPath), "direct-new-failed") }.getOrDefault(0)
                infoLog("MANAGED_PUT_DIRECT_NEW_MISSING_CLEANUP rel=$relPath mode=${decision.modeName} code=$cleanupCode afterHttp=$code")
            }
        }
        return code
    }

    private fun putFileManagedRel(user: String, pass: String, baseUrl: String, relPath: String, localFile: String, mode: String?, parentMode: String?): Int {
        val file = File(localFile)
        if (!file.isFile) return 0
        val parentCode = ensureManagedPutParent(user, pass, baseUrl, relPath, parentMode)
        if (parentCode !in 200..299) return parentCode
        val decision = managedDecision(user, pass, baseUrl, relPath, mode)
        val baseHost = runCatching { URL(baseUrl).host.lowercase(java.util.Locale.US) }.getOrDefault("")
        val publicJianguoyun = decision.serverKind == "jianguoyun" && (baseHost.contains("jianguoyun") || baseHost.contains("nutstore"))
        val jianguoyunDefaultLimit = 500_000_000L
        if (publicJianguoyun && file.length() > jianguoyunDefaultLimit) {
            infoLog("WEBDAV_PROVIDER_LIMIT_REJECT provider=jianguoyun kind=single_file_default_500m rel=$relPath size=${file.length()} limit=$jianguoyunDefaultLimit action=fail_early mode=r610")
            return 413
        }
        val facts = featureFactsCache[featureFactsKey(baseUrl)]
        // r612: all replayable local-file endpoints share the same fact-driven fixed/chunked policy.
        val chunkedFilePut = replayableLocalFileUsesChunked(baseUrl)
        infoLog("MANAGED_PUT_FILE mode=${decision.modeName} server=${decision.serverKind} rel=$relPath file=${file.name} size=${file.length()} chunked=${if (chunkedFilePut) 1 else 0} featureSource=${facts?.source ?: "unknown"}")
        fun putLocalFile(targetRel: String): PutAttempt = putReplayableLocalFileAttempt(user, pass, baseUrl, targetRel, file)
        val code = if (decision.direct) {
            val targetUrl = buildRelUrl(baseUrl, relPath)
            val attempt = putLocalFile(relPath)
            val recovered = attempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
                user, pass, targetUrl, relPath, file.length(), attempt.code, attempt.failure,
                clientBodyComplete = attempt.clientBodyComplete, context = "file-direct",
                allowSizeOnly = decision.knownMissing, compareLocalFile = if (decision.knownMissing) null else file
            )
            val normalized = if (recovered) 200 else attempt.code
            if (normalized in 200..299 && !verifiedPut2xxAfterStat(user, pass, baseUrl, targetUrl, relPath, file.length(), "file-direct", requireKnownRemoteSize = true, allowSizeOnly = decision.knownMissing, compareLocalFile = if (decision.knownMissing) null else file)) PUT_SEMANTIC_FAILURE_HTTP_CODE else normalized
        } else {
            val partRel = managedPartRel(relPath)
            val partUrl = buildRelUrl(baseUrl, partRel)
            val attempt = putLocalFile(partRel)
            val putRecovered = attempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
                user, pass, partUrl, partRel, file.length(), attempt.code, attempt.failure,
                clientBodyComplete = attempt.clientBodyComplete, context = "file-atomic-part", allowSizeOnly = true
            )
            if (attempt.code !in 200..299 && !putRecovered) {
                attempt.code
            } else {
                val putOk = if (putRecovered) true else verifiedPut2xxAfterStat(user, pass, baseUrl, partUrl, partRel, file.length(), "file-atomic-part", requireKnownRemoteSize = true, allowSizeOnly = true)
                if (!putOk) {
                    PUT_SEMANTIC_FAILURE_HTTP_CODE
                } else {
                    val moveCode = move(user, pass, partUrl, buildRelUrl(baseUrl, relPath), overwrite = true, expectedLength = file.length())
                    if (moveCode !in 200..299) runCatching { deleteCleanup(user, pass, partUrl, "atomic-file-part-after-move-fail") }
                    moveCode
                }
            }
        }
        if (code in 200..299) {
            invalidateListCache()
        } else if (decision.direct && decision.knownMissing) {
            if (isAmbiguousPutCode(code)) {
                infoLog("MANAGED_PUT_FILE_DIRECT_NEW_MISSING_CLEANUP_SKIP rel=$relPath mode=${decision.modeName} afterHttp=$code reason=put-ambiguous-unverified mode=r613")
            } else {
                val cleanupCode = runCatching { deleteCleanup(user, pass, buildRelUrl(baseUrl, relPath), "direct-file-new-failed") }.getOrDefault(0)
                infoLog("MANAGED_PUT_FILE_DIRECT_NEW_MISSING_CLEANUP rel=$relPath mode=${decision.modeName} code=$cleanupCode afterHttp=$code")
            }
        }
        return code
    }

    private fun managedBatchPutRelWithParents(user: String, pass: String, baseUrl: String, mode: String?, parentMode: String?, rootRelRaw: String, body: String): Pair<Int, String> {
        data class BatchItem(val rel: String, val localFile: String)
        val items = ArrayList<BatchItem>()
        val parentManifest = StringBuilder()
        val seenParents = HashSet<String>()
        for (line in body.lineSequence()) {
            val raw = line.trim()
            if (raw.isEmpty() || raw.startsWith("#")) continue
            val parts = raw.split('\t')
            if (parts.size < 2) continue
            val rel = sanitizeRelPath(parts[0])
            val file = parts[1].trim()
            if (rel.isEmpty() || file.isEmpty()) continue
            items.add(BatchItem(rel, file))
            val parent = parentRelForManagedPut(rel)
            if (parent.isNotEmpty() && seenParents.add(parent)) parentManifest.append(parent).append('\n')
        }
        if (items.isEmpty()) return 200 to "SUMMARY\ttotal=0\tok=0\tfailed=0\tparents=0\tmode=batch-empty\n"
        val parentResult = if (parseParentMkdirMode(parentMode) == ParentMkdirMode.SKIP || parentManifest.isEmpty()) {
            200 to "SUMMARY\ttotal=0\texisting=0\tcreated=0\tok=0\tfailed=0\trootStatus=0\tmode=skip-parent\n"
        } else {
            val rootRel = rootRelRaw.ifBlank { commonRootForParents(seenParents) }
            prepareDirsPlanRel(user, pass, baseUrl, rootRel, "create", parentManifest.toString(), "")
        }
        val out = StringBuilder(items.size * 96)
        var ok = 0
        var failed = 0
        var finalCode = parentResult.first
        out.append("PARENTS\tcode=").append(parentResult.first)
            .append("\tparents=").append(seenParents.size)
            .append("\tmode=preparedirsplanrel\n")
        if (parentResult.first !in 200..299) {
            out.append(parentResult.second)
            out.append("SUMMARY\ttotal=").append(items.size).append("\tok=0\tfailed=").append(items.size).append("\tparents=").append(seenParents.size).append("\tmode=parent-failed\n")
            return finalCode to out.toString()
        }
        for (item in items) {
            val file = File(item.localFile)
            if (!file.isFile) {
                failed++
                if (finalCode in 200..299) finalCode = 404
                out.append("FAIL\t").append(item.rel).append('\t').append(item.localFile).append("\t404\tlocal-file-missing\n")
                continue
            }
            val code = putFileManagedRel(user, pass, baseUrl, item.rel, item.localFile, mode, "skipParentMkdir")
            if (code in 200..299) {
                ok++
                out.append("OK\t").append(item.rel).append('\t').append(item.localFile).append('\t').append(code).append("\tmanaged-put\n")
            } else {
                failed++
                if (finalCode in 200..299) finalCode = code
                out.append("FAIL\t").append(item.rel).append('\t').append(item.localFile).append('\t').append(code).append("\tmanaged-put\n")
            }
        }
        out.append("SUMMARY\ttotal=").append(items.size)
            .append("\tok=").append(ok)
            .append("\tfailed=").append(failed)
            .append("\tparents=").append(seenParents.size)
            .append("\tmode=managedBatchPutRelWithParents\n")
        return finalCode to out.toString()
    }

    private fun commonRootForParents(parents: Set<String>): String {
        if (parents.isEmpty()) return ""
        val first = parents.first().split('/').filter { it.isNotEmpty() }
        if (first.isEmpty()) return ""
        val out = ArrayList<String>()
        for (i in first.indices) {
            val seg = first[i]
            if (parents.all { p -> p.split('/').filter { it.isNotEmpty() }.getOrNull(i) == seg }) out.add(seg) else break
        }
        return out.joinToString("/")
    }

    private fun managedProbeRel(user: String, pass: String, baseUrl: String, relBase: String): Pair<Int, String> {
        val kind = detectServerKind(user, pass, baseUrl)
        val base = relBase.trim('/').takeIf { it.isNotEmpty() && it != "." } ?: ""
        val name = "speedbackup_managed_probe_${System.currentTimeMillis()}_${managedUploadSeq.incrementAndGet()}"
        val partRel = if (base.isEmpty()) "$name.part" else "$base/$name.part"
        val finalRel = if (base.isEmpty()) name else "$base/$name"
        val bytes = "speedbackup_managed_probe".toByteArray(StandardCharsets.UTF_8)
        // r610: this probe gates the real tar|zstd -> WebDAV path, so it must prove chunked PUT,
        // not merely a fixed Content-Length PUT. The tiny body is replayable only for probing.
        val partUrl = buildRelUrl(baseUrl, partRel)
        val putAttempt = putReplayableChunkedBytesAttempt(user, pass, partUrl, bytes)
        val putRecovered = putAttempt.code !in 200..299 && ambiguousPutVerifiedAfterStat(
            user, pass, partUrl, partRel, bytes.size.toLong(), putAttempt.code, putAttempt.failure,
            clientBodyComplete = putAttempt.clientBodyComplete, context = "managed-probe-chunked-put", allowSizeOnly = true
        )
        val putCode = if (putRecovered) 200 else putAttempt.code
        val putVerified = putRecovered || (putCode in 200..299 &&
            verifiedPut2xxAfterStat(user, pass, baseUrl, partUrl, partRel, bytes.size.toLong(), "managed-probe-chunked-put-2xx", requireKnownRemoteSize = false, allowSizeOnly = true))
        if (putCode !in 200..299 || !putVerified) {
            cacheFeatureFacts(baseUrl, WebDavFeatureFacts(
                supportsChunkedPut = false, source = "managed-probe-chunked-put-fail"
            ))
            return (if (putCode in 200..299) PUT_SEMANTIC_FAILURE_HTTP_CODE else putCode) to "step=chunked-put http=$putCode putVerified=${if (putVerified) 1 else 0} server=$kind rel=$partRel replayable=true chunked=1 temp=nodot\n"
        }
        val moveCode = move(user, pass, partUrl, buildRelUrl(baseUrl, finalRel), overwrite = true, expectedLength = bytes.size.toLong())
        if (moveCode !in 200..299) {
            // MOVE support is optional for a usable streaming backend. The successful PUT
            // already proves direct upload works, so cache atomic=false and let auto mode
            // switch to direct PUT instead of disabling WebDAV entirely.
            val cleanupCode = runCatching { deleteCleanup(user, pass, partUrl, "managed-probe-part") }.getOrDefault(0)
            cacheFeatureFacts(baseUrl, WebDavFeatureFacts(
                supportsChunkedPut = true, supportsMove = false, supportsAtomicPublish = false,
                source = "managed-probe-direct-fallback"
            ))
            return 200 to "step=fallback-direct putHttp=$putCode putRecovered=${if (putRecovered) 1 else 0} moveHttp=$moveCode server=$kind src=$partRel dst=$finalRel cleanup=$cleanupCode directFallback=1 chunked=1\n"
        }
        // MOVE 2xx is authoritative evidence that atomic publish exists. STAT is a separate
        // capability: if unsupported, do not incorrectly disable a working MOVE backend.
        val (statCode, entry) = statDav(user, pass, buildRelUrl(baseUrl, finalRel))
        val statSupported = statCode in 200..299 && entry != null && !entry.isDirectory
        val sizeOk = statSupported && entry?.length == bytes.size.toLong()
        val cleanupCode = runCatching { deleteCleanup(user, pass, buildRelUrl(baseUrl, finalRel), "managed-probe-final") }.getOrDefault(0)
        cacheFeatureFacts(baseUrl, WebDavFeatureFacts(
            supportsChunkedPut = true, supportsMove = true, supportsStat = statSupported,
            supportsAtomicPublish = true, source = "managed-probe"
        ))
        return 200 to "step=move-confirmed putRecovered=${if (putRecovered) 1 else 0} moveHttp=$moveCode statHttp=$statCode statSupported=${if (statSupported) 1 else 0} sizeOk=${if (sizeOk) 1 else 0} server=$kind rel=$finalRel cleanup=$cleanupCode chunked=1 temp=nodot\n"
    }

    private fun getTo(user: String, pass: String, url: String, out: OutputStream): Int {
        return http.request("GET", url, user, pass, followRedirects = true, canReplayBody = true) { code, headers, input ->
            if (code in 200..299) HttpCore.readResponseBody(headers, input, out) else HttpCore.discardErrorResponseBody(headers, input)
        }
    }

    private fun delete(user: String, pass: String, url: String, maxAttempts: Int = 4): Int {
        val raw = pacedCode(DavOperation.DELETE, maxAttempts = maxAttempts) {
            http.request("DELETE", url, user, pass, mapOf("Content-Length" to "0"), followRedirects = true, canReplayBody = true)
        }
        val decision = policyFor(DavOperation.DELETE, raw)
        if (decision.ok) {
            invalidateListCache()
            invalidateDirectoryCache()
        }
        return if (decision.ok) decision.normalizedCode else raw
    }

    // AList/OpenList backed providers (notably some Aliyun paths) may leave a failed
    // upload temporarily locked. Cleanup is advisory and bounded: one DELETE per delay,
    // no nested pacer fan-out, and an orphan may be left for the next manual cleanup.
    private fun deleteCleanup(user: String, pass: String, url: String, reason: String): Int {
        var code = delete(user, pass, url, maxAttempts = 1)
        if (code != 423) return code
        val delays = intArrayOf(1_000, 2_000, 4_000, 8_000)
        for ((idx, delayMs) in delays.withIndex()) {
            infoLog("WEBDAV_CLEANUP_LOCKED_DEFER reason=$reason http=$code delayMs=$delayMs attempt=${idx + 2} mode=r610")
            try { Thread.sleep(delayMs.toLong()) } catch (_: InterruptedException) { Thread.currentThread().interrupt(); break }
            code = delete(user, pass, url, maxAttempts = 1)
            if (code != 423) return code
        }
        infoLog("WEBDAV_CLEANUP_DEFERRED reason=$reason http=$code action=leave-orphan-for-next-cleanup mode=r610")
        return code
    }

    private fun mutationVerifiedAfterAmbiguous(
        user: String, pass: String, srcBefore: DavEntry?, srcUrl: String, dstUrl: String,
        operation: String, code: Int, failure: Throwable?
    ): Boolean {
        if (!isTransientWebDavCode(code) || srcBefore == null || srcBefore.isDirectory) return false
        val message = failure?.message.orEmpty()
        if (message.startsWith("HTTP_REDIRECT_AUTH_")) return false
        val (dstCode, dst) = statDav(user, pass, dstUrl)
        val sizeOk = dstCode in 200..299 && dst != null && !dst.isDirectory && dst.length == srcBefore.length
        val recovered = if (!sizeOk) {
            false
        } else if (operation == "MOVE") {
            val (srcAfterCode, srcAfter) = statDav(user, pass, srcUrl)
            val sourceGone = srcAfterCode == 404 || srcAfter == null && srcAfterCode !in 200..299
            infoLog("WEBDAV_MUTATION_VERIFY_SOURCE operation=MOVE sourceHttp=$srcAfterCode sourceGone=${if (sourceGone) 1 else 0} mode=r610")
            sourceGone
        } else {
            val srcEtag = srcBefore.etag.trim()
            val dstEtag = dst?.etag?.trim().orEmpty()
            srcEtag.isNotEmpty() && dstEtag.isNotEmpty() && srcEtag == dstEtag
        }
        infoLog("WEBDAV_MUTATION_VERIFY operation=$operation originalHttp=$code dstHttp=$dstCode expectedBytes=${srcBefore.length} actualBytes=${dst?.length ?: -1} recovered=${if (recovered) 1 else 0} mode=r610")
        return recovered
    }

    private fun move(
        user: String, pass: String, srcUrl: String, dstUrl: String, overwrite: Boolean = true, expectedLength: Long? = null
    ): Int {
        // Managed PUT callers already know the byte count. Reuse it so normal atomic uploads
        // do not pay an extra pre-MOVE PROPFIND; generic moverel still probes the source.
        val srcBefore = if (expectedLength != null && expectedLength >= 0L) {
            DavEntry(srcUrl, expectedLength, isDirectory = false)
        } else {
            runCatching { statDav(user, pass, srcUrl).second }.getOrNull()
        }
        val headers = linkedMapOf(
            "Destination" to webDavDestinationHeader(dstUrl),
            "Overwrite" to if (overwrite) "T" else "F",
            "Content-Length" to "0"
        )
        var failure: Throwable? = null
        val code = runCatching { http.request("MOVE", srcUrl, user, pass, headers, followRedirects = true, canReplayBody = true, retryOnConnectionFailure = { false }) }.getOrElse { failure = it; HttpCore.extractCode(it) }
        val decision = policyFor(DavOperation.MOVE, code)
        val recovered = !decision.ok && mutationVerifiedAfterAmbiguous(user, pass, srcBefore, srcUrl, dstUrl, "MOVE", code, failure)
        if (decision.ok || recovered) {
            invalidateListCache()
            invalidateDirectoryCache()
            return if (recovered) 200 else decision.normalizedCode
        }
        return code
    }

    private fun copy(user: String, pass: String, srcUrl: String, dstUrl: String, overwrite: Boolean = true): Int {
        val srcBefore = runCatching { statDav(user, pass, srcUrl).second }.getOrNull()
        val headers = linkedMapOf(
            "Destination" to webDavDestinationHeader(dstUrl),
            "Overwrite" to if (overwrite) "T" else "F",
            "Content-Length" to "0"
        )
        var failure: Throwable? = null
        val code = runCatching { http.request("COPY", srcUrl, user, pass, headers, followRedirects = true, canReplayBody = true, retryOnConnectionFailure = { false }) }.getOrElse { failure = it; HttpCore.extractCode(it) }
        val decision = policyFor(DavOperation.COPY, code)
        val recovered = !decision.ok && mutationVerifiedAfterAmbiguous(user, pass, srcBefore, srcUrl, dstUrl, "COPY", code, failure)
        if (decision.ok || recovered) {
            invalidateListCache()
            invalidateDirectoryCache()
            return if (recovered) 200 else decision.normalizedCode
        }
        return code
    }

    /**
     * WebDAV Destination is an absolute URI. Encode the path component without
     * double-encoding existing %HH escapes so CJK/space relPaths work on strict
     * servers while preserving tools.sh already-encoded paths.
     */
    private fun webDavDestinationHeader(dstUrl: String): String {
        val u = URL(dstUrl)
        val defaultPort = (u.protocol.equals("http", ignoreCase = true) && (u.port == -1 || u.port == 80)) ||
            (u.protocol.equals("https", ignoreCase = true) && (u.port == -1 || u.port == 443))
        val host = if (u.host.contains(":") && !u.host.startsWith("[")) "[${u.host}]" else u.host
        val authority = if (defaultPort) host else "$host:${u.port}"
        val path = HttpCore.percentEncodePathPreservingEscapes(u.path.takeIf { it.isNotEmpty() } ?: "/")
        return "${u.protocol}://$authority$path"
    }

    private fun quotaDav(user: String, pass: String, url: String): Pair<Int, WebDavQuota> {
        val bodyOut = ByteArrayOutputStream()
        val headers = linkedMapOf(
            "Depth" to "0",
            "Content-Type" to "application/xml; charset=utf-8",
            "Content-Length" to DAV_QUOTA_BODY.size.toString()
        )
        val code = pacedCode(DavOperation.PROPFIND) {
            http.request("PROPFIND", url, user, pass, headers, bodyWriter = { out -> out.write(DAV_QUOTA_BODY) }, followRedirects = true, canReplayBody = true) { status, respHeaders, input ->
                if (status in 200..299) HttpCore.readResponseBody(respHeaders, input, bodyOut) else HttpCore.discardErrorResponseBody(respHeaders, input)
            }
        }
        if (code !in 200..299) return code to WebDavQuota(state = "unavailable")
        val bytes = bodyOut.toByteArray()
        val text = bytes.toString(StandardCharsets.UTF_8)
        val available = firstXmlTagText(text, "quota-available-bytes")?.trim()?.toLongOrNull()
        val used = firstXmlTagText(text, "quota-used-bytes")?.trim()?.toLongOrNull()
        val state = if (available != null || used != null) "supported" else "unsupported"
        return code to WebDavQuota(available, used, state)
    }

    private fun quotaRel(user: String, pass: String, baseUrl: String, relPath: String): Pair<Int, String> {
        val (code, quota) = quotaDav(user, pass, buildRelUrl(baseUrl, relPath))
        return code to buildString {
            append("state=").append(quota.state).append('\n')
            append("availableBytes=").append(quota.availableBytes ?: -1L).append('\n')
            append("usedBytes=").append(quota.usedBytes ?: -1L).append('\n')
        }
    }

    private fun verifyUploadMapRel(user: String, pass: String, baseUrl: String, rootRelRaw: String, manifest: String): Pair<Int, String> {
        val rootRel = sanitizeRelPath(rootRelRaw).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val expected = linkedMapOf<String, Long>()
        manifest.lineSequence().forEach { line ->
            if (line.isBlank()) return@forEach
            val parts = line.split('\t')
            if (parts.size < 2) return@forEach
            val rel = sanitizeRelPath(parts[0].trim()).trim('/')
            val size = parts[1].trim().toLongOrNull() ?: return@forEach
            if (rel.isNotEmpty() && size >= 0L) expected[rel] = size
        }
        if (expected.isEmpty()) return 400 to "SUMMARY\ttotal=0\tverified=0\tmissing=0\tmismatch=0\tunverifiable=0\tstate=empty\n"
        val (listCode, classified) = classifyListRel(user, pass, baseUrl, rootRel, -1)
        if (listCode !in 200..299) return listCode to "SUMMARY\ttotal=${expected.size}\tverified=0\tmissing=${expected.size}\tmismatch=0\tunverifiable=0\tstate=list_failed\thttp=$listCode\n"
        val actual = HashMap<String, Long>()
        classified.lineSequence().forEach { line ->
            val parts = line.split('\t')
            // classifyListRel has semantic kinds (APP_PAYLOAD/MEDIA_PAYLOAD/APP_METADATA/etc.).
            // Every non-directory object can satisfy an exact-path upload verification.
            if (parts.size >= 3 && parts[0] != "DIR") {
                parts[2].toLongOrNull()?.let { actual[parts[1].trim('/')] = it }
            }
        }
        val out = StringBuilder()
        var verified = 0
        var missing = 0
        var mismatch = 0
        var unverifiable = 0
        for ((rel, size) in expected) {
            val got = actual[rel]
            when {
                got == null -> { missing++; out.append("MISSING\t").append(rel).append("\t").append(size).append("\t-1\n") }
                got < 0L -> { unverifiable++; out.append("UNVERIFIABLE\t").append(rel).append('\t').append(size).append('\t').append(got).append('\n') }
                got != size -> { mismatch++; out.append("MISMATCH\t").append(rel).append("\t").append(size).append('\t').append(got).append('\n') }
                else -> { verified++; out.append("OK\t").append(rel).append('\t').append(size).append('\t').append(got).append('\n') }
            }
        }
        val hardFail = missing > 0 || mismatch > 0
        val state = when {
            hardFail -> "failed"
            unverifiable > 0 -> "partial"
            else -> "ok"
        }
        out.append("SUMMARY\ttotal=").append(expected.size).append("\tverified=").append(verified)
            .append("\tmissing=").append(missing).append("\tmismatch=").append(mismatch)
            .append("\tunverifiable=").append(unverifiable)
            .append("\tstate=").append(state).append("\tlistHttp=").append(listCode).append('\n')
        return (if (hardFail) 409 else if (unverifiable > 0) 206 else 200) to out.toString()
    }

    private fun propfindRaw(user: String, pass: String, url: String, depth: Int): Pair<Int, ByteArray> {
        return pacedPair(DavOperation.PROPFIND, ByteArray(0)) {
            val bodyOut = ByteArrayOutputStream()
            val headers = linkedMapOf(
                "Depth" to if (depth < 0) "infinity" else depth.toString(),
                "Content-Type" to "application/xml; charset=utf-8",
                "Cache-Control" to "no-cache",
                "Pragma" to "no-cache",
                "Content-Length" to DAV_PROPFIND_BODY.size.toString()
            )
            val code = http.request("PROPFIND", url, user, pass, headers, bodyWriter = { out -> out.write(DAV_PROPFIND_BODY) }, followRedirects = true, canReplayBody = true) { status, respHeaders, input ->
                if (status in 200..299) HttpCore.readResponseBody(respHeaders, input, bodyOut) else HttpCore.discardErrorResponseBody(respHeaders, input)
            }
            code to bodyOut.toByteArray()
        }
    }

    // ---------------------------------------------------------------- XML/list ----

    private data class DavEntry(
        val href: String,
        val length: Long,
        val isDirectory: Boolean,
        val etag: String = "",
        val lastModified: String = "",
        val displayName: String = "",
        val status: Int = 200,
    )


    private fun classifyListRel(user: String, pass: String, baseUrl: String, relPath: String, depth: Int): Pair<Int, String> {
        // r612: once the full feature probe proved Depth: infinity is unavailable but a recursive Depth:1 walk is verified,
        // skip the known-failing infinity request and go straight to the bounded recursive walk.
        if (depth < 0) {
            val facts = featureFactsCache[featureFactsKey(baseUrl)]
            if (facts?.supportsDepthInfinity == false && facts.supportsDepth1 == true && facts.supportsRecursiveWalkFallback == true) {
                infoLog("WEBDAV_LIST_STRATEGY strategy=depth1-walk source=${facts.source} mode=r613")
                return classifyListRelParallelDepth1(user, pass, baseUrl, relPath, 200)
            }
        }
        val targetUrl = buildRelUrl(baseUrl, relPath)
        val (status, body) = propfindRaw(user, pass, targetUrl, depth)
        if (status in 200..299) {
            val baseRel = sanitizeRelPath(relPath).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
            return status to classifyDavEntries(parseDavEntries(body), baseRel)
        }
        if (depth < 0 && shouldFallbackDepth1Walk(status)) {
            cacheFeatureFacts(baseUrl, WebDavFeatureFacts(
                supportsDepthInfinity = false,
                supportsDepth1 = true,
                supportsRecursiveWalkFallback = true,
                source = "runtime-list-fallback-r612"
            ))
            return classifyListRelParallelDepth1(user, pass, baseUrl, relPath, status)
        }
        return status to ""
    }

    private fun shouldFallbackDepth1Walk(status: Int): Boolean = when (status) {
        403, 405, 501 -> true
        else -> false
    }

    private fun classifyDavEntries(entries: List<DavEntry>, baseRel: String): String {
        val out = StringBuilder(entries.size * 64)
        for (entry in entries) {
            val rel = davEntryRelativePath(entry.href, baseRel)
            appendClassifiedDavRel(out, rel, entry)
        }
        return out.toString()
    }

    private fun appendClassifiedDavRel(out: StringBuilder, relRaw: String, entry: DavEntry) {
        val rel = relRaw.replace('\\', '/').trim('/')
        if (rel.isEmpty() || rel == ".") return
        // r568: PROPFIND href/display data is remote-controlled. Never emit TAB/CR/LF or
        // other control chars into tools.sh TSV; skipping is safer than path mutation because
        // a mutated rel would later address the wrong remote object.
        if (!isSafeTsvPath(rel)) return
        val name = rel.substringAfterLast('/')
        val kind = classifyDavRel(rel, entry.isDirectory)
        out.append(kind).append('\t')
            .append(rel).append('\t')
            .append(entry.length).append('\t')
            .append(sanitizeTsv(entry.lastModified)).append('\t')
            .append(sanitizeTsv(name)).append('\n')
    }

    private data class ParallelClassifyResult(val topRel: String, val status: Int, val body: String, val visitedDirs: Int)

    private fun classifyListRelParallelDepth1(user: String, pass: String, baseUrl: String, relPath: String, originalStatus: Int): Pair<Int, String> {
        val rootRel = sanitizeRelPath(relPath).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val startedMs = System.currentTimeMillis()
        val rootRequestUrl = buildRelUrl(baseUrl, rootRel)
        val (rootStatus, rootBody) = propfindRaw(user, pass, rootRequestUrl, 1)
        if (rootStatus !in 200..299) return rootStatus to ""
        val rootEntries = parseDavEntries(rootBody)
        val out = StringBuilder(rootEntries.size * 64)
        val topDirs = ArrayList<String>()
        val seenRoot = HashSet<String>()
        for (entry in rootEntries) {
            val child = davEntryRelativePath(entry.href, rootRel).trim('/')
            if (child.isEmpty() || child == "." || child.contains('/')) continue
            if (!seenRoot.add(child)) continue
            appendClassifiedDavRel(out, child, entry)
            if (entry.isDirectory) topDirs.add(child)
        }
        if (topDirs.isEmpty()) {
            val elapsedMs = (System.currentTimeMillis() - startedMs).coerceAtLeast(0L)
            infoLog("WEBDAV_CLASSIFY_PARALLEL_DONE root=$rootRel workers=1 topDirs=0 visitedDirs=1 rows=${out.toString().lineSequence().count { it.isNotBlank() }} elapsedMs=$elapsedMs status=$rootStatus mode=r671")
            return rootStatus to out.toString()
        }

        val workers = minOf(4, topDirs.size).coerceAtLeast(1)
        val executor = Executors.newFixedThreadPool(workers)
        val futures = topDirs.map { topRel ->
            executor.submit<ParallelClassifyResult> {
                classifyDepth1Subtree(user, pass, baseUrl, rootRel, topRel)
            }
        }
        var finalStatus = rootStatus
        var visitedDirs = 1
        var failed = false
        try {
            for (future in futures) {
                val result = runCatching { future.get() }.getOrElse {
                    ParallelClassifyResult("", HttpCore.extractCode(it), "", 0)
                }
                visitedDirs += result.visitedDirs
                if (result.status !in 200..299) {
                    if (finalStatus in 200..299) finalStatus = result.status
                    failed = true
                } else {
                    out.append(result.body)
                }
            }
        } finally {
            executor.shutdownNow()
        }
        if (failed) {
            infoLog("WEBDAV_CLASSIFY_PARALLEL_FALLBACK root=$rootRel workers=$workers topDirs=${topDirs.size} status=$finalStatus action=serial-depth1 mode=r671")
            return classifyListRelDepth1WalkSerial(user, pass, baseUrl, relPath, originalStatus)
        }
        val elapsedMs = (System.currentTimeMillis() - startedMs).coerceAtLeast(0L)
        val rows = out.toString().lineSequence().count { it.isNotBlank() }
        infoLog("WEBDAV_CLASSIFY_PARALLEL_DONE root=$rootRel workers=$workers topDirs=${topDirs.size} visitedDirs=$visitedDirs rows=$rows elapsedMs=$elapsedMs status=$finalStatus mode=r671")
        return finalStatus to out.toString()
    }

    private fun classifyDepth1Subtree(user: String, pass: String, baseUrl: String, rootRel: String, topRel: String): ParallelClassifyResult {
        val pending = ArrayDeque<String>()
        val seenDirs = HashSet<String>()
        val seenEntries = HashSet<String>()
        val out = StringBuilder()
        pending.add(topRel.trim('/'))
        var httpStatus = 200
        var visited = 0
        val maxDirs = 20000
        while (!pending.isEmpty()) {
            val dirRel = pending.removeFirst().trim('/')
            if (!seenDirs.add(dirRel)) continue
            visited += 1
            if (visited > maxDirs) return ParallelClassifyResult(topRel, 508, "", visited)
            val requestRel = joinDavRel(rootRel, dirRel)
            val (status, body) = propfindRaw(user, pass, buildRelUrl(baseUrl, requestRel), 1)
            httpStatus = status
            if (status !in 200..299) return ParallelClassifyResult(topRel, status, "", visited)
            for (entry in parseDavEntries(body)) {
                val childUnderDir = davEntryRelativePath(entry.href, requestRel).trim('/')
                if (childUnderDir.isEmpty() || childUnderDir == ".") continue
                val finalRel = joinDavRel(dirRel, childUnderDir)
                if (finalRel.isEmpty() || !seenEntries.add(finalRel)) continue
                appendClassifiedDavRel(out, finalRel, entry)
                if (entry.isDirectory && finalRel !in seenDirs) pending.add(finalRel)
            }
        }
        return ParallelClassifyResult(topRel, httpStatus, out.toString(), visited)
    }

    private fun classifyListRelDepth1WalkSerial(user: String, pass: String, baseUrl: String, relPath: String, originalStatus: Int): Pair<Int, String> {
        val rootRel = sanitizeRelPath(relPath).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val pending = ArrayDeque<String>()
        val seenDirs = HashSet<String>()
        val seenEntries = HashSet<String>()
        val out = StringBuilder()
        pending.add("")
        var httpStatus = originalStatus
        var visited = 0
        val maxDirs = 20000
        while (!pending.isEmpty()) {
            val dirRel = pending.removeFirst().trim('/')
            if (!seenDirs.add(dirRel)) continue
            visited += 1
            if (visited > maxDirs) return 508 to ""
            val requestRel = joinDavRel(rootRel, dirRel)
            val requestUrl = buildRelUrl(baseUrl, requestRel)
            val (status, body) = propfindRaw(user, pass, requestUrl, 1)
            httpStatus = status
            if (status !in 200..299) return status to ""
            for (entry in parseDavEntries(body)) {
                val childUnderDir = davEntryRelativePath(entry.href, requestRel).trim('/')
                if (childUnderDir.isEmpty() || childUnderDir == ".") continue
                val finalRel = joinDavRel(dirRel, childUnderDir)
                if (finalRel.isEmpty() || !seenEntries.add(finalRel)) continue
                appendClassifiedDavRel(out, finalRel, entry)
                if (entry.isDirectory && finalRel !in seenDirs) pending.add(finalRel)
            }
        }
        return httpStatus to out.toString()
    }

    private fun directChildrenRel(user: String, pass: String, baseUrl: String, relPath: String): Pair<Int, String> {
        val rootRel = sanitizeRelPath(relPath).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val (status, body) = propfindRaw(user, pass, buildRelUrl(baseUrl, rootRel), 1)
        if (status !in 200..299) return status to ""
        val out = StringBuilder()
        val seen = HashSet<String>()
        for (entry in parseDavEntries(body)) {
            val rel = davEntryRelativePath(entry.href, rootRel).trim('/')
            if (rel.isEmpty() || rel == "." || rel.contains('/')) continue
            if (!isSafeRemoteItem(rel) || !seen.add(rel)) continue
            out.append(if (entry.isDirectory) 'D' else 'N').append(' ').append(rel).append('\n')
        }
        return status to out.toString()
    }

    private fun orphanRootsRel(user: String, pass: String, baseUrl: String, rootRelRaw: String): Pair<Int, String> {
        val rootRel = sanitizeRelPath(rootRelRaw).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val (status, body) = propfindRaw(user, pass, buildRelUrl(baseUrl, rootRel), 1)
        if (status !in 200..299) return status to ""
        val out = StringBuilder()
        val seen = HashSet<String>()
        for (entry in parseDavEntries(body)) {
            val name = davEntryRelativePath(entry.href, rootRel).trim('/')
            if (name.isEmpty() || name == "." || name.contains('/')) continue
            if (!isSafeRemoteItem(name) || !seen.add(name)) continue
            val fullRel = joinDavRel(rootRel, name)
            val kind = when {
                name == "app_details_bundle.tar.zst" || name == "app_details_bundle.tar" -> "BUNDLE"
                entry.isDirectory -> "DIR"
                else -> "FILE"
            }
            out.append(kind).append('\t').append(name).append('\t').append(fullRel).append('\n')
        }
        return status to out.toString()
    }

    private fun downloadManifestRel(user: String, pass: String, baseUrl: String, baseRelRaw: String, destDirRaw: String, itemBody: String): Pair<Int, String> {
        val baseRel = sanitizeRelPath(baseRelRaw).trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        val destDir = destDirRaw.trimEnd('/')
        require(destDir.isNotEmpty() && isSafeTsvPath(destDir)) { "unsafe destDir" }
        val out = StringBuilder()
        var status = 200
        var failed = false
        val seen = HashSet<String>()
        for (rawLine in itemBody.lineSequence()) {
            val item = rawLine.trim()
            if (item.isEmpty() || item.startsWith("#") || item.startsWith("＃")) continue
            if (!isSafeRemoteItem(item)) { failed = true; status = 400; continue }
            if (isMediaNetworkPayload(item)) {
                appendDownloadFile(out, seen, joinDavRel(baseRel, "Media/$item"), "$destDir/Media/$item")
                continue
            }
            val itemRel = joinDavRel(baseRel, item)
            val itemLocal = "$destDir/$item"
            val rc = appendDownloadTree(user, pass, baseUrl, itemRel, itemLocal, out, seen)
            if (rc !in 200..299) { failed = true; status = rc }
        }
        return (if (failed) status else 200) to out.toString()
    }

    private fun appendDownloadTree(
        user: String,
        pass: String,
        baseUrl: String,
        remoteRel: String,
        localDir: String,
        out: StringBuilder,
        seen: MutableSet<String>
    ): Int {
        val pending = ArrayDeque<Pair<String, String>>()
        val seenDirs = HashSet<String>()
        pending.add(remoteRel to localDir.trimEnd('/'))
        var visited = 0
        val maxDirs = 20000
        while (!pending.isEmpty()) {
            val (dirRel, dirLocal) = pending.removeFirst()
            if (!seenDirs.add(dirRel)) continue
            visited += 1
            if (visited > maxDirs) return 508
            val (status, body) = propfindRaw(user, pass, buildRelUrl(baseUrl, dirRel), 1)
            if (status !in 200..299) return status
            val baseName = dirRel.trim('/').substringAfterLast('/')
            for (entry in parseDavEntries(body)) {
                val child = davEntryRelativePath(entry.href, dirRel).trim('/')
                if (child.isEmpty() || child == ".") continue
                val name = child.substringAfterLast('/')
                if (name.isEmpty() || name == baseName || !isSafeRemoteItem(name)) continue
                val childRel = joinDavRel(dirRel, name)
                val childLocal = "$dirLocal/$name"
                if (entry.isDirectory) {
                    pending.add(childRel to childLocal)
                } else {
                    if (isLocalRebuildSidecar(name) || name == "app_details.json") continue
                    appendDownloadFile(out, seen, childRel, childLocal)
                }
            }
        }
        return 200
    }

    private fun appendDownloadFile(out: StringBuilder, seen: MutableSet<String>, relRaw: String, localRaw: String) {
        val rel = sanitizeRelPath(relRaw)
        val local = localRaw.trimEnd('/')
        if (!isSafeTsvPath(rel) || !isSafeTsvPath(local)) return
        val key = "$rel\t$local"
        if (!seen.add(key)) return
        out.append(rel).append('\t').append(local).append('\n')
    }

    private fun isLocalRebuildSidecar(name: String): Boolean = when (name) {
        "backup.sh", "recover.sh", "upload.sh" -> true
        else -> false
    }

    private fun isMediaNetworkPayload(name: String): Boolean {
        if (name.contains('/')) return false
        if (isAppMetadataName(name) || isReservedAppPayloadName(name)) return false
        return name.endsWith(".tar", ignoreCase = true) || name.endsWith(".tar.zst", ignoreCase = true)
    }

    private fun isSafeRemoteItem(value: String): Boolean {
        if (value.isEmpty() || value == "." || value == "..") return false
        if (value.startsWith('/') || value.contains("../") || value.startsWith("../")) return false
        if (!isSafeTsvPath(value)) return false
        for (ch in value) {
            when (ch) {
                '"', ';', '!', '`', '|', '<', '>' -> return false
            }
        }
        return true
    }

    private fun joinDavRel(left: String, right: String): String {
        val l = left.replace('\\', '/').trim('/')
        val r = right.replace('\\', '/').trim('/')
        return when {
            l.isEmpty() -> r
            r.isEmpty() -> l
            else -> "$l/$r"
        }
    }

    private fun davEntryRelativePath(href: String, baseRelRaw: String): String {
        var rel = href.substringBefore('?').substringBefore('#').trim()
        if (rel.startsWith("http://", ignoreCase = true) || rel.startsWith("https://", ignoreCase = true)) {
            rel = runCatching { URL(rel).path }.getOrElse { rel }
        }
        rel = HttpCore.percentDecodePath(rel)
        rel = rel.replace('\\', '/').trimStart('/')
        rel = rel.trimEnd('/')
        val baseRel = baseRelRaw.replace('\\', '/').trim('/').takeIf { it.isNotEmpty() && it != "." }.orEmpty()
        if (baseRel.isEmpty()) return rel
        if (rel == baseRel) return ""
        if (rel.startsWith("$baseRel/")) return rel.substring(baseRel.length + 1)
        val marker = "/$baseRel/"
        val idx = rel.indexOf(marker)
        if (idx >= 0) return rel.substring(idx + marker.length)
        val tailIdx = rel.lastIndexOf(baseRel)
        if (tailIdx >= 0) {
            val candidate = rel.substring(tailIdx + baseRel.length).trimStart('/')
            if (candidate.isNotEmpty()) return candidate
            // r517: Depth:1 walk receives the directory itself in many PROPFIND responses.
            // When the href ends exactly at baseRel (possibly with a server-side prefix), treat it as self.
            return ""
        }
        return rel
    }

    private fun classifyDavRel(rel: String, isDirectory: Boolean): String {
        if (isDirectory) return "DIR"
        val name = rel.substringAfterLast('/')
        val firstLevel = !rel.contains('/')
        val underMedia = rel.startsWith("Media/") && rel.count { it == '/' } == 1
        if (isInternalMarkerName(name)) return "INTERNAL_MARKER"
        if (isAppMetadataName(name)) return "APP_METADATA"
        if (isReservedAppPayloadName(name)) return if (rel.contains('/')) "APP_PAYLOAD" else "RESERVED_SKIP"
        if ((firstLevel || underMedia) && isTarPayloadName(name)) return "MEDIA_PAYLOAD"
        if (name.endsWith(".json", ignoreCase = true)) return "JSON"
        return "FILE"
    }

    private fun isTarPayloadName(name: String): Boolean =
        name.endsWith(".tar", ignoreCase = true) || name.endsWith(".tar.zst", ignoreCase = true)

    private fun isAppMetadataName(name: String): Boolean = when (name) {
        "app_details_bundle.tar", "app_details_bundle.tar.zst", "app_details.tar", "app_details.tar.zst", "app_details.json" -> true
        else -> false
    }

    private fun isInternalMarkerName(name: String): Boolean = when (name) {
        ".speedbackup_root_ready", ".speedbackup_dir_ready", ".speedbackup_transport_ready" -> true
        else -> false
    }

    private fun isReservedAppPayloadName(name: String): Boolean = when (name) {
        "apk.tar", "apk.tar.zst", "data.tar", "data.tar.zst", "user.tar", "user.tar.zst",
        "user_de.tar", "user_de.tar.zst", "obb.tar", "obb.tar.zst", "hma.tar", "hma.tar.zst",
        "thanox.tar", "thanox.tar.zst" -> true
        else -> false
    }

    private fun sanitizeTsv(value: String): String = value.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ')

    private fun isSafeTsvPath(value: String): Boolean {
        if (value.isEmpty()) return true
        for (ch in value) {
            if (ch == '\t' || ch == '\r' || ch == '\n' || ch.code < 0x20 || ch.code == 0x7f) return false
        }
        return true
    }

    private fun parseDavList(body: ByteArray): String {
        val entries = parseDavEntries(body)
        val sb = StringBuilder()
        for (e in entries) {
            val href = e.href.replace('\\', '/')
            if (!isSafeTsvPath(href)) continue
            sb.append(href).append('\t').append(e.length).append('\t').append(if (e.isDirectory) "D" else "F").append('\n')
        }
        return sb.toString()
    }

    private fun parseDavEntries(body: ByteArray): List<DavEntry> {
        if (body.isEmpty()) return emptyList()
        val parsed = runCatching { parseDavEntriesDom(body) }.getOrElse { emptyList() }
        if (parsed.isNotEmpty()) return parsed
        return parseDavEntriesFallback(body)
    }

    private fun parseDavEntriesDom(body: ByteArray): List<DavEntry> {
        val entries = mutableListOf<DavEntry>()
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
            runCatching { setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }
            isExpandEntityReferences = false
        }
        val doc = factory.newDocumentBuilder().parse(ByteArrayInputStream(body))
        val responses = doc.getElementsByTagNameNS("*", "response")
        val responseList = if (responses.length > 0) responses else doc.getElementsByTagName("response")
        for (i in 0 until responseList.length) {
            val response = responseList.item(i) as? Element ?: continue
            val hrefRaw = response.firstDirectTextCompat("href") ?: response.firstTextCompat("href") ?: continue
            val href = normalizeDavHref(hrefRaw)
            val responseStatus = parseHttpStatusCode(response.firstDirectTextCompat("status"))

            var bestProp: Element? = null
            var bestStatus = responseStatus ?: 200
            for (propstat in response.directChildrenCompat("propstat")) {
                val code = parseHttpStatusCode(propstat.firstDirectTextCompat("status")) ?: responseStatus ?: 200
                if (code in 200..299) {
                    bestProp = propstat.directChildrenCompat("prop").firstOrNull()
                    bestStatus = code
                    break
                }
            }
            if (bestProp == null && responseStatus != null && responseStatus !in 200..299) continue
            val prop = bestProp ?: response.directChildrenCompat("prop").firstOrNull() ?: response
            val length = prop.firstTextCompat("getcontentlength")?.trim()?.toLongOrNull() ?: -1L
            val etag = prop.firstTextCompat("getetag")?.trim() ?: ""
            val lastModified = prop.firstTextCompat("getlastmodified")?.trim() ?: ""
            val displayName = prop.firstTextCompat("displayname")?.trim() ?: ""
            val isDir = prop.hasDescendantCompat("collection") || href.endsWith("/") || prop.firstTextCompat("resourcetype")?.contains("collection", ignoreCase = true) == true
            entries.add(DavEntry(href, length, isDir, etag, lastModified, displayName, bestStatus))
        }
        return entries
    }

    private fun parseDavEntriesFallback(body: ByteArray): List<DavEntry> {
        val bodyText = body.toString(StandardCharsets.UTF_8)
        val out = ArrayList<DavEntry>()
        val responseRe = Regex("<[^>]*response[^>]*>(.*?)</[^>]*response>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val blocks = responseRe.findAll(bodyText).map { it.groupValues[1] }.toList().ifEmpty { listOf(bodyText) }
        for (block in blocks) {
            val hrefRaw = firstXmlTagText(block, "href") ?: continue
            val status = parseHttpStatusCode(firstXmlTagText(block, "status")) ?: 200
            if (status !in 200..299) continue
            val href = normalizeDavHref(hrefRaw)
            val length = firstXmlTagText(block, "getcontentlength")?.trim()?.toLongOrNull() ?: -1L
            val etag = firstXmlTagText(block, "getetag")?.trim() ?: ""
            val modified = firstXmlTagText(block, "getlastmodified")?.trim() ?: ""
            val display = firstXmlTagText(block, "displayname")?.trim() ?: ""
            val isDir = href.endsWith("/") || Regex("<[^>]*collection[^>]*/?>", RegexOption.IGNORE_CASE).containsMatchIn(block)
            out.add(DavEntry(href, length, isDir, etag, modified, display, status))
        }
        return out
    }

    private fun firstXmlTagText(block: String, local: String): String? {
        val re = Regex("<([A-Za-z0-9_.-]+:)?" + Regex.escape(local) + "\\b[^>]*>(.*?)</([A-Za-z0-9_.-]+:)?" + Regex.escape(local) + ">", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        return re.find(block)?.groupValues?.getOrNull(2)
    }

    private fun parseHttpStatusCode(statusLine: String?): Int? {
        if (statusLine.isNullOrBlank()) return null
        return Regex("""HTTP/\S+\s+(\d{3})""").find(statusLine)?.groupValues?.getOrNull(1)?.toIntOrNull()
    }

    private fun normalizeDavHref(raw: String): String {
        val value = raw.trim()
        if (value.isEmpty()) return value
        val withoutQuery = value.substringBefore('?').substringBefore('#')
        val path = runCatching {
            val u = URL(withoutQuery)
            u.path.ifEmpty { "/" }
        }.getOrElse { withoutQuery }
        return HttpCore.percentDecodePath(path)
    }

    private fun Element.localNameCompat(): String = localName ?: nodeName.substringAfter(':')

    private fun Element.directChildrenCompat(local: String): List<Element> {
        val out = ArrayList<Element>()
        val nodes = childNodes
        for (i in 0 until nodes.length) {
            val e = nodes.item(i) as? Element ?: continue
            if (e.localNameCompat().equals(local, ignoreCase = true)) out.add(e)
        }
        return out
    }

    private fun Element.firstDirectTextCompat(local: String): String? = directChildrenCompat(local).firstOrNull()?.textContent

    private fun Element.firstTextCompat(local: String): String? {
        val nsList = getElementsByTagNameNS("*", local)
        if (nsList.length > 0) return nsList.item(0)?.textContent
        val all = getElementsByTagName("*")
        for (i in 0 until all.length) {
            val e = all.item(i) as? Element ?: continue
            if (e.localNameCompat().equals(local, ignoreCase = true)) return e.textContent
        }
        return null
    }

    private fun Element.hasDescendantCompat(local: String): Boolean {
        val nsList = getElementsByTagNameNS("*", local)
        if (nsList.length > 0) return true
        val all = getElementsByTagName("*")
        for (i in 0 until all.length) {
            val e = all.item(i) as? Element ?: continue
            if (e.localNameCompat().equals(local, ignoreCase = true)) return true
        }
        return false
    }

    private fun Map<String, List<String>>.firstHeaderCompat(name: String): String? = this[name.lowercase(java.util.Locale.US)]?.firstOrNull()

    // ---------------------------------------------------------------- util ----

    private fun InputStream.copyTo(out: OutputStream) {
        val buf = ByteArray(HttpCore.COPY_BUF_SIZE)
        while (true) {
            val n = read(buf)
            if (n <= 0) break
            out.write(buf, 0, n)
        }
    }

    private fun finish(code: Int) {
        println("HTTP $code")
        exitProcess(if (code in 200..299) 0 else 1)
    }

    private fun readRequestBody(input: InputStream, length: Long): ByteArray {
        if (length < 0L) {
            val out = ByteArrayOutputStream()
            input.copyTo(out)
            return out.toByteArray()
        }
        require(length <= MAX_DAEMON_BODY_BYTES) { "request body too large: $length > $MAX_DAEMON_BODY_BYTES" }
        val out = ByteArray(length.toInt())
        var offset = 0
        while (offset < out.size) {
            val n = input.read(out, offset, out.size - offset)
            if (n < 0) throw IOException("unexpected EOF: expected=${out.size} actual=$offset")
            offset += n
        }
        return out
    }

    private class LimitedInputStream(private val source: InputStream, private var remaining: Long) : InputStream() {
        override fun read(): Int {
            if (remaining <= 0) return -1
            val b = source.read()
            if (b >= 0) remaining--
            return b
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (remaining <= 0) return -1
            val want = minOf(length.toLong(), remaining).toInt()
            val n = source.read(buffer, offset, want)
            if (n > 0) remaining -= n.toLong()
            return n
        }
    }

    private fun printUsage() {
        println("WebDavUtil $VERSION commands:")
        println("  version")
        println("  rel-only capability: webdav.rel_only.v1; legacy URL aliases disabled")
        println("  stream diagnostics capability: webdav.stream_heartbeat_error_kind.dex.v1 / webdav.stream_stall_watchdog.dex.v1 / webdav.stream_stall_socket_abort.dex.v1")
        println("  mkdirrel <user> <pass> <baseUrl> <relPath>")
        println("  mkdirsrel <user> <pass> <baseUrl> <relPath>")
        println("  putrel <user> <pass> <baseUrl> <relPath> <localFile>")
        println("  putbatchrel <user> <pass> <baseUrl> <baseRel>  (stdin: rel\tlocalFile lines)")
        println("  putstdinmanagedrel <user> <pass> <baseUrl> <relPath> [auto|atomic|direct|direct-json|known-missing|direct-new-known-missing] [ensureParentMkdir|skipParentMkdir]")
        println("  putmanagedrel <user> <pass> <baseUrl> <relPath> <localFile> [auto|atomic|direct|direct-json|known-missing|direct-new-known-missing] [ensureParentMkdir|skipParentMkdir]")
        println("  managedbatchputrelwithparents <user> <pass> <baseUrl> [mode] [ensureParentMkdir|skipParentMkdir]  (stdin: rel<TAB>localFile; Dex prepares parents then managed PUTs files)")
        println("  managedlistclassifyrel <user> <pass> <baseUrl> <relPath> [depth]  (alias of classifylistrel; transport-owned classified facts)")
        println("  managed manifest capabilities: webdav.direct_children_manifest.dex.v1 / webdav.download_manifest.dex.v1 / webdav.orphan_roots_manifest.dex.v1")
        println("  directchildrenrel <user> <pass> <baseUrl> <relPath>  (safe one-level D/N names for tools remote menu)")
        println("  downloadmanifestrel <user> <pass> <baseUrl> <baseRel> <destDir>  (stdin: safe item lines; stdout: rel<TAB>localFile)")
        println("  orphanrootsrel <user> <pass> <baseUrl> <rootRel>  (stdout: BUNDLE/DIR/FILE<TAB>name<TAB>rel for remote orphan cleanup)")
        println("  managedproberel <user> <pass> <baseUrl> [relBase]")
        println("  compatProbeRel <user> <pass> <baseUrl> [testRel]")
        println("  ensurebaserel <user> <pass> <configuredBaseUrl>")
        println("  ensuredirrel <user> <pass> <baseUrl> <relPath>")
        println("  ensuredirsbatchrel <user> <pass> <baseUrl>  (stdin: rel lines)")
        println("  preparedirsplanrel <user> <pass> <baseUrl> <rootRel> [create|check] [progressFile]  (stdin: desired dir rel lines; TSV EXISTING/CREATED/FAIL/SUMMARY; optional progress TSV file)")
        println("  optionspreflightrel <user> <pass> <baseUrl> <relPath> <mode>")
        println("  quotarel <user> <pass> <baseUrl> <relPath>  (DAV quota-available-bytes / quota-used-bytes; advisory)")
        println("  verifyuploadmaprel <user> <pass> <baseUrl> <rootRel>  (stdin: rel<TAB>expectedBytes; one remote list + size join)")
        println("  r613 capabilities: webdav.put_verify_after_ambiguous.dex.v1 / webdav.put_405_ambiguous_stat.dex.v1 / webdav.direct_put_verify_before_cleanup.dex.v1")
        println("  r613 integrity capabilities: webdav.put_2xx_body_semantic_guard.dex.v1 / webdav.put_2xx_stat_verify.dex.v1 / webdav.cloudreve_identity.dex.v1")
        println("  r618 identity capability: webdav.sftpgo_identity.dex.v1")
        println("  r620 NAS identity capability: webdav.zspace_identity.dex.v1")
        println("  r622 extended NAS identity capability: webdav.nas_identity_extended.dex.v1")
        println("  r628 profile contract capability: webdav.profile_contract.dex.v1")
        println("  vendor quirks: webdav.vendor_quirks.v1 / webdav.vendor_auto_detect.v1")
        println("  WEBR5 consolidated: webdav.compat_probe.v1 / webdav.atomic_probe.v2 / webdav.pacer_retry_backoff.v1 / webdav.directory_cache.v1 / webdav.propfind_xml_tolerant.v2 / webdav.error_policy_table.v1 / webdav.regression_suite.v1 / webdav.deep_policy_table.dex.v1")
        println("  deleterel <user> <pass> <baseUrl> <relPath>")
        println("  moverel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]")
        println("  copyrel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]")
        println("  propfindrel <user> <pass> <baseUrl> <relPath> [depth]")
        println("  statrel <user> <pass> <baseUrl> <relPath>")
        println("  optionsrel <user> <pass> <baseUrl> <relPath>")
        println("  listrel <user> <pass> <baseUrl> <relPath> [depth]")
        println("  classifylistrel <user> <pass> <baseUrl> <relPath> [depth]  (TSV kind\trel\tsize\tmtime\tname)")
        println("  encodepath <text>")
        println("  decodepath <text>")
        println("  daemon <port> [idleTimeoutSec] [ownerPid]          (persistent mode, TCP loopback)")
        println("  daemonunix <socketPath> [idleTimeoutSec] [ownerPid] (persistent mode, AF_UNIX filesystem socket)")
    }

    private const val UNIX_PATH_MAX_BYTES = 100
    private const val UNIX_SOCKET_MODE = 0x180 // 0600
    private const val DAEMON_CHUNKED_BODY = -2L
}
