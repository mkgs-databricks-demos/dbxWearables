package com.dbxwearables.android.data.remote

sealed class APIError : Exception() {

    data class HttpError(val statusCode: Int) : APIError() {
        val isRetryable: Boolean
            get() = statusCode == 429 || statusCode in 500..599
    }

    data class NetworkError(override val cause: Throwable) : APIError()

    data class DecodingError(override val cause: Throwable) : APIError()
}
