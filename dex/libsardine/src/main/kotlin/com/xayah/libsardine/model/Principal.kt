package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "principal", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Principal(
    var href: String? = null,
    var property: Property? = null,
    var all: All? = null,
    var authenticated: Authenticated? = null,
    var unauthenticated: Unauthenticated? = null,
    var self: Self? = null,
)
