package com.dbxwearables.android.data.remote

import com.dbxwearables.android.BuildConfig

object APIConfiguration {

    val baseURL: String
        get() {
            val url = BuildConfig.DBX_API_BASE_URL
            require(url.isNotEmpty()) { "DBX_API_BASE_URL must be set in gradle.properties" }
            return url.trimEnd('/')
        }

    const val INGEST_PATH = "/api/v1/healthconnect/ingest"
    const val TIMEOUT_SECONDS = 30L
    const val MAX_RETRIES = 3
}
