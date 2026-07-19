package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "propstat", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Propstat(
    var prop: Prop? = null,
    var status: String? = null,
    var error: Error? = null,
    var responsedescription: String? = null,
)
