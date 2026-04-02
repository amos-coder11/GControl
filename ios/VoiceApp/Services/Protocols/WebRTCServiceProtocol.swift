import Combine
import Foundation
import WebRTC

/// WebRTC peer connection, local audio track, `oai-events` data channel, and SDP exchange hooks.
protocol WebRTCServiceProtocol: AnyObject {
    var connectionStatePublisher: PassthroughSubject<RTCIceConnectionState, Never> { get }
    var dataChannelMessagePublisher: PassthroughSubject<Data, Never> { get }

    /// Tears down any existing connection and prepares a fresh factory/PC for a new session.
    func reset() throws

    /// Builds peer connection, adds mic + `oai-events` data channel, creates and returns local SDP offer.
    func createOfferSDP() async throws -> String

    /// Applies the remote SDP answer from OpenAI.
    func setRemoteAnswerSDP(_ sdp: String) async throws

    /// Sends a JSON payload on the data channel (UTF-8 encoded).
    func sendDataChannelMessage(_ data: Data)

    /// Closes peer connection and data channel.
    func close()
}
