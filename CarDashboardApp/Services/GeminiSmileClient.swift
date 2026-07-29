import Foundation
import UIKit

/// Transformación de sonrisa: Gemini (imagen→imagen) con fallback a OpenAI Images Edit.
enum GeminiSmileClient {
    /// Token local de imágenes de dientes (DrFly) — preferido para sonrisa.
    private static var geminiImageAPIKey: String? {
        value(forInfoKey: "GEMINI_IMAGE_API_KEY")
    }

    /// Clave Gemini estándar (generativelanguage).
    private static var geminiAPIKey: String? {
        value(forInfoKey: "GEMINI_API_KEY")
    }

    /// Orden: token de dientes → clave estándar.
    private static var geminiAPIKeys: [String] {
        var keys: [String] = []
        if let image = geminiImageAPIKey { keys.append(image) }
        if let standard = geminiAPIKey, !keys.contains(standard) { keys.append(standard) }
        return keys
    }

    private static var openAIAPIKey: String? {
        value(forInfoKey: "OPENAI_API_KEY")
    }

    /// Modelos Gemini de imagen nativa. Se prueba en orden si el primero falla con 404.
    private static var preferredGeminiModels: [String] {
        var models: [String] = []
        if let configured = value(forInfoKey: "GEMINI_MODEL") {
            models.append(configured)
        }
        for candidate in [
            "gemini-3-pro-image",
            "gemini-3.1-flash-image",
            "gemini-2.5-flash-image",
            "gemini-3.1-flash-lite-image",
        ] where !models.contains(candidate) {
            models.append(candidate)
        }
        return models
    }

    static var isConfigured: Bool { !geminiAPIKeys.isEmpty || openAIAPIKey != nil }

    enum GeminiError: LocalizedError {
        case missingAPIKey
        case invalidImage
        case invalidResponse
        case httpStatus(Int, String?)
        case noImageInResponse(String?)
        case blocked(String?)
        case quotaExceeded(String?)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Falta GEMINI_API_KEY / GEMINI_IMAGE_API_KEY u OPENAI_API_KEY en DeveloperSettings.local.xcconfig."
            case .invalidImage:
                return "No se pudo leer la foto."
            case .invalidResponse:
                return "Respuesta inválida del servicio de imagen."
            case let .httpStatus(code, msg):
                if let msg, !msg.isEmpty { return "Error (\(code)): \(msg)" }
                return "Error del servicio (\(code))."
            case let .noImageInResponse(detail):
                if let detail, !detail.isEmpty {
                    return "No se generó imagen: \(detail)"
                }
                return "El servicio no devolvió imagen. Prueba otra foto."
            case let .blocked(reason):
                return reason ?? "La imagen no pudo procesarse por políticas de seguridad."
            case let .quotaExceeded(detail):
                if let detail, !detail.isEmpty { return detail }
                return "Cuota de Gemini agotada. Activa facturación en Google AI Studio o usa OPENAI_API_KEY."
            }
        }
    }

    enum SmileType: String, CaseIterable, Identifiable, Sendable {
        case auto
        case softDelicate
        case square
        case oval
        case triangular
        case rounded
        case hollywood

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: return "Según el rostro"
            case .softDelicate: return "Suave / delicada"
            case .square: return "Cuadrada"
            case .oval: return "Ovalada"
            case .triangular: return "Triangular"
            case .rounded: return "Redondeada"
            case .hollywood: return "Hollywood"
            }
        }

        var subtitle: String {
            switch self {
            case .auto: return "Forma según cara, edad y personalidad"
            case .softDelicate: return "Bordes fluidos, caninos suaves"
            case .square: return "Incisivos rectos, presencia fuerte"
            case .oval: return "Contornos suaves y equilibrados"
            case .triangular: return "Más estrecha hacia el borde"
            case .rounded: return "Bordes curvos, aspecto amable"
            case .hollywood: return "Más blanca y uniforme"
            }
        }

        var icon: String {
            switch self {
            case .auto: return "face.smiling"
            case .softDelicate: return "leaf.fill"
            case .square: return "square.fill"
            case .oval: return "oval.fill"
            case .triangular: return "triangle.fill"
            case .rounded: return "circle.fill"
            case .hollywood: return "star.fill"
            }
        }

        var promptDirective: String {
            switch self {
            case .auto:
                return """
                SMILE TYPE: AUTO (face-matched).
                Choose square, oval, triangular, or rounded tooth forms based on facial morphology, personality cues, apparent age, and aesthetic harmony — never by gender stereotypes.
                Prefer delicate incisal edges, fluid contours, and less prominent canines with an elegant progressive transition between teeth.
                """
            case .softDelicate:
                return """
                SMILE TYPE: SOFT / DELICATE.
                Create delicate incisal edges, fluid contours, and less prominent canines.
                Maintain a progressive elegant transition between all teeth. Soft, refined, natural presence.
                """
            case .square:
                return """
                SMILE TYPE: SQUARE.
                Emphasize more rectangular central incisors with flatter, decisive incisal edges and strong but natural presence.
                Keep canines less aggressive; preserve fluid transitions and realistic enamel anatomy.
                """
            case .oval:
                return """
                SMILE TYPE: OVAL.
                Use softly oval tooth outlines with gently curved incisal edges and balanced proportions.
                Elegant, harmonious, progressive transitions; canines softly rounded, not pointed.
                """
            case .triangular:
                return """
                SMILE TYPE: TRIANGULAR.
                Teeth slightly wider cervically and tapering toward a narrower, refined incisal edge.
                Keep contours fluid and elegant; avoid sharp aggressive points on canines.
                """
            case .rounded:
                return """
                SMILE TYPE: ROUNDED.
                Softly rounded incisal corners and gently curved contours for a warm, approachable smile.
                Progressive transitions between teeth; subdued canine prominence.
                """
            case .hollywood:
                return """
                SMILE TYPE: HOLLYWOOD.
                Brighter, more uniform aesthetic smile while remaining photorealistic.
                Still avoid plastic texture, neon blue-white, perfect symmetry, and identity change.
                Keep delicate anatomy and natural gingival integration.
                """
            }
        }
    }

    struct SmileDesignOptions: Sendable {
        /// Rehabilitación estética natural: blancura moderada + armonía + máxima naturalidad.
        var smileType: SmileType = .softDelicate
        var whitenLevel: Double = 0.72
        var alignmentLevel: Double = 0.78
        var naturalLook: Double = 0.94
        var notes: String = ""
    }

    static func transformSmile(
        image: UIImage,
        options: SmileDesignOptions = SmileDesignOptions()
    ) async throws -> UIImage {
        guard isConfigured else { throw GeminiError.missingAPIKey }
        let prepared = GrooImageProcessing.resize(image)
        guard let jpeg = GrooImageProcessing.jpegData(prepared) else {
            throw GeminiError.invalidImage
        }

        let prompt = buildPrompt(options: options)
        var lastError: Error?

        for geminiKey in geminiAPIKeys {
            do {
                let raw = try await transformWithGemini(jpeg: jpeg, prompt: prompt, apiKey: geminiKey)
                return GrooImageProcessing.stampAIPreviewDisclaimer(raw)
            } catch let error as GeminiError {
                lastError = error
                switch error {
                case .quotaExceeded, .httpStatus(429, _), .httpStatus(404, _), .httpStatus(403, _):
                    continue
                default:
                    if openAIAPIKey == nil && geminiKey == geminiAPIKeys.last {
                        throw error
                    }
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }

        if let openAIKey = openAIAPIKey {
            let raw = try await transformWithOpenAI(jpeg: jpeg, prompt: prompt, apiKey: openAIKey)
            return GrooImageProcessing.stampAIPreviewDisclaimer(raw)
        }

        throw lastError ?? GeminiError.missingAPIKey
    }

    // MARK: - Gemini

    private static func transformWithGemini(jpeg: Data, prompt: String, apiKey: String) async throws -> UIImage {
        let body = GeminiGenerateRequest(
            contents: [
                GeminiContent(
                    parts: [
                        GeminiPart(inlineData: GeminiInlineData(mimeType: "image/jpeg", data: jpeg.base64EncodedString())),
                        GeminiPart(text: prompt),
                    ]
                ),
            ],
            generationConfig: GeminiGenerationConfig(responseModalities: ["TEXT", "IMAGE"])
        )
        let bodyData = try JSONEncoder().encode(body)

        var lastError: Error?
        for model in preferredGeminiModels {
            do {
                return try await requestGeminiImage(model: model, apiKey: apiKey, bodyData: bodyData)
            } catch let error as GeminiError {
                lastError = error
                if case let .httpStatus(code, message) = error {
                    if code == 404 { continue }
                    if code == 429 || isQuotaMessage(message) {
                        throw GeminiError.quotaExceeded(friendlyQuotaMessage(message))
                    }
                }
                throw error
            }
        }
        throw lastError ?? GeminiError.invalidResponse
    }

    private static func requestGeminiImage(model: String, apiKey: String, bodyData: Data) async throws -> UIImage {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }

        if http.statusCode != 200 {
            let message = parseGeminiErrorMessage(from: data)
            if http.statusCode == 429 || isQuotaMessage(message) {
                throw GeminiError.quotaExceeded(friendlyQuotaMessage(message))
            }
            throw GeminiError.httpStatus(http.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        if let block = decoded.promptFeedback?.blockReason, !block.isEmpty {
            throw GeminiError.blocked(decoded.promptFeedback?.blockReasonMessage ?? block)
        }

        let candidate = decoded.candidates?.first
        if let finish = candidate?.finishReason?.uppercased(),
           ["SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "IMAGE_SAFETY"].contains(finish) {
            throw GeminiError.blocked(candidate?.finishMessage ?? "Bloqueado (\(finish)).")
        }

        guard let parts = candidate?.content?.parts, !parts.isEmpty else {
            throw GeminiError.noImageInResponse(candidate?.finishReason)
        }

        for part in parts {
            if let image = decodeBase64Image(part.inlineData?.data) {
                return image
            }
        }

        let textHint = parts.compactMap(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        throw GeminiError.noImageInResponse(textHint.isEmpty ? candidate?.finishReason : String(textHint.prefix(180)))
    }

    // MARK: - OpenAI fallback

    private static func transformWithOpenAI(jpeg: Data, prompt: String, apiKey: String) async throws -> UIImage {
        let boundary = "GrooBoundary\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", "gpt-image-1")
        appendField("prompt", prompt)
        // Alta fidelidad al retrato original: misma cara, pose, encuadre.
        appendField("input_fidelity", "high")
        appendField("quality", "high")
        appendField("size", "auto")
        appendField("output_format", "jpeg")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"smile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        if http.statusCode != 200 {
            throw GeminiError.httpStatus(http.statusCode, parseOpenAIErrorMessage(from: data))
        }

        let decoded = try JSONDecoder().decode(OpenAIImagesResponse.self, from: data)
        guard let b64 = decoded.data?.first?.b64Json,
              let image = decodeBase64Image(b64) else {
            throw GeminiError.noImageInResponse(nil)
        }
        return image
    }

    // MARK: - Prompt / helpers

    private static func buildPrompt(options: SmileDesignOptions) -> String {
        let whiten = Int(options.whitenLevel * 100)
        let align = Int(options.alignmentLevel * 100)
        let natural = Int(options.naturalLook * 100)
        var prompt = """
        You are editing THIS exact patient photograph for a dental smile preview.

        CRITICAL — FACE LOCK (highest priority):
        - Keep the EXACT same face. Same person, same identity. This is a photo edit, NOT a new AI portrait.
        - Do NOT redesign, beautify, slim, reshape, rejuvenate, or smooth the face.
        - LOCK unchanged: eyes, eyelids, eyebrows, nose, cheeks, jaw, chin, forehead, ears, hair, skin tone, pores, freckles, moles, wrinkles, makeup, facial fat, bone structure.
        - LOCK lips shape, lip volume, lip color, mouth opening amount, and smile width — only the teeth inside the mouth may change.
        - LOCK head pose, camera angle, crop/framing of the face, and expression.
        - If unsure, copy the face pixels from the input and only retouch the dental region + background.

        BACKGROUND ONLY (studio):
        - Replace ONLY the background behind the person with pure matte black (#000000), seamless studio backdrop.
        - Do NOT re-light or re-render the face when changing the background.
        - Keep the original facial lighting, shadows, and skin appearance as close as possible to the input.
        - Clean cutout of the same subject against black — no new face generation.

        TEETH ONLY:
        - Edit only the visible tooth crowns / enamel for the smile design.
        - Do not invent a different mouth or change gum position unless needed for natural tooth fit.

        Patient design intensity: whitening \(whiten)%, alignment harmony \(align)%, natural look \(natural)%.

        \(options.smileType.promptDirective)

        TOOTH SHAPE & ARCHITECTURE
        - Create delicate incisal edges, fluid contours, and less prominent canines unless the selected type requires stronger presence.
        - Maintain a progressive, elegant transition between all teeth.
        - Do NOT assign tooth shapes automatically by gender.
        - Honor the selected smile type above; only fall back to facial morphology when type is AUTO.

        AGE-APPROPRIATE NATURALNESS
        - Young patients: greater incisal translucency, subtly visible mamelons, richer surface texture, defined incisal edges.
        - Adult patients: moderated mamelons, softened texture, minimal credible incisal wear.
        - Older patients: slightly reduced translucency, warmer cervical shade, discreet physiological wear.
        - Avoid exaggerated rejuvenation incompatible with the face.

        GINGIVA & FACIAL INTEGRATION
        - Preserve or credibly improve gingival architecture without changing the face.
        - Harmonic gingival margins, complete papillae, natural contours.
        - Healthy realistic pink gingival texture — never artificial.
        - Avoid overly long teeth, identical margins, or unrealistic gingival display.

        FINAL RESULT
        Same face as the input photo, improved natural teeth, black studio background. Must look like a real photo edit of this person — not a generated lookalike.

        AVOID
        - Changing the face, eyes, nose, cheeks, jaw, skin, or lips
        - Beautification filters, face morphing, identity drift
        - Excessively large, white, or uniform teeth
        - Flat anatomy; perfect symmetry; plastic texture
        - Pointed canines; black triangles; artificial gums
        - Regenerating a new portrait instead of editing this one

        Return ONE photorealistic edit of THIS same person: original face preserved, teeth improved, pure black studio background.
        """
        let extra = options.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            prompt += "\n\nPatient aesthetic preferences (teeth only): \(extra)"
        }
        return prompt
    }

    private static func value(forInfoKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeBase64Image(_ raw: String?) -> UIImage? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private static func isQuotaMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("quota") || lower.contains("resource_exhausted") || lower.contains("rate limit")
    }

    private static func friendlyQuotaMessage(_ message: String?) -> String {
        "Cuota gratuita de Gemini Image agotada (limit 0). Activa facturación en https://aistudio.google.com o deja OPENAI_API_KEY para el fallback."
            + (message.flatMap { "\n\n\($0.prefix(160))" } ?? "")
    }

    private static func parseGeminiErrorMessage(from data: Data) -> String? {
        struct ErrBody: Decodable {
            struct Err: Decodable { let message: String? }
            let error: Err?
        }
        return (try? JSONDecoder().decode(ErrBody.self, from: data))?.error?.message
    }

    private static func parseOpenAIErrorMessage(from data: Data) -> String? {
        struct ErrBody: Decodable {
            struct Err: Decodable { let message: String? }
            let error: Err?
        }
        return (try? JSONDecoder().decode(ErrBody.self, from: data))?.error?.message
    }

    // MARK: - Gemini DTOs

    private struct GeminiGenerateRequest: Encodable {
        let contents: [GeminiContent]
        let generationConfig: GeminiGenerationConfig
    }

    private struct GeminiContent: Encodable {
        let parts: [GeminiPart]
    }

    private struct GeminiPart: Encodable {
        var text: String?
        var inlineData: GeminiInlineData?

        init(text: String) {
            self.text = text
        }

        init(inlineData: GeminiInlineData) {
            self.inlineData = inlineData
        }

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(inlineData, forKey: .inlineData)
        }
    }

    private struct GeminiInlineData: Encodable {
        let mimeType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }
    }

    private struct GeminiGenerationConfig: Encodable {
        let responseModalities: [String]
    }

    private struct GeminiGenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                let parts: [GeminiResponsePart]?
            }
            let content: Content?
            let finishReason: String?
            let finishMessage: String?
        }

        struct PromptFeedback: Decodable {
            let blockReason: String?
            let blockReasonMessage: String?
        }

        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private struct GeminiResponsePart: Decodable {
        struct InlineData: Decodable {
            let mimeType: String?
            let data: String

            enum CodingKeys: String, CodingKey {
                case mimeType
                case mime_type
                case data
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
                    ?? c.decodeIfPresent(String.self, forKey: .mime_type)
                data = try c.decode(String.self, forKey: .data)
            }
        }

        let text: String?
        let inlineData: InlineData?

        enum CodingKeys: String, CodingKey {
            case text
            case inlineData
            case inline_data
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decodeIfPresent(String.self, forKey: .text)
            inlineData = try c.decodeIfPresent(InlineData.self, forKey: .inlineData)
                ?? c.decodeIfPresent(InlineData.self, forKey: .inline_data)
        }
    }

    // MARK: - OpenAI DTOs

    private struct OpenAIImagesResponse: Decodable {
        struct Item: Decodable {
            let b64Json: String?

            enum CodingKeys: String, CodingKey {
                case b64Json = "b64_json"
            }
        }

        let data: [Item]?
    }
}
