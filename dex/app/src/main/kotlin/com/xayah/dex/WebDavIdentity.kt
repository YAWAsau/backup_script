package com.xayah.dex

import com.google.gson.JsonParser
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.FutureTask

/** Identity hints only: never cache a failed probe, and briefly cache negative hints. */
internal class WebDavIdentityCache<T : Any>(
    private val lifetimeNanos: (T) -> Long,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    private data class Entry<T>(val value: T, val storedAt: Long, val lifetime: Long)
    private val entries = ConcurrentHashMap<String, Entry<T>>()
    private val pending = ConcurrentHashMap<String, FutureTask<T?>>()

    fun get(key: String): T? {
        val entry = entries[key] ?: return null
        if (entry.lifetime == Long.MAX_VALUE || nanoTime() - entry.storedAt < entry.lifetime) return entry.value
        entries.remove(key, entry)
        return null
    }

    fun put(key: String, value: T) {
        entries[key] = Entry(value, nanoTime(), lifetimeNanos(value))
    }

    fun clear() = entries.clear()

    fun getOrProbe(key: String, probe: () -> T?): T? {
        get(key)?.let { return it }
        // Only publish the task under the map's lock. run() (including all network
        // work) is outside any map callback/monitor, even for colliding origins.
        val task = FutureTask<T?> { get(key) ?: probe()?.also { put(key, it) } }
        val existing = pending.putIfAbsent(key, task)
        if (existing != null) return await(existing)
        try {
            task.run()
            return await(task)
        } finally {
            pending.remove(key, task)
        }
    }

    private fun await(task: FutureTask<T?>): T? = try {
        task.get()
    } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        null
    } catch (failure: ExecutionException) {
        throw failure.cause ?: failure
    }

    companion object {
        const val NEGATIVE_TTL_NANOS = 30_000_000_000L

        fun identityLifetime(recognized: Boolean): Long =
            if (recognized) Long.MAX_VALUE else NEGATIVE_TTL_NANOS

        // An OPTIONS success can still contain only a fallback after the optional
        // identity GET failed. Do not let this outer cache make that permanent.
        fun serverKindLifetime(kind: String): Long =
            if (kind == "generic" || kind == "alist_compatible") NEGATIVE_TTL_NANOS else Long.MAX_VALUE
    }
}

internal object SpeedBackupIdentityProbe {
    // null means inconclusive (transport/server/parse/size failure), not a true
    // negative. Keep the public same-origin request independent of DAV credentials.
    fun probe(url: String): Boolean? = runCatching {
        val start = System.nanoTime()
        val source = URL(url)
        val endpoint = URL(source.protocol, source.host, source.port, "/api/v1/capabilities")
        val conn = endpoint.openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "GET"
            conn.connectTimeout = 1000
            conn.readTimeout = 1000
            conn.instanceFollowRedirects = false
            conn.useCaches = false
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("Connection", "close")
            val code = conn.responseCode
            if (code <= 0 || code == 408 || code == 423 || code == 425 || code == 429 || code in 500..599) return@runCatching null
            if (code != 200 || !conn.contentType.orEmpty().substringBefore(';').trim().equals("application/json", true)) return@runCatching false
            val bytes = ByteArrayOutputStream()
            conn.inputStream.use { input ->
                val buffer = ByteArray(1024)
                while (true) {
                    if (System.nanoTime() - start > 2_000_000_000L) throw IOException("identity deadline")
                    val n = input.read(buffer)
                    if (n < 0) break
                    if (bytes.size() + n > 8192) throw IOException("identity size limit")
                    bytes.write(buffer, 0, n)
                }
            }
            val obj = JsonParser.parseString(bytes.toString("UTF-8")).asJsonObject
            val protocol = obj.getAsJsonObject("protocol")
            val webdav = obj.getAsJsonObject("webdav")
            obj.get("server")?.asString == "SpeedBackup Server" &&
                protocol?.get("major")?.asString == "1" &&
                webdav?.get("path")?.asString == "/" &&
                webdav.get("authentication")?.asString == "basic" &&
                webdav.get("storage")?.asString == "per_user_files"
        } finally {
            conn.disconnect()
        }
    }.getOrNull()
}
