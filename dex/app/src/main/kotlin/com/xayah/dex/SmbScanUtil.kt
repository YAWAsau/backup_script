package com.xayah.dex

import java.io.File
import java.io.IOException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.Collections
import java.util.concurrent.Callable
import java.util.concurrent.CompletionService
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.system.exitProcess

/**
 * Fast TCP pre-scan for SMB hosts.
 *
 * This deliberately does not implement SMB. It only checks whether SMB ports are reachable,
 * then tools.sh still uses smbclient for SMB2/SMB3 negotiation, auth, share listing and transfer.
 */
object SmbScanUtil {
    private data class HostRange(val start: Long, val end: Long)
    private data class ScanResult(val ip: String, val port: Int, val elapsedMs: Long)

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isEmpty() || args[0] == "help" || args[0] == "--help" || args[0] == "-h") {
            printUsage()
            exitProcess(if (args.isEmpty()) 2 else 0)
        }
        when (args[0]) {
            "scanSmb" -> cmdScanSmb(args)
            else -> {
                printUsage()
                exitProcess(2)
            }
        }
    }

    private fun cmdScanSmb(args: Array<String>) {
        val cidrArg = args.getOrNull(1) ?: "auto"
        val timeoutMs = clampInt(args.getOrNull(2)?.toIntOrNull() ?: 800, 80, 5000)
        val concurrency = clampInt(args.getOrNull(3)?.toIntOrNull() ?: 192, 1, 1024)
        val firstOnly = when ((args.getOrNull(4) ?: "0").lowercase()) {
            "1", "true", "yes", "y" -> true
            else -> false
        }
        val ports = parsePorts(args.getOrNull(5) ?: "445,139")
        if (ports.isEmpty()) {
            System.err.println("bad ports")
            exitProcess(2)
        }

        val cidr = if (cidrArg == "auto") autoCidr24() else cidrArg
        if (cidr == null) {
            System.err.println("cannot detect local IPv4")
            exitProcess(1)
        }

        val hosts = runCatching { prioritizeHosts(expandHosts(cidr)) }.getOrElse {
            System.err.println(it.message ?: "bad cidr")
            exitProcess(2)
        }
        if (hosts.isEmpty()) exitProcess(1)
        if (hosts.size * ports.size > 16384) {
            System.err.println("scan range too large: hosts=${hosts.size} ports=${ports.size}")
            exitProcess(2)
        }

        val results = scan(hosts, ports, timeoutMs, concurrency, firstOnly)
            .distinctBy { it.ip + ":" + it.port }
            .sortedWith(compareBy<ScanResult> { ipv4ToLong(it.ip) }.thenBy { it.port })
        for (r in results) {
            println("${r.ip}\t${r.port}\topen\t${r.elapsedMs}ms")
        }
        exitProcess(if (results.isNotEmpty()) 0 else 1)
    }

    private fun scan(
        hosts: List<String>,
        ports: List<Int>,
        timeoutMs: Int,
        concurrency: Int,
        firstOnly: Boolean
    ): List<ScanResult> {
        val first = scanPass(hosts, ports, timeoutMs, concurrency, firstOnly)
        if (first.isNotEmpty() || timeoutMs >= 1000) return first

        // ARP resolution on some Android/NAS combinations can exceed 250 ms.
        // If the fast pass finds nothing, retry once with a conservative timeout.
        return scanPass(hosts, ports, max(1000, timeoutMs * 3), concurrency, firstOnly)
    }

    private fun scanPass(
        hosts: List<String>,
        ports: List<Int>,
        timeoutMs: Int,
        concurrency: Int,
        firstOnly: Boolean
    ): List<ScanResult> {
        val taskCount = hosts.size * ports.size
        val pool = Executors.newFixedThreadPool(min(concurrency, max(1, taskCount)))
        val completion: CompletionService<ScanResult?> = ExecutorCompletionService(pool)
        val stop = AtomicBoolean(false)
        var submitted = 0
        try {
            for (ip in hosts) {
                for (port in ports) {
                    completion.submit(Callable {
                        if (firstOnly && stop.get()) return@Callable null
                        probe(ip, port, timeoutMs)?.also {
                            if (firstOnly) stop.set(true)
                        }
                    })
                    submitted++
                }
            }

            val out = ArrayList<ScanResult>()
            repeat(submitted) {
                val result = runCatching { completion.take().get() }.getOrNull()
                if (result != null) {
                    out += result
                    if (firstOnly) return out
                }
            }
            return out
        } finally {
            pool.shutdownNow()
            pool.awaitTermination(300, TimeUnit.MILLISECONDS)
        }
    }

    private fun probe(ip: String, port: Int, timeoutMs: Int): ScanResult? {
        val start = System.nanoTime()
        return try {
            Socket().use { socket ->
                socket.reuseAddress = true
                socket.tcpNoDelay = true
                socket.soTimeout = timeoutMs
                socket.connect(InetSocketAddress(ip, port), timeoutMs)
            }
            val elapsedMs = max(1L, TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start))
            ScanResult(ip, port, elapsedMs)
        } catch (_: IOException) {
            null
        } catch (_: SecurityException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun autoCidr24(): String? {
        val ifaces = runCatching { Collections.list(NetworkInterface.getNetworkInterfaces()) }.getOrNull().orEmpty()
        val candidates = ArrayList<Inet4Address>()
        for (iface in ifaces) {
            if (runCatching { !iface.isUp || iface.isLoopback || iface.isVirtual }.getOrDefault(true)) continue
            for (addr in Collections.list(iface.inetAddresses)) {
                val v4 = addr as? Inet4Address ?: continue
                if (v4.isLoopbackAddress || v4.isLinkLocalAddress) continue
                candidates += v4
            }
        }
        val best = candidates.firstOrNull { it.isSiteLocalAddress } ?: candidates.firstOrNull() ?: return null
        val parts = best.hostAddress?.split('.') ?: return null
        if (parts.size != 4) return null
        return "${parts[0]}.${parts[1]}.${parts[2]}.0/24"
    }

    private fun prioritizeHosts(hosts: List<String>): List<String> {
        if (hosts.isEmpty()) return hosts
        val hostSet = hosts.toHashSet()
        val preferred = ArrayList<String>()

        // Scan already-known L2 neighbors first. This helps firstOnly mode and usually finds NAS/router hosts early.
        for (ip in readArpHosts()) {
            if (ip in hostSet) preferred += ip
        }

        val prefix = hosts.firstOrNull()?.substringBeforeLast('.')
        if (prefix != null) {
            listOf(1, 2, 5, 10, 100, 200, 205, 220, 250, 254).forEach { n ->
                val ip = "$prefix.$n"
                if (ip in hostSet) preferred += ip
            }
        }

        val distinctPreferred = preferred.distinct()
        if (distinctPreferred.isEmpty()) return hosts
        return distinctPreferred + hosts.filterNot { it in distinctPreferred }
    }

    private fun readArpHosts(): List<String> {
        return runCatching {
            File("/proc/net/arp").readLines()
                .drop(1)
                .mapNotNull { line -> line.trim().split(Regex("\\s+")).firstOrNull() }
                .filter { it.matches(Regex("^\\d{1,3}(?:\\.\\d{1,3}){3}$")) }
                .distinct()
        }.getOrDefault(emptyList())
    }

    private fun expandHosts(cidrOrPrefix: String): List<String> {
        val cidr = normalizeCidr(cidrOrPrefix)
        val range = parseCidr(cidr)
        val out = ArrayList<String>()
        var cur = range.start
        while (cur <= range.end) {
            out += longToIpv4(cur)
            cur++
        }
        return out
    }

    private fun normalizeCidr(input: String): String {
        val s = input.trim().trimEnd('/')
        if (s.matches(Regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) return "$s.0/24"
        if (s.matches(Regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) return "$s/32"
        return s
    }

    private fun parseCidr(cidr: String): HostRange {
        val slash = cidr.indexOf('/')
        require(slash > 0) { "bad cidr: $cidr" }
        val ip = cidr.substring(0, slash)
        val prefix = cidr.substring(slash + 1).toIntOrNull() ?: error("bad cidr prefix: $cidr")
        require(prefix in 16..32) { "cidr prefix must be 16..32: $cidr" }
        val base = ipv4ToLong(ip)
        val mask = if (prefix == 0) 0L else (0xffffffffL shl (32 - prefix)) and 0xffffffffL
        val network = base and mask
        val broadcast = network or (mask.inv() and 0xffffffffL)
        val start = if (prefix <= 30) network + 1 else network
        val end = if (prefix <= 30) broadcast - 1 else broadcast
        require(end >= start) { "empty cidr: $cidr" }
        return HostRange(start, end)
    }

    private fun ipv4ToLong(ip: String): Long {
        val parts = ip.split('.')
        require(parts.size == 4) { "bad IPv4: $ip" }
        var out = 0L
        for (p in parts) {
            val n = p.toIntOrNull() ?: error("bad IPv4: $ip")
            require(n in 0..255) { "bad IPv4: $ip" }
            out = (out shl 8) or n.toLong()
        }
        return out and 0xffffffffL
    }

    private fun longToIpv4(value: Long): String {
        return listOf(
            (value ushr 24) and 255,
            (value ushr 16) and 255,
            (value ushr 8) and 255,
            value and 255
        ).joinToString(".")
    }

    private fun parsePorts(raw: String): List<Int> {
        return raw.split(',', ';')
            .mapNotNull { it.trim().toIntOrNull() }
            .filter { it in 1..65535 }
            .distinct()
    }

    private fun clampInt(value: Int, minValue: Int, maxValue: Int): Int {
        return min(max(value, minValue), maxValue)
    }

    private fun printUsage() {
        println("SmbScanUtil commands:")
        println("  scanSmb [cidr|auto] [timeoutMs] [concurrency] [firstOnly] [ports]")
        println("examples:")
        println("  scanSmb auto 800 192 0 445,139")
        println("  scanSmb 192.168.1.0/24 800 192 1 445,139")
        println("output:")
        println("  <ip>\\t<port>\\topen\\t<elapsedMs>ms")
    }
}
