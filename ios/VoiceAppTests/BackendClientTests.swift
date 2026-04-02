import XCTest
@testable import VoiceApp

final class BackendClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.handler = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }

    func testCreateSessionDecodesSuccess() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)

        let json = """
        {"id":"sess_1","client_secret":{"value":"ek_test_token","expires_at":9999999999}}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("/session") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = URL(string: "http://127.0.0.1:3000")!
        let client = BackendClient(session: session, baseURL: base)

        let result = try await client.createSession()
        XCTAssertEqual(result.id, "sess_1")
        XCTAssertEqual(result.clientSecret.value, "ek_test_token")
        XCTAssertEqual(result.clientSecret.expiresAt, 9_999_999_999)
    }

    func testCreateSessionMapsHTTPErrorToSessionTokenFetchFailed() async {
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = URL(string: "http://127.0.0.1:3000")!
        let client = BackendClient(session: session, baseURL: base)

        do {
            _ = try await client.createSession()
            XCTFail("Expected error")
        } catch let error as AppError {
            if case .sessionTokenFetchFailed = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Wrong error: \(error)")
            }
        } catch {
            XCTFail("Wrong error type")
        }
    }
}

// MARK: - Mock URL protocol

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocolDidFinishLoading(self)
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
