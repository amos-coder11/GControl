import Foundation

/// Fetches ephemeral Realtime session JSON from your backend (`POST /session`).
final class BackendClient {
    private let session: URLSession
    private let baseURL: URL

    /// - Parameters:
    ///   - session: Injectable for tests (`URLSession` with `URLProtocol` mocks).
    ///   - baseURL: Backend root (e.g. `http://127.0.0.1:3000`).
    init(session: URLSession, baseURL: URL) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Calls `POST /session` and decodes `SessionResponse`. Retries once after 2s on `URLError`.
    func createSession() async throws -> SessionResponse {
        let request = try Self.buildRequest(baseURL: baseURL)
        do {
            return try await execute(request: request)
        } catch let urlError as URLError {
            Logger.info("createSession: retrying after URLError code=\(urlError.code.rawValue)")
            try await Task.sleep(nanoseconds: BackendConstants.retryDelayNanoseconds)
            do {
                return try await execute(request: request)
            } catch let second as URLError {
                Logger.error("createSession: second URLError code=\(second.code.rawValue)")
                throw AppError.backendUnreachable
            } catch {
                throw error
            }
        }
    }

    private static func buildRequest(baseURL: URL) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(BackendPaths.session, isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = BackendConstants.requestTimeoutSeconds
        return request
    }

    private func execute(request: URLRequest) async throws -> SessionResponse {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw urlError
        } catch {
            throw AppError.sessionTokenFetchFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.sessionTokenFetchFailed(underlying: URLError(.badServerResponse))
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let err = NSError(
                domain: "BackendClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
            throw AppError.sessionTokenFetchFailed(underlying: err)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(SessionResponse.self, from: data)
        } catch {
            throw AppError.sessionTokenFetchFailed(underlying: error)
        }
    }
}

private enum BackendPaths {
    static let session = "session"
}

private enum BackendConstants {
    static let requestTimeoutSeconds: TimeInterval = 10
    static let retryDelayNanoseconds: UInt64 = 2_000_000_000
}
