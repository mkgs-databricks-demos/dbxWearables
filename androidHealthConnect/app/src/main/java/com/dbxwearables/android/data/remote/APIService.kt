package com.dbxwearables.android.data.remote

import com.dbxwearables.android.BuildConfig
import com.dbxwearables.android.data.model.APIResponse
import com.dbxwearables.android.util.DeviceIdentifier
import com.dbxwearables.android.util.SecureStorage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class APIService @Inject constructor(
    private val client: OkHttpClient,
    private val secureStorage: SecureStorage,
    private val deviceIdentifier: DeviceIdentifier
) {

    companion object {
        private val NDJSON_MEDIA_TYPE = "application/x-ndjson".toMediaType()
    }

    private val json = Json { ignoreUnknownKeys = true }

    fun buildRequestHeaders(recordType: String): Map<String, String> {
        val headers = mutableMapOf(
            "Content-Type" to "application/x-ndjson",
            "X-Device-Id" to deviceIdentifier.deviceId,
            "X-Platform" to "android_health_connect",
            "X-App-Version" to BuildConfig.VERSION_NAME,
            "X-Upload-Timestamp" to Instant.now().toString(),
            "X-Record-Type" to recordType
        )

        secureStorage.getApiToken()?.let { token ->
            headers["Authorization"] = "Bearer $token"
        }

        return headers
    }

    suspend fun postRecords(ndjsonBody: String, recordType: String): APIResponse {
        val url = "${APIConfiguration.baseURL}${APIConfiguration.INGEST_PATH}"
        return postRecordsToUrl(ndjsonBody, recordType, url)
    }

    suspend fun postRecordsToUrl(ndjsonBody: String, recordType: String, url: String): APIResponse =
        withContext(Dispatchers.IO) {
            val headers = buildRequestHeaders(recordType)

            val requestBody = ndjsonBody.toRequestBody(NDJSON_MEDIA_TYPE)

            val requestBuilder = Request.Builder()
                .url(url)
                .post(requestBody)

            headers.forEach { (key, value) ->
                requestBuilder.addHeader(key, value)
            }

            val request = requestBuilder.build()

            try {
                val response = client.newCall(request).execute()

                response.use { resp ->
                    if (resp.isSuccessful) {
                        val body = resp.body?.string()
                            ?: throw APIError.DecodingError(
                                IllegalStateException("Empty response body")
                            )
                        try {
                            json.decodeFromString<APIResponse>(body)
                        } catch (e: Exception) {
                            throw APIError.DecodingError(e)
                        }
                    } else {
                        throw APIError.HttpError(resp.code)
                    }
                }
            } catch (e: APIError) {
                throw e
            } catch (e: IOException) {
                throw APIError.NetworkError(e)
            }
        }
}
