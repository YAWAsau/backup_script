package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "response", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Response(
    var href: List<String> = listOf(),
    var status: String? = null,
    var propstat: List<Propstat> = listOf(),
    var error: Error? = null,
    var responsedescription: String? = null,
    var location: Location? = null,
)
