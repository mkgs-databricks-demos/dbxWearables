package com.dbxwearables.android.data.remote

import com.dbxwearables.android.util.DeviceIdentifier
import com.dbxwearables.android.util.SecureStorage
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class APIServiceTest {

    private lateinit var server: MockWebServer
    private lateinit var sut: APIService

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.start()

        val secureStorage = mockk<SecureStorage>()
        every { secureStorage.getApiToken() } returns null

        val deviceIdentifier = mockk<DeviceIdentifier>()
        every { deviceIdentifier.deviceId } returns "test-device-id"

        val client = OkHttpClient.Builder().build()
        sut = APIService(client, secureStorage, deviceIdentifier)
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `postRecords returns success response`() = runTest {
        server.enqueue(MockResponse()
            .setBody("""{"status":"ok","message":"Ingested","record_id":"abc-123"}""")
            .setResponseCode(200))

        val ndjson = """{"id":"test","type":"StepsRecord","value":100}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()
        val result = sut.postRecordsToUrl(ndjson, "samples", url)

        assertEquals("ok", result.status)
        assertEquals("Ingested", result.message)
        assertEquals("abc-123", result.recordId)
    }

    @Test
    fun `postRecords throws HttpError on 500`() = runTest {
        server.enqueue(MockResponse().setResponseCode(500))

        val ndjson = """{"id":"test","type":"StepsRecord","value":100}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()

        val error = assertThrows<APIError.HttpError> {
            sut.postRecordsToUrl(ndjson, "samples", url)
        }
        assertEquals(500, error.statusCode)
        assertTrue(error.isRetryable, "5xx errors should be retryable")
    }

    @Test
    fun `postRecords throws non-retryable on 400`() = runTest {
        server.enqueue(MockResponse().setResponseCode(400))

        val ndjson = """{"id":"test","type":"StepsRecord","value":100}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()

        val error = assertThrows<APIError.HttpError> {
            sut.postRecordsToUrl(ndjson, "samples", url)
        }
        assertEquals(400, error.statusCode)
        assertFalse(error.isRetryable, "4xx errors should not be retryable")
    }

    @Test
    fun `postRecords throws retryable on 429`() = runTest {
        server.enqueue(MockResponse().setResponseCode(429))

        val ndjson = """{"id":"test","type":"StepsRecord","value":100}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()

        val error = assertThrows<APIError.HttpError> {
            sut.postRecordsToUrl(ndjson, "samples", url)
        }
        assertEquals(429, error.statusCode)
        assertTrue(error.isRetryable, "429 should be retryable")
    }

    @Test
    fun `request includes expected headers`() = runTest {
        server.enqueue(MockResponse()
            .setBody("""{"status":"ok"}""")
            .setResponseCode(200))

        val ndjson = """{"id":"test","type":"StepsRecord","value":100}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()
        sut.postRecordsToUrl(ndjson, "samples", url)

        val request = server.takeRequest()
        assertEquals("application/x-ndjson", request.getHeader("Content-Type"))
        assertEquals("samples", request.getHeader("X-Record-Type"))
        assertEquals("android_health_connect", request.getHeader("X-Platform"))
        assertNotNull(request.getHeader("X-Device-Id"))
        assertNotNull(request.getHeader("X-Upload-Timestamp"))
    }

    @Test
    fun `request sends NDJSON body`() = runTest {
        server.enqueue(MockResponse()
            .setBody("""{"status":"ok"}""")
            .setResponseCode(200))

        val ndjson = """{"id":"001","type":"StepsRecord","value":100}
{"id":"002","type":"StepsRecord","value":200}"""
        val url = server.url("/api/v1/healthconnect/ingest").toString()
        sut.postRecordsToUrl(ndjson, "samples", url)

        val request = server.takeRequest()
        val body = request.body.readUtf8()
        val lines = body.split("\n").filter { it.isNotBlank() }
        assertEquals(2, lines.size, "NDJSON body should have 2 lines")
    }

    @Test
    fun `buildRequestHeaders includes correct platform`() {
        val headers = sut.buildRequestHeaders("samples")
        assertEquals("android_health_connect", headers["X-Platform"])
        assertEquals("samples", headers["X-Record-Type"])
        assertEquals("application/x-ndjson", headers["Content-Type"])
    }
}
