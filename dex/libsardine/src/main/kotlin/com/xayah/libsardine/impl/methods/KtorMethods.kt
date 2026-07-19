package com.xayah.libsardine.impl.methods

import com.xayah.libsardine.model.Propfind
import com.xayah.libsardine.util.KotlinSardineUtil
import io.ktor.client.HttpClient
import io.ktor.client.content.ProgressListener
import io.ktor.client.plugins.onDownload
import io.ktor.client.request.delete
import io.ktor.client.request.headers
import io.ktor.client.request.preparePut
import io.ktor.client.request.prepareRequest
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.utils.io.ByteWriteChannel
import java.io.IOException

class KtorMethods(private val client: HttpClient) {
    companion object {
        private const val METHOD_PROPFIND = "PROPFIND"
        private const val METHOD_MKCOL = "MKCOL"
        private const val METHOD_MOVE = "MOVE"
        private const val METHOD_COPY = "COPY"
    }

    private fun getDepthString(depth: Int) = if (depth < 0) "infinity" else depth.toString()

    private fun HttpResponse.validateResponse(url: String): HttpResponse {
        if (status.value < HttpStatusCode.OK.value || status.value >= HttpStatusCode.MultipleChoices.value) {
            throw IOException("Unexpected response $url (${status})")
        }
        return this
    }

    private fun HttpResponse.validateExists(url: String): Boolean {
        if (status.value < HttpStatusCode.MultipleChoices.value) return true
        if (status.value == HttpStatusCode.NotFound.value) return false
        throw IOException("Unexpected response $url (${status})")
    }

    @Throws(IOException::class)
    suspend fun propfind(url: String, depth: Int, body: Propfind?) = propfindPrivate(url, depth, body).validateResponse(url)

    @Throws(IOException::class)
    private suspend fun propfindPrivate(url: String, depth: Int, body: Propfind?) = client.request(url) {
        headers {
            append(HttpHeaders.Depth, getDepthString(depth))
        }
        if (body != null) {
            setBody(KotlinSardineUtil.toXml(body))
        }
        method = HttpMethod.parse(METHOD_PROPFIND)
    }

    @Throws(IOException::class)
    suspend fun <T> get(url: String, headers: Map<String, String>, listener: ProgressListener?, block: suspend (response: HttpResponse) -> T): T = client.prepareRequest(url) {
        headers {
            headers.forEach { header ->
                append(header.key, header.value)
            }
        }
        method = HttpMethod.Get
        onDownload(listener)
    }.execute { res ->
        res.validateResponse(url)
        block(res)
    }

    @Throws(IOException::class)
    suspend fun put(
        url: String,
        onWriting: suspend (channel: ByteWriteChannel) -> Unit,
        contentLength: Long?,
        contentType: ContentType?,
        headers: Map<String, String>,
        block: suspend (response: HttpResponse) -> Unit
    ): Unit = client.preparePut(url) {
        setBody(object : OutgoingContent.WriteChannelContent() {
            override val contentLength: Long? = contentLength
            override val contentType: ContentType? = contentType
            override val headers: Headers
                get() = Headers.build {
                    headers.forEach { header ->
                        append(header.key, header.value)
                    }
                }

            override suspend fun writeTo(channel: ByteWriteChannel) {
                onWriting(channel)
            }
        })
    }.execute { res ->
        res.validateResponse(url)
        block(res)
    }

    @Throws(IOException::class)
    suspend fun delete(url: String, headers: Map<String, String>) = client.delete(url) {
        headers {
            headers.forEach { header ->
                append(header.key, header.value)
            }
        }
    }.validateResponse(url)

    @Throws(IOException::class)
    suspend fun createDirectory(url: String) = client.request(url) {
        method = HttpMethod.parse(METHOD_MKCOL)
    }.validateResponse(url)

    @Throws(IOException::class)
    suspend fun exists(url: String) = propfindPrivate(url, 0, null).validateExists(url)

    @Throws(IOException::class)
    suspend fun move(sourceUrl: String, destinationUrl: String, overwrite: Boolean, headers: Map<String, String>) = client.request(sourceUrl) {
        method = HttpMethod.parse(METHOD_MOVE)
        headers {
            append(HttpHeaders.Destination, destinationUrl)
            append(HttpHeaders.Overwrite, if (overwrite) "T" else "F")
            headers.forEach { header ->
                append(header.key, header.value)
            }
        }
    }.validateResponse(destinationUrl)

    @Throws(IOException::class)
    suspend fun copy(sourceUrl: String, destinationUrl: String, overwrite: Boolean, headers: Map<String, String>) = client.request(sourceUrl) {
        method = HttpMethod.parse(METHOD_COPY)
        headers {
            append(HttpHeaders.Destination, destinationUrl)
            append(HttpHeaders.Overwrite, if (overwrite) "T" else "F")
            headers.forEach { header ->
                append(header.key, header.value)
            }
        }
    }.validateResponse(destinationUrl)
}