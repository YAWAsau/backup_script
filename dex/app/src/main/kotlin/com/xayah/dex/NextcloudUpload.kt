package com.xayah.dex

import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Nextcloud chunking v2. A bounded replayable chunk, never a replay of the source stream. */
internal object NextcloudUpload {
    private const val CHUNK_SIZE = 8 * 1024 * 1024
    private val capability = ConcurrentHashMap<String, Boolean>()

    private fun uploadsRoot(destination: String): String? {
        val url = URL(destination)
        val match = Regex("^(.*)/remote\\.php/dav/files/([^/]+)(?:/.*)?$").matchEntire(url.path) ?: return null
        if (url.query != null || url.ref != null || url.userInfo != null) return null
        return URL(url, match.groupValues[1] + "/remote.php/dav/uploads/" + match.groupValues[2]).toString()
    }

    fun available(http: HttpCore.Client, user: String, pass: String, destination: String): Boolean {
        val root = uploadsRoot(destination) ?: return false
        val key = WebDavIdentityKey(root, user, pass)
        capability[key]?.let { return it }
        val code = http.request("PROPFIND", root, user, pass, mapOf("Depth" to "0", "Content-Length" to "0"), canReplayBody = true)
        val supported = code == 207
        // Transient/auth failures must not become permanent negative capability entries.
        if (supported || code in setOf(404, 405, 501)) {
            if (capability.size > 128) capability.clear()
            capability[key] = supported
        }
        return supported
    }

    private fun WebDavIdentityKey(root: String, user: String, pass: String): String =
        java.security.MessageDigest.getInstance("SHA-256").digest("$root\n$user\n$pass".toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }

    fun put(http: HttpCore.Client, user: String, pass: String, destination: String, input: InputStream, length: Long?, bodyComplete: () -> Unit, timeout: Int = HttpCore.LONG_TRANSFER_TIMEOUT_MS): Int {
        val root = uploadsRoot(destination) ?: throw IOException("NEXTCLOUD_UPLOAD_PATH_REQUIRED")
        val upload = "$root/speedbackup-${UUID.randomUUID()}"
        val common = linkedMapOf("Destination" to HttpCore.Target(destination).let { URL(it.urlObj.protocol, it.urlObj.host, it.urlObj.port, it.requestTarget).toString() })
        if (length != null && length >= 0) common["OC-Total-Length"] = length.toString()
        try {
            val created = http.request("MKCOL", upload, user, pass, common + ("Content-Length" to "0"))
            if (created !in 200..299) return created
            val buffer = ByteArray(CHUNK_SIZE)
            var index = 0
            var sent = 0L
            while (true) {
                var count = 0
                while (count < buffer.size) {
                    val read = input.read(buffer, count, buffer.size - count)
                    if (read < 0) break
                    if (read == 0) throw IOException("NEXTCLOUD_SOURCE_ZERO_READ")
                    count += read
                }
                if (count == 0) break
                if (++index > 10_000) throw IOException("NEXTCLOUD_MAX_CHUNKS_EXCEEDED")
                var code = 0
                var failure: IOException? = null
                for (attempt in 0..3) {
                    try {
                        code = http.request("PUT", "$upload/${index.toString().padStart(5, '0')}", user, pass,
                            common + mapOf("Content-Length" to count.toString(), "Content-Type" to "application/octet-stream"),
                            bodyWriter = { it.write(buffer, 0, count) }, canReplayBody = true,
                            responseHeadTimeoutMs = timeout)
                        failure = null
                        if (code in 200..299 || code !in setOf(408, 429, 500, 502, 503, 504)) break
                    } catch (e: IOException) { failure = e }
                    if (attempt < 3) Thread.sleep(maxOf((attempt + 1) * 500L, http.consumeLastRetryAfterMs()).coerceAtMost(30_000L))
                }
                failure?.let { throw it }
                if (code !in 200..299) return code
                sent += count
                if (length != null && sent > length) throw IOException("NEXTCLOUD_SOURCE_LENGTH_CHANGED")
                if (count < buffer.size) break
            }
            if (length != null && sent != length) throw IOException("NEXTCLOUD_SOURCE_LENGTH_CHANGED")
            bodyComplete()
            if (index == 0) return http.request("PUT", destination, user, pass, mapOf("Content-Length" to "0"), canReplayBody = true)
            // Assemble only into the caller's unique staged destination. The caller verifies and publishes.
            return http.request("MOVE", "$upload/.file", user, pass,
                common + mapOf("OC-Total-Length" to sent.toString(), "Overwrite" to "T", "Content-Length" to "0"),
                retryOnConnectionFailure = { false }, responseHeadTimeoutMs = timeout)
        } finally {
            // This directory belongs exclusively to this operation; never delete the final backup.
            runCatching { http.request("DELETE", upload, user, pass, mapOf("Content-Length" to "0"), canReplayBody = true) }
        }
    }
}
