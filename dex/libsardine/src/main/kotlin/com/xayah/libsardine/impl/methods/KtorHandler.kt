package com.xayah.libsardine.impl.methods

import android.util.Log
import com.xayah.libsardine.DavResource
import com.xayah.libsardine.model.Multistatus
import com.xayah.libsardine.util.KotlinSardineUtil
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import java.net.URISyntaxException

object KtorHandler {
    private const val TAG = "KtorHandler"

    suspend fun multiStatus(httpResponse: HttpResponse): Multistatus {
        return KotlinSardineUtil.unmarshal(
            httpResponse.bodyAsText(),
            Multistatus.serializer(),
        )
    }

    fun responses(multistatus: Multistatus): List<DavResource> {
        val responses = multistatus.response
        val resources: MutableList<DavResource> = ArrayList(responses.size)
        for (response in responses) {
            try {
                resources.add(DavResource(response))
            } catch (e: URISyntaxException) {
                Log.w(TAG, "Ignore resource with invalid URI ${response.href}")
            }
        }
        return resources
    }
}
