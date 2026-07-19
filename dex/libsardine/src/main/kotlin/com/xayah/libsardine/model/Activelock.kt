package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "activelock", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Activelock(
    var lockscope: Lockscope? = null,
    var locktype: Locktype? = null,
    var depth: String? = null,
    var owner: Owner? = null,
    var timeout: String? = null,
    var locktoken: Locktoken? = null,
)
