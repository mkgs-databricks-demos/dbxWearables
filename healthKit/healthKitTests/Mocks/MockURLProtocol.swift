import Foundation

/// URLProtocol subclass that intercepts requests routed through a test URLSession
/// and returns controlled responses. Shared across APIService and AuthService tests.
final class MockURLProtocol: URLProtocol {

    /// Set this before each test to control the response for intercepted requests.
    /// Returning `(HTTPURLResponse, Data)` simulates a normal completion;
    /// throwing simulates a transport failure.
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
