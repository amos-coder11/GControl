import Foundation

/// Parses JSON events from the `oai-events` WebRTC data channel (minimal fields used by the UI).
enum RealtimeEventParser {
    /// Known `type` strings we handle; others are ignored for UI purposes.
    enum EventType: String {
        case sessionCreated = "session.created"
        case sessionUpdated = "session.updated"
        case responseAudioTranscriptDelta = "response.audio_transcript.delta"
        // TODO: VERIFY — behavior not confirmed in official OpenAI or stasel/WebRTC docs
        case responseOutputAudioDelta = "response.output_audio.delta"
        case responseAudioDelta = "response.audio.delta"
        case responseDone = "response.done"
        case error = "error"
    }

    struct Parsed: Sendable {
        let type: EventType?
        let transcriptDelta: String?
        let modelSpeakingHint: Bool?
    }

    /// Extracts UI-relevant fields from raw JSON (schema varies by event).
    static func parse(data: Data) -> Parsed {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = obj["type"] as? String
        else {
            return Parsed(type: nil, transcriptDelta: nil, modelSpeakingHint: nil)
        }

        let type = EventType(rawValue: typeStr)

        var delta: String?
        if let d = obj["delta"] as? String {
            delta = d
        }

        var speaking: Bool?
        switch type {
        case .responseOutputAudioDelta, .responseAudioDelta:
            // TODO: VERIFY — exact payload for audio delta events in WebRTC mode
            speaking = true
        case .responseDone:
            speaking = false
        default:
            break
        }

        return Parsed(type: type, transcriptDelta: delta, modelSpeakingHint: speaking)
    }
}
