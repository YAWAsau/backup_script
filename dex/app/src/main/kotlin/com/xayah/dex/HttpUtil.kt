package com.xayah.dex

import java.io.FileOutputStream
import kotlin.system.exitProcess

/**
 * Plain HTTP/HTTPS downloader for non-WebDAV tasks such as update checks.
 * Uses the same dependency-free HttpCore as WebDavUtil.
 */
object HttpUtil {
    private val http = HttpCore.Client(keepAlive = false)

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isEmpty()) {
            printUsage()
            exitProcess(2)
        }
        when (args[0]) {
            "get" -> cmdGet(args)
            "download" -> cmdDownload(args)
            "encodepath" -> {
                require(args.size >= 2) { "encodepath <text>" }
                print(HttpCore.percentEncodePath(args[1]))
            }
            "decodepath" -> {
                require(args.size >= 2) { "decodepath <text>" }
                print(HttpCore.percentDecodePath(args[1]))
            }
            else -> {
                printUsage()
                exitProcess(2)
            }
        }
    }

    private fun cmdGet(args: Array<String>) {
        require(args.size >= 2) { "get <url>" }
        val code = runCatching { http.getTo(args[1], System.out, followRedirects = true) }.getOrElse { HttpCore.extractCode(it) }
        System.out.flush()
        if (code !in 200..299) System.err.println("HTTP $code")
        exitProcess(if (code in 200..299) 0 else 1)
    }

    private fun cmdDownload(args: Array<String>) {
        require(args.size >= 3) { "download <url> <file>" }
        val code = runCatching { FileOutputStream(args[2]).use { out -> http.getTo(args[1], out, followRedirects = true) } }.getOrElse { HttpCore.extractCode(it) }
        println("HTTP $code")
        exitProcess(if (code in 200..299) 0 else 1)
    }

    private fun printUsage() {
        println("HttpUtil commands:")
        println("  get <url>                 (body on stdout; follows redirects; gzip/deflate supported)")
        println("  download <url> <file>")
        println("  encodepath <text>")
        println("  decodepath <text>")
    }
}
