package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.dom.Element
import nl.adaptivity.xmlutil.serialization.XmlOtherAttributes
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "prop", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Prop(
    var creationdate: Creationdate? = null,
    var displayname: Displayname? = null,
    var getcontentlanguage: Getcontentlanguage? = null,
    var getcontentlength: Getcontentlength? = null,
    var getcontenttype: Getcontenttype? = null,
    var getetag: Getetag? = null,
    var getlastmodified: Getlastmodified? = null,
    var lockdiscovery: Lockdiscovery? = null,
    var resourcetype: Resourcetype? = null,
    var supportedlock: Supportedlock? = null,

    @XmlSerialName("supported-report-set")
    var supportedReportSet: SupportedReportSet? = null,

    @XmlSerialName("quota-available-bytes")
    var quotaAvailableBytes: QuotaAvailableBytes? = null,

    @XmlSerialName("quota-used-bytes")
    var quotaUsedBytes: QuotaUsedBytes? = null,

    @XmlOtherAttributes
    var any: List<Element> = listOf(),

    var owner: Owner? = null,
    var group: Group? = null,
    var acl: Acl? = null,

    @XmlSerialName("principal-collection-set")
    var principalCollectionSet: PrincipalCollectionSet? = null,

    @XmlSerialName("principal-URL")
    var principalURL: PrincipalURL? = null,
)
