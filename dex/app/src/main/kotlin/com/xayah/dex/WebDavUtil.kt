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
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.ConcurrentHashMap
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
    private const val VERSION = "v1.5.10-standard-webdav-no-hiddenapi dex=v2.6.81-ssaid-metadata-restore build=v24.20.14-7.66-439-ssaid-metadata-restore-20260723"

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

    private val http = HttpCore.Client(keepAlive = true)
    private val mkcolOkCache = ConcurrentHashMap<String, Boolean>()
    private val listOkCache = ConcurrentHashMap<ListCacheKey, String>()
    private val serverKindCache = ConcurrentHashMap<String, String>()
    private val managedUploadSeq = AtomicInteger(0)

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

    private data class ManagedDecision(val direct: Boolean, val modeName: String, val serverKind: String)

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
            "managedproberel" -> cmdManagedProbeRel(args)
            "compatProbeRel" -> cmdCompatProbeRel(args)
            "getrel" -> cmdGetRel(args)
            "getstdoutrel" -> cmdGetStdoutRel(args)
            "deleterel" -> cmdDeleteRel(args)
            "moverel" -> cmdMoveRel(args)
            "copyrel" -> cmdCopyRel(args)
            "propfindrel" -> cmdPropfindRel(args)
            "statrel" -> cmdStatRel(args)
            "optionsrel" -> cmdOptionsRel(args)
            "listrel" -> cmdListRel(args)
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

        fun extraParts(): List<String> = extra.split('\t')
        fun extra1(): String = extraParts().getOrElse(0) { "" }
        fun extra2(): String = extraParts().getOrElse(1) { "" }
        fun extra3(): String = extraParts().getOrElse(2) { "" }
        fun relUrl(): String = buildRelUrl(url, extra1())

        when (command) {
            "mkdirrel" -> httpCode = safe { mkcolCached(user, pass, relUrl()) }
            "putrel" -> {
                val file = File(extra2())
                httpCode = if (!file.isFile) 0 else safe {
                    FileInputStream(file).use { put(user, pass, relUrl(), it, file.length(), chunked = false).also { if (it in 200..299) invalidateListCache() } }
                }
            }
            "putbatchrel" -> {
                val body = readRequestBody(input, requestBodyLen).toString(StandardCharsets.UTF_8)
                httpCode = safe {
                    val result = putBatchRel(user, pass, url, extra1(), body)
                    respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "putstdinchunkedrel" -> httpCode = safe {
                put(user, pass, relUrl(), input, contentLength = null, chunked = true).also { if (it in 200..299) invalidateListCache() }
            }
            "putstdinmanagedrel" -> httpCode = safe {
                putStdinManagedRel(user, pass, url, extra1(), extra2(), input)
            }
            "putmanagedrel" -> httpCode = safe {
                putFileManagedRel(user, pass, url, extra1(), extra2(), extra3())
            }
            "managedproberel" -> httpCode = safe {
                managedProbeRel(user, pass, url, extra1())
            }
            "compatProbeRel" -> httpCode = safe {
                val result = compatProbeRel(user, pass, url, extra1())
                respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                result.first
            }
            "getrel" -> httpCode = safe {
                FileOutputStream(extra2()).use { out -> getTo(user, pass, relUrl(), out) }
            }
            "getstdoutrel" -> httpCode = safe {
                streamDaemonGet(user, pass, relUrl(), output) { chunkOutput ->
                    streamingResponseStarted = true
                    streamingChunkOutput = chunkOutput
                }
            }
            "deleterel" -> httpCode = safe { delete(user, pass, relUrl()).also { if (it in 200..299) invalidateListCache() } }
            "moverel" -> httpCode = safe { move(user, pass, buildRelUrl(url, extra1()), buildRelUrl(url, extra2()), overwrite = extra3().ifEmpty { "T" } != "F").also { if (it in 200..299) invalidateListCache() } }
            "copyrel" -> httpCode = safe { copy(user, pass, buildRelUrl(url, extra1()), buildRelUrl(url, extra2()), overwrite = extra3().ifEmpty { "T" } != "F").also { if (it in 200..299) invalidateListCache() } }
            "propfindrel" -> {
                val depth = extra2().toIntOrNull() ?: 0
                httpCode = safe { propfindRaw(user, pass, relUrl(), depth).first }
            }
            "statrel" -> {
                httpCode = safe {
                    val result = statDav(user, pass, relUrl())
                    if (result.first in 200..299 && result.second != null) respBody = formatDavStat(result.second!!).toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "optionsrel" -> {
                httpCode = safe {
                    val result = optionsDav(user, pass, relUrl())
                    if (result.first in 200..299) respBody = result.second.toByteArray(StandardCharsets.UTF_8)
                    result.first
                }
            }
            "listrel" -> {
                val depth = extra2().toIntOrNull() ?: -1
                httpCode = safe {
                    val result = listCached(user, pass, relUrl(), depth)
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
            System.err.println("[daemon] cmd=$command url=$url -> ${lastError!!.javaClass.name}: ${lastError!!.message}")
            lastError!!.printStackTrace(System.err)
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
            FileInputStream(file).use { put(args[1], args[2], buildRelUrl(args[3], args[4]), it, file.length(), chunked = false) }
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
        require(args.size >= 5) { "putstdinmanagedrel <user> <pass> <baseUrl> <relPath> [mode]" }
        val mode = args.getOrNull(5) ?: "auto"
        val code = runCatching {
            putStdinManagedRel(args[1], args[2], args[3], args[4], mode, System.`in`)
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdPutManagedRel(args: Array<String>) {
        require(args.size >= 6) { "putmanagedrel <user> <pass> <baseUrl> <relPath> <localFile> [mode]" }
        val mode = args.getOrNull(6) ?: "auto"
        val code = runCatching {
            putFileManagedRel(args[1], args[2], args[3], args[4], args[5], mode)
        }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
    }

    private fun cmdManagedProbeRel(args: Array<String>) {
        require(args.size >= 4) { "managedproberel <user> <pass> <baseUrl> [relBase]" }
        val relBase = args.getOrNull(4) ?: ""
        val code = runCatching { managedProbeRel(args[1], args[2], args[3], relBase) }.getOrElse { HttpCore.extractCode(it) }
        finish(code)
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
        val rel = relPath.trimStart('/')
        if (rel.isEmpty() || rel == ".") return base
        return "$base/$rel"
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
        return code == 0 || code == 408 || code == 423 || code == 425 || code == 429 || code in 500..599
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
                else DavPolicyDecision(false, retryable = false, normalizedCode = code, reason = "put-fail-no-body-replay")
            }
        }
    }

    private fun pacedCode(operation: DavOperation, maxAttempts: Int = 3, block: () -> Int): Int {
        var attempt = 0
        var lastCode = 0
        while (attempt < maxAttempts) {
            val code = runCatching { block() }.getOrElse { HttpCore.extractCode(it) }
            lastCode = code
            val decision = policyFor(operation, code)
            if (decision.ok || !decision.retryable || attempt + 1 >= maxAttempts) return code
            val sleepMs = (150L * (1L shl attempt)).coerceAtMost(1200L)
            runCatching { Thread.sleep(sleepMs) }
            attempt++
        }
        return lastCode
    }

    private fun <T> pacedPair(operation: DavOperation, empty: T, maxAttempts: Int = 3, block: () -> Pair<Int, T>): Pair<Int, T> {
        var attempt = 0
        var last: Pair<Int, T> = 0 to empty
        while (attempt < maxAttempts) {
            val result = runCatching { block() }.getOrElse { HttpCore.extractCode(it) to empty }
            last = result
            val decision = policyFor(operation, result.first)
            if (decision.ok || !decision.retryable || attempt + 1 >= maxAttempts) return result
            val sleepMs = (150L * (1L shl attempt)).coerceAtMost(1200L)
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
                val len = headers.firstHeaderCompat("content-length")?.toLongOrNull() ?: 0L
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
        val partRel = "$probeRoot/payload.txt.part"
        val finalRel = "$probeRoot/payload.txt"
        val copyRel = "$probeRoot/payload.copy.txt"
        val payload = "speedbackup_webdav_compat_probe:${System.currentTimeMillis()}:pid=${android.os.Process.myPid()}\n"
            .toByteArray(StandardCharsets.UTF_8)
        val steps = ArrayList<CompatProbeStep>()
        var allow = ""
        var dav = ""
        var server = ""
        var allowReliable = true
        var bodyMatches = false
        var finalStatOk = false
        var copyStatOk = false
        var cleanupOk = true
        var finalCode = 200

        fun add(name: String, code: Int, detail: String = ""): Boolean {
            val ok = code in 200..299
            steps.add(CompatProbeStep(name, code, ok, detail))
            if (!ok && finalCode in 200..299) finalCode = code
            return ok
        }

        fun cleanup() {
            val d1 = delete(user, pass, buildRelUrl(base, partRel))
            val d2 = delete(user, pass, buildRelUrl(base, finalRel))
            val d3 = delete(user, pass, buildRelUrl(base, copyRel))
            val d4 = delete(user, pass, buildRelUrl(base, "$probeRoot/payload.overwrite.part"))
            val d5 = delete(user, pass, buildRelUrl(base, probeRoot))
            cleanupOk = listOf(d1, d2, d3, d4, d5).all { it in 200..299 || it == 404 }
            val cleanupCode = if (cleanupOk) 204 else listOf(d1, d2, d3, d4, d5).firstOrNull { it !in 200..299 && it != 404 } ?: 0
            steps.add(CompatProbeStep("cleanup", cleanupCode, cleanupOk))
            if (!cleanupOk && finalCode in 200..299) finalCode = cleanupCode
        }

        try {
            val (optCode, optText) = optionsDav(user, pass, buildRelUrl(base, "."))
            if (optCode in 200..299) {
                val opt = parseCompatKeyValue(optText)
                allow = opt["allow"].orEmpty()
                dav = opt["dav"].orEmpty()
                server = opt["server"].orEmpty()
                val required = listOf("OPTIONS", "PROPFIND", "PUT", "GET", "DELETE", "MOVE")
                allowReliable = allow.isBlank() || required.all { allowHasMethod(allow, it) }
            }
            if (add("optionsrel", optCode, if (allowReliable) "" else "allow-incomplete")) {
                val mkdirCode = mkcolParentsRel(user, pass, base, probeRoot)
                if (add("mkdirsrel", mkdirCode)) {
                    delete(user, pass, buildRelUrl(base, partRel))
                    delete(user, pass, buildRelUrl(base, finalRel))
                    delete(user, pass, buildRelUrl(base, copyRel))

                    val putCode = put(user, pass, buildRelUrl(base, partRel), ByteArrayInputStream(payload), contentLength = null, chunked = true)
                    if (add("putstdinchunkedrel", putCode)) {
                        val moveCode = move(user, pass, buildRelUrl(base, partRel), buildRelUrl(base, finalRel), overwrite = true)
                        if (add("moverel", moveCode)) {
                            val (statCode, statEntry) = statDav(user, pass, buildRelUrl(base, finalRel))
                            finalStatOk = statCode in 200..299 && statEntry != null && !statEntry.isDirectory
                            steps.add(CompatProbeStep("statrel", statCode, finalStatOk, if (statEntry != null) "len=${statEntry.length}" else ""))
                            if (!finalStatOk && finalCode in 200..299) finalCode = statCode
                            if (finalStatOk) {
                                val got = ByteArrayOutputStream()
                                val getCode = getTo(user, pass, buildRelUrl(base, finalRel), got)
                                bodyMatches = getCode in 200..299 && payload.contentEquals(got.toByteArray())
                                steps.add(CompatProbeStep("getstdoutrel", getCode, bodyMatches, "expected=${payload.size};got=${got.size()}"))
                                if (!bodyMatches && finalCode in 200..299) finalCode = getCode
                                if (bodyMatches) {
                                    val copyCode = copy(user, pass, buildRelUrl(base, finalRel), buildRelUrl(base, copyRel), overwrite = true)
                                    if (add("copyrel", copyCode)) {
                                        val (copyStatCode, copyEntry) = statDav(user, pass, buildRelUrl(base, copyRel))
                                        copyStatOk = copyStatCode in 200..299 && copyEntry != null && !copyEntry.isDirectory
                                        steps.add(CompatProbeStep("statrel.copy", copyStatCode, copyStatOk, if (copyEntry != null) "len=${copyEntry.length}" else ""))
                                        if (!copyStatOk && finalCode in 200..299) finalCode = copyStatCode
                                    }
                                    val overwritePayload = payload + "overwrite-pass\n".toByteArray(StandardCharsets.UTF_8)
                                    val overwritePartRel = "$probeRoot/payload.overwrite.part"
                                    val overwritePutCode = put(user, pass, buildRelUrl(base, overwritePartRel), ByteArrayInputStream(overwritePayload), contentLength = null, chunked = true)
                                    if (add("putstdinchunkedrel.overwrite", overwritePutCode)) {
                                        val overwriteMoveCode = move(user, pass, buildRelUrl(base, overwritePartRel), buildRelUrl(base, finalRel), overwrite = true)
                                        val overwriteOk = overwriteMoveCode in 200..299
                                        steps.add(CompatProbeStep("moverel.overwrite", overwriteMoveCode, overwriteOk))
                                        if (!overwriteOk && finalCode in 200..299) finalCode = overwriteMoveCode
                                        if (overwriteOk) {
                                            val got2 = ByteArrayOutputStream()
                                            val get2Code = getTo(user, pass, buildRelUrl(base, finalRel), got2)
                                            val overwriteBodyOk = get2Code in 200..299 && overwritePayload.contentEquals(got2.toByteArray())
                                            steps.add(CompatProbeStep("getstdoutrel.overwrite", get2Code, overwriteBodyOk, "expected=${overwritePayload.size};got=${got2.size()}"))
                                            if (!overwriteBodyOk && finalCode in 200..299) finalCode = get2Code
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            val code = HttpCore.extractCode(e)
            steps.add(CompatProbeStep("exception", code, false, "${e.javaClass.simpleName}:${e.message ?: ""}"))
            if (finalCode in 200..299) finalCode = code
        } finally {
            cleanup()
        }

        val ok = finalCode in 200..299 && bodyMatches && finalStatOk && copyStatOk && cleanupOk &&
            stepOk(steps, "putstdinchunkedrel") && stepOk(steps, "moverel") && stepOk(steps, "copyrel")
        val quirks = detectWebDavQuirks(base, allow, dav, server, allowReliable, steps)
        return finishCompatProbe(steps, finalCode, ok, allowReliable, allow, dav, server, quirks, bodyMatches, finalStatOk, copyStatOk, cleanupOk, probeRoot)
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
        copyStatOk: Boolean,
        cleanupOk: Boolean,
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
            append("\"supportsMove\":").append(stepOk(steps, "moverel")).append(',')
            append("\"supportsCopy\":").append(stepOk(steps, "copyrel")).append(',')
            append("\"supportsGetStream\":").append(stepOk(steps, "getstdoutrel")).append(',')
            append("\"supportsStat\":").append(finalStatOk).append(',')
            append("\"supportsAtomicPublish\":").append(stepOk(steps, "putstdinchunkedrel") && stepOk(steps, "moverel") && finalStatOk).append(',')
            append("\"supportsOverwriteMove\":").append(stepOk(steps, "moverel.overwrite") && stepOk(steps, "getstdoutrel.overwrite")).append(',')
            append("\"supportsPacerRetryBackoff\":").append(quirks.pacerRetryBackoff).append(',')
            append("\"supportsDirectoryCache\":").append(quirks.directoryCache.isNotEmpty() && quirks.directoryCache != "none").append(',')
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
            val code = FileInputStream(file).use { put(user, pass, buildRelUrl(baseUrl, fullRel), it, file.length(), chunked = false) }
            if (code in 200..299) ok++ else fail++
            sb.append(rel).append('\t').append(code).append('\t').append(file.length()).append('\t')
                .append(if (code in 200..299) "OK" else "PUT_FAIL").append('\n')
        }
        if (ok > 0) invalidateListCache()
        sb.append("SUMMARY\t").append(if (fail == 0) 200 else 500).append('\t').append(total).append('\t')
            .append("ok=").append(ok).append(" fail=").append(fail).append('\n')
        return (if (fail == 0) 200 else 500) to sb.toString()
    }

    private fun put(user: String, pass: String, url: String, input: InputStream, contentLength: Long?, chunked: Boolean): Int {
        val headers = linkedMapOf("Content-Type" to "application/octet-stream")
        if (chunked || contentLength == null) headers["Transfer-Encoding"] = "chunked" else headers["Content-Length"] = contentLength.toString()
        return http.request("PUT", url, user, pass, headers, bodyWriter = { out ->
            if (chunked || contentLength == null) HttpCore.writeChunked(input, out) else input.copyTo(out)
        })
    }

    private fun serverKindCacheKey(baseUrl: String): String {
        val u = runCatching { URL(baseUrl.trimEnd('/')) }.getOrNull() ?: return baseUrl.trimEnd('/')
        val defaultPort = (u.protocol.equals("http", ignoreCase = true) && (u.port == -1 || u.port == 80)) ||
            (u.protocol.equals("https", ignoreCase = true) && (u.port == -1 || u.port == 443))
        val portPart = if (defaultPort) "" else ":${u.port}"
        return "${u.protocol.lowercase(java.util.Locale.US)}://${u.host.lowercase(java.util.Locale.US)}$portPart"
    }

    private fun detectServerKind(user: String, pass: String, baseUrl: String): String {
        val key = serverKindCacheKey(baseUrl)
        serverKindCache[key]?.let { return it }
        val host = baseHostLower(baseUrl)
        if (host.contains("123pan") || host.contains("123pan.cn")) {
            serverKindCache[key] = "123pan"
            return "123pan"
        }
        if (host.contains("jianguoyun") || host.contains("nutstore")) {
            serverKindCache[key] = "jianguoyun"
            return "jianguoyun"
        }
        val (code, body) = optionsDav(user, pass, buildRelUrl(baseUrl, ""))
        val server = body.lineSequence()
            .firstOrNull { it.startsWith("server=", ignoreCase = true) }
            ?.substringAfter("=", "")
            ?.trim()
            ?: ""
        val lowerServer = server.lowercase(java.util.Locale.US)
        val kind = when {
            code in 200..299 && lowerServer.contains("rclone") -> "rclone"
            code in 200..299 && lowerServer.contains("123pan") -> "123pan"
            code in 200..299 && (lowerServer.contains("jianguoyun") || lowerServer.contains("nutstore")) -> "jianguoyun"
            else -> "generic"
        }
        if (code in 200..299) serverKindCache[key] = kind
        return kind
    }

    private fun isAppDetailsJson(relPath: String): Boolean {
        return relPath.trimEnd('/').substringAfterLast('/') == "app_details.json"
    }

    private fun managedDecision(user: String, pass: String, baseUrl: String, relPath: String, modeRaw: String?): ManagedDecision {
        val mode = (modeRaw ?: "auto").trim().lowercase(java.util.Locale.US).ifEmpty { "auto" }
        if (mode == "direct") return ManagedDecision(true, "direct_forced", "not_checked")
        if (mode == "atomic") return ManagedDecision(false, "atomic_forced", "not_checked")
        val kind = detectServerKind(user, pass, baseUrl)
        val direct = when (mode) {
            "direct-json" -> isAppDetailsJson(relPath)
            "direct-new-known-missing" -> kind == "rclone" || kind == "123pan"
            // rclone serve webdav 對任何 .part -> MOVE 都可能在 PC 終端印
            // "Failed to stat node: file does not exist"。123pan 官方 WebDAV 在 app_details
            // .part -> MOVE 覆蓋時已觀察到 HTTP 500。auto 模式下這兩類全部 direct PUT，
            // 避免 shell 層維護後端特例；其他 generic/Nextcloud 類仍走 atomic。
            "auto" -> kind == "rclone" || kind == "123pan"
            else -> false
        }
        val modeName = when {
            direct && mode == "direct-json" -> "direct_json"
            direct && mode == "direct-new-known-missing" -> "direct_new_known_missing"
            direct && mode == "auto" && kind == "rclone" && isAppDetailsJson(relPath) -> "rclone_direct_json"
            direct && mode == "auto" && kind == "rclone" -> "rclone_direct_all"
            direct && mode == "auto" && kind == "123pan" && isAppDetailsJson(relPath) -> "pan123_direct_json"
            direct && mode == "auto" && kind == "123pan" -> "pan123_direct_all"
            direct -> "direct"
            else -> "atomic"
        }
        return ManagedDecision(direct, modeName, kind)
    }

    private fun managedPartRel(relPath: String): String {
        val rel = relPath.trimStart('/')
        val seq = managedUploadSeq.incrementAndGet()
        return "$rel.part.${System.currentTimeMillis()}.$seq"
    }

    private fun putStdinManagedRel(user: String, pass: String, baseUrl: String, relPath: String, mode: String?, input: InputStream): Int {
        val decision = managedDecision(user, pass, baseUrl, relPath, mode)
        System.err.println("MANAGED_PUT mode=${decision.modeName} server=${decision.serverKind} rel=$relPath")
        val code = if (decision.direct) {
            put(user, pass, buildRelUrl(baseUrl, relPath), input, contentLength = null, chunked = true)
        } else {
            val partRel = managedPartRel(relPath)
            val putCode = put(user, pass, buildRelUrl(baseUrl, partRel), input, contentLength = null, chunked = true)
            if (putCode !in 200..299) {
                putCode
            } else {
                val moveCode = move(user, pass, buildRelUrl(baseUrl, partRel), buildRelUrl(baseUrl, relPath), overwrite = true)
                if (moveCode !in 200..299) runCatching { delete(user, pass, buildRelUrl(baseUrl, partRel)) }
                moveCode
            }
        }
        if (code in 200..299) invalidateListCache()
        return code
    }

    private fun putFileManagedRel(user: String, pass: String, baseUrl: String, relPath: String, localFile: String, mode: String?): Int {
        val file = File(localFile)
        if (!file.isFile) return 0
        val decision = managedDecision(user, pass, baseUrl, relPath, mode)
        System.err.println("MANAGED_PUT_FILE mode=${decision.modeName} server=${decision.serverKind} rel=$relPath file=${file.name} size=${file.length()}")
        val code = if (decision.direct) {
            FileInputStream(file).use { put(user, pass, buildRelUrl(baseUrl, relPath), it, file.length(), chunked = false) }
        } else {
            val partRel = managedPartRel(relPath)
            val putCode = FileInputStream(file).use { put(user, pass, buildRelUrl(baseUrl, partRel), it, file.length(), chunked = false) }
            if (putCode !in 200..299) {
                putCode
            } else {
                val moveCode = move(user, pass, buildRelUrl(baseUrl, partRel), buildRelUrl(baseUrl, relPath), overwrite = true)
                if (moveCode !in 200..299) runCatching { delete(user, pass, buildRelUrl(baseUrl, partRel)) }
                moveCode
            }
        }
        if (code in 200..299) invalidateListCache()
        return code
    }

    private fun managedProbeRel(user: String, pass: String, baseUrl: String, relBase: String): Int {
        val kind = detectServerKind(user, pass, baseUrl)
        if (kind == "rclone" || kind == "123pan") {
            System.err.println("MANAGED_PROBE mode=skip_direct_backend server=$kind reason=direct-put-managed-backend")
            return 200
        }
        val base = relBase.trim('/').takeIf { it.isNotEmpty() && it != "." } ?: ""
        val name = ".speedbackup_managed_probe.${System.currentTimeMillis()}.${managedUploadSeq.incrementAndGet()}"
        val partRel = if (base.isEmpty()) "$name.part" else "$base/$name.part"
        val finalRel = if (base.isEmpty()) name else "$base/$name"
        val bytes = "speedbackup_managed_probe".toByteArray(StandardCharsets.UTF_8)
        val putCode = put(user, pass, buildRelUrl(baseUrl, partRel), ByteArrayInputStream(bytes), bytes.size.toLong(), chunked = false)
        if (putCode !in 200..299) return putCode
        val moveCode = move(user, pass, buildRelUrl(baseUrl, partRel), buildRelUrl(baseUrl, finalRel), overwrite = true)
        if (moveCode !in 200..299) {
            runCatching { delete(user, pass, buildRelUrl(baseUrl, partRel)) }
            return moveCode
        }
        val (statCode, entry) = statDav(user, pass, buildRelUrl(baseUrl, finalRel))
        runCatching { delete(user, pass, buildRelUrl(baseUrl, finalRel)) }
        return if (statCode in 200..299 && entry != null) 200 else statCode
    }

    private fun getTo(user: String, pass: String, url: String, out: OutputStream): Int {
        return http.request("GET", url, user, pass, followRedirects = true, canReplayBody = true) { code, headers, input ->
            if (code in 200..299) HttpCore.readResponseBody(headers, input, out) else HttpCore.discardErrorResponseBody(headers, input)
        }
    }

    private fun delete(user: String, pass: String, url: String): Int {
        val raw = pacedCode(DavOperation.DELETE) {
            http.request("DELETE", url, user, pass, mapOf("Content-Length" to "0"), followRedirects = true, canReplayBody = true)
        }
        val decision = policyFor(DavOperation.DELETE, raw)
        if (decision.ok) {
            invalidateListCache()
            invalidateDirectoryCache()
        }
        return if (decision.ok) decision.normalizedCode else raw
    }

    private fun move(user: String, pass: String, srcUrl: String, dstUrl: String, overwrite: Boolean = true): Int {
        val headers = linkedMapOf(
            "Destination" to webDavDestinationHeader(dstUrl),
            "Overwrite" to if (overwrite) "T" else "F",
            "Content-Length" to "0"
        )
        val code = http.request("MOVE", srcUrl, user, pass, headers, followRedirects = true, canReplayBody = true)
        val decision = policyFor(DavOperation.MOVE, code)
        if (decision.ok) {
            invalidateListCache()
            invalidateDirectoryCache()
        }
        return if (decision.ok) decision.normalizedCode else code
    }

    private fun copy(user: String, pass: String, srcUrl: String, dstUrl: String, overwrite: Boolean = true): Int {
        val headers = linkedMapOf(
            "Destination" to webDavDestinationHeader(dstUrl),
            "Overwrite" to if (overwrite) "T" else "F",
            "Content-Length" to "0"
        )
        val code = http.request("COPY", srcUrl, user, pass, headers, followRedirects = true, canReplayBody = true)
        val decision = policyFor(DavOperation.COPY, code)
        if (decision.ok) {
            invalidateListCache()
            invalidateDirectoryCache()
        }
        return if (decision.ok) decision.normalizedCode else code
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

    private fun propfindRaw(user: String, pass: String, url: String, depth: Int): Pair<Int, ByteArray> {
        return pacedPair(DavOperation.PROPFIND, ByteArray(0)) {
            val bodyOut = ByteArrayOutputStream()
            val headers = linkedMapOf(
                "Depth" to if (depth < 0) "infinity" else depth.toString(),
                "Content-Type" to "application/xml; charset=utf-8",
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

    private fun parseDavList(body: ByteArray): String {
        val entries = parseDavEntries(body)
        val sb = StringBuilder()
        for (e in entries) {
            sb.append(e.href).append('\t').append(e.length).append('\t').append(if (e.isDirectory) "D" else "F").append('\n')
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
            val length = prop.firstTextCompat("getcontentlength")?.trim()?.toLongOrNull() ?: 0L
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
            val length = firstXmlTagText(block, "getcontentlength")?.trim()?.toLongOrNull() ?: 0L
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
        require(length <= Int.MAX_VALUE.toLong()) { "request body too large" }
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
        println("  mkdirrel <user> <pass> <baseUrl> <relPath>")
        println("  mkdirsrel <user> <pass> <baseUrl> <relPath>")
        println("  putrel <user> <pass> <baseUrl> <relPath> <localFile>")
        println("  putbatchrel <user> <pass> <baseUrl> <baseRel>  (stdin: rel\tlocalFile lines)")
        println("  putstdinmanagedrel <user> <pass> <baseUrl> <relPath> [auto|atomic|direct|direct-json|direct-new-known-missing]")
        println("  putmanagedrel <user> <pass> <baseUrl> <relPath> <localFile> [auto|atomic|direct|direct-json|direct-new-known-missing]")
        println("  managedproberel <user> <pass> <baseUrl> [relBase]")
        println("  compatProbeRel <user> <pass> <baseUrl> [testRel]")
        println("  vendor quirks: webdav.vendor_quirks.v1 / webdav.vendor_auto_detect.v1")
        println("  WEBR5 consolidated: webdav.compat_probe.v1 / webdav.atomic_probe.v2 / webdav.pacer_retry_backoff.v1 / webdav.directory_cache.v1 / webdav.propfind_xml_tolerant.v2 / webdav.error_policy_table.v1 / webdav.regression_suite.v1")
        println("  deleterel <user> <pass> <baseUrl> <relPath>")
        println("  moverel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]")
        println("  copyrel <user> <pass> <baseUrl> <srcRel> <dstRel> [overwrite T|F]")
        println("  propfindrel <user> <pass> <baseUrl> <relPath> [depth]")
        println("  statrel <user> <pass> <baseUrl> <relPath>")
        println("  optionsrel <user> <pass> <baseUrl> <relPath>")
        println("  listrel <user> <pass> <baseUrl> <relPath> [depth]")
        println("  encodepath <text>")
        println("  decodepath <text>")
        println("  daemon <port> [idleTimeoutSec] [ownerPid]          (persistent mode, TCP loopback)")
        println("  daemonunix <socketPath> [idleTimeoutSec] [ownerPid] (persistent mode, AF_UNIX filesystem socket)")
    }

    private const val UNIX_PATH_MAX_BYTES = 100
    private const val UNIX_SOCKET_MODE = 0x180 // 0600
    private const val DAEMON_CHUNKED_BODY = -2L
}
