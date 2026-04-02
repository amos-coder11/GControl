import Foundation

/// Coordinates backend session token, SDP offer/answer with OpenAI, and WebRTC setup.
protocol SessionServiceProtocol: AnyObject {
    /// Runs token fetch → offer → OpenAI SDP answer → set remote description.
    func start(with backend: BackendClient) async throws

    /// Stops WebRTC (audio track teardown is handled separately by `AudioService` if needed).
    func stop() async
}
