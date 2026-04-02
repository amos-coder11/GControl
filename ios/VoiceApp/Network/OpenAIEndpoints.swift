import Foundation

/// OpenAI HTTP endpoints used by the Realtime WebRTC client (no API key in app).
enum OpenAIEndpoints {
    static let realtimeSDPQueryModel = "gpt-4o-realtime-preview"

    static func realtimeSDPURL() -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "api.openai.com"
        c.path = "/v1/realtime"
        c.queryItems = [URLQueryItem(name: "model", value: realtimeSDPQueryModel)]
        return c.url
    }
}
