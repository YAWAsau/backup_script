package com.xayah.dex

import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.IOException
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Shared low-level HTTP/HTTPS client for SpeedBackup dex utilities.
 *
 * This is intentionally dependency-free and uses only Java/Android platform APIs.
 * WebDavUtil uses it for WebDAV methods/daemon keep-alive; HttpUtil uses it for
 * normal HTTP downloads/update checks with redirect + gzip handling.
 */
object HttpCore {
    const val CONNECT_TIMEOUT_MS: Int = 30_000
    const val LONG_TRANSFER_TIMEOUT_MS: Int = 45_000
    val COPY_BUF_SIZE: Int = autoCopyBufferSize()

    private fun autoCopyBufferSize(): Int {
        val maxMem = Runtime.getRuntime().maxMemory()
        return when {
            maxMem >= 256L * 1024L * 1024L -> 1024 * 1024
            maxMem >= 128L * 1024L * 1024L -> 512 * 1024
            else -> 256 * 1024
        }
    }

    private val authCache = ConcurrentHashMap<String, String>()

    enum class PathMode { ENCODED, RAW_UTF8 }

    data class Target(val rawUrl: String, val pathMode: PathMode = PathMode.ENCODED) {
        val urlObj: URL = URL(rawUrl)
        val scheme: String = urlObj.protocol.lowercase(Locale.US)
        val host: String = urlObj.host
        val port: Int = if (urlObj.port > 0) urlObj.port else if (scheme == "https") 443 else 80
        val requestTarget: String = buildRequestTarget(urlObj, pathMode)
        val requestCharset: java.nio.charset.Charset = if (pathMode == PathMode.RAW_UTF8) StandardCharsets.UTF_8 else StandardCharsets.ISO_8859_1
        val hostHeader: String = run {
            val defaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            val h = if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
            if (defaultPort) h else "$h:$port"
        }
        val connKey: ConnKey = ConnKey(scheme, host, port)
        init {
            require(scheme == "http" || scheme == "https") { "unsupported scheme: $scheme" }
        }
    }

    private fun buildRequestTarget(urlObj: URL, mode: PathMode): String {
        val rawPath = urlObj.path.takeIf { it.isNotEmpty() } ?: "/"
        val requestPath = when (mode) {
            PathMode.ENCODED -> percentEncodePathPreservingEscapes(rawPath)
            // Some lightweight WebDAV servers on Windows/NAS accept raw UTF-8 request targets
            // but return 404 for RFC-style percent-encoded CJK base paths. Keep existing %HH
            // escapes from tools.sh and only send the unescaped Unicode base path as UTF-8 bytes.
            PathMode.RAW_UTF8 -> rawPath
        }
        val rawQuery = urlObj.query
        val requestQuery = if (rawQuery.isNullOrEmpty()) null else when (mode) {
            PathMode.ENCODED -> percentEncodeQueryPreservingEscapes(rawQuery)
            PathMode.RAW_UTF8 -> rawQuery
        }
        return if (requestQuery.isNullOrEmpty()) requestPath else "$requestPath?$requestQuery"
    }

    /**
     * Encode URL path for the actual HTTP request line.
     *
     * Preserve existing %HH escapes because tools.sh already encodes the relative WebDAV
     * backup path. This avoids double-encoding Backup_zstd_0/Android%E5... while still
     * fixing unencoded remote_url base paths on standards-compliant WebDAV servers.
     */
    fun percentEncodePathPreservingEscapes(s: String): String {
        val sb = StringBuilder(s.length * 3)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%' && i + 2 < s.length && Character.digit(s[i + 1], 16) >= 0 && Character.digit(s[i + 2], 16) >= 0) {
                sb.append('%').append(s[i + 1]).append(s[i + 2])
                i += 3
                continue
            }
            val code = c.code
            val keepAscii = (code in 0x30..0x39) || (code in 0x41..0x5a) || (code in 0x61..0x7a) ||
                c == '-' || c == '_' || c == '.' || c == '~' || c == '/'
            if (keepAscii) {
                sb.append(c)
            } else {
                val bytes = c.toString().toByteArray(StandardCharsets.UTF_8)
                for (bb in bytes) sb.append('%').append(((bb.toInt() and 0xff).toString(16).uppercase(Locale.US)).padStart(2, '0'))
            }
            i++
        }
        return sb.toString()
    }

    private fun percentEncodeQueryPreservingEscapes(s: String): String {
        val sb = StringBuilder(s.length * 3)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%' && i + 2 < s.length && Character.digit(s[i + 1], 16) >= 0 && Character.digit(s[i + 2], 16) >= 0) {
                sb.append('%').append(s[i + 1]).append(s[i + 2])
                i += 3
                continue
            }
            val code = c.code
            val keepAscii = (code in 0x30..0x39) || (code in 0x41..0x5a) || (code in 0x61..0x7a) ||
                c == '-' || c == '_' || c == '.' || c == '~' || c == '&' || c == '=' || c == '+' || c == ';' || c == ':' || c == '@' || c == ','
            if (keepAscii) {
                sb.append(c)
            } else {
                val bytes = c.toString().toByteArray(StandardCharsets.UTF_8)
                for (bb in bytes) sb.append('%').append(((bb.toInt() and 0xff).toString(16).uppercase(Locale.US)).padStart(2, '0'))
            }
            i++
        }
        return sb.toString()
    }

    data class ConnKey(val scheme: String, val host: String, val port: Int)

    class PooledConn(val key: ConnKey, val socket: Socket) {
        fun usable(): Boolean = socket.isConnected && !socket.isClosed && !socket.isInputShutdown && !socket.isOutputShutdown
    }

    data class ResponseHead(val code: Int, val message: String, val headers: Map<String, List<String>>, val keepAlive: Boolean)

    class Client(private val keepAlive: Boolean = true) {
        private val keepAlivePool = ConcurrentHashMap<ConnKey, PooledConn>()
        private val pathModeCache = ConcurrentHashMap<ConnKey, PathMode>()
        private val closing = AtomicBoolean(false)

        fun closeAll() {
            closing.set(true)
            val all = keepAlivePool.values.toList()
            keepAlivePool.clear()
            for (conn in all) runCatching { conn.socket.close() }
        }

        fun request(
            method: String,
            url: String,
            user: String = "",
            pass: String = "",
            headers: Map<String, String> = emptyMap(),
            bodyWriter: (OutputStream) -> Unit = {},
            followRedirects: Boolean = false,
            maxRedirects: Int = 5,
            canReplayBody: Boolean = false,
            retryOnConnectionFailure: () -> Boolean = { true },
            closeConnectionOnNon2xx: Boolean = false,
            responseConsumer: (Int, Map<String, List<String>>, InputStream) -> Unit = { code, respHeaders, input ->
                if (code in 200..299) discardResponseBody(respHeaders, input)
                else discardErrorResponseBody(respHeaders, input)
            }
        ): Int {
            var currentUrl = url
            var redirects = 0
            while (true) {
                val (code, location) = requestOnce(
                    method, currentUrl, user, pass, headers, bodyWriter,
                    retryOnConnectionFailure, closeConnectionOnNon2xx, responseConsumer
                )
                if (!followRedirects || code !in intArrayOf(301, 302, 303, 307, 308)) return code
                if (!canReplayBody && method !in setOf("GET", "HEAD")) return code
                if (redirects++ >= maxRedirects) return code
                val loc = location ?: return code
                currentUrl = URL(URL(currentUrl), loc).toString()
            }
        }

        private fun requestOnce(
            method: String,
            url: String,
            user: String,
            pass: String,
            headers: Map<String, String>,
            bodyWriter: (OutputStream) -> Unit,
            retryOnConnectionFailure: () -> Boolean,
            closeConnectionOnNon2xx: Boolean,
            responseConsumer: (Int, Map<String, List<String>>, InputStream) -> Unit
        ): Pair<Int, String?> {
            val seed = Target(url)
            val preferredMode = pathModeCache[seed.connKey] ?: PathMode.ENCODED
            val first = requestOnceWithMode(
                method, url, preferredMode, user, pass, headers, bodyWriter,
                retryOnConnectionFailure, closeConnectionOnNon2xx, responseConsumer
            )
            val code = first.first
            if (code != 404 || method == "PUT" || !urlHasNonAscii(url)) return first

            // Adaptive WebDAV base-path compatibility:
            // - standards-compliant servers expect percent-encoded request targets
            // - some NAS/Windows WebDAV stacks expect raw UTF-8 for CJK base paths
            // Retry 404 once with the opposite path mode for replay-safe methods and remember
            // the mode that succeeds for the same scheme/host/port. PUT is deliberately excluded
            // because a streaming body cannot be replayed safely.
            val altMode = if (preferredMode == PathMode.ENCODED) PathMode.RAW_UTF8 else PathMode.ENCODED
            val alt = requestOnceWithMode(
                method, url, altMode, user, pass, headers, bodyWriter,
                retryOnConnectionFailure, closeConnectionOnNon2xx, responseConsumer
            )
            if (alt.first in 200..299) {
                pathModeCache[seed.connKey] = altMode
                return alt
            }
            return first
        }

        private fun requestHasBody(method: String, headers: Map<String, String>): Boolean {
            if (method == "PUT" || method == "POST" || method == "PROPFIND") return true
            return headers.keys.any { it.equals("Content-Length", ignoreCase = true) || it.equals("Transfer-Encoding", ignoreCase = true) }
        }

        private fun guardedBodyWriter(conn: PooledConn, out: OutputStream, enabled: Boolean, bodyWriter: (OutputStream) -> Unit) {
            if (!enabled) {
                bodyWriter(out)
                return
            }
            val stop = AtomicBoolean(false)
            val lastProgress = AtomicLong(System.currentTimeMillis())
            val guard = Thread {
                while (!stop.get()) {
                    try {
                        Thread.sleep(1000)
                    } catch (_: InterruptedException) {
                        return@Thread
                    }
                    if (!stop.get() && System.currentTimeMillis() - lastProgress.get() > LONG_TRANSFER_TIMEOUT_MS) {
                        runCatching { conn.socket.close() }
                        return@Thread
                    }
                }
            }.apply { isDaemon = true; name = "SpeedBackup-WebDAV-write-idle-watchdog"; start() }

            val guarded = object : OutputStream() {
                override fun write(value: Int) {
                    lastProgress.set(System.currentTimeMillis())
                    out.write(value)
                    lastProgress.set(System.currentTimeMillis())
                }

                override fun write(buffer: ByteArray, offset: Int, length: Int) {
                    if (length <= 0) return
                    lastProgress.set(System.currentTimeMillis())
                    out.write(buffer, offset, length)
                    lastProgress.set(System.currentTimeMillis())
                }

                override fun flush() {
                    lastProgress.set(System.currentTimeMillis())
                    out.flush()
                    lastProgress.set(System.currentTimeMillis())
                }

                override fun close() {
                    flush()
                }
            }
            try {
                bodyWriter(guarded)
            } finally {
                stop.set(true)
                guard.interrupt()
            }
        }

        private fun requestOnceWithMode(
            method: String,
            url: String,
            pathMode: PathMode,
            user: String,
            pass: String,
            headers: Map<String, String>,
            bodyWriter: (OutputStream) -> Unit,
            retryOnConnectionFailure: () -> Boolean,
            closeConnectionOnNon2xx: Boolean,
            responseConsumer: (Int, Map<String, List<String>>, InputStream) -> Unit
        ): Pair<Int, String?> {
            val target = Target(url, pathMode)
            var attempt = 0
            while (true) {
                val conn = acquireConnection(target)
                try {
                    conn.socket.soTimeout = LONG_TRANSFER_TIMEOUT_MS
                    val input = conn.socket.getInputStream()
                    val output = conn.socket.getOutputStream()
                    writeRequestHead(output, method, target, user, pass, headers)
                    guardedBodyWriter(conn, output, requestHasBody(method, headers), bodyWriter)
                    output.flush()
                    val response = readResponseHead(input)
                    val location = response.headers.firstHeader("location")
                    try {
                        responseConsumer(response.code, response.headers, input)
                    } catch (_: NonFatalErrorBodyReadException) {
                        // The HTTP status line/headers were received successfully, but a non-2xx
                        // diagnostic body was truncated or malformed. Preserve the HTTP status,
                        // discard this connection from the keep-alive pool, and do not promote the
                        // optional error body to a transport failure. Successful 2xx bodies still
                        // use strict framing and therefore never reach this path.
                        closeConnection(conn)
                        return response.code to location
                    }
                    if (closeConnectionOnNon2xx && response.code !in 200..299) {
                        // Streaming daemon callers do not consume server-generated error bodies.
                        // An unread body makes this origin connection unsafe for keep-alive, so
                        // close it while preserving the already parsed HTTP status.
                        closeConnection(conn)
                    } else {
                        releaseConnection(conn, response)
                    }
                    return response.code to location
                } catch (e: Exception) {
                    closeConnection(conn)
                    // A cached keep-alive socket may have been closed by the server.
                    // Retry only when the request body is replay-safe.
                    if (retryOnConnectionFailure() && attempt == 0 && method != "PUT") {
                        attempt++
                        continue
                    }
                    throw e
                }
            }
        }

        private fun urlHasNonAscii(url: String): Boolean = url.any { it.code > 0x7f }

        fun getTo(url: String, out: OutputStream, user: String = "", pass: String = "", followRedirects: Boolean = true): Int {
            return request(
                method = "GET",
                url = url,
                user = user,
                pass = pass,
                headers = linkedMapOf("Accept-Encoding" to "gzip, deflate"),
                followRedirects = followRedirects,
                canReplayBody = true
            ) { code, headers, input ->
                if (code in 200..299) readResponseBody(headers, input, out, decodeContent = true) else discardResponseBody(headers, input)
            }
        }

        /**
         * Binary-safe streaming GET for the WebDAV daemon protocol.
         *
         * The callback is invoked immediately before the first response-body byte. A
         * non-negative length is supplied when the origin returned Content-Length; -1
         * means the body is framed by chunked transfer or connection EOF. Transport
         * retry is disabled because replaying after body bytes reached [out] would
         * duplicate/corrupt the downstream archive stream.
         */
        fun getToStreaming(
            url: String,
            user: String = "",
            pass: String = "",
            followRedirects: Boolean = true,
            onResponseHead: (code: Int, bodyLength: Long) -> OutputStream
        ): Int {
            // Do not expose a 2xx response head to the daemon until the first payload byte is
            // actually available. Some WebDAV servers briefly answer a just-deleted object with
            // stale 2xx headers and then close before sending any body. Because no downstream byte
            // has been emitted yet, requestOnceWithMode() may safely retry that GET once on a fresh
            // origin connection. If the retry resolves to 404, the daemon receives HTTP 404 rather
            // than a transport-level HTTP 0. Once even one payload byte is emitted, retry remains
            // disabled so an archive can never be duplicated/corrupted downstream.
            var successHeadSent = false
            val code = request(
                method = "GET",
                url = url,
                user = user,
                pass = pass,
                headers = linkedMapOf("Accept-Encoding" to "identity"),
                followRedirects = followRedirects,
                canReplayBody = true,
                retryOnConnectionFailure = { !successHeadSent },
                closeConnectionOnNon2xx = true
            ) { status, responseHeaders, input ->
                if (status in 200..299) {
                    val transferEncoding = responseHeaders.firstHeader("transfer-encoding")?.lowercase(Locale.US) ?: ""
                    val isChunked = transferEncoding.split(',').map { it.trim() }.contains("chunked")
                    val contentLength = responseHeaders.firstHeader("content-length")?.toLongOrNull()
                    val bodyLength = if (isChunked) -1L else contentLength ?: -1L
                    val connectionHeader = responseHeaders.firstHeader("connection") ?: ""
                    var responseOut: OutputStream? = null

                    fun ensureResponseOut(): OutputStream {
                        val existing = responseOut
                        if (existing != null) return existing
                        val created = onResponseHead(status, bodyLength)
                        responseOut = created
                        successHeadSent = true
                        return created
                    }

                    val lazyOut = object : OutputStream() {
                        override fun write(value: Int) {
                            ensureResponseOut().write(value)
                        }

                        override fun write(buffer: ByteArray, offset: Int, length: Int) {
                            if (length <= 0) return
                            ensureResponseOut().write(buffer, offset, length)
                        }

                        override fun flush() {
                            responseOut?.flush()
                        }
                    }

                    try {
                        readResponseBody(responseHeaders, input, lazyOut, decodeContent = false)
                        // Legitimate zero-length 2xx response: no write() occurred, so publish the
                        // successful head only after strict body framing completed successfully.
                        ensureResponseOut().flush()
                    } catch (e: IOException) {
                        throw IOException(
                            "streaming GET 2xx body failure status=$status " +
                                "contentLength=${contentLength ?: -1L} " +
                                "transferEncoding=${if (transferEncoding.isEmpty()) "identity" else transferEncoding} " +
                                "connection=${if (connectionHeader.isEmpty()) "unspecified" else connectionHeader} " +
                                "downstreamStarted=$successHeadSent: ${e.message}",
                            e
                        )
                    }
                } else {
                    // The daemon protocol only needs the HTTP status for non-success GETs.
                    // Do not read an optional server error page here. requestOnceWithMode()
                    // closes this origin connection before returning, so unread bytes can never
                    // contaminate the keep-alive pool.
                }
            }
            if (!successHeadSent) {
                successHeadSent = true
                onResponseHead(code, 0L).flush()
            }
            return code
        }

        private fun acquireConnection(target: Target): PooledConn {
            if (closing.get()) throw java.io.IOException("HttpCore client is closing")
            if (!keepAlive) return PooledConn(target.connKey, openSocket(target))
            while (true) {
                val cached = keepAlivePool.remove(target.connKey) ?: break
                if (cached.usable()) return cached
                closeConnection(cached)
            }
            return PooledConn(target.connKey, openSocket(target))
        }

        private fun releaseConnection(conn: PooledConn, response: ResponseHead) {
            if (closing.get() || !keepAlive || !response.keepAlive || !conn.usable()) {
                closeConnection(conn)
                return
            }
            val old = keepAlivePool.put(conn.key, conn)
            if (old != null && old !== conn) closeConnection(old)
        }

        private fun closeConnection(conn: PooledConn) {
            keepAlivePool.remove(conn.key, conn)
            runCatching { conn.socket.close() }
        }
    }

    fun authHeader(user: String, pass: String): String? {
        if (user.isEmpty()) return null
        return authCache.computeIfAbsent("$user:$pass") {
            val raw = "$user:$pass".toByteArray(StandardCharsets.UTF_8)
            "Basic " + Base64.getEncoder().encodeToString(raw)
        }
    }

    fun openSocket(target: Target): Socket {
        val raw = Socket()
        raw.connect(InetSocketAddress(target.host, target.port), CONNECT_TIMEOUT_MS)
        raw.soTimeout = LONG_TRANSFER_TIMEOUT_MS
        if (target.scheme != "https") return raw
        val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, target.host, target.port, true) as SSLSocket
        ssl.soTimeout = LONG_TRANSFER_TIMEOUT_MS
        ssl.startHandshake()
        if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(target.host, ssl.session)) {
            runCatching { ssl.close() }
            throw SSLHandshakeException("Hostname verification failed: ${target.host}")
        }
        return ssl
    }

    fun writeRequestHead(out: OutputStream, method: String, target: Target, user: String, pass: String, headers: Map<String, String>) {
        val sb = StringBuilder()
        sb.append(method).append(' ').append(target.requestTarget).append(" HTTP/1.1\r\n")
        sb.append("Host: ").append(target.hostHeader).append("\r\n")
        sb.append("User-Agent: SpeedBackup-DexHttpCore/Socket\r\n")
        sb.append("Accept: */*\r\n")
        sb.append("Connection: keep-alive\r\n")
        authHeader(user, pass)?.let { sb.append("Authorization: ").append(it).append("\r\n") }
        for ((k, v) in headers) sb.append(k).append(": ").append(v).append("\r\n")
        sb.append("\r\n")
        out.write(sb.toString().toByteArray(target.requestCharset))
    }

    fun readResponseHead(input: InputStream): ResponseHead {
        while (true) {
            val status = readHttpLine(input)
            if (status.isEmpty()) throw EOFException("empty HTTP response")
            val parts = status.split(" ", limit = 3)
            val code = parts.getOrNull(1)?.toIntOrNull() ?: 0
            val message = parts.getOrNull(2) ?: ""
            val headers = linkedMapOf<String, MutableList<String>>()
            while (true) {
                val line = readHttpLine(input)
                if (line.isEmpty()) break
                val idx = line.indexOf(':')
                if (idx <= 0) continue
                val name = line.substring(0, idx).trim().lowercase(Locale.US)
                val value = line.substring(idx + 1).trim()
                headers.getOrPut(name) { mutableListOf() }.add(value)
            }
            if (code in 100..199 && code != 101) continue
            val connection = headers["connection"]?.joinToString(",")?.lowercase(Locale.US) ?: ""
            val transferEncoding = headers["transfer-encoding"]?.joinToString(",")?.lowercase(Locale.US) ?: ""
            val hasKnownBodyLength = headers.containsKey("content-length") || transferEncoding.split(',').map { it.trim() }.contains("chunked")
            val bodylessStatus = code in 100..199 || code == 204 || code == 304
            val responseKeepAlive = !connection.split(',').map { it.trim() }.contains("close") && (hasKnownBodyLength || bodylessStatus)
            return ResponseHead(code, message, headers, responseKeepAlive)
        }
    }

    fun readHttpLine(input: InputStream): String {
        val out = ByteArrayOutputStream(128)
        while (true) {
            val b = input.read()
            if (b == -1) break
            if (b == '\n'.code) break
            if (b != '\r'.code) out.write(b)
        }
        return out.toString("ISO-8859-1")
    }

    fun writeChunked(input: InputStream, out: OutputStream) {
        val buf = ByteArray(COPY_BUF_SIZE)
        while (true) {
            val n = input.read(buf)
            if (n <= 0) break
            out.write(Integer.toHexString(n).toByteArray(StandardCharsets.ISO_8859_1))
            out.write("\r\n".toByteArray(StandardCharsets.ISO_8859_1))
            out.write(buf, 0, n)
            out.write("\r\n".toByteArray(StandardCharsets.ISO_8859_1))
        }
        out.write("0\r\n\r\n".toByteArray(StandardCharsets.ISO_8859_1))
    }

    fun readResponseBody(headers: Map<String, List<String>>, input: InputStream, out: OutputStream, decodeContent: Boolean = false) {
        val rawOut = if (decodeContent) ByteArrayOutputStream() else null
        val targetOut = rawOut ?: out
        val te = headers.firstHeader("transfer-encoding")?.lowercase(Locale.US) ?: ""
        val len = headers.firstHeader("content-length")?.toLongOrNull()
        when {
            te.split(',').map { it.trim() }.contains("chunked") -> readChunked(input, targetOut)
            len != null -> readFixed(input, len, targetOut)
            else -> input.copyToBuffer(targetOut)
        }
        if (decodeContent && rawOut != null) {
            val encoding = headers.firstHeader("content-encoding")?.lowercase(Locale.US) ?: ""
            val rawBytes = rawOut.toByteArray()
            when {
                encoding.contains("gzip") -> GZIPInputStream(rawBytes.inputStream()).use { it.copyToBuffer(out) }
                encoding.contains("deflate") -> InflaterInputStream(rawBytes.inputStream()).use { it.copyToBuffer(out) }
                else -> out.write(rawBytes)
            }
        }
    }

    fun discardResponseBody(headers: Map<String, List<String>>, input: InputStream) {
        if (!hasKnownBodyFraming(headers)) return
        readResponseBody(headers, input, NullOutputStream)
    }

    /**
     * Consume a non-success HTTP response body without allowing a broken diagnostic/error
     * payload to erase an already valid HTTP status code.
     *
     * A truncated/malformed non-2xx body makes the current socket unsafe for keep-alive, so
     * [requestOnceWithMode] catches this marker, closes that connection, and returns the
     * response status. This must never be used for 2xx payloads: successful archive/data
     * streams remain strictly length/chunk validated.
     */
    fun discardErrorResponseBody(headers: Map<String, List<String>>, input: InputStream) {
        try {
            discardResponseBody(headers, input)
        } catch (e: IOException) {
            throw NonFatalErrorBodyReadException(e)
        }
    }

    private class NonFatalErrorBodyReadException(cause: IOException) : IOException(cause)

    fun hasKnownBodyFraming(headers: Map<String, List<String>>): Boolean {
        val te = headers.firstHeader("transfer-encoding")?.lowercase(Locale.US) ?: ""
        return headers.firstHeader("content-length") != null || te.split(',').map { it.trim() }.contains("chunked")
    }

    fun readChunked(input: InputStream, out: OutputStream) {
        val buf = ByteArray(COPY_BUF_SIZE)
        while (true) {
            val sizeLine = readHttpLine(input)
            val sizeText = sizeLine.substringBefore(';').trim()
            val size = sizeText.toIntOrNull(16) ?: throw java.io.IOException("bad chunk size: $sizeLine")
            if (size == 0) {
                while (readHttpLine(input).isNotEmpty()) Unit
                return
            }
            var remaining = size
            while (remaining > 0) {
                val n = input.read(buf, 0, minOf(buf.size, remaining))
                if (n <= 0) throw EOFException("unexpected EOF in chunk")
                out.write(buf, 0, n)
                remaining -= n
            }
            readHttpLine(input)
        }
    }

    fun readFixed(input: InputStream, length: Long, out: OutputStream) {
        val buf = ByteArray(COPY_BUF_SIZE)
        var remaining = length
        while (remaining > 0) {
            val n = input.read(buf, 0, minOf(buf.size.toLong(), remaining).toInt())
            if (n <= 0) throw EOFException("unexpected EOF in fixed body")
            out.write(buf, 0, n)
            remaining -= n.toLong()
        }
    }

    fun InputStream.copyToBuffer(out: OutputStream) {
        val buf = ByteArray(COPY_BUF_SIZE)
        while (true) {
            val n = read(buf)
            if (n <= 0) break
            out.write(buf, 0, n)
        }
    }

    fun Map<String, List<String>>.firstHeader(name: String): String? = this[name.lowercase(Locale.US)]?.firstOrNull()

    object NullOutputStream : OutputStream() {
        override fun write(b: Int) = Unit
        override fun write(b: ByteArray, off: Int, len: Int) = Unit
    }

    fun percentEncodePath(s: String): String {
        val bytes = s.toByteArray(StandardCharsets.UTF_8)
        val sb = StringBuilder(bytes.size * 3)
        for (bb in bytes) {
            val b = bb.toInt() and 0xff
            val keep = (b in 0x30..0x39) || (b in 0x41..0x5a) || (b in 0x61..0x7a) || b == '-'.code || b == '_'.code || b == '.'.code || b == '~'.code || b == '/'.code
            if (keep) sb.append(b.toChar()) else sb.append('%').append(b.toString(16).uppercase(Locale.US).padStart(2, '0'))
        }
        return sb.toString()
    }

    fun percentDecodePath(s: String): String {
        val out = ByteArrayOutputStream(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%' && i + 2 < s.length) {
                val hi = Character.digit(s[i + 1], 16)
                val lo = Character.digit(s[i + 2], 16)
                if (hi >= 0 && lo >= 0) {
                    out.write((hi shl 4) + lo)
                    i += 3
                    continue
                }
            }
            val bytes = c.toString().toByteArray(StandardCharsets.UTF_8)
            out.write(bytes, 0, bytes.size)
            i++
        }
        return String(out.toByteArray(), StandardCharsets.UTF_8)
    }

    fun extractCode(e: Throwable): Int {
        if (e is java.io.FileNotFoundException) return 404
        val msg = e.message ?: return 0
        val m = Regex("""\b([1-5][0-9]{2})\b""").find(msg) ?: return 0
        return m.groupValues[1].toIntOrNull() ?: 0
    }
}
