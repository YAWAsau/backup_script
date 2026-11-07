package com.xayah.dex

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

/** Resume only the isolated file owned by this invocation; never append to a decompressor. */
internal object WebDavDownload {
    fun fetch(http: HttpCore.Client, user: String, pass: String, url: String, staging: File): Int {
        var etag: String? = null
        var total: Long? = null
        var lastCode = 0
        var lastFailure: IOException? = null
        repeat(4) { attempt ->
            val offset = if (etag != null && total != null && staging.length() in 1 until total!!) staging.length() else 0L
            val headers = linkedMapOf("Accept-Encoding" to "identity")
            if (offset > 0) { headers["Range"] = "bytes=$offset-"; headers["If-Range"] = etag!! }
            try {
                lastCode = http.request("GET", url, user, pass, headers,
                    followRedirects = true, retryOnConnectionFailure = { false },
                    responseConsumer = { code, h, input ->
                        fun header(name: String) = h[name]?.singleOrNull()
                        if (code != 200 && code != 206) {
                            HttpCore.discardErrorResponseBody(h, input)
                        } else {
                            if (header("content-encoding")?.let { !it.equals("identity", true) } == true) throw IOException("WEBDAV_RESUME_ENCODED_RESPONSE")
                            val responseTag = header("etag")?.takeIf { it.startsWith('"') && it.endsWith('"') }
                            val responseLength = header("content-length")?.toLongOrNull()?.takeIf { it >= 0 }
                            var append = false
                            var expected = responseLength
                            if (code == 206) {
                                val range = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(header("content-range").orEmpty())
                                val start = range?.groupValues?.get(1)?.toLongOrNull()
                                val end = range?.groupValues?.get(2)?.toLongOrNull()
                                val length = range?.groupValues?.get(3)?.toLongOrNull()
                                if (offset <= 0 || start != offset || end == null || length == null || length != total || end < offset || end >= length || responseTag != etag || (responseLength != null && responseLength != end - offset + 1)) {
                                    etag = null; total = null
                                    throw IOException("WEBDAV_RESUME_INVALID_CONTENT_RANGE")
                                }
                                append = true
                                expected = end - offset + 1
                            } else {
                                // If-Range mismatch or Range ignored: replace the partial, never append a 200.
                                etag = responseTag
                                total = responseLength
                            }
                            FileOutputStream(staging, append).use { file ->
                                var received = 0L
                                val limited = object : OutputStream() {
                                    override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)
                                    override fun write(b: ByteArray, off: Int, len: Int) {
                                        if (expected != null && len.toLong() > expected!! - received) throw IOException("WEBDAV_DOWNLOAD_TOO_LONG")
                                        file.write(b, off, len); received += len
                                    }
                                }
                                HttpCore.readResponseBody(h, input, limited)
                                if (expected != null && received != expected) throw IOException("WEBDAV_DOWNLOAD_TRUNCATED")
                                file.flush(); file.fd.sync()
                            }
                        }
                    })
                if (lastCode in 200..299 && lastCode != 200 && lastCode != 206) throw IOException("WEBDAV_DOWNLOAD_UNEXPECTED_STATUS_$lastCode")
                if (lastCode == 200 || lastCode == 206) {
                    if (total == null || staging.length() == total) return 200
                    lastFailure = IOException("WEBDAV_DOWNLOAD_INCOMPLETE")
                } else if (lastCode == 416 && offset > 0) {
                    etag = null; total = null
                } else if (lastCode !in setOf(408, 429, 500, 502, 503, 504)) return lastCode
            } catch (e: IOException) { lastFailure = e }
            if (attempt < 3) Thread.sleep(maxOf((attempt + 1) * 250L, http.consumeLastRetryAfterMs()).coerceAtMost(30_000L))
        }
        lastFailure?.let { throw it }
        return lastCode
    }
}
