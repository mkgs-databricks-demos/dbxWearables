import XCTest
@testable import dbxWearablesApp

// MARK: - Mock URL Protocol

/// Intercepts all URL requests made through the session, returning controlled responses.
private final class MockURLProtocol: URLProtocol {

    /// Set this before each test to control the response for intercepted requests.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class APIServiceTests: XCTestCase {

    private var sut: APIService!

    override func setUp() {
        super.setUp()

        // Provide the required environment variable so APIConfiguration.baseURL doesn't fatalError.
        setenv("DBX_API_BASE_URL", "https://test.databricks.com/apps/wearables", 1)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        sut = APIService(session: URLSession(configuration: config))
    }

    override func tearDown() {
        sut = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Success Response

    func testPostPayloadReturnsSuccessResponse() async throws {
        let json = #"{"status":"ok","message":"Ingested","record_id":"abc-123"}"#

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let result = try await sut.postRecords([makeSample()], recordType: "samples")

        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.message, "Ingested")
        XCTAssertEqual(result.recordId, "abc-123")
    }

    // MARK: - HTTP Errors

    func testPostPayloadThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await sut.postRecords([makeSample()], recordType: "samples")
            XCTFail("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(let statusCode) = error else {
                return XCTFail("Wrong APIError case")
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertTrue(error.isRetryable, "5xx errors should be retryable")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPostPayloadThrowsNonRetryableOn4xx() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await sut.postRecords([makeSample()], recordType: "samples")
            XCTFail("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(let statusCode) = error else {
                return XCTFail("Wrong APIError case")
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertFalse(error.isRetryable, "4xx errors (except 429) should not be retryable")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPostPayloadThrowsRetryableOn429() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await sut.postRecords([makeSample()], recordType: "samples")
            XCTFail("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(let statusCode) = error else {
                return XCTFail("Wrong APIError case")
            }
            XCTAssertEqual(statusCode, 429)
            XCTAssertTrue(error.isRetryable, "429 rate-limit errors should be retryable")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Request Headers

    func testPostPayloadIncludesExpectedHeaders() async throws {
        var capturedRequest: URLRequest?
        let json = #"{"status":"ok"}"#

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        _ = try await sut.postRecords([makeSample()], recordType: "samples")

        let headers = capturedRequest?.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["Content-Type"], "application/x-ndjson")
        XCTAssertEqual(headers["X-Record-Type"], "samples")
        XCTAssertEqual(headers["X-Platform"], "apple_healthkit")
        XCTAssertNotNil(headers["X-Device-Id"], "Should include device identifier")
        XCTAssertNotNil(headers["X-Upload-Timestamp"], "Should include upload timestamp")
        XCTAssertNotNil(headers["X-App-Version"], "Should include app version")
    }

    func testPostPayloadIncludesAuthorizationHeader() async throws {
        // Store a test token so APIService picks it up via KeychainHelper.
        KeychainHelper.saveAPIToken("test-token-abc")
        defer { KeychainHelper.saveAPIToken("") }

        var capturedRequest: URLRequest?
        let json = #"{"status":"ok"}"#

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        _ = try await sut.postRecords([makeSample()], recordType: "samples")

        let auth = capturedRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Bearer test-token-abc")
    }

    // MARK: - Request Structure

    func testPostPayloadSendsToCorrectEndpoint() async throws {
        var capturedRequest: URLRequest?
        let json = #"{"status":"ok"}"#

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        _ = try await sut.postRecords([makeSample()], recordType: "samples")

        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.url?.host, "test.databricks.com")
        XCTAssertEqual(capturedRequest?.url?.path, "/apps/wearables/api/v1/healthkit/ingest")
    }

    func testPostPayloadSendsNDJSONBody() async throws {
        var capturedBody: Data?
        let json = #"{"status":"ok"}"#

        MockURLProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let samples = [
            makeSample(uuid: "00000000-0001-0000-0000-000000000000"),
            makeSample(uuid: "00000000-0002-0000-0000-000000000000"),
        ]
        _ = try await sut.postRecords(samples, recordType: "samples")

        let bodyString = String(data: capturedBody ?? Data(), encoding: .utf8) ?? ""
        let lines = bodyString.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "NDJSON body should have one line per record")

        for line in lines {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: Data(line.utf8)),
                "Each NDJSON line should be valid JSON"
            )
        }
    }

    // MARK: - Helpers

    private func makeSample(uuid: String = "A1B2C3D4-0001-0000-0000-000000000000") -> HealthSample {
        HealthSample(
            uuid: uuid,
            type: "HKQuantityTypeIdentifierStepCount",
            value: 1000,
            unit: "count",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            sourceName: "Apple Watch",
            sourceBundleId: "com.apple.health",
            metadata: nil
        )
    }
}
