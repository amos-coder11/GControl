import Foundation

/// Actor-backed transcript buffer (serializes concurrent updates from the data channel).
actor TranscriptStore {
    private var content: String = ""

    /// Appends text and returns the full transcript.
    func append(_ chunk: String) -> String {
        content += chunk
        return content
    }

    func reset() {
        content = ""
    }
}
