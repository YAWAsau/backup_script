package com.xayah.libsardine.impl

import com.xayah.libsardine.DavResource
import com.xayah.libsardine.KtorSardine
import com.xayah.libsardine.impl.methods.KtorHandler
import com.xayah.libsardine.impl.methods.KtorMethods
import com.xayah.libsardine.model.Allprop
import com.xayah.libsardine.model.Creationdate
import com.xayah.libsardine.model.Displayname
import com.xayah.libsardine.model.Getcontentlength
import com.xayah.libsardine.model.Getcontenttype
import com.xayah.libsardine.model.Getetag
import com.xayah.libsardine.model.Getlastmodified
import com.xayah.libsardine.model.Lockdiscovery
import com.xayah.libsardine.model.Prop
import com.xayah.libsardine.model.Propfind
import com.xayah.libsardine.model.Resourcetype
import com.xayah.libsardine.util.KotlinSardineUtil
import com.xayah.libsardine.util.copyTo
import io.ktor.client.HttpClient
import io.ktor.client.content.ProgressListener
import io.ktor.client.engine.ProxyConfig
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.auth.Auth
import io.ktor.client.plugins.auth.providers.BasicAuthCredentials
import io.ktor.client.plugins.auth.providers.BearerTokens
import io.ktor.client.plugins.auth.providers.basic
import io.ktor.client.plugins.auth.providers.bearer
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.utils.io.ByteWriteChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import nl.adaptivity.xmlutil.XmlUtilInternal
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import javax.xml.namespace.QName

@OptIn(XmlUtilInternal::class)
class KtorSardineImpl : KtorSardine {
    companion object {
        private const val DEFAULT_TIMEOUT = 15000L
    }
    private var client: HttpClient
    private var methods: KtorMethods

    private suspend fun <T> withIOContext(block: suspend CoroutineScope.() -> T): T =
        withContext(Dispatchers.IO, block)

    constructor(requestTimeout: Long = 15000) {
        this.client = HttpClient(CIO) {
            engine {
                this.requestTimeout = requestTimeout
            }
        }
        this.methods = KtorMethods(this.client)
    }

    constructor(client: HttpClient) {
        this.client = client
        this.methods = KtorMethods(this.client)
    }

    constructor(accessToken: String, requestTimeout: Long = DEFAULT_TIMEOUT) {
        this.client = HttpClient(CIO) {
            engine {
                this.requestTimeout = requestTimeout
            }

            install(Auth) {
                bearer {
                    loadTokens {
                        BearerTokens(accessToken, "")
                    }
                }
            }
        }
        this.methods = KtorMethods(this.client)
    }

    constructor(username: String, password: String, requestTimeout: Long = DEFAULT_TIMEOUT) {
        this.client = HttpClient(CIO) {
            engine {
                this.requestTimeout = requestTimeout
            }

            install(Auth) {
                basic {
                    credentials {
                        BasicAuthCredentials(username = username, password = password)
                    }
                    // WebDAV 大檔 chunked PUT 不能依賴 401 challenge 後重送 body；
                    // 直接預送 Basic Authorization，避免非 repeatable stream 被消耗後重試失敗。
                    sendWithoutRequest { true }
                }
            }
        }
        this.methods = KtorMethods(this.client)
    }

    constructor(username: String, password: String, proxyConfig: ProxyConfig, requestTimeout: Long = DEFAULT_TIMEOUT) {
        this.client = HttpClient(CIO) {
            engine {
                this.requestTimeout = requestTimeout
                this.proxy = proxyConfig
            }

            install(Auth) {
                basic {
                    credentials {
                        BasicAuthCredentials(username = username, password = password)
                    }
                    // WebDAV 大檔 chunked PUT 不能依賴 401 challenge 後重送 body；
                    // 直接預送 Basic Authorization，避免非 repeatable stream 被消耗後重試失敗。
                    sendWithoutRequest { true }
                }
            }
        }
        this.methods = KtorMethods(this.client)
    }

    @Throws(IOException::class)
    override suspend fun list(url: String, depth: Int, props: Set<QName>): List<DavResource> {
        val body = Propfind()
        val prop = Prop()
        prop.getcontentlength = Getcontentlength()
        prop.getlastmodified = Getlastmodified()
        prop.creationdate = Creationdate()
        prop.displayname = Displayname()
        prop.getcontenttype = Getcontenttype()
        prop.resourcetype = Resourcetype()
        prop.getetag = Getetag()
        prop.lockdiscovery = Lockdiscovery()
        addCustomProperties(prop = prop, props = props)
        body.prop = prop
        return propfind(url = url, depth = depth, body = body)
    }

    @Throws(IOException::class)
    override suspend fun list(url: String, depth: Int, allProp: Boolean): List<DavResource> {
        if (allProp) {
            val body = Propfind()
            body.allprop = Allprop()
            return propfind(url = url, depth = depth, body = body)
        } else {
            return list(url = url, depth = depth, props = emptySet())
        }
    }

    @Throws(IOException::class)
    override suspend fun propfind(url: String, depth: Int, props: Set<QName>): List<DavResource> {
        val body = Propfind()
        val prop = Prop()
        addCustomProperties(prop = prop, props = props)
        body.prop = prop
        return propfind(url = url, depth = depth, body = body)
    }

    @Throws(IOException::class)
    override suspend fun <T> get(url: String, headers: Map<String, String>, listener: ProgressListener?, block: suspend (response: HttpResponse) -> T): T {
        return methods.get(url = url, headers = headers, listener = listener, block = block)
    }

    @Throws(IOException::class)
    override suspend fun put(url: String, onWriting: suspend (channel: ByteWriteChannel) -> Unit, block: suspend (response: HttpResponse) -> Unit) {
        put(url = url, onWriting = onWriting, contentLength = null, contentType = null, headers = emptyMap(), block = block)
    }

    @Throws(IOException::class)
    override suspend fun put(url: String, data: ByteArray, contentType: ContentType?, listener: ProgressListener?, block: suspend (response: HttpResponse) -> Unit) {
        put(url = url, dataStream = ByteArrayInputStream(data), contentType = contentType, contentLength = data.size.toLong(), listener = listener, block = block)
    }

    @Throws(IOException::class)
    override suspend fun put(url: String, dataStream: InputStream, contentType: ContentType?, expectContinue: Boolean, contentLength: Long?, headers: Map<String, String>, listener: ProgressListener?, block: suspend (response: HttpResponse) -> Unit) {
        // If contentLength is null, the resources will be sent as `Transfer-Encoding: chunked`
        val _headers: MutableMap<String, String> = mutableMapOf()
        if (expectContinue) {
            _headers[HttpHeaders.Expect] = "100-continue"
        }
        _headers.putAll(headers)
        put(url = url, dataStream = dataStream, contentLength = contentLength, contentType = contentType, headers = _headers, listener = listener, block = block)
    }

    @Throws(IOException::class)
    override suspend fun put(url: String, localFile: File, contentType: ContentType?, expectContinue: Boolean, listener: ProgressListener?, block: suspend (response: HttpResponse) -> Unit) {
        // Don't use ExpectContinue for repeatable FileEntity, some web server (IIS for example) may return 400 bad request after retry
        put(url = url, dataStream = localFile.inputStream(), contentType = contentType, expectContinue = expectContinue, contentLength = localFile.length(), headers = emptyMap(), listener = listener, block = block)
    }

    @Throws(IOException::class)
    override suspend fun delete(url: String, headers: Map<String, String>) {
        methods.delete(url, headers)
    }

    @Throws(IOException::class)
    override suspend fun createDirectory(url: String) {
        methods.createDirectory(url)
    }

    @Throws(IOException::class)
    override suspend fun move(sourceUrl: String, destinationUrl: String, overwrite: Boolean, headers: Map<String, String>) {
        methods.move(sourceUrl, destinationUrl, overwrite, headers)
    }

    @Throws(IOException::class)
    override suspend fun copy(sourceUrl: String, destinationUrl: String, overwrite: Boolean, headers: Map<String, String>) {
        methods.copy(sourceUrl, destinationUrl, overwrite, headers)
    }

    @Throws(IOException::class)
    override suspend fun exists(url: String): Boolean = methods.exists(url)


    @Throws(IOException::class)
    private fun addCustomProperties(prop: Prop, props: Set<QName>) {
        val any = prop.any.toMutableList()
        for (entry in props) {
            val element = KotlinSardineUtil.createElement(entry)
            any.add(element)
        }
        prop.any = any
    }

    @Throws(IOException::class)
    private suspend fun propfind(url: String, depth: Int, body: Propfind): List<DavResource> = withIOContext {
        KtorHandler.responses(KtorHandler.multiStatus(methods.propfind(url, depth, body)))
    }

    @Throws(IOException::class)
    private suspend fun put(
        url: String,
        dataStream: InputStream,
        contentLength: Long?,
        contentType: ContentType?,
        headers: Map<String, String>,
        listener: ProgressListener?,
        block: suspend (response: HttpResponse) -> Unit
    ) {
        put(
            url = url,
            onWriting = { channel ->
                dataStream.copyTo(channel) { copied ->
                    listener?.invoke(copied, contentLength ?: -1)
                }
            },
            contentLength = contentLength,
            contentType = contentType,
            headers = headers,
            block = block
        )
    }

    @Throws(IOException::class)
    private suspend fun put(
        url: String,
        onWriting: suspend (channel: ByteWriteChannel) -> Unit,
        contentLength: Long?,
        contentType: ContentType?,
        headers: Map<String, String>,
        block: suspend (response: HttpResponse) -> Unit
    ) {
        methods.put(url, onWriting, contentLength, contentType, headers, block)
    }
}