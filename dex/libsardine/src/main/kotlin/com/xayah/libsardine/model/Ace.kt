package com.xayah.libsardine.model

import com.xayah.libsardine.util.KotlinSardineUtil
import kotlinx.serialization.Serializable
import nl.adaptivity.xmlutil.serialization.XmlSerialName

@Serializable
@XmlSerialName(value = "ace", namespace = KotlinSardineUtil.DEFAULT_NAMESPACE_URI, prefix = KotlinSardineUtil.DEFAULT_NAMESPACE_PREFIX)
data class Ace(
    var principal: Principal? = null,
    var grant: Grant? = null,
    var deny: Deny? = null,
    var inherited: Inherited? = null,

    @XmlSerialName("protected")
    var protected1: Protected? = null,
)
