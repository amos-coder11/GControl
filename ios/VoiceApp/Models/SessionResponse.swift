import Foundation

/// Decodable subset of OpenAI `POST /v1/realtime/sessions` JSON used by the client.
struct SessionResponse: Codable, Sendable {
    let id: String
    let clientSecret: ClientSecret

    struct ClientSecret: Codable, Sendable {
        let value: String
        let expiresAt: Int

        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clientSecret = "client_secret"
    }
}
