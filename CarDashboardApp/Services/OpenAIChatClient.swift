import Foundation

// MARK: - OpenAI (pestaña IA · Chat Completions)

/// Chat Viera vía OpenAI. Claves: `OPENAI_API_KEY`, opcional `OPENAI_MODEL` en Info (xcconfig).
enum OpenAIChatClient {
    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static var openAIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static var openAIModel: String {
        if let m = Bundle.main.object(forInfoDictionaryKey: "OPENAI_MODEL") as? String {
            let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "gpt-4o-mini"
    }

    static var isConfigured: Bool { openAIKey != nil }

    enum OpenAIError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int, String?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OPENAI_API_KEY is missing. Set it in DeveloperSettings.local.xcconfig."
            case .invalidResponse:
                return "Invalid server response."
            case let .httpStatus(code, msg):
                if let msg, !msg.isEmpty { return "Error \(code): \(msg)" }
                return "Service error (\(code))."
            case .decodingFailed:
                return "Could not read the OpenAI response."
            }
        }
    }

    private struct OpenAIChatMessageDTO: Encodable {
        let role: String
        let content: String
    }

    private struct OpenAINonStreamRequestBody: Encodable {
        let model: String
        let messages: [OpenAIChatMessageDTO]
    }

    private struct OpenAIStreamRequestBody: Encodable {
        let model: String
        let messages: [OpenAIChatMessageDTO]
        let stream: Bool
    }

    private struct OpenAIStreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]?
    }

    private struct OpenAIStreamErrorEnvelope: Decodable {
        struct Err: Decodable {
            let message: String?
        }

        let error: Err?
    }

    private static let vieraSystemPrompt = """
    You are Groo's AI assistant, a career mentorship platform. \
    You speak in English with a clear, professional, and approachable tone: fluent, direct, and pleasant to read.

    OUTPUT FORMAT (required): the app displays plain text without a Markdown engine. \
    NEVER use Markdown syntax or characters the interface won't interpret: \
    no asterisks for bold or italic (** * __ _), no hash headings (#), no dense dash-list blocks like "- item", \
    no tables, no fenced code blocks. If you want to emphasize something, do it through wording (word order, a short opening sentence), not symbols.

    Prioritize continuous paragraphs with good rhythm; separate ideas with a blank line between paragraphs. \
    Avoid long numbered lists unless the user explicitly asks for one; \
    even then, keep each item to one or two simple sentences without asterisk labels. \
    When the user asks for "point by point", respond clearly but without a technical-document feel: complete sentences, natural tone.

    You can help with: professional clarity, career goals, preparing for difficult conversations, goal tracking, and team coordination. \
    You do not offer therapy, psychological diagnosis, or medical advice; for mental health concerns, recommend qualified professional help.

    Use emojis very sparingly (at most one every few sentences); never replace key information with icons only.
    """

    /// Si el bloque de datos de la app va vacío, no añadimos esta parte (el modelo no tendría UUID reales).
    private static let vieraStructuredCardsInstruction = """
    Cuando el usuario pida enviar una tarea al equipo, asignar compañeros o avisar a alguien del directorio, \
    al terminar tu respuesta en texto plano para el usuario añade ÚNICAMENTE al final (sin texto después) este bloque:

    <<<VIERA_CARDS
    {"team":["uuid-en-minúsculas",...]}
    >>>

    Reglas: "team" es un array opcional de strings UUID exactamente como en la lista de referencia (minúsculas). \
    Omite la clave si no aplica. Si no corresponde mostrar fichas, no escribas el bloque. No expliques el bloque al usuario.

    Si el usuario quiere que un compañero gestione algo, incluye en "team" el UUID del compañero sugerido o el que el usuario nombre del listado EQUIPO. \
    Si nombra a una persona concreta del listado EQUIPO, incluye solo su user_id en "team". \
    Si habla de «todo el equipo» o similar, puedes omitir "team" o listar varios: la app mostrará a todo el equipo.
    """

    private struct OpenAIChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable {
                let content: String?
            }

            let message: Msg?
        }

        let choices: [Choice]?
    }

    private struct OpenAIAPIErrorEnvelope: Decodable {
        struct APIErr: Decodable {
            let message: String?
        }

        let error: APIErr?
    }

    private static func openAIMessages(
        for conversation: [(isUser: Bool, text: String)],
        dataContextSupplement: String?
    ) -> [OpenAIChatMessageDTO] {
        var systemContent = vieraSystemPrompt
        if let raw = dataContextSupplement?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            systemContent += """

            ---
            \(raw)

            \(vieraStructuredCardsInstruction)
            """
        }
        var messages: [OpenAIChatMessageDTO] = [
            OpenAIChatMessageDTO(role: "system", content: systemContent),
        ]
        for turn in conversation {
            messages.append(
                OpenAIChatMessageDTO(role: turn.isUser ? "user" : "assistant", content: turn.text)
            )
        }
        return messages
    }

    /// Respuesta en streaming (SSE). `onChunk` se llama por cada trozo de texto en el orden correcto.
    /// `dataContextSupplement`: listado equipo; si es nil o vacío, no se pide el bloque de tarjetas.
    static func streamVieraChatReply(
        conversation: [(isUser: Bool, text: String)],
        dataContextSupplement: String?,
        onChunk: @escaping (String) async -> Void
    ) async throws {
        guard let key = openAIKey else { throw OpenAIError.missingAPIKey }

        let messages = openAIMessages(for: conversation, dataContextSupplement: dataContextSupplement)
        let body = OpenAIStreamRequestBody(model: openAIModel, messages: messages, stream: true)
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        if !(200 ... 299).contains(http.statusCode) {
            var err = Data()
            err.reserveCapacity(4096)
            for try await b in bytes {
                err.append(b)
                if err.count >= 8192 { break }
            }
            let snippet = String(data: err, encoding: .utf8)
            if let d = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: err),
               let m = d.error?.message, !m.isEmpty {
                throw OpenAIError.httpStatus(http.statusCode, m)
            }
            throw OpenAIError.httpStatus(http.statusCode, snippet)
        }

        try await readOpenAISSEStream(bytes) { piece in
            await onChunk(piece)
        }
    }

    private static func readOpenAISSEStream(
        _ bytes: URLSession.AsyncBytes,
        onDelta: @escaping (String) async -> Void
    ) async throws {
        var lineBytes: [UInt8] = []
        lineBytes.reserveCapacity(256)

        for try await byte in bytes {
            if byte == 10 {
                guard !lineBytes.isEmpty else { continue }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)

                guard line.hasPrefix("data:") else { continue }
                let rest = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if rest == "[DONE]" { return }
                guard let data = rest.data(using: .utf8) else { continue }

                if let env = try? JSONDecoder().decode(OpenAIStreamErrorEnvelope.self, from: data),
                   let msg = env.error?.message, !msg.isEmpty {
                    throw OpenAIError.httpStatus(0, msg)
                }

                guard let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                      let piece = chunk.choices?.first?.delta?.content,
                      !piece.isEmpty
                else { continue }

                await onDelta(piece)
            } else if byte != 13 {
                lineBytes.append(byte)
            }
        }
    }

    static func vieraChatReply(conversation: [(isUser: Bool, text: String)]) async throws -> String {
        guard let key = openAIKey else { throw OpenAIError.missingAPIKey }

        let messages = openAIMessages(for: conversation, dataContextSupplement: nil)
        let body = OpenAINonStreamRequestBody(model: openAIModel, messages: messages)
        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        guard (200 ... 299).contains(http.statusCode) else {
            if let env = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data),
               let m = env.error?.message, !m.isEmpty {
                throw OpenAIError.httpStatus(http.statusCode, m)
            }
            let snippet = String(data: data, encoding: .utf8)
            throw OpenAIError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        let text = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if text.isEmpty { throw OpenAIError.decodingFailed }
        return text
    }
}
