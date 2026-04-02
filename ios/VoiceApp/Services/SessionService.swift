import Foundation

/// Orchestrates backend token → local SDP offer → OpenAI SDP answer → remote description.
final class SessionService: SessionServiceProtocol {
    private let webRTC: WebRTCServiceProtocol
    private let urlSession: URLSession

    init(webRTC: WebRTCServiceProtocol, urlSession: URLSession = .shared) {
        self.webRTC = webRTC
        self.urlSession = urlSession
    }

    func start(with backend: BackendClient) async throws {
        try webRTC.reset()

        let sessionResponse = try await backend.createSession()
        try Self.assertTokenValid(sessionResponse)

        let offerSDP = try await webRTC.createOfferSDP()
        let answerSDP = try await postOfferToOpenAI(offerSDP: offerSDP, ephemeralToken: sessionResponse.clientSecret.value)
        try await webRTC.setRemoteAnswerSDP(answerSDP)
    }

    func stop() async {
        webRTC.close()
    }

    private static func assertTokenValid(_ response: SessionResponse) throws {
        let now = Int(Date().timeIntervalSince1970)
        // TODO: VERIFY — whether `expires_at` is always Unix seconds (vs ms) in current OpenAI API
        if now >= response.clientSecret.expiresAt {
            throw AppError.tokenExpired
        }
    }

    private func postOfferToOpenAI(offerSDP: String, ephemeralToken: String) async throws -> String {
        guard let url = OpenAIEndpoints.realtimeSDPURL() else {
            throw AppError.webRTCConnectionFailed(reason: "Invalid OpenAI realtime URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ephemeralToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(offerSDP.utf8)
        request.timeoutInterval = 55

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AppError.webRTCConnectionFailed(reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.webRTCConnectionFailed(reason: "Invalid OpenAI response.")
        }

        guard http.statusCode == 201 else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            Logger.error("OpenAI SDP exchange failed status=\(http.statusCode) bodyLen=\(data.count)")
            throw AppError.webRTCConnectionFailed(reason: "OpenAI returned HTTP \(http.statusCode). \(snippet.prefix(120))")
        }

        guard let answerText = String(data: data, encoding: .utf8), !answerText.isEmpty else {
            throw AppError.webRTCConnectionFailed(reason: "Empty SDP answer from OpenAI.")
        }
        return answerText
    }
}
