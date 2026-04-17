package com.dbxwearables.android.data.remote

import com.dbxwearables.android.data.model.APIResponse

class MockAPIService {
    val recordedCalls = mutableListOf<Pair<String, Int>>()

    suspend fun postRecords(ndjsonBody: String, recordType: String): APIResponse {
        val lineCount = ndjsonBody.split("\n").filter { it.isNotBlank() }.size
        recordedCalls.add(recordType to lineCount)
        return APIResponse(status = "ok", message = "Ingested", recordId = "mock-${recordedCalls.size}")
    }
}
