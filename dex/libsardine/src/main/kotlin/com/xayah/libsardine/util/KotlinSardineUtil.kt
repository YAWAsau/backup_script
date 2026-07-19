package com.xayah.libsardine.util

import kotlinx.serialization.DeserializationStrategy
import nl.adaptivity.xmlutil.XmlUtilInternal
import nl.adaptivity.xmlutil.serialization.XML
import nl.adaptivity.xmlutil.util.impl.createDocument
import org.w3c.dom.Element
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.xml.namespace.QName

/**
 * Imported from [lookfirst/sardine](https://github.com/lookfirst/sardine/blob/fa17c2ea707141b2c62df9c72c2c430b09801123/src/main/java/com/github/sardine/util/SardineUtil.java)
 */
object KotlinSardineUtil {
    /**
     * Default namespace prefix
     */
    const val DEFAULT_NAMESPACE_PREFIX: String = "D"

    /**
     * Default namespace URI
     */
    const val DEFAULT_NAMESPACE_URI: String = "DAV:"

    private val SUPPORTED_DATE_FORMATS: List<String> = listOf(
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "EEE MMM dd HH:mm:ss zzz yyyy",
        "EEEEEE, dd-MMM-yy HH:mm:ss zzz",
        "EEE MMMM d HH:mm:ss yyyy"
    )

    /**
     * Imported from [thegrizzlylabs/sardine-android](https://github.com/thegrizzlylabs/sardine-android/blob/d0af7ae8e7ee0654a763c4c6f638a5e98b1782e9/src/main/java/com/thegrizzlylabs/sardineandroid/util/SardineUtil.java)
     * <p>
     * Loops over all the possible date formats and tries to find the right one.
     *
     * @param value ISO date string
     * @return Null if there is a parsing failure
     */
    fun parseDate(value: String?): Date? {
        if (value == null) {
            return null
        }
        var date: Date? = null
        for (format in SUPPORTED_DATE_FORMATS) {
            val sdf = SimpleDateFormat(format, Locale.US)
            sdf.timeZone = TimeZone.getTimeZone("UTC")
            runCatching {
                date = sdf.parse(value)
            }
        }
        return date
    }

    @Throws(IOException::class)
    fun <T> unmarshal(string: String, deserializer: DeserializationStrategy<T>): T = runCatching {
        XML {
            defaultPolicy {
                ignoreUnknownChildren()
            }
        }.decodeFromString(deserializer, string)
    }.getOrNull() ?: throw IOException("Not a valid DAV response")

    inline fun <reified T : Any> toXml(obj: T): String = XML.encodeToString(obj)

    fun toQName(element: Element): QName {
        val namespace = element.namespaceURI
        return if (namespace == null) {
            QName(DEFAULT_NAMESPACE_URI, element.localName, DEFAULT_NAMESPACE_PREFIX)
        } else if (element.prefix == null) {
            QName(element.namespaceURI, element.localName)
        } else {
            QName(element.namespaceURI, element.localName, element.prefix)
        }
    }

    /**
     * @param key Local element name.
     */
    fun createQNameWithDefaultNamespace(key: String?): QName {
        return QName(DEFAULT_NAMESPACE_URI, key, DEFAULT_NAMESPACE_PREFIX)
    }

    /**
     * @param key Fully qualified element name.
     */
    @XmlUtilInternal
    fun createElement(key: QName): Element {
        return createDocument(key).documentElement
    }
}
