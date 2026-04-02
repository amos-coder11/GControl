import Combine
import Foundation
import WebRTC

/// WebRTC peer connection to OpenAI Realtime: mic track + `oai-events` data channel.
final class WebRTCService: NSObject, WebRTCServiceProtocol, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    let connectionStatePublisher = PassthroughSubject<RTCIceConnectionState, Never>()
    let dataChannelMessagePublisher = PassthroughSubject<Data, Never>()

    private static let sslLock = NSLock()
    private static var didInitializeSSL = false

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?

    override init() {
        super.init()
        Self.ensureSSLInitialized()
    }

    private static func ensureSSLInitialized() {
        sslLock.lock()
        defer { sslLock.unlock() }
        if !didInitializeSSL {
            RTCInitializeSSL()
            didInitializeSSL = true
        }
    }

    func reset() throws {
        close()
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let factory = RTCPeerConnectionFactory()
        self.factory = factory

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw AppError.webRTCConnectionFailed(reason: "Could not create RTCPeerConnection.")
        }
        peerConnection = pc

        let audioSource = factory.audioSource(with: constraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        pc.add(audioTrack, streamIds: ["stream0"])

        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        guard let dc = pc.dataChannel(forLabel: "oai-events", configuration: dcConfig) else {
            throw AppError.webRTCConnectionFailed(reason: "Could not create oai-events data channel.")
        }
        dc.delegate = self
        dataChannel = dc
    }

    func createOfferSDP() async throws -> String {
        guard let peerConnection else {
            throw AppError.webRTCConnectionFailed(reason: "Peer connection not initialized. Call reset() first.")
        }

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false",
            ],
            optionalConstraints: nil
        )

        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: offerConstraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: AppError.webRTCConnectionFailed(reason: error.localizedDescription))
                    return
                }
                guard let sdp else {
                    continuation.resume(throwing: AppError.webRTCConnectionFailed(reason: "Missing SDP offer."))
                    return
                }
                continuation.resume(returning: sdp)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(offer) { error in
                if let error {
                    continuation.resume(throwing: AppError.webRTCConnectionFailed(reason: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        // TODO: VERIFY — behavior not confirmed in official OpenAI or stasel/WebRTC docs
        // Whether we must wait for ICE gathering to complete before POSTing SDP, or if
        // `continualGathering` + immediate SDP is sufficient for OpenAI's edge.
        try? await Task.sleep(nanoseconds: 400_000_000)

        guard let local = peerConnection.localDescription else {
            throw AppError.webRTCConnectionFailed(reason: "Missing localDescription after offer.")
        }
        return local.sdp
    }

    func setRemoteAnswerSDP(_ sdp: String) async throws {
        guard let peerConnection else {
            throw AppError.webRTCConnectionFailed(reason: "No peer connection for remote answer.")
        }
        let answer = RTCSessionDescription(type: .answer, sdp: sdp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(answer) { error in
                if let error {
                    continuation.resume(throwing: AppError.webRTCConnectionFailed(reason: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func sendDataChannelMessage(_ data: Data) {
        guard let dataChannel else {
            Logger.error("sendDataChannelMessage: no data channel")
            return
        }
        guard dataChannel.readyState == .open else {
            Logger.error("sendDataChannelMessage: channel not open (state=\(dataChannel.readyState.rawValue))")
            return
        }
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dataChannel.sendData(buffer)
    }

    func close() {
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        factory = nil
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("signalingState=\(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Logger.debug("didAdd stream id=\(stream.streamId)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.debug("peerConnectionShouldNegotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        connectionStatePublisher.send(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.debug("iceGatheringState=\(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Logger.debug("ICE candidate generated")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Logger.debug("Remote opened data channel \(dataChannel.label)")
    }

    // MARK: - RTCDataChannelDelegate

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Logger.debug("dataChannel state=\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        dataChannelMessagePublisher.send(buffer.data)
    }
}
