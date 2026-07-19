package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "locktoken", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Locktoken(
    var href: List<String> = listOf(),
)
