package com.xayah.dex

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.util.Locale
import kotlin.system.exitProcess

/**
 * Structured App-state CLI and persistent AF_UNIX daemon.
 *
 * Daemon request framing intentionally mirrors the established WebDavUtil/unixsock pattern:
 * six UTF-8 header lines followed by an optional body.
 *
 * Request:
 *   command\n
 *   userId\n
 *   format\n          (reserved; currently ndjson/json)
 *   extra\n           (reserved)
 *   protocolVersion\n
 *   bodyLength\n      (-1 = read until client half-close)
 *   body bytes
 *
 * Response:
 *   RESULT <numericCode> <symbolicName>\n
 *   bodyLength\n
 *   body bytes
 */
object AppStateUtil {
    private const val VERSION = "v1.3.35-ssaid-metadata-restore"
    private const val DEFAULT_IDLE_TIMEOUT_SEC = 1800L

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isEmpty()) {
            printUsage()
            exitProcess(2)
        }
        when (args[0]) {
            "version", "--version", "-v" -> {
                println("$VERSION dex=${HiddenApiUtil.VERSION}")
                exitProcess(0)
            }
            "help" -> {
                printUsage()
                exitProcess(0)
            }
            "daemonunix" -> {
                HiddenApiBypassBridge.installExemptionsOnce()
                cmdDaemonUnix(args)
            }
            else -> {
                HiddenApiBypassBridge.installExemptionsOnce()
                runOneShot(args)
            }
        }
    }

    private fun normalizeCommand(command: String?): String {
        val value = command?.trim()?.lowercase(Locale.ROOT) ?: return ""
        return when (value) {
            "snapshotappstatebatch" -> "snapshot"
            "foreground", "foregroundstate", "foregroundstatebatch", "processstatebatch" -> "foregroundstate"
            "foregroundrunning", "foregroundrunningbatch", "foregroundstaterunning", "foregroundstaterunningbatch" -> "foregroundrunning"
            "foregroundlist", "foregroundlistjson", "foregroundstatelist", "foregroundstatejson", "foregroundjson" -> "foregroundlist"
            "foregroundtop", "foregroundtopapp" -> "foregroundtop"
            "restoreappstatebatch" -> "restore"
            "verifyappstatebatch" -> "verify"
            else -> value
        }
    }

    private fun runOneShot(args: Array<String>) {
        val command = args[0]
        if (command == "capabilities") {
            val pretty = args.any { it == "--pretty" }
            val response = AppStateEngine.capabilities(pretty)
            print(response.body)
            exitProcess(response.processExitCode())
        }
        if (args.size < 2) {
            val response = AppStateEngine.dispatch(command, 0, "", "")
            print(response.body)
            exitProcess(2)
        }
        val userId = args[1].toIntOrNull()
        if (userId == null || userId < 0) {
            val response = AppStateEngine.dispatch(command, 0, "", "")
            print(response.body)
            exitProcess(2)
        }

        val normalized = normalizeCommand(command)
        val body = when (normalized) {
            "snapshot", "foregroundstate" -> packageBody(args, 2)
            "foregroundrunning", "foregroundtop", "foregroundlist" -> ""
            "restore", "verify" -> payloadBody(args, 2)
            "localize", "localizebatch" -> args.drop(2).joinToString(" ")
            "ping" -> ""
            else -> packageBody(args, 2)
        }
        val response = AppStateEngine.dispatch(normalized, userId, "ndjson", body)
        print(response.body)
        System.out.flush()
        exitProcess(response.processExitCode())
    }

    private fun packageBody(args: Array<String>, start: Int): String {
        val builder = StringBuilder()
        var readStdin = false
        for (i in start until args.size) {
            when (val token = args[i]) {
                "--stdin" -> readStdin = true
                "--pretty", "--format=ndjson", "--format=json" -> Unit
                else -> if (token.isNotBlank()) builder.append(token.trim()).append('\n')
            }
        }
        if (readStdin) builder.append(readAll(System.`in`).toString(StandardCharsets.UTF_8))
        return builder.toString()
    }

    private fun payloadBody(args: Array<String>, start: Int): String {
        var readStdin = false
        var file: File? = null
        for (i in start until args.size) {
            val token = args[i]
            when {
                token == "--stdin" -> readStdin = true
                token.startsWith("--file=") -> file = File(token.substringAfter("--file="))
                token.isNotBlank() && !token.startsWith("--") -> file = File(token)
            }
        }
        val payloadFile = file
        return when {
            readStdin -> readAll(System.`in`).toString(StandardCharsets.UTF_8)
            payloadFile?.isFile == true -> payloadFile.readText(Charsets.UTF_8)
            else -> ""
        }
    }

    private fun cmdDaemonUnix(args: Array<String>) {
        require(args.size >= 2) { "daemonunix <socketPath> [idleTimeoutSec] [ownerPid]" }
        val socketPath = args[1]
        val idleTimeoutSec = args.getOrNull(2)?.toLongOrNull() ?: DEFAULT_IDLE_TIMEOUT_SEC
        require(idleTimeoutSec > 0) { "idleTimeoutSec must be > 0" }
        val ownerPid = parseOwnerPid(args.getOrNull(3))
        try {
            // Initialize ActivityThread system Context and Binder services on the daemon
            // main thread before accepting worker requests. READY is emitted only after this succeeds.
            AppStateEngine.initializeRuntime()
        } catch (t: Throwable) {
            System.err.println("APPSTATE_DAEMON_INIT_FAILED reason=${t.javaClass.simpleName}")
            exitProcess(1)
        }
        DaemonBootstrap.runUnixDaemon(
            "APPSTATE",
            socketPath,
            idleTimeoutSec * 1000L,
            ownerPid ?: -1,
            "APPSTATE_DAEMON_READY_UNIX $socketPath",
            true
        ) { client ->
            client.use { handleConnection(it.inputStream, it.outputStream) }
        }
    }

    private fun parseOwnerPid(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        val pid = raw.toIntOrNull() ?: throw IllegalArgumentException("ownerPid must be numeric")
        require(pid > 1) { "ownerPid must be > 1" }
        require(DaemonBootstrap.readProcStarttime(pid) != null) { "ownerPid is not alive: $pid" }
        return pid
    }

    private fun handleConnection(input: InputStream, output: OutputStream) {
        val command = readUtf8Line(input)
        val userIdRaw = readUtf8Line(input)
        val format = readUtf8Line(input)
        val extra = readUtf8Line(input)
        val protocolRaw = readUtf8Line(input)
        val bodyLengthRaw = readUtf8Line(input)

        val response = try {
            val userId = userIdRaw.toIntOrNull()
            val protocol = protocolRaw.toIntOrNull()
                ?: throw IllegalArgumentException("invalid protocolVersion=$protocolRaw")
            val bodyLength = bodyLengthRaw.toLongOrNull()
                ?: throw IllegalArgumentException("invalid bodyLength=$bodyLengthRaw")
            when {
                protocol != AppStateEngine.DAEMON_PROTOCOL_VERSION -> AppStateEngine.protocolError(
                    AppStateEngine.ResultCode.BAD_REQUEST,
                    "unsupported protocolVersion=$protocol extra=$extra"
                )
                userId == null || userId < 0 -> AppStateEngine.protocolError(
                    AppStateEngine.ResultCode.BAD_REQUEST, "invalid userId=$userIdRaw"
                )
                bodyLength < -1L -> AppStateEngine.protocolError(
                    AppStateEngine.ResultCode.BAD_REQUEST, "invalid bodyLength=$bodyLength"
                )
                else -> {
                    val bodyBytes = if (bodyLength == -1L) readAll(input) else readExactly(input, bodyLength)
                    val body = bodyBytes.toString(StandardCharsets.UTF_8)
                    AppStateEngine.dispatch(command, userId, extra.ifBlank { format }, body)
                }
            }
        } catch (e: IllegalArgumentException) {
            AppStateEngine.protocolError(AppStateEngine.ResultCode.BAD_REQUEST, e.message ?: "bad request")
        } catch (e: SecurityException) {
            AppStateEngine.protocolError(AppStateEngine.ResultCode.PERMISSION_DENIED, e.message ?: "permission denied")
        } catch (e: Throwable) {
            AppStateEngine.protocolError(
                AppStateEngine.ResultCode.INTERNAL_ERROR,
                e.message ?: e.javaClass.simpleName
            )
        }

        val bodyBytes = response.body.toByteArray(StandardCharsets.UTF_8)
        output.write("RESULT ${response.resultCode.code} ${response.resultCode.name}\n".toByteArray(StandardCharsets.UTF_8))
        output.write("${bodyBytes.size}\n".toByteArray(StandardCharsets.UTF_8))
        output.write(bodyBytes)
        output.flush()
    }

    private fun readUtf8Line(input: InputStream): String {
        val buffer = ByteArrayOutputStream(128)
        while (true) {
            val b = input.read()
            if (b == -1 || b == '\n'.code) break
            if (b != '\r'.code) buffer.write(b)
        }
        return buffer.toByteArray().toString(StandardCharsets.UTF_8)
    }

    private fun readExactly(input: InputStream, length: Long): ByteArray {
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

    private fun readAll(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }

    private fun printUsage() {
        println("AppStateUtil commands:")
        println("  version")
        println("  capabilities [--pretty]")
        println("  localize USER_ID TYPE KEY")
        println("  snapshotAppStateBatch USER_ID PACKAGE...|--stdin")
        println("  foregroundStateBatch USER_ID PACKAGE...|--stdin")
        println("  foregroundStateRunning USER_ID")
        println("  foregroundListJson USER_ID")
        println("  foregroundTop USER_ID")
        println("  restoreAppStateBatch USER_ID --stdin|--file=SNAPSHOT_NDJSON")
        println("  verifyAppStateBatch USER_ID --stdin|--file=SNAPSHOT_NDJSON")
        println("  daemonunix SOCKET_PATH [idleTimeoutSec] [ownerPid]")
        println("Daemon protocol: six-line request header + body, two-line RESULT/bodyLength response header.")
    }
}
