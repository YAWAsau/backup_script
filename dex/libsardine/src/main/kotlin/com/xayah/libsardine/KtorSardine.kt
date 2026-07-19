package com.xayah.libsardine

import io.ktor.client.content.ProgressListener
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.utils.io.ByteWriteChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import javax.xml.namespace.QName

/**
 * Imported from [lookfirst/sardine](https://github.com/lookfirst/sardine/blob/fa17c2ea707141b2c62df9c72c2c430b09801123/src/main/java/com/github/sardine/Sardine.java)
 *
 * The main interface for Sardine operations.
 *
 * @author jonstevens
 */
interface KtorSardine {
    /**
     * Gets a directory listing using WebDAV <code>PROPFIND</code>.
     *
     * @param url   Path to the resource including protocol and hostname
     * @param depth The depth to look at (use 0 for single resource, 1 for directory listing,
     *              -1 for infinite recursion)
     * @param props Additional properties which should be requested.
     * @return List of resources for this URI including the parent resource itself
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun list(url: String, depth: Int, props: Set<QName>): List<DavResource>

    /**
     * Gets a directory listing using WebDAV <code>PROPFIND</code>.
     *
     * @param url   Path to the resource including protocol and hostname
     * @param depth The depth to look at (use 0 for single resource, 1 for directory listing,
     *              -1 for infinite recursion)
     * @param allProp If allprop should be used, which can be inefficient sometimes;
     * warning: no allprop does not retrieve custom props, just the basic ones
     * @return List of resources for this URI including the parent resource itself
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun list(url: String, depth: Int = 1, allProp: Boolean = true): List<DavResource>

    /**
     * Fetches a resource using WebDAV <code>PROPFIND</code>. Only the specified properties
     * are retrieved.
     *
     * @param url   Path to the resource including protocol and hostname
     * @param depth The depth to look at (use 0 for single resource, 1 for directory listing,
     *              -1 for infinite recursion)
     * @param props Set of properties to be requested
     * @return List of resources for this URI including the parent resource itself
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun propfind(url: String, depth: Int, props: Set<QName>): List<DavResource>

    /**
     * Uses HTTP `GET` to download data from a server. The stream must be closed after reading.
     *
     * @param url     Path to the resource including protocol and hostname
     * @param headers Additional HTTP headers to add to the request
     * @param listener Callback that can be registered to listen for upload/ download progress, see [io.ktor.client.content.ProgressListener]
     * @param block See [io.ktor.client.statement.HttpStatement.execute]
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun <T> get(url: String, headers: Map<String, String> = emptyMap(), listener: ProgressListener? = null, block: suspend (response: HttpResponse) -> T): T

    /**
     * Uses `PUT` to send data to a server. Not repeatable on authentication failure.
     *
     * @param url        Path to the resource including protocol and hostname (must not point to a directory)
     * @param onWriting  Input source using [ByteWriteChannel]
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun put(url: String, onWriting: suspend (channel: ByteWriteChannel) -> Unit, block: suspend (response: HttpResponse) -> Unit)

    /**
     * Uses `PUT` to send data to a server with a specific content type
     * header. Repeatable on authentication failure.
     *
     * @param url         Path to the resource including protocol and hostname (must not point to a directory)
     * @param data        Input source
     * @param contentType MIME type to add to the HTTP request header
     * @param listener Callback that can be registered to listen for upload/ download progress, see [io.ktor.client.content.ProgressListener]
     * @param block See [io.ktor.client.statement.HttpStatement.execute]
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun put(url: String, data: ByteArray, contentType: ContentType? = null, listener: ProgressListener? = null, block: suspend (response: HttpResponse) -> Unit)

    /**
     * Uses `PUT` to send data to a server with a specific content
     * type header. Not repeatable on authentication failure.
     *
     * @param url            Path to the resource including protocol and hostname (must not point to a directory)
     * @param dataStream     Input source
     * @param contentType    MIME type to add to the HTTP request header
     * @param expectContinue Enable `Expect: continue` header for `PUT` requests.
     * @param contentLength data size in bytes to set to Content-Length header
     * @param headers    Additional HTTP headers to add to the request
     * @param listener Callback that can be registered to listen for upload/ download progress, see [io.ktor.client.content.ProgressListener]
     * @param block See [io.ktor.client.statement.HttpStatement.execute]
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun put(
        url: String,
        dataStream: InputStream,
        contentType: ContentType? = null,
        expectContinue: Boolean = true,
        contentLength: Long? = null,
        headers: Map<String, String> = emptyMap(),
        listener: ProgressListener? = null,
        block: suspend (response: HttpResponse) -> Unit
    )

    /**
     * Uses `PUT` to upload file to a server with specific contentType.
     * Repeatable on authentication failure.
     *
     * @param url       Path to the resource including protocol and hostname (must not point to a directory)
     * @param localFile local file to send
     * @param contentType   MIME type to add to the HTTP request header
     * @param expectContinue Enable `Expect: continue` header for `PUT` requests.
     * @param listener Callback that can be registered to listen for upload/ download progress, see [io.ktor.client.content.ProgressListener]
     * @param block See [io.ktor.client.statement.HttpStatement.execute]
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun put(url: String, localFile: File, contentType: ContentType?, expectContinue: Boolean = false, listener: ProgressListener? = null, block: suspend (response: HttpResponse) -> Unit)

    /**
     * Delete a resource using HTTP `DELETE` at the specified url
     *
     * @param url Path to the resource including protocol and hostname
     * @param headers Additional HTTP headers to add to the request
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun delete(url: String, headers: Map<String, String> = emptyMap())

    /**
     * Uses WebDAV `MKCOL` to create a directory at the specified url
     *
     * @param url Path to the resource including protocol and hostname
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun createDirectory(url: String)

    /**
     * Move a url to from source to destination using WebDAV `MOVE`.
     *
     * @param sourceUrl      Path to the resource including protocol and hostname
     * @param destinationUrl Path to the resource including protocol and hostname
     * @param overwrite `true` to overwrite if the destination exists, `false` otherwise.
     * @param headers Additional HTTP headers to add to the request
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun move(sourceUrl: String, destinationUrl: String, overwrite: Boolean = true, headers: Map<String, String> = emptyMap())

    /**
     * Copy a url from source to destination using WebDAV `COPY`.
     *
     * @param sourceUrl      Path to the resource including protocol and hostname
     * @param destinationUrl Path to the resource including protocol and hostname
     * @param overwrite `true` to overwrite if the destination exists, `false` otherwise.
     * @param headers Additional HTTP headers to add to the request
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun copy(sourceUrl: String, destinationUrl: String, overwrite: Boolean = true, headers: Map<String, String> = emptyMap())

    /**
     * Performs a HTTP `HEAD` request to see if a resource exists or not.
     *
     * @param url Path to the resource including protocol and hostname
     * @return Anything outside of the 200-299 response code range returns false.
     * @throws IOException I/O error or HTTP response validation failure
     */
    @Throws(IOException::class)
    suspend fun exists(url: String): Boolean
}